import "server-only";

import { createHash, randomBytes, randomUUID } from "node:crypto";

import { database } from "../licenses/database";

const tokenLifetimeMinutes = 15;

export type BetaSignupInput = {
  email: string;
  marketingConsent: boolean;
  source: string;
};

export async function createBetaDownload(input: BetaSignupInput): Promise<string> {
  const sql = database();
  const normalizedEmail = normalizeEmail(input.email);
  const signupID = randomUUID();
  const token = randomBytes(32).toString("base64url");
  const tokenHash = hashToken(token);
  const expiresAt = new Date(Date.now() + tokenLifetimeMinutes * 60 * 1_000);

  await sql.begin(async (transaction) => {
    const [signup] = await transaction<{ id: string }[]>`
      INSERT INTO flint_beta_signups (
        id,
        email,
        normalized_email,
        source,
        marketing_consented_at
      ) VALUES (
        ${signupID},
        ${input.email.trim()},
        ${normalizedEmail},
        ${input.source},
        ${input.marketingConsent ? new Date() : null}
      )
      ON CONFLICT (normalized_email) DO UPDATE SET
        email = EXCLUDED.email,
        source = EXCLUDED.source,
        marketing_consented_at = CASE
          WHEN EXCLUDED.marketing_consented_at IS NOT NULL
            THEN COALESCE(flint_beta_signups.marketing_consented_at, EXCLUDED.marketing_consented_at)
          ELSE flint_beta_signups.marketing_consented_at
        END,
        updated_at = NOW()
      RETURNING id
    `;

    await transaction`
      DELETE FROM flint_beta_download_tokens
      WHERE expires_at <= NOW()
    `;

    await transaction`
      INSERT INTO flint_beta_download_tokens (token_hash, signup_id, expires_at)
      VALUES (${tokenHash}, ${signup.id}, ${expiresAt})
    `;
  });

  return token;
}

export async function consumeBetaDownload(token: string): Promise<boolean> {
  const sql = database();
  const tokenHash = hashToken(token);

  return sql.begin(async (transaction) => {
    const [download] = await transaction<{ signup_id: string }[]>`
      DELETE FROM flint_beta_download_tokens
      WHERE token_hash = ${tokenHash}
        AND expires_at > NOW()
      RETURNING signup_id
    `;

    if (!download) {
      return false;
    }

    await transaction`
      UPDATE flint_beta_signups
      SET
        download_count = download_count + 1,
        last_downloaded_at = NOW(),
        updated_at = NOW()
      WHERE id = ${download.signup_id}
    `;
    return true;
  });
}

function normalizeEmail(email: string): string {
  return email.trim().toLocaleLowerCase("en-US");
}

function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}
