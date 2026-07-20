import "server-only";

export class RequestBodyError extends Error {}

export async function readJSONBody(request: Request, maximumBytes = 4_096): Promise<unknown> {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new RequestBodyError("Request body is too large.");
  }

  const text = await request.text();
  if (Buffer.byteLength(text, "utf8") > maximumBytes) {
    throw new RequestBodyError("Request body is too large.");
  }

  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new RequestBodyError("Request body must be valid JSON.");
  }
}
