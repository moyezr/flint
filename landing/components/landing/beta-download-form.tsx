"use client";

import { FormEvent, useRef, useState } from "react";

type SubmissionState = "idle" | "submitting" | "error";

export function BetaDownloadForm() {
  const startedAt = useRef<number | null>(null);
  const [email, setEmail] = useState("");
  const [marketingConsent, setMarketingConsent] = useState(false);
  const [submissionState, setSubmissionState] = useState<SubmissionState>("idle");
  const [message, setMessage] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (submissionState === "submitting") {
      return;
    }

    setSubmissionState("submitting");
    setMessage("Preparing your download…");

    const form = new FormData(event.currentTarget);
    try {
      const response = await fetch("/api/beta-signups", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          email,
          marketingConsent,
          source: "landing-download",
          website: form.get("website")?.toString() ?? "",
          startedAt: startedAt.current ?? Date.now() - 1_000,
        }),
      });
      const body = (await response.json()) as { downloadURL?: string; error?: string };
      if (!response.ok || !body.downloadURL) {
        throw new Error(body.error || "The download could not be prepared.");
      }

      window.localStorage.setItem("flint-beta-email", email.trim());
      window.location.assign(body.downloadURL);
    } catch (error) {
      startedAt.current = Date.now() - 1_000;
      setSubmissionState("error");
      setMessage(error instanceof Error ? error.message : "The download could not be prepared.");
    }
  }

  return (
    <form className="grid gap-4" onSubmit={submit}>
      <div>
        <label className="mb-2 block font-mono text-[11px] font-semibold tabular-nums" htmlFor="beta-email">
          YOUR EMAIL
        </label>
        <input
          autoComplete="email"
          className="min-h-12 w-full border border-line bg-paper px-4 text-base text-ink outline-none transition-colors placeholder:text-muted focus:border-signal"
          disabled={submissionState === "submitting"}
          id="beta-email"
          maxLength={320}
          name="email"
          onChange={(event) => {
            startedAt.current ??= Date.now();
            setEmail(event.target.value);
          }}
          onFocus={() => {
            startedAt.current ??= Date.now();
          }}
          placeholder="you@example.com"
          required
          type="email"
          value={email}
        />
      </div>

      <div aria-hidden="true" className="absolute -left-[10000px] h-px w-px overflow-hidden">
        <label htmlFor="beta-website">Website</label>
        <input autoComplete="off" id="beta-website" name="website" tabIndex={-1} type="text" />
      </div>

      <label className="flex cursor-pointer items-start gap-3 text-[13px] leading-[1.45] text-muted">
        <input
          checked={marketingConsent}
          className="mt-1 size-4 accent-signal"
          disabled={submissionState === "submitting"}
          onChange={(event) => setMarketingConsent(event.target.checked)}
          type="checkbox"
        />
        <span>Email me occasional Flint product updates. This is optional.</span>
      </label>

      <button
        className="inline-flex min-h-12 items-center justify-center bg-signal px-5 font-mono text-[12px] font-semibold text-paper tabular-nums transition-colors hover:bg-ink disabled:cursor-wait disabled:opacity-70"
        disabled={submissionState === "submitting"}
        type="submit"
      >
        {submissionState === "submitting" ? "PREPARING DOWNLOAD…" : "GET THE FREE BETA DMG ↓"}
      </button>

      <p
        aria-live="polite"
        className={`min-h-5 text-[13px] leading-[1.45] ${submissionState === "error" ? "text-red-700" : "text-muted"}`}
        role="status"
      >
        {message}
      </p>
    </form>
  );
}
