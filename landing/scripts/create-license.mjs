import { createHmac, randomUUID } from "node:crypto";
import postgres from "postgres";

const databaseUrl = required("DATABASE_URL");
const keyPepper = required("LICENSE_KEY_PEPPER");
const licenseKey = required("FLINT_LICENSE_KEY").trim().toUpperCase();
const customerEmail = required("FLINT_CUSTOMER_EMAIL").trim().toLowerCase();

const licenseKeyHash = createHmac("sha256", keyPepper).update(licenseKey).digest("hex");
const sql = postgres(databaseUrl, { max: 1, onnotice: () => {} });

try {
  const [license] = await sql`
    INSERT INTO flint_licenses (id, license_key_hash, customer_email)
    VALUES (${randomUUID()}, ${licenseKeyHash}, ${customerEmail})
    RETURNING id, customer_email, product_id, created_at
  `;
  console.log(`Created Flint license ${license.id} for ${license.customer_email}.`);
} finally {
  await sql.end();
}

function required(name) {
  const value = process.env[name];
  if (!value?.trim()) {
    throw new Error(`${name} must be set.`);
  }
  return value;
}
