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
          Flint currently requires an Apple Silicon Mac with macOS {release.minimumSystemVersion} or newer. This beta does not include an Intel executable. It is distributed directly and is not yet Apple-notarized.
        </p>

        <aside className="mt-10 border border-signal bg-[color-mix(in_srgb,var(--color-signal)_8%,var(--color-paper))] p-6" aria-labelledby="gatekeeper-warning-heading">
          <p className="font-mono text-[11px] font-semibold text-signal">EXPECTED FIRST-LAUNCH WARNING</p>
          <h2 className={`${spaceGrotesk.className} mt-3 text-2xl font-semibold`} id="gatekeeper-warning-heading">
            macOS will initially block this beta.
          </h2>
          <p className="mt-3 leading-[1.7] text-muted">
            You will see “Flint Not Opened” because this independent beta has not been verified through Apple&apos;s paid developer and notarization process. This warning does not mean macOS found malware. Follow the Open Anyway steps below before Flint can launch and request its normal permissions.
          </p>
        </aside>

        <section className="mt-16 border-t border-line pt-9" aria-labelledby="download-heading">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`} id="download-heading">1. Download the beta</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            Use the download form on the home page and enter the six-digit code sent to your email. The verified download link is short-lived, and the DMG itself is versioned so published builds are never silently replaced.
          </p>
          <Link className="mt-6 inline-flex min-h-12 items-center bg-signal px-5 font-mono text-[12px] font-semibold text-paper" href="/#download">
            GO TO DOWNLOAD ↓
          </Link>
        </section>

        <section className="mt-14 border-t border-line pt-9" aria-labelledby="install-heading">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`} id="install-heading">2. Approve the first launch</h2>
          <ol className="mt-5 grid gap-4 pl-5 leading-[1.7] text-muted">
            <li>Open the DMG and drag Flint into your Applications folder.</li>
            <li>Open Flint once. When “Flint Not Opened” appears, click Done—do not move Flint to Trash.</li>
            <li>Open System Settings → Privacy &amp; Security, scroll to Security, and click Open Anyway for Flint.</li>
            <li>Enter your Mac password and confirm Open. Flint can then launch and request its normal permissions.</li>
          </ol>
          <p className="mt-5 text-sm leading-[1.7] text-muted">
            Open Anyway is available for a limited time after the blocked launch attempt. If it is missing, try opening Flint once more and return to Privacy &amp; Security.
          </p>
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

        <section className="mt-14 border-t border-line pt-9" aria-labelledby="uninstall-heading">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`} id="uninstall-heading">Remove Flint and its models</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            Before removing the app, open Flint from the menu bar, choose Privacy, then select Uninstall Flint. Flint deletes downloaded speech models and its other local data, disables Launch at Login, moves Flint.app to Trash, and quits.
          </p>
          <p className="mt-4 leading-[1.7] text-muted">
            Dragging Flint.app directly to Trash cannot notify the running app or remove its files from your Library folder. If you already removed Flint manually, open Finder → Go → Go to Folder and enter <code className="font-mono text-sm text-ink">~/Library/Application Support/Flint</code>, then move that Flint folder to Trash to reclaim the model space.
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
          Need help? Visit <Link className="border-b border-current text-ink" href="/support">Support</Link> or email <a className="border-b border-current text-ink" href="mailto:moyezrabbani.work@gmail.com?subject=Flint%20beta%20support">moyezrabbani.work@gmail.com</a>.
        </p>
      </article>
    </main>
  );
}
