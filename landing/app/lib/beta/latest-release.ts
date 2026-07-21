import "server-only";

const siteURL = process.env.NEXT_PUBLIC_SITE_URL ?? "https://flint.moyezrabbani.dev";

export type LatestRelease = {
  version: string;
  build: string;
  publishedAt: string;
  minimumSystemVersion: string;
  supportedArchitectures: readonly string[];
  downloadPageURL: string;
  assetURL: string;
  sha256: string;
  notes: readonly string[];
};

export function latestRelease(): LatestRelease {
  const version = process.env.FLINT_BETA_VERSION?.trim() || "0.1.0-beta.7";
  const filename = `Flint-${version}.dmg`;

  return {
    version,
    build: process.env.FLINT_BETA_BUILD?.trim() || "7",
    publishedAt: process.env.FLINT_BETA_PUBLISHED_AT?.trim() || "2026-07-21T09:45:30Z",
    minimumSystemVersion: "14.0",
    supportedArchitectures: ["arm64"],
    downloadPageURL: new URL("/#download", siteURL).toString(),
    assetURL:
      process.env.FLINT_BETA_DMG_URL?.trim() ||
      new URL(`/downloads/${filename}`, siteURL).toString(),
    sha256: process.env.FLINT_BETA_SHA256?.trim() || "67861fda1f5537fd276a08ada045fa90c7249461434b2f0a6406acea7add87dc",
    notes: [
      "Independent Accessibility and Input Monitoring recovery controls during onboarding.",
      "Shortcut monitoring stays paused until macOS reports Input Monitoring ready.",
      "Permission errors can be dismissed and disappear automatically after five seconds.",
      "A clear Quit action is available while applying macOS permission changes.",
    ],
  };
}
