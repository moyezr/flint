import "server-only";

import { Resend } from "resend";

import { betaVerificationLifetimeMinutes } from "@/lib/beta-verification";

export async function sendBetaVerificationCode(input: {
  email: string;
  firstName: string;
  code: string;
}): Promise<void> {
  const apiKey = required("RESEND_API_KEY");
  const from = required("BETA_EMAIL_FROM");

  const greeting = `Hi ${input.firstName},`;
  const resend = new Resend(apiKey);
  const { error } = await resend.emails.send({
    from,
    to: [input.email],
    subject: `${input.code} is your Flint verification code`,
    text: [
      greeting,
      "",
      "Use this code to verify your email and download the Flint beta:",
      "",
      input.code,
      "",
      `The code expires in ${betaVerificationLifetimeMinutes} minutes and can only be used once.`,
      "If you did not request Flint, you can ignore this email.",
    ].join("\n"),
  });

  if (error) {
    throw new Error(`Resend failed to send the beta verification code: ${error.message}`);
  }
}

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) {
    throw new Error(`${name} is not configured.`);
  }
  return value;
}
