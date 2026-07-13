import type { CSSProperties } from "react";

const waveBars = [
  28, 45, 64, 31, 73, 52, 87, 40, 59, 78, 44, 68, 35, 82, 55, 91, 46, 70, 34, 62, 84, 51,
  76, 38, 58, 86, 47, 67, 30, 80, 54, 72, 42, 89, 49, 64, 37, 77, 56, 33, 83, 45, 69, 52,
];

export function WaveField() {
  return (
    <div className="pointer-events-none absolute inset-x-0 top-[90px] bottom-[30px] z-0 overflow-hidden [contain:paint] max-[520px]:top-[68px] max-[520px]:bottom-6" aria-hidden="true">
      <div className="absolute top-[51%] left-1/2 grid h-[260px] w-[min(1120px,140vw)] -translate-x-1/2 -translate-y-1/2 grid-cols-[repeat(44,minmax(0,1fr))] items-center gap-2 opacity-25 max-[840px]:w-[150vw] max-[840px]:gap-[5px] max-[520px]:h-[190px] max-[520px]:gap-[3px]">
        {waveBars.map((height, index) => (
          <span
            className="block h-[var(--wave-height)] min-h-3 origin-center bg-signal animate-[wave-pulse_2.8s_ease-in-out_var(--wave-delay)_infinite_alternate]"
            key={index}
            style={
              {
                "--wave-height": `${height}%`,
                "--wave-delay": `${(index % 9) * -0.16}s`,
              } as CSSProperties
            }
          />
        ))}
      </div>
      <span className="absolute top-1/2 left-1/2 block aspect-square w-[min(920px,110vw)] -translate-x-1/2 -translate-y-1/2 rounded-full border border-line max-[520px]:w-[135vw]" />
      <span className="absolute top-1/2 left-1/2 block aspect-square w-[min(650px,80vw)] -translate-x-1/2 -translate-y-1/2 rounded-full border border-[color-mix(in_srgb,var(--color-signal)_44%,var(--color-line))] max-[520px]:w-[102vw]" />
    </div>
  );
}
