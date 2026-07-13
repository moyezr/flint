"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

const TEST_DURATION = 15;
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
  wpm: number;
}

function getMetrics(input: string, passage: string, startedAt: number, finishedAt: number): ResultMetrics {
  const elapsed = Math.max(0.1, (finishedAt - startedAt) / 1000);
  const correctCharacters = Array.from(input).reduce(
    (total, character, index) => total + Number(character === passage[index]),
    0
  );
  const accuracy = input.length ? Math.round((correctCharacters / input.length) * 100) : 0;
  const wpm = Math.round((correctCharacters / 5) / (elapsed / 60));

  return {
    accuracy,
    completedEarly: input === passage && elapsed < TEST_DURATION,
    elapsed,
    wpm
  };
}

export function TypingTest() {
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

    setMetrics(getMetrics(finalInput, passage, startedAt, finishedAt));
    setRemaining(Math.max(0, TEST_DURATION - (finishedAt - startedAt) / 1000));
    setState("complete");
  }, [passage]);

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
    setRemaining(TEST_DURATION);
    startedAtRef.current = performance.now();
    setState("running");
    window.requestAnimationFrame(() => inputRef.current?.focus());
  }, []);

  const cancel = useCallback(() => {
    startedAtRef.current = null;
    setState("ready");
    setInput("");
    setMetrics(null);
    setRemaining(TEST_DURATION);
  }, []);

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
        <div className="mx-auto mt-9 max-w-[830px] border-t border-typing-line pt-6 text-center" role="status">
          <p className="mb-2 text-base leading-[1.5] text-typing-muted"><strong>{metrics.wpm} WPM.</strong> {metrics.accuracy}% accuracy over {metrics.elapsed.toFixed(1)} seconds{metrics.completedEarly ? ", finished before the timer" : ""}.</p>
          <p className="m-0 text-base leading-[1.5] text-signal">A one-time Flint purchase turns that repeating typing cost into a voice-first workflow.</p>
        </div>
      )}
    </div>
  );
}
