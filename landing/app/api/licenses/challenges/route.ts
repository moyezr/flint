import { NextResponse } from "next/server";

import { apiErrorResponse, parseRequest } from "@/app/lib/licenses/http";
import { challengeRequestSchema } from "@/app/lib/licenses/schemas";
import { issueChallenge } from "@/app/lib/licenses/service";

export const runtime = "nodejs";

export async function POST(request: Request) {
  try {
    const input = await parseRequest(request, challengeRequestSchema);
    return NextResponse.json(await issueChallenge(input), { status: 201 });
  } catch (error) {
    return apiErrorResponse(error);
  }
}
