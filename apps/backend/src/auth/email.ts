import { Resend } from "resend";
import type { AppConfig } from "../config/env.js";

export type EmailConfirmationInput = {
  to: string;
  displayName: string;
  confirmationUrl: string;
  expiresAt: string;
};

export interface AuthEmailSender {
  sendEmailConfirmation(input: EmailConfirmationInput): Promise<void>;
}

export class ResendAuthEmailSender implements AuthEmailSender {
  private readonly resend?: Resend;

  constructor(private readonly config: AppConfig) {
    const apiKey = config.RESEND_API_KEY.trim();
    this.resend = apiKey ? new Resend(apiKey) : undefined;
  }

  async sendEmailConfirmation(
    input: EmailConfirmationInput,
  ): Promise<void> {
    if (!this.resend || !this.config.RESEND_FROM_EMAIL.trim()) {
      console.info("auth.email_confirmation.dev_link", {
        email: input.to,
        confirmationUrl: input.confirmationUrl,
      });
      return;
    }

    await this.resend.emails.send({
      from: this.config.RESEND_FROM_EMAIL,
      to: input.to,
      subject: "Confirm your BetterCalories account",
      html: confirmationEmailHtml(input),
      text: confirmationEmailText(input),
    });
  }
}

function confirmationEmailText(input: EmailConfirmationInput): string {
  return [
    `Hi ${input.displayName},`,
    "",
    "Confirm your BetterCalories account by opening this link:",
    input.confirmationUrl,
    "",
    `This link expires at ${new Date(input.expiresAt).toUTCString()}.`,
    "",
    "If you did not request this account, you can ignore this email.",
  ].join("\n");
}

function confirmationEmailHtml(input: EmailConfirmationInput): string {
  const escapedName = escapeHtml(input.displayName);
  const escapedUrl = escapeHtml(input.confirmationUrl);
  const expiresAt = escapeHtml(new Date(input.expiresAt).toUTCString());
  return `<!doctype html>
<html lang="en">
  <body style="font-family:Arial,sans-serif;color:#18201b;line-height:1.5">
    <p>Hi ${escapedName},</p>
    <p>Confirm your BetterCalories account with this secure link:</p>
    <p>
      <a href="${escapedUrl}" style="display:inline-block;background:#2f6f31;color:#ffffff;padding:12px 18px;border-radius:8px;text-decoration:none">
        Confirm account
      </a>
    </p>
    <p>This link expires at ${expiresAt}.</p>
    <p>If you did not request this account, you can ignore this email.</p>
  </body>
</html>`;
}

function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
