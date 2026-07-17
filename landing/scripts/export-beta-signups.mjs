import postgres from "postgres";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  throw new Error("DATABASE_URL must be configured.");
}

const sql = postgres(databaseUrl, { max: 1, onnotice: () => {} });

try {
  const rows = await sql`
    SELECT
      email,
      beta_access_consented_at,
      marketing_consented_at,
      download_count,
      last_downloaded_at,
      created_at
    FROM flint_beta_signups
    ORDER BY created_at DESC
  `;

  console.log([
    "email",
    "beta_access_consented_at",
    "marketing_consented_at",
    "download_count",
    "last_downloaded_at",
    "created_at",
  ].join(","));

  for (const row of rows) {
    console.log([
      row.email,
      toISO(row.beta_access_consented_at),
      toISO(row.marketing_consented_at),
      row.download_count,
      toISO(row.last_downloaded_at),
      toISO(row.created_at),
    ].map(csvCell).join(","));
  }
} finally {
  await sql.end();
}

function toISO(value) {
  return value instanceof Date ? value.toISOString() : value ?? "";
}

function csvCell(value) {
  const text = String(value ?? "");
  return `"${text.replaceAll('"', '""')}"`;
}
