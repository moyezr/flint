import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  betaVerificationCodeMatches,
  generateBetaVerificationCode,
  hashBetaVerificationCode,
  normalizeOptionalName,
  normalizeRequiredName,
} from "./beta-verification.ts";

describe("beta email verification", () => {
  it("generates a six-digit code", () => {
    assert.equal(generateBetaVerificationCode(() => 123456), "123456");
  });

  it("binds the stored hash to both the challenge and code", () => {
    const expectedHash = hashBetaVerificationCode({
      verificationID: "verification-a",
      code: "123456",
      pepper: "test-pepper",
    });

    assert.equal(betaVerificationCodeMatches({
      verificationID: "verification-a",
      code: "123456",
      pepper: "test-pepper",
      expectedHash,
    }), true);
    assert.equal(betaVerificationCodeMatches({
      verificationID: "verification-a",
      code: "654321",
      pepper: "test-pepper",
      expectedHash,
    }), false);
    assert.equal(betaVerificationCodeMatches({
      verificationID: "verification-b",
      code: "123456",
      pepper: "test-pepper",
      expectedHash,
    }), false);
  });

  it("stores blank optional names as null and trims entered names", () => {
    assert.equal(normalizeOptionalName(undefined), null);
    assert.equal(normalizeOptionalName("   "), null);
    assert.equal(normalizeOptionalName("  Ada  "), "Ada");
  });

  it("requires and trims the first name", () => {
    assert.equal(normalizeRequiredName("  Ada  "), "Ada");
    assert.throws(() => normalizeRequiredName("   "), /First name is required/);
  });
});
