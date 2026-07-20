"use client";

import { useTypingEconomics } from "./typing-economics-provider";

export function TypingResultNote() {
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
      Based on your test: about <span className="font-mono tabular-nums text-ink">${Math.round(result.monthlyValue).toLocaleString("en-US")}/month</span> in typing time, assuming one hour a day, five days a week, at a conservative <span className="font-mono tabular-nums text-ink">$20/hour</span>.
    </p>
  );
}
