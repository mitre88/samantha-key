import * as x509 from "npm:@peculiar/x509@1.12.3";

// Verifies data signed by the App Store: StoreKit 2 transactions (`jwsRepresentation`) and
// App Store Server Notifications V2. Decoding the payload alone proves nothing — anyone can
// base64-encode a JSON body — so every JWS must chain to Apple's root and carry a valid signature.

x509.cryptoProvider.set(crypto);

// SHA-256 of https://www.apple.com/certificateauthority/AppleRootCA-G3.cer (valid until 2039-04-30).
const APPLE_ROOT_CA_G3_SHA256 = "63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179";
// Marker extensions Apple puts on the App Store receipt-signing leaf and its WWDR intermediate.
const LEAF_MARKER_OID = "1.2.840.113635.100.6.11.1";
const INTERMEDIATE_MARKER_OID = "1.2.840.113635.100.6.2.1";

export class AppleJWSError extends Error {}

export type AppleJWSOptions = {
  bundleId: string;
  environments?: string[];
};

/// Returns the verified payload, or throws AppleJWSError with a short machine-readable reason.
export async function verifyAppleJWS(jws: string, options: AppleJWSOptions): Promise<Record<string, unknown>> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new AppleJWSError("malformed_jws");
  const [encodedHeader, encodedPayload, encodedSignature] = parts;

  const header = parseJSON(encodedHeader);
  if (header.alg !== "ES256") throw new AppleJWSError("unexpected_algorithm");
  const chain = header.x5c;
  if (!Array.isArray(chain) || chain.length !== 3) throw new AppleJWSError("missing_certificate_chain");

  let leaf: x509.X509Certificate, intermediate: x509.X509Certificate, root: x509.X509Certificate;
  try {
    [leaf, intermediate, root] = chain.map((der: string) => new x509.X509Certificate(base64ToBytes(der)));
  } catch {
    throw new AppleJWSError("unreadable_certificate");
  }

  const rootThumbprint = toHex(await root.getThumbprint("SHA-256", crypto));
  if (rootThumbprint !== APPLE_ROOT_CA_G3_SHA256) throw new AppleJWSError("untrusted_root");
  if (!intermediate.getExtension(INTERMEDIATE_MARKER_OID)) throw new AppleJWSError("intermediate_not_apple_wwdr");
  if (!leaf.getExtension(LEAF_MARKER_OID)) throw new AppleJWSError("leaf_not_app_store_signer");
  if (!await intermediate.verify({ publicKey: root.publicKey, signatureOnly: true }, crypto)) {
    throw new AppleJWSError("intermediate_not_issued_by_root");
  }
  if (!await leaf.verify({ publicKey: intermediate.publicKey, signatureOnly: true }, crypto)) {
    throw new AppleJWSError("leaf_not_issued_by_intermediate");
  }

  const payload = parseJSON(encodedPayload);
  // Certificates must have been valid when Apple signed, so older renewals still verify.
  const signedAt = new Date(Number(payload.signedDate ?? Date.now()));
  for (const certificate of [leaf, intermediate]) {
    if (signedAt < certificate.notBefore || signedAt > certificate.notAfter) {
      throw new AppleJWSError("certificate_not_valid_at_signing");
    }
  }

  const leafKey = await leaf.publicKey.export({ name: "ECDSA", namedCurve: "P-256" }, ["verify"], crypto);
  const signatureIsValid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    leafKey,
    base64ToBytes(encodedSignature),
    new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`),
  );
  if (!signatureIsValid) throw new AppleJWSError("invalid_signature");

  // Transactions carry bundleId at the top level; notifications nest it under `data`.
  const data = payload.data as Record<string, unknown> | undefined;
  const bundleId = payload.bundleId ?? data?.bundleId;
  if (bundleId !== options.bundleId) throw new AppleJWSError("wrong_bundle");
  const environment = String(payload.environment ?? data?.environment ?? "");
  if (!(options.environments ?? ["Production", "Sandbox"]).includes(environment)) {
    throw new AppleJWSError("unexpected_environment");
  }

  return payload;
}

/// Verification is enforced unless APPLE_JWS_ENFORCEMENT=shadow, an emergency switch that only
/// logs failures, so a missing secret can never reopen the unverified path.
export function isEnforcing(): boolean {
  return Deno.env.get("APPLE_JWS_ENFORCEMENT") !== "shadow";
}

/// Reads a StoreKit transaction for an Edge Function: the verified payload, or null when it fails
/// verification under enforcement. Every verdict is logged so failures can be audited.
export async function readTransaction(
  jws: string,
  options: AppleJWSOptions,
  functionName: string,
): Promise<Record<string, unknown> | null> {
  try {
    const payload = await verifyAppleJWS(jws, options);
    console.log(JSON.stringify({ event: "apple_jws", fn: functionName, verdict: "verified" }));
    return payload;
  } catch (error) {
    const reason = error instanceof AppleJWSError ? error.message : "verification_error";
    const enforced = isEnforcing();
    console.log(JSON.stringify({ event: "apple_jws", fn: functionName, verdict: "rejected", reason, enforced }));
    return enforced ? null : decodeJWSPayload(jws);
  }
}

export function decodeJWSPayload(jws: string): Record<string, unknown> | null {
  try {
    return parseJSON(jws.split(".")[1] ?? "");
  } catch {
    return null;
  }
}

function parseJSON(segment: string): Record<string, unknown> {
  return JSON.parse(new TextDecoder().decode(base64ToBytes(segment)));
}

// Returns a plain ArrayBuffer so it satisfies BufferSource across Deno/TypeScript versions.
function base64ToBytes(value: string): ArrayBuffer {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "="));
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
  return bytes.buffer as ArrayBuffer;
}

function toHex(buffer: ArrayBuffer): string {
  return Array.from(new Uint8Array(buffer), (byte) => byte.toString(16).padStart(2, "0")).join("");
}
