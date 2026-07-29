type DemoVideoProps = {
  className?: string;
  autoPlay?: boolean;
};

export default function DemoVideo({ className, autoPlay = true }: DemoVideoProps) {
  const src = "https://ee7apxf8lxdpfnbh.public.blob.vercel-storage.com/flint%20demo";

  return (
    <div className={className}>
      <video
        className="w-full rounded-xl shadow-sm"
        aria-label="Flint demo video"
        autoPlay={autoPlay}
        controls
        muted
        playsInline
        preload="metadata"
      >
        <source src={src} type="video/mp4" />
        Your browser does not support the video tag.
      </video>
    </div>
  );
}
