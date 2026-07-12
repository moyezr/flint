import { createHmac, createPublicKey, generateKeyPairSync, randomBytes, randomUUID, sign, verify } from "node:crypto";
import postgres from "postgres";

const databaseUrl = required("DATABASE_URL");
const keyPepper = required("LICENSE_KEY_PEPPER");
const privateKey = Buffer.from(required("LICENSE_SIGNING_PRIVATE_KEY"), "base64").toString("utf8");
const apiBaseURL = process.env.FLINT_LICENSE_TEST_URL ?? "http://localhost:3001/api/licenses";
const testKey = `FLINT-VERIFY-${randomBytes(16).toString("hex").toUpperCase()}`;
const testEmail = `license-verification-${randomUUID()}@example.invalid`;
const licenseID = randomUUID();
const sql = postgres(databaseUrl, { max: 1, onnotice: () => {} });

try {
  const licenseHash = createHmac("sha256", keyPepper).update(testKey).digest("hex");
  await sql`
    INSERT INTO flint_licenses (id, license_key_hash, customer_email)
    VALUES (${licenseID}, ${licenseHash}, ${testEmail})
  `;

  const { privateKey: devicePrivateKey, publicKey: devicePublicKey } = generateKeyPairSync("ed25519");
  const rawDevicePublicKey = devicePublicKey.export({ format: "der", type: "spki" }).subarray(-32).toString("base64url");
  const challenge = await post("challenges", { purpose: "activate", devicePublicKey: rawDevicePublicKey });
  const deviceSignature = sign(null, Buffer.from(challenge.message, "utf8"), devicePrivateKey).toString("base64url");
  const activation = await post("activate", {
    licenseKey: testKey,
    deviceName: "Flint API verification",
    devicePublicKey: rawDevicePublicKey,
    challengeID: challenge.challengeID,
    challengeNonce: challenge.nonce,
    challengeSignature: deviceSignature,
  });

  if (activation.kind !== "activated" || !activation.certificate || !activation.activationID) {
    throw new Error("Activation did not return a certificate.");
  }
  const [payloadPart, signaturePart] = activation.certificate.split(".");
  if (!payloadPart || !signaturePart || !verify(null, Buffer.from(payloadPart, "utf8"), createPublicKey(privateKey), Buffer.from(signaturePart, "base64url"))) {
    throw new Error("The activation certificate signature could not be verified.");
  }
  const certificate = JSON.parse(Buffer.from(payloadPart, "base64url").toString("utf8"));
  if (certificate.activationID !== activation.activationID || certificate.licenseID !== licenseID || certificate.appBundleID !== "com.moyezrabbani.Flint") {
    throw new Error("The activation certificate contains an unexpected payload.");
  }

  console.log("License API activation and certificate verification passed.");
} finally {
  await sql`DELETE FROM flint_licenses WHERE id = ${licenseID}`;
  await sql.end();
}

async function post(path, body) {
  const response = await fetch(`${apiBaseURL}/${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  const payload = await response.json();
  if (!response.ok) {
    throw new Error(payload.error?.message ?? `License API returned ${response.status}.`);
  }
  return payload;
}

function required(name) {
  const value = process.env[name];
  if (!value?.trim()) {
    throw new Error(`${name} must be set.`);
  }
  return value;
}
