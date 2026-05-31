import {
  draftUsualFoodProviderOutputSchema,
  type DraftUsualFoodProviderOutput,
} from "@cal-tracker/contracts";
import { zodToJsonSchema } from "zod-to-json-schema";
import type { ChatAgentProvider } from "./chatAgentProvider.js";

export interface UsualFoodDraftProvider {
  draft(input: {
    text: string;
    locale: string;
    traceId: string;
  }): Promise<DraftUsualFoodProviderOutput>;
}

export class UsualFoodDraftProviderUnavailableError extends Error {
  readonly code = "usual_food_draft_provider_unavailable";

  constructor() {
    super("usual_food_draft_provider_unavailable");
    this.name = "UsualFoodDraftProviderUnavailableError";
  }
}

export class ToolCallingUsualFoodDraftProvider implements UsualFoodDraftProvider {
  constructor(
    private readonly agentProvider: ChatAgentProvider,
    private readonly model: string,
  ) {}

  async draft(input: {
    text: string;
    locale: string;
    traceId: string;
  }): Promise<DraftUsualFoodProviderOutput> {
    const decision = await this.agentProvider.runWithTools({
      model: this.model,
      traceId: input.traceId,
      messages: [
        {
          role: "system",
          content: usualFoodDraftSystemPrompt(input.locale),
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
            name: "return_usual_food_draft",
            description:
              "Return a usual ingredient draft using only nutrition values explicitly stated by the user.",
            parameters: zodToJsonSchema(
              draftUsualFoodProviderOutputSchema,
            ) as Record<string, unknown>,
          },
        },
      ],
    });
    const call = decision.toolCalls.find(
      (toolCall) => toolCall.function.name === "return_usual_food_draft",
    );
    if (!call) throw new UsualFoodDraftProviderUnavailableError();
    return draftUsualFoodProviderOutputSchema.parse(
      JSON.parse(call.function.arguments),
    );
  }
}

function usualFoodDraftSystemPrompt(locale: string): string {
  return [
    "You extract review-only usual ingredient drafts for BetterCalories.",
    `User locale: ${locale}.`,
    "Use the return_usual_food_draft tool exactly once.",
    "Extract only values explicitly stated by the user. Do not estimate, infer, calculate, translate with shortcuts, or fill nutrition from general food knowledge.",
    "Only include a required nutrition field in explicitFields when the user explicitly provided that exact value.",
    "If serving size, calories, protein, carbohydrates, or fat are missing, omit those values and do not mark them explicit.",
    "Optional label nutrients such as salt, sodium, fiber, sugar, or saturated fat may be included only when explicitly stated.",
    "Never save a food and never claim that missing required fields are ready to save.",
  ].join(" ");
}
