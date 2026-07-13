import Image from "next/image";

const meterHeights = [24, 40, 48, 30, 64, 36, 52, 28, 58, 42, 64, 34, 50, 26, 60, 38, 48];

export function DemoSurface() {
  return (
    <div className="relative flex min-h-[500px] flex-col justify-between overflow-hidden border border-deep bg-deep p-6 text-paper max-[840px]:min-h-[390px] max-[520px]:min-h-[320px] max-[520px]:p-4" role="img" aria-label="Flint dictation interface preview">
      <span className="absolute top-1/2 left-1/2 aspect-square w-[680px] -translate-x-1/2 -translate-y-1/2 rounded-full border border-demo-line" aria-hidden="true" />
      <span className="absolute top-1/2 left-1/2 aspect-square w-[430px] -translate-x-1/2 -translate-y-1/2 rounded-full border border-demo-line-strong" aria-hidden="true" />
      <div className="relative z-10 flex justify-between font-mono text-[11px] font-semibold text-demo-muted tabular-nums">
        <span>FLINT / RECORDING</span>
        <span>00:18</span>
      </div>
      <div className="relative z-10 grid justify-items-center gap-7">
        <Image className="h-24 w-24 object-contain max-[520px]:h-[72px] max-[520px]:w-[72px]" src="/flint-mark.png" alt="" width={96} height={96} priority />
        <div className="grid h-[76px] w-[min(520px,78vw)] grid-cols-[repeat(17,minmax(0,1fr))] items-center gap-2 max-[520px]:gap-1">
          {meterHeights.map((height, index) => (
            <span
              className="block origin-center bg-signal animate-[demo-level_1.8s_ease-in-out_infinite_alternate]"
              key={index}
              style={{ height, animationDelay: `${(index % 5) * -0.2}s` }}
            />
          ))}
        </div>
      </div>
      <div className="relative z-10 flex justify-between font-mono text-[11px] font-semibold text-demo-muted tabular-nums">
        <span className="inline-flex items-center gap-2"><b className="block size-[7px] bg-signal animate-[status-pulse_1.4s_ease-in-out_infinite]" /> LOCAL PROCESSING</span>
        <span>RIGHT OPTION</span>
      </div>
    </div>
  );
}
