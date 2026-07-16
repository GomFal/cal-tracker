export const PUBLIC_AI_ERROR_CODES = [
  "validation_error",
  "authentication_required",
  "rate_limit_exceeded",
  "provider_unavailable",
  "internal_error",
] as const;

export type PublicAiErrorCode = (typeof PUBLIC_AI_ERROR_CODES)[number];

export type PublicAiError = {
  code: PublicAiErrorCode;
  message: string;
  traceId: string;
};

export class PublicAiErrorException extends Error {
  readonly publicError: PublicAiError;

  constructor(
    code: PublicAiErrorCode,
    traceId: string,
    public readonly status: 400 | 401 | 429 | 500 | 503,
    cause?: unknown,
  ) {
    const error = createPublicAiError(code, traceId);
    super(error.message, { cause });
    this.name = "PublicAiErrorException";
    this.publicError = error;
  }
}

export function createPublicAiError(
  code: PublicAiErrorCode,
  traceId: string,
): PublicAiError {
  return { code, message: publicAiErrorMessage(code), traceId };
}

export function publicAiErrorMessage(code: PublicAiErrorCode): string {
  switch (code) {
    case "validation_error":
      return "Check the request and try again.";
    case "authentication_required":
      return "Sign in to continue.";
    case "rate_limit_exceeded":
      return "You have reached the current limit. Try again later.";
    case "provider_unavailable":
      return "The nutrition assistant is temporarily unavailable. Try again shortly.";
    case "internal_error":
      return "We could not complete that request. Try again.";
  }
}

export function publicAiErrorStatus(code: PublicAiErrorCode): 400 | 401 | 429 | 500 | 503 {
  switch (code) {
    case "validation_error":
      return 400;
    case "authentication_required":
      return 401;
    case "rate_limit_exceeded":
      return 429;
    case "provider_unavailable":
      return 503;
    case "internal_error":
      return 500;
  }
}

export function classifyPublicAiError(
  error: unknown,
  fallback: PublicAiErrorCode = "internal_error",
): PublicAiErrorCode {
  if (error instanceof PublicAiErrorException) return error.publicError.code;
  const code = readErrorCode(error);
  if (
    code === "agent_provider_unavailable" ||
    code === "stt_provider_unavailable" ||
    code === "usual_food_draft_provider_unavailable" ||
    code === "usual_meal_draft_provider_unavailable" ||
    code === "provider_unavailable"
  ) {
    return "provider_unavailable";
  }
  if (code === "rate_limit_exceeded") return "rate_limit_exceeded";
  if (
    code === "authentication_required" ||
    code === "token_expired" ||
    code === "invalid_refresh_token" ||
    code === "permission_denied"
  ) {
    return "authentication_required";
  }
  if (code === "validation_error" || code?.startsWith("invalid_")) {
    return "validation_error";
  }
  return fallback;
}

export function isPublicAiEndpoint(path: string): boolean {
  return (
    path === "/v1/agent/chat" ||
    path === "/v1/agent/chat/audio" ||
    path === "/v1/agent/runs" ||
    path === "/v1/meal-templates/draft" ||
    path.startsWith("/v1/stt/") ||
    path === "/v1/usual-foods/draft" ||
    path.startsWith("/v1/voice/") ||
    /^\/v1\/actions\/(?:draft_usual_food|draft_usual_meal)\/execute$/.test(path)
  );
}

function readErrorCode(error: unknown): string | undefined {
  if (typeof error !== "object" || error === null) return undefined;
  const code = (error as { code?: unknown }).code;
  return typeof code === "string" ? code : undefined;
}
