import { describe, expect, it } from "vitest";
import type { ActionContext } from "@cal-tracker/contracts";
import { buildSystemMessage } from "../agent/agentMessages.js";
import { buildToolSchemas } from "../agent/toolSchemas.js";

const context: ActionContext = {
  actorUserId: "00000000-0000-4000-8000-000000000001",
  actorType: "user",
  source: "flutter",
  scopes: [],
  timezone: "UTC",
  locale: "en-US",
  trustedModeEnabled: false,
  traceId: "test-trace",
};

describe("agent meal proposal language prompt schema", () => {
  it("explains canonical English names in the meal proposal system prompt", () => {
    const message = buildSystemMessage(context);

    expect(message.content).toContain(
      "set originalText to the exact food phrase",
    );
    expect(message.content).toContain(
      "set canonicalName to the normalized food name in the same language as that food phrase",
    );
    expect(message.content).toContain(
      "set canonicalEnglishName to the English generic food name when confidently known",
    );
    expect(message.content).toContain(
      "omit canonicalEnglishName when uncertain",
    );
    expect(message.content).toContain(
      "Set language to the language code of the food phrase when clear, not the app locale",
    );
    expect(message.content).toContain(
      "Preserve brand and product names as stated; do not invent translations",
    );
  });

  it("exposes canonical English name semantics in the propose_meal_log tool schema", () => {
    const tool = buildToolSchemas().find(
      (definition) => definition.function.name === "propose_meal_log",
    );

    expect(tool).toBeDefined();
    const parameters = JSON.stringify(tool?.function.parameters);
    expect(parameters).toContain("canonicalEnglishName");
    expect(parameters).toContain(
      "English generic food name when confidently known; omit when uncertain and do not invent translations.",
    );
    expect(parameters).toContain(
      "Normalized food name in the same language as originalText.",
    );
    expect(parameters).toContain(
      "Language code of originalText when clear; this is the food phrase language, not the app locale.",
    );
  });
});
