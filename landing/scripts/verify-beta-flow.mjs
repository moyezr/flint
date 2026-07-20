import { createHmac, randomUUID } from "node:crypto";

import postgres from "postgres";

import { disposableBetaTestEmail } from "../lib/beta-test-email.mjs";

const databaseUrl = required("DATABASE_URL");
const baseURL = new URL(process.env.FLINT_BETA_TEST_URL ?? "http://127.0.0.1:3000");
const verificationCode = "123456";
const testEmail = required("FLINT_BETA_TEST_EMAIL");
const normalizedEmail = disposableBetaTestEmail(testEmail, randomUUID()).toLocaleLowerCase("en-US");
const verificationPepper = required("BETA_OTP_PEPPER");
const sql = postgres(databaseUrl, { max: 1, onnotice: () => {} });

try {
  const signupResponse = await fetch(new URL("/api/beta-signups", baseURL), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: normalizedEmail,
      firstName: "Beta",
      lastName: "Verifier",
      marketingConsent: false,
      source: "automated-verifier",
      website: "",
      startedAt: Date.now() - 1_000,
      acceptedTerms: true,
    }),
  });
  const signupBody = await signupResponse.json();
  assert(
    signupResponse.status === 202,
    `Expected signup 202, received ${signupResponse.status}.${responseError(signupBody)}`,
  );
  assert(typeof signupBody.verificationID === "string", "Signup response did not include a verification ID.");

  const codeHash = createHmac("sha256", verificationPepper)
    .update(`${signupBody.verificationID}:${verificationCode}`, "utf8")
    .digest("hex");
  const updated = await sql`
    UPDATE flint_beta_email_verifications
    SET code_hash = ${codeHash}
    WHERE id = ${signupBody.verificationID}
    RETURNING id
  `;
  assert(updated.length === 1, "The pending email verification was not stored.");

  const verificationResponse = await fetch(new URL("/api/beta-signups/verify", baseURL), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      verificationID: signupBody.verificationID,
      code: verificationCode,
    }),
  });
  const verificationBody = await verificationResponse.json();
  assert(verificationResponse.status === 200, `Expected verification 200, received ${verificationResponse.status}.`);
  assert(typeof verificationBody.downloadURL === "string", "Verification response did not include a download URL.");

  const downloadResponse = await fetch(verificationBody.downloadURL, { redirect: "manual" });
  assert(downloadResponse.status === 307, `Expected download redirect 307, received ${downloadResponse.status}.`);
  assert(downloadResponse.headers.get("location")?.endsWith(".dmg"), "Download did not redirect to a DMG.");

  const reusedResponse = await fetch(verificationBody.downloadURL, { redirect: "manual" });
  assert(reusedResponse.status === 303, `Expected consumed token redirect 303, received ${reusedResponse.status}.`);

  const [signup] = await sql`
    SELECT first_name, last_name, email_verified_at, download_count
    FROM flint_beta_signups
    WHERE normalized_email = ${normalizedEmail}
  `;
  assert(signup?.first_name === "Beta", "The beta signup first name was not recorded.");
  assert(signup?.last_name === "Verifier", "The beta signup last name was not recorded.");
  assert(signup?.email_verified_at instanceof Date, "The beta signup email was not marked verified.");
  assert(signup?.download_count === 1, "The beta signup download count was not recorded.");

  console.log(`Beta OTP verification and one-time download flow passed against ${baseURL.origin}.`);
} finally {
  await sql`DELETE FROM flint_beta_email_verifications WHERE normalized_email = ${normalizedEmail}`;
  await sql`DELETE FROM flint_beta_signups WHERE normalized_email = ${normalizedEmail}`;
  await sql.end();
}

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} must be configured.`);
  }
  return value;
}

function responseError(body) {
  return typeof body?.error === "string" ? ` ${body.error}` : "";
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
