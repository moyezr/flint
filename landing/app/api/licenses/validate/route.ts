import { NextResponse } from "next/server";

import { apiErrorResponse, parseRequest } from "@/app/lib/licenses/http";
import { validationRequestSchema } from "@/app/lib/licenses/schemas";
import { validate } from "@/app/lib/licenses/service";

export const runtime = "nodejs";

export async function POST(request: Request) {
  try {
    const input = await parseRequest(request, validationRequestSchema);
    return NextResponse.json(await validate(input));
  } catch (error) {
    return apiErrorResponse(error);
  }
}
