import "server-only";

export type LicenseConfiguration = {
  certificateLifetimeDays: number;
  appBundleID: string;
  emailFrom: string;
  keyPepper: string;
  signingPrivateKeyPem: string;
  siteUrl: URL;
};

export function licenseConfiguration(): LicenseConfiguration {
  const keyPepper = required("LICENSE_KEY_PEPPER");
  const encodedPrivateKey = required("LICENSE_SIGNING_PRIVATE_KEY");
  const privateKey = Buffer.from(encodedPrivateKey, "base64").toString("utf8");
  if (!privateKey.includes("BEGIN PRIVATE KEY")) {
    throw new Error("LICENSE_SIGNING_PRIVATE_KEY must be a base64-encoded PKCS#8 PEM.");
  }

  const siteUrl = new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000");
  const certificateLifetimeDays = Number.parseInt(process.env.LICENSE_CERTIFICATE_TTL_DAYS ?? "90", 10);
  if (!Number.isInteger(certificateLifetimeDays) || certificateLifetimeDays < 1 || certificateLifetimeDays > 365) {
    throw new Error("LICENSE_CERTIFICATE_TTL_DAYS must be an integer between 1 and 365.");
  }

  return {
    appBundleID: process.env.LICENSE_APP_BUNDLE_ID?.trim() || "com.moyezrabbani.Flint",
    certificateLifetimeDays,
    emailFrom: required("LICENSE_EMAIL_FROM"),
    keyPepper,
    signingPrivateKeyPem: privateKey,
    siteUrl,
  };
}

export function commerceWebhookSecret(): string {
  return required("COMMERCE_WEBHOOK_SECRET");
}

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is not configured.`);
  }
  return value;
}
