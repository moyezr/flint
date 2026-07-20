import { createHmac } from "node:crypto";

import { NextResponse } from "next/server";

import { commerceWebhookSecret } from "@/app/lib/licenses/config";
import { safeEqualHex } from "@/app/lib/licenses/crypto";
import { apiErrorResponse } from "@/app/lib/licenses/http";
import { LicenseApiError } from "@/app/lib/licenses/errors";

export const runtime = "nodejs";

export async function POST(request: Request) {
  try {
    const signature = request.headers.get("x-flint-signature");
    if (!signature) {
      throw new LicenseApiError(401, "MISSING_SIGNATURE", "A webhook signature is required.");
    }
    const declaredLength = Number(request.headers.get("content-length"));
    if (Number.isFinite(declaredLength) && declaredLength > 64 * 1_024) {
      throw new LicenseApiError(413, "PAYLOAD_TOO_LARGE", "The webhook payload is too large.");
    }
    const body = await request.text();
    if (Buffer.byteLength(body, "utf8") > 64 * 1_024) {
      throw new LicenseApiError(413, "PAYLOAD_TOO_LARGE", "The webhook payload is too large.");
    }
    const expected = createHmac("sha256", commerceWebhookSecret()).update(body).digest("hex");
    if (!safeEqualHex(signature, expected)) {
      throw new LicenseApiError(401, "INVALID_SIGNATURE", "The webhook signature is not valid.");
    }

    return NextResponse.json(
      { error: { code: "COMMERCE_PROVIDER_NOT_CONFIGURED", message: "Choose and configure a payment provider before enabling this webhook." } },
      { status: 501 },
    );
  } catch (error) {
    return apiErrorResponse(error);
  }
}
