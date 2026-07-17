import Link from "next/link";

import { BrandMark } from "./brand-mark";

export function Footer() {
  return (
    <footer className="mx-auto flex min-h-[74px] w-[min(100%-48px,1180px)] items-center justify-between bg-deep font-mono text-[11px] font-semibold text-demo-muted tabular-nums max-[840px]:w-[min(100%-36px,1180px)] max-[520px]:min-h-24 max-[520px]:w-[min(100%-28px,1180px)] max-[520px]:flex-col max-[520px]:items-start max-[520px]:justify-center max-[520px]:gap-[9px]">
      <span className="text-paper"><BrandMark compact /></span>
      <span className="flex items-center gap-5">
        <Link className="hover:text-signal" href="/beta">INSTALL</Link>
        <Link className="hover:text-signal" href="/privacy">PRIVACY</Link>
        <span>LOCAL FIRST / MACOS</span>
      </span>
    </footer>
  );
}
