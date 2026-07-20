import type { Metadata } from "next";
import Link from "next/link";

import { spaceGrotesk } from "@/lib/fonts";

const supportEmail = "moyezrabbani.work@gmail.com";

export const metadata: Metadata = {
  title: "Support",
  description: "Simple email support and troubleshooting for the Flint public beta.",
};

export default function SupportPage() {
  return (
    <main className="min-h-screen bg-paper px-6 py-16 text-ink">
      <article className="mx-auto max-w-[760px]">
        <Link className="font-mono text-[11px] font-semibold text-signal" href="/">← FLINT</Link>
        <p className="mt-16 mb-5 font-mono text-[11px] font-semibold text-signal">SUPPORT / PUBLIC BETA</p>
        <h1 className={`${spaceGrotesk.className} text-[64px] leading-[0.95] font-semibold max-[520px]:text-[44px]`}>
          Email the developer.
        </h1>
        <p className="mt-7 text-lg leading-[1.65] text-muted">
          Flint is currently supported directly by its independent developer. There is no ticket portal or account to manage.
        </p>

        <section className="mt-16 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Contact</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            Email <a className="border-b border-current text-ink" href={`mailto:${supportEmail}?subject=Flint%20beta%20support`}>{supportEmail}</a>. Please do not attach private recordings, transcripts, license secrets, database credentials, or other sensitive material.
          </p>
        </section>

        <section className="mt-14 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Helpful details</h2>
          <p className="mt-4 leading-[1.7] text-muted">For a reproducible problem, include:</p>
          <ul className="mt-5 grid gap-3 pl-5 leading-[1.7] text-muted">
            <li>Flint version and macOS version.</li>
            <li>Mac model and Apple chip.</li>
            <li>The target application and its version.</li>
            <li>What you expected, what happened, and whether it repeats.</li>
            <li>Whether Microphone, Accessibility, and Input Monitoring are enabled.</li>
          </ul>
        </section>

        <section className="mt-14 border-t border-line pt-9">
          <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>Install and privacy</h2>
          <p className="mt-4 leading-[1.7] text-muted">
            See the <Link className="border-b border-current text-ink" href="/beta">installation guide</Link> for Gatekeeper and setup steps. See the <Link className="border-b border-current text-ink" href="/privacy">Privacy Policy</Link> for local data controls and email deletion requests.
          </p>
        </section>
      </article>
    </main>
  );
}
