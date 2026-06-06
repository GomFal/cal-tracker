import type { Context } from "hono";
import { HTTPException } from "hono/http-exception";
import { errors } from "jose";
import { ZodError } from "zod";
import { ActionExecutionError } from "../actions/executor.js";
import { AgentProviderUnavailableError } from "../agent/agentService.js";
import { AuthError } from "../auth/service.js";
import { getTraceId } from "./requestContext.js";

export function formatErrorResponse(c: Context, error: unknown) {
  const traceId = getTraceId(c);
  if (error instanceof ZodError) {
    return c.json({ error: { code: "validation_error", message: "Invalid request", traceId, details: error.flatten() } }, 400);
  }
  if (error instanceof AuthError) {
    return c.json({ error: { code: error.code, message: authErrorMessage(error.code), traceId } }, error.status);
  }
  if (error instanceof errors.JWTExpired || error instanceof errors.JWTClaimValidationFailed) {
    return c.json({ error: { code: "token_expired", message: "Token expired or invalid", traceId } }, 401);
  }
  if (error instanceof ActionExecutionError) {
    const status = error.code === "permission_denied" ? 403 : 400;
    return c.json({ error: { code: error.code, message: actionErrorMessage(error.code), traceId } }, status);
  }
  if (error instanceof AgentProviderUnavailableError) {
    return c.json({
      error: {
        code: error.code,
        message: "An error occurred. Please, try again.",
        traceId,
      },
    }, 503);
  }
  if (error instanceof HTTPException) {
    return c.json({ error: { code: httpErrorCode(error.status), message: httpErrorMessage(error.status), traceId } }, error.status);
  }
  const message = error instanceof Error ? error.message : "Unexpected error";
  console.error("request.unhandled_error", {
    traceId,
    method: c.req.method,
    path: new URL(c.req.url).pathname,
    message,
    stack: error instanceof Error ? error.stack : undefined,
  });
  return c.json({ error: { code: "internal_error", message: "We could not complete that request. Try again.", traceId } }, 500);
}

function authErrorMessage(code: string): string {
  switch (code) {
    case "email_already_registered":
      return "An account already exists for this email";
    case "invalid_credentials":
      return "Invalid email or password";
    case "invalid_google_token":
      return "Google sign-in did not finish. Try again.";
    case "invalid_refresh_token":
      return "Sign in to continue.";
    default:
      return "We could not complete that request. Try again.";
  }
}

function actionErrorMessage(code: string): string {
  switch (code) {
    case "permission_denied":
      return "You do not have permission to do that.";
    case "meal_not_found":
      return "We could not find that meal.";
    case "proposal_not_found":
      return "We could not find that meal proposal.";
    case "template_not_found":
      return "We could not find that usual meal.";
    case "invalid_meal_label":
      return "Choose a valid meal label.";
    default:
      return "We could not complete that request. Try again.";
  }
}

function httpErrorCode(status: number): string {
  switch (status) {
    case 401:
      return "authentication_required";
    case 403:
      return "permission_denied";
    case 404:
      return "not_found";
    default:
      return "request_failed";
  }
}

function httpErrorMessage(status: number): string {
  switch (status) {
    case 401:
      return "Sign in to continue.";
    case 403:
      return "You do not have permission to do that.";
    case 404:
      return "We could not find that.";
    default:
      return "We could not complete that request. Try again.";
  }
}
