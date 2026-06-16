import type { Context, Next } from "hono";
import { HTTPException } from "hono/http-exception";
import { errors } from "jose";
import type { AppConfig } from "../config/env.js";
import type { AppRepository, StoredUser } from "../repository/types.js";
import { verifyAccessToken } from "../auth/tokens.js";
import { resolveUserScopes } from "../telemetry/authorization.js";

export type AuthBindings = {
  Variables: {
    authUser: StoredUser;
    traceId: string;
  };
};

export function authMiddleware(config: AppConfig, repository: AppRepository) {
  return async (c: Context, next: Next) => {
    const auth = c.req.header("authorization");
    if (!auth?.startsWith("Bearer ")) {
      throw new HTTPException(401, { message: "Missing bearer token" });
    }
    try {
      const claims = await verifyAccessToken(config, auth.slice("Bearer ".length));
      const user = await repository.findUserById(claims.sub);
      if (!user) throw new HTTPException(401, { message: "Invalid bearer token" });
      const mergedUser: StoredUser = {
        ...user,
        scopes: resolveUserScopes(user, config),
      };
      c.set("authUser", mergedUser);
      await next();
    } catch (error) {
      if (error instanceof errors.JWTExpired || error instanceof errors.JWTClaimValidationFailed) {
        throw new HTTPException(401, { message: "Token expired or invalid" });
      }
      throw error;
    }
  };
}
