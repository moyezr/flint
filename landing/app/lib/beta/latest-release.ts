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
  const version = process.env.FLINT_BETA_VERSION?.trim() || "0.1.0-beta.10";
  const filename = `Flint-${version}.dmg`;

  return {
    version,
    build: process.env.FLINT_BETA_BUILD?.trim() || "10",
    publishedAt: process.env.FLINT_BETA_PUBLISHED_AT?.trim() || "2026-07-21T11:09:00Z",
    minimumSystemVersion: "14.0",
    supportedArchitectures: ["arm64"],
    downloadPageURL: new URL("/#download", siteURL).toString(),
    assetURL:
      process.env.FLINT_BETA_DMG_URL?.trim() ||
      new URL(`/downloads/${filename}`, siteURL).toString(),
    sha256: process.env.FLINT_BETA_SHA256?.trim() || "e8a708e5716576c7026a356d2196791cc94606db56df901a3b6f3b03320a293b",
    notes: [
      "The installer now presents only Flint and the Applications shortcut.",
      "Gatekeeper, setup, and cleanup guidance remains available on Flint's beta page.",
      "The app and onboarding behavior are unchanged from Beta 9.",
    ],
  };
}
