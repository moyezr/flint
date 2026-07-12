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
    <div className="typing-tool">
      <div className="typing-tool-topline">
        <span>YOUR TYPING PACE</span>
        <span>{timerLabel}</span>
      </div>
      <p className="typing-prompt">{testCopy}</p>
      <textarea
        aria-label="Type the test passage"
        ref={inputRef}
        value={input}
        onChange={(event) => setInput(event.target.value)}
        disabled={state !== "running"}
        placeholder={state === "ready" ? "Start the test when you are ready." : "Type the passage above..."}
      />
      <div className="typing-tool-footer">
        {state === "ready" && <button type="button" onClick={start}>Start 15 second test</button>}
        {state === "running" && <span className="typing-live"><i /> YOUR TIME IS RUNNING</span>}
        {state === "complete" && <button type="button" onClick={reset}>Try again</button>}
        <span>{input.length} CHARACTERS</span>
      </div>
      {state === "complete" && (
        <div className="typing-result" role="status">
          <p><strong>{metrics.wpm} WPM.</strong> At this pace, a 1,000-word draft asks for about {metrics.typedMinutes} minutes of typing.</p>
          <p>A one-time Flint purchase turns that repeating typing cost into a voice-first workflow.</p>
        </div>
      )}
    </div>
  );
}
