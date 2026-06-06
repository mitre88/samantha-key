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
  audio_base64?: string;
  mime_type?: string;
  outputLanguage?: string;
  outputLanguageCode?: string;
};

const PRODUCT_ID = "samantha_key_monthly";
const MAX_TOKEN_REQUESTS_PER_DAY = Number(Deno.env.get("MAX_TOKEN_REQUESTS_PER_DAY") ?? "240");
const MAX_AUDIO_BYTES = Number(Deno.env.get("MAX_AUDIO_TRANSLATION_BYTES") ?? String(24 * 1024 * 1024));

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

  const audioBytes = decodeAudio(body.audio_base64 ?? "");
  if (!audioBytes || audioBytes.byteLength < 1024) return jsonResponse({ error: "missing_audio" }, 400);
  if (audioBytes.byteLength > MAX_AUDIO_BYTES) return jsonResponse({ error: "audio_too_large" }, 413);

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

  let transcript = "";
  let translatedText = "";
  const outputLanguage = body.outputLanguage || "English";
  const outputLanguageCode = body.outputLanguageCode || "en";
  try {
    transcript = await transcribeAudio(openAIKey, audioBytes, body.mime_type ?? "audio/mp4");
    if (!transcript) return jsonResponse({ error: "empty_transcript" }, 502);
    translatedText = await translateText(openAIKey, transcript, outputLanguage, outputLanguageCode);
    if (!translatedText) return jsonResponse({ error: "empty_translation" }, 502);
  } catch (error) {
    if (error instanceof Response) return error;
    return jsonResponse({ error: "audio_translate_failed", detail: String(error) }, 500);
  }

  return jsonResponse({
    transcript,
    translated_text: translatedText,
    output_language: outputLanguage,
  });
});

async function transcribeAudio(openAIKey: string, audioBytes: Uint8Array, mimeType: string) {
  const form = new FormData();
  form.append("file", new Blob([audioBytes], { type: mimeType }), "speech.m4a");
  form.append("model", Deno.env.get("OPENAI_AUDIO_TRANSCRIPTION_MODEL") ?? "gpt-4o-transcribe");
  form.append("response_format", "json");

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${openAIKey}` },
    body: form,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Response(JSON.stringify({ error: "openai_audio_transcription_failed", detail: data }), {
      status: response.status,
      headers: corsHeaders,
    });
  }
  return typeof data.text === "string" ? data.text.trim() : "";
}

async function translateText(
  openAIKey: string,
  sourceText: string,
  outputLanguage: string,
  outputLanguageCode: string,
) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("OPENAI_TEXT_TRANSLATION_MODEL") ?? "gpt-4.1-mini",
      instructions:
        `Translate the user's transcript into ${outputLanguage} (${outputLanguageCode}). ` +
        "Return only the translated text. Do not explain, quote, label, or add commentary.",
      input: sourceText,
      max_output_tokens: 1200,
      temperature: 0,
    }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Response(JSON.stringify({ error: "openai_text_translation_failed", detail: data }), {
      status: response.status,
      headers: corsHeaders,
    });
  }
  return extractOutputText(data);
}

function createServiceClient() {
  const url = Deno.env.get("SUPABASE_URL")!;
  const secretKeysRaw = Deno.env.get("SUPABASE_SECRET_KEYS");
  const legacyServiceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const key = secretKeysRaw ? JSON.parse(secretKeysRaw).default : legacyServiceRole;
  return createClient(url, key);
}

function decodeJWSPayload(jws: string): Record<string, unknown> | null {
  try {
    const part = jws.split(".")[1];
    if (!part) return null;
    const normalized = part.replace(/-/g, "+").replace(/_/g, "/");
    const json = atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "="));
    return JSON.parse(json);
  } catch {
    return null;
  }
}

function decodeAudio(base64: string): Uint8Array | null {
  try {
    if (!base64) return null;
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
    return bytes;
  } catch {
    return null;
  }
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

function extractOutputText(data: unknown): string {
  const chunks: string[] = [];
  collectText(data, chunks);
  return chunks.join("").trim();
}

function collectText(value: unknown, chunks: string[]) {
  if (!value || typeof value !== "object") return;
  if (Array.isArray(value)) {
    for (const item of value) collectText(item, chunks);
    return;
  }

  const record = value as Record<string, unknown>;
  if (typeof record.output_text === "string") chunks.push(record.output_text);
  if (record.type === "output_text" && typeof record.text === "string") chunks.push(record.text);
  if (typeof record.text === "string" && record.type === "message") chunks.push(record.text);

  for (const key of ["output", "content", "message"]) {
    collectText(record[key], chunks);
  }
}
