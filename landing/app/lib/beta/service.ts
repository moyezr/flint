import "server-only";

import { createHash, randomBytes, randomUUID } from "node:crypto";

import {
  betaVerificationCodeMatches,
  betaVerificationLifetimeMinutes,
  betaVerificationMaximumAttempts,
  generateBetaVerificationCode,
  hashBetaVerificationCode,
  normalizeOptionalName,
} from "@/lib/beta-verification";

import { database } from "../licenses/database";

const tokenLifetimeMinutes = 15;
export const currentBetaTermsVersion = "2026-07-20";

export type BetaSignupInput = {
  email: string;
  firstName?: string;
  lastName?: string;
  marketingConsent: boolean;
  source: string;
};

export type BetaEmailVerification = {
  verificationID: string;
  code: string;
  expiresAt: Date;
  firstName: string | null;
};

export type BetaEmailVerificationResult =
  | { status: "verified"; token: string }
  | { status: "invalid" }
  | { status: "expired" }
  | { status: "locked" };

type PendingVerification = {
  id: string;
  email: string;
  normalized_email: string;
  first_name: string | null;
  last_name: string | null;
  source: string;
  marketing_consent: boolean;
  terms_version: string;
  terms_accepted_at: Date;
  code_hash: string;
  attempt_count: number;
  expires_at: Date;
};

export async function createBetaEmailVerification(
  input: BetaSignupInput,
): Promise<BetaEmailVerification> {
  const sql = database();
  const verificationID = randomUUID();
  const code = generateBetaVerificationCode();
  const normalizedEmail = normalizeEmail(input.email);
  const firstName = normalizeOptionalName(input.firstName);
  const lastName = normalizeOptionalName(input.lastName);
  const expiresAt = new Date(Date.now() + betaVerificationLifetimeMinutes * 60 * 1_000);
  const codeHash = hashBetaVerificationCode({
    verificationID,
    code,
    pepper: verificationPepper(),
  });

  await sql.begin(async (transaction) => {
    await transaction`
      DELETE FROM flint_beta_email_verifications
      WHERE expires_at <= NOW()
         OR normalized_email = ${normalizedEmail}
    `;

    await transaction`
      INSERT INTO flint_beta_email_verifications (
        id,
        email,
        normalized_email,
        first_name,
        last_name,
        source,
        marketing_consent,
        terms_version,
        terms_accepted_at,
        code_hash,
        expires_at
      ) VALUES (
        ${verificationID},
        ${input.email.trim()},
        ${normalizedEmail},
        ${firstName},
        ${lastName},
        ${input.source},
        ${input.marketingConsent},
        ${currentBetaTermsVersion},
        ${new Date()},
        ${codeHash},
        ${expiresAt}
      )
    `;
  });

  return { verificationID, code, expiresAt, firstName };
}

export async function cancelBetaEmailVerification(verificationID: string): Promise<void> {
  const sql = database();
  await sql`DELETE FROM flint_beta_email_verifications WHERE id = ${verificationID}`;
}

export async function verifyBetaEmail(input: {
  verificationID: string;
  code: string;
}): Promise<BetaEmailVerificationResult> {
  const sql = database();
  const token = randomBytes(32).toString("base64url");
  const tokenHash = hashToken(token);
  const tokenExpiresAt = new Date(Date.now() + tokenLifetimeMinutes * 60 * 1_000);
  const signupID = randomUUID();
  const pepper = verificationPepper();

  return sql.begin(async (transaction) => {
    const [verification] = await transaction<PendingVerification[]>`
      SELECT
        id,
        email,
        normalized_email,
        first_name,
        last_name,
        source,
        marketing_consent,
        terms_version,
        terms_accepted_at,
        code_hash,
        attempt_count,
        expires_at
      FROM flint_beta_email_verifications
      WHERE id = ${input.verificationID}
      FOR UPDATE
    `;

    if (!verification) {
      return { status: "invalid" } as const;
    }

    if (verification.expires_at.getTime() <= Date.now()) {
      await transaction`DELETE FROM flint_beta_email_verifications WHERE id = ${verification.id}`;
      return { status: "expired" } as const;
    }

    if (verification.attempt_count >= betaVerificationMaximumAttempts) {
      return { status: "locked" } as const;
    }

    const matches = betaVerificationCodeMatches({
      verificationID: verification.id,
      code: input.code,
      pepper,
      expectedHash: verification.code_hash,
    });
    if (!matches) {
      const attemptCount = verification.attempt_count + 1;
      await transaction`
        UPDATE flint_beta_email_verifications
        SET attempt_count = ${attemptCount}
        WHERE id = ${verification.id}
      `;
      return {
        status: attemptCount >= betaVerificationMaximumAttempts ? "locked" : "invalid",
      } as const;
    }

    const [signup] = await transaction<{ id: string }[]>`
      INSERT INTO flint_beta_signups (
        id,
        email,
        normalized_email,
        first_name,
        last_name,
        source,
        beta_access_consented_at,
        marketing_consented_at,
        terms_version,
        terms_accepted_at,
        email_verified_at
      ) VALUES (
        ${signupID},
        ${verification.email},
        ${verification.normalized_email},
        ${verification.first_name},
        ${verification.last_name},
        ${verification.source},
        ${verification.terms_accepted_at},
        ${verification.marketing_consent ? verification.terms_accepted_at : null},
        ${verification.terms_version},
        ${verification.terms_accepted_at},
        ${new Date()}
      )
      ON CONFLICT (normalized_email) DO UPDATE SET
        email = EXCLUDED.email,
        first_name = COALESCE(EXCLUDED.first_name, flint_beta_signups.first_name),
        last_name = COALESCE(EXCLUDED.last_name, flint_beta_signups.last_name),
        source = EXCLUDED.source,
        marketing_consented_at = CASE
          WHEN EXCLUDED.marketing_consented_at IS NOT NULL
            THEN COALESCE(flint_beta_signups.marketing_consented_at, EXCLUDED.marketing_consented_at)
          ELSE flint_beta_signups.marketing_consented_at
        END,
        terms_version = EXCLUDED.terms_version,
        terms_accepted_at = EXCLUDED.terms_accepted_at,
        email_verified_at = EXCLUDED.email_verified_at,
        updated_at = NOW()
      RETURNING id
    `;

    await transaction`
      DELETE FROM flint_beta_email_verifications
      WHERE id = ${verification.id}
    `;
    await transaction`
      DELETE FROM flint_beta_download_tokens
      WHERE expires_at <= NOW()
    `;
    await transaction`
      INSERT INTO flint_beta_download_tokens (token_hash, signup_id, expires_at)
      VALUES (${tokenHash}, ${signup.id}, ${tokenExpiresAt})
    `;

    return { status: "verified", token } as const;
  });
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

function verificationPepper(): string {
  const pepper = process.env.BETA_OTP_PEPPER?.trim();
  if (!pepper) {
    throw new Error("BETA_OTP_PEPPER is not configured.");
  }
  return pepper;
}

function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}
