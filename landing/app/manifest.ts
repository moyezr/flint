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
  };
}
