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
  const version = process.env.FLINT_BETA_VERSION?.trim() || "0.1.0-beta.3";
  const filename = `Flint-${version}.dmg`;

  return {
    version,
    build: process.env.FLINT_BETA_BUILD?.trim() || "3",
    publishedAt: process.env.FLINT_BETA_PUBLISHED_AT?.trim() || "2026-07-17T00:00:00Z",
    minimumSystemVersion: "14.0",
    supportedArchitectures: ["arm64"],
    downloadPageURL: new URL("/#download", siteURL).toString(),
    assetURL:
      process.env.FLINT_BETA_DMG_URL?.trim() ||
      new URL(`/downloads/${filename}`, siteURL).toString(),
    sha256: process.env.FLINT_BETA_SHA256?.trim() || "0214c9eaae8e5fec75551cac7febd2619577b27ee557658a5a279c943164d11a",
    notes: [
      "Lightweight automatic update checks that never block dictation.",
      "A repeatable onboarding flow for testing setup at any time.",
      "Local, explicit vocabulary and correction learning.",
      "Compact Dynamic Island feedback and safer insertion in rich editors.",
    ],
  };
}
