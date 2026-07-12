import { NextResponse } from "next/server";

import { apiErrorResponse, parseRequest } from "@/app/lib/licenses/http";
import { transferConfirmationSchema } from "@/app/lib/licenses/schemas";
import { confirmTransfer } from "@/app/lib/licenses/service";

export const runtime = "nodejs";

export async function POST(request: Request) {
  try {
    const input = await parseRequest(request, transferConfirmationSchema);
    return NextResponse.json(await confirmTransfer(input.token));
  } catch (error) {
    return apiErrorResponse(error);
  }
}
