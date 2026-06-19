import { randomUUID } from "node:crypto";
import {
  actionDefinitions,
  type ActionContext,
  type DailySummary,
  type DraftUsualFoodOutput,
  type DraftUsualMealOutput,
  type Meal,
  type MealItem,
  type MealProposal,
  type MealTemplate,
  type NutritionSnapshot,
  type UsualFood,
} from "@cal-tracker/contracts";
import {
  ActionExecutor,
  type ExecuteActionResult,
} from "../actions/executor.js";
import type {
  AgentConversationMessageRecord,
  AgentConversationRecord,
  AppRepository,
} from "../repository/types.js";
import {
  extractGenerationId,
  extractReasoningTokens,
  extractTokenUsage,
  summarizeError,
  type LocalRunLogger,
} from "../observability/localRunLogger.js";
import {
  DEFAULT_TELEMETRY_SERVICE,
  type TelemetryService,
} from "../telemetry/telemetryService.js";
import { resolveLlmCost, type LlmCostResult } from "../telemetry/llmCost.js";
import type {
  AgentMessage,
  AgentToolCall,
  AgentToolDecision,
  ChatAgentProvider,
} from "./chatAgentProvider.js";
import { buildChatSystemMessage } from "./agentMessages.js";
import { buildToolSchemas } from "./toolSchemas.js";
import { filterToolsByPolicy } from "./agentPolicy.js";

const MAX_CHAT_ITERATIONS = 6;
const MAX_TOOL_CALLS_PER_TURN = 8;
const STORED_TOOL_RESULT_MAX_CHARS = 12000;
const MAX_CONVERSATION_TITLE_CHARS = 64;
const CHAT_OPTIONS_TOOL_NAME = "show_chat_options";

type ChatTurnCorrelation = {
  traceId: string;
  turnId: string;
  inputMode: "text" | "voice";
  source: string;
  conversationId: string;
  activeProposalId?: string;
};

type AgentChatSuggestion = {
  label: string;
  value: string;
};

export type AgentChatResultKind =
  | "proposal"
  | "meal_committed"
  | "meal_corrected"
  | "summary"
  | "remaining_targets"
  | "history"
  | "food_memory"
  | "nutrition_search"
  | "usual_foods"
  | "templates"
  | "template_saved"
  | "template_deleted"
  | "usual_food_draft"
  | "usual_meal_draft"
  | "confirmation_required"
  | "meal_deleted"
  | "clarification_required";

export type AgentChatMappedResult =
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
  | { kind: "usual_foods"; usualFoods: UsualFood[]; message: string }
  | { kind: "templates"; templates: MealTemplate[]; message: string }
  | { kind: "template_saved"; template: MealTemplate; message: string }
  | { kind: "template_deleted"; deleted: boolean; message: string }
  | {
      kind: "usual_food_draft";
      usualFoodDraft: DraftUsualFoodOutput;
      message: string;
    }
  | {
      kind: "usual_meal_draft";
      usualMealDraft: DraftUsualMealOutput;
      message: string;
      options?: unknown[];
      candidateGroups?: unknown[];
    }
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

export type AgentToolFeedback = {
  id: string;
  actionId: string;
  label: string;
  summary: string;
  input: unknown;
};

export type AgentWidgetPayload = {
  kind: AgentChatResultKind;
  title: string;
  result: AgentChatMappedResult;
};

export type AgentChatEvent =
  | { type: "conversation_started"; conversationId: string; turnId: string }
  | { type: "thinking"; conversationId?: string; message: string }
  | {
      type: "transcription_completed";
      conversationId?: string;
      transcript: string;
    }
  | { type: "assistant_delta"; conversationId?: string; delta: string }
  | {
      type: "assistant_suggestions";
      conversationId?: string;
      suggestions: AgentChatSuggestion[];
    }
  | {
      type: "tool_call_started";
      conversationId: string;
      toolCall: AgentToolFeedback;
    }
  | {
      type: "tool_call_completed";
      conversationId: string;
      toolCall: AgentToolFeedback;
      result: AgentChatMappedResult;
      widget?: AgentWidgetPayload;
    }
  | {
      type: "tool_call_failed";
      conversationId: string;
      toolCall: AgentToolFeedback;
      error: string;
    }
  | { type: "done"; conversationId: string }
  | { type: "error"; conversationId?: string; error: string };

export class AgentChatService {
  constructor(
    private readonly agentProvider: ChatAgentProvider,
    private readonly actionExecutor: ActionExecutor,
    private readonly repository: AppRepository,
    private readonly model: string,
    private readonly runLogger?: LocalRunLogger,
    private readonly telemetryService: TelemetryService = DEFAULT_TELEMETRY_SERVICE,
  ) {}

  async *chat(input: {
    text: string;
    context: ActionContext;
    conversationId?: string;
    activeProposalId?: string;
    activeProposal?: MealProposal | null;
    inputMode?: "text" | "voice";
  }): AsyncGenerator<AgentChatEvent> {
    const runStarted = Date.now();
    const conversation = await this.resolveConversation(
      input.context.actorUserId,
      input.conversationId,
      input.text,
    );
    const inputMode = input.inputMode ?? "text";
    const correlation: ChatTurnCorrelation = {
      traceId: input.context.traceId,
      turnId: randomUUID(),
      inputMode,
      source: input.context.source,
      conversationId: conversation.id,
      activeProposalId: input.activeProposalId,
    };
    yield {
      type: "conversation_started",
      conversationId: conversation.id,
      turnId: correlation.turnId,
    };

    const text = input.text.trim();
    if (!text) {
      yield {
        type: "assistant_delta",
        conversationId: conversation.id,
        delta: "I could not understand enough input. Please try again.",
      };
      yield { type: "done", conversationId: conversation.id };
      return;
    }

    await this.repository.addAgentConversationMessage(
      input.context.actorUserId,
      conversation.id,
      {
        role: "user",
        content: text,
        ...messageCorrelation(correlation, { stage: "user_input" }),
      },
    );

    let currentActiveProposal = input.activeProposalId
      ? input.activeProposal !== undefined
        ? (input.activeProposal ?? undefined)
        : await this.actionExecutor.getProposalForAgentContext(
            input.context.actorUserId,
            input.activeProposalId,
          )
      : undefined;

    const allowedActions = filterToolsByPolicy(
      actionDefinitions,
      input.context,
    );
    const schemas = buildToolSchemas();
    const tools = [
      ...prioritizeDefaultTool(allowedActions).map((action) => ({
        type: "function" as const,
        function: {
          name: action.id,
          description:
            schemas.find((tool) => tool.function.name === action.id)?.function
              .description ?? `${action.title}. ${action.description}`,
          parameters:
            schemas.find((tool) => tool.function.name === action.id)?.function
              .parameters ?? {},
        },
      })),
      chatOptionsToolDefinition(),
    ];

    const messages = await this.messagesForModel(
      input.context.actorUserId,
      conversation.id,
      input.context,
      currentActiveProposal,
    );
    const executedSignatures = new Set<string>();
    let iteration = 0;
    let toolCallCount = 0;
    let accumulatedPromptTokens = 0;
    let accumulatedCompletionTokens = 0;
    let accumulatedTotalTokens = 0;
    let accumulatedReasoningTokens = 0;
    let accumulatedProviderCost = 0;
    let accumulatedEstimatedCost = 0;
    let costCurrency: string | undefined;
    let costSource: string | undefined;
    let lastPricingSnapshot: Record<string, unknown> = {};
    let latestAssistantText = "";
    let latestResultKind: string | undefined;
    let latestStopReason: string | undefined;
    let firstByteMs: number | undefined;
    let firstToolCallMs: number | undefined;
    let largestStreamGapMs: number | undefined;
    let accumulatedLlmMs = 0;
    let accumulatedActionMs = 0;

    while (iteration < MAX_CHAT_ITERATIONS) {
      iteration++;
      yield {
        type: "thinking",
        conversationId: conversation.id,
        message: iteration === 1 ? "Thinking..." : "Checking the result...",
      };

      let decision: AgentToolDecision;
      try {
        decision = await this.agentProvider.runWithTools({
          messages,
          tools,
          model: this.model,
          traceId: input.context.traceId,
        });
      } catch (error) {
        await this.logRun({
          type: "agent.chat",
          traceId: input.context.traceId,
          userId: input.context.actorUserId,
          conversationId: conversation.id,
          inputText: text,
          inputMode,
          error: summarizeError(error),
          timingsMs: { total: Date.now() - runStarted },
        });
        await this.recordTurnTelemetry({
          correlation,
          userId: input.context.actorUserId,
          text,
          model: this.model,
          iterationCount: iteration,
          toolCallCount,
          status: "failure",
          errorCode: "provider_error",
          errorMessage: error instanceof Error ? error.message : String(error),
          totalMs: Date.now() - runStarted,
        });
        yield {
          type: "error",
          conversationId: conversation.id,
          error: "The assistant is temporarily unavailable.",
        };
        return;
      }

      const assistantText =
        decision.interaction?.assistantContent?.trim() ?? "";
      latestAssistantText = assistantText || latestAssistantText;
      const tokenMetrics = extractLlmTokenMetrics(decision.rawResponse);
      accumulatedPromptTokens += tokenMetrics.promptTokens ?? 0;
      accumulatedCompletionTokens += tokenMetrics.completionTokens ?? 0;
      accumulatedTotalTokens += tokenMetrics.totalTokens ?? 0;
      accumulatedReasoningTokens += tokenMetrics.reasoningTokens ?? 0;
      firstByteMs ??= decision.timingsMs?.firstByteMs;
      firstToolCallMs ??= decision.timingsMs?.firstToolCallMs;
      largestStreamGapMs = maxOptional(
        largestStreamGapMs,
        decision.timingsMs?.largestStreamGapMs,
      );
      accumulatedLlmMs += decision.timingsMs?.totalMs ?? 0;
      const cost = resolveLlmCost({
        rawResponse: decision.rawResponse,
        model: this.model,
        metrics: tokenMetrics,
      });
      accumulatedProviderCost += cost.providerCostAmount ?? 0;
      accumulatedEstimatedCost += cost.estimatedCostAmount ?? 0;
      costCurrency = cost.costCurrency ?? costCurrency;
      costSource = mergeCostSource(costSource, cost.costSource);
      lastPricingSnapshot = cost.pricingSnapshot;
      await this.recordProviderTelemetry({
        correlation,
        userId: input.context.actorUserId,
        decision,
        iteration,
        cost,
        tokenMetrics,
      });
      if (decision.toolCalls.length === 0) {
        const finalText = assistantText || "Done.";
        latestAssistantText = finalText;
        latestResultKind = "assistant_message";
        latestStopReason = "assistant_message";
        await this.repository.addAgentConversationMessage(
          input.context.actorUserId,
          conversation.id,
          {
            role: "assistant",
            content: finalText,
            ...messageCorrelation(correlation, {
              resultKind: "assistant_message",
              stopReason: "assistant_message",
            }),
          },
        );
        yield {
          type: "assistant_delta",
          conversationId: conversation.id,
          delta: finalText,
        };
        await this.logRun({
          type: "agent.chat",
          traceId: input.context.traceId,
          userId: input.context.actorUserId,
          conversationId: conversation.id,
          inputText: text,
          inputMode,
          resultKind: "assistant_message",
          toolCallCount,
          timingsMs: { total: Date.now() - runStarted },
        });
        await this.recordTurnTelemetry({
          correlation,
          userId: input.context.actorUserId,
          text,
          assistantText: latestAssistantText,
          model: this.model,
          resultKind: latestResultKind,
          stopReason: latestStopReason,
          iterationCount: iteration,
          toolCallCount,
          promptTokens: zeroAsUndefined(accumulatedPromptTokens),
          completionTokens: zeroAsUndefined(accumulatedCompletionTokens),
          totalTokens: zeroAsUndefined(accumulatedTotalTokens),
          reasoningTokens: zeroAsUndefined(accumulatedReasoningTokens),
          providerCostAmount: zeroAsUndefined(accumulatedProviderCost),
          estimatedCostAmount: zeroAsUndefined(accumulatedEstimatedCost),
          costCurrency,
          costSource,
          pricingSnapshot: lastPricingSnapshot,
          firstByteMs,
          firstToolCallMs,
          largestStreamGapMs,
          llmMs: zeroAsUndefined(accumulatedLlmMs),
          actionMs: zeroAsUndefined(accumulatedActionMs),
          totalMs: Date.now() - runStarted,
          status: "success",
        });
        yield { type: "done", conversationId: conversation.id };
        return;
      }

      const toolCalls = decision.toolCalls.slice(
        0,
        MAX_TOOL_CALLS_PER_TURN - toolCallCount,
      );
      if (toolCalls.length === 0) {
        await this.recordTurnTelemetry({
          correlation,
          userId: input.context.actorUserId,
          text,
          assistantText: latestAssistantText,
          model: this.model,
          iterationCount: iteration,
          toolCallCount,
          status: "failure",
          errorCode: "tool_call_limit",
          errorMessage: "The assistant reached the tool-call limit for this turn.",
          totalMs: Date.now() - runStarted,
        });
        yield {
          type: "error",
          conversationId: conversation.id,
          error: "The assistant reached the tool-call limit for this turn.",
        };
        return;
      }

      const assistantToolMessage: AgentMessage = {
        role: "assistant",
        content: assistantText,
        toolCalls,
      };
      messages.push(assistantToolMessage);
      await this.repository.addAgentConversationMessage(
        input.context.actorUserId,
        conversation.id,
        {
          role: "assistant",
          content: assistantText,
          toolCalls,
          ...messageCorrelation(correlation, {
            providerRouting: decision.providerRouting,
            iteration,
            toolCallCount: toolCalls.length,
          }),
        },
      );

      for (const toolCall of toolCalls) {
        toolCallCount++;
        const actionId = toolCall.function.name;

        let parsedInput: unknown;
        try {
          parsedInput = JSON.parse(toolCall.function.arguments || "{}");
        } catch {
          const feedback = describeToolCall(toolCall, undefined);
          const error = "The assistant sent invalid tool arguments.";
          yield {
            type: "tool_call_failed",
            conversationId: conversation.id,
            toolCall: feedback,
            error,
          };
          await this.addToolErrorMessage(
            input.context.actorUserId,
            conversation.id,
            messages,
            toolCall,
            actionId,
            error,
            correlation,
            { iteration, errorCode: "invalid_tool_arguments" },
          );
          await this.recordToolCallTelemetry({
            correlation,
            userId: input.context.actorUserId,
            toolCall,
            actionId,
            status: "failed",
            errorMessage: error,
            iteration,
            toolCallIndex: toolCallCount,
          });
          continue;
        }

        if (actionId === CHAT_OPTIONS_TOOL_NAME) {
          const quickReply = normalizeChatOptions(parsedInput, assistantText);
          if (!quickReply) {
            const feedback = describeToolCall(toolCall, parsedInput);
            const error = "The assistant sent invalid chat options.";
            yield {
              type: "tool_call_failed",
              conversationId: conversation.id,
              toolCall: feedback,
              error,
            };
            await this.addToolErrorMessage(
              input.context.actorUserId,
              conversation.id,
              messages,
              toolCall,
              actionId,
              error,
              correlation,
              { iteration, errorCode: "invalid_chat_options" },
            );
            await this.recordToolCallTelemetry({
              correlation,
              userId: input.context.actorUserId,
              toolCall,
              actionId,
              arguments: parsedInput,
              status: "failed",
              errorMessage: error,
              iteration,
              toolCallIndex: toolCallCount,
            });
            continue;
          }

          await this.repository.addAgentConversationMessage(
            input.context.actorUserId,
            conversation.id,
            {
              role: "assistant",
              content: quickReply.message,
              ...messageCorrelation(correlation, {
                suggestions: quickReply.suggestions,
                resultKind: "assistant_options",
                iteration,
              }),
            },
          );
          yield {
            type: "assistant_delta",
            conversationId: conversation.id,
            delta: quickReply.message,
          };
          yield {
            type: "assistant_suggestions",
            conversationId: conversation.id,
            suggestions: quickReply.suggestions,
          };
          latestAssistantText = quickReply.message;
          latestResultKind = "assistant_options";
          latestStopReason = "assistant_options";
          await this.logRun({
            type: "agent.chat",
            traceId: input.context.traceId,
            userId: input.context.actorUserId,
            conversationId: conversation.id,
            inputText: text,
            inputMode,
            resultKind: "assistant_options",
            toolCallCount,
            timingsMs: { total: Date.now() - runStarted },
          });
          await this.recordToolCallTelemetry({
            correlation,
            userId: input.context.actorUserId,
            toolCall,
            actionId,
            arguments: parsedInput,
            resultSummary: quickReply,
            status: "completed",
            iteration,
            toolCallIndex: toolCallCount,
          });
          await this.recordTurnTelemetry({
            correlation,
            userId: input.context.actorUserId,
            text,
            assistantText: latestAssistantText,
            model: this.model,
            resultKind: latestResultKind,
            stopReason: latestStopReason,
            iterationCount: iteration,
            toolCallCount,
            promptTokens: zeroAsUndefined(accumulatedPromptTokens),
            completionTokens: zeroAsUndefined(accumulatedCompletionTokens),
            totalTokens: zeroAsUndefined(accumulatedTotalTokens),
            reasoningTokens: zeroAsUndefined(accumulatedReasoningTokens),
            providerCostAmount: zeroAsUndefined(accumulatedProviderCost),
            estimatedCostAmount: zeroAsUndefined(accumulatedEstimatedCost),
            costCurrency,
            costSource,
            pricingSnapshot: lastPricingSnapshot,
            firstByteMs,
            firstToolCallMs,
            largestStreamGapMs,
            llmMs: zeroAsUndefined(accumulatedLlmMs),
            actionMs: zeroAsUndefined(accumulatedActionMs),
            totalMs: Date.now() - runStarted,
            status: "success",
          });
          yield { type: "done", conversationId: conversation.id };
          return;
        }

        if (!allowedActions.some((action) => action.id === actionId)) {
          const feedback = describeToolCall(toolCall, parsedInput);
          const error = `This action is not available: ${actionId}`;
          yield {
            type: "tool_call_failed",
            conversationId: conversation.id,
            toolCall: feedback,
            error,
          };
          await this.addToolErrorMessage(
            input.context.actorUserId,
            conversation.id,
            messages,
            toolCall,
            actionId,
            error,
            correlation,
            { iteration, errorCode: "disallowed_tool" },
          );
          await this.recordToolCallTelemetry({
            correlation,
            userId: input.context.actorUserId,
            toolCall,
            actionId,
            arguments: parsedInput,
            status: "failed",
            errorMessage: error,
            iteration,
            toolCallIndex: toolCallCount,
          });
          continue;
        }

        if (
          currentActiveProposal &&
          actionId === "revise_meal_proposal" &&
          typeof parsedInput === "object" &&
          parsedInput !== null &&
          !Array.isArray(parsedInput) &&
          !("proposalId" in parsedInput)
        ) {
          parsedInput = {
            ...parsedInput,
            proposalId: currentActiveProposal.id,
          };
        }

        const signature = `${actionId}:${JSON.stringify(parsedInput)}`;
        const feedback = describeToolCall(toolCall, parsedInput);
        if (executedSignatures.has(signature)) {
          const error = "Skipped a repeated tool call with the same arguments.";
          yield {
            type: "tool_call_failed",
            conversationId: conversation.id,
            toolCall: feedback,
            error,
          };
          await this.addToolErrorMessage(
            input.context.actorUserId,
            conversation.id,
            messages,
            toolCall,
            actionId,
            error,
            correlation,
            { iteration, errorCode: "repeated_tool_call" },
          );
          await this.recordToolCallTelemetry({
            correlation,
            userId: input.context.actorUserId,
            toolCall,
            actionId,
            arguments: parsedInput,
            status: "skipped",
            errorMessage: error,
            iteration,
            toolCallIndex: toolCallCount,
          });
          continue;
        }
        executedSignatures.add(signature);
        yield {
          type: "tool_call_started",
          conversationId: conversation.id,
          toolCall: feedback,
        };

        const actionStarted = Date.now();
        try {
          const result = await this.actionExecutor.execute(
            actionId,
            parsedInput,
            {
              ...input.context,
              source: "internal_agent",
            },
          );
          const mapped = mapActionResult(actionId, result, text);
          const actionMs = Date.now() - actionStarted;
          accumulatedActionMs += actionMs;
          latestResultKind = mapped.kind;
          if ("proposal" in mapped && mapped.proposal) {
            currentActiveProposal = mapped.proposal;
          }
          if (
            mapped.kind === "meal_committed" ||
            mapped.kind === "meal_deleted"
          ) {
            currentActiveProposal = undefined;
          }
          const widget = widgetForResult(mapped);
          yield {
            type: "tool_call_completed",
            conversationId: conversation.id,
            toolCall: feedback,
            result: mapped,
            widget,
          };

          const toolContent = safeToolContent({
            actionId,
            input: parsedInput,
            result: mapped,
            rawOutput: result.output,
          });
          const toolMessage: AgentMessage = {
            role: "tool",
            toolCallId: toolCall.id,
            content: toolContent,
          };
          messages.push(toolMessage);
          await this.repository.addAgentConversationMessage(
            input.context.actorUserId,
            conversation.id,
            {
              role: "tool",
              content: toolContent,
              toolCallId: toolCall.id,
              ...messageCorrelation(correlation, {
                actionId,
                actionCallId: result.actionCallId,
                iteration,
                toolCallIndex: toolCallCount,
                resultKind: mapped.kind,
              }),
            },
          );
          await this.recordToolCallTelemetry({
            correlation,
            userId: input.context.actorUserId,
            toolCall,
            actionId,
            actionCallId: result.actionCallId,
            arguments: parsedInput,
            resultSummary: mapped,
            status: "completed",
            iteration,
            toolCallIndex: toolCallCount,
            durationMs: actionMs,
          });
        } catch (error) {
          const errorText =
            error instanceof Error ? error.message : String(error);
          yield {
            type: "tool_call_failed",
            conversationId: conversation.id,
            toolCall: feedback,
            error: errorText,
          };
          const toolMessage: AgentMessage = {
            role: "tool",
            toolCallId: toolCall.id,
            content: JSON.stringify({ actionId, error: errorText }),
          };
          messages.push(toolMessage);
          await this.repository.addAgentConversationMessage(
            input.context.actorUserId,
            conversation.id,
            {
              role: "tool",
              content: toolMessage.content,
              toolCallId: toolCall.id,
              ...messageCorrelation(correlation, {
                actionId,
                error: errorText,
                iteration,
                toolCallIndex: toolCallCount,
              }),
            },
          );
          const actionMs = Date.now() - actionStarted;
          accumulatedActionMs += actionMs;
          await this.recordToolCallTelemetry({
            correlation,
            userId: input.context.actorUserId,
            toolCall,
            actionId,
            arguments: parsedInput,
            status: "failed",
            errorMessage: errorText,
            iteration,
            toolCallIndex: toolCallCount,
            durationMs: actionMs,
          });
        }
      }
    }

    yield {
      type: "error",
      conversationId: conversation.id,
      error: "The assistant stopped after the maximum number of steps.",
    };
    await this.recordTurnTelemetry({
      correlation,
      userId: input.context.actorUserId,
      text,
      assistantText: latestAssistantText,
      model: this.model,
      resultKind: latestResultKind,
      stopReason: "max_iterations",
      iterationCount: iteration,
      toolCallCount,
      promptTokens: zeroAsUndefined(accumulatedPromptTokens),
      completionTokens: zeroAsUndefined(accumulatedCompletionTokens),
      totalTokens: zeroAsUndefined(accumulatedTotalTokens),
      reasoningTokens: zeroAsUndefined(accumulatedReasoningTokens),
      providerCostAmount: zeroAsUndefined(accumulatedProviderCost),
      estimatedCostAmount: zeroAsUndefined(accumulatedEstimatedCost),
      costCurrency,
      costSource,
      pricingSnapshot: lastPricingSnapshot,
      firstByteMs,
      firstToolCallMs,
      largestStreamGapMs,
      llmMs: zeroAsUndefined(accumulatedLlmMs),
      actionMs: zeroAsUndefined(accumulatedActionMs),
      totalMs: Date.now() - runStarted,
      status: "failure",
      errorCode: "max_iterations",
      errorMessage: "The assistant stopped after the maximum number of steps.",
    });
  }

  private async resolveConversation(
    userId: string,
    conversationId?: string,
    initialText?: string,
  ): Promise<AgentConversationRecord> {
    if (!conversationId) {
      return this.repository.createAgentConversation(userId, {
        title: conversationTitleFromInput(initialText),
      });
    }
    const existing = await this.repository.getAgentConversation(
      userId,
      conversationId,
    );
    if (!existing) throw new Error("agent_conversation_not_found");
    return existing;
  }

  private async addToolErrorMessage(
    userId: string,
    conversationId: string,
    messages: AgentMessage[],
    toolCall: AgentToolCall,
    actionId: string,
    error: string,
    correlation: ChatTurnCorrelation,
    metadata: Record<string, unknown> = {},
  ): Promise<void> {
    const toolMessage: AgentMessage = {
      role: "tool",
      toolCallId: toolCall.id,
      content: JSON.stringify({ actionId, error }),
    };
    messages.push(toolMessage);
    await this.repository.addAgentConversationMessage(userId, conversationId, {
      role: "tool",
      content: toolMessage.content,
      toolCallId: toolCall.id,
      ...messageCorrelation(correlation, { ...metadata, actionId, error }),
    });
  }

  private async messagesForModel(
    userId: string,
    conversationId: string,
    context: ActionContext,
    activeProposal?: MealProposal,
  ): Promise<AgentMessage[]> {
    const stored = await this.repository.listAgentConversationMessages(
      userId,
      conversationId,
    );
    return [
      buildChatSystemMessage(context, activeProposal),
      ...stored.map(storedMessageToAgentMessage),
    ];
  }

  private async recordProviderTelemetry(input: {
    correlation: ChatTurnCorrelation;
    userId: string;
    decision: AgentToolDecision;
    iteration: number;
    cost: LlmCostResult;
    tokenMetrics: ReturnType<typeof extractLlmTokenMetrics>;
  }): Promise<void> {
    try {
      await this.telemetryService.recordLlmProviderCall({
        traceId: input.correlation.traceId,
        userId: input.userId,
        conversationId: input.correlation.conversationId,
        turnId: input.correlation.turnId,
        featureSurface: "agent_chat",
        provider: "openrouter",
        providerGenerationId: extractGenerationId(input.decision.rawResponse),
        requestedModel: this.model,
        routing: input.decision.providerRouting,
        inputMode: input.correlation.inputMode,
        promptTokens: input.tokenMetrics.promptTokens,
        completionTokens: input.tokenMetrics.completionTokens,
        totalTokens: input.tokenMetrics.totalTokens,
        reasoningTokens: input.tokenMetrics.reasoningTokens,
        providerCostAmount: input.cost.providerCostAmount,
        estimatedCostAmount: input.cost.estimatedCostAmount,
        costCurrency: input.cost.costCurrency,
        costSource: input.cost.costSource,
        inputTokenUnitPrice: input.cost.inputTokenUnitPrice,
        outputTokenUnitPrice: input.cost.outputTokenUnitPrice,
        reasoningTokenUnitPrice: input.cost.reasoningTokenUnitPrice,
        cachedInputTokenUnitPrice: input.cost.cachedInputTokenUnitPrice,
        pricingSource: input.cost.pricingSource,
        pricingVersion: input.cost.pricingVersion,
        pricingEffectiveAt: input.cost.pricingEffectiveAt,
        status: "success",
        durationMs: input.decision.timingsMs?.totalMs,
        metadata: {
          iteration: input.iteration,
          toolCallCount: input.decision.toolCalls.length,
          streamEventCount: input.decision.timingsMs?.streamEventCount,
        },
      });
      await this.telemetryService.recordLlmRun({
        flow: "llm_run",
        surface: "agent",
        traceId: input.correlation.traceId,
        userId: input.userId,
        conversationId: input.correlation.conversationId,
        turnId: input.correlation.turnId,
        provider: "openrouter",
        providerGenerationId: extractGenerationId(input.decision.rawResponse),
        model: this.model,
        source: input.correlation.source,
        inputMode: input.correlation.inputMode,
        activeProposalId: input.correlation.activeProposalId,
        outcome: "success",
        selectedTool: input.decision.toolCalls[0]?.function.name,
        promptTokens: input.tokenMetrics.promptTokens,
        completionTokens: input.tokenMetrics.completionTokens,
        totalTokens: input.tokenMetrics.totalTokens,
        reasoningTokens: input.tokenMetrics.reasoningTokens,
        firstByteMs: input.decision.timingsMs?.firstByteMs,
        firstToolCallMs: input.decision.timingsMs?.firstToolCallMs,
        largestStreamGapMs: input.decision.timingsMs?.largestStreamGapMs,
        timingsMs: { llm: input.decision.timingsMs?.totalMs },
        providerCostAmount: input.cost.providerCostAmount,
        estimatedCostAmount: input.cost.estimatedCostAmount,
        costCurrency: input.cost.costCurrency,
        costSource: input.cost.costSource,
        pricingSnapshot: input.cost.pricingSnapshot,
        metadata: { iteration: input.iteration },
      });
    } catch (error) {
      console.warn("agent.chat_provider_telemetry.failed", summarizeError(error));
    }
  }

  private async recordToolCallTelemetry(input: {
    correlation: ChatTurnCorrelation;
    userId: string;
    toolCall: AgentToolCall;
    actionId: string;
    actionCallId?: string;
    arguments?: unknown;
    resultSummary?: unknown;
    status: "started" | "completed" | "failed" | "skipped";
    errorMessage?: string;
    iteration: number;
    toolCallIndex: number;
    durationMs?: number;
  }): Promise<void> {
    try {
      const completedAt =
        input.status === "started" ? undefined : new Date().toISOString();
      await this.telemetryService.recordAgentToolCall({
        conversationId: input.correlation.conversationId,
        traceId: input.correlation.traceId,
        turnId: input.correlation.turnId,
        userId: input.userId,
        toolCallId: input.toolCall.id,
        actionCallId: input.actionCallId,
        actionId: input.actionId,
        arguments: input.arguments ?? safeParseJson(input.toolCall.function.arguments),
        resultSummary: input.resultSummary,
        status: input.status,
        errorMessage: input.errorMessage,
        startedAt: new Date(Date.now() - (input.durationMs ?? 0)).toISOString(),
        completedAt,
        durationMs: input.durationMs,
        metadata: {
          iteration: input.iteration,
          toolCallIndex: input.toolCallIndex,
        },
      });
    } catch (error) {
      console.warn("agent.chat_tool_telemetry.failed", summarizeError(error));
    }
  }

  private async recordTurnTelemetry(input: {
    correlation: ChatTurnCorrelation;
    userId: string;
    text: string;
    assistantText?: string;
    model: string;
    resultKind?: string;
    stopReason?: string;
    iterationCount: number;
    toolCallCount: number;
    promptTokens?: number;
    completionTokens?: number;
    totalTokens?: number;
    reasoningTokens?: number;
    providerCostAmount?: number;
    estimatedCostAmount?: number;
    costCurrency?: string;
    costSource?: string;
    pricingSnapshot?: Record<string, unknown>;
    firstByteMs?: number;
    firstToolCallMs?: number;
    largestStreamGapMs?: number;
    llmMs?: number;
    actionMs?: number;
    totalMs?: number;
    status: "success" | "failure" | "partial";
    errorCode?: string;
    errorMessage?: string;
  }): Promise<void> {
    try {
      await this.telemetryService.recordAgentTurn({
        traceId: input.correlation.traceId,
        turnId: input.correlation.turnId,
        userId: input.userId,
        conversationId: input.correlation.conversationId,
        inputMode: input.correlation.inputMode,
        source: input.correlation.source,
        activeProposalId: input.correlation.activeProposalId,
        model: input.model,
        inputText: input.text,
        assistantText: input.assistantText,
        resultKind: input.resultKind,
        stopReason: input.stopReason,
        iterationCount: input.iterationCount,
        toolCallCount: input.toolCallCount,
        promptTokens: input.promptTokens,
        completionTokens: input.completionTokens,
        totalTokens: input.totalTokens,
        reasoningTokens: input.reasoningTokens,
        providerCostAmount: input.providerCostAmount,
        estimatedCostAmount: input.estimatedCostAmount,
        costCurrency: input.costCurrency,
        costSource: input.costSource,
        pricingSnapshot: input.pricingSnapshot ?? {},
        firstByteMs: input.firstByteMs,
        firstToolCallMs: input.firstToolCallMs,
        largestStreamGapMs: input.largestStreamGapMs,
        llmMs: input.llmMs,
        actionMs: input.actionMs,
        totalMs: input.totalMs,
        status: input.status,
        errorCode: input.errorCode,
        errorMessage: input.errorMessage,
        completedAt: new Date().toISOString(),
        metadata: {},
      });
    } catch (error) {
      console.warn("agent.chat_turn_telemetry.failed", summarizeError(error));
    }
  }

  private async logRun(event: Record<string, unknown>): Promise<void> {
    try {
      await this.runLogger?.log(event);
    } catch (error) {
      console.warn("agent.chat_log.failed", summarizeError(error));
    }
  }
}

function storedMessageToAgentMessage(
  message: AgentConversationMessageRecord,
): AgentMessage {
  if (message.role === "assistant") {
    return {
      role: "assistant",
      content: message.content,
      toolCalls: Array.isArray(message.toolCalls)
        ? (message.toolCalls as AgentToolCall[])
        : undefined,
    };
  }
  if (message.role === "tool") {
    return {
      role: "tool",
      content: message.content,
      toolCallId: message.toolCallId ?? "",
    };
  }
  return { role: "user", content: message.content };
}

function extractLlmTokenMetrics(rawResponse: unknown): {
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
} {
  const usage = extractTokenUsage(rawResponse);
  if (!usage) return {};
  return {
    promptTokens: asNumber(usage.prompt_tokens),
    completionTokens: asNumber(usage.completion_tokens),
    totalTokens: asNumber(usage.total_tokens),
    reasoningTokens: extractReasoningTokens(rawResponse),
  };
}

function asNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function zeroAsUndefined(value: number): number | undefined {
  return value === 0 ? undefined : value;
}

function maxOptional(
  left: number | undefined,
  right: number | undefined,
): number | undefined {
  if (left === undefined) return right;
  if (right === undefined) return left;
  return Math.max(left, right);
}

function mergeCostSource(
  existing: string | undefined,
  next: string,
): string {
  if (!existing) return next;
  if (existing === next) return existing;
  if (existing === "provider" && next === "estimate") return "mixed";
  if (existing === "estimate" && next === "provider") return "mixed";
  if (existing === "mixed" || next === "mixed") return "mixed";
  if (existing === "unknown") return next;
  if (next === "unknown") return existing;
  return "mixed";
}

function safeParseJson(value: string): unknown {
  try {
    return JSON.parse(value || "{}");
  } catch {
    return undefined;
  }
}

function chatOptionsToolDefinition() {
  return {
    type: "function" as const,
    function: {
      name: CHAT_OPTIONS_TOOL_NAME,
      description: [
        "Show concise quick-reply buttons in the mobile chat.",
        "Use this only when asking the user to choose between 2 to 4 short interaction options, such as Yes/No or Save/Edit.",
        "The message should ask one clear question. Button labels should be brief and mobile-friendly.",
      ].join(" "),
      parameters: {
        type: "object",
        additionalProperties: false,
        required: ["message", "options"],
        properties: {
          message: {
            type: "string",
            description: "The assistant message shown above the buttons.",
          },
          options: {
            type: "array",
            minItems: 2,
            maxItems: 4,
            items: {
              type: "object",
              additionalProperties: false,
              required: ["label"],
              properties: {
                label: {
                  type: "string",
                  description: "Short button label shown in chat.",
                },
                value: {
                  type: "string",
                  description:
                    "Text to send if tapped. Defaults to label when omitted.",
                },
              },
            },
          },
        },
      },
    },
  };
}

function normalizeChatOptions(
  input: unknown,
  assistantText: string,
): { message: string; suggestions: AgentChatSuggestion[] } | undefined {
  if (!isRecord(input)) return undefined;
  const message = textValue(input.message, assistantText).trim();
  const options = Array.isArray(input.options) ? input.options : [];
  if (!message || options.length < 2 || options.length > 4) return undefined;
  const suggestions = options
    .map((option) => {
      if (!isRecord(option)) return undefined;
      const label = textValue(option.label).trim();
      const value = textValue(option.value, label).trim();
      if (!label || !value) return undefined;
      return { label: label.slice(0, 40), value: value.slice(0, 240) };
    })
    .filter((option): option is AgentChatSuggestion => option !== undefined);
  if (suggestions.length < 2) return undefined;
  return { message, suggestions: suggestions.slice(0, 4) };
}

function textValue(value: unknown, fallback = ""): string {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function describeToolCall(
  toolCall: AgentToolCall,
  parsedInput: unknown,
): AgentToolFeedback {
  const actionId = toolCall.function.name;
  const definition = actionDefinitions.find((action) => action.id === actionId);
  const input = isRecord(parsedInput) ? parsedInput : {};
  const text = textValue;
  const summaries: Record<string, string> = {
    show_chat_options: "Preparing quick reply buttons",
    query_food_memory: `Checking food memory for ${text(input.text, "this request")}`,
    search_nutrition_database: `Searching nutrition data for ${text(input.query, "food")}`,
    propose_meal_log: "Creating a meal proposal",
    revise_meal_proposal: "Updating the current meal proposal",
    create_meal_proposal_from_items:
      "Creating a meal proposal from selected foods",
    commit_meal: "Logging the confirmed meal",
    correct_meal: "Correcting meal items",
    delete_meal: "Preparing to delete a meal",
    get_daily_summary: `Reading daily summary${text(input.date) ? ` for ${text(input.date)}` : ""}`,
    get_remaining_targets: "Checking remaining calorie and macro targets",
    get_meal_history: "Reading recent meal history",
    get_usual_foods: "Reading usual ingredients",
    get_usual_meals: "Reading usual meals",
    draft_usual_food: "Preparing a usual ingredient draft",
    draft_usual_meal: "Preparing a usual meal draft",
  };
  return {
    id: toolCall.id,
    actionId,
    label: definition?.title ?? actionId,
    summary: summaries[actionId] ?? `Running ${definition?.title ?? actionId}`,
    input: parsedInput,
  };
}

function mapActionResult(
  actionId: string,
  result: ExecuteActionResult,
  originalText: string,
): AgentChatMappedResult {
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
        return {
          kind: "clarification_required",
          proposal: output.proposal as MealProposal | undefined,
          options: output.options as unknown[] | undefined,
          candidateGroups: output.candidateGroups as unknown[] | undefined,
          resolvedItems: output.resolvedItems as MealItem[] | undefined,
          message:
            typeof output.message === "string"
              ? output.message
              : "I could not confidently match every ingredient.",
        };
      }
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
        proposal: output.proposal as MealProposal,
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
    case "revise_meal_proposal":
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
    case "commit_meal":
      return {
        kind: "meal_committed",
        meal: output.meal as Meal,
        message: "Meal logged.",
      };
    case "correct_meal": {
      const meal = output.meal as Meal | undefined;
      const proposal = output.proposal as MealProposal | undefined;
      return meal
        ? { kind: "meal_corrected", meal, message: "Meal corrected." }
        : {
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
    case "get_usual_foods":
      return {
        kind: "usual_foods",
        usualFoods: output.usualFoods as UsualFood[],
        message: "Here are your usual ingredients.",
      };
    case "get_usual_meals":
      return {
        kind: "templates",
        templates: output.templates as MealTemplate[],
        message: "Here are your usual meals.",
      };
    case "draft_usual_food":
      return {
        kind: "usual_food_draft",
        usualFoodDraft: output as DraftUsualFoodOutput,
        message:
          typeof output.message === "string"
            ? output.message
            : "Usual ingredient draft created for review.",
      };
    case "draft_usual_meal":
      return {
        kind: "usual_meal_draft",
        usualMealDraft: output as DraftUsualMealOutput,
        options: output.options as unknown[] | undefined,
        candidateGroups: output.candidateGroups as unknown[] | undefined,
        message:
          typeof output.message === "string"
            ? output.message
            : output.clarificationRequired
              ? "Usual meal draft needs ingredient matches before saving."
              : "Usual meal draft created for review.",
      };
    case "create_meal_template":
    case "update_meal_template":
      return {
        kind: "template_saved",
        template: output.template as MealTemplate,
        message:
          actionId === "create_meal_template"
            ? "Usual meal created."
            : "Usual meal updated.",
      };
    case "delete_meal_template":
      return {
        kind: "template_deleted",
        deleted: Boolean(output.deleted),
        message: output.deleted
          ? "Usual meal deleted."
          : "Usual meal was not found.",
      };
    case "delete_meal":
      if ((output as { confirmationRequired?: boolean }).confirmationRequired) {
        return {
          kind: "confirmation_required",
          actionId: "delete_meal",
          input: { ...output, originalText },
          message: "Please confirm deletion.",
        };
      }
      return { kind: "meal_deleted", message: "Meal deleted." };
    default:
      return {
        kind: "clarification_required",
        message: "Action completed but I don't know how to display the result.",
      };
  }
}

function widgetForResult(result: AgentChatMappedResult): AgentWidgetPayload {
  const titles: Record<AgentChatResultKind, string> = {
    proposal: "Meal proposal",
    meal_committed: "Meal logged",
    meal_corrected: "Meal corrected",
    summary: "Daily summary",
    remaining_targets: "Remaining targets",
    history: "Meal history",
    food_memory: "Food memory",
    nutrition_search: "Nutrition search",
    usual_foods: "Usual ingredients",
    templates: "Usual meals",
    template_saved: "Usual meal saved",
    template_deleted: "Usual meal deleted",
    usual_food_draft: "Usual ingredient draft",
    usual_meal_draft: "Usual meal draft",
    confirmation_required: "Needs confirmation",
    meal_deleted: "Meal deleted",
    clarification_required: "Needs clarification",
  };
  return { kind: result.kind, title: titles[result.kind], result };
}

function safeToolContent(value: unknown): string {
  const content = JSON.stringify(value);
  if (content.length <= STORED_TOOL_RESULT_MAX_CHARS) return content;
  return `${content.slice(0, STORED_TOOL_RESULT_MAX_CHARS)}...`;
}

function conversationTitleFromInput(input?: string): string {
  const title = (input ?? "").replace(/\s+/g, " ").trim();
  if (!title) return "Nutrition chat";
  if (title.length <= MAX_CONVERSATION_TITLE_CHARS) return title;
  return `${title.slice(0, MAX_CONVERSATION_TITLE_CHARS - 3).trimEnd()}...`;
}

function messageCorrelation(
  correlation: ChatTurnCorrelation,
  metadata: Record<string, unknown> = {},
): Pick<
  AgentConversationMessageRecord,
  "traceId" | "turnId" | "inputMode" | "source" | "activeProposalId" | "metadata"
> {
  const activeProposalId = correlation.activeProposalId;
  return {
    traceId: correlation.traceId,
    turnId: correlation.turnId,
    inputMode: correlation.inputMode,
    source: correlation.source,
    activeProposalId,
    metadata: {
      traceId: correlation.traceId,
      turnId: correlation.turnId,
      inputMode: correlation.inputMode,
      source: correlation.source,
      conversationId: correlation.conversationId,
      ...(activeProposalId ? { activeProposalId } : {}),
      ...metadata,
    },
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function prioritizeDefaultTool<T extends { id: string }>(actions: T[]): T[] {
  return [...actions].sort((a, b) => {
    if (a.id === "propose_meal_log") return -1;
    if (b.id === "propose_meal_log") return 1;
    return 0;
  });
}
