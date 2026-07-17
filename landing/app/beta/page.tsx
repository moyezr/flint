import type { Metadata } from "next";
import Link from "next/link";

import { latestRelease } from "@/app/lib/beta/latest-release";
import { spaceGrotesk } from "@/lib/fonts";

export const metadata: Metadata = {
  title: "Install the Flint Beta",
  description: "Download, install, and update the Flint public beta for macOS.",
};

export default function BetaGuidePage() {
  const release = latestRelease();

  return (
    <main className="min-h-screen bg-paper px-6 py-16 text-ink">
      <article className="mx-auto max-w-[760px]">
        <Link className="font-mono text-[11px] font-semibold text-signal" href="/">← FLINT</Link>
        <p className="mt-16 mb-5 font-mono text-[11px] font-semibold text-signal">PUBLIC BETA / {release.version}</p>
        <h1 className={`${spaceGrotesk.className} text-[64px] leading-[0.95] font-semibold max-[520px]:text-[44px]`}>
          Install Flint on your Mac.
        </h1>
        <p className="mt-7 text-lg leading-[1.65] text-muted">
          Flint currently requires macOS {release.minimumSystemVersion} or newer. The beta is distributed directly and is not yet Apple-notarized.
        </p>

        <section className="mt-16 border-t border-line pt-9" aria-labelledby="download-heading">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`} id="download-heading">1. Download the beta</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            Use the email gate on the home page. Your download link is short-lived, and the DMG itself is versioned so published builds are never silently replaced.
          </p>
          <Link className="mt-6 inline-flex min-h-12 items-center bg-signal px-5 font-mono text-[12px] font-semibold text-paper" href="/#download">
            GO TO DOWNLOAD ↓
          </Link>
        </section>

        <section className="mt-14 border-t border-line pt-9" aria-labelledby="install-heading">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`} id="install-heading">2. Approve the first launch</h2>
          <ol className="mt-5 grid gap-4 pl-5 leading-[1.7] text-muted">
            <li>Open the DMG and drag Flint into your Applications folder.</li>
            <li>Control-click Flint in Applications and choose Open.</li>
            <li>If macOS still blocks it, open System Settings → Privacy &amp; Security and choose Open Anyway for Flint.</li>
            <li>Confirm that you want to open Flint. Future launches of that build should open normally.</li>
          </ol>
        </section>

        <section className="mt-14 border-t border-line pt-9" aria-labelledby="setup-heading">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`} id="setup-heading">3. Complete local setup</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            Onboarding requests Microphone, Accessibility, and Input Monitoring access, then downloads your selected speech model. Once the model is ready, dictation and personalization work without an internet connection.
          </p>
          <p className="mt-4 leading-[1.7] text-muted">
            You can run setup again at any time from the menu bar: Flint → Run Onboarding Again. Existing models, vocabulary, and permissions are preserved.
          </p>
        </section>

        <section className="mt-14 border-t border-line pt-9" aria-labelledby="release-heading">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`} id="release-heading">What is in {release.version}</h2>
          <ul className="mt-5 grid gap-3 pl-5 leading-[1.7] text-muted">
            {release.notes.map((note) => <li key={note}>{note}</li>)}
          </ul>
          <p className="mt-6 break-all font-mono text-[11px] leading-[1.6] text-muted">SHA-256: {release.sha256}</p>
        </section>

        <p className="mt-16 border-t border-line pt-8 text-sm leading-[1.7] text-muted">
          Need help? Email <a className="border-b border-current text-ink" href="mailto:moyezrabbani.work@gmail.com?subject=Flint%20beta%20support">moyezrabbani.work@gmail.com</a>.
        </p>
      </article>
    </main>
  );
}
