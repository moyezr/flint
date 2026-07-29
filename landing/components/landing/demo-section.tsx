import { lazy, Suspense } from "react";

import { SectionHeading } from "./section-heading";

const DemoVideo = lazy(() => import("./demo-video"));

function VideoSkeleton() {
  return (
    <div
      className="relative aspect-video w-full overflow-hidden rounded-xl border border-line bg-paper"
      role="status"
      aria-busy="true"
      aria-live="polite"
    >
      <div
        className="absolute inset-0 opacity-40"
        style={{
          backgroundImage: "radial-gradient(circle, rgba(255, 79, 31, 0.45) 1.25px, transparent 1.25px)",
          backgroundSize: "18px 18px",
        }}
        aria-hidden="true"
      />
      <div className="relative flex h-full flex-col justify-between p-[clamp(18px,3vw,40px)]" aria-hidden="true">
        <div className="flex items-center justify-between font-mono text-[10px] font-semibold tracking-[0.08em] text-muted tabular-nums sm:text-[11px]">
          <span className="text-ink">FLINT<span className="text-signal">/</span></span>
          <span className="inline-flex items-center gap-2">
            <i className="size-2 animate-[status-pulse_1.2s_ease-in-out_infinite] bg-signal" />
            LOADING DEMO
          </span>
        </div>

        <div className="mx-auto grid w-[min(76%,620px)] justify-items-center gap-[clamp(18px,3vw,34px)]">
          <div className="grid size-[clamp(52px,8vw,82px)] place-items-center border border-deep bg-deep">
            <span className="ml-1 block h-0 w-0 border-y-[10px] border-l-[16px] border-y-transparent border-l-signal sm:border-y-[13px] sm:border-l-[21px]" />
          </div>
          <div className="grid w-full gap-3">
            <span className="h-3 w-full animate-pulse bg-mist" />
            <span className="h-3 w-[72%] animate-pulse bg-mist" />
          </div>
        </div>

        <div className="h-1 w-full overflow-hidden bg-mist">
          <span className="block h-full w-1/3 animate-pulse bg-signal" />
        </div>
      </div>
      <span className="sr-only">Loading Flint demo video</span>
    </div>
  );
}

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
          <Suspense fallback={<VideoSkeleton />}>
            <DemoVideo />
          </Suspense>
        </div>
      </div>
    </section>
  );
}
