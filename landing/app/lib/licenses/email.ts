import "server-only";

import { Resend } from "resend";

import { licenseConfiguration } from "./config";

export async function sendTransferConfirmation(input: {
  customerEmail: string;
  deviceName: string;
  token: string;
}): Promise<void> {
  const configuration = licenseConfiguration();
  const confirmationURL = new URL("/license-transfer", configuration.siteUrl);
  confirmationURL.searchParams.set("token", input.token);

  const resend = new Resend(process.env.RESEND_API_KEY);
  const { error } = await resend.emails.send({
    from: configuration.emailFrom,
    to: [input.customerEmail],
    subject: "Confirm your Flint device transfer",
    text: [
      `A Flint activation was requested for ${input.deviceName}.`,
      "",
      "Confirming this transfer will deactivate Flint on the currently active Mac.",
      `Confirm the transfer: ${confirmationURL.toString()}`,
      "",
      "This link expires in 15 minutes. If you did not request this, you can ignore this email.",
    ].join("\n"),
  });

  if (error) {
    throw new Error(`Resend failed to send the transfer confirmation: ${error.message}`);
  }
}
