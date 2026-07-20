"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

import { useTypingEconomics } from "@/components/landing/typing-economics-provider";
import {
  ASSUMED_TYPING_DAYS_PER_WEEK,
  ASSUMED_TYPING_HOURS_PER_DAY,
  CONSERVATIVE_HOURLY_RATE,
  SPEAKING_PACE_WPM,
  TYPING_TEST_SECONDS,
  calculateTypingEconomics,
  type NoGapTypingResult,
  type SavingsTypingResult,
  type TypingEconomicsResult,
} from "@/lib/typing-economics";

const TEST_DURATION = TYPING_TEST_SECONDS;
const TEST_COPY = [
  "Clear thinking deserves a faster path from the first idea to the finished sentence.",
  "The best tools disappear until the work is all that remains in front of you.",
  "A quiet moment can turn a rough thought into a sentence worth keeping.",
  "Speak naturally, edit lightly, and keep your attention on the idea that matters.",
  "Good writing begins when the distance between thought and page becomes smaller.",
  "Your next clear sentence may arrive before your hands have found the keyboard.",
  "Small improvements to the way you work make room for better decisions every day.",
  "When your voice keeps pace with your mind, momentum becomes easier to protect."
] as const;

type TestState = "ready" | "running" | "complete";

interface ResultMetrics {
  accuracy: number;
  completedEarly: boolean;
  elapsed: number;
}

function getMetrics(input: string, passage: string, startedAt: number, finishedAt: number): ResultMetrics {
  const elapsed = Math.max(0.1, (finishedAt - startedAt) / 1000);
  const correctCharacters = Array.from(input).reduce(
    (total, character, index) => total + Number(character === passage[index]),
    0
  );
  const accuracy = input.length ? Math.round((correctCharacters / input.length) * 100) : 0;

  return {
    accuracy,
    completedEarly: input.length === passage.length && elapsed < TEST_DURATION,
    elapsed,
  };
}

export function TypingTest() {
  const { setResult } = useTypingEconomics();
  const [state, setState] = useState<TestState>("ready");
  const [input, setInput] = useState("");
  const [passage, setPassage] = useState<string>(TEST_COPY[0]);
  const [remaining, setRemaining] = useState(TEST_DURATION);
  const [metrics, setMetrics] = useState<ResultMetrics | null>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const startedAtRef = useRef<number | null>(null);
  const passageIndexRef = useRef(0);

  const finish = useCallback((finalInput: string, finishedAt = performance.now()) => {
    const startedAt = startedAtRef.current;
    if (!startedAt) return;

    const nextMetrics = getMetrics(finalInput, passage, startedAt, finishedAt);
    setMetrics(nextMetrics);
    setResult(calculateTypingEconomics({
      charactersTyped: finalInput.length,
      completedEarly: nextMetrics.completedEarly,
      elapsedSeconds: nextMetrics.elapsed,
    }));
    setRemaining(Math.max(0, TEST_DURATION - (finishedAt - startedAt) / 1000));
    setState("complete");
  }, [passage, setResult]);

  useEffect(() => {
    if (state !== "running") return;

    const timer = window.setInterval(() => {
      const startedAt = startedAtRef.current;
      if (!startedAt) return;
      const nextRemaining = Math.max(0, TEST_DURATION - (performance.now() - startedAt) / 1000);
      setRemaining(nextRemaining);
      if (nextRemaining === 0) finish(inputRef.current?.value ?? "", performance.now());
    }, 100);

    return () => window.clearInterval(timer);
  }, [finish, state]);

  const start = useCallback(() => {
    const nextIndex = (passageIndexRef.current + 1 + Math.floor(Math.random() * (TEST_COPY.length - 1))) % TEST_COPY.length;
    passageIndexRef.current = nextIndex;
    setPassage(TEST_COPY[nextIndex]);
    setInput("");
    setMetrics(null);
    setResult(null);
    setRemaining(TEST_DURATION);
    startedAtRef.current = performance.now();
    setState("running");
    window.requestAnimationFrame(() => inputRef.current?.focus());
  }, [setResult]);

  const cancel = useCallback(() => {
    startedAtRef.current = null;
    setState("ready");
    setInput("");
    setMetrics(null);
    setResult(null);
    setRemaining(TEST_DURATION);
  }, [setResult]);

  const handleInput = useCallback((event: React.ChangeEvent<HTMLTextAreaElement>) => {
    const nextInput = event.target.value.slice(0, passage.length);
    setInput(nextInput);
    if (nextInput.length === passage.length) finish(nextInput);
  }, [finish, passage.length]);

  const renderedPassage = useMemo(() => (
    Array.from(passage).map((character, index) => {
      const typedCharacter = input[index];
      const isCurrent = state === "running" && index === input.length;
      const feedbackClass = typedCharacter === undefined
        ? "text-typing-muted"
        : typedCharacter === character
          ? "text-emerald-300"
          : "bg-red-500/20 text-red-300";

      return (
        <span className={`rounded-sm ${feedbackClass} ${isCurrent ? "border-b-2 border-paper" : ""}`} key={`${character}-${index}`}>
          {character}
        </span>
      );
    })
  ), [input, passage, state]);

  const timerLabel = state === "complete" ? "COMPLETE" : `${Math.ceil(remaining).toString().padStart(2, "0")} SEC`;

  return (
    <div id="typing-test" className="mt-[68px] min-h-[408px] border border-typing-line bg-typing-panel p-6 max-[520px]:mt-[46px] max-[520px]:min-h-[390px] max-[520px]:p-4 scroll-mt-[calc(50svh-204px)] ">
      <div className="flex items-center justify-between font-mono text-[11px] font-semibold text-demo-muted tabular-nums">
        <span>YOUR TYPING PACE</span>
        <span>{timerLabel}</span>
      </div>
      <p className="mt-3 mb-0 flex items-center gap-4 font-mono text-[10px] font-semibold uppercase tracking-[0.04em]">
        <span className="inline-flex items-center gap-1.5 text-emerald-300"><i className="block size-1.5 rounded-full bg-emerald-400" /> Correct character</span>
        <span className="inline-flex items-center gap-1.5 text-red-300"><i className="block size-1.5 rounded-full bg-red-400" /> Mistyped character</span>
      </p>

      <div className="relative mx-auto mt-[62px] max-w-[830px] max-[520px]:mt-[42px]" onClick={() => state === "running" && inputRef.current?.focus()}>
        <p aria-hidden="true" className="m-0 select-none text-center text-[28px] leading-[1.55] tracking-[-0.02em] max-[520px]:text-[22px]">
          {renderedPassage}
        </p>
        <textarea
          aria-label="Type the displayed passage"
          autoCapitalize="none"
          autoComplete="off"
          autoCorrect="off"
          className="absolute inset-0 h-full w-full resize-none opacity-0 outline-none disabled:cursor-default"
          disabled={state !== "running"}
          onChange={handleInput}
          ref={inputRef}
          spellCheck={false}
          value={input}
        />
      </div>

      <div className="mt-[34px] flex items-center justify-between font-mono text-[11px] font-semibold text-demo-muted tabular-nums max-[520px]:flex-col max-[520px]:items-start max-[520px]:gap-[18px]">
        {state === "ready" && <button className="min-h-11 cursor-pointer border border-signal bg-signal px-4 text-paper transition-colors hover:bg-paper hover:text-ink" type="button" onClick={start}>Start 15 second test</button>}
        {state === "running" && <div className="flex items-center gap-4"><span className="inline-flex items-center gap-2 text-signal"><i className="block size-2 animate-[status-pulse_1.2s_ease-in-out_infinite] bg-signal" /> YOUR TIME IS RUNNING</span><button className="cursor-pointer text-demo-muted underline decoration-demo-muted/60 underline-offset-4 transition-colors hover:text-paper" type="button" onClick={cancel}>Cancel test</button></div>}
        {state === "complete" && <button className="min-h-11 cursor-pointer border border-signal bg-signal px-4 text-paper transition-colors hover:bg-paper hover:text-ink" type="button" onClick={start}>Try another passage</button>}
        <span>{input.length} / {passage.length} CHARACTERS</span>
      </div>

      {state === "complete" && metrics && (
        <TypingResultReveal
          accuracy={metrics.accuracy}
          completedEarly={metrics.completedEarly}
          elapsed={metrics.elapsed}
          result={calculateTypingEconomics({
            charactersTyped: input.length,
            completedEarly: metrics.completedEarly,
            elapsedSeconds: metrics.elapsed,
          })}
        />
      )}
    </div>
  );
}

function TypingResultReveal({
  accuracy,
  completedEarly,
  elapsed,
  result,
}: {
  accuracy: number;
  completedEarly: boolean;
  elapsed: number;
  result: TypingEconomicsResult;
}) {
  if (result.kind === "insufficient") {
    return (
      <div className="mx-auto mt-9 max-w-[830px] border-t border-typing-line pt-7" role="status">
        <p className="font-mono text-[11px] font-semibold text-signal">NOT ENOUGH TEXT FOR AN ESTIMATE</p>
        <p className="mt-3 mb-0 max-w-[620px] text-[15px] leading-[1.65] text-typing-muted">
          This run had <span className="font-mono tabular-nums text-paper">{result.charactersTyped} characters</span>. A useful comparison needs at least <span className="font-mono tabular-nums text-paper">{result.minimumCharacters}</span>. Try another passage and keep typing until the timer ends.
        </p>
      </div>
    );
  }

  return (
    <div className="mx-auto mt-9 max-w-[920px] border-t border-typing-line pt-7" role="status">
      <div>
        <p className="font-mono text-[11px] font-semibold text-signal">YOUR RESULT</p>
        <p className="mt-2 mb-0 text-[14px] leading-[1.55] text-typing-muted">
          <span className="font-mono tabular-nums text-paper">{accuracy}% accuracy</span> over <span className="font-mono tabular-nums text-paper">{formatNumber(elapsed, 1)} seconds</span>{completedEarly ? ", with the passage completed before the timer" : ""}.
        </p>
      </div>

      <div className="mt-8 grid max-w-[650px] grid-cols-2 gap-8 max-[520px]:gap-5">
        <div>
          <p className="font-mono text-[10px] font-semibold text-demo-muted">YOUR PACE</p>
          <p className="mt-2 mb-0 font-mono text-[42px] leading-none text-paper tabular-nums max-[520px]:text-[34px]">
            {formatWpm(result.wpm)} <span className="text-[13px] text-typing-muted">WPM</span>
          </p>
        </div>
        <div className="border-l border-typing-line pl-8 max-[520px]:pl-5">
          <p className="font-mono text-[10px] font-semibold text-demo-muted">FLINT&apos;S PACE</p>
          <p className="mt-2 mb-0 font-mono text-[42px] leading-none text-signal tabular-nums max-[520px]:text-[34px]">
            ~{SPEAKING_PACE_WPM} <span className="text-[13px] text-typing-muted">WPM</span>
          </p>
          <p className="mt-2 mb-0 text-[12px] leading-[1.45] text-demo-muted">Roughly natural speaking pace.</p>
        </div>
      </div>

      <ResultSummary result={result} />
      <CalculationDetails result={result} />

      <div className="mt-8 flex items-center justify-between gap-6 border-t border-typing-line pt-6 max-[620px]:flex-col max-[620px]:items-start">
        <p className="m-0 max-w-[620px] text-[15px] leading-[1.65] text-typing-muted">
          Flint is free to try during early access. You can compare it with your current pace without making a purchase.
        </p>
        <a
          className="inline-flex min-h-11 shrink-0 items-center bg-signal px-5 font-mono text-[11px] font-semibold text-paper transition-colors hover:bg-paper hover:text-ink"
          href="#download"
        >
          TRY FLINT FREE ↓
        </a>
      </div>
    </div>
  );
}

function ResultSummary({ result }: { result: NoGapTypingResult | SavingsTypingResult }) {
  if (result.kind === "no-gap") {
    return (
      <p className="mt-8 mb-0 max-w-[780px] text-[17px] leading-[1.7] text-typing-muted">
        That leaves no measured pace gap against the <Metric>~{SPEAKING_PACE_WPM} WPM</Metric> comparison. Dictation is unlikely to save much typing time at this pace, though it can still provide a hands-free way to write.
      </p>
    );
  }

  return (
    <p className="mt-8 mb-0 max-w-[820px] text-[17px] leading-[1.7] text-typing-muted">
      That is a <Metric>{formatNumber(result.gapPercent, 1)}% gap</Metric>. Assuming one hour of typing a day, five days a week, it adds up to about <Metric>${formatMoney(result.monthlyValue)} a month</Metric> in time—using a conservative <Metric>${CONSERVATIVE_HOURLY_RATE}/hour</Metric>, not your actual rate.
    </p>
  );
}

function Metric({ children }: { children: React.ReactNode }) {
  return <span className="font-mono text-paper tabular-nums">{children}</span>;
}

function CalculationDetails({ result }: { result: NoGapTypingResult | SavingsTypingResult }) {
  return (
    <details className="mt-6 max-w-[820px] border-t border-typing-line pt-4 text-typing-muted">
      <summary className="cursor-pointer font-mono text-[11px] font-semibold text-demo-muted hover:text-paper">
        SEE HOW THIS IS CALCULATED
      </summary>
      <div className="mt-4 grid gap-3 font-mono text-[11px] leading-[1.6] text-typing-muted tabular-nums">
        <p className="m-0"><span className="text-demo-muted">Typing pace:</span> {wpmEquation(result)}</p>
        <p className="m-0"><span className="text-demo-muted">Pace gap:</span> {gapEquation(result)}</p>
        {result.kind === "savings" ? (
          <>
            <p className="m-0"><span className="text-demo-muted">Weekly time:</span> {ASSUMED_TYPING_HOURS_PER_DAY} hour/day × {ASSUMED_TYPING_DAYS_PER_WEEK} days × {formatNumber(result.gapPercent, 1)}% = {formatNumber(result.weeklyHours, 2)} hours/week</p>
            <p className="m-0"><span className="text-demo-muted">Time value:</span> {formatNumber(result.weeklyHours, 2)} hours × ${CONSERVATIVE_HOURLY_RATE} = ${formatMoney(result.weeklyValue)}/week; × 52 ÷ 12 = ${formatMoney(result.monthlyValue)}/month</p>
          </>
        ) : null}
      </div>
    </details>
  );
}

function wpmEquation(result: NoGapTypingResult | SavingsTypingResult) {
  if (result.measurementSeconds === TYPING_TEST_SECONDS) {
    return `${result.charactersTyped} characters × 0.8 = ${formatWpm(result.wpm)} WPM`;
  }
  return `(${result.charactersTyped} ÷ 5) ÷ (${formatNumber(result.measurementSeconds, 1)} seconds ÷ 60) = ${formatWpm(result.wpm)} WPM`;
}

function gapEquation(result: NoGapTypingResult | SavingsTypingResult) {
  return `max(0, 1 − (${formatWpm(result.wpm)} ÷ ${SPEAKING_PACE_WPM})) = ${formatNumber(result.gapPercent, 1)}%`;
}

function formatWpm(value: number) {
  return formatNumber(value, Number.isInteger(value) ? 0 : 1);
}

function formatMoney(value: number) {
  return Math.round(value).toLocaleString("en-US");
}

function formatNumber(value: number, maximumFractionDigits: number) {
  return value.toLocaleString("en-US", { maximumFractionDigits });
}
