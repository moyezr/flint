type DemoVideoProps = {
  className?: string;
  autoPlay?: boolean;
};

export default function DemoVideo({ className, autoPlay = false }: DemoVideoProps) {
  const src = "https://www.youtube.com/embed/YHKTbN2mvGU";

  return (
    <div className={className}>
      <iframe
        className="aspect-video w-full rounded-xl shadow-sm"
        aria-label="Flint demo video"
        src={`${src}?autoplay=${autoPlay ? 1 : 0}&mute=${autoPlay ? 1 : 0}&controls=1&playsinline=1`}
        title="Flint demo video"
        allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
        allowFullScreen
      />
    </div>
  );
}
