import type { Metadata } from "next";
import Link from "next/link";

import { spaceGrotesk } from "@/lib/fonts";

export const metadata: Metadata = {
  title: "Public Beta Terms",
  description: "The terms for downloading and using the free Flint public beta.",
};

export default function TermsPage() {
  return (
    <main className="min-h-screen bg-paper px-6 py-16 text-ink">
      <article className="mx-auto max-w-[760px]">
        <Link className="font-mono text-[11px] font-semibold text-signal" href="/">← FLINT</Link>
        <p className="mt-16 mb-5 font-mono text-[11px] font-semibold text-signal">TERMS / PUBLIC BETA</p>
        <h1 className={`${spaceGrotesk.className} text-[64px] leading-[0.95] font-semibold max-[520px]:text-[44px]`}>
          Free public beta terms.
        </h1>
        <p className="mt-7 text-lg leading-[1.65] text-muted">Effective: July 20, 2026.</p>

        <LegalSection title="Agreement">
          By selecting the terms checkbox, downloading, installing, or using Flint, you agree to these terms. Flint is provided by Moyez Rabbani as an independent developer. If you do not agree, do not download or use the beta.
        </LegalSection>

        <LegalSection title="Beta license">
          You receive a limited, personal, non-exclusive, non-transferable, revocable license to install and use the free Flint public beta on your own compatible Mac for evaluation and feedback. Flint and its original code, design, name, and assets remain proprietary. Third-party components remain governed by their own licenses, listed in the <Link className="border-b border-current text-ink" href="/third-party-notices">Third-Party Notices</Link>.
        </LegalSection>

        <LegalSection title="Early software">
          This is unfinished beta software. Features may change, fail, lose compatibility, or be withdrawn. You are responsible for reviewing important dictated text before relying on or sending it. Do not use Flint as the sole way to create or preserve safety-critical, medical, legal, financial, or emergency information.
        </LegalSection>

        <LegalSection title="Permissions and local processing">
          Flint needs macOS Microphone and Accessibility permissions for recording, shortcut handling, and text insertion. Accessibility covers both the shortcut listener and insertion, so Flint does not separately require Input Monitoring. Speech models may require a network download before first use. Dictation processing is performed on your Mac. Data handling is described in the <Link className="border-b border-current text-ink" href="/privacy">Privacy Policy</Link>.
        </LegalSection>

        <LegalSection title="Acceptable use">
          You may not use Flint unlawfully, interfere with the download or release services, bypass reasonable access or abuse controls, distribute altered builds as Flint, or use Flint&apos;s name or assets to imply endorsement. Restrictions apply only to the extent permitted by applicable law and do not limit rights granted by third-party open-source licenses.
        </LegalSection>

        <LegalSection title="Price and refunds">
          The public beta is provided without charge. No purchase is made and no refund applies. Any future paid version will have separate pricing and applicable purchase terms before payment is collected.
        </LegalSection>

        <LegalSection title="Updates and ending access">
          Flint may check for release information while online and may direct you to a newer build. You may stop using the beta at any time by quitting and uninstalling Flint. Beta access or distribution may be changed or ended, including for security, abuse, compatibility, or product reasons.
        </LegalSection>

        <LegalSection title="No warranty">
          To the maximum extent permitted by applicable law, the beta is provided “as is” and “as available,” without warranties of uninterrupted operation, accuracy, fitness for a particular purpose, merchantability, or non-infringement. Nothing in these terms excludes a warranty or consumer right that cannot legally be excluded.
        </LegalSection>

        <LegalSection title="Liability">
          To the maximum extent permitted by applicable law, Flint&apos;s developer is not liable for indirect, incidental, special, consequential, or exemplary losses arising from the free beta, including lost text, data, opportunity, or productivity. Nothing in these terms excludes liability that cannot legally be excluded or limited.
        </LegalSection>

        <LegalSection title="Changes and contact">
          Material changes will be reflected by a new effective date and terms version. A new acceptance may be requested before another download. Questions and beta support can be sent to <a className="border-b border-current text-ink" href="mailto:moyezrabbani.work@gmail.com?subject=Flint%20beta%20terms">moyezrabbani.work@gmail.com</a>.
        </LegalSection>

        <p className="mt-14 border-t border-line pt-8 text-sm leading-[1.7] text-muted">
          These terms are a practical beta baseline, not a substitute for jurisdiction-specific legal review before accepting payment.
        </p>
      </article>
    </main>
  );
}

function LegalSection({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="mt-14 border-t border-line pt-9">
      <h2 className={`${spaceGrotesk.className} text-3xl font-semibold`}>{title}</h2>
      <p className="mt-4 leading-[1.7] text-muted">{children}</p>
    </section>
  );
}
