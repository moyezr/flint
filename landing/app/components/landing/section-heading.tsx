import type { ReactNode } from "react";

import { spaceGrotesk } from "../../fonts";

type SectionHeadingProps = {
  eyebrow: string;
  title: ReactNode;
  titleId?: string;
  description?: string;
  inverse?: boolean;
  align?: "center" | "left";
};

export function SectionHeading({ eyebrow, title, titleId, description, inverse = false, align = "center" }: SectionHeadingProps) {
  const centered = align === "center";
  const bodyColor = inverse ? "text-typing-muted" : "text-muted";

  const alignment = centered ? "mx-auto text-center" : "text-left max-[840px]:text-center";
  const descriptionAlignment = centered ? "mx-auto" : "max-[840px]:mx-auto";

  return (
    <div className={`max-w-[760px] ${alignment}`}>
      <p className="mb-[22px] font-mono text-[11px] font-semibold text-signal tabular-nums">{eyebrow}</p>
      <h2 className={`${spaceGrotesk.className} mb-[22px] text-[66px] leading-[0.95] font-semibold max-[840px]:text-[51px] max-[520px]:text-[42px] max-[520px]:leading-[0.98]`} id={titleId}>
        {title}
      </h2>
      {description ? (
        <p className={`max-w-[570px] text-[17px] leading-[1.6] max-[520px]:text-base ${bodyColor} ${descriptionAlignment}`}>
          {description}
        </p>
      ) : null}
    </div>
  );
}
