import DemoVideo from "./demo-video";
import { SectionHeading } from "./section-heading";

export function DemoSection() {
  return (
    <section className="py-36 max-[840px]:py-24" aria-labelledby="demo-title">
      <div className="relative z-10 mx-auto w-[min(100%-48px,1180px)] max-[840px]:w-[min(100%-36px,1180px)] max-[520px]:w-[min(100%-28px,1180px)]">
        <SectionHeading
          eyebrow="THE MOMENT IT CLICKS"
          titleId="demo-title"
          title={<>Your hands can stay<br />on the work.</>}
          description="Hold your shortcut. Speak. Release. Flint takes care of the space between thought and text."
        />
        <div className="mt-[68px] max-[520px]:mt-[46px]">
          <DemoVideo />
        </div>
      </div>
    </section>
  );
}
