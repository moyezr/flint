import { NextResponse } from "next/server";

import { latestRelease } from "@/app/lib/beta/latest-release";
import { consumeBetaDownload } from "@/app/lib/beta/service";

export const runtime = "nodejs";

export async function GET(request: Request) {
  const token = new URL(request.url).searchParams.get("token")?.trim();
  if (!token || token.length > 128) {
    return expiredResponse(request.url);
  }

  try {
    if (!(await consumeBetaDownload(token))) {
      return expiredResponse(request.url);
    }

    const response = NextResponse.redirect(latestRelease().assetURL, 307);
    response.headers.set("Cache-Control", "no-store");
    response.headers.set("Referrer-Policy", "no-referrer");
    return response;
  } catch (error) {
    console.error("Flint beta download failed", error);
    return NextResponse.json(
      { error: "The download is temporarily unavailable. Please try again shortly." },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }
}

function expiredResponse(requestURL: string) {
  const retryURL = new URL("/#download", requestURL);
  retryURL.searchParams.set("download", "expired");
  return NextResponse.redirect(retryURL, 303);
}
