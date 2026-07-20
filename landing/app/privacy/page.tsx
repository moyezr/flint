import type { Metadata } from "next";
import Link from "next/link";

import { spaceGrotesk } from "@/lib/fonts";

export const metadata: Metadata = {
  title: "Privacy",
  description: "How Flint handles local dictation data and beta download emails.",
};

export default function PrivacyPage() {
  return (
    <main className="min-h-screen bg-paper px-6 py-16 text-ink">
      <article className="mx-auto max-w-[760px]">
        <Link className="font-mono text-[11px] font-semibold text-signal" href="/">← FLINT</Link>
        <p className="mt-16 mb-5 font-mono text-[11px] font-semibold text-signal">PRIVACY / PUBLIC BETA</p>
        <h1 className={`${spaceGrotesk.className} text-[64px] leading-[0.95] font-semibold max-[520px]:text-[44px]`}>
          Your words stay yours.
        </h1>
        <p className="mt-7 text-lg leading-[1.65] text-muted">Last updated: July 17, 2026.</p>

        <section className="mt-16 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Dictation data</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            Flint records temporary audio only while you dictate and transcribes it on your Mac. Temporary recordings are deleted after transcription or cancellation. Flint does not upload audio, transcripts, vocabulary, or corrections to the website.
          </p>
        </section>

        <section className="mt-14 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Data stored on your Mac</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            Settings, downloaded speech models, explicit vocabulary, corrections, and optional history are stored locally. History is off by default. Flint provides controls to inspect and delete local data.
          </p>
        </section>

        <section className="mt-14 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Beta download emails</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            The website stores the email address you submit, the time you requested access, whether you separately opted into occasional product updates, and aggregate download timestamps and counts. It does not store your dictation content. Email records are used for beta access, essential release communication, support, and—only when selected—occasional product updates.
          </p>
        </section>

        <section className="mt-14 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Terms and abuse prevention</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            The website stores the version and time of your beta-terms acceptance. To protect the download service, it also keeps short-lived counters keyed by pseudonymous hashes derived from request addresses and email addresses. Raw addresses are not stored in the rate-limit table, and expired counters are deleted automatically.
          </p>
        </section>

        <section className="mt-14 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Update checks</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            Packaged beta builds may make a small request to Flint&apos;s release endpoint at most once per day while internet access is available. The request contains the installed app version through normal HTTP client behavior but contains no audio, transcripts, vocabulary, or corrections. Failed checks are ignored and never prevent dictation.
          </p>
        </section>

        <section className="mt-14 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Control and contact</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            You can ask to access or delete your beta email record, or unsubscribe from optional updates, by emailing <a className="border-b border-current text-ink" href="mailto:moyezrabbani.work@gmail.com?subject=Flint%20privacy">moyezrabbani.work@gmail.com</a>. Local application data can be removed from Flint&apos;s Privacy screen.
          </p>
        </section>
      </article>
    </main>
  );
}
