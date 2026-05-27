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
  AgentToolDecision,
  ChatAgentProvider,
} from "./chatAgentProvider.js";
import { buildSystemMessage } from "./agentMessages.js";
import { buildToolSchemas } from "./toolSchemas.js";
import { filterToolsByPolicy } from "./agentPolicy.js";
import {
  extractReasoningTokens,
  extractGenerationId,
  extractTokenUsage,
  summarizeError,
  type LocalRunLogger,
} from "../observability/localRunLogger.js";
import { withSpan, withSyncSpan } from "../observability/profiler.js";

export class AgentProviderUnavailableError extends Error {
  readonly code = "agent_provider_unavailable";

  constructor(cause?: unknown) {
    super("agent_provider_unavailable");
    this.name = "AgentProviderUnavailableError";
    this.cause = cause;
  }
}

export type AgentRunResult =
  | {
      kind: "proposal";
      proposal: MealProposal;
      message: string;
      options?: unknown[];
      candidateGroups?: unknown[];
    }
  | {
      kind: "meal_committed";
      meal: Meal;
      message: string;
      options?: unknown[];
      candidateGroups?: unknown[];
    }
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
      proposal?: MealProposal;
      options?: unknown[];
      candidateGroups?: unknown[];
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
    options: {
      activeProposal?: MealProposal | null;
      inputMode?: "text" | "voice";
    } = {},
  ): Promise<AgentRunResult> {
    const runStarted = Date.now();
    const activeProposal = options.activeProposal !== undefined
      ? options.activeProposal ?? undefined
      : activeProposalId
        ? await this.actionExecutor.getProposalForAgentContext(
            context.actorUserId,
            activeProposalId,
          )
        : undefined;
    const messages: AgentMessage[] = [
      buildSystemMessage(context, activeProposal),
      { role: "user", content: text },
    ];

    const allowedActions = withSyncSpan(
      "AgentService.filterToolsByPolicy",
      { scopeCount: context.scopes.length },
      () => filterToolsByPolicy(actionDefinitions, context),
    );
    const toolSchemas = withSyncSpan(
      "AgentService.buildToolSchemas",
      undefined,
      () => buildToolSchemas(),
    );
    const tools = withSyncSpan(
      "AgentService.materializeTools",
      { allowedActionCount: allowedActions.length },
      () =>
        prioritizeDefaultTool(allowedActions).map((action) => ({
          type: "function" as const,
          function: {
            name: action.id,
            description:
              toolSchemas.find((t) => t.function.name === action.id)?.function
                .description ?? `${action.title}. ${action.description}`,
            parameters:
              toolSchemas.find((t) => t.function.name === action.id)?.function
                .parameters ?? {},
          },
        })),
    );
    const modelInputStats = agentModelInputStats(messages, tools);
    const baseLog = {
      type: "agent.run",
      traceId: context.traceId,
      userId: context.actorUserId,
      source: context.source,
      locale: context.locale,
      timezone: context.timezone,
      model: this.model,
      inputText: text,
      inputMode: options.inputMode ?? "text",
      activeProposalId,
      activeProposal,
      systemPrompt: messages[0]!.content,
      messages,
      availableTools: allowedActions.map((action) => action.id),
      modelInputStats,
    };

    let decision: AgentToolDecision;
    let llmMs: number | undefined;
    try {
      const llmStarted = Date.now();
      decision = await withSpan(
        "AgentService.llmToolDecision",
        modelInputStats,
        () => this.agentProvider.runWithTools({
          messages,
          tools,
          model: this.model,
          traceId: context.traceId,
        }),
      );
      llmMs = Date.now() - llmStarted;
    } catch (error) {
      await this.logRun({
        ...baseLog,
        decisionSource: "provider_error",
        providerError: summarizeError(error),
        timingsMs: { total: Date.now() - runStarted },
      });
      throw new AgentProviderUnavailableError(error);
    }

    if (decision.toolCalls.length === 0) {
      const mapped = {
        kind: "clarification_required",
        proposal: activeProposal,
        message: activeProposal
          ? "I could not safely apply that correction. The meal was not changed. Please repeat the correction."
          : "I'm not sure what you'd like to do. Could you rephrase?",
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
      parsedInput = withSyncSpan(
        "AgentService.parseToolArguments",
        {
          actionId,
          argumentsChars: toolCall.function.arguments.length,
        },
        () => JSON.parse(toolCall.function.arguments),
      );
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
      const result = await withSpan(
        "AgentService.executeAction",
        { actionId },
        () => this.actionExecutor.execute(actionId, parsedInput, {
          ...context,
          source: "internal_agent",
        }),
      );
      const mapped = withSyncSpan(
        "AgentService.mapResult",
        { actionId },
        () => this.mapResult(actionId, result, text),
      );
      await this.logRun({
        ...baseLog,
        decisionSource: "model",
        selectedTool: originalActionId,
        executedTool: actionId,
        selectedArguments: parsedInput,
        usage: extractTokenUsage(decision.rawResponse),
        reasoningTokens: extractReasoningTokens(decision.rawResponse),
        generationId: extractGenerationId(decision.rawResponse),
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
            proposal: output.proposal as MealProposal | undefined,
            options,
            candidateGroups: output.candidateGroups as unknown[] | undefined,
            resolvedItems,
            message:
              typeof output.message === "string"
                ? output.message
                : "I could not confidently match every ingredient.",
          };
        }
        const proposal = output.proposal as MealProposal;
        const meal = output.autoCommittedMeal as Meal | undefined;
        const candidateGroups =
          (output.candidateGroups as unknown[] | undefined) ??
          (output.options as unknown[] | undefined) ??
          [];
        if (meal) {
          return {
            kind: "meal_committed",
            meal,
            candidateGroups,
            message: "Meal logged from trusted template.",
          };
        }
        return {
          kind: "proposal",
          proposal,
          candidateGroups,
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
            proposal: output.proposal as MealProposal | undefined,
            options: output.options as unknown[] | undefined,
            candidateGroups: output.candidateGroups as unknown[] | undefined,
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
          candidateGroups: output.candidateGroups as unknown[] | undefined,
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

function agentModelInputStats(
  messages: AgentMessage[],
  tools: Array<{ type: "function"; function: { name: string; description: string; parameters: Record<string, unknown> } }>,
) {
  const toolSummaries = tools.map((tool) => ({
    name: tool.function.name,
    chars: JSON.stringify(tool).length,
  }));
  const toolsJsonChars = JSON.stringify(tools).length;
  const messagesJsonChars = JSON.stringify(messages).length;
  const systemPromptChars = messages[0]?.content.length ?? 0;
  return {
    toolCount: tools.length,
    toolsJsonChars,
    toolsJsonApproxTokens: approxTokens(toolsJsonChars),
    messagesJsonChars,
    messagesJsonApproxTokens: approxTokens(messagesJsonChars),
    systemPromptChars,
    requestPayloadChars: toolsJsonChars + messagesJsonChars,
    topToolsByChars: toolSummaries
      .sort((a, b) => b.chars - a.chars)
      .slice(0, 5),
  };
}

function approxTokens(chars: number): number {
  return Math.ceil(chars / 4);
}

function prioritizeDefaultTool<T extends { id: string }>(actions: T[]): T[] {
  return [...actions].sort((a, b) => {
    if (a.id === "propose_meal_log") return -1;
    if (b.id === "propose_meal_log") return 1;
    return 0;
  });
}
