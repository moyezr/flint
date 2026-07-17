import { randomUUID } from "node:crypto";

import postgres from "postgres";

const databaseUrl = required("DATABASE_URL");
const baseURL = new URL(process.env.FLINT_BETA_TEST_URL ?? "http://127.0.0.1:3000");
const normalizedEmail = `flint-beta-test+${randomUUID()}@example.com`;
const sql = postgres(databaseUrl, { max: 1, onnotice: () => {} });

try {
  const signupResponse = await fetch(new URL("/api/beta-signups", baseURL), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: normalizedEmail,
      marketingConsent: false,
      source: "automated-verifier",
      website: "",
      startedAt: Date.now() - 1_000,
    }),
  });
  const signupBody = await signupResponse.json();
  assert(signupResponse.status === 200, `Expected signup 200, received ${signupResponse.status}.`);
  assert(typeof signupBody.downloadURL === "string", "Signup response did not include a download URL.");

  const downloadResponse = await fetch(signupBody.downloadURL, { redirect: "manual" });
  assert(downloadResponse.status === 307, `Expected download redirect 307, received ${downloadResponse.status}.`);
  assert(downloadResponse.headers.get("location")?.endsWith(".dmg"), "Download did not redirect to a DMG.");

  const reusedResponse = await fetch(signupBody.downloadURL, { redirect: "manual" });
  assert(reusedResponse.status === 303, `Expected consumed token redirect 303, received ${reusedResponse.status}.`);

  const [signup] = await sql`
    SELECT download_count
    FROM flint_beta_signups
    WHERE normalized_email = ${normalizedEmail}
  `;
  assert(signup?.download_count === 1, "The beta signup download count was not recorded.");

  console.log(`Beta signup and one-time download flow passed against ${baseURL.origin}.`);
} finally {
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

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}
