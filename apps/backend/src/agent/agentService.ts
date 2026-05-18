import {
  type ActionContext,
  type DailySummary,
  type Meal,
  type MealItem,
  type NutritionSnapshot,
  type MealProposal,
  type MealTemplate,
  actionDefinitions,
} from "@cal-tracker/contracts";
import {
  ActionExecutor,
  type ExecuteActionResult,
} from "../actions/executor.js";
import type {
  AgentMessage,
  AgentToolCall,
  AgentToolDecision,
  ChatAgentProvider,
} from "./chatAgentProvider.js";
import { buildSystemMessage } from "./agentMessages.js";
import { buildToolSchemas } from "./toolSchemas.js";
import { filterToolsByPolicy } from "./agentPolicy.js";
import {
  extractReasoningTokens,
  extractTokenUsage,
  summarizeError,
  type LocalRunLogger,
} from "../observability/localRunLogger.js";

export type AgentRunResult =
  | {
      kind: "proposal";
      proposal: MealProposal;
      message: string;
      options?: unknown[];
    }
  | { kind: "meal_committed"; meal: Meal; message: string; options?: unknown[] }
  | {
      kind: "meal_corrected";
      meal?: Meal;
      proposal?: MealProposal;
      message: string;
    }
  | { kind: "summary"; summary: DailySummary; message: string }
  | { kind: "remaining_targets"; remaining: NutritionSnapshot; message: string }
  | { kind: "history"; meals: Meal[]; message: string }
  | {
      kind: "food_memory";
      matches: unknown[];
      message: string;
      options?: unknown[];
    }
  | {
      kind: "nutrition_search";
      items: MealItem[];
      message: string;
      options?: unknown[];
    }
  | { kind: "templates"; templates: MealTemplate[]; message: string }
  | { kind: "template_saved"; template: MealTemplate; message: string }
  | { kind: "template_deleted"; deleted: boolean; message: string }
  | {
      kind: "confirmation_required";
      actionId: string;
      input: unknown;
      message: string;
    }
  | { kind: "meal_deleted"; message: string }
  | {
      kind: "clarification_required";
      message: string;
      options?: unknown[];
      resolvedItems?: MealItem[];
    };

export class AgentService {
  constructor(
    private readonly agentProvider: ChatAgentProvider,
    private readonly actionExecutor: ActionExecutor,
    private readonly model: string,
    private readonly runLogger?: LocalRunLogger,
  ) {}

  async run(
    text: string,
    context: ActionContext,
    activeProposalId?: string,
  ): Promise<AgentRunResult> {
    const runStarted = Date.now();
    const activeProposal = activeProposalId
      ? await this.actionExecutor.getProposalForAgentContext(
          context.actorUserId,
          activeProposalId,
        )
      : undefined;
    const messages: AgentMessage[] = [
      buildSystemMessage(context, activeProposal),
      { role: "user", content: text },
    ];

    const allowedActions = filterToolsByPolicy(actionDefinitions, context);
    const toolSchemas = buildToolSchemas();
    const tools = allowedActions.map((action) => ({
      type: "function" as const,
      function: {
        name: action.id,
        description: `${action.title}. ${action.description}`,
        parameters:
          toolSchemas.find((t) => t.function.name === action.id)?.function
            .parameters ?? {},
      },
    }));
    const baseLog = {
      type: "agent.run",
      traceId: context.traceId,
      userId: context.actorUserId,
      source: context.source,
      locale: context.locale,
      timezone: context.timezone,
      model: this.model,
      inputText: text,
      activeProposalId,
      activeProposal,
      systemPrompt: messages[0]!.content,
      messages,
      availableTools: allowedActions.map((action) => action.id),
    };

    let decision: AgentToolDecision;
    let llmMs: number | undefined;
    try {
      const llmStarted = Date.now();
      decision = await this.agentProvider.runWithTools({
        messages,
        tools,
        model: this.model,
        traceId: context.traceId,
      });
      llmMs = Date.now() - llmStarted;
    } catch (error) {
      const fallbackToolCall = fallbackToolCallForText(text);
      if (fallbackToolCall) {
        return this.executeFallbackTool({
          text,
          context,
          runStarted,
          baseLog,
          fallbackToolCall,
          decisionSource: "provider_error_fallback",
          providerError: summarizeError(error),
        });
      }
      const mapped = {
        kind: "clarification_required",
        message:
          "The agent provider is unavailable. Please rephrase or try again.",
      } satisfies AgentRunResult;
      await this.logRun({
        ...baseLog,
        decisionSource: "provider_error_no_fallback",
        providerError: summarizeError(error),
        resultKind: mapped.kind,
        timingsMs: { total: Date.now() - runStarted },
      });
      return mapped;
    }

    if (decision.toolCalls.length === 0) {
      const fallbackToolCall = fallbackToolCallForText(text);
      if (fallbackToolCall) {
        return this.executeFallbackTool({
          text,
          context,
          runStarted,
          baseLog,
          fallbackToolCall,
          decisionSource: "empty_tool_call_fallback",
          decision,
          llmMs,
        });
      }
      const mapped = {
        kind: "clarification_required",
        message: "I'm not sure what you'd like to do. Could you rephrase?",
      } satisfies AgentRunResult;
      await this.logRun({
        ...baseLog,
        decisionSource: "empty_tool_call",
        usage: extractTokenUsage(decision.rawResponse),
        reasoningTokens: extractReasoningTokens(decision.rawResponse),
        providerTimingsMs: decision.timingsMs,
        providerRouting: decision.providerRouting,
        modelInteraction: decision.interaction,
        resultKind: mapped.kind,
        timingsMs: {
          llm: decision.timingsMs?.totalMs ?? llmMs,
          total: Date.now() - runStarted,
        },
      });
      return mapped;
    }

    const toolCall = decision.toolCalls[0]!;
    let actionId = toolCall.function.name;

    if (!allowedActions.some((a) => a.id === actionId)) {
      const mapped = {
        kind: "clarification_required",
        message: `I'm not able to perform that action (${actionId}).`,
      } satisfies AgentRunResult;
      await this.logRun({
        ...baseLog,
        decisionSource: "model",
        selectedTool: actionId,
        selectedArgumentsRaw: toolCall.function.arguments,
        usage: extractTokenUsage(decision.rawResponse),
        reasoningTokens: extractReasoningTokens(decision.rawResponse),
        providerTimingsMs: decision.timingsMs,
        providerRouting: decision.providerRouting,
        modelInteraction: decision.interaction,
        resultKind: mapped.kind,
        timingsMs: {
          llm: decision.timingsMs?.totalMs ?? llmMs,
          total: Date.now() - runStarted,
        },
      });
      return mapped;
    }

    let parsedInput: unknown;
    try {
      parsedInput = JSON.parse(toolCall.function.arguments);
    } catch {
      const mapped = {
        kind: "clarification_required",
        message:
          "I didn't understand the parameters for that action. Could you rephrase?",
      } satisfies AgentRunResult;
      await this.logRun({
        ...baseLog,
        decisionSource: "model",
        selectedTool: actionId,
        selectedArgumentsRaw: toolCall.function.arguments,
        usage: extractTokenUsage(decision.rawResponse),
        reasoningTokens: extractReasoningTokens(decision.rawResponse),
        providerTimingsMs: decision.timingsMs,
        providerRouting: decision.providerRouting,
        modelInteraction: decision.interaction,
        resultKind: mapped.kind,
        timingsMs: {
          llm: decision.timingsMs?.totalMs ?? llmMs,
          total: Date.now() - runStarted,
        },
      });
      return mapped;
    }

    const originalActionId = actionId;
    if (
      isMealLoggingIntent(text) &&
      !activeProposal &&
      actionId !== "propose_meal_log"
    ) {
      actionId = "propose_meal_log";
      parsedInput = { text };
    }
    if (
      activeProposal &&
      actionId === "revise_meal_proposal" &&
      typeof parsedInput === "object" &&
      parsedInput !== null &&
      !Array.isArray(parsedInput) &&
      !("proposalId" in parsedInput)
    ) {
      parsedInput = { ...parsedInput, proposalId: activeProposal.id };
    }

    const actionStarted = Date.now();
    try {
      const result = await this.actionExecutor.execute(actionId, parsedInput, {
        ...context,
        source: "internal_agent",
      });
      const mapped = this.mapResult(actionId, result, text);
      await this.logRun({
        ...baseLog,
        decisionSource: "model",
        selectedTool: originalActionId,
        executedTool: actionId,
        forcedToolOverride:
          originalActionId !== actionId
            ? { from: originalActionId, to: actionId }
            : undefined,
        selectedArguments: parsedInput,
        usage: extractTokenUsage(decision.rawResponse),
        reasoningTokens: extractReasoningTokens(decision.rawResponse),
        providerTimingsMs: decision.timingsMs,
        providerRouting: decision.providerRouting,
        modelInteraction: decision.interaction,
        actionInstrumentation: result.instrumentation,
        actionCallId: result.actionCallId,
        resultKind: mapped.kind,
        timingsMs: {
          llm: decision.timingsMs?.totalMs ?? llmMs,
          action: Date.now() - actionStarted,
          total: Date.now() - runStarted,
        },
      });
      return mapped;
    } catch (error) {
      await this.logRun({
        ...baseLog,
        decisionSource: "model",
        selectedTool: originalActionId,
        executedTool: actionId,
        selectedArguments: parsedInput,
        usage: extractTokenUsage(decision.rawResponse),
        reasoningTokens: extractReasoningTokens(decision.rawResponse),
        providerTimingsMs: decision.timingsMs,
        providerRouting: decision.providerRouting,
        modelInteraction: decision.interaction,
        error: summarizeError(error),
        timingsMs: {
          llm: decision.timingsMs?.totalMs ?? llmMs,
          action: Date.now() - actionStarted,
          total: Date.now() - runStarted,
        },
      });
      throw error;
    }
  }

  private async executeFallbackTool(input: {
    text: string;
    context: ActionContext;
    runStarted: number;
    baseLog: Record<string, unknown>;
    fallbackToolCall: AgentToolCall;
    decisionSource: string;
    decision?: AgentToolDecision;
    llmMs?: number;
    providerError?: Record<string, unknown>;
  }): Promise<AgentRunResult> {
    const parsedArguments = JSON.parse(input.fallbackToolCall.function.arguments);
    const actionStarted = Date.now();
    const result = await this.actionExecutor.execute(
      input.fallbackToolCall.function.name,
      parsedArguments,
      {
        ...input.context,
        source: "internal_agent",
      },
    );
    const mapped = this.mapResult(
      input.fallbackToolCall.function.name,
      result,
      input.text,
    );
    await this.logRun({
      ...input.baseLog,
      decisionSource: input.decisionSource,
      selectedTool: input.fallbackToolCall.function.name,
      selectedArguments: parsedArguments,
      providerError: input.providerError,
      usage: input.decision
        ? extractTokenUsage(input.decision.rawResponse)
        : undefined,
      reasoningTokens: input.decision
        ? extractReasoningTokens(input.decision.rawResponse)
        : undefined,
      providerTimingsMs: input.decision?.timingsMs,
      providerRouting: input.decision?.providerRouting,
      modelInteraction: input.decision?.interaction,
      actionInstrumentation: result.instrumentation,
      actionCallId: result.actionCallId,
      resultKind: mapped.kind,
      timingsMs: {
        llm: input.decision?.timingsMs?.totalMs ?? input.llmMs,
        action: Date.now() - actionStarted,
        total: Date.now() - input.runStarted,
      },
    });
    return mapped;
  }

  private async logRun(event: Record<string, unknown>): Promise<void> {
    try {
      await this.runLogger?.log(event);
    } catch (error) {
      console.warn("agent.run_log.failed", summarizeError(error));
    }
  }

  private mapResult(
    actionId: string,
    result: ExecuteActionResult,
    originalText: string,
  ): AgentRunResult {
    const output = result.output as Record<string, unknown>;

    switch (actionId) {
      case "query_food_memory": {
        const matches = (output.matches as unknown[]) ?? [];
        return {
          kind: "food_memory",
          matches,
          options: matches,
          message:
            matches.length > 0
              ? "I found matching food memories."
              : "I couldn't find matching food memories.",
        };
      }
      case "search_nutrition_database": {
        const items = (output.items as MealItem[]) ?? [];
        const options =
          (output.candidateGroups as unknown[] | undefined) ??
          (output.candidates as unknown[] | undefined) ??
          [];
        return {
          kind: "nutrition_search",
          items,
          options,
          message:
            items.length > 0
              ? "I found matching nutrition items."
              : "I couldn't find matching nutrition items.",
        };
      }
      case "propose_meal_log": {
        if (output.clarificationRequired) {
          const options = output.options as unknown[] | undefined;
          const resolvedItems = output.resolvedItems as MealItem[] | undefined;
          return {
            kind: "clarification_required",
            options,
            resolvedItems,
            message:
              typeof output.message === "string"
                ? output.message
                : "I could not confidently match every ingredient.",
          };
        }
        const proposal = output.proposal as MealProposal;
        const meal = output.autoCommittedMeal as Meal | undefined;
        const options =
          (output.options as unknown[] | undefined) ??
          (output.candidateGroups as unknown[] | undefined) ??
          [];
        if (meal) {
          return {
            kind: "meal_committed",
            meal,
            options,
            message: "Meal logged from trusted template.",
          };
        }
        return {
          kind: "proposal",
          proposal,
          options,
          message: "Meal proposal created.",
        };
      }
      case "create_meal_proposal_from_items":
        return {
          kind: "proposal",
          proposal: output.proposal as MealProposal,
          message: "Meal proposal created.",
        };
      case "revise_meal_proposal": {
        if (output.clarificationRequired) {
          return {
            kind: "clarification_required",
            options: output.options as unknown[] | undefined,
            resolvedItems: output.resolvedItems as MealItem[] | undefined,
            message:
              typeof output.message === "string"
                ? output.message
                : "I need a food match before updating the meal proposal.",
          };
        }
        return {
          kind: "proposal",
          proposal: output.proposal as MealProposal,
          message:
            typeof output.message === "string"
              ? output.message
              : "Meal proposal updated.",
        };
      }
      case "commit_meal":
        return {
          kind: "meal_committed",
          meal: output.meal as Meal,
          message: "Meal logged.",
        };
      case "correct_meal": {
        const meal = output.meal as Meal | undefined;
        const proposal = output.proposal as MealProposal | undefined;
        if (meal)
          return { kind: "meal_corrected", meal, message: "Meal corrected." };
        return {
          kind: "meal_corrected",
          proposal,
          message: "Meal proposal corrected.",
        };
      }
      case "get_daily_summary":
        return {
          kind: "summary",
          summary: output.summary as DailySummary,
          message: "Here is your daily summary.",
        };
      case "get_remaining_targets":
        return {
          kind: "remaining_targets",
          remaining: output.remaining as NutritionSnapshot,
          message: "Here are your remaining targets.",
        };
      case "get_meal_history":
        return {
          kind: "history",
          meals: output.meals as Meal[],
          message: "Here is your meal history.",
        };
      case "get_usual_meals":
        return {
          kind: "templates",
          templates: output.templates as MealTemplate[],
          message: "Here are your usual meals.",
        };
      case "create_meal_template":
        return {
          kind: "template_saved",
          template: output.template as MealTemplate,
          message: "Usual meal created.",
        };
      case "update_meal_template":
        return {
          kind: "template_saved",
          template: output.template as MealTemplate,
          message: "Usual meal updated.",
        };
      case "delete_meal_template":
        return {
          kind: "template_deleted",
          deleted: Boolean(output.deleted),
          message: output.deleted
            ? "Usual meal deleted."
            : "Usual meal was not found.",
        };
      case "delete_meal": {
        const confirmationRequired = (
          output as { confirmationRequired?: boolean }
        ).confirmationRequired;
        if (confirmationRequired) {
          return {
            kind: "confirmation_required",
            actionId: "delete_meal",
            input: { ...output, originalText },
            message: "Please confirm deletion.",
          };
        }
        return { kind: "meal_deleted", message: "Meal deleted." };
      }
      default:
        return {
          kind: "clarification_required",
          message:
            "Action completed but I don't know how to display the result.",
        };
    }
  }
}

function isMealLoggingIntent(text: string): boolean {
  const normalized = normalizeIntentText(text);

  if (/^(how|cuanto|cuanta|cuantas|cuantos|que|what)\b/.test(normalized))
    return false;
  if (
    /\b(delete|remove|borrar|eliminar|corrige|correct|corregir)\b/.test(
      normalized,
    )
  )
    return false;
  return (
    /\b(log|add|ate|had|consumed|record|registrar|registro|anade|anadir|agrega|agregar|apunta|apuntar|pon|ponme|poner|mete|meteme|put|comi|comido|tome|consumi|desayuno|almuerzo|comida|cena|merienda|snack)\b/.test(
      normalized,
    ) || hasExplicitFoodQuantity(normalized)
  );
}

function hasExplicitFoodQuantity(normalized: string): boolean {
  return /\b\d+(?:[.,]\d+)?\s*(?:g|gr|gramo|gramos|gram|grams|kg|kilo|kilos|ml|mililitro|mililitros|l|litro|litros|oz|ounce|ounces|cup|cups|taza|tazas)\b(?:\s+(?:de|of))?\s+[a-z]/.test(
    normalized,
  );
}

function fallbackToolCallForText(text: string): AgentToolCall | null {
  const normalized = normalizeIntentText(text);
  if (isMealLoggingIntent(text)) return toolCall("propose_meal_log", { text });
  if (
    /\b(remaining|left|quedan|restan|calorias restantes|calories left)\b/.test(
      normalized,
    )
  ) {
    return toolCall("get_remaining_targets", {});
  }
  if (/\b(summary|resumen|today|hoy)\b/.test(normalized))
    return toolCall("get_daily_summary", {});
  if (/\b(history|historial|ultimas comidas|recent meals)\b/.test(normalized))
    return toolCall("get_meal_history", { limit: 10 });
  if (
    /\b(usual meals|templates|plantillas|comidas habituales|habituales)\b/.test(
      normalized,
    )
  )
    return toolCall("get_usual_meals", {});

  const nutritionSearch =
    /\b(?:search|buscar|lookup|consulta|consultar)\b.*\b(?:nutrition|nutricion|food|alimento|database|base)\b(?:\s+(?:for|de|para))?\s*(.*)$/.exec(
      normalized,
    );
  if (nutritionSearch?.[1])
    return toolCall("search_nutrition_database", {
      query: nutritionSearch[1].trim(),
    });

  return null;
}

function toolCall(name: string, input: unknown): AgentToolCall {
  return {
    id: `fallback_${name}`,
    type: "function",
    function: {
      name,
      arguments: JSON.stringify(input),
    },
  };
}

function normalizeIntentText(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
