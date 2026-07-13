import { spaceGrotesk } from "../../fonts";

export function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <span className={`${spaceGrotesk.className} inline-flex items-baseline text-[23px] leading-none font-bold ${compact ? "text-base" : ""}`}>
      FLINT<span className="text-signal" aria-hidden="true">/</span>
    </span>
  );
}
