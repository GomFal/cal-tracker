import {
  draftUsualMealProviderOutputSchema,
  type DraftUsualMealProviderOutput,
} from "@cal-tracker/contracts";
import { zodToJsonSchema } from "zod-to-json-schema";
import type { ChatAgentProvider } from "./chatAgentProvider.js";

export interface UsualMealDraftProvider {
  draft(input: {
    text: string;
    locale: string;
    traceId: string;
  }): Promise<DraftUsualMealProviderOutput>;
}

export class UsualMealDraftProviderUnavailableError extends Error {
  readonly code = "usual_meal_draft_provider_unavailable";

  constructor() {
    super("usual_meal_draft_provider_unavailable");
    this.name = "UsualMealDraftProviderUnavailableError";
  }
}

export class ToolCallingUsualMealDraftProvider implements UsualMealDraftProvider {
  constructor(
    private readonly agentProvider: ChatAgentProvider,
    private readonly model: string,
  ) {}

  async draft(input: {
    text: string;
    locale: string;
    traceId: string;
  }): Promise<DraftUsualMealProviderOutput> {
    const decision = await this.agentProvider.runWithTools({
      model: this.model,
      traceId: input.traceId,
      messages: [
        {
          role: "system",
          content: usualMealDraftSystemPrompt(input.locale),
        },
        {
          role: "user",
          content: input.text,
        },
      ],
      tools: [
        {
          type: "function",
          function: {
            name: "return_usual_meal_draft",
            description:
              "Return a usual meal draft with a title, explicit aliases, and structured ingredient mentions.",
            parameters: zodToJsonSchema(
              draftUsualMealProviderOutputSchema,
            ) as Record<string, unknown>,
          },
        },
      ],
    });
    const call = decision.toolCalls.find(
      (toolCall) => toolCall.function.name === "return_usual_meal_draft",
    );
    if (!call) throw new UsualMealDraftProviderUnavailableError();
    return draftUsualMealProviderOutputSchema.parse(
      JSON.parse(call.function.arguments),
    );
  }
}

function usualMealDraftSystemPrompt(locale: string): string {
  return [
    "You extract review-only usual meal template drafts for BetterCalories.",
    `User locale: ${locale}.`,
    "Use the return_usual_meal_draft tool exactly once.",
    "Extract a concise meal title only when the user explicitly names the saved meal or the title is directly stated in the request.",
    "Extract aliases only when the user explicitly provides alternate names.",
    "Extract structured ingredient mentions for foods the user explicitly lists, preserving originalText, canonicalName in the user's language when possible, quantity, unit, rawUnitText, unitKind, brand/barcode when stated, confidence, and marketProduct.",
    "Do not invent nutrition facts, ingredients, translations, titles, aliases, quantities, or units.",
    "Do not infer missing ingredients from meal names or habits. If ingredients are missing, return an empty mentions array.",
    "Never save a meal template and never claim that missing ingredients are ready to save.",
  ].join(" ");
}
