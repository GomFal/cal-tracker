import { SignJWT, jwtVerify } from "jose";
import type { PermissionScope } from "@cal-tracker/contracts";
import type { AppConfig } from "../config/env.js";

export type AdminTokenClaims = {
  sub: "admin";
  username: string;
  scopes: PermissionScope[];
};

const encoder = new TextEncoder();

export async function signAdminToken(
  config: AppConfig,
  input: { username: string; scopes: PermissionScope[] },
): Promise<{ token: string; expiresAt: string }> {
  const expiresAt = new Date(Date.now() + config.ADMIN_PANEL_TOKEN_TTL_SECONDS * 1000);
  const token = await new SignJWT({
    username: input.username,
    scopes: input.scopes,
    token_use: "admin_panel",
  })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject("admin")
    .setIssuer("bettercalories-admin")
    .setAudience("bettercalories.admin")
    .setIssuedAt()
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
    .sign(encoder.encode(config.ADMIN_PANEL_TOKEN_SECRET));

  return { token, expiresAt: expiresAt.toISOString() };
}

export async function verifyAdminToken(config: AppConfig, token: string): Promise<AdminTokenClaims> {
  const { payload } = await jwtVerify(token, encoder.encode(config.ADMIN_PANEL_TOKEN_SECRET), {
    issuer: "bettercalories-admin",
    audience: "bettercalories.admin",
    subject: "admin",
  });

  return {
    sub: "admin",
    username: typeof payload.username === "string" ? payload.username : "",
    scopes: Array.isArray(payload.scopes) ? (payload.scopes as PermissionScope[]) : [],
  };
}
