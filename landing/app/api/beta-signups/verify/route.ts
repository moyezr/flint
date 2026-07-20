import { NextResponse } from "next/server";
import { z } from "zod";

import { verifyBetaEmail } from "@/app/lib/beta/service";
import { readJSONBody } from "@/app/lib/security/request";
import {
  enforceRateLimits,
  RateLimitExceededError,
  requestClientAddress,
} from "@/app/lib/security/rate-limit";

export const runtime = "nodejs";

const verificationSchema = z.object({
  verificationID: z.string().uuid(),
  code: z.string().regex(/^\d{6}$/),
});

export async function POST(request: Request) {
  if (request.headers.get("sec-fetch-site") === "cross-site") {
    return NextResponse.json({ error: "Invalid request origin." }, { status: 403 });
  }

  let body: unknown;
  try {
    body = await readJSONBody(request);
  } catch {
    return NextResponse.json({ error: "Enter the six-digit code from your email." }, { status: 400 });
  }

  const parsed = verificationSchema.safeParse(body);
  if (!parsed.success) {
    return NextResponse.json({ error: "Enter the six-digit code from your email." }, { status: 400 });
  }

  try {
    await enforceRateLimits([
      {
        identifier: `beta-verify-ip:${requestClientAddress(request)}`,
        maximumRequests: 30,
        windowSeconds: 15 * 60,
      },
      {
        identifier: `beta-verify-challenge:${parsed.data.verificationID}`,
        maximumRequests: 10,
        windowSeconds: 15 * 60,
      },
    ]);

    const result = await verifyBetaEmail(parsed.data);
    if (result.status === "invalid") {
      return NextResponse.json(
        { error: "That code is incorrect. Check the email and try again." },
        { status: 400, headers: { "Cache-Control": "no-store" } },
      );
    }
    if (result.status === "expired") {
      return NextResponse.json(
        { error: "That code has expired. Request a new code." },
        { status: 410, headers: { "Cache-Control": "no-store" } },
      );
    }
    if (result.status === "locked") {
      return NextResponse.json(
        { error: "Too many incorrect attempts. Request a new code." },
        { status: 429, headers: { "Cache-Control": "no-store", "Retry-After": "60" } },
      );
    }

    const downloadURL = new URL("/api/beta-download", request.url);
    downloadURL.searchParams.set("token", result.token);
    return NextResponse.json(
      { downloadURL: downloadURL.toString() },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    if (error instanceof RateLimitExceededError) {
      return NextResponse.json(
        { error: "Too many verification attempts. Please wait before trying again." },
        {
          status: 429,
          headers: {
            "Cache-Control": "no-store",
            "Retry-After": error.retryAfterSeconds.toString(),
          },
        },
      );
    }
    console.error("Flint beta email verification failed", error);
    return NextResponse.json(
      { error: "Email verification is temporarily unavailable. Please try again shortly." },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }
}
