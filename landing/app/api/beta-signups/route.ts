import { NextResponse } from "next/server";
import { z } from "zod";

import { createBetaDownload } from "@/app/lib/beta/service";
import { readJSONBody, RequestBodyError } from "@/app/lib/security/request";
import {
  enforceRateLimits,
  RateLimitExceededError,
  requestClientAddress,
} from "@/app/lib/security/rate-limit";

export const runtime = "nodejs";

const signupSchema = z.object({
  email: z.string().trim().email().max(320),
  marketingConsent: z.boolean().default(false),
  source: z.string().trim().min(1).max(80).default("landing"),
  website: z.string().max(0).default(""),
  startedAt: z.number().int().positive(),
  acceptedTerms: z.literal(true),
});

export async function POST(request: Request) {
  if (request.headers.get("sec-fetch-site") === "cross-site") {
    return NextResponse.json({ error: "Invalid request origin." }, { status: 403 });
  }

  let body: unknown;
  try {
    body = await readJSONBody(request);
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
    const normalizedEmail = parsed.data.email.trim().toLocaleLowerCase("en-US");
    await enforceRateLimits([
      {
        identifier: `beta-signup-ip:${requestClientAddress(request)}`,
        maximumRequests: 20,
        windowSeconds: 15 * 60,
      },
      {
        identifier: `beta-signup-email:${normalizedEmail}`,
        maximumRequests: 5,
        windowSeconds: 15 * 60,
      },
    ]);
    const token = await createBetaDownload(parsed.data);
    const downloadURL = new URL("/api/beta-download", request.url);
    downloadURL.searchParams.set("token", token);

    return NextResponse.json(
      { downloadURL: downloadURL.toString() },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    if (error instanceof RateLimitExceededError) {
      return NextResponse.json(
        { error: "Too many download requests. Please wait a few minutes and try again." },
        {
          status: 429,
          headers: {
            "Cache-Control": "no-store",
            "Retry-After": error.retryAfterSeconds.toString(),
          },
        },
      );
    }
    if (error instanceof RequestBodyError) {
      return NextResponse.json({ error: "Enter a valid email address." }, { status: 400 });
    }
    console.error("Flint beta signup failed", error);
    return NextResponse.json(
      { error: "Beta downloads are temporarily unavailable. Please try again shortly." },
      { status: 503 },
    );
  }
}
