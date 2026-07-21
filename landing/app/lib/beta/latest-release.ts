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
  const version = process.env.FLINT_BETA_VERSION?.trim() || "0.1.0-beta.11";
  const filename = `Flint-${version}.dmg`;

  return {
    version,
    build: process.env.FLINT_BETA_BUILD?.trim() || "11",
    publishedAt: process.env.FLINT_BETA_PUBLISHED_AT?.trim() || "2026-07-21T11:46:47Z",
    minimumSystemVersion: "14.0",
    supportedArchitectures: ["arm64"],
    downloadPageURL: new URL("/#download", siteURL).toString(),
    assetURL:
      process.env.FLINT_BETA_DMG_URL?.trim() ||
      new URL(`/downloads/${filename}`, siteURL).toString(),
    sha256: process.env.FLINT_BETA_SHA256?.trim() || "1a6797695fc6fa7dd01192055f447bc3fcd06bfa7e825327a959337cc7b30229",
    notes: [
      "Flint now uses one stable private beta identity so later beta updates can retain macOS permissions.",
      "People updating from Beta 10 or earlier need to remove the old Accessibility entry and add Flint once; onboarding shows the exact steps.",
      "Gatekeeper still shows the expected unverified-app warning because this beta is not Developer ID signed or notarized.",
    ],
  };
}
