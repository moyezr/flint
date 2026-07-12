import { z } from "zod";

const base64Url = z.string().regex(/^[A-Za-z0-9_-]+$/, "Must be base64url encoded.");
const devicePublicKey = base64Url.max(64);
const challengeProof = z.object({
  challengeID: z.uuid(),
  challengeNonce: base64Url.max(128),
  challengeSignature: base64Url.max(128),
  devicePublicKey,
});

export const challengeRequestSchema = z.object({
  purpose: z.enum(["activate", "validate", "deactivate"]),
  devicePublicKey,
});

export const activationRequestSchema = challengeProof.extend({
  licenseKey: z.string().trim().min(8).max(256),
  deviceName: z.string().trim().min(1).max(80),
});

export const validationRequestSchema = challengeProof.extend({
  activationID: z.uuid(),
});

export const deactivationRequestSchema = validationRequestSchema;

export const transferConfirmationSchema = z.object({
  token: base64Url.min(32).max(128),
});
