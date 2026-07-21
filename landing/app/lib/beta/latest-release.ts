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
  const version = process.env.FLINT_BETA_VERSION?.trim() || "0.1.0-beta.6";
  const filename = `Flint-${version}.dmg`;

  return {
    version,
    build: process.env.FLINT_BETA_BUILD?.trim() || "6",
    publishedAt: process.env.FLINT_BETA_PUBLISHED_AT?.trim() || "2026-07-21T09:17:17Z",
    minimumSystemVersion: "14.0",
    supportedArchitectures: ["arm64"],
    downloadPageURL: new URL("/#download", siteURL).toString(),
    assetURL:
      process.env.FLINT_BETA_DMG_URL?.trim() ||
      new URL(`/downloads/${filename}`, siteURL).toString(),
    sha256: process.env.FLINT_BETA_SHA256?.trim() || "be57d389d073c055c730f7d035bd4f0abd11db9e169d0ebe4b79105068b1ee55",
    notes: [
      "Onboarding requests macOS permissions one at a time so system prompts cannot overlap.",
      "Missing-permission retries open the relevant Privacy & Security pane when macOS does not show another prompt.",
      "A compact drag-to-Applications installer with the Flint F/ app icon.",
      "An always-available Quit Flint menu action.",
    ],
  };
}
