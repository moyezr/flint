import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import postgres from "postgres";

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) {
  throw new Error("DATABASE_URL must be set before running migrations.");
}

const migrationsDirectory = join(import.meta.dirname, "..", "db", "migrations");
const migrationNames = (await readdir(migrationsDirectory)).filter((name) => name.endsWith(".sql")).sort();
const sql = postgres(databaseUrl, { max: 1, onnotice: () => {} });

try {
  await sql`CREATE TABLE IF NOT EXISTS flint_schema_migrations (
    filename TEXT PRIMARY KEY,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  )`;

  for (const filename of migrationNames) {
    const [applied] = await sql`SELECT filename FROM flint_schema_migrations WHERE filename = ${filename}`;
    if (applied) {
      continue;
    }

    const migration = await readFile(join(migrationsDirectory, filename), "utf8");
    await sql.begin(async (transaction) => {
      await transaction.unsafe(migration);
      await transaction`INSERT INTO flint_schema_migrations (filename) VALUES (${filename})`;
    });
    console.log(`Applied ${filename}`);
  }
} finally {
  await sql.end();
}
