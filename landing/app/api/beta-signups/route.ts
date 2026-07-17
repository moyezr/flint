import { NextResponse } from "next/server";
import { z } from "zod";

import { createBetaDownload } from "@/app/lib/beta/service";

export const runtime = "nodejs";

const signupSchema = z.object({
  email: z.string().trim().email().max(320),
  marketingConsent: z.boolean().default(false),
  source: z.string().trim().min(1).max(80).default("landing"),
  website: z.string().max(0).default(""),
  startedAt: z.number().int().positive(),
});

export async function POST(request: Request) {
  if (request.headers.get("sec-fetch-site") === "cross-site") {
    return NextResponse.json({ error: "Invalid request origin." }, { status: 403 });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
  }

  const parsed = signupSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
  }

  if (Date.now() - parsed.data.startedAt < 400) {
    return NextResponse.json({ error: "Please try again." }, { status: 400 });
  }

  try {
    const token = await createBetaDownload(parsed.data);
    const downloadURL = new URL("/api/beta-download", request.url);
    downloadURL.searchParams.set("token", token);

    return NextResponse.json(
      { downloadURL: downloadURL.toString() },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    console.error("Flint beta signup failed", error);
    return NextResponse.json(
      { error: "Beta downloads are temporarily unavailable. Please try again shortly." },
      { status: 503 },
    );
  }
}
