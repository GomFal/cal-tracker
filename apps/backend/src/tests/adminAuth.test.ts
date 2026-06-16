import { describe, expect, it } from "vitest";
import { jwtVerify } from "jose";
import { buildTestApp } from "./testApp.js";

const encoder = new TextEncoder();

describe("admin auth", () => {
  it("issues a short-lived dedicated admin token for valid credentials", async () => {
    const { request, config } = buildTestApp();

    const response = await request("http://localhost/v1/admin/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "admin", password: "admin-password-123" })
    });

    expect(response.status).toBe(200);
    const body = await response.json() as {
      accessToken: string;
      expiresAt: string;
      tokenType: string;
      scope: string;
      username: string;
      refreshToken?: string;
    };
    expect(body.tokenType).toBe("Bearer");
    expect(body.username).toBe("admin");
    expect(body.scope).toContain("admin.telemetry.read");
    expect(body.scope).toContain("admin.telemetry.write");
    expect(body.refreshToken).toBeUndefined();

    const { payload } = await jwtVerify(body.accessToken, encoder.encode(config.ADMIN_PANEL_TOKEN_SECRET), {
      issuer: "bettercalories-admin",
      audience: "bettercalories.admin",
      subject: "admin"
    });
    expect(payload.token_use).toBe("admin_panel");
    expect(payload.username).toBe("admin");
    expect(payload.scopes).toContain("admin.telemetry.read");
  });

  it("rejects invalid admin credentials with a generic error", async () => {
    const { request } = buildTestApp();

    const response = await request("http://localhost/v1/admin/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: "admin", password: "wrong-password" })
    });

    expect(response.status).toBe(401);
    const body = await response.json() as { error: { code: string; message: string } };
    expect(body.error.code).toBe("invalid_admin_credentials");
    expect(body.error.message).toBe("Invalid admin username or password.");
  });

  it("normalizes the configured admin username for login", async () => {
    const { request } = buildTestApp();

    const response = await request("http://localhost/v1/admin/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ username: " ADMIN ", password: "admin-password-123" })
    });

    expect(response.status).toBe(200);
  });
});
