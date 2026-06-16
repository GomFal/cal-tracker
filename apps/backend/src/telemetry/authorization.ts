import {
  adminTelemetryScopes,
  defaultUserScopes,
  PermissionScope,
} from "@cal-tracker/contracts";
import type { AppConfig } from "../config/env.js";
import type { StoredUser } from "../repository/types.js";

export function isAdminUser(user: StoredUser, config: AppConfig): boolean {
  return config.adminEmails.includes(user.email.toLowerCase());
}

export function resolveUserScopes(user: StoredUser, config: AppConfig): PermissionScope[] {
  const merged = new Set<PermissionScope>(defaultUserScopes);
  for (const scope of user.scopes) {
    merged.add(scope);
  }
  if (isAdminUser(user, config)) {
    for (const scope of adminTelemetryScopes) {
      merged.add(scope);
    }
  }
  return Array.from(merged);
}

export function hasAdminTelemetryRead(user: StoredUser, config: AppConfig): boolean {
  return resolveUserScopes(user, config).includes(PermissionScope.AdminTelemetryRead);
}
