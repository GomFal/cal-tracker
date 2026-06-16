import { errors } from "jose";
import {
  adminTelemetryScopes,
  PermissionScope,
  type AdminLoginRequest,
  type AdminTokenResponse,
} from "@cal-tracker/contracts";
import type { AppConfig } from "../config/env.js";
import { verifyPassword } from "./passwords.js";
import { signAdminToken, verifyAdminToken, type AdminTokenClaims } from "./adminTokens.js";

type AdminAuthStatus = 401 | 403 | 503;

export class AdminAuthError extends Error {
  constructor(
    public readonly code: string,
    message = code,
    public readonly status: AdminAuthStatus = 401,
  ) {
    super(message);
  }
}

export class AdminAuthService {
  constructor(private readonly config: AppConfig) {}

  isEnabled(): boolean {
    return this.config.adminPanelEnabled;
  }

  async login(input: AdminLoginRequest): Promise<AdminTokenResponse> {
    this.ensureEnabled();
    const username = input.username.trim().toLowerCase();
    if (username !== this.config.adminPanelUsername) {
      throw new AdminAuthError("invalid_admin_credentials", "Invalid admin credentials");
    }

    let passwordMatches = false;
    try {
      passwordMatches = await verifyPassword(this.config.ADMIN_PANEL_PASSWORD_HASH, input.password);
    } catch {
      throw new AdminAuthError("admin_panel_misconfigured", "Admin panel is not configured correctly", 503);
    }

    if (!passwordMatches) {
      throw new AdminAuthError("invalid_admin_credentials", "Invalid admin credentials");
    }

    const { token, expiresAt } = await signAdminToken(this.config, {
      username: this.config.adminPanelUsername,
      scopes: adminTelemetryScopes,
    });

    return {
      accessToken: token,
      expiresAt,
      tokenType: "Bearer",
      scope: adminTelemetryScopes.join(" "),
      username: this.config.adminPanelUsername,
    };
  }

  async authenticate(authorizationHeader: string | undefined): Promise<AdminTokenClaims> {
    this.ensureEnabled();
    if (!authorizationHeader?.startsWith("Bearer ")) {
      throw new AdminAuthError("admin_token_required", "Admin token required");
    }

    const rawToken = authorizationHeader.slice("Bearer ".length).trim();
    if (!rawToken) {
      throw new AdminAuthError("admin_token_required", "Admin token required");
    }

    try {
      const claims = await verifyAdminToken(this.config, rawToken);
      if (!claims.scopes.includes(PermissionScope.AdminTelemetryRead)) {
        throw new AdminAuthError("admin_scope_required", "Admin telemetry scope required", 403);
      }
      return claims;
    } catch (error) {
      if (error instanceof AdminAuthError) throw error;
      if (error instanceof errors.JWTExpired || error instanceof errors.JWTClaimValidationFailed) {
        throw new AdminAuthError("token_expired", "Admin token expired or invalid");
      }
      throw new AdminAuthError("admin_token_invalid", "Admin token invalid");
    }
  }

  private ensureEnabled(): void {
    if (!this.config.adminPanelEnabled) {
      throw new AdminAuthError("admin_panel_disabled", "Admin panel auth is disabled", 503);
    }
  }
}
