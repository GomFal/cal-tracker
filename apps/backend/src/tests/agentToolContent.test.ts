import { describe, expect, it } from "vitest";
import type { MealItem } from "@cal-tracker/contracts";
import {
  buildToolContentForModel,
  resolveCandidateReferenceFromMessages,
} from "../agent/toolContent.js";
import type { AgentConversationMessageRecord } from "../repository/types.js";

describe("agent chat tool content", () => {
  it("sends a compressed top-10 candidate preview to the model", () => {
    const candidates = Array.from({ length: 12 }, (_, index) =>
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
      status: "candidate_preview",
      searchRef: "action-search-1",
      candidateCount: 12,
    });
    expect(built.modelContentApproxTokens).toBeLessThan(
      Math.ceil(built.rawContentApproxTokens * 0.1),
    );

    const content = JSON.stringify(built.contentValue);
    expect(JSON.parse(content)).toEqual(built.contentValue);
    expect(content).toContain("candidatePreview");
    expect(content).toContain("cols=n|ref|name|qty|kcal|p|c|f|conf|score|src|id");
    expect(content).toContain("Candidate 10");
    expect(content).not.toContain("Candidate 11");
    expect(content).not.toContain("candidateGroups");
    expect(content).not.toContain("candidates");
    expect(content).not.toContain("rawOutput");
    expect(content).not.toContain("sourceUrl");
    expect(content).not.toContain("license");
    expect(content).not.toContain("displayDetails");
    expect(built.candidateRegistry?.groups[0]?.candidates).toHaveLength(12);
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
      candidateRef: "g1c6",
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
