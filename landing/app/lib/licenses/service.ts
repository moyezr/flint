import "server-only";

import { randomUUID } from "node:crypto";

import type postgres from "postgres";

import { licenseConfiguration } from "./config";
import { challengeMessage, deviceKeyHash, randomToken, secretHash, signedCertificate, verifyDeviceProof } from "./crypto";
import { database } from "./database";
import { sendTransferConfirmation } from "./email";
import { LicenseApiError } from "./errors";

type Transaction = postgres.TransactionSql;

type LicenseRow = {
  id: string;
  customer_email: string;
  status: "active" | "revoked" | "expired";
  product_id: string;
};

type ActivationRow = {
  id: string;
  license_id: string;
  device_public_key_hash: string;
  device_name: string;
  status: "active" | "revoked";
  activated_at: Date;
};

type ValidatedActivationRow = ActivationRow & {
  customer_email: string;
  license_status: LicenseRow["status"];
  product_id: string;
};

type ChallengePurpose = "activate" | "validate" | "deactivate";

type DeviceProof = {
  challengeID: string;
  challengeNonce: string;
  challengeSignature: string;
  devicePublicKey: string;
};

export type ActivationRequest = DeviceProof & {
  deviceName: string;
  licenseKey: string;
};

export type ValidationRequest = DeviceProof & {
  activationID: string;
};

export type ActivationResult =
  | { kind: "activated"; activationID: string; certificate: string; expiresAt: string }
  | { kind: "transfer_pending"; transferExpiresAt: string };

export async function issueChallenge(input: { devicePublicKey: string; purpose: ChallengePurpose }) {
  const sql = database();
  const id = randomUUID();
  const nonce = randomToken();
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

  await sql`
    INSERT INTO flint_license_challenges (id, device_public_key_hash, nonce_hash, purpose, expires_at)
    VALUES (${id}, ${deviceKeyHash(input.devicePublicKey)}, ${secretHash(nonce)}, ${input.purpose}, ${expiresAt})
  `;

  return {
    challengeID: id,
    nonce,
    purpose: input.purpose,
    message: challengeMessage(id, nonce, input.purpose),
    expiresAt: expiresAt.toISOString(),
  };
}

export async function activate(input: ActivationRequest): Promise<ActivationResult> {
  const licenseKey = normalizeLicenseKey(input.licenseKey);
  const deviceHash = deviceKeyHash(input.devicePublicKey);
  const db = database();
  const pending = await db.begin(async (sql) => {
    await consumeChallenge(sql, input, "activate", deviceHash);
    const [license] = await sql<LicenseRow[]>`
      SELECT id, customer_email, status, product_id
      FROM flint_licenses
      WHERE license_key_hash = ${secretHash(licenseKey)}
      FOR UPDATE
    `;
    if (!license) {
      throw new LicenseApiError(404, "INVALID_LICENSE", "That license key is not valid.");
    }
    assertLicenseActive(license);

    const [existing] = await sql<ActivationRow[]>`
      SELECT id, license_id, device_public_key_hash, device_name, status, activated_at
      FROM flint_activations
      WHERE license_id = ${license.id} AND status = 'active'
      FOR UPDATE
    `;

    if (!existing || existing.device_public_key_hash === deviceHash) {
      const activation = existing ?? await createActivation(sql, license.id, deviceHash, input.deviceName);
      await sql`
        UPDATE flint_activations
        SET last_verified_at = NOW(), updated_at = NOW()
        WHERE id = ${activation.id}
      `;
      await audit(sql, license.id, activation.id, existing ? "activation_reused" : "activated", { deviceName: input.deviceName });
      return { kind: "activated" as const, license, activation };
    }

    const [existingTransfer] = await sql<{ expires_at: Date }[]>`
      SELECT expires_at
      FROM flint_activation_transfers
      WHERE license_id = ${license.id}
        AND new_device_public_key_hash = ${deviceHash}
        AND status = 'pending'
        AND expires_at > NOW()
      ORDER BY created_at DESC
      LIMIT 1
      FOR UPDATE
    `;
    if (existingTransfer) {
      return { kind: "transfer_pending" as const, expiresAt: existingTransfer.expires_at };
    }

    const transfer = await createTransfer(sql, license.id, existing.id, deviceHash, input.deviceName);
    await audit(sql, license.id, existing.id, "transfer_requested", { newDeviceName: input.deviceName });
    return { kind: "transfer_pending" as const, expiresAt: transfer.expiresAt, transfer, license };
  });

  if (pending.kind === "activated") {
    return certificateResult(pending.license, pending.activation);
  }

  if ("transfer" in pending && pending.transfer && pending.license) {
    try {
      await sendTransferConfirmation({
        customerEmail: pending.license.customer_email,
        deviceName: pending.transfer.deviceName,
        token: pending.transfer.token,
      });
    } catch (error) {
      await db`
        DELETE FROM flint_activation_transfers
        WHERE id = ${pending.transfer.id} AND status = 'pending'
      `;
      throw new LicenseApiError(503, "TRANSFER_EMAIL_UNAVAILABLE", error instanceof Error ? error.message : "Could not send the transfer email.");
    }
  }

  return { kind: "transfer_pending", transferExpiresAt: pending.expiresAt.toISOString() };
}

export async function validate(input: ValidationRequest) {
  const deviceHash = deviceKeyHash(input.devicePublicKey);
  const db = database();
  const result = await db.begin(async (sql) => {
    await consumeChallenge(sql, input, "validate", deviceHash);
    const [activation] = await sql<ValidatedActivationRow[]>`
      SELECT a.id, a.license_id, a.device_public_key_hash, a.device_name, a.status, a.activated_at,
             l.customer_email, l.status AS license_status, l.product_id, l.id AS license_id
      FROM flint_activations a
      JOIN flint_licenses l ON l.id = a.license_id
      WHERE a.id = ${input.activationID}
      FOR UPDATE
    `;
    if (!activation || activation.status !== "active" || activation.device_public_key_hash !== deviceHash) {
      throw new LicenseApiError(401, "ACTIVATION_NOT_ACTIVE", "This device activation is not active.");
    }
    const license: LicenseRow = {
      id: activation.license_id,
      customer_email: activation.customer_email,
      status: activation.license_status,
      product_id: activation.product_id,
    };
    assertLicenseActive(license);
    await sql`UPDATE flint_activations SET last_verified_at = NOW(), updated_at = NOW() WHERE id = ${activation.id}`;
    await audit(sql, license.id, activation.id, "validated", {});
    return { license, activation };
  });
  return certificateResult(result.license, result.activation);
}

export async function deactivate(input: ValidationRequest) {
  const deviceHash = deviceKeyHash(input.devicePublicKey);
  const db = database();
  await db.begin(async (sql) => {
    await consumeChallenge(sql, input, "deactivate", deviceHash);
    const [activation] = await sql<ActivationRow[]>`
      SELECT id, license_id, device_public_key_hash, device_name, status, activated_at
      FROM flint_activations
      WHERE id = ${input.activationID}
      FOR UPDATE
    `;
    if (!activation || activation.status !== "active" || activation.device_public_key_hash !== deviceHash) {
      throw new LicenseApiError(401, "ACTIVATION_NOT_ACTIVE", "This device activation is not active.");
    }
    await sql`
      UPDATE flint_activations
      SET status = 'revoked', revoked_at = NOW(), updated_at = NOW()
      WHERE id = ${activation.id}
    `;
    await audit(sql, activation.license_id, activation.id, "deactivated", {});
  });
}

export async function confirmTransfer(token: string) {
  const sql = database();
  const result = await sql.begin(async (transaction) => {
    const [transfer] = await transaction<{
      id: string;
      license_id: string;
      previous_activation_id: string;
      new_device_public_key_hash: string;
      new_device_name: string;
      status: string;
      expires_at: Date;
    }[]>`
      SELECT id, license_id, previous_activation_id, new_device_public_key_hash, new_device_name, status, expires_at
      FROM flint_activation_transfers
      WHERE token_hash = ${secretHash(token)}
      FOR UPDATE
    `;
    if (!transfer || transfer.status !== "pending" || transfer.expires_at < new Date()) {
      throw new LicenseApiError(410, "TRANSFER_EXPIRED", "This transfer link has expired or was already used.");
    }

    const [license] = await transaction<LicenseRow[]>`
      SELECT id, customer_email, status, product_id
      FROM flint_licenses
      WHERE id = ${transfer.license_id}
      FOR UPDATE
    `;
    if (!license) {
      throw new LicenseApiError(404, "LICENSE_NOT_FOUND", "The license for this transfer no longer exists.");
    }
    assertLicenseActive(license);

    await transaction`
      UPDATE flint_activations
      SET status = 'revoked', revoked_at = NOW(), updated_at = NOW()
      WHERE license_id = ${license.id} AND status = 'active'
    `;
    const activation = await createActivation(transaction, license.id, transfer.new_device_public_key_hash, transfer.new_device_name);
    await transaction`
      UPDATE flint_activation_transfers
      SET status = 'confirmed', confirmed_at = NOW()
      WHERE id = ${transfer.id}
    `;
    await audit(transaction, license.id, activation.id, "transfer_confirmed", { previousActivationID: transfer.previous_activation_id });
    return { activationID: activation.id };
  });
  return result;
}

async function consumeChallenge(
  sql: Transaction,
  proof: DeviceProof,
  purpose: ChallengePurpose,
  expectedDeviceHash: string,
): Promise<void> {
  verifyDeviceProof({ ...proof, purpose });
  const [challenge] = await sql<{
    device_public_key_hash: string;
    expires_at: Date;
    nonce_hash: string;
    purpose: ChallengePurpose;
    used_at: Date | null;
  }[]>`
    SELECT device_public_key_hash, expires_at, nonce_hash, purpose, used_at
    FROM flint_license_challenges
    WHERE id = ${proof.challengeID}
    FOR UPDATE
  `;
  if (
    !challenge ||
    challenge.used_at ||
    challenge.expires_at < new Date() ||
    challenge.purpose !== purpose ||
    challenge.device_public_key_hash !== expectedDeviceHash ||
    challenge.nonce_hash !== secretHash(proof.challengeNonce)
  ) {
    throw new LicenseApiError(401, "INVALID_CHALLENGE", "The device challenge is invalid, expired, or already used.");
  }
  await sql`UPDATE flint_license_challenges SET used_at = NOW() WHERE id = ${proof.challengeID}`;
}

async function createActivation(sql: Transaction, licenseID: string, deviceHash: string, deviceName: string): Promise<ActivationRow> {
  const [activation] = await sql<ActivationRow[]>`
    INSERT INTO flint_activations (id, license_id, device_public_key_hash, device_name)
    VALUES (${randomUUID()}, ${licenseID}, ${deviceHash}, ${deviceName})
    RETURNING id, license_id, device_public_key_hash, device_name, status, activated_at
  `;
  return activation;
}

async function createTransfer(
  sql: Transaction,
  licenseID: string,
  previousActivationID: string,
  deviceHash: string,
  deviceName: string,
) {
  const id = randomUUID();
  const token = randomToken();
  const expiresAt = new Date(Date.now() + 15 * 60 * 1000);
  await sql`
    INSERT INTO flint_activation_transfers (
      id, license_id, previous_activation_id, new_device_public_key_hash, new_device_name, token_hash, expires_at
    ) VALUES (
      ${id}, ${licenseID}, ${previousActivationID}, ${deviceHash}, ${deviceName}, ${secretHash(token)}, ${expiresAt}
    )
  `;
  return { id, token, deviceName, expiresAt };
}

async function audit(
  sql: Transaction,
  licenseID: string,
  activationID: string | null,
  eventType: string,
  eventData: Record<string, unknown>,
): Promise<void> {
  await sql`
    INSERT INTO flint_license_audit_events (id, license_id, activation_id, event_type, event_data)
    VALUES (${randomUUID()}, ${licenseID}, ${activationID}, ${eventType}, ${JSON.stringify(eventData)}::jsonb)
  `;
}

function certificateResult(license: LicenseRow, activation: ActivationRow) {
  const now = new Date();
  const expiresAt = new Date(now.getTime() + licenseConfiguration().certificateLifetimeDays * 24 * 60 * 60 * 1000);
  const certificate = signedCertificate({
    version: 1,
    licenseID: license.id,
    activationID: activation.id,
    productID: license.product_id,
    appBundleID: licenseConfiguration().appBundleID,
    deviceKeyHash: activation.device_public_key_hash,
    issuedAt: now.toISOString(),
    expiresAt: expiresAt.toISOString(),
  });
  return { kind: "activated" as const, activationID: activation.id, certificate, expiresAt: expiresAt.toISOString() };
}

function assertLicenseActive(license: LicenseRow): void {
  if (license.status === "revoked") {
    throw new LicenseApiError(403, "LICENSE_REVOKED", "This license has been revoked.");
  }
  if (license.status === "expired") {
    throw new LicenseApiError(403, "LICENSE_EXPIRED", "This license has expired.");
  }
}

function normalizeLicenseKey(value: string): string {
  return value.trim().toUpperCase();
}
