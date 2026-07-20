import "server-only";

import { createHmac } from "node:crypto";

import { database } from "../licenses/database";

export type RateLimitRule = {
  identifier: string;
  maximumRequests: number;
  windowSeconds: number;
};

export class RateLimitExceededError extends Error {
  constructor(readonly retryAfterSeconds: number) {
    super("Rate limit exceeded.");
  }
}

export async function enforceRateLimits(rules: readonly RateLimitRule[]): Promise<void> {
  const pepper = process.env.BETA_ABUSE_PEPPER?.trim() || process.env.LICENSE_KEY_PEPPER?.trim();
  if (!pepper) {
    throw new Error("BETA_ABUSE_PEPPER is not configured.");
  }

  const sql = database();
  const now = new Date();

  await sql.begin(async (transaction) => {
    await transaction`
      DELETE FROM flint_api_rate_limits
      WHERE expires_at <= NOW()
    `;

    for (const rule of rules) {
      const windowMilliseconds = rule.windowSeconds * 1_000;
      const windowStart = new Date(Math.floor(now.getTime() / windowMilliseconds) * windowMilliseconds);
      const expiresAt = new Date(windowStart.getTime() + windowMilliseconds * 2);
      const keyHash = createHmac("sha256", pepper)
        .update(rule.identifier, "utf8")
        .digest("hex");
      const [counter] = await transaction<{ request_count: number }[]>`
        INSERT INTO flint_api_rate_limits (
          key_hash,
          window_started_at,
          request_count,
          expires_at
        ) VALUES (
          ${keyHash},
          ${windowStart},
          1,
          ${expiresAt}
        )
        ON CONFLICT (key_hash, window_started_at) DO UPDATE SET
          request_count = flint_api_rate_limits.request_count + 1,
          expires_at = EXCLUDED.expires_at
        RETURNING request_count
      `;

      if (counter.request_count > rule.maximumRequests) {
        const retryAfterSeconds = Math.max(
          1,
          Math.ceil((windowStart.getTime() + windowMilliseconds - now.getTime()) / 1_000),
        );
        throw new RateLimitExceededError(retryAfterSeconds);
      }
    }
  });
}

export function requestClientAddress(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for")
    ?.split(",")
    .map((value) => value.trim())
    .find(Boolean);
  return forwarded || request.headers.get("x-real-ip")?.trim() || "unavailable";
}
