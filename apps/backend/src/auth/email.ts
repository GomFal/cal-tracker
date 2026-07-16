import { Resend } from "resend";
import type { AppConfig } from "../config/env.js";

export type EmailConfirmationInput = {
  to: string;
  displayName: string;
  confirmationUrl: string;
  expiresAt: string;
  expiresInMinutes: number;
  locale?: string;
};

export type EmailConfirmationMessage = {
  subject: string;
  html: string;
  text: string;
};

type ResendMessage = EmailConfirmationMessage & {
  from: string;
  to: string;
};

type ResendClient = {
  emails: {
    send(message: ResendMessage): Promise<{ error?: unknown | null }>;
  };
};

type EmailLocale = "en" | "es";

type EmailCopy = {
  subject: string;
  preheader: string;
  greeting: string;
  heading: string;
  body: string;
  cta: string;
  expiry: string;
  fallback: string;
  securityTitle: string;
  securityBody: string;
  ignore: string;
  tagline: string;
};

export interface AuthEmailSender {
  sendEmailConfirmation(input: EmailConfirmationInput): Promise<void>;
}

export class ResendAuthEmailSender implements AuthEmailSender {
  private readonly resend?: ResendClient;

  constructor(
    private readonly config: AppConfig,
    resend?: ResendClient,
  ) {
    const apiKey = config.RESEND_API_KEY.trim();
    this.resend = resend ?? (apiKey ? new Resend(apiKey) : undefined);
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

    const message = buildEmailConfirmationMessage(input);
    const result = await this.resend.emails.send({
      from: this.config.RESEND_FROM_EMAIL,
      to: input.to,
      ...message,
    });

    if (result.error) {
      throw new Error("Unable to send confirmation email");
    }
  }
}

export function buildEmailConfirmationMessage(
  input: EmailConfirmationInput,
): EmailConfirmationMessage {
  const locale = resolveEmailLocale(input.locale);
  const copy = emailCopy(locale, input);

  return {
    subject: copy.subject,
    text: confirmationEmailText(input, copy),
    html: confirmationEmailHtml(input, locale, copy),
  };
}

function resolveEmailLocale(locale?: string): EmailLocale {
  return locale?.trim().toLowerCase().split(/[-_,;]/)[0] === "es" ? "es" : "en";
}

function emailCopy(locale: EmailLocale, input: EmailConfirmationInput): EmailCopy {
  const minutes = Math.max(1, Math.round(input.expiresInMinutes));

  if (locale === "es") {
    return {
      subject: "Confirma tu correo de BetterCalories",
      preheader: "Confirma tu correo y empieza a registrar tus comidas.",
      greeting: `Hola, ${input.displayName}`,
      heading: "Confirma tu correo",
      body: "Confirma tu cuenta para empezar a registrar tus comidas con BetterCalories.",
      cta: "Confirmar correo",
      expiry: minutes === 1
        ? "Este enlace caduca en 1 minuto."
        : `Este enlace caduca en ${minutes} minutos.`,
      fallback: "Si el botón no funciona, copia y pega este enlace en tu navegador:",
      securityTitle: "Tu seguridad es importante",
      securityBody: "Este enlace es único para tu cuenta. No lo compartas con nadie.",
      ignore: "Si no has creado esta cuenta, puedes ignorar este correo.",
      tagline: "Registro sencillo, decisiones claras.",
    };
  }

  return {
    subject: "Confirm your BetterCalories email",
    preheader: "Confirm your email and start logging your meals.",
    greeting: `Hi, ${input.displayName}`,
    heading: "Confirm your email",
    body: "Confirm your account to start logging your meals with BetterCalories.",
    cta: "Confirm email",
    expiry: minutes === 1
      ? "This link expires in 1 minute."
      : `This link expires in ${minutes} minutes.`,
    fallback: "If the button does not work, copy and paste this link into your browser:",
    securityTitle: "Your security matters",
    securityBody: "This link is unique to your account. Do not share it with anyone.",
    ignore: "If you did not create this account, you can ignore this email.",
    tagline: "Simple tracking, clearer choices.",
  };
}

function confirmationEmailText(
  input: EmailConfirmationInput,
  copy: EmailCopy,
): string {
  return [
    copy.greeting,
    "",
    copy.heading,
    copy.body,
    "",
    `${copy.cta}: ${input.confirmationUrl}`,
    copy.expiry,
    "",
    copy.securityTitle,
    copy.securityBody,
    copy.ignore,
    "",
    `BetterCalories · ${copy.tagline}`,
  ].join("\n");
}

function confirmationEmailHtml(
  input: EmailConfirmationInput,
  locale: EmailLocale,
  copy: EmailCopy,
): string {
  const escapedUrl = escapeHtml(input.confirmationUrl);
  const escapedCopy = Object.fromEntries(
    Object.entries(copy).map(([key, value]) => [key, escapeHtml(value)]),
  ) as EmailCopy;

  return `<!doctype html>
<html lang="${locale}">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="color-scheme" content="light only">
    <meta name="supported-color-schemes" content="light">
    <title>${escapedCopy.subject}</title>
    <style>
      :root { color-scheme: light only; }
      body, table, td, a { -webkit-text-size-adjust: 100%; -ms-text-size-adjust: 100%; }
      table, td { mso-table-lspace: 0pt; mso-table-rspace: 0pt; }
      table { border-collapse: collapse !important; }
      body { width: 100% !important; min-width: 100%; margin: 0 !important; padding: 0 !important; background: #f0f0ef; }
      a[x-apple-data-detectors] { color: inherit !important; text-decoration: none !important; }
      @media screen and (max-width: 620px) {
        .page-pad { padding: 12px !important; }
        .header-pad { padding: 24px 22px 28px !important; }
        .content-pad { padding: 30px 22px 26px !important; }
        .footer-pad { padding: 22px !important; }
        .headline { font-size: 30px !important; line-height: 34px !important; }
        .cta-cell { padding: 15px 18px !important; }
      }
    </style>
  </head>
  <body>
    <div style="display:none;font-size:1px;color:#f0f0ef;line-height:1px;max-height:0;max-width:0;opacity:0;overflow:hidden;mso-hide:all;">
      ${escapedCopy.preheader}&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;&nbsp;&#847;&zwnj;
    </div>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;background:#f0f0ef;">
      <tr>
        <td class="page-pad" align="center" style="padding:28px 12px;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;background:#fbfbf8;border:1px solid #e3e4df;border-radius:28px;overflow:hidden;">
            <tr>
              <td class="header-pad" style="padding:30px 38px 34px;background:#edf8d2;">
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
                  <tr>
                    <td valign="middle">
                      <span style="color:#080907;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:20px;font-weight:750;letter-spacing:-0.4px;">BetterCalories</span>
                    </td>
                  </tr>
                  <tr>
                    <td align="center" style="padding-top:32px;">
                      <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                        <tr>
                          <td align="center" valign="middle" width="72" height="72" style="width:72px;height:72px;border-radius:36px;background:#fbfbf8;color:#5f8d00;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI Symbol',Arial,sans-serif;font-size:38px;font-weight:700;line-height:72px;">&#10003;</td>
                        </tr>
                      </table>
                    </td>
                  </tr>
                  <tr>
                    <td class="headline" align="center" style="padding-top:18px;color:#080907;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:34px;font-weight:800;line-height:39px;letter-spacing:-1.1px;">
                      ${escapedCopy.heading}
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td class="content-pad" style="padding:36px 38px 30px;background:#fbfbf8;">
                <p style="margin:0 0 10px;color:#080907;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:17px;font-weight:700;line-height:25px;">${escapedCopy.greeting}</p>
                <p style="margin:0 0 26px;color:#50534e;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:16px;font-weight:400;line-height:25px;">${escapedCopy.body}</p>
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;">
                  <tr>
                    <td class="cta-cell" align="center" style="padding:16px 22px;border-radius:999px;background:#9ad32a;">
                      <a href="${escapedUrl}" target="_blank" style="display:block;color:#080907;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:16px;font-weight:800;line-height:20px;text-align:center;text-decoration:none;">${escapedCopy.cta}</a>
                    </td>
                  </tr>
                </table>
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;">
                  <tr>
                    <td align="center" style="padding:15px 0 28px;color:#72756f;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:13px;line-height:19px;"><span style="color:#6d9f00;font-size:18px;line-height:13px;vertical-align:-1px;">&#8226;</span>&nbsp; ${escapedCopy.expiry}</td>
                  </tr>
                </table>
                <div style="height:1px;background:#e3e4df;line-height:1px;font-size:1px;">&nbsp;</div>
                <p style="margin:24px 0 10px;color:#72756f;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:13px;line-height:19px;">${escapedCopy.fallback}</p>
                <div style="padding:13px 15px;border:1px solid #dfe2d9;border-radius:14px;background:#f5f6f1;word-break:break-all;overflow-wrap:anywhere;">
                  <a href="${escapedUrl}" target="_blank" style="color:#466900;font-family:ui-monospace,SFMono-Regular,Consolas,'Liberation Mono',monospace;font-size:12px;line-height:18px;text-decoration:underline;word-break:break-all;overflow-wrap:anywhere;">${escapedUrl}</a>
                </div>
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="width:100%;margin-top:26px;">
                  <tr>
                    <td width="34" valign="top" style="width:34px;color:#5f8d00;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI Symbol',Arial,sans-serif;font-size:20px;line-height:24px;">&#9673;</td>
                    <td valign="top">
                      <p style="margin:0 0 3px;color:#080907;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:14px;font-weight:750;line-height:21px;">${escapedCopy.securityTitle}</p>
                      <p style="margin:0;color:#72756f;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:13px;line-height:20px;">${escapedCopy.securityBody}</p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
            <tr>
              <td class="footer-pad" align="center" style="padding:24px 38px;background:#f7f7f5;border-top:1px solid #e3e4df;">
                <p style="margin:0 0 8px;color:#72756f;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:12px;line-height:18px;">${escapedCopy.ignore}</p>
                <p style="margin:0;color:#9a9d97;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;font-size:11px;line-height:17px;">BetterCalories &middot; ${escapedCopy.tagline}</p>
              </td>
            </tr>
          </table>
        </td>
      </tr>
    </table>
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
