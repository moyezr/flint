import { NextResponse } from "next/server";

import { apiErrorResponse, parseRequest } from "@/app/lib/licenses/http";
import { activationRequestSchema } from "@/app/lib/licenses/schemas";
import { activate } from "@/app/lib/licenses/service";

export const runtime = "nodejs";

export async function POST(request: Request) {
  try {
    const input = await parseRequest(request, activationRequestSchema);
    const result = await activate(input);
    return NextResponse.json(result, { status: result.kind === "activated" ? 201 : 202 });
  } catch (error) {
    return apiErrorResponse(error);
  }
}
