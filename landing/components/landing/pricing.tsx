import { spaceGrotesk } from "@/lib/fonts";
import Link from "next/link";

import { BetaDownloadForm } from "./beta-download-form";
import { SectionHeading } from "./section-heading";

const planDetails = [
  "Local transcription on your Mac",
  "Push to talk at any cursor",
  "Fast, balanced, or accurate models",
  "Private vocabulary and correction learning",
  "Free while Flint is in public beta",
];

export function BetaDownload() {
  return (
    <section className="bg-paper py-36 max-[840px]:py-24" id="download" aria-labelledby="download-title">
      <div className="relative z-10 mx-auto grid w-[min(100%-48px,1180px)] grid-cols-2 items-center gap-[98px] max-[840px]:w-[min(100%-36px,1180px)] max-[840px]:grid-cols-1 max-[840px]:gap-[52px] max-[520px]:w-[min(100%-28px,1180px)]">
        <div className="max-[840px]:text-center">
          <SectionHeading
            align="left"
            eyebrow="PUBLIC BETA"
            titleId="download-title"
            title={<>Use Flint today.<br />Help shape what ships.</>}
            description="Enter your email to download the current Mac beta. Flint remains local after its speech model is ready, and beta feedback will guide the paid release."
          />
          <p className="mt-7 text-[13px] leading-[1.6] text-muted">
            Requires an Apple Silicon Mac with macOS 14 or newer. This early beta is not yet Apple-notarized, so first launch requires a one-time Gatekeeper approval. Read the{" "}
            <Link className="border-b border-current text-ink hover:text-signal" href="/beta">installation guide</Link>.
          </p>
        </div>
        <div className="min-h-[520px] border border-signal bg-paper p-7 max-[520px]:min-h-0">
          <p className="mb-8 font-mono text-[11px] font-semibold tabular-nums">FLINT FOR MAC / 0.1 BETA</p>
          <p className={`${spaceGrotesk.className} mb-8 text-[52px] font-bold text-signal max-[520px]:text-[42px]`}>FREE BETA</p>
          <BetaDownloadForm />
          <ul className="m-0 list-none border-t border-[color-mix(in_srgb,var(--color-signal)_50%,var(--color-line))] p-0">
            {planDetails.map((detail) => <li className="border-b border-line py-3 text-[15px]" key={detail}>{detail}</li>)}
          </ul>
          <p className="mt-6 mb-0 text-[13px] leading-[1.45] text-muted">
            Your email is used to provide beta access and essential release information. Optional product updates require the checkbox above. See the{" "}
            <Link className="border-b border-current text-ink hover:text-signal" href="/privacy">privacy policy</Link> and <Link className="border-b border-current text-ink hover:text-signal" href="/terms">beta terms</Link>.
          </p>
        </div>
      </div>
    </section>
  );
}
