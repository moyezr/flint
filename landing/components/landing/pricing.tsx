import { spaceGrotesk } from "@/lib/fonts";
import { SectionHeading } from "./section-heading";

const planDetails = [
  "Local transcription on your Mac",
  "Push to talk at any cursor",
  "Fast, balanced, or accurate models",
  "Private vocabulary and cleanup modes",
  "One active Mac at a time",
];

export function Pricing() {
  return (
    <section className="bg-paper py-36 max-[840px]:py-24" id="pricing" aria-labelledby="pricing-title">
      <div className="mx-auto grid w-[min(100%-48px,1180px)] grid-cols-2 items-center gap-[98px] max-[840px]:w-[min(100%-36px,1180px)] max-[840px]:grid-cols-1 max-[840px]:gap-[52px] max-[520px]:w-[min(100%-28px,1180px)]">
        <div className="max-[840px]:text-center">
          <SectionHeading
            align="left"
            eyebrow="EARLY ACCESS"
            titleId="pricing-title"
            title={<>One purchase.<br />No recurring ask.</>}
            description="Flint is being prepared as a direct Mac download. Early access includes the full local dictation workflow and future product updates."
          />
        </div>
        <div className="min-h-[390px] border border-signal bg-paper p-7 max-[520px]:min-h-0">
          <p className="mb-[72px] font-mono text-[11px] font-semibold tabular-nums">FLINT FOR MAC</p>
          <p className={`${spaceGrotesk.className} mb-9 text-[52px] font-bold text-signal max-[520px]:text-[42px]`}>ONE-TIME</p>
          <ul className="m-0 list-none border-t border-[color-mix(in_srgb,var(--color-signal)_50%,var(--color-line))] p-0">
            {planDetails.map((detail) => <li className="border-b border-line py-3 text-[15px]" key={detail}>{detail}</li>)}
          </ul>
          <p className="mt-6 mb-0 text-[13px] leading-[1.45] text-muted">Personal adaptation is on the roadmap. It is not part of the current release.</p>
        </div>
      </div>
    </section>
  );
}
