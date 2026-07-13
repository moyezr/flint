"use client";

import { useEffect, useMemo, useRef, useState } from "react";

const testCopy = "Clear thinking deserves a faster path from the first idea to the finished sentence.";
const testDuration = 15;

type TestState = "ready" | "running" | "complete";

export function TypingTest() {
  const [state, setState] = useState<TestState>("ready");
  const [input, setInput] = useState("");
  const [startedAt, setStartedAt] = useState<number | null>(null);
  const [remaining, setRemaining] = useState(testDuration);
  const inputRef = useRef<HTMLTextAreaElement>(null);

  useEffect(() => {
    if (state !== "running" || !startedAt) return;
    const timer = window.setInterval(() => {
      const elapsed = (Date.now() - startedAt) / 1000;
      const nextRemaining = Math.max(0, testDuration - elapsed);
      setRemaining(nextRemaining);
      if (nextRemaining === 0) {
        setState("complete");
        window.clearInterval(timer);
      }
    }, 100);
    return () => window.clearInterval(timer);
  }, [state, startedAt]);

  const metrics = useMemo(() => {
    const words = input.trim().match(/\S+/g)?.length ?? 0;
    const wpm = Math.max(1, Math.round((words / testDuration) * 60));
    const typedMinutes = Math.max(1, Math.round(1000 / wpm));
    return { typedMinutes, wpm, words };
  }, [input]);

  function start() {
    setInput("");
    setRemaining(testDuration);
    setStartedAt(Date.now());
    setState("running");
    window.requestAnimationFrame(() => inputRef.current?.focus());
  }

  function reset() {
    setState("ready");
    setInput("");
    setStartedAt(null);
    setRemaining(testDuration);
  }

  const timerLabel = state === "complete" ? "COMPLETE" : `${Math.ceil(remaining).toString().padStart(2, "0")} SEC`;

  return (
    <div className="mt-[68px] min-h-[408px] border border-typing-line bg-typing-panel p-6 max-[520px]:mt-[46px] max-[520px]:min-h-[390px] max-[520px]:p-4">
      <div className="flex items-center justify-between font-mono text-[11px] font-semibold text-demo-muted tabular-nums">
        <span>YOUR TYPING PACE</span>
        <span>{timerLabel}</span>
      </div>
      <p className="mx-auto mt-[74px] mb-8 max-w-[830px] text-center text-[28px] leading-[1.35] max-[520px]:mt-[52px] max-[520px]:text-[22px]">{testCopy}</p>
      <textarea
        aria-label="Type the test passage"
        className="mx-auto block min-h-[86px] w-full max-w-[830px] resize-none border-0 border-b border-typing-input bg-transparent text-lg leading-[1.5] text-paper outline-0 placeholder:text-typing-placeholder disabled:cursor-default max-[520px]:min-h-[102px] max-[520px]:text-base"
        ref={inputRef}
        value={input}
        onChange={(event) => setInput(event.target.value)}
        disabled={state !== "running"}
        placeholder={state === "ready" ? "Start the test when you are ready." : "Type the passage above..."}
      />
      <div className="mt-[34px] flex items-center justify-between font-mono text-[11px] font-semibold text-demo-muted tabular-nums max-[520px]:flex-col max-[520px]:items-start max-[520px]:gap-[18px]">
        {state === "ready" && <button className="min-h-11 cursor-pointer border border-signal bg-signal px-4 text-paper hover:bg-paper hover:text-ink" type="button" onClick={start}>Start 15 second test</button>}
        {state === "running" && <span className="inline-flex items-center gap-2 text-signal"><i className="block size-2 bg-signal animate-[status-pulse_1.2s_ease-in-out_infinite]" /> YOUR TIME IS RUNNING</span>}
        {state === "complete" && <button className="min-h-11 cursor-pointer border border-signal bg-signal px-4 text-paper hover:bg-paper hover:text-ink" type="button" onClick={reset}>Try again</button>}
        <span>{input.length} CHARACTERS</span>
      </div>
      {state === "complete" && (
        <div className="mx-auto mt-9 max-w-[830px] border-t border-typing-line pt-6 text-center" role="status">
          <p className="mb-2 text-base leading-[1.5] text-typing-muted"><strong>{metrics.wpm} WPM.</strong> At this pace, a 1,000-word draft asks for about {metrics.typedMinutes} minutes of typing.</p>
          <p className="m-0 text-base leading-[1.5] text-signal">A one-time Flint purchase turns that repeating typing cost into a voice-first workflow.</p>
        </div>
      )}
    </div>
  );
}
