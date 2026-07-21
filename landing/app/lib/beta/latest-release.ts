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
  const version = process.env.FLINT_BETA_VERSION?.trim() || "0.1.0-beta.5";
  const filename = `Flint-${version}.dmg`;

  return {
    version,
    build: process.env.FLINT_BETA_BUILD?.trim() || "5",
    publishedAt: process.env.FLINT_BETA_PUBLISHED_AT?.trim() || "2026-07-21T08:27:04Z",
    minimumSystemVersion: "14.0",
    supportedArchitectures: ["arm64"],
    downloadPageURL: new URL("/#download", siteURL).toString(),
    assetURL:
      process.env.FLINT_BETA_DMG_URL?.trim() ||
      new URL(`/downloads/${filename}`, siteURL).toString(),
    sha256: process.env.FLINT_BETA_SHA256?.trim() || "9665cfb60a14d210a57ab7ade98a7123eeaec55a848620e8f57fae9a6065d006",
    notes: [
      "Onboarding automatically detects permissions granted in System Settings.",
      "Clear recovery steps for stale permission entries left by an earlier direct beta.",
      "A compact drag-to-Applications installer with the Flint F/ app icon.",
      "An always-available Quit Flint menu action.",
    ],
  };
}
