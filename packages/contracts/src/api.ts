import { z } from "zod";
import {
  calorieTargetSourceSchema,
  dailyGoalsSchema,
  dailySummarySchema,
  draftUsualFoodInputSchema,
  draftUsualFoodOutputSchema,
  draftUsualMealInputSchema,
  draftUsualMealOutputSchema,
  foodCandidateSchema,
  isoDateTimeSchema,
  macroModeSchema,
  macroPresetSchema,
  macroSourceSchema,
  mealItemSchema,
  mealProposalSchema,
  mealSchema,
  mealTemplateSchema,
  nutritionSnapshotSchema,
  quarterLiterSchema,
  usualFoodSchema,
  uuidSchema,
} from "./common.js";

export const errorResponseSchema = z.object({
  error: z.object({
    code: z.string(),
    message: z.string(),
    traceId: z.string().optional(),
    details: z.unknown().optional(),
  }),
});

export const executeActionRequestSchema = z.object({
  input: z.unknown().default({}),
  source: z
    .enum([
      "flutter",
      "internal_agent",
      "android_appfunctions",
      "ios_appintents",
      "rest",
    ])
    .default("rest"),
});

export const executeActionResponseSchema = z.object({
  actionCallId: uuidSchema,
  confirmationRequired: z.boolean(),
  output: z.unknown(),
});

export const agentRunRequestSchema = z.object({
  text: z.string().min(1),
  source: z
    .enum(["flutter", "ios_appintents", "android_appfunctions"])
    .default("flutter"),
  activeProposalId: uuidSchema.optional(),
});

export const agentChatRequestSchema = z
  .object({
    message: z.string().trim().min(1),
    source: z
      .enum(["flutter", "ios_appintents", "android_appfunctions"])
      .default("flutter"),
    conversationId: uuidSchema.optional(),
    activeProposalId: uuidSchema.optional(),
  });

export const agentConversationSummarySchema = z.object({
  id: uuidSchema,
  userId: uuidSchema.optional(),
  title: z.string(),
  hiddenFromUserAt: isoDateTimeSchema.nullable().optional(),
  createdAt: isoDateTimeSchema,
  updatedAt: isoDateTimeSchema,
});

export const agentConversationMessageSchema = z.object({
  id: uuidSchema,
  conversationId: uuidSchema,
  userId: uuidSchema.optional(),
  role: z.enum(["user", "assistant", "tool"]),
  content: z.string(),
  toolCalls: z.unknown().optional(),
  toolCallId: z.string().nullable().optional(),
  traceId: z.string().nullable().optional(),
  turnId: uuidSchema.nullable().optional(),
  inputMode: z.string().nullable().optional(),
  source: z.string().nullable().optional(),
  activeProposalId: uuidSchema.nullable().optional(),
  metadata: z.unknown().optional(),
  createdAt: isoDateTimeSchema,
});

export const agentConversationsResponseSchema = z.object({
  conversations: z.array(agentConversationSummarySchema),
});

export const agentConversationDetailResponseSchema = z.object({
  conversation: agentConversationSummarySchema,
  messages: z.array(agentConversationMessageSchema),
});

export const deleteAgentConversationResponseSchema = z.object({
  ok: z.boolean(),
  deleted: z.boolean().optional(),
  hidden: z.boolean().optional(),
});

export const agentRunResponseSchema = z.object({
  kind: z.enum([
    "proposal",
    "meal_committed",
    "meal_corrected",
    "summary",
    "remaining_targets",
    "history",
    "food_memory",
    "nutrition_search",
    "templates",
    "template_saved",
    "template_deleted",
    "usual_food_draft",
    "usual_meal_draft",
    "confirmation_required",
    "meal_deleted",
    "clarification_required",
  ]),
  message: z.string(),
  proposal: mealProposalSchema.optional(),
  meal: mealSchema.optional(),
  summary: dailySummarySchema.optional(),
  remaining: nutritionSnapshotSchema.optional(),
  meals: z.array(mealSchema).optional(),
  items: z.array(mealItemSchema).optional(),
  templates: z.array(mealTemplateSchema).optional(),
  template: mealTemplateSchema.optional(),
  usualFoodDraft: draftUsualFoodOutputSchema.optional(),
  usualMealDraft: draftUsualMealOutputSchema.optional(),
  matches: z.array(z.unknown()).optional(),
  deleted: z.boolean().optional(),
  actionId: z.string().optional(),
  input: z.unknown().optional(),
  options: z.array(z.union([foodCandidateSchema, z.unknown()])).optional(),
  candidateGroups: z
    .array(z.union([foodCandidateSchema, z.unknown()]))
    .optional(),
});

export const transcriptionResponseSchema = z.object({
  transcript: z.string(),
  provider: z.string(),
  model: z.string(),
  traceId: z.string(),
});

export const voiceMealRunResponseSchema = z.object({
  transcript: z.string(),
  provider: z.string(),
  model: z.string(),
  traceId: z.string(),
  result: agentRunResponseSchema,
});

export const foodSearchRequestSchema = z.object({
  query: z.string().trim().min(1),
  barcode: z.string().trim().min(1).optional(),
  limit: z.number().int().min(1).max(25).default(10),
});

export const foodSearchResponseSchema = z.object({
  items: z.array(mealItemSchema),
  candidateGroups: z.array(foodCandidateSchema).optional(),
});

const optionalNullableTrimmedStringSchema = z.preprocess(
  (value) => (typeof value === "string" && value.trim() === "" ? null : value),
  z.string().trim().min(1).nullable().optional(),
);

const aliasesSchema = z.preprocess(
  (value) =>
    Array.isArray(value)
      ? value.filter(
          (alias) => typeof alias !== "string" || alias.trim() !== "",
        )
      : value,
  z.array(z.string().trim().min(1)).default([]),
);

const usualFoodMutationBaseSchema = z.object({
  name: z.string().trim().min(1),
  canonicalName: optionalNullableTrimmedStringSchema,
  brand: optionalNullableTrimmedStringSchema,
  barcode: optionalNullableTrimmedStringSchema,
  servingGrams: z.number().positive(),
  nutrition: nutritionSnapshotSchema,
  nutrients: z.record(z.unknown()).optional(),
  aliases: aliasesSchema,
});

export const createUsualFoodRequestSchema = usualFoodMutationBaseSchema;

export const updateUsualFoodRequestSchema = usualFoodMutationBaseSchema
  .partial()
  .refine(
    (value) => Object.keys(value).length > 0,
    "at least one field is required",
  );

export const usualFoodResponseSchema = z.object({
  usualFood: usualFoodSchema,
});

export const usualFoodsResponseSchema = z.object({
  usualFoods: z.array(usualFoodSchema),
});

export const settingsUpdateSchema = z.object({
  trustedModeEnabled: z.boolean().optional(),
});

export const goalsUpdateSchema = z
  .object({
    date: z.string().optional(),
    calories: z.number().int().min(800).max(10000).optional(),
    hydrationGoalLiters: quarterLiterSchema.optional(),
    calorieTargetSource: calorieTargetSourceSchema.optional(),
    macroMode: macroModeSchema.optional(),
    macroSource: macroSourceSchema.optional(),
    macroPreset: macroPresetSchema.nullable().optional(),
    proteinPct: z.number().int().min(0).max(100).optional(),
    carbsPct: z.number().int().min(0).max(100).optional(),
    fatPct: z.number().int().min(0).max(100).optional(),
    proteinGrams: z.number().nonnegative().max(2000).optional(),
    carbsGrams: z.number().nonnegative().max(2000).optional(),
    fatGrams: z.number().nonnegative().max(2000).optional(),
    macroCalories: z.number().int().nonnegative().optional(),
    calorieDeltaKcal: z.number().int().optional(),
  })
  .superRefine((value, ctx) => {
    const hasMacroField =
      value.macroMode !== undefined ||
      value.macroSource !== undefined ||
      value.macroPreset !== undefined ||
      value.proteinPct !== undefined ||
      value.carbsPct !== undefined ||
      value.fatPct !== undefined ||
      value.proteinGrams !== undefined ||
      value.carbsGrams !== undefined ||
      value.fatGrams !== undefined ||
      value.macroCalories !== undefined ||
      value.calorieDeltaKcal !== undefined;
    if (
      value.calories === undefined &&
      value.hydrationGoalLiters === undefined &&
      !hasMacroField
    ) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        message: "calories, hydrationGoalLiters, or macro fields are required",
      });
    }
    if (!hasMacroField) return;
    if (value.macroMode === undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["macroMode"],
        message: "macroMode is required when macro fields are provided",
      });
      return;
    }
    if (value.macroMode === "percentage") {
      if (
        value.proteinPct === undefined ||
        value.carbsPct === undefined ||
        value.fatPct === undefined
      ) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["proteinPct"],
          message:
            "proteinPct, carbsPct, and fatPct are required in percentage mode",
        });
        return;
      }
      const total = value.proteinPct + value.carbsPct + value.fatPct;
      if (total !== 100) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["proteinPct"],
          message: "macro percentages must total 100",
        });
      }
    }
    if (value.macroMode === "grams") {
      if (
        value.proteinGrams === undefined ||
        value.carbsGrams === undefined ||
        value.fatGrams === undefined
      ) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: ["proteinGrams"],
          message:
            "proteinGrams, carbsGrams, and fatGrams are required in grams mode",
        });
      }
    }
  });

export const dailyHydrationUpdateSchema = z.object({
  date: z.string().optional(),
  waterConsumedLiters: quarterLiterSchema,
});

export const dailyHydrationResponseSchema = z.object({
  summary: dailySummarySchema,
});

export const calorieEstimateRequestSchema = z.object({
  age: z.number().int().min(18).max(100),
  sex: z.enum(["male", "female"]),
  heightCm: z.number().min(120).max(230),
  weightKg: z.number().min(35).max(250),
  activityLevel: z.enum([
    "sedentary",
    "lightly_active",
    "moderately_active",
    "very_active",
    "extra_active",
  ]),
  goal: z.enum(["lose_fat", "maintain", "gain_muscle"]),
  pace: z
    .enum(["slow", "moderate", "aggressive", "lean", "standard"])
    .optional(),
});

export const calorieEstimateResponseSchema = z.object({
  bmr: z.number().int().positive(),
  maintenanceCalories: z.number().int().positive(),
  targetCalories: z.number().int().min(800).max(10000),
  recommendedRange: z.object({
    min: z.number().int().min(800).max(10000),
    max: z.number().int().min(800).max(10000),
  }),
  activityFactor: z.number().positive(),
  adjustmentCalories: z.number().int(),
  warnings: z.array(z.string()),
  explanation: z.string(),
});

export const goalsResponseSchema = z.object({
  goals: dailyGoalsSchema,
  summary: dailySummarySchema.optional(),
});

export type CalorieEstimateRequest = z.infer<
  typeof calorieEstimateRequestSchema
>;
export type CalorieEstimateResponse = z.infer<
  typeof calorieEstimateResponseSchema
>;
export type CreateUsualFoodRequest = z.infer<
  typeof createUsualFoodRequestSchema
>;
export type UpdateUsualFoodRequest = z.infer<
  typeof updateUsualFoodRequestSchema
>;
export type AgentConversationSummary = z.infer<
  typeof agentConversationSummarySchema
>;
export type AgentConversationMessage = z.infer<
  typeof agentConversationMessageSchema
>;
export type AgentConversationsResponse = z.infer<
  typeof agentConversationsResponseSchema
>;
export type AgentConversationDetailResponse = z.infer<
  typeof agentConversationDetailResponseSchema
>;
export type DeleteAgentConversationResponse = z.infer<
  typeof deleteAgentConversationResponseSchema
>;

export const dashboardResponseSchema = z.object({
  summary: dailySummarySchema,
});

export const mealHistoryResponseSchema = z.object({
  meals: z.array(mealSchema),
});

export const templatesResponseSchema = z.object({
  templates: z.array(mealTemplateSchema),
});

export const usualFoodDraftRequestSchema = draftUsualFoodInputSchema;
export const usualFoodDraftResponseSchema = draftUsualFoodOutputSchema;
export const usualMealDraftRequestSchema = draftUsualMealInputSchema;
export const usualMealDraftResponseSchema = draftUsualMealOutputSchema;

export const telemetrySurfaceSchema = z.enum([
  "backend",
  "mobile",
  "agent",
  "stt",
  "db",
  "admin"
]);

export const clientTelemetrySurfaceSchema = z.enum(["mobile"]);

export const telemetrySeveritySchema = z.enum(["info", "warning", "error"]);

export const telemetryStatusSchema = z.enum([
  "success",
  "failure",
  "partial",
  "abandoned"
]);

export const clientTelemetryEventInputSchema = z.object({
  eventType: z.string().trim().min(1).max(120).regex(/^mobile\./),
  flow: z.string().trim().max(120).optional(),
  surface: clientTelemetrySurfaceSchema.default("mobile"),
  severity: telemetrySeveritySchema.default("info"),
  status: telemetryStatusSchema.optional(),
  traceId: z.string().trim().max(120).optional(),
  sessionId: z.string().trim().max(120).optional(),
  route: z.string().trim().max(255).optional(),
  method: z.string().trim().max(20).optional(),
  actionId: z.string().trim().max(120).optional(),
  durationMs: z.number().int().nonnegative().optional(),
  errorCode: z.string().trim().max(120).optional(),
  errorMessage: z.string().trim().max(2000).optional(),
  appVersion: z.string().trim().max(60).optional(),
  appBuild: z.string().trim().max(60).optional(),
  platform: z.string().trim().max(60).optional(),
  locale: z.string().trim().max(40).optional(),
  metadata: z.record(z.unknown()).optional()
});

export const clientTelemetryIngestRequestSchema = z.object({
  events: z.array(clientTelemetryEventInputSchema).min(1).max(50)
});

export const clientTelemetryIngestResponseSchema = z.object({
  accepted: z.number().int().nonnegative()
});

export const telemetryEventSummarySchema = z.object({
  id: uuidSchema,
  traceId: z.string(),
  userId: uuidSchema.nullable().optional(),
  sessionId: z.string().nullable().optional(),
  eventType: z.string(),
  flow: z.string().nullable().optional(),
  surface: telemetrySurfaceSchema,
  severity: telemetrySeveritySchema,
  status: telemetryStatusSchema.nullable().optional(),
  route: z.string().nullable().optional(),
  method: z.string().nullable().optional(),
  actionId: z.string().nullable().optional(),
  durationMs: z.number().nullable().optional(),
  errorCode: z.string().nullable().optional(),
  errorMessage: z.string().nullable().optional(),
  appVersion: z.string().nullable().optional(),
  appBuild: z.string().nullable().optional(),
  platform: z.string().nullable().optional(),
  locale: z.string().nullable().optional(),
  metadata: z.record(z.unknown()),
  createdAt: isoDateTimeSchema
});

export const llmRunSummarySchema = z.object({
  id: uuidSchema,
  traceId: z.string(),
  userId: uuidSchema.nullable().optional(),
  source: z.string().nullable().optional(),
  locale: z.string().nullable().optional(),
  timezone: z.string().nullable().optional(),
  conversationId: uuidSchema.nullable().optional(),
  turnId: uuidSchema.nullable().optional(),
  provider: z.string().nullable().optional(),
  providerRequestId: z.string().nullable().optional(),
  providerGenerationId: z.string().nullable().optional(),
  model: z.string(),
  inputMode: z.string().nullable().optional(),
  activeProposalId: uuidSchema.nullable().optional(),
  decisionSource: z.string().nullable().optional(),
  selectedTool: z.string().nullable().optional(),
  executedTool: z.string().nullable().optional(),
  resultKind: z.string().nullable().optional(),
  actionCallId: uuidSchema.nullable().optional(),
  promptChars: z.number().int().nullable().optional(),
  toolsJsonChars: z.number().int().nullable().optional(),
  messagesJsonChars: z.number().int().nullable().optional(),
  requestPayloadChars: z.number().int().nullable().optional(),
  promptTokens: z.number().int().nullable().optional(),
  completionTokens: z.number().int().nullable().optional(),
  totalTokens: z.number().int().nullable().optional(),
  reasoningTokens: z.number().int().nullable().optional(),
  firstByteMs: z.number().int().nullable().optional(),
  firstToolCallMs: z.number().int().nullable().optional(),
  largestStreamGapMs: z.number().int().nullable().optional(),
  llmMs: z.number().int().nullable().optional(),
  actionMs: z.number().int().nullable().optional(),
  totalMs: z.number().int().nullable().optional(),
  emptyToolCall: z.boolean(),
  invalidToolArguments: z.boolean(),
  providerError: z.boolean(),
  providerCostAmount: z.number().nullable().optional(),
  estimatedCostAmount: z.number().nullable().optional(),
  costCurrency: z.string().nullable().optional(),
  costSource: z.string().nullable().optional(),
  pricingSnapshot: z.record(z.unknown()).optional(),
  metadata: z.record(z.unknown()),
  createdAt: isoDateTimeSchema
});

export const foodSearchEventSummarySchema = z.object({
  id: uuidSchema,
  traceId: z.string(),
  userId: uuidSchema.nullable().optional(),
  queryText: z.string().nullable().optional(),
  queryHash: z.string().nullable().optional(),
  queryLength: z.number().int(),
  locale: z.string().nullable().optional(),
  barcodePresent: z.boolean(),
  normalizedSearchEnabled: z.boolean().nullable().optional(),
  normalizedScope: z.string().nullable().optional(),
  path: z.string().nullable().optional(),
  resultCount: z.number().int(),
  candidateGroupCount: z.number().int().nullable().optional(),
  topScore: z.number().nullable().optional(),
  topExternalSource: z.string().nullable().optional(),
  topResultType: z.string().nullable().optional(),
  zeroResults: z.boolean(),
  lowConfidence: z.boolean(),
  selectedRank: z.number().int().nullable().optional(),
  durationMs: z.number().int().nullable().optional(),
  metadata: z.record(z.unknown()),
  createdAt: isoDateTimeSchema
});

export const telemetryEventsResponseSchema = z.object({
  events: z.array(telemetryEventSummarySchema)
});

export const adminAgentTurnSummarySchema = z.object({
  id: uuidSchema,
  conversationId: uuidSchema.nullable().optional(),
  traceId: z.string(),
  turnId: uuidSchema,
  userId: uuidSchema.nullable().optional(),
  inputMode: z.string().nullable().optional(),
  source: z.string().nullable().optional(),
  activeProposalId: uuidSchema.nullable().optional(),
  model: z.string().nullable().optional(),
  inputText: z.string().nullable().optional(),
  assistantText: z.string().nullable().optional(),
  resultKind: z.string().nullable().optional(),
  stopReason: z.string().nullable().optional(),
  iterationCount: z.number().int(),
  toolCallCount: z.number().int(),
  promptTokens: z.number().int().nullable().optional(),
  completionTokens: z.number().int().nullable().optional(),
  totalTokens: z.number().int().nullable().optional(),
  reasoningTokens: z.number().int().nullable().optional(),
  providerCostAmount: z.number().nullable().optional(),
  estimatedCostAmount: z.number().nullable().optional(),
  costCurrency: z.string().nullable().optional(),
  costSource: z.string().nullable().optional(),
  firstByteMs: z.number().int().nullable().optional(),
  firstToolCallMs: z.number().int().nullable().optional(),
  largestStreamGapMs: z.number().int().nullable().optional(),
  llmMs: z.number().int().nullable().optional(),
  actionMs: z.number().int().nullable().optional(),
  totalMs: z.number().int().nullable().optional(),
  status: z.string(),
  errorCode: z.string().nullable().optional(),
  errorMessage: z.string().nullable().optional(),
  metadata: z.record(z.unknown()),
  completedAt: isoDateTimeSchema.nullable().optional(),
  createdAt: isoDateTimeSchema
});

export const adminAgentToolCallSummarySchema = z.object({
  id: uuidSchema,
  agentTurnId: uuidSchema.nullable().optional(),
  conversationId: uuidSchema.nullable().optional(),
  traceId: z.string(),
  turnId: uuidSchema.nullable().optional(),
  userId: uuidSchema.nullable().optional(),
  toolCallId: z.string().nullable().optional(),
  actionCallId: uuidSchema.nullable().optional(),
  actionId: z.string(),
  arguments: z.unknown().optional(),
  resultSummary: z.unknown().optional(),
  status: z.string(),
  errorMessage: z.string().nullable().optional(),
  startedAt: isoDateTimeSchema,
  completedAt: isoDateTimeSchema.nullable().optional(),
  durationMs: z.number().int().nullable().optional(),
  metadata: z.record(z.unknown()),
  createdAt: isoDateTimeSchema
});

export const adminActionCallSummarySchema = z.object({
  id: uuidSchema,
  userId: uuidSchema,
  actionId: z.string(),
  source: z.string(),
  input: z.unknown(),
  output: z.unknown().optional(),
  error: z.unknown().optional(),
  confirmationStatus: z.string(),
  traceId: z.string(),
  latencyMs: z.number().int(),
  createdAt: isoDateTimeSchema
});

export const adminLlmProviderCallSummarySchema = z.object({
  id: uuidSchema,
  traceId: z.string(),
  userId: uuidSchema.nullable().optional(),
  conversationId: uuidSchema.nullable().optional(),
  agentTurnId: uuidSchema.nullable().optional(),
  turnId: uuidSchema.nullable().optional(),
  actionCallId: uuidSchema.nullable().optional(),
  featureSurface: z.string(),
  provider: z.string(),
  providerRequestId: z.string().nullable().optional(),
  providerGenerationId: z.string().nullable().optional(),
  requestedModel: z.string(),
  servedModel: z.string().nullable().optional(),
  routing: z.unknown().optional(),
  inputMode: z.string().nullable().optional(),
  promptTokens: z.number().int().nullable().optional(),
  completionTokens: z.number().int().nullable().optional(),
  totalTokens: z.number().int().nullable().optional(),
  reasoningTokens: z.number().int().nullable().optional(),
  providerCostAmount: z.number().nullable().optional(),
  estimatedCostAmount: z.number().nullable().optional(),
  costCurrency: z.string().nullable().optional(),
  costSource: z.string(),
  pricingSource: z.string().nullable().optional(),
  pricingVersion: z.string().nullable().optional(),
  status: z.string(),
  errorCode: z.string().nullable().optional(),
  errorMessage: z.string().nullable().optional(),
  durationMs: z.number().int().nullable().optional(),
  metadata: z.record(z.unknown()),
  createdAt: isoDateTimeSchema
});

export const adminTranscriptionSummarySchema = z.object({
  id: uuidSchema,
  traceId: z.string(),
  userId: uuidSchema.nullable().optional(),
  conversationId: uuidSchema.nullable().optional(),
  turnId: uuidSchema.nullable().optional(),
  surface: z.string(),
  provider: z.string().nullable().optional(),
  model: z.string().nullable().optional(),
  language: z.string().nullable().optional(),
  audioMimeType: z.string().nullable().optional(),
  audioBytes: z.number().int().nullable().optional(),
  audioDurationMs: z.number().int().nullable().optional(),
  transcriptText: z.string().nullable().optional(),
  transcriptLength: z.number().int(),
  durationMs: z.number().int().nullable().optional(),
  status: z.string(),
  errorCode: z.string().nullable().optional(),
  errorMessage: z.string().nullable().optional(),
  downstreamResultKind: z.string().nullable().optional(),
  metadata: z.record(z.unknown()),
  createdAt: isoDateTimeSchema
});

export const adminAgentConversationsResponseSchema = z.object({
  conversations: z.array(agentConversationSummarySchema)
});

export const adminAgentConversationDetailResponseSchema = z.object({
  conversation: agentConversationSummarySchema,
  messages: z.array(agentConversationMessageSchema)
});

export const adminActionCallsResponseSchema = z.object({
  actionCalls: z.array(adminActionCallSummarySchema)
});

export const adminAgentTurnsResponseSchema = z.object({
  agentTurns: z.array(adminAgentTurnSummarySchema)
});

export const adminAgentToolCallsResponseSchema = z.object({
  agentToolCalls: z.array(adminAgentToolCallSummarySchema)
});

export const adminLlmProviderCallsResponseSchema = z.object({
  providerCalls: z.array(adminLlmProviderCallSummarySchema)
});

export const adminTranscriptionsResponseSchema = z.object({
  transcriptions: z.array(adminTranscriptionSummarySchema)
});

export const adminLlmCostBreakdownSchema = z.object({
  key: z.string(),
  providerCostAmount: z.number(),
  estimatedCostAmount: z.number(),
  totalCostAmount: z.number(),
  unknownCostCount: z.number().int(),
  totalTokens: z.number().int(),
  callCount: z.number().int()
});

export const adminLlmCostResponseSchema = z.object({
  from: isoDateTimeSchema,
  to: isoDateTimeSchema,
  totalProviderCostAmount: z.number(),
  totalEstimatedCostAmount: z.number(),
  totalCostAmount: z.number(),
  unknownCostCount: z.number().int(),
  totalPromptTokens: z.number().int(),
  totalCompletionTokens: z.number().int(),
  totalTokens: z.number().int(),
  byUser: z.array(adminLlmCostBreakdownSchema),
  byConversation: z.array(adminLlmCostBreakdownSchema),
  byTurn: z.array(adminLlmCostBreakdownSchema),
  byModel: z.array(adminLlmCostBreakdownSchema),
  byProvider: z.array(adminLlmCostBreakdownSchema),
  byFeature: z.array(adminLlmCostBreakdownSchema),
  byDay: z.array(adminLlmCostBreakdownSchema)
});

export const telemetryTraceResponseSchema = z.object({
  traceId: z.string(),
  events: z.array(telemetryEventSummarySchema),
  llmRuns: z.array(llmRunSummarySchema),
  foodSearchEvents: z.array(foodSearchEventSummarySchema),
  conversationMessages: z.array(agentConversationMessageSchema).optional(),
  agentTurns: z.array(adminAgentTurnSummarySchema).optional(),
  agentToolCalls: z.array(adminAgentToolCallSummarySchema).optional(),
  actionCalls: z.array(adminActionCallSummarySchema).optional(),
  providerCalls: z.array(adminLlmProviderCallSummarySchema).optional(),
  transcriptions: z.array(adminTranscriptionSummarySchema).optional()
});

export const telemetryOverviewResponseSchema = z.object({
  from: isoDateTimeSchema,
  to: isoDateTimeSchema,
  totalEvents: z.number().int().nonnegative(),
  totalLlmRuns: z.number().int().nonnegative(),
  totalFoodSearchEvents: z.number().int().nonnegative(),
  totalConversations: z.number().int().nonnegative(),
  totalAgentTurns: z.number().int().nonnegative(),
  totalProviderCalls: z.number().int().nonnegative(),
  totalTranscriptions: z.number().int().nonnegative(),
  providerCostAmount: z.number(),
  estimatedCostAmount: z.number(),
  unknownCostCount: z.number().int().nonnegative(),
  uniqueUsers: z.number().int().nonnegative(),
  uniqueTraces: z.number().int().nonnegative(),
  eventsBySeverity: z.record(z.number().int().nonnegative()),
  eventsBySurface: z.record(z.number().int().nonnegative()),
  recentResultKinds: z.record(z.number().int().nonnegative()),
  zeroResultRate: z.number().min(0).max(1),
  lowConfidenceRate: z.number().min(0).max(1),
  providerErrorRate: z.number().min(0).max(1)
});

export const telemetryLlmRunsResponseSchema = z.object({
  llmRuns: z.array(llmRunSummarySchema)
});

export const telemetryFoodSearchResponseSchema = z.object({
  foodSearchEvents: z.array(foodSearchEventSummarySchema)
});

export const telemetryEventsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).optional(),
  severity: telemetrySeveritySchema.optional(),
  eventType: z.string().trim().max(120).optional(),
  surface: telemetrySurfaceSchema.optional(),
  traceId: z.string().trim().max(120).optional(),
  userId: uuidSchema.optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional()
});

export const telemetryLlmRunsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).optional(),
  resultKind: z.string().trim().max(80).optional(),
  selectedTool: z.string().trim().max(80).optional(),
  executedTool: z.string().trim().max(80).optional(),
  traceId: z.string().trim().max(120).optional(),
  userId: uuidSchema.optional(),
  conversationId: uuidSchema.optional(),
  turnId: uuidSchema.optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional()
});

export const adminIncludeHiddenSchema = z
  .union([z.literal("true"), z.literal("false")])
  .transform((value) => value === "true")
  .optional();

export const adminTelemetryBaseQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(500).optional(),
  userId: uuidSchema.optional(),
  conversationId: uuidSchema.optional(),
  traceId: z.string().trim().max(120).optional(),
  turnId: uuidSchema.optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional()
});

export const adminTelemetryConversationsQuerySchema =
  adminTelemetryBaseQuerySchema.extend({
    includeHidden: adminIncludeHiddenSchema
  });

export const adminTelemetryActionCallsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(500).optional(),
  userId: uuidSchema.optional(),
  traceId: z.string().trim().max(120).optional(),
  actionId: z.string().trim().max(120).optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional()
});

export const adminTelemetryAgentTurnsQuerySchema =
  adminTelemetryBaseQuerySchema.extend({
    inputMode: z.string().trim().max(40).optional(),
    status: z.string().trim().max(40).optional()
  });

export const adminTelemetryAgentToolCallsQuerySchema =
  adminTelemetryBaseQuerySchema.extend({
    actionId: z.string().trim().max(120).optional(),
    status: z.string().trim().max(40).optional()
  });

export const adminTelemetryProviderCallsQuerySchema =
  adminTelemetryBaseQuerySchema.extend({
    provider: z.string().trim().max(120).optional(),
    model: z.string().trim().max(160).optional(),
    status: z.string().trim().max(40).optional(),
    costSource: z.string().trim().max(40).optional()
  });

export const adminTelemetryTranscriptionsQuerySchema =
  adminTelemetryBaseQuerySchema.extend({
    surface: z.string().trim().max(80).optional(),
    status: z.string().trim().max(40).optional()
  });

export const adminTelemetryCostQuerySchema = z.object({
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional(),
  userId: uuidSchema.optional(),
  conversationId: uuidSchema.optional(),
  traceId: z.string().trim().max(120).optional()
});

export const telemetryFoodSearchQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).optional(),
  zeroResults: z
    .union([z.literal("true"), z.literal("false")])
    .transform((value) => value === "true")
    .optional(),
  lowConfidence: z
    .union([z.literal("true"), z.literal("false")])
    .transform((value) => value === "true")
    .optional(),
  path: z.string().trim().max(80).optional(),
  traceId: z.string().trim().max(120).optional(),
  userId: uuidSchema.optional(),
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional()
});

export const telemetryOverviewQuerySchema = z.object({
  from: z.string().datetime().optional(),
  to: z.string().datetime().optional()
});

export type TelemetrySurface = z.infer<typeof telemetrySurfaceSchema>;
export type ClientTelemetrySurface = z.infer<typeof clientTelemetrySurfaceSchema>;
export type TelemetrySeverity = z.infer<typeof telemetrySeveritySchema>;
export type TelemetryStatus = z.infer<typeof telemetryStatusSchema>;
export type ClientTelemetryEventInput = z.infer<typeof clientTelemetryEventInputSchema>;
export type ClientTelemetryIngestRequest = z.infer<typeof clientTelemetryIngestRequestSchema>;
export type ClientTelemetryIngestResponse = z.infer<typeof clientTelemetryIngestResponseSchema>;
export type TelemetryEventSummary = z.infer<typeof telemetryEventSummarySchema>;
export type TelemetryEventsResponse = z.infer<typeof telemetryEventsResponseSchema>;
export type TelemetryTraceResponse = z.infer<typeof telemetryTraceResponseSchema>;
export type TelemetryOverviewResponse = z.infer<typeof telemetryOverviewResponseSchema>;
export type TelemetryLlmRunsResponse = z.infer<typeof telemetryLlmRunsResponseSchema>;
export type TelemetryFoodSearchResponse = z.infer<typeof telemetryFoodSearchResponseSchema>;
export type LlmRunSummary = z.infer<typeof llmRunSummarySchema>;
export type FoodSearchEventSummary = z.infer<typeof foodSearchEventSummarySchema>;
export type AdminAgentTurnSummary = z.infer<typeof adminAgentTurnSummarySchema>;
export type AdminAgentToolCallSummary = z.infer<typeof adminAgentToolCallSummarySchema>;
export type AdminActionCallSummary = z.infer<typeof adminActionCallSummarySchema>;
export type AdminLlmProviderCallSummary = z.infer<typeof adminLlmProviderCallSummarySchema>;
export type AdminTranscriptionSummary = z.infer<typeof adminTranscriptionSummarySchema>;
export type AdminAgentConversationsResponse = z.infer<typeof adminAgentConversationsResponseSchema>;
export type AdminAgentConversationDetailResponse = z.infer<typeof adminAgentConversationDetailResponseSchema>;
export type AdminActionCallsResponse = z.infer<typeof adminActionCallsResponseSchema>;
export type AdminAgentTurnsResponse = z.infer<typeof adminAgentTurnsResponseSchema>;
export type AdminAgentToolCallsResponse = z.infer<typeof adminAgentToolCallsResponseSchema>;
export type AdminLlmProviderCallsResponse = z.infer<typeof adminLlmProviderCallsResponseSchema>;
export type AdminTranscriptionsResponse = z.infer<typeof adminTranscriptionsResponseSchema>;
export type AdminLlmCostResponse = z.infer<typeof adminLlmCostResponseSchema>;
export type AdminLlmCostBreakdown = z.infer<typeof adminLlmCostBreakdownSchema>;
