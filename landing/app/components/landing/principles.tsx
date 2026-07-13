import { spaceGrotesk } from "../../fonts";
import { SectionHeading } from "./section-heading";

const principles = [
  ["LOCAL", "Offline, by default.", "Your audio and transcription stay on your Mac after the model is ready."],
  ["FOCUSED", "One gesture.", "No workspace, no new editor, no context switch. Just your current cursor."],
  ["OWNED", "One-time investment.", "Buy the tool, keep the workflow. There is no monthly meter on your words."],
];

export function Principles() {
  return (
    <section className="bg-mist py-36 max-[840px]:py-24" aria-labelledby="principles-title">
      <div className="mx-auto w-[min(100%-48px,1180px)] max-[840px]:w-[min(100%-36px,1180px)] max-[520px]:w-[min(100%-28px,1180px)]">
        <SectionHeading eyebrow="WHY IT FEELS DIFFERENT" titleId="principles-title" title={<>Built to disappear<br />into your day.</>} />
        <div className="mt-[70px] grid grid-cols-3 max-[840px]:grid-cols-1">
          {principles.map(([label, title, detail], index) => (
            <article className={`min-h-[280px] border-t border-b border-line p-7 ${index > 0 ? "border-l border-l-line max-[840px]:border-l-0" : ""} max-[840px]:min-h-[236px]`} key={label}>
              <span className="font-mono text-[11px] font-semibold text-signal tabular-nums">{label}</span>
              <h3 className={`${spaceGrotesk.className} mt-[72px] mb-[14px] text-[31px] leading-none font-semibold max-[840px]:mt-11`}>{title}</h3>
              <p className="m-0 text-[15px] leading-[1.55] text-muted">{detail}</p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}
