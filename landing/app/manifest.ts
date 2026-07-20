import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Flint - Local Dictation for Mac",
    short_name: "Flint",
    description: "Local-first dictation for macOS.",
    start_url: "/",
    display: "browser",
    background_color: "#f5f3ef",
    theme_color: "#f5f3ef",
    icons: [
      {
        src: "/icons/flint-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icons/flint-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/icons/flint-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "maskable",
      },
      {
        src: "/icons/flint-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
  };
}
