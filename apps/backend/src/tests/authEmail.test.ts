import { describe, expect, it, vi } from "vitest";
import {
  buildEmailConfirmationMessage,
  buildPasswordResetMessage,
  ResendAuthEmailSender,
  type EmailConfirmationInput,
  type PasswordResetEmailInput,
} from "../auth/email.js";
import { loadConfig } from "../config/env.js";

const confirmation: EmailConfirmationInput = {
  to: "antonio@example.com",
  displayName: "Antonio",
  confirmationUrl: "https://api.bettercalories.app/auth/email/confirm?token=test-token",
  expiresAt: "2026-07-16T12:30:00.000Z",
  expiresInMinutes: 30,
};

const passwordReset: PasswordResetEmailInput = {
  to: "antonio@example.com",
  displayName: "Antonio",
  resetUrl: "https://api.bettercalories.app/auth/password-reset/confirm?token=test-token",
  expiresInMinutes: 30,
};

describe("email confirmation messages", () => {
  it("renders the polished Spanish mobile-first message", () => {
    const message = buildEmailConfirmationMessage({
      ...confirmation,
      locale: "es-ES",
    });

    expect(message.subject).toBe("Confirma tu correo de BetterCalories");
    expect(message.text).toContain("Este enlace caduca en 30 minutos.");
    expect(message.html).toContain('<html lang="es">');
    expect(message.html).toContain("Confirma tu correo");
    expect(message.html).toContain("BetterCalories");
    expect(message.html).toContain("@media screen and (max-width: 620px)");
    expect(message.html).toContain(confirmation.confirmationUrl);
    expect(message.html).not.toContain("2026-07-16T12:30:00.000Z");
  });

  it("falls back to English and escapes user-controlled content", () => {
    const message = buildEmailConfirmationMessage({
      ...confirmation,
      displayName: '<script>alert("x")</script>',
      confirmationUrl: "https://example.com/confirm?token=a&next=\"bad\"",
      locale: "fr-FR",
    });

    expect(message.subject).toBe("Confirm your BetterCalories email");
    expect(message.html).toContain('<html lang="en">');
    expect(message.html).toContain("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;");
    expect(message.html).toContain("token=a&amp;next=&quot;bad&quot;");
    expect(message.html).not.toContain("<script>alert");
  });

  it("throws when Resend reports a delivery error", async () => {
    const send = vi.fn().mockResolvedValue({ error: { message: "rejected" } });
    const config = loadConfig({
      NODE_ENV: "test",
      RESEND_API_KEY: "re_test_key",
      RESEND_FROM_EMAIL: "BetterCalories <auth@bettercalories.app>",
    } as NodeJS.ProcessEnv);
    const sender = new ResendAuthEmailSender(config, { emails: { send } });

    await expect(sender.sendEmailConfirmation(confirmation)).rejects.toThrow(
      "Unable to send confirmation email",
    );
    expect(send).toHaveBeenCalledWith(expect.objectContaining({
      to: confirmation.to,
      subject: "Confirm your BetterCalories email",
    }));
  });

  it("renders localized password reset messages without exposing the token beyond the link", () => {
    const message = buildPasswordResetMessage({
      ...passwordReset,
      locale: "es-ES",
    });

    expect(message.subject).toBe("Restablece tu contraseña de BetterCalories");
    expect(message.text).toContain("Este enlace caduca en 30 minutos.");
    expect(message.html).toContain('<html lang="es">');
    expect(message.html).toContain(passwordReset.resetUrl);
  });

  it("sends password reset mail through the configured provider", async () => {
    const send = vi.fn().mockResolvedValue({ error: null });
    const config = loadConfig({
      NODE_ENV: "test",
      RESEND_API_KEY: "re_test_key",
      RESEND_FROM_EMAIL: "BetterCalories <auth@bettercalories.app>",
    } as NodeJS.ProcessEnv);
    const sender = new ResendAuthEmailSender(config, { emails: { send } });

    await sender.sendPasswordReset(passwordReset);

    expect(send).toHaveBeenCalledWith(expect.objectContaining({
      to: passwordReset.to,
      subject: "Reset your BetterCalories password",
    }));
  });
});
