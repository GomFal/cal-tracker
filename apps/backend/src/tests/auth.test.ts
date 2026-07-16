import { describe, expect, it, vi } from "vitest";
import type { GoogleTokenVerifier } from "../auth/google.js";
import { buildTestApp, FakeAuthEmailSender, registerAndAuth } from "./testApp.js";

describe("auth routes", () => {
  it("registers pending accounts by email and confirms them once", async () => {
    const authEmailSender = new FakeAuthEmailSender();
    const { request, repository } = buildTestApp({ authEmailSender });

    const register = await request("http://localhost/v1/auth/register", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "accept-language": "es-ES,es;q=0.9",
      },
      body: JSON.stringify({
        email: "test@example.com",
        password: "password123",
        displayName: "Test User"
      })
    });
    expect(register.status).toBe(200);
    expect(await register.json()).toEqual({ ok: true });
    await expect(repository.findUserByEmail("test@example.com")).resolves.toBeUndefined();
    expect(authEmailSender.confirmations).toHaveLength(1);
    expect(authEmailSender.confirmations[0]).toMatchObject({
      locale: "es-ES",
      expiresInMinutes: 30,
    });

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

  it("resets the password, revokes every refresh session, and records the security audit", async () => {
    const { request, repository, authEmailSender } = buildTestApp();
    const registered = await registerAndAuth(request);
    const secondLogin = await request("http://localhost/v1/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "test@example.com",
        password: "password123",
      }),
    });
    const secondSession = await secondLogin.json() as {
      accessToken: string;
      refreshToken: string;
    };

    const resetRequest = await request("http://localhost/v1/auth/password-reset/request", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "test@example.com" })
    });
    expect(resetRequest.status).toBe(200);
    expect(await resetRequest.json()).toEqual({ ok: true });
    expect(authEmailSender).toBeInstanceOf(FakeAuthEmailSender);
    const resetToken = (authEmailSender as FakeAuthEmailSender).latestPasswordResetToken();

    const confirm = await request("http://localhost/v1/auth/password-reset/confirm", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: resetToken, newPassword: "newpassword123" })
    });
    expect(confirm.status).toBe(200);
    expect(await confirm.json()).toEqual({ ok: true });

    const existingAccessToken = await request("http://localhost/v1/auth/me", {
      headers: { authorization: `Bearer ${registered.accessToken}` },
    });
    expect(existingAccessToken.status).toBe(200);

    for (const refreshToken of [registered.refreshToken, secondSession.refreshToken]) {
      const refresh = await request("http://localhost/v1/auth/refresh", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ refreshToken }),
      });
      expect(refresh.status).toBe(401);
      expect(await refresh.json()).toMatchObject({
        error: { code: "invalid_refresh_token" },
      });
    }

    const oldPasswordLogin = await request("http://localhost/v1/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "test@example.com",
        password: "password123",
      }),
    });
    expect(oldPasswordLogin.status).toBe(401);

    const newPasswordLogin = await request("http://localhost/v1/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "test@example.com",
        password: "newpassword123",
      }),
    });
    expect(newPasswordLogin.status).toBe(200);

    const reuse = await request("http://localhost/v1/auth/password-reset/confirm", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ token: resetToken, newPassword: "anotherpassword123" }),
    });
    expect(reuse.status).toBe(200);
    expect(await reuse.json()).toEqual({ ok: false });

    const audits = await repository.listAuditEvents(registered.user.id);
    const completedAudits = audits.filter(
      (event) => event.eventType === "auth.password_reset_completed",
    );
    expect(completedAudits).toHaveLength(1);
    expect(completedAudits[0]).toMatchObject({
      userId: registered.user.id,
      metadata: { sessionRevocation: "all" },
      traceId: "auth-reset-confirm",
    });
    expect(JSON.stringify(completedAudits[0])).not.toContain(resetToken);
    expect(JSON.stringify(completedAudits[0])).not.toContain("newpassword123");
  });

  it("returns session-ended semantics if a reset revokes the session during refresh", async () => {
    const { request, repository } = buildTestApp();
    const registered = await registerAndAuth(request);
    vi.spyOn(repository, "rotateSession").mockResolvedValueOnce(undefined);

    const refresh = await request("http://localhost/v1/auth/refresh", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ refreshToken: registered.refreshToken }),
    });

    expect(refresh.status).toBe(401);
    expect(await refresh.json()).toMatchObject({
      error: {
        code: "invalid_refresh_token",
        message: "Sign in to continue.",
      },
    });
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

  it("accepts duplicate registration neutrally without sending another email", async () => {
    const authEmailSender = new FakeAuthEmailSender();
    const { request } = buildTestApp({ authEmailSender });
    await registerAndAuth(request);
    expect(authEmailSender.confirmations).toHaveLength(1);

    const response = await request("http://localhost/v1/auth/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "test@example.com",
        password: "password123",
        displayName: "Test User"
      })
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
    expect(authEmailSender.confirmations).toHaveLength(1);
  });

  it("does not turn email delivery failures into an account-state oracle", async () => {
    const authEmailSender = new FakeAuthEmailSender();
    vi.spyOn(authEmailSender, "sendEmailConfirmation").mockRejectedValue(
      new Error("provider unavailable"),
    );
    const { request } = buildTestApp({ authEmailSender });

    const response = await request("http://localhost/v1/auth/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "new@example.com",
        password: "password123",
        displayName: "New User",
      }),
    });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
  });

  it("keeps registration responses equivalent for new, pending, and existing emails", async () => {
    const authEmailSender = new FakeAuthEmailSender();
    const { request } = buildTestApp({ authEmailSender });
    await registerAndAuth(request, { email: "existing@example.com" });

    await request("http://localhost/v1/auth/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "pending@example.com",
        password: "password123",
        displayName: "Pending User",
      }),
    });

    const cases = [
      { email: "new@example.com", displayName: "New User" },
      { email: "pending@example.com", displayName: "Pending User" },
      { email: "existing@example.com", displayName: "Existing User" },
    ];
    const durations: number[] = [];
    for (const item of cases) {
      const startedAt = performance.now();
      const response = await request("http://localhost/v1/auth/register", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          ...item,
          password: "password123",
        }),
      });
      durations.push(performance.now() - startedAt);
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ ok: true });
    }
    expect(Math.max(...durations) - Math.min(...durations)).toBeLessThan(150);
  });

  it("keeps password reset responses equivalent and emails only real accounts", async () => {
    const authEmailSender = new FakeAuthEmailSender();
    const { request } = buildTestApp({ authEmailSender });
    await registerAndAuth(request, { email: "existing@example.com" });
    await request("http://localhost/v1/auth/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "pending@example.com",
        password: "password123",
        displayName: "Pending User",
      }),
    });

    const durations: number[] = [];
    for (const email of [
      "existing@example.com",
      "pending@example.com",
      "missing@example.com",
    ]) {
      const startedAt = performance.now();
      const response = await request("http://localhost/v1/auth/password-reset/request", {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "accept-language": "es-ES",
        },
        body: JSON.stringify({ email }),
      });
      durations.push(performance.now() - startedAt);
      expect(response.status).toBe(200);
      expect(await response.json()).toEqual({ ok: true });
    }

    expect(authEmailSender.passwordResets).toHaveLength(1);
    expect(authEmailSender.passwordResets[0]).toMatchObject({
      to: "existing@example.com",
      locale: "es-ES",
    });
    expect(Math.max(...durations) - Math.min(...durations)).toBeLessThan(100);
  });

  it("provides a functional localized password reset link without exposing account state", async () => {
    const authEmailSender = new FakeAuthEmailSender();
    const { request } = buildTestApp({ authEmailSender });
    await registerAndAuth(request);

    const resetRequest = await request("http://localhost/v1/auth/password-reset/request", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "accept-language": "es-ES",
      },
      body: JSON.stringify({ email: "test@example.com" }),
    });
    expect(await resetRequest.json()).toEqual({ ok: true });

    const resetUrl = authEmailSender.passwordResets[0]?.resetUrl;
    expect(resetUrl).toContain("lang=es");
    const form = await request(resetUrl!);
    expect(form.status).toBe(200);
    const html = await form.text();
    expect(html).toContain("Restablece tu contraseña");
    expect(html).toContain('autocomplete="new-password"');

    const token = authEmailSender.latestPasswordResetToken();
    const confirm = await request("http://localhost/auth/password-reset/confirm", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        token,
        lang: "es",
        newPassword: "newpassword123",
        confirmPassword: "newpassword123",
      }),
    });
    expect(confirm.status).toBe(200);
    expect(await confirm.text()).toContain("Contraseña actualizada");

    const login = await request("http://localhost/v1/auth/login", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "test@example.com",
        password: "newpassword123",
      }),
    });
    expect(login.status).toBe(200);
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
