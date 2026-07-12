import { createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const environmentPath = resolve(import.meta.dirname, "..", ".env");
const existing = await readEnvironment(environmentPath);
const generated = {};

if (!existing.LICENSE_KEY_PEPPER) {
  generated.LICENSE_KEY_PEPPER = randomBytes(32).toString("hex");
}
if (!existing.COMMERCE_WEBHOOK_SECRET) {
  generated.COMMERCE_WEBHOOK_SECRET = randomBytes(32).toString("hex");
}
if (!existing.LICENSE_SIGNING_PRIVATE_KEY) {
  const { privateKey } = generateKeyPairSync("ed25519");
  const privatePem = privateKey.export({ format: "pem", type: "pkcs8" });
  const publicSpki = createPublicKey(privateKey).export({ format: "der", type: "spki" });
  generated.LICENSE_SIGNING_PRIVATE_KEY = Buffer.from(privatePem).toString("base64");
  generated.LICENSE_CERTIFICATE_PUBLIC_KEY = Buffer.from(publicSpki).subarray(-32).toString("base64url");
} else if (!existing.LICENSE_CERTIFICATE_PUBLIC_KEY) {
  const privatePem = Buffer.from(existing.LICENSE_SIGNING_PRIVATE_KEY, "base64").toString("utf8");
  const publicSpki = createPublicKey(createPrivateKey(privatePem)).export({ format: "der", type: "spki" });
  generated.LICENSE_CERTIFICATE_PUBLIC_KEY = Buffer.from(publicSpki).subarray(-32).toString("base64url");
}
if (!existing.NEXT_PUBLIC_SITE_URL) {
  generated.NEXT_PUBLIC_SITE_URL = "https://flint.moyezrabbani.dev";
}
if (!existing.LICENSE_EMAIL_FROM) {
  generated.LICENSE_EMAIL_FROM = "Flint <licenses@flint.moyezrabbani.dev>";
}
if (!existing.LICENSE_APP_BUNDLE_ID) {
  generated.LICENSE_APP_BUNDLE_ID = "com.moyezrabbani.Flint";
}

const finalValues = { ...existing, ...generated };
if (Object.keys(generated).length > 0) {
  const additions = Object.entries(generated)
    .map(([key, value]) => `${key}=${serialize(value)}`)
    .join("\n");
  const prefix = existing.__raw?.trim() ? `${existing.__raw.trim()}\n` : "";
  await writeFile(environmentPath, `${prefix}${additions}\n`, { mode: 0o600 });
  console.log(`Updated ${environmentPath} with ${Object.keys(generated).length} licensing configuration values.`);
} else {
  console.log("Licensing configuration is already present.");
}

console.log(`LICENSE_CERTIFICATE_PUBLIC_KEY=${finalValues.LICENSE_CERTIFICATE_PUBLIC_KEY}`);
console.log("Keep landing/.env in a secret manager. The public key is safe to embed in Flint.");

async function readEnvironment(path) {
  let raw = "";
  try {
    raw = await readFile(path, "utf8");
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
  const values = { __raw: raw };
  for (const line of raw.split(/\r?\n/)) {
    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!match) {
      continue;
    }
    values[match[1]] = match[2].replace(/^"|"$/g, "");
  }
  return values;
}

function serialize(value) {
  return /[\s<>]/.test(value) ? JSON.stringify(value) : value;
}
