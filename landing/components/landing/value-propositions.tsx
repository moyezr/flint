import { spaceGrotesk } from "@/lib/fonts";
import { SectionHeading } from "./section-heading";

const valuePoints = [
  ["Time returns to you", "Say the first draft while the thought is still intact. Flint writes it in the field you already chose."],
  ["Your voice gets clearer", "Turning a thought into a sentence out loud is a small practice. Over time, you hear what is worth saying."],
  ["The work stays yours", "Audio is transcribed on your Mac. Your words never need to become someone else’s training data."],
];

export function ValuePropositions() {
  return (
    <section className="bg-paper py-36 max-[840px]:py-24" aria-labelledby="value-title">
      <div className="relative z-10">
        <SectionHeading eyebrow="THE BETTER DEFAULT" titleId="value-title" title={<>You have better things<br />to do than type everything.</>} />
        <div className="mx-auto mt-[70px] grid w-[min(100%-48px,1180px)] grid-cols-3 gap-14 max-[840px]:w-[min(100%-36px,1180px)] max-[840px]:grid-cols-1 max-[840px]:gap-[34px] max-[520px]:w-[min(100%-28px,1180px)]">
          {valuePoints.map(([title, detail]) => (
            <article className="flex min-h-[288px] flex-col items-center px-[18px] pt-3 text-center max-[840px]:min-h-[230px]" key={title}>
              <span className="mb-[34px] grid size-12 place-items-center rounded-full border border-signal shadow-[0_0_0_7px_var(--color-paper),0_0_0_8px_color-mix(in_srgb,var(--color-signal)_40%,var(--color-paper))]" aria-hidden="true">
                <i className="block size-[7px] rounded-full bg-signal" />
              </span>
              <h3 className={`${spaceGrotesk.className} mb-[13px] text-[29px] leading-none font-semibold`}>{title}</h3>
              <p className="m-0 max-w-[290px] text-[15px] leading-[1.55] text-muted">{detail}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
