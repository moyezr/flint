import Link from "next/link";

import { spaceGrotesk } from "@/lib/fonts";
import { SectionHeading } from "./section-heading";

export function Contact() {
  return (
    <section className="bg-deep py-[138px] text-center text-paper max-[520px]:py-[98px]" aria-labelledby="contact-title">
      <div className="mx-auto w-[min(100%-48px,880px)] max-[840px]:w-[min(100%-36px,880px)] max-[520px]:w-[min(100%-28px,880px)]">
        <SectionHeading eyebrow="MAKE ROOM FOR THE THOUGHT" titleId="contact-title" title="Want Flint on your Mac?" />
        <Link className={`${spaceGrotesk.className} inline-flex items-baseline gap-3 border-b border-signal text-[31px] leading-[1.2] font-semibold text-signal hover:border-paper hover:text-paper max-[520px]:break-words max-[520px]:text-[21px]`} href="mailto:moyezrabbani.work@gmail.com?subject=Flint%20early%20access">
          moyezrabbani.work@gmail.com <span aria-hidden="true">↗</span>
        </Link>
        <p className="mt-[26px] text-[17px] leading-[1.6] text-demo-muted max-[520px]:text-base">Early access, questions, and feedback go directly to Moyez.</p>
      </div>
    </section>
  );
}
