import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { calculateTypingEconomics } from "./typing-economics.ts";

describe("calculateTypingEconomics", () => {
  it("shows an honest no-gap result for a fast typer who finishes early", () => {
    const result = calculateTypingEconomics({
      charactersTyped: 84,
      completedEarly: true,
      elapsedSeconds: 7.5,
    });

    assert.equal(result.kind, "no-gap");
    assert.equal(result.wpm, 134.4);
    assert.equal(result.gapPercent, 0);
  });

  it("calculates the time and value estimates for a slower 15-second run", () => {
    const result = calculateTypingEconomics({
      charactersTyped: 30,
      completedEarly: false,
      elapsedSeconds: 15,
    });

    assert.equal(result.kind, "savings");
    assert.equal(result.wpm, 24);
    assert.ok(Math.abs(result.gapPercent - 81.5384615385) < 0.000001);
    assert.ok(Math.abs(result.weeklyHours - 4.0769230769) < 0.000001);
    assert.ok(Math.abs(result.weeklyValue - 81.5384615385) < 0.000001);
    assert.ok(Math.abs(result.monthlyValue - 353.3333333333) < 0.000001);
  });

  it("does not estimate a run with fewer than 15 characters", () => {
    const result = calculateTypingEconomics({
      charactersTyped: 14,
      completedEarly: false,
      elapsedSeconds: 15,
    });

    assert.deepEqual(result, {
      kind: "insufficient",
      charactersTyped: 14,
      minimumCharacters: 15,
    });
  });
});
