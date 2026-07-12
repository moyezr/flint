import { NextResponse } from "next/server";

import { apiErrorResponse, parseRequest } from "@/app/lib/licenses/http";
import { deactivationRequestSchema } from "@/app/lib/licenses/schemas";
import { deactivate } from "@/app/lib/licenses/service";

export const runtime = "nodejs";

export async function POST(request: Request) {
  try {
    const input = await parseRequest(request, deactivationRequestSchema);
    await deactivate(input);
    return new NextResponse(null, { status: 204 });
  } catch (error) {
    return apiErrorResponse(error);
  }
}
