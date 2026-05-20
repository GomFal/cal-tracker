import {
  actionById,
  actionDefinitions,
  commitMealInputSchema,
  correctMealInputSchema,
  createMealProposalFromItemsInputSchema,
  createMealTemplateInputSchema,
  deleteMealInputSchema,
  deleteMealTemplateInputSchema,
  getDailySummaryInputSchema,
  getMealHistoryInputSchema,
  getRemainingTargetsInputSchema,
  proposeMealLogInputSchema,
  queryFoodMemoryInputSchema,
  reviseMealProposalInputSchema,
  searchNutritionDatabaseInputSchema,
  updateMealTemplateInputSchema,
  type ActionContext,
  type FoodCandidateGroup,
  type FoodMention,
  type Meal,
  type MealItem,
  type MealLabel,
  type MealProposal,
} from "@cal-tracker/contracts";
import type { AppConfig } from "../config/env.js";
import type {
  MealTextResolutionProvider,
  NutritionProvider,
  NutritionSearchResult,
} from "../nutrition/provider.js";
import type { AppRepository, FoodFeedbackAction, FoodFeedbackRecord } from "../repository/types.js";
import type { MemoryRetrievalService } from "../memory/retrieval.js";
import { withSpan, withSyncSpan } from "../observability/profiler.js";
import { newId } from "../utils/ids.js";
import { normalizeText } from "../utils/normalize.js";
import { sumNutrition } from "../utils/nutrition.js";

export type ExecuteActionResult = {
  actionCallId: string;
  confirmationRequired: boolean;
  output: unknown;
  instrumentation?: Record<string, unknown>;
};

export class ActionExecutionError extends Error {
  constructor(
    public readonly code: string,
    message = code,
  ) {
    super(message);
  }
}

function actionInstrumentation(output: unknown): Record<string, unknown> | undefined {
  if (
    typeof output !== "object" ||
    output === null ||
    Array.isArray(output) ||
    !("instrumentation" in output)
  ) {
    return undefined;
  }
  return (output as { instrumentation?: Record<string, unknown> })
    .instrumentation;
}

type FoodFeedbackEventType =
  | "selected_for_proposal"
  | "proposal_committed"
  | "proposal_corrected"
  | "meal_corrected";

type FoodFeedbackInput = {
  userId: string;
  eventType: FoodFeedbackEventType;
  traceId: string;
  source: string;
  phrase?: string;
  proposalId?: string;
  mealId?: string;
  items: MealItem[];
  previousItems?: MealItem[];
  metadata?: Record<string, unknown>;
};

export class ActionExecutor {
  constructor(
    private readonly config: AppConfig,
    private readonly repository: AppRepository,
    private readonly nutritionProvider: NutritionProvider,
    private readonly memoryRetrievalService?: MemoryRetrievalService,
  ) {}

  listActions() {
    return actionDefinitions.map(
      ({
        inputSchema: _inputSchema,
        outputSchema: _outputSchema,
        ...metadata
      }) => metadata,
    );
  }

  async execute(
    actionId: string,
    rawInput: unknown,
    context: ActionContext,
  ): Promise<ExecuteActionResult> {
    return withSpan(
      "ActionExecutor.execute",
      { actionId, source: context.source },
      () => this.executeInternal(actionId, rawInput, context),
    );
  }

  private async executeInternal(
    actionId: string,
    rawInput: unknown,
    context: ActionContext,
  ): Promise<ExecuteActionResult> {
    const definition = actionById.get(actionId);
    if (!definition)
      throw new ActionExecutionError(
        "unknown_action",
        `Unknown action: ${actionId}`,
      );
    if (!context.scopes.includes(definition.permissionScope)) {
      throw new ActionExecutionError(
        "permission_denied",
        `Missing scope: ${definition.permissionScope}`,
      );
    }

    const started = Date.now();
    const input = withSyncSpan(
      "ActionExecutor.parseInput",
      { actionId },
      () => definition.inputSchema.parse(rawInput),
    );
    let actionCallId = newId();

    try {
      const output = await withSpan(
        "ActionExecutor.dispatch",
        { actionId },
        () => this.dispatch(actionId, input, context),
      );
      const call = await withSpan(
        "Repository.recordActionCall",
        { actionId, status: definition.confirmationPolicy },
        () => this.repository.recordActionCall({
          userId: context.actorUserId,
          actionId,
          source: context.source,
          input,
          output,
          confirmationStatus: definition.confirmationPolicy,
          traceId: context.traceId,
          latencyMs: Date.now() - started,
        }),
      );
      actionCallId = call.id;
      if (definition.sideEffect !== "none") {
        await withSpan(
          "Repository.recordAuditEvent",
          { eventType: `action.${actionId}` },
          () => this.repository.recordAuditEvent({
            userId: context.actorUserId,
            eventType: `action.${actionId}`,
            metadata: { input, output },
            traceId: context.traceId,
          }),
        );
      }
      return {
        actionCallId,
        confirmationRequired: definition.confirmationPolicy === "required",
        output,
        instrumentation: actionInstrumentation(output),
      };
    } catch (error) {
      const call = await withSpan(
        "Repository.recordActionCall",
        { actionId, status: "error" },
        () => this.repository.recordActionCall({
          userId: context.actorUserId,
          actionId,
          source: context.source,
          input,
          error: error instanceof Error ? { message: error.message } : error,
          confirmationStatus: "error",
          traceId: context.traceId,
          latencyMs: Date.now() - started,
        }),
      );
      throw Object.assign(
        error instanceof Error ? error : new Error("action_failed"),
        { actionCallId: call.id },
      );
    }
  }

  private async dispatch(
    actionId: string,
    input: unknown,
    context: ActionContext,
  ): Promise<unknown> {
    switch (actionId) {
      case "query_food_memory": {
        const parsed = queryFoodMemoryInputSchema.parse(input);
        const memory = await this.queryMemory(context.actorUserId, parsed.text);
        const matches = memory.matches;
        return {
          matches,
          needsClarification:
            matches.length === 0 || matches[0]!.confidence < 0.75,
        };
      }
      case "search_nutrition_database": {
        const parsed = searchNutritionDatabaseInputSchema.parse(input);
        const searchResult = normalizeNutritionSearchResult(
          await this.nutritionProvider.search(
            context.actorUserId,
            parsed.query,
            parsed.barcode,
            context.locale,
          ),
        );
        return {
          items: searchResult.items,
          candidates: searchResult.candidateGroups,
          candidateGroups: searchResult.candidateGroups,
        };
      }
      case "propose_meal_log":
        return this.proposeMeal(input, context);
      case "create_meal_proposal_from_items":
        return this.createMealProposalFromItems(input, context);
      case "commit_meal": {
        const parsed = commitMealInputSchema.parse(input);
        const proposal = await this.requireProposal(
          context.actorUserId,
          parsed.proposalId,
        );
        const mealLabel = normalizeMealLabel(parsed.mealLabel);
        const meal = await this.repository.createMealFromProposal(
          context.actorUserId,
          proposal,
          parsed.occurredAt ?? new Date().toISOString(),
          parsed.items,
          mealLabel,
        );
        await recordFoodFeedback(this.repository, {
          userId: context.actorUserId,
          eventType: "proposal_committed",
          traceId: context.traceId,
          source: context.source,
          phrase: proposal.phrase,
          proposalId: proposal.id,
          mealId: meal.id,
          items: meal.items,
          previousItems: proposal.items,
          metadata: { overriddenItems: Boolean(parsed.items?.length) },
        });
        return { meal };
      }
      case "correct_meal":
        return this.correctMeal(input, context);
      case "revise_meal_proposal":
        return this.reviseMealProposal(input, context);
      case "delete_meal": {
        const parsed = deleteMealInputSchema.parse(input);
        if (parsed.confirmationToken !== "DELETE") {
          return { deleted: false, confirmationRequired: true };
        }
        return {
          deleted: await this.repository.softDeleteMeal(
            context.actorUserId,
            parsed.mealId,
          ),
          confirmationRequired: false,
        };
      }
      case "get_daily_summary": {
        const parsed = getDailySummaryInputSchema.parse(input);
        return {
          summary: await this.repository.getDailySummary(
            context.actorUserId,
            parsed.date ?? today(),
          ),
        };
      }
      case "get_remaining_targets": {
        const parsed = getRemainingTargetsInputSchema.parse(input);
        const summary = await this.repository.getDailySummary(
          context.actorUserId,
          parsed.date ?? today(),
        );
        return { remaining: summary.remaining };
      }
      case "get_meal_history": {
        const parsed = getMealHistoryInputSchema.parse(input);
        return {
          meals: await this.repository.listMeals(
            context.actorUserId,
            parsed.limit,
          ),
        };
      }
      case "get_usual_meals":
        return {
          templates: await this.repository.listTemplates(context.actorUserId),
        };
      case "create_meal_template": {
        const parsed = createMealTemplateInputSchema.parse(input);
        const nutrition = sumNutrition(parsed.items);
        const template = await this.repository.createTemplate(
          context.actorUserId,
          { ...parsed, nutrition },
        );
        return { template };
      }
      case "update_meal_template": {
        const parsed = updateMealTemplateInputSchema.parse(input);
        const templates = await this.repository.listTemplates(
          context.actorUserId,
        );
        const existing = templates.find(
          (template) => template.id === parsed.templateId,
        );
        if (!existing) throw new ActionExecutionError("template_not_found");
        const items = parsed.items ?? existing.items;
        const template = await this.repository.updateTemplate(
          context.actorUserId,
          {
            ...existing,
            ...parsed,
            id: parsed.templateId,
            items,
            aliases: parsed.aliases ?? existing.aliases,
            trustedAutoCommitEnabled:
              parsed.trustedAutoCommitEnabled ??
              existing.trustedAutoCommitEnabled,
            nutrition: sumNutrition(items),
          },
        );
        return { template };
      }
      case "delete_meal_template": {
        const parsed = deleteMealTemplateInputSchema.parse(input);
        return {
          deleted: await this.repository.deleteTemplate(
            context.actorUserId,
            parsed.templateId,
          ),
        };
      }
      default:
        throw new ActionExecutionError("unimplemented_action", actionId);
    }
  }

  private async proposeMeal(
    input: unknown,
    context: ActionContext,
  ): Promise<Record<string, unknown>> {
    const started = Date.now();
    const phases: Record<string, number> = {};
    const markPhase = (name: string, phaseStarted: number) => {
      phases[name] = Date.now() - phaseStarted;
    };

    const parseStarted = Date.now();
    const parsed = withSyncSpan(
      "ActionExecutor.proposeMeal.parseInput",
      undefined,
      () => proposeMealLogInputSchema.parse(input),
    );
    const normalized = normalizeText(parsed.text);
    const providedMentions =
      parsed.mentions && parsed.mentions.length > 0 ? parsed.mentions : null;
    const inputMode = providedMentions
      ? "model_mentions"
      : "deterministic_fallback";
    markPhase("parse_and_normalize", parseStarted);

    const memoryStarted = Date.now();
    const memories = (await withSpan(
      "ActionExecutor.proposeMeal.queryMemory",
      undefined,
      () => this.queryMemory(context.actorUserId, normalized),
    )).matches;
    markPhase("query_memory", memoryStarted);
    const memory = memories[0];
    const template = memory?.template ?? null;
    const fromTemplate = Boolean(
      template && memory && memory.confidence >= 0.75,
    );

    const resolutionStarted = Date.now();
    const resolution = template
      ? null
      : providedMentions
        ? await withSpan(
            "ActionExecutor.proposeMeal.resolveProvidedMentions",
            { mentionCount: providedMentions.length },
            () => this.resolveMealMentions(context.actorUserId, providedMentions, context.locale),
          )
        : await withSpan(
            "ActionExecutor.proposeMeal.resolveMealText",
            { textChars: parsed.text.length },
            () => this.resolveMealText(context.actorUserId, parsed.text, context.locale),
          );
    markPhase(
      template
        ? "resolve_meal_text_skipped_template"
        : providedMentions
          ? "resolve_provided_mentions"
          : "resolve_meal_text",
      resolutionStarted,
    );
    if (resolution?.clarificationRequired) {
      const clarificationStarted = Date.now();
      const unsupportedUnitMessage = unsupportedUnitClarification(
        resolution.candidateGroups,
      );
      markPhase("build_clarification", clarificationStarted);
      return {
        clarificationRequired: true,
        resolvedItems: resolution.items,
        unresolvedMentions: resolution.unresolvedMentions,
        options: resolution.candidateGroups,
        message:
          unsupportedUnitMessage ??
          (resolution.unresolvedMentions.length > 0
            ? "I could not confidently match every ingredient. Please choose a food match or rephrase the meal."
            : "I could not identify the ingredients in that meal. Please add quantities and food names."),
        instrumentation: {
          action: "propose_meal_log",
          path: "clarification_required",
          inputMode,
          usedTemplate: false,
          memoryMatches: memories.length,
          resolvedItems: resolution.items.length,
          unresolvedMentions: resolution.unresolvedMentions.length,
          candidateGroups: resolution.candidateGroups.length,
          phasesMs: phases,
          totalMs: Date.now() - started,
        },
      };
    }
    const itemStarted = Date.now();
    const items: MealItem[] = template
      ? template.items
      : (resolution?.items ??
        (await withSpan(
          "ActionExecutor.proposeMeal.estimateMeal",
          undefined,
          () => this.nutritionProvider.estimateMeal(
            context.actorUserId,
            parsed.text,
          ),
        )));
    markPhase(
      template
        ? "select_template_items"
        : resolution?.items
          ? "select_resolved_items"
          : "estimate_meal",
      itemStarted,
    );
    const nutritionStarted = Date.now();
    const nutrition = withSyncSpan(
      "ActionExecutor.proposeMeal.sumNutrition",
      { itemCount: items.length },
      () => sumNutrition(items),
    );
    markPhase("sum_nutrition", nutritionStarted);
    const trustedAutoCommitEligible = Boolean(
      template &&
      memory &&
      context.trustedModeEnabled &&
      template.trustedAutoCommitEnabled &&
      memory.confidence >= this.config.TRUSTED_AUTO_COMMIT_THRESHOLD &&
      items.every((item) => item.source !== "llm_estimate"),
    );
    const proposalStarted = Date.now();
    const proposal = await withSpan(
      "Repository.createProposal",
      { itemCount: items.length },
      () => this.repository.createProposal(context.actorUserId, {
        phrase: parsed.text,
        title: template?.title ?? inferTitle(parsed.text, items),
        status: "pending",
        confidence: fromTemplate ? memory!.confidence : 0.68,
        requiresConfirmation: true,
        trustedAutoCommitEligible,
        source: fromTemplate ? "user_template" : "backend_estimate",
        nutrition,
        items,
      }),
    );
    markPhase("create_proposal", proposalStarted);

    let autoCommittedMeal: Meal | null = null;
    if (trustedAutoCommitEligible) {
      const autoCommitStarted = Date.now();
      autoCommittedMeal = await this.repository.createMealFromProposal(
        context.actorUserId,
        proposal,
        parsed.occurredAt ?? new Date().toISOString(),
      );
      markPhase("trusted_auto_commit_create_meal", autoCommitStarted);
      const auditStarted = Date.now();
      await this.repository.recordAuditEvent({
        userId: context.actorUserId,
        eventType: "trusted_auto_commit.meal_committed",
        metadata: {
          proposalId: proposal.id,
          mealId: autoCommittedMeal.id,
          phrase: parsed.text,
          confidence: memory!.confidence,
        },
        traceId: context.traceId,
      });
      markPhase("trusted_auto_commit_audit", auditStarted);
      const feedbackStarted = Date.now();
      await recordFoodFeedback(this.repository, {
        userId: context.actorUserId,
        eventType: "proposal_committed",
        traceId: context.traceId,
        source: context.source,
        phrase: parsed.text,
        proposalId: proposal.id,
        mealId: autoCommittedMeal.id,
        items: autoCommittedMeal.items,
        previousItems: proposal.items,
        metadata: { trustedAutoCommit: true },
      });
      markPhase("trusted_auto_commit_feedback", feedbackStarted);
    }

    return {
      proposal,
      autoCommittedMeal,
      options: resolution?.candidateGroups ?? [],
      candidateGroups: resolution?.candidateGroups ?? [],
      instrumentation: {
        action: "propose_meal_log",
        path: autoCommittedMeal
          ? "trusted_auto_committed"
          : fromTemplate
            ? "template_proposal"
            : "resolved_proposal",
        inputMode,
        usedTemplate: Boolean(template),
        fromTemplate,
        memoryMatches: memories.length,
        topMemoryConfidence: memory?.confidence,
        itemCount: items.length,
        candidateGroups: resolution?.candidateGroups.length ?? 0,
        phasesMs: phases,
        totalMs: Date.now() - started,
      },
    };
  }

  private async createMealProposalFromItems(
    input: unknown,
    context: ActionContext,
  ): Promise<Record<string, unknown>> {
    const parsed = createMealProposalFromItemsInputSchema.parse(input);
    const proposal = await this.repository.createProposal(context.actorUserId, {
      phrase: parsed.phrase,
      title: parsed.title ?? inferTitle(parsed.phrase, parsed.items),
      status: "pending",
      confidence: Math.min(
        ...parsed.items.map((item) => item.confidence ?? 0.78),
        0.9,
      ),
      requiresConfirmation: true,
      trustedAutoCommitEligible: false,
      source: "backend_estimate",
      nutrition: sumNutrition(parsed.items),
      items: parsed.items,
    });
    await recordFoodFeedback(this.repository, {
      userId: context.actorUserId,
      eventType: "selected_for_proposal",
      traceId: context.traceId,
      source: context.source,
      phrase: parsed.phrase,
      proposalId: proposal.id,
      items: parsed.items,
      metadata: { explicitSelection: true },
    });
    return { proposal };
  }

  private async resolveMealText(userId: string, text: string, locale?: string) {
    if (hasMealTextResolution(this.nutritionProvider)) {
      return this.nutritionProvider.resolveMealText(userId, text, locale);
    }
    return {
      items: await this.nutritionProvider.estimateMeal(userId, text),
      unresolvedMentions: [],
      candidateGroups: [],
      clarificationRequired: false,
    };
  }

  private async resolveMealMentions(userId: string, mentions: FoodMention[], locale?: string) {
    if (hasMealTextResolution(this.nutritionProvider)) {
      return this.nutritionProvider.resolveMealMentions(userId, mentions, locale);
    }
    return {
      items: [],
      unresolvedMentions: mentions,
      candidateGroups: mentions.map((mention) => ({
        mention,
        candidates: [],
        reason: "no_resolution_provider",
      })),
      clarificationRequired: true,
    };
  }

  private async correctMeal(input: unknown, context: ActionContext) {
    const parsed = correctMealInputSchema.parse(input);
    if (parsed.proposalId) {
      const proposal = await this.requireProposal(
        context.actorUserId,
        parsed.proposalId,
      );
      const corrected = await this.repository.updateProposal(
        context.actorUserId,
        {
          ...proposal,
          status: "corrected",
          items: parsed.items,
          nutrition: sumNutrition(parsed.items),
        },
      );
      await recordFoodFeedback(this.repository, {
        userId: context.actorUserId,
        eventType: "proposal_corrected",
        traceId: context.traceId,
        source: context.source,
        phrase: proposal.phrase,
        proposalId: corrected.id,
        items: corrected.items,
        previousItems: proposal.items,
      });
      return { proposal: corrected };
    }

    const meal = await this.repository.getMeal(
      context.actorUserId,
      parsed.mealId!,
    );
    if (!meal) throw new ActionExecutionError("meal_not_found");
    const corrected = await this.repository.updateMeal(context.actorUserId, {
      ...meal,
      items: parsed.items,
      nutrition: sumNutrition(parsed.items),
    });
    await recordFoodFeedback(this.repository, {
      userId: context.actorUserId,
      eventType: "meal_corrected",
      traceId: context.traceId,
      source: context.source,
      mealId: corrected.id,
      items: corrected.items,
      previousItems: meal.items,
    });
    return { meal: corrected };
  }

  async getProposalForAgentContext(
    userId: string,
    proposalId: string,
  ): Promise<MealProposal | undefined> {
    return this.repository.getProposal(userId, proposalId);
  }

  private async reviseMealProposal(input: unknown, context: ActionContext) {
    const parsed = reviseMealProposalInputSchema.parse(input);
    const proposal = await this.requireProposal(
      context.actorUserId,
      parsed.proposalId,
    );
    if (proposal.status === "committed") {
      throw new ActionExecutionError("proposal_already_committed");
    }
    if (proposal.status === "rejected") {
      throw new ActionExecutionError("proposal_not_editable");
    }

    const items = [...proposal.items];
    for (const operation of parsed.operations) {
      switch (operation.type) {
        case "add_item": {
          const resolved = await this.resolveRevisionMention(
            context.actorUserId,
            operation.mention,
            context.locale,
          );
          if ("clarificationRequired" in resolved) return resolved;
          items.push(...resolved.items);
          break;
        }
        case "remove_item": {
          const index = findProposalItemIndex(items, operation);
          if (index < 0) {
            throw new ActionExecutionError("proposal_item_not_found");
          }
          items.splice(index, 1);
          break;
        }
        case "replace_item": {
          const index = findProposalItemIndex(items, operation);
          if (index < 0) {
            throw new ActionExecutionError("proposal_item_not_found");
          }
          const resolved = await this.resolveRevisionMention(
            context.actorUserId,
            operation.mention,
            context.locale,
          );
          if ("clarificationRequired" in resolved) return resolved;
          items.splice(index, 1, ...resolved.items);
          break;
        }
        case "update_item_quantity": {
          const index = findProposalItemIndex(items, operation);
          if (index < 0) {
            throw new ActionExecutionError("proposal_item_not_found");
          }
          const current = items[index]!;
          if (sameUnit(current.unit, operation.unit)) {
            items[index] = scaleMealItem(
              current,
              operation.quantity,
              operation.unit,
            );
            break;
          }
          const foodName = current.canonicalName ?? current.name;
          const resolved = await this.resolveRevisionMention(
            context.actorUserId,
            {
              originalText:
                `${operation.quantity} ${operation.rawUnitText ?? operation.unit} ${foodName}`.trim(),
              canonicalEnglishName: foodName,
              quantity: operation.quantity,
              unit: operation.unit,
              rawUnitText: operation.rawUnitText ?? operation.unit,
              unitKind: operation.unit === "g" ? "metric" : "unknown",
              confidence: current.confidence ?? 0.8,
              marketProduct: false,
            },
            context.locale,
          );
          if ("clarificationRequired" in resolved) return resolved;
          items.splice(index, 1, ...resolved.items);
          break;
        }
      }
    }

    if (items.length === 0) {
      throw new ActionExecutionError("proposal_empty");
    }

    const corrected = await this.repository.updateProposal(
      context.actorUserId,
      {
        ...proposal,
        status: "corrected",
        title: inferTitle(proposal.phrase, items),
        items,
        nutrition: sumNutrition(items),
      },
    );
    await recordFoodFeedback(this.repository, {
      userId: context.actorUserId,
      eventType: "proposal_corrected",
      traceId: context.traceId,
      source: context.source,
      phrase: parsed.instruction,
      proposalId: corrected.id,
      items: corrected.items,
      previousItems: proposal.items,
      metadata: { revisionOperationCount: parsed.operations.length },
    });
    return {
      proposal: corrected,
      message: "Meal proposal updated.",
    };
  }

  private async resolveRevisionMention(
    userId: string,
    mention: FoodMention,
    locale?: string,
  ) {
    const resolution = await this.resolveMealMentions(userId, [mention], locale);
    if (resolution.clarificationRequired || resolution.items.length === 0) {
      return {
        clarificationRequired: true,
        resolvedItems: resolution.items,
        unresolvedMentions: resolution.unresolvedMentions,
        options: resolution.candidateGroups,
        message:
          unsupportedUnitClarification(resolution.candidateGroups) ??
          "I need a food match before updating the meal proposal.",
      };
    }
    return { items: resolution.items };
  }

  private async requireProposal(
    userId: string,
    proposalId: string,
  ): Promise<MealProposal> {
    const proposal = await this.repository.getProposal(userId, proposalId);
    if (!proposal) throw new ActionExecutionError("proposal_not_found");
    return proposal;
  }

  private async queryMemory(userId: string, text: string) {
    if (this.memoryRetrievalService) {
      return withSpan(
        "MemoryRetrievalService.query",
        undefined,
        () => this.memoryRetrievalService!.query(userId, text),
      );
    }
    return {
      matches: await withSpan(
        "Repository.queryMemory",
        undefined,
        () => this.repository.queryMemory(userId, normalizeText(text)),
      ),
      vectorUnavailable: true,
    };
  }
}

function hasMealTextResolution(
  provider: NutritionProvider,
): provider is MealTextResolutionProvider {
  return (
    typeof (provider as Partial<MealTextResolutionProvider>).resolveMealText ===
    "function"
  );
}

function normalizeNutritionSearchResult(
  result: MealItem[] | NutritionSearchResult,
): { items: MealItem[]; candidateGroups: FoodCandidateGroup[] } {
  if (Array.isArray(result)) {
    return {
      items: result,
      candidateGroups: [],
    };
  }
  return {
    items: result.items,
    candidateGroups: result.candidateGroups ?? result.candidates ?? [],
  };
}

async function recordFoodFeedback(
  repository: AppRepository,
  input: FoodFeedbackInput,
): Promise<void> {
  const action = foodFeedbackActionForEvent(input.eventType);
  await withSpan(
    "Repository.recordFoodFeedback.batch",
    { itemCount: input.items.length, eventType: input.eventType },
    () => Promise.all(
      input.items.map((item) => {
        const record = foodFeedbackRecordForItem(input, item, action);
        return record ? repository.recordFoodFeedback(record) : Promise.resolve();
      }),
    ),
  );
}

function foodFeedbackActionForEvent(
  eventType: FoodFeedbackEventType,
): FoodFeedbackAction {
  switch (eventType) {
    case "selected_for_proposal":
      return "selected";
    case "proposal_committed":
      return "logged";
    case "proposal_corrected":
    case "meal_corrected":
      return "corrected";
  }
}

function foodFeedbackRecordForItem(
  input: FoodFeedbackInput,
  item: MealItem,
  action: FoodFeedbackAction,
): FoodFeedbackRecord | undefined {
  return {
    userId: input.userId,
    externalSource: item.externalSource,
    externalId: item.externalId,
    query: item.originalText ?? item.canonicalName ?? input.phrase ?? item.name,
    action,
    metadata: {
      ...input.metadata,
      eventType: input.eventType,
      traceId: input.traceId,
      source: input.source,
      proposalId: input.proposalId,
      mealId: input.mealId,
      itemName: item.name,
      confidence: item.confidence,
    },
  };
}

function unsupportedUnitClarification(
  candidateGroups: FoodCandidateGroup[],
): string | undefined {
  const group = candidateGroups.find(
    (candidateGroup) =>
      candidateGroup.reason === "unsupported_unit" ||
      candidateGroup.reason === "ambiguous_portion",
  );
  if (!group) return undefined;
  const mention = group.mention;
  const canonicalName = canonicalNameForMention(mention);
  if (group.reason === "ambiguous_portion") {
    return `Which ${canonicalName} portion did you mean?`;
  }
  const unit = mention.rawUnitText ?? mention.unit;
  const unitAlreadyNamesFood =
    normalizeText(unit) === normalizeText(canonicalName);
  const phrase =
    `${mention.quantity} ${unit}${unitAlreadyNamesFood ? "" : ` ${canonicalName}`}`
      .replace(/\s+/g, " ")
      .trim();
  const alternatives = group.portionOptions?.length
    ? " Choose one of the supported portions or use grams."
    : "";
  return `I could not validate "${phrase}" as a supported portion.${
    alternatives ||
    ` Please use grams, cups, or another serving size for ${canonicalName}.`
  }`;
}

function canonicalNameForMention(mention: FoodMention): string {
  return normalizeText(
    mention.canonicalName ??
      mention.canonicalEnglishName ??
      mention.originalText,
  );
}

function findProposalItemIndex(
  items: MealItem[],
  target: { itemIndex?: number; matchText?: string },
): number {
  if (
    target.itemIndex !== undefined &&
    target.itemIndex >= 0 &&
    target.itemIndex < items.length
  ) {
    return target.itemIndex;
  }
  const normalizedMatch = normalizeText(target.matchText ?? "");
  if (!normalizedMatch) return -1;
  return items.findIndex((item) => {
    const names = [item.name, item.canonicalName, item.originalText]
      .filter((value): value is string => Boolean(value))
      .map(normalizeText);
    return names.some(
      (name) =>
        name === normalizedMatch ||
        name.includes(normalizedMatch) ||
        normalizedMatch.includes(name),
    );
  });
}

function sameUnit(left: string, right: string): boolean {
  return normalizeText(left) === normalizeText(right);
}

function scaleMealItem(
  item: MealItem,
  quantity: number,
  unit: string,
): MealItem {
  const ratio = quantity / item.quantity;
  return {
    ...item,
    quantity,
    unit,
    calories: Math.round(item.calories * ratio),
    proteinGrams: roundOne(item.proteinGrams * ratio),
    carbsGrams: roundOne(item.carbsGrams * ratio),
    fatGrams: roundOne(item.fatGrams * ratio),
    resolvedGrams:
      item.resolvedGrams === undefined
        ? undefined
        : roundOne(item.resolvedGrams * ratio),
    source: item.source.endsWith(":manual_edit")
      ? item.source
      : `${item.source}:manual_edit`,
  };
}

function roundOne(value: number): number {
  return Math.round(value * 10) / 10;
}

function inferTitle(text: string, items: MealItem[]): string {
  if (items.length === 1) return items[0]!.name;
  if (
    normalizeText(text).includes("chicken") &&
    normalizeText(text).includes("rice")
  )
    return "Chicken and rice";
  if (items.length === 2) return `${items[0]!.name} and ${items[1]!.name}`;
  return "Meal";
}

const fixedMealLabels: Record<Exclude<MealLabel["type"], "other">, string> = {
  breakfast: "Breakfast",
  lunch: "Lunch",
  dinner: "Dinner",
  snack: "Snack",
  pre_workout: "Pre-workout",
  post_workout: "Post-workout",
};

function normalizeMealLabel(
  input: { type: MealLabel["type"]; label?: string } | null | undefined,
): MealLabel | null {
  if (!input) return null;
  if (input.type === "other") {
    const label = input.label?.trim();
    if (!label) {
      throw new ActionExecutionError(
        "invalid_meal_label",
        "Other meal labels require a custom label.",
      );
    }
    return { type: "other", label };
  }
  return { type: input.type, label: fixedMealLabels[input.type] };
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}
