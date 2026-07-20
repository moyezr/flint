import Link from "next/link";

import { spaceGrotesk } from "@/lib/fonts";
import { BrandMark } from "./brand-mark";

export function Hero() {
  return (
    <section className="relative isolate min-h-screen overflow-hidden" id="top" aria-labelledby="hero-title">
      {/* <WaveField /> */}
      <nav className="relative z-10 mx-auto flex h-[76px] w-[min(100%-48px,1180px)] items-center justify-between max-[840px]:w-[min(100%-36px,1180px)] max-[520px]:h-[68px] max-[520px]:w-[min(100%-28px,1180px)]" aria-label="Primary navigation">
        <Link href="#top" aria-label="Flint home"><BrandMark /></Link>
        <Link className="inline-flex min-h-10 items-center border border-signal bg-signal px-4 font-mono text-[11px] font-semibold text-paper tabular-nums transition-colors hover:bg-paper hover:text-signal max-[520px]:min-h-9 max-[520px]:px-3 max-[520px]:text-[10px]" href="/#download">DOWNLOAD BETA</Link>
      </nav>
      <div className="relative z-10 mx-auto max-w-[960px] pt-24 text-center max-[840px]:pt-32 max-[520px]:pt-[132px]">
        <p className="mb-[22px] font-mono text-[11px] font-semibold text-signal tabular-nums max-[520px]:text-[10px]">LOCAL DICTATION FOR MAC</p>
        <h1 className={`${spaceGrotesk.className} mb-[26px] text-[100px] leading-[0.91] font-semibold max-[840px]:text-[66px] max-[520px]:text-[49px] max-[520px]:leading-[0.95]`} id="hero-title">
          Your thoughts move fast.<br /><span className="text-signal">Your fingers don&apos;t.</span>
        </h1>
        <p className="mx-auto mb-[38px] max-w-[510px] text-lg leading-[1.55] text-muted max-[520px]:max-w-[330px] max-[520px]:text-base">
          Flint places your voice exactly where your cursor already is.
        </p>
        <div className="flex items-center justify-center gap-6 max-[520px]:flex-col max-[520px]:gap-4">
          <Link className="inline-flex min-h-12 items-center bg-signal px-6 font-mono text-[12px] font-semibold text-paper transition-colors hover:bg-ink" href="#download">
            DOWNLOAD FREE BETA ↓
          </Link>
          <Link className="inline-flex items-center gap-[9px] border-b border-current pb-[5px] font-mono text-[13px] font-medium hover:text-signal" href="#typing-test">
            See your typing gap <span aria-hidden="true">↓</span>
          </Link>
        </div>
      </div>
    </section>
  );
}
