import { createHmac, randomInt, timingSafeEqual } from "node:crypto";

export const betaVerificationCodeDigits = 6;
export const betaVerificationLifetimeMinutes = 10;
export const betaVerificationMaximumAttempts = 5;

export function generateBetaVerificationCode(
  randomInteger: (minimum: number, maximum: number) => number = randomInt,
): string {
  const minimum = 10 ** (betaVerificationCodeDigits - 1);
  const maximum = 10 ** betaVerificationCodeDigits;
  return randomInteger(minimum, maximum).toString();
}

export function hashBetaVerificationCode(input: {
  verificationID: string;
  code: string;
  pepper: string;
}): string {
  return createHmac("sha256", input.pepper)
    .update(`${input.verificationID}:${input.code}`, "utf8")
    .digest("hex");
}

export function betaVerificationCodeMatches(input: {
  verificationID: string;
  code: string;
  pepper: string;
  expectedHash: string;
}): boolean {
  const actualHash = hashBetaVerificationCode(input);
  const actual = Buffer.from(actualHash, "hex");
  const expected = Buffer.from(input.expectedHash, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function normalizeOptionalName(value: string | undefined): string | null {
  const normalized = value?.trim();
  return normalized ? normalized : null;
}
