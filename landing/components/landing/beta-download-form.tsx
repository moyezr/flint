"use client";

import Link from "next/link";
import { FormEvent, useEffect, useRef, useState } from "react";

type SubmissionState = "idle" | "submitting" | "error";

export function BetaDownloadForm() {
  const startedAt = useRef<number | null>(null);
  const [email, setEmail] = useState("");
  const [marketingConsent, setMarketingConsent] = useState(false);
  const [acceptedTerms, setAcceptedTerms] = useState(false);
  const [submissionState, setSubmissionState] = useState<SubmissionState>("idle");
  const [message, setMessage] = useState("");
  const [pendingDownloadURL, setPendingDownloadURL] = useState<string | null>(null);
  const [isInstallNoticeOpen, setIsInstallNoticeOpen] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pendingDownloadURL) {
      setIsInstallNoticeOpen(true);
      return;
    }
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
          acceptedTerms,
        }),
      });
      const body = (await response.json()) as { downloadURL?: string; error?: string };
      if (!response.ok || !body.downloadURL) {
        throw new Error(body.error || "The download could not be prepared.");
      }

      window.localStorage.setItem("flint-beta-email", email.trim());
      setPendingDownloadURL(body.downloadURL);
      setSubmissionState("idle");
      setMessage("Your download is ready. Review the required macOS first-launch steps.");
      setIsInstallNoticeOpen(true);
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

      <div className="flex items-start gap-3 text-[13px] leading-[1.45] text-muted">
        <input
          checked={acceptedTerms}
          className="mt-1 size-4 accent-signal"
          disabled={submissionState === "submitting"}
          id="beta-terms"
          onChange={(event) => setAcceptedTerms(event.target.checked)}
          required
          type="checkbox"
        />
        <span>
          <label className="cursor-pointer" htmlFor="beta-terms">I agree to the free public beta</label>{" "}
          <Link className="border-b border-current text-ink" href="/terms">terms</Link>.
        </span>
      </div>

      <button
        className="inline-flex min-h-12 items-center justify-center bg-signal px-5 font-mono text-[12px] font-semibold text-paper tabular-nums transition-colors hover:bg-ink disabled:cursor-wait disabled:opacity-70"
        disabled={submissionState === "submitting"}
        type="submit"
      >
        {submissionState === "submitting"
          ? "PREPARING DOWNLOAD…"
          : pendingDownloadURL
            ? "REVIEW FIRST-LAUNCH STEPS →"
            : "GET THE FREE BETA DMG ↓"}
      </button>

      <p
        aria-live="polite"
        className={`min-h-5 text-[13px] leading-[1.45] ${submissionState === "error" ? "text-red-700" : "text-muted"}`}
        role="status"
      >
        {message}
      </p>

      {isInstallNoticeOpen && pendingDownloadURL ? (
        <GatekeeperDownloadDialog
          downloadURL={pendingDownloadURL}
          onClose={() => {
            setIsInstallNoticeOpen(false);
            setMessage("Your download is ready. Review the first-launch steps to continue.");
          }}
          onDownload={() => {
            setIsInstallNoticeOpen(false);
            setPendingDownloadURL(null);
            setMessage("Download started. Keep the first-launch instructions handy.");
          }}
        />
      ) : null}
    </form>
  );
}

function GatekeeperDownloadDialog({
  downloadURL,
  onClose,
  onDownload,
}: {
  downloadURL: string;
  onClose: () => void;
  onDownload: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);

  useEffect(() => {
    previousFocusRef.current = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const focusFrame = window.requestAnimationFrame(() => dialogRef.current?.focus());

    function handleKeyDown(event: KeyboardEvent) {
      if (event.key === "Escape") {
        event.preventDefault();
        onClose();
        return;
      }
      if (event.key !== "Tab" || !dialogRef.current) {
        return;
      }

      const focusable = Array.from(
        dialogRef.current.querySelectorAll<HTMLElement>(
          'a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])',
        ),
      );
      const first = focusable.at(0);
      const last = focusable.at(-1);
      if (!first || !last) {
        return;
      }
      if (event.shiftKey && (document.activeElement === first || document.activeElement === dialogRef.current)) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === dialogRef.current) {
        event.preventDefault();
        first.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }

    document.addEventListener("keydown", handleKeyDown);
    return () => {
      window.cancelAnimationFrame(focusFrame);
      document.removeEventListener("keydown", handleKeyDown);
      document.body.style.overflow = previousOverflow;
      previousFocusRef.current?.focus();
    };
  }, [onClose]);

  return (
    <div className="fixed inset-0 z-[100] overflow-y-auto bg-black/70 p-4 sm:p-8">
      <div className="flex min-h-full items-center justify-center">
        <div
          aria-describedby="gatekeeper-description"
          aria-labelledby="gatekeeper-title"
          aria-modal="true"
          className="relative w-full max-w-[680px] border border-line bg-paper p-6 shadow-2xl outline-none sm:p-9"
          ref={dialogRef}
          role="dialog"
          tabIndex={-1}
        >
          <button
            aria-label="Close first-launch instructions"
            className="absolute top-4 right-4 flex size-10 items-center justify-center border border-line font-mono text-xl text-muted hover:border-signal hover:text-ink"
            onClick={onClose}
            type="button"
          >
            ×
          </button>

          <p className="mb-5 font-mono text-[11px] font-semibold text-signal">BEFORE YOU DOWNLOAD</p>
          <h2 className="pr-12 text-[38px] leading-[1.02] font-semibold sm:text-[48px]" id="gatekeeper-title">
            Expect a macOS warning.
          </h2>
          <p className="mt-6 text-[16px] leading-[1.7] text-muted" id="gatekeeper-description">
            Flint is an independent, unnotarized public beta. The first time you open it, macOS will say Apple could not verify Flint. <strong className="font-semibold text-ink">This warning does not mean macOS found malware.</strong> It means this beta has not been verified through Apple&apos;s paid developer and notarization process.
          </p>

          <div className="mt-7 border border-signal bg-[color-mix(in_srgb,var(--color-signal)_8%,var(--color-paper))] p-5">
            <p className="font-mono text-[11px] font-semibold text-signal">WHEN “FLINT NOT OPENED” APPEARS</p>
            <ol className="mt-4 grid gap-3 pl-5 text-[14px] leading-[1.6] text-ink">
              <li>Click <strong>Done</strong>—do not move Flint to Trash.</li>
              <li>Open <strong>System Settings → Privacy &amp; Security</strong>.</li>
              <li>Scroll to Security and click <strong>Open Anyway</strong> for Flint.</li>
              <li>Enter your Mac password, confirm <strong>Open</strong>, then complete Flint&apos;s permission setup.</li>
            </ol>
          </div>

          <div className="mt-7 flex flex-col gap-3 sm:flex-row sm:items-center">
            <a
              className="inline-flex min-h-12 items-center justify-center bg-signal px-5 text-center font-mono text-[12px] font-semibold text-paper hover:bg-ink"
              href={downloadURL}
              onClick={onDownload}
            >
              I UNDERSTAND — DOWNLOAD DMG ↓
            </a>
            <Link className="inline-flex min-h-12 items-center justify-center border border-line px-5 font-mono text-[12px] font-semibold text-ink hover:border-signal" href="/beta" rel="noreferrer" target="_blank">
              FULL INSTALL GUIDE →
            </Link>
          </div>
        </div>
      </div>
    </div>
  );
}
