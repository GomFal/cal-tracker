import { actionDefinitions } from "@cal-tracker/contracts";
import { zodToJsonSchema } from "zod-to-json-schema";
import type { AgentToolDefinition } from "./chatAgentProvider.js";

let cachedToolSchemas: AgentToolDefinition[] | undefined;

export function buildToolSchemas(): AgentToolDefinition[] {
  cachedToolSchemas ??= actionDefinitions.map((action) => ({
    type: "function",
    function: {
      name: action.id,
      description: toolDescription(action),
      parameters: zodToJsonSchema(action.inputSchema) as Record<string, unknown>,
    },
  }));
  return cachedToolSchemas;
}

function toolDescription(action: (typeof actionDefinitions)[number]): string {
  switch (action.id) {
    case "propose_meal_log":
      return [
        `${action.title}.`,
        "Primary/default tool for turning typed or transcribed food text into a meal proposal.",
        "Use for one or many foods, quantities, and natural-language add/record meal requests in any language.",
        "In same-list phrases like '300 gramos de pollo y 200 de pan', treat the second quantity as 200 grams because grams was the last explicit unit.",
        "Do not use nutrition lookup tools first for these requests.",
        action.description,
      ].join(" ");
    case "search_nutrition_database":
      return [
        `${action.title}.`,
        "Use only for explicit nutrition lookup/search requests where the user is not asking to add food to their log.",
        action.description,
      ].join(" ");
    case "query_food_memory":
      return [
        `${action.title}.`,
        "Use only to retrieve stored usual-meal aliases or memories, not as the final action for logging food.",
        action.description,
      ].join(" ");
    case "draft_usual_food":
      return [
        `${action.title}.`,
        "Use when the user explicitly asks to create or fill a usual ingredient draft from provided label text.",
        "Return only values explicitly present in the user's text; do not guess nutrition from food names.",
        "This action never saves a food.",
        action.description,
      ].join(" ");
    case "draft_usual_meal":
      return [
        `${action.title}.`,
        "Use when the user explicitly asks to create a usual meal, saved meal, or meal template from typed or transcribed text.",
        "Return a review-only draft by extracting structured ingredient mentions, title, and aliases from the user's text.",
        "Do not guess ingredients from meal names, and do not save a template.",
        action.description,
      ].join(" ");
    default:
      return `${action.title}. ${action.description}`;
  }
}
