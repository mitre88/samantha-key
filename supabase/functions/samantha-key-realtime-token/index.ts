import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

type EntitlementPayload = {
  productID: string;
  originalTransactionID: string;
  transactionID: string;
  signedTransactionInfo: string;
};

type RequestBody = {
  entitlement?: EntitlementPayload;
  outputLanguage?: string;
  outputLanguageCode?: string;
};

const PRODUCT_ID = "samantha_key_monthly";
const MAX_TOKEN_REQUESTS_PER_DAY = Number(Deno.env.get("MAX_TOKEN_REQUESTS_PER_DAY") ?? "240");
const CLIENT_SECRET_TTL_SECONDS = Number(Deno.env.get("OPENAI_CLIENT_SECRET_TTL_SECONDS") ?? "120");

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  const openAIKey = Deno.env.get("OPENAI_API_KEY");
  if (!openAIKey) return jsonResponse({ error: "missing_openai_secret" }, 500);

  const body = await request.json().catch(() => ({})) as RequestBody;
  const entitlement = body.entitlement;
  if (!entitlement?.signedTransactionInfo || entitlement.productID !== PRODUCT_ID) {
    return jsonResponse({ error: "missing_or_invalid_entitlement" }, 403);
  }

  const transaction = decodeJWSPayload(entitlement.signedTransactionInfo);
  if (!transaction || transaction.productId !== PRODUCT_ID) {
    return jsonResponse({ error: "invalid_transaction_payload" }, 403);
  }

  const expiresDate = Number(transaction.expiresDate ?? 0);
  const isActive = expiresDate > Date.now() && !transaction.revocationDate;
  if (!isActive) return jsonResponse({ error: "subscription_inactive" }, 403);

  const supabase = createServiceClient();
  const originalTransactionId = String(transaction.originalTransactionId ?? entitlement.originalTransactionID);
  const allowed = await recordAndCheckUsage(supabase, {
    originalTransactionId,
    transactionId: String(transaction.transactionId ?? entitlement.transactionID),
    productId: PRODUCT_ID,
    expiresAt: new Date(expiresDate).toISOString(),
    environment: transaction.environment ?? "unknown",
  });
  if (!allowed) return jsonResponse({ error: "daily_usage_limit_exceeded" }, 429);

  const outputLanguage = body.outputLanguage || "English";
  const outputLanguageCode = body.outputLanguageCode || "en";
  const model = Deno.env.get("OPENAI_REALTIME_TRANSLATE_MODEL") ?? "gpt-realtime-translate";
  const tokenResponse = await fetch("https://api.openai.com/v1/realtime/translations/client_secrets", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      expires_after: {
        anchor: "created_at",
        seconds: CLIENT_SECRET_TTL_SECONDS,
      },
      session: {
        model,
        audio: {
          output: {
            language: outputLanguageCode,
          },
        },
      },
    }),
  });

  const data = await tokenResponse.json();
  if (!tokenResponse.ok) return jsonResponse({ error: "openai_token_failed", detail: data }, tokenResponse.status);

  return jsonResponse({
    ...data,
    output_language: outputLanguage,
    call_endpoint: "wss://api.openai.com/v1/realtime/translations",
    webrtc_call_endpoint: "https://api.openai.com/v1/realtime/translations/calls",
    model,
  });
});

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL")!;
  const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
  const legacyServiceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const key = secretKeysRaw ? JSON.parse(secretKeysRaw).default : legacyServiceRole;
  return createClient(url, key);
}

function decodeJWSPayload(jws: string): Record<string, unknown> | null {
  const part = jws.split(".")[1];
  if (!part) return null;
  const normalized = part.replace(/-/g, "+").replace(/_/g, "/");
  const json = atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "="));
  return JSON.parse(json);
}

async function recordAndCheckUsage(
  supabase: ReturnType<typeof createServiceClient>,
  input: {
    originalTransactionId: string;
    transactionId: string;
    productId: string;
    expiresAt: string;
    environment: string;
  },
) {
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data } = await supabase
    .from("samantha_key_subscription_access")
    .select("token_requests,last_token_request_at")
    .eq("original_transaction_id", input.originalTransactionId)
    .maybeSingle();

  const recentCount = data?.last_token_request_at && data.last_token_request_at > since
    ? Number(data.token_requests ?? 0)
    : 0;
  if (recentCount >= MAX_TOKEN_REQUESTS_PER_DAY) return false;

  await supabase.from("samantha_key_subscription_access").upsert({
    original_transaction_id: input.originalTransactionId,
    product_id: input.productId,
    status: "active",
    expires_at: input.expiresAt,
    environment: input.environment,
    last_transaction_id: input.transactionId,
    token_requests: recentCount + 1,
    last_token_request_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  });
  return true;
}
