import { createHash } from "node:crypto";

const REDACTED = "[redacted]";
const MAX_LOG_STRING_LENGTH = 2_000;

const SENSITIVE_KEY_TERMS = [
  "authorization",
  "cookie",
  "credential",
  "email",
  "filename",
  "inputtext",
  "assistanttext",
  "message",
  "password",
  "payload",
  "prompt",
  "query",
  "secret",
  "token",
  "transcript",
];

const SENSITIVE_EXACT_KEYS = new Set([
  "arguments",
  "body",
  "content",
  "error",
  "messages",
  "response",
  "resultsummary",
]);

export function redactSensitiveText(value: string): string {
  return value
    .replace(/\bBearer\s+[^\s,;]+/gi, `Bearer ${REDACTED}`)
    .replace(
      /\b([A-Za-z0-9_-]*(?:api[_-]?key|password|secret|token)[A-Za-z0-9_-]*)\s*[:=]\s*(["']?)[^\s,;&}"']+\2/gi,
      `$1=${REDACTED}`,
    )
    .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, REDACTED)
    .replace(/([?&](?:key|token|secret|signature|password)=)[^&#\s]+/gi, `$1${REDACTED}`)
    .replace(/\b(?:sk|gsk|pk)_[A-Za-z0-9_-]{12,}\b/g, REDACTED)
    .slice(0, MAX_LOG_STRING_LENGTH);
}

export function redactSensitiveLogValue(
  value: unknown,
  keyHint = "",
  depth = 0,
): unknown {
  if (isSensitiveKey(keyHint)) return REDACTED;
  if (value === null || value === undefined) return value;
  if (typeof value === "string") return redactSensitiveText(value);
  if (typeof value === "number" || typeof value === "boolean") return value;
  if (depth >= 5) return "[max_depth]";
  if (Array.isArray(value)) {
    return value.slice(0, 50).map((entry) =>
      redactSensitiveLogValue(entry, keyHint, depth + 1)
    );
  }
  if (typeof value === "object") {
    const result: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
      result[key] = redactSensitiveLogValue(entry, key, depth + 1);
    }
    return result;
  }
  return redactSensitiveText(String(value));
}

export function safeErrorDiagnostic(error: unknown): Record<string, unknown> {
  const message = error instanceof Error ? error.message : String(error);
  const diagnostic: Record<string, unknown> = {
    name: error instanceof Error ? error.name : "NonError",
    messageLength: message.length,
    messageSha256: createHash("sha256").update(message).digest("hex").slice(0, 16),
  };
  if (typeof error === "object" && error !== null) {
    const code = (error as { code?: unknown }).code;
    const status = (error as { status?: unknown }).status;
    if (typeof code === "string" && /^[a-z0-9_.-]{1,80}$/i.test(code)) {
      diagnostic.code = code;
    }
    if (typeof status === "number" && Number.isInteger(status)) {
      diagnostic.status = status;
    }
  }
  return diagnostic;
}

export function safeErrorDiagnosticMessage(error: unknown): string {
  return JSON.stringify(safeErrorDiagnostic(error));
}

function isSensitiveKey(key: string): boolean {
  const normalized = key.toLowerCase().replace(/[^a-z0-9]/g, "");
  if (!normalized) return false;
  if (
    normalized.endsWith("length") ||
    normalized.endsWith("count") ||
    normalized.endsWith("hash") ||
    normalized.endsWith("sha256") ||
    normalized.endsWith("present") ||
    normalized.endsWith("tokens") ||
    normalized.endsWith("chars")
  ) {
    return false;
  }
  if (SENSITIVE_EXACT_KEYS.has(normalized)) return true;
  return SENSITIVE_KEY_TERMS.some((term) => normalized.includes(term));
}
