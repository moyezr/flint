import { NextResponse } from "next/server";
import { z } from "zod";

import { sendBetaVerificationCode } from "@/app/lib/beta/email";
import {
  cancelBetaEmailVerification,
  createBetaEmailVerification,
} from "@/app/lib/beta/service";
import { betaVerificationLifetimeMinutes } from "@/lib/beta-verification";
import { readJSONBody, RequestBodyError } from "@/app/lib/security/request";
import {
  enforceRateLimits,
  RateLimitExceededError,
  requestClientAddress,
} from "@/app/lib/security/rate-limit";

export const runtime = "nodejs";

const optionalNameSchema = z.string().trim().max(80).refine(
  (value) => !/[\u0000-\u001f\u007f]/u.test(value),
);

const requiredFirstNameSchema = z.string().trim().min(1).max(80).refine(
  (value) => !/[\u0000-\u001f\u007f]/u.test(value),
);

const signupSchema = z.object({
  email: z.string().trim().email().max(320),
  firstName: requiredFirstNameSchema,
  lastName: optionalNameSchema.default(""),
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
    return NextResponse.json(
      { error: "Enter your first name and a valid email address. Last name is optional." },
      { status: 400 },
    );
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
    const verification = await createBetaEmailVerification(parsed.data);
    try {
      await sendBetaVerificationCode({
        email: parsed.data.email.trim(),
        firstName: verification.firstName,
        code: verification.code,
      });
    } catch (error) {
      await cancelBetaEmailVerification(verification.verificationID).catch(() => {});
      throw error;
    }

    return NextResponse.json(
      {
        verificationID: verification.verificationID,
        expiresInSeconds: betaVerificationLifetimeMinutes * 60,
      },
      { status: 202, headers: { "Cache-Control": "no-store" } },
    );
  } catch (error) {
    if (error instanceof RateLimitExceededError) {
      return NextResponse.json(
        { error: "Too many verification-code requests. Please wait a few minutes and try again." },
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
      { error: "The verification email could not be sent. Please try again shortly." },
      { status: 503 },
    );
  }
}
