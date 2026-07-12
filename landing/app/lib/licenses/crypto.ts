import "server-only";

import { createHash, createHmac, createPrivateKey, randomBytes, sign, timingSafeEqual, verify } from "node:crypto";

import { licenseConfiguration } from "./config";
import { LicenseApiError } from "./errors";

const ed25519SpkiPrefix = Buffer.from("302a300506032b6570032100", "hex");

export function base64Url(bytes: Buffer): string {
  return bytes.toString("base64url");
}

export function parseBase64Url(value: string, label: string): Buffer {
  try {
    const bytes = Buffer.from(value, "base64url");
    if (bytes.length === 0 || base64Url(bytes) !== value) {
      throw new Error("invalid encoding");
    }
    return bytes;
  } catch {
    throw new LicenseApiError(400, "INVALID_ENCODING", `${label} must be base64url encoded.`);
  }
}

export function deviceKeyHash(devicePublicKey: string): string {
  const bytes = parseBase64Url(devicePublicKey, "devicePublicKey");
  if (bytes.length !== 32) {
    throw new LicenseApiError(400, "INVALID_DEVICE_KEY", "devicePublicKey must be a 32-byte Ed25519 public key.");
  }
  return createHash("sha256").update(bytes).digest("hex");
}

export function secretHash(value: string): string {
  return createHmac("sha256", licenseConfiguration().keyPepper).update(value).digest("hex");
}

export function randomToken(bytes = 32): string {
  return base64Url(randomBytes(bytes));
}

export function challengeMessage(challengeID: string, nonce: string, purpose: string): string {
  return `flint-license-v1|${challengeID}|${nonce}|${purpose}`;
}

export function verifyDeviceProof(input: {
  challengeID: string;
  challengeNonce: string;
  challengeSignature: string;
  devicePublicKey: string;
  purpose: string;
}): void {
  const publicKey = parseBase64Url(input.devicePublicKey, "devicePublicKey");
  const signature = parseBase64Url(input.challengeSignature, "challengeSignature");
  if (publicKey.length !== 32 || signature.length !== 64) {
    throw new LicenseApiError(400, "INVALID_DEVICE_PROOF", "The device proof has an invalid length.");
  }

  const key = { key: Buffer.concat([ed25519SpkiPrefix, publicKey]), format: "der" as const, type: "spki" as const };
  const message = Buffer.from(challengeMessage(input.challengeID, input.challengeNonce, input.purpose), "utf8");
  if (!verify(null, message, key, signature)) {
    throw new LicenseApiError(401, "INVALID_DEVICE_PROOF", "The device proof could not be verified.");
  }
}

export function signedCertificate(payload: Record<string, unknown>): string {
  const payloadPart = base64Url(Buffer.from(JSON.stringify(payload), "utf8"));
  const signature = sign(null, Buffer.from(payloadPart, "utf8"), createPrivateKey(licenseConfiguration().signingPrivateKeyPem));
  return `${payloadPart}.${base64Url(signature)}`;
}

export function safeEqualHex(left: string, right: string): boolean {
  const leftBytes = Buffer.from(left, "hex");
  const rightBytes = Buffer.from(right, "hex");
  return leftBytes.length === rightBytes.length && timingSafeEqual(leftBytes, rightBytes);
}
