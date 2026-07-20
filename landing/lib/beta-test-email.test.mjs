import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { disposableBetaTestEmail } from "./beta-test-email.mjs";

describe("disposable beta test email", () => {
  it("keeps an ordinary mailbox within the email local-part limit", () => {
    const email = disposableBetaTestEmail(
      "moyezrabbani@example.com",
      "13cb7348-f4ee-4cb4-a869-bb61e1e11f33",
    );

    assert.equal(email, "moyezrabbani+flint-13cb7348f4ee@example.com");
    assert.ok(email.slice(0, email.lastIndexOf("@")).length <= 64);
  });

  it("replaces an existing plus tag", () => {
    assert.equal(
      disposableBetaTestEmail("ada+old@example.com", "ABC-123"),
      "ada+flint-abc123@example.com",
    );
  });

  it("reports when an inbox is too long for a disposable suffix", () => {
    assert.throws(
      () => disposableBetaTestEmail(`${"a".repeat(50)}@example.com`, "123456789012"),
      /too long/,
    );
  });
});
