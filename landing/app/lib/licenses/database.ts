import "server-only";

import postgres from "postgres";

declare global {
  var flintLicenseDatabase: ReturnType<typeof postgres> | undefined;
}

export function database() {
  if (!globalThis.flintLicenseDatabase) {
    const databaseUrl = process.env.DATABASE_URL;
    if (!databaseUrl) {
      throw new Error("DATABASE_URL is not configured.");
    }
    globalThis.flintLicenseDatabase = postgres(databaseUrl, { max: 1, prepare: false });
  }
  return globalThis.flintLicenseDatabase;
}
