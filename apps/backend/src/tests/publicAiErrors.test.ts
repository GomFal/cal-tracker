import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  classifyPublicAiError,
  createPublicAiError,
  publicAiErrorStatus,
} from "../errors/publicAiErrors.js";
import { createLocalRunLogger } from "../observability/localRunLogger.js";
import {
  redactSensitiveLogValue,
  safeErrorDiagnostic,
  safeErrorDiagnosticMessage,
} from "../observability/sensitiveDataRedaction.js";
import { buildTestApp } from "./testApp.js";

const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories.splice(0).map((directory) =>
      rm(directory, { recursive: true, force: true })
    ),
  );
});

describe("public AI errors", () => {
  it("keeps a stable client envelope with a correlation trace", () => {
    expect(createPublicAiError("provider_unavailable", "trace-public")).toEqual({
      code: "provider_unavailable",
      message:
        "The nutrition assistant is temporarily unavailable. Try again shortly.",
      traceId: "trace-public",
    });
  });

  it.each([
    "usual_food_draft_provider_unavailable",
    "usual_meal_draft_provider_unavailable",
  ])("classifies %s as a temporary provider failure", (code) => {
    const error = Object.assign(new Error(code), { code });
    const category = classifyPublicAiError(error, "validation_error");
    expect(category).toBe("provider_unavailable");
    expect(publicAiErrorStatus(category)).toBe(503);
  });

  it("turns arbitrary provider messages into fail-closed diagnostics", () => {
    const leaked =
      "Antonio comió arroz at https://provider.invalid/debug?token=secret sk_providersecret123";
    const diagnostic = safeErrorDiagnostic(new Error(leaked));
    const serialized = JSON.stringify(diagnostic);

    expect(diagnostic).toEqual(
      expect.objectContaining({
        name: "Error",
        messageLength: leaked.length,
        messageSha256: expect.stringMatching(/^[a-f0-9]{16}$/),
      }),
    );
    expect(serialized).not.toContain("Antonio");
    expect(serialized).not.toContain("provider.invalid");
    expect(serialized).not.toContain("providersecret");
  });

  it("redacts tainted structured log fields without traversing their content", () => {
    const leaked = "Antonio comió arroz at https://nested.invalid/private";
    const sanitized = redactSensitiveLogValue({
      traceId: "trace-nested",
      messages: [{ role: "user", content: leaked }],
      payload: { nested: [{ content: leaked }] },
      error: { message: leaked, stack: leaked },
      technical: {
        status: 503,
        messageLength: leaked.length,
        messageSha256: "0123456789abcdef",
      },
    });

    expect(sanitized).toEqual({
      traceId: "trace-nested",
      messages: "[redacted]",
      payload: "[redacted]",
      error: "[redacted]",
      technical: {
        status: 503,
        messageLength: leaked.length,
        messageSha256: "0123456789abcdef",
      },
    });
    expect(JSON.stringify(sanitized)).not.toContain("Antonio");
    expect(JSON.stringify(sanitized)).not.toContain("nested.invalid");
  });

  it("does not persist free-form error details in current JSONL or DB telemetry", async () => {
    const leaked =
      "Antonio comió pasta at https://logs.invalid/debug?key=secret sk_logsecret123";
    const directory = await mkdtemp(join(tmpdir(), "bettercalories-errors-"));
    temporaryDirectories.push(directory);
    const logger = createLocalRunLogger({ enabled: true, directory });
    await logger.log({
      traceId: "trace-log-redaction",
      errorMessage: leaked,
      errorDiagnostic: safeErrorDiagnostic(new Error(leaked)),
    });
    const [filename] = await readdir(directory);
    const persistedJsonl = await readFile(join(directory, filename!), "utf8");

    expect(persistedJsonl).toContain("trace-log-redaction");
    expect(persistedJsonl).toContain("messageSha256");
    expect(persistedJsonl).not.toContain("Antonio");
    expect(persistedJsonl).not.toContain("logs.invalid");
    expect(persistedJsonl).not.toContain("logsecret");

    const { telemetry } = buildTestApp();
    const persisted = await telemetry.recordEvent({
      traceId: "trace-db-redaction",
      eventType: "backend.ai_request_failed",
      surface: "backend",
      severity: "error",
      status: "failure",
      errorCode: "provider_unavailable",
      errorMessage: leaked,
    });
    expect(persisted?.traceId).toBe("trace-db-redaction");
    expect(persisted?.errorCode).toBe("provider_unavailable");
    expect(persisted?.errorMessage).toContain("messageSha256");
    expect(persisted?.errorMessage).toBe(safeErrorDiagnosticMessage(leaked));
    expect(persisted?.errorMessage).not.toContain("Antonio");
    expect(persisted?.errorMessage).not.toContain("logs.invalid");
    expect(persisted?.errorMessage).not.toContain("logsecret");
  });
});
