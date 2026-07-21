import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { betaDownloadFormIsReady } from "./beta-download-form.ts";

const initialForm = {
  firstName: "",
  email: "",
  acceptedTerms: false,
  verificationID: null,
  verificationCode: "",
  pendingDownloadURL: null,
};

describe("beta download form readiness", () => {
  it("requires a first name, valid email, and beta-terms acceptance", () => {
    assert.equal(betaDownloadFormIsReady(initialForm), false);
    assert.equal(betaDownloadFormIsReady({
      ...initialForm,
      firstName: "Ada",
      email: "ada@example.com",
      acceptedTerms: true,
    }), true);
    assert.equal(betaDownloadFormIsReady({
      ...initialForm,
      firstName: "Ada",
      email: "not-an-email",
      acceptedTerms: true,
    }), false);
  });

  it("requires all six OTP digits after a code is sent", () => {
    assert.equal(betaDownloadFormIsReady({
      ...initialForm,
      verificationID: "verification-id",
      verificationCode: "12345",
    }), false);
    assert.equal(betaDownloadFormIsReady({
      ...initialForm,
      verificationID: "verification-id",
      verificationCode: "123456",
    }), true);
  });

  it("keeps the ready-download action enabled", () => {
    assert.equal(betaDownloadFormIsReady({
      ...initialForm,
      pendingDownloadURL: "/api/beta-download?token=test",
    }), true);
  });
});
