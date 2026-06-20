import { describe, expect, it } from "vitest";
import type { MealItem } from "@cal-tracker/contracts";
import {
  buildToolContentForModel,
  resolveCandidateReferenceFromMessages,
} from "../agent/toolContent.js";
import type { AgentConversationMessageRecord } from "../repository/types.js";

describe("agent chat tool content", () => {
  it("keeps low-confidence nutrition candidates out of model-visible content", () => {
    const candidates = Array.from({ length: 10 }, (_, index) =>
      candidate(index + 1),
    );
    const mappedResult = {
      kind: "nutrition_search",
      message: "I found matching nutrition items.",
      items: candidates,
      candidateGroups: [
        {
          mention: { originalText: "pan", canonicalName: "pan" },
          candidates,
        },
      ],
      options: [
        {
          mention: { originalText: "pan", canonicalName: "pan" },
          candidates,
        },
      ],
    };
    const built = buildToolContentForModel({
      actionId: "search_nutrition_database",
      actionCallId: "action-search-1",
      toolInput: { query: "pan" },
      mappedResult,
      rawOutput: {
        items: candidates,
        candidates: mappedResult.candidateGroups,
        candidateGroups: mappedResult.candidateGroups,
      },
      threshold: 0.75,
    });

    expect(built.selectionState).toMatchObject({
      status: "awaiting_user_selection",
      searchRef: "action-search-1",
      candidateCount: 10,
    });
    expect(built.modelContentApproxTokens).toBeLessThan(
      Math.ceil(built.rawContentApproxTokens * 0.2),
    );

    const content = JSON.stringify(built.contentValue);
    expect(JSON.parse(content)).toEqual(built.contentValue);
    expect(content).not.toContain("candidateGroups");
    expect(content).not.toContain("candidates");
    expect(content).not.toContain("rawOutput");
    expect(content).not.toContain("sourceUrl");
    expect(content).not.toContain("license");
    expect(content).not.toContain("displayDetails");
    expect(built.candidateRegistry?.groups[0]?.candidates).toHaveLength(10);
  });

  it("resolves a candidate outside the model-visible payload from metadata", () => {
    const candidates = Array.from({ length: 10 }, (_, index) =>
      candidate(index + 1),
    );
    const built = buildToolContentForModel({
      actionId: "search_nutrition_database",
      actionCallId: "action-search-2",
      toolInput: { query: "bread" },
      mappedResult: {
        kind: "nutrition_search",
        message: "I found matching nutrition items.",
        items: candidates,
        candidateGroups: [{ candidates }],
      },
      rawOutput: { items: candidates, candidateGroups: [{ candidates }] },
      threshold: 0.75,
    });
    const messages: AgentConversationMessageRecord[] = [
      {
        id: "message-1",
        conversationId: "conversation-1",
        userId: "user-1",
        role: "tool",
        content: JSON.stringify(built.contentValue),
        metadata: { candidateRegistry: built.candidateRegistry },
        createdAt: new Date().toISOString(),
      },
    ];

    const resolved = resolveCandidateReferenceFromMessages(messages, {
      searchRef: "action-search-2",
      groupIndex: 1,
      candidateIndex: 6,
    });

    expect(resolved?.candidateRef).toBe("action-search-2:g1:c6");
    expect(resolved?.item.name).toBe("Candidate 6");
  });
});

function candidate(rank: number): MealItem {
  return {
    name: `Candidate ${rank}`,
    quantity: 100,
    unit: "g",
    calories: 200 + rank,
    proteinGrams: 5,
    carbsGrams: 30,
    fatGrams: 4,
    source: "database",
    originalText: "pan",
    canonicalName: `candidate ${rank}`,
    externalSource: "test",
    externalId: `food-${rank}`,
    sourceUrl: `https://example.com/foods/${rank}`,
    license: "verbose license text",
    confidence: 0.6,
    needsReview: true,
    displayDetails: [
      "detail one",
      "detail two",
      "detail three",
      "detail four",
    ],
    rank,
    matchScore: 0.6,
  };
}
