import { describe, expect, it } from "vitest";
import { PermissionScope } from "@cal-tracker/contracts";
import { buildSystemMessage } from "../agent/agentMessages.js";

describe("agent system message", () => {
  it("guides propose_meal_log occurredAt without requiring extra repair calls", () => {
    const message = buildSystemMessage({
      actorUserId: "00000000-0000-0000-0000-000000000000",
      actorType: "user",
      source: "flutter",
      scopes: [PermissionScope.NutritionWritePropose],
      timezone: "Europe/Madrid",
      locale: "es-ES",
      trustedModeEnabled: false,
      traceId: "trace-test",
    });

    expect(message.content).toContain("omit occurredAt unless");
    expect(message.content).toContain("part-of-day language in any language");
    expect(message.content).toContain("UTC ISO 8601 with Z");
    expect(message.content).toContain("Do not output local offset datetimes");
  });
});
