import { NextResponse } from "next/server";

import { latestRelease } from "@/app/lib/beta/latest-release";

export const runtime = "nodejs";

export function GET() {
  const release = latestRelease();
  return NextResponse.json(
    {
      version: release.version,
      build: release.build,
      publishedAt: release.publishedAt,
      minimumSystemVersion: release.minimumSystemVersion,
      supportedArchitectures: release.supportedArchitectures,
      downloadURL: release.downloadPageURL,
      sha256: release.sha256,
      notes: release.notes,
    },
    {
      headers: {
        "Cache-Control": "public, max-age=300, s-maxage=3600, stale-while-revalidate=86400",
      },
    },
  );
}
