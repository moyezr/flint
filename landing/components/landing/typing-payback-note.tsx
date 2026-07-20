"use client";

import { useTypingEconomics } from "./typing-economics-provider";

export function TypingPaybackNote() {
  const { result } = useTypingEconomics();

  if (!result || result.kind === "insufficient") {
    return null;
  }

  if (result.kind === "no-gap") {
    return (
      <p className="-mt-5 mb-8 border-l-2 border-signal pl-3 text-[13px] leading-[1.55] text-muted">
        Based on your test: your typing matched or exceeded the roughly <span className="font-mono tabular-nums text-ink">130 WPM</span> comparison pace.
      </p>
    );
  }

  return (
    <p className="-mt-5 mb-8 border-l-2 border-signal pl-3 text-[13px] leading-[1.55] text-muted">
      Based on your test: pays for itself in about <span className="font-mono tabular-nums text-ink">{Math.round(result.paybackMinutes)} minutes</span> of typing.
    </p>
  );
}
