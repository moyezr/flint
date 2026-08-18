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
  const version = process.env.FLINT_BETA_VERSION?.trim() || "0.1.0-beta.12";
  const filename = `Flint-${version}.dmg`;

  return {
    version,
    build: process.env.FLINT_BETA_BUILD?.trim() || "12",
    publishedAt: process.env.FLINT_BETA_PUBLISHED_AT?.trim() || "2026-08-18T19:26:02Z",
    minimumSystemVersion: "14.0",
    supportedArchitectures: ["arm64"],
    downloadPageURL: new URL("/#download", siteURL).toString(),
    assetURL:
      process.env.FLINT_BETA_DMG_URL?.trim() ||
      new URL(`/downloads/${filename}`, siteURL).toString(),
    sha256: process.env.FLINT_BETA_SHA256?.trim() || "72dfa326f6086c6694906a375bd3deb705060b132809f6e177ddc13ae4745823",
    notes: [
      "Escape now passes through normally unless an active dictation is being cancelled.",
      "This build keeps the same private beta identity as Beta 11, so its macOS permission identity is unchanged.",
      "Gatekeeper still shows the expected unverified-app warning because this beta is not Developer ID signed or notarized.",
    ],
  };
}
