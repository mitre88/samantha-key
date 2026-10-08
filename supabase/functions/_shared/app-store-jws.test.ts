// Run with: deno test --allow-env --allow-net=registry.npmjs.org supabase/functions/_shared/app-store-jws.test.ts
// Synthetic tokens only: these prove forged data is refused. Real App Store transactions were checked
// manually against the App Store Server API and are deliberately not stored in the repository.
import * as x509 from "npm:@peculiar/x509@1.12.3";
import { AppleJWSError, verifyAppleJWS } from "./app-store-jws.ts";

const options = { bundleId: "com.alexmitre.samanthakey" };
const base64Url = (value: string) => btoa(value).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

async function expectRejection(jws: string, reason: string) {
  try {
    await verifyAppleJWS(jws, options);
  } catch (error) {
    if (error instanceof AppleJWSError && error.message === reason) return;
    throw new Error(`expected ${reason}, got ${error}`);
  }
  throw new Error(`expected ${reason}, but verification passed`);
}

Deno.test("an unsigned payload, as the old decoder accepted, is refused", async () => {
  const payload = base64Url(JSON.stringify({ productId: "samantha_key_monthly", expiresDate: Date.now() + 1e9 }));
  await expectRejection(`${base64Url(JSON.stringify({ alg: "none" }))}.${payload}.`, "unexpected_algorithm");
  await expectRejection(`${base64Url(JSON.stringify({ alg: "ES256" }))}.${payload}.AAAA`, "missing_certificate_chain");
});

Deno.test("a self-made chain that copies Apple's names and markers is refused", async () => {
  x509.cryptoProvider.set(crypto);
  const algorithm = { name: "ECDSA", namedCurve: "P-256", hash: "SHA-256" };
  const rootKeys = await crypto.subtle.generateKey(algorithm, true, ["sign", "verify"]);
  const leafKeys = await crypto.subtle.generateKey(algorithm, true, ["sign", "verify"]);
  const validity = { notBefore: new Date(Date.now() - 86_400_000), notAfter: new Date(Date.now() + 86_400_000) };
  const marker = (oid: string) => new x509.Extension(oid, false, new Uint8Array([5, 0]));

  const root = await x509.X509CertificateGenerator.createSelfSigned({
    serialNumber: "01", name: "CN=Apple Root CA - G3", keys: rootKeys, signingAlgorithm: algorithm, ...validity,
  });
  const intermediate = await x509.X509CertificateGenerator.create({
    serialNumber: "02", subject: "CN=Apple Worldwide Developer Relations", issuer: root.subject,
    publicKey: leafKeys.publicKey, signingKey: rootKeys.privateKey, signingAlgorithm: algorithm, ...validity,
    extensions: [marker("1.2.840.113635.100.6.2.1")],
  });
  const leaf = await x509.X509CertificateGenerator.create({
    serialNumber: "03", subject: "CN=Prod ECC Mac App Store and iTunes Store Receipt Signing", issuer: intermediate.subject,
    publicKey: leafKeys.publicKey, signingKey: leafKeys.privateKey, signingAlgorithm: algorithm, ...validity,
    extensions: [marker("1.2.840.113635.100.6.11.1")],
  });

  const der = (certificate: x509.X509Certificate) => btoa(String.fromCharCode(...new Uint8Array(certificate.rawData)));
  const header = base64Url(JSON.stringify({ alg: "ES256", x5c: [der(leaf), der(intermediate), der(root)] }));
  const payload = base64Url(JSON.stringify({
    bundleId: "com.alexmitre.samanthakey", productId: "samantha_key_monthly", environment: "Production",
    expiresDate: Date.now() + 1e9, signedDate: Date.now(),
  }));
  const signature = new Uint8Array(
    await crypto.subtle.sign(algorithm, leafKeys.privateKey, new TextEncoder().encode(`${header}.${payload}`)),
  );
  await expectRejection(`${header}.${payload}.${base64Url(String.fromCharCode(...signature))}`, "untrusted_root");
});
