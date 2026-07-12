import "server-only";

import { NextResponse } from "next/server";
import { z } from "zod";

import { LicenseApiError } from "./errors";

export async function parseRequest<T extends z.ZodType>(request: Request, schema: T): Promise<z.output<T>> {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    throw new LicenseApiError(400, "INVALID_JSON", "The request body must be valid JSON.");
  }
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    throw new LicenseApiError(400, "INVALID_REQUEST", "The request body is invalid.");
  }
  return parsed.data;
}

export function apiErrorResponse(error: unknown): NextResponse {
  if (error instanceof LicenseApiError) {
    return NextResponse.json({ error: { code: error.code, message: error.message } }, { status: error.status });
  }
  console.error("Flint licensing API error", error);
  return NextResponse.json(
    { error: { code: "LICENSING_UNAVAILABLE", message: "The licensing service is temporarily unavailable." } },
    { status: 503 },
  );
}
