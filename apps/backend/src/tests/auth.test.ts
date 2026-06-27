import { describe, expect, it } from "vitest";
import type { GoogleTokenVerifier } from "../auth/google.js";
import { buildTestApp, FakeAuthEmailSender, registerAndAuth } from "./testApp.js";

describe("auth routes", () => {
  it("registers pending accounts by email and confirms them once", async () => {
    const authEmailSender = new FakeAuthEmailSender();
    const { request, repository } = buildTestApp({ authEmailSender });

    const register = await request("http://localhost/v1/auth/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "test@example.com",
        password: "password123",
        displayName: "Test User"
      })
    });
    expect(register.status).toBe(200);
    expect(await register.json()).toEqual({ ok: true, email: "test@example.com" });
    await expect(repository.findUserByEmail("test@example.com")).resolves.toBeUndefined();
    expect(authEmailSender.confirmations).toHaveLength(1);

    const confirm = await request("http://localhost/v1/auth/email/confirm", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: authEmailSender.latestConfirmationToken() })
    });
    expect(confirm.status).toBe(200);
    const body = await confirm.json() as { accessToken: string; refreshToken: string; user: { email: string; emailVerifiedAt?: string } };
    expect(body.accessToken).toBeTruthy();
    expect(body.refreshToken).toBeTruthy();
    expect(body.user.email).toBe("test@example.com");
    expect(body.user.emailVerifiedAt).toBeTruthy();

    const reuse = await request("http://localhost/v1/auth/email/confirm", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: authEmailSender.latestConfirmationToken() })
    });
    expect(reuse.status).toBe(400);
    expect(await reuse.json()).toMatchObject({
      error: { code: "invalid_email_confirmation_token" }
    });
  });

  it("registers, logs in, refreshes, returns me, and logs out", async () => {
    const { request } = buildTestApp();
    const registered = await registerAndAuth(request);

    expect(registered.accessToken).toBeTruthy();
    expect(registered.refreshToken).toBeTruthy();

    const me = await request("http://localhost/v1/auth/me", { headers: registered.authHeader });
    expect(me.status).toBe(200);
    expect((await me.json() as { email: string }).email).toBe("test@example.com");

    const login = await request("http://localhost/v1/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "test@example.com", password: "password123" })
    });
    expect(login.status).toBe(200);

    const refresh = await request("http://localhost/v1/auth/refresh", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refreshToken: registered.refreshToken })
    });
    expect(refresh.status).toBe(200);
    const refreshed = await refresh.json() as { accessToken: string; refreshToken: string };
    expect(refreshed.accessToken).toBeTruthy();
    expect(refreshed.refreshToken).not.toBe(registered.refreshToken);

    const logout = await request("http://localhost/v1/auth/logout", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refreshToken: refreshed.refreshToken })
    });
    expect(logout.status).toBe(200);
  });

  it("stores reset token hashes and accepts the dev reset token once", async () => {
    const { request } = buildTestApp();
    await registerAndAuth(request);
    const resetRequest = await request("http://localhost/v1/auth/password-reset/request", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "test@example.com" })
    });
    expect(resetRequest.status).toBe(200);
    const { resetToken } = await resetRequest.json() as { resetToken: string };
    expect(resetToken).toBeTruthy();

    const confirm = await request("http://localhost/v1/auth/password-reset/confirm", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: resetToken, newPassword: "newpassword123" })
    });
    expect(confirm.status).toBe(200);
    expect(await confirm.json()).toEqual({ ok: true });
  });

  it("rejects invalid registration email with a safe validation message", async () => {
    const { request } = buildTestApp();
    const response = await request("http://localhost/v1/auth/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "demo444422iii§@example.com",
        password: "password123",
        displayName: "Test User"
      })
    });

    expect(response.status).toBe(400);
    const body = await response.json() as { error: { code: string; message: string } };
    expect(body.error.code).toBe("validation_error");
    expect(body.error.message).toBe("Invalid request");
  });

  it("rejects duplicate registration with actionable public copy", async () => {
    const { request } = buildTestApp();
    await registerAndAuth(request);

    const response = await request("http://localhost/v1/auth/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "test@example.com",
        password: "password123",
        displayName: "Test User"
      })
    });

    expect(response.status).toBe(409);
    expect(await response.json()).toMatchObject({
      error: {
        code: "email_already_registered",
        message: "An account already exists for this email"
      }
    });
  });

  it("blocks password login before email confirmation", async () => {
    const { request } = buildTestApp();
    const register = await request("http://localhost/v1/auth/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "test@example.com",
        password: "password123",
        displayName: "Test User"
      })
    });
    expect(register.status).toBe(200);

    const login = await request("http://localhost/v1/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "test@example.com", password: "password123" })
    });
    expect(login.status).toBe(403);
    expect(await login.json()).toMatchObject({
      error: { code: "email_not_verified" }
    });

    const wrongPassword = await request("http://localhost/v1/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "test@example.com", password: "wrongpassword" })
    });
    expect(wrongPassword.status).toBe(401);
    expect(await wrongPassword.json()).toMatchObject({
      error: { code: "invalid_credentials" }
    });
  });

  it("keeps email and password login failures generic", async () => {
    const { request } = buildTestApp();
    await registerAndAuth(request);

    const response = await request("http://localhost/v1/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "test@example.com", password: "wrongpassword" })
    });

    expect(response.status).toBe(401);
    expect(await response.json()).toMatchObject({
      error: {
        code: "invalid_credentials",
        message: "Invalid email or password"
      }
    });
  });

  it("creates a session for a verified Google identity", async () => {
    const { request } = buildTestApp({
      googleTokenVerifier: new FakeGoogleTokenVerifier({
        subject: "google-sub-1",
        email: "google@example.com",
        displayName: "Google User"
      })
    });

    const login = await request("http://localhost/v1/auth/google/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ idToken: "valid-google-token" })
    });
    expect(login.status).toBe(200);
    const body = await login.json() as { accessToken: string; refreshToken: string; user: { email: string; displayName: string } };
    expect(body.accessToken).toBeTruthy();
    expect(body.refreshToken).toBeTruthy();
    expect(body.user.email).toBe("google@example.com");
    expect(body.user.displayName).toBe("Google User");

    const me = await request("http://localhost/v1/auth/me", {
      headers: { authorization: `Bearer ${body.accessToken}` }
    });
    expect(me.status).toBe(200);
  });

  it("links Google login to an existing verified email", async () => {
    const { request, repository } = buildTestApp({
      googleTokenVerifier: new FakeGoogleTokenVerifier({
        subject: "google-sub-existing",
        email: "test@example.com",
        displayName: "Google Name"
      })
    });
    const registered = await registerAndAuth(request);

    const login = await request("http://localhost/v1/auth/google/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ idToken: "valid-google-token" })
    });
    expect(login.status).toBe(200);
    const body = await login.json() as { user: { id: string; email: string; displayName: string } };
    expect(body.user.id).toBe(registered.user.id);
    expect(body.user.email).toBe("test@example.com");
    expect(body.user.displayName).toBe("Test User");
    await expect(repository.findAuthIdentity("google", "google-sub-existing")).resolves.toMatchObject({
      userId: registered.user.id,
      email: "test@example.com"
    });
  });

  it("rejects invalid Google tokens", async () => {
    const { request } = buildTestApp({
      googleTokenVerifier: {
        async verify() {
          throw new Error("invalid");
        }
      }
    });

    const login = await request("http://localhost/v1/auth/google/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ idToken: "bad-token" })
    });
    expect(login.status).toBe(401);
    expect(await login.json()).toMatchObject({
      error: { code: "invalid_google_token" }
    });
  });
});

class FakeGoogleTokenVerifier implements GoogleTokenVerifier {
  constructor(private readonly claims: Awaited<ReturnType<GoogleTokenVerifier["verify"]>>) {}

  async verify(): Promise<Awaited<ReturnType<GoogleTokenVerifier["verify"]>>> {
    return this.claims;
  }
}
