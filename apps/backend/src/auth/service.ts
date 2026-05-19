import { randomBytes } from "node:crypto";
import { defaultUserScopes, type AuthUser, type GoogleLoginRequest, type LoginRequest, type RegisterRequest, type TokenPair } from "@cal-tracker/contracts";
import type { AppConfig } from "../config/env.js";
import type { AppRepository } from "../repository/types.js";
import { newId } from "../utils/ids.js";
import { RemoteGoogleTokenVerifier, type GoogleTokenVerifier } from "./google.js";
import { hashPassword, verifyPassword } from "./passwords.js";
import { createRefreshToken, hashRefreshToken, refreshExpiry, signAccessToken } from "./tokens.js";

type AuthErrorStatus = 401 | 409;

export class AuthError extends Error {
  constructor(
    public readonly code: string,
    message = code,
    public readonly status: AuthErrorStatus = 401,
  ) {
    super(message);
  }
}

export class AuthService {
  constructor(
    private readonly config: AppConfig,
    private readonly repository: AppRepository,
    private readonly googleTokenVerifier: GoogleTokenVerifier = new RemoteGoogleTokenVerifier(config)
  ) {}

  async register(input: RegisterRequest): Promise<TokenPair> {
    if (await this.repository.findUserByEmail(input.email)) {
      throw new AuthError(
        "email_already_registered",
        "An account already exists for this email",
        409,
      );
    }
    const passwordHash = await hashPassword(input.password);
    let user;
    try {
      user = await this.repository.createUser({
        email: input.email,
        displayName: input.displayName,
        passwordHash,
        scopes: defaultUserScopes
      });
    } catch (error) {
      if (isDuplicateEmailError(error)) {
        throw new AuthError(
          "email_already_registered",
          "An account already exists for this email",
          409,
        );
      }
      throw error;
    }
    await this.repository.recordAuditEvent({
      userId: user.id,
      eventType: "auth.registered",
      metadata: { email: user.email },
      traceId: "auth-register"
    });
    return this.issueTokenPair(publicUser(user), user.scopes);
  }

  async login(input: LoginRequest): Promise<TokenPair> {
    const user = await this.repository.findUserByEmail(input.email);
    if (!user?.passwordHash || !(await verifyPassword(user.passwordHash, input.password))) {
      throw new AuthError("invalid_credentials", "Invalid email or password");
    }
    await this.repository.recordAuditEvent({
      userId: user.id,
      eventType: "auth.login_succeeded",
      metadata: { email: user.email },
      traceId: "auth-login"
    });
    return this.issueTokenPair(publicUser(user), user.scopes);
  }

  async loginWithGoogle(input: GoogleLoginRequest): Promise<TokenPair> {
    let claims;
    try {
      claims = await this.googleTokenVerifier.verify(input.idToken);
    } catch {
      throw new AuthError("invalid_google_token", "Invalid Google sign-in token");
    }

    const existingIdentity = await this.repository.findAuthIdentity("google", claims.subject);
    let user = existingIdentity ? await this.repository.findUserById(existingIdentity.userId) : undefined;
    if (!user) {
      user = await this.repository.findUserByEmail(claims.email);
    }
    if (!user) {
      user = await this.repository.createUser({
        email: claims.email,
        displayName: claims.displayName,
        scopes: defaultUserScopes
      });
    }

    await this.repository.linkAuthIdentity({
      userId: user.id,
      provider: "google",
      providerUserId: claims.subject,
      email: claims.email
    });
    await this.repository.recordAuditEvent({
      userId: user.id,
      eventType: "auth.google_login_succeeded",
      metadata: { email: user.email },
      traceId: "auth-google-login"
    });
    return this.issueTokenPair(publicUser(user), user.scopes);
  }

  async refresh(refreshToken: string): Promise<TokenPair> {
    const hashValue = hashRefreshToken(this.config, refreshToken);
    const session = await this.repository.findSessionByRefreshTokenHash(hashValue);
    if (!session) throw new AuthError("invalid_refresh_token", "Refresh token is invalid or expired");
    const user = await this.repository.findUserById(session.userId);
    if (!user) throw new AuthError("invalid_refresh_token", "Refresh token user no longer exists");

    const nextRefreshToken = createRefreshToken();
    await this.repository.rotateSession(session.id, hashRefreshToken(this.config, nextRefreshToken), refreshExpiry());
    const access = await signAccessToken(this.config, { sub: user.id, scopes: user.scopes });

    return {
      accessToken: access.token,
      refreshToken: nextRefreshToken,
      expiresAt: access.expiresAt,
      user: publicUser(user)
    };
  }

  async logout(refreshToken?: string): Promise<void> {
    if (!refreshToken) return;
    const session = await this.repository.findSessionByRefreshTokenHash(hashRefreshToken(this.config, refreshToken));
    if (session) await this.repository.revokeSession(session.id);
  }

  async logoutAll(userId: string): Promise<void> {
    await this.repository.revokeAllSessions(userId);
  }

  async requestPasswordReset(email: string): Promise<{ resetToken?: string }> {
    const user = await this.repository.findUserByEmail(email);
    if (!user) return {};
    const resetToken = randomBytes(40).toString("base64url");
    await this.repository.createPasswordReset({
      userId: user.id,
      tokenHash: hashRefreshToken(this.config, resetToken),
      expiresAt: new Date(Date.now() + 30 * 60 * 1000).toISOString()
    });
    await this.repository.recordAuditEvent({
      userId: user.id,
      eventType: "auth.password_reset_requested",
      metadata: {},
      traceId: "auth-reset"
    });
    return this.config.NODE_ENV === "production" ? {} : { resetToken };
  }

  async confirmPasswordReset(token: string, newPassword: string): Promise<boolean> {
    return this.repository.consumePasswordReset(hashRefreshToken(this.config, token), await hashPassword(newPassword));
  }

  private async issueTokenPair(user: AuthUser, scopes: typeof defaultUserScopes): Promise<TokenPair> {
    const refreshToken = createRefreshToken();
    const access = await signAccessToken(this.config, { sub: user.id, scopes });
    await this.repository.createSession({
      id: newId(),
      userId: user.id,
      refreshTokenHash: hashRefreshToken(this.config, refreshToken),
      expiresAt: refreshExpiry()
    });
    return {
      accessToken: access.token,
      refreshToken,
      expiresAt: access.expiresAt,
      user
    };
  }
}

function publicUser(user: AuthUser): AuthUser {
  return {
    id: user.id,
    email: user.email,
    displayName: user.displayName,
    trustedModeEnabled: user.trustedModeEnabled,
    createdAt: user.createdAt
  };
}

function isDuplicateEmailError(error: unknown): boolean {
  if (error instanceof Error && error.message === "email_already_registered") {
    return true;
  }
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const maybeDatabaseError = error as {
    code?: unknown;
    constraint_name?: unknown;
    constraint?: unknown;
  };
  return maybeDatabaseError.code === "23505" &&
    (
      maybeDatabaseError.constraint_name === "users_active_email_unique" ||
      maybeDatabaseError.constraint === "users_active_email_unique"
    );
}
