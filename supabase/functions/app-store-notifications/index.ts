import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, jsonResponse } from "../_shared/cors.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  const body = await request.json().catch(() => ({}));
  const signedPayload = body.signedPayload;
  if (!signedPayload) return jsonResponse({ error: "missing_signed_payload" }, 400);

  const notification = decodeJWSPayload(String(signedPayload));
  const data = notification?.data as Record<string, unknown> | undefined;
  const signedTransactionInfo = data?.signedTransactionInfo as string | undefined;
  if (!signedTransactionInfo) return jsonResponse({ ok: true, ignored: true });

  const transaction = decodeJWSPayload(signedTransactionInfo);
  const originalTransactionId = String(transaction?.originalTransactionId ?? "");
  if (!originalTransactionId) return jsonResponse({ ok: true, ignored: true });

  const supabase = createServiceClient();
  await supabase.from("samantha_key_subscription_access").upsert({
    original_transaction_id: originalTransactionId,
    product_id: transaction?.productId ?? "samantha_key_monthly",
    status: notification?.notificationType ?? "updated",
    expires_at: transaction?.expiresDate ? new Date(Number(transaction.expiresDate)).toISOString() : null,
    environment: transaction?.environment ?? "unknown",
    last_transaction_id: transaction?.transactionId ?? null,
    updated_at: new Date().toISOString(),
  });

  return jsonResponse({ ok: true });
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
