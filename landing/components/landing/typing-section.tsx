import { TypingTest } from "@/components/typing-test";
import { SectionHeading } from "./section-heading";

export function TypingSection() {
  return (
    <section className="bg-deep py-36 text-paper max-[840px]:py-24" id="typing-test" aria-labelledby="typing-title">
      <SectionHeading
        eyebrow="A 15-SECOND REALITY CHECK"
        titleId="typing-title"
        inverse
        title={<>You might not need Flint.<br /><span className="text-signal">Let your fingers decide.</span></>}
        description="Type one short passage. See how much time your current pace asks from you every day."
      />
      <div className="mx-auto w-[min(100%-48px,1180px)] max-[840px]:w-[min(100%-36px,1180px)] max-[520px]:w-[min(100%-28px,1180px)]"><TypingTest /></div>
    </section>
  );
}
