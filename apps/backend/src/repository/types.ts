import type {
  AuthUser,
  CalorieTargetSource,
  DailySummary,
  DailyGoals,
  MacroMode,
  MacroPreset,
  MacroSource,
  Meal,
  MealItem,
  MealLabel,
  MealProposal,
  MealTemplate,
  NutritionSnapshot,
  PermissionScope,
  CreateUsualFoodRequest,
  UpdateUsualFoodRequest,
  UsualFood,
} from "@cal-tracker/contracts";

export type StoredUser = AuthUser & {
  passwordHash?: string;
  scopes: PermissionScope[];
};

export type UpdateDailyGoalsInput = {
  date: string;
  calories?: number;
  hydrationGoalLiters?: number;
  calorieTargetSource?: CalorieTargetSource;
  macroMode?: MacroMode;
  macroSource?: MacroSource;
  macroPreset?: MacroPreset | null;
  proteinPct?: number;
  carbsPct?: number;
  fatPct?: number;
  proteinGrams?: number;
  carbsGrams?: number;
  fatGrams?: number;
  macroCalories?: number;
  calorieDeltaKcal?: number;
};

export type AuthIdentityProvider = "google";

export type AuthIdentityRecord = {
  id: string;
  userId: string;
  provider: AuthIdentityProvider;
  providerUserId: string;
  email: string;
  createdAt: string;
  updatedAt: string;
};

export type StoredSession = {
  id: string;
  userId: string;
  refreshTokenHash: string;
  expiresAt: string;
  revokedAt?: string;
  createdAt: string;
  rotatedAt?: string;
};

export type FoodItemRecord = {
  id: string;
  userId?: string;
  name: string;
  normalizedName: string;
  canonicalName?: string;
  brand?: string;
  barcode?: string;
  source: string;
  externalSource?: string;
  externalId?: string;
  sourceUrl?: string;
  license?: string;
  fetchedAt?: string;
  dataType?: string;
  foodCategory?: string;
  publicationDate?: string;
  ndbNumber?: string;
  foodKey?: string;
  ingredients?: string;
  marketCountry?: string;
  normalizedDisplayName?: string;
  normalizedBaseName?: string;
  normalizedVariantName?: string;
  normalizedResultType?: string;
  normalizedBrandDisplay?: string;
  primaryEntityName?: string;
  primaryEntityAliases?: string[];
  secondaryEntityAliases?: string[];
  primaryEntityCategory?: string;
  primaryEntityCategoryCoherence?: number;
  primaryEntityRepresentativeness?: number;
  displayDetails?: string[];
  householdServingFulltext?: string;
  nutrients?: Record<string, unknown>;
  portions?: FoodPortionRecord[];
  servingGrams: number;
  calories: number;
  proteinGrams: number;
  carbsGrams: number;
  fatGrams: number;
  createdAt?: string;
  updatedAt?: string;
  deletedAt?: string;
};

export type FoodPortionRecord = {
  id: string;
  foodItemId: string;
  usdaPortionId?: string;
  amount?: number;
  unit?: string;
  modifier?: string;
  description?: string;
  gramWeight: number;
  normalizedAliases: string[];
  kind: string;
  sourceDescription: string;
};

export type FoodItemEmbeddingRecord = {
  id: string;
  foodItemId: string;
  embeddedText: string;
  embeddedTextHash: string;
  createdAt: string;
  updatedAt: string;
};

export type FoodSearchCandidate = FoodItemRecord & {
  lexicalScore: number;
  vectorScore?: number;
  preferenceScore: number;
  finalScore: number;
};

export type FoodFeedbackAction =
  | "selected"
  | "logged"
  | "corrected"
  | "dismissed"
  | "rejected";

export type FoodFeedbackRecord = {
  userId: string;
  foodItemId?: string;
  externalSource?: string;
  externalId?: string;
  query: string;
  action: FoodFeedbackAction;
  metadata?: Record<string, unknown>;
};

export type UserFoodPreference = {
  userId: string;
  foodItemId: string;
  affinityScore: number;
  positiveFeedbackCount: number;
  negativeFeedbackCount: number;
  lastFeedbackAt: string;
  updatedAt: string;
};

export type FoodHybridSearchInput = {
  query: string;
  barcode?: string;
  embedding?: number[];
  limit?: number;
  locale?: string;
};

export type UpsertFoodItemEmbeddingInput = {
  foodItemId: string;
  embeddedText: string;
  embeddedTextHash: string;
  embedding: number[];
};

export type MemoryMatch = {
  id: string;
  userId: string;
  label: string;
  normalizedText: string;
  confidence: number;
  template: MealTemplate | null;
};

export type ActionCallRecord = {
  id: string;
  userId: string;
  actionId: string;
  source: string;
  input: unknown;
  output?: unknown;
  error?: unknown;
  confirmationStatus: string;
  traceId: string;
  latencyMs: number;
  createdAt: string;
};

export type AuditEventRecord = {
  id: string;
  userId?: string;
  eventType: string;
  metadata: unknown;
  traceId: string;
  createdAt: string;
};

export type TelemetryEventRecord = {
  id: string;
  traceId: string;
  userId?: string;
  sessionId?: string;
  eventType: string;
  flow?: string;
  surface: string;
  severity: string;
  status?: string;
  route?: string;
  method?: string;
  actionId?: string;
  durationMs?: number;
  errorCode?: string;
  errorMessage?: string;
  appVersion?: string;
  appBuild?: string;
  platform?: string;
  locale?: string;
  metadata: Record<string, unknown>;
  createdAt: string;
};

export type LlmRunRecord = {
  id: string;
  traceId: string;
  userId?: string;
  source?: string;
  locale?: string;
  timezone?: string;
  conversationId?: string;
  turnId?: string;
  provider?: string;
  providerRequestId?: string;
  providerGenerationId?: string;
  model: string;
  inputMode?: string;
  activeProposalId?: string;
  decisionSource?: string;
  selectedTool?: string;
  executedTool?: string;
  resultKind?: string;
  actionCallId?: string;
  promptChars?: number;
  toolsJsonChars?: number;
  messagesJsonChars?: number;
  requestPayloadChars?: number;
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  firstByteMs?: number;
  firstToolCallMs?: number;
  largestStreamGapMs?: number;
  llmMs?: number;
  actionMs?: number;
  totalMs?: number;
  emptyToolCall: boolean;
  invalidToolArguments: boolean;
  providerError: boolean;
  providerCostAmount?: number;
  estimatedCostAmount?: number;
  costCurrency?: string;
  costSource?: string;
  pricingSnapshot?: Record<string, unknown>;
  metadata: Record<string, unknown>;
  createdAt: string;
};

export type FoodSearchEventRecord = {
  id: string;
  traceId: string;
  userId?: string;
  queryText?: string;
  queryHash?: string;
  queryLength: number;
  locale?: string;
  barcodePresent: boolean;
  normalizedSearchEnabled?: boolean;
  normalizedScope?: string;
  path?: string;
  resultCount: number;
  candidateGroupCount?: number;
  topScore?: number;
  topExternalSource?: string;
  topResultType?: string;
  zeroResults: boolean;
  lowConfidence: boolean;
  selectedRank?: number;
  durationMs?: number;
  metadata: Record<string, unknown>;
  createdAt: string;
};

export type AgentTurnTelemetryRecord = {
  id: string;
  conversationId?: string;
  traceId: string;
  turnId: string;
  userId?: string;
  inputMode?: string;
  source?: string;
  activeProposalId?: string;
  model?: string;
  inputText?: string;
  assistantText?: string;
  resultKind?: string;
  stopReason?: string;
  iterationCount: number;
  toolCallCount: number;
  promptChars?: number;
  messagesJsonChars?: number;
  toolsJsonChars?: number;
  requestPayloadChars?: number;
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  providerCostAmount?: number;
  estimatedCostAmount?: number;
  costCurrency?: string;
  costSource?: string;
  pricingSnapshot: Record<string, unknown>;
  firstByteMs?: number;
  firstToolCallMs?: number;
  largestStreamGapMs?: number;
  llmMs?: number;
  actionMs?: number;
  totalMs?: number;
  status: string;
  errorCode?: string;
  errorMessage?: string;
  metadata: Record<string, unknown>;
  completedAt?: string;
  createdAt: string;
};

export type AgentToolCallTelemetryRecord = {
  id: string;
  agentTurnId?: string;
  conversationId?: string;
  traceId: string;
  turnId?: string;
  userId?: string;
  toolCallId?: string;
  actionCallId?: string;
  actionId: string;
  arguments?: unknown;
  resultSummary?: unknown;
  status: string;
  errorMessage?: string;
  startedAt: string;
  completedAt?: string;
  durationMs?: number;
  metadata: Record<string, unknown>;
  createdAt: string;
};

export type LlmProviderCallRecord = {
  id: string;
  traceId: string;
  userId?: string;
  conversationId?: string;
  agentTurnId?: string;
  turnId?: string;
  actionCallId?: string;
  featureSurface: string;
  provider: string;
  providerRequestId?: string;
  providerGenerationId?: string;
  requestedModel: string;
  servedModel?: string;
  routing?: unknown;
  inputMode?: string;
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  cachedInputTokens?: number;
  audioTokens?: number;
  imageTokens?: number;
  providerCostAmount?: number;
  estimatedCostAmount?: number;
  costCurrency?: string;
  costSource: string;
  inputTokenUnitPrice?: number;
  outputTokenUnitPrice?: number;
  reasoningTokenUnitPrice?: number;
  cachedInputTokenUnitPrice?: number;
  audioTokenUnitPrice?: number;
  imageTokenUnitPrice?: number;
  pricingSource?: string;
  pricingVersion?: string;
  pricingEffectiveAt?: string;
  status: string;
  errorCode?: string;
  errorMessage?: string;
  durationMs?: number;
  metadata: Record<string, unknown>;
  createdAt: string;
};

export type TranscriptionRecord = {
  id: string;
  traceId: string;
  userId?: string;
  conversationId?: string;
  turnId?: string;
  surface: string;
  provider?: string;
  model?: string;
  language?: string;
  audioMimeType?: string;
  audioBytes?: number;
  audioDurationMs?: number;
  transcriptText?: string;
  transcriptLength: number;
  durationMs?: number;
  status: string;
  errorCode?: string;
  errorMessage?: string;
  downstreamResultKind?: string;
  metadata: Record<string, unknown>;
  createdAt: string;
};

export type TelemetryEventFilter = {
  limit?: number;
  severity?: string;
  eventType?: string;
  surface?: string;
  traceId?: string;
  userId?: string;
  from?: string;
  to?: string;
};

export type LlmRunFilter = {
  limit?: number;
  resultKind?: string;
  selectedTool?: string;
  executedTool?: string;
  traceId?: string;
  userId?: string;
  conversationId?: string;
  turnId?: string;
  from?: string;
  to?: string;
};

export type FoodSearchEventFilter = {
  limit?: number;
  zeroResults?: boolean;
  lowConfidence?: boolean;
  path?: string;
  traceId?: string;
  userId?: string;
  from?: string;
  to?: string;
};

export type TelemetryOverview = {
  from: string;
  to: string;
  totalEvents: number;
  totalLlmRuns: number;
  totalFoodSearchEvents: number;
  totalConversations: number;
  totalAgentTurns: number;
  totalProviderCalls: number;
  totalTranscriptions: number;
  providerCostAmount: number;
  estimatedCostAmount: number;
  unknownCostCount: number;
  uniqueUsers: number;
  uniqueTraces: number;
  eventsBySeverity: Record<string, number>;
  eventsBySurface: Record<string, number>;
  recentResultKinds: Record<string, number>;
  zeroResultRate: number;
  lowConfidenceRate: number;
  providerErrorRate: number;
};

export type AdminConversationFilter = {
  limit?: number;
  userId?: string;
  conversationId?: string;
  traceId?: string;
  turnId?: string;
  includeHidden?: boolean;
  from?: string;
  to?: string;
};

export type AdminActionCallFilter = {
  limit?: number;
  userId?: string;
  traceId?: string;
  actionId?: string;
  from?: string;
  to?: string;
};

export type AgentTurnTelemetryFilter = {
  limit?: number;
  userId?: string;
  conversationId?: string;
  traceId?: string;
  turnId?: string;
  inputMode?: string;
  status?: string;
  from?: string;
  to?: string;
};

export type AgentToolCallTelemetryFilter = {
  limit?: number;
  userId?: string;
  conversationId?: string;
  traceId?: string;
  turnId?: string;
  actionId?: string;
  status?: string;
  from?: string;
  to?: string;
};

export type LlmProviderCallFilter = {
  limit?: number;
  userId?: string;
  conversationId?: string;
  traceId?: string;
  turnId?: string;
  provider?: string;
  model?: string;
  status?: string;
  costSource?: string;
  from?: string;
  to?: string;
};

export type TranscriptionRecordFilter = {
  limit?: number;
  userId?: string;
  conversationId?: string;
  traceId?: string;
  turnId?: string;
  surface?: string;
  status?: string;
  from?: string;
  to?: string;
};

export type LlmCostFilter = {
  from: string;
  to: string;
  userId?: string;
  conversationId?: string;
  traceId?: string;
};

export type LlmCostOverview = {
  from: string;
  to: string;
  totalProviderCostAmount: number;
  totalEstimatedCostAmount: number;
  totalCostAmount: number;
  unknownCostCount: number;
  totalPromptTokens: number;
  totalCompletionTokens: number;
  totalTokens: number;
  byUser: LlmCostBreakdown[];
  byConversation: LlmCostBreakdown[];
  byTurn: LlmCostBreakdown[];
  byModel: LlmCostBreakdown[];
  byProvider: LlmCostBreakdown[];
  byFeature: LlmCostBreakdown[];
  byDay: LlmCostBreakdown[];
};

export type LlmCostBreakdown = {
  key: string;
  providerCostAmount: number;
  estimatedCostAmount: number;
  totalCostAmount: number;
  unknownCostCount: number;
  totalTokens: number;
  callCount: number;
};

export type AgentConversationRecord = {
  id: string;
  userId: string;
  title: string;
  hiddenFromUserAt?: string;
  createdAt: string;
  updatedAt: string;
};

export type AgentConversationMessageRole = "user" | "assistant" | "tool";

export type AgentConversationMessageRecord = {
  id: string;
  conversationId: string;
  userId: string;
  role: AgentConversationMessageRole;
  content: string;
  toolCalls?: unknown;
  toolCallId?: string;
  traceId?: string;
  turnId?: string;
  inputMode?: string;
  source?: string;
  activeProposalId?: string;
  metadata?: unknown;
  createdAt: string;
};

export interface AppRepository {
  createUser(input: {
    email: string;
    displayName: string;
    passwordHash?: string;
    scopes: PermissionScope[];
  }): Promise<StoredUser>;
  findUserByEmail(email: string): Promise<StoredUser | undefined>;
  findUserById(id: string): Promise<StoredUser | undefined>;
  updateTrustedMode(userId: string, enabled: boolean): Promise<StoredUser>;
  findAuthIdentity(
    provider: AuthIdentityProvider,
    providerUserId: string,
  ): Promise<AuthIdentityRecord | undefined>;
  linkAuthIdentity(input: {
    userId: string;
    provider: AuthIdentityProvider;
    providerUserId: string;
    email: string;
  }): Promise<AuthIdentityRecord>;

  createSession(
    input: Omit<StoredSession, "createdAt">,
  ): Promise<StoredSession>;
  findSessionByRefreshTokenHash(
    hash: string,
  ): Promise<StoredSession | undefined>;
  revokeSession(sessionId: string): Promise<void>;
  revokeAllSessions(userId: string): Promise<void>;
  rotateSession(
    sessionId: string,
    nextHash: string,
    expiresAt: string,
  ): Promise<StoredSession>;

  createPasswordReset(input: {
    userId: string;
    tokenHash: string;
    expiresAt: string;
  }): Promise<void>;
  consumePasswordReset(
    tokenHash: string,
    newPasswordHash: string,
  ): Promise<boolean>;

  listFoods(userId: string): Promise<FoodItemRecord[]>;
  searchFoods(
    userId: string,
    query: string,
    barcode?: string,
  ): Promise<FoodItemRecord[]>;
  searchFoodsHybrid(
    userId: string,
    input: FoodHybridSearchInput,
  ): Promise<FoodSearchCandidate[]>;
  upsertFoodItem(input: Omit<FoodItemRecord, "id">): Promise<FoodItemRecord>;
  listUsualFoods(userId: string): Promise<UsualFood[]>;
  createUsualFood(
    userId: string,
    input: CreateUsualFoodRequest,
  ): Promise<UsualFood>;
  updateUsualFood(
    userId: string,
    usualFoodId: string,
    input: UpdateUsualFoodRequest,
  ): Promise<UsualFood | undefined>;
  deleteUsualFood(userId: string, usualFoodId: string): Promise<boolean>;
  recordFoodFeedback(
    input: FoodFeedbackRecord,
  ): Promise<UserFoodPreference | undefined>;
  getUserFoodPreferences(userId: string): Promise<UserFoodPreference[]>;
  upsertFoodItemEmbedding(
    input: UpsertFoodItemEmbeddingInput,
  ): Promise<FoodItemEmbeddingRecord>;

  getNutritionTarget(userId: string): Promise<NutritionSnapshot>;
  getDailyGoals(userId: string, date: string): Promise<DailyGoals>;
  updateDailyGoals(
    userId: string,
    input: UpdateDailyGoalsInput,
  ): Promise<DailyGoals>;
  updateDailyHydration(
    userId: string,
    date: string,
    waterConsumedLiters: number,
  ): Promise<DailySummary>;
  listMeals(userId: string, limit?: number): Promise<Meal[]>;
  getMeal(userId: string, mealId: string): Promise<Meal | undefined>;
  createProposal(
    userId: string,
    proposal: Omit<MealProposal, "id" | "createdAt">,
  ): Promise<MealProposal>;
  getProposal(
    userId: string,
    proposalId: string,
  ): Promise<MealProposal | undefined>;
  updateProposal(userId: string, proposal: MealProposal): Promise<MealProposal>;
  createMealFromProposal(
    userId: string,
    proposal: MealProposal,
    occurredAt: string,
    items?: MealItem[],
    mealLabel?: MealLabel | null,
  ): Promise<Meal>;
  updateMeal(userId: string, meal: Meal): Promise<Meal>;
  softDeleteMeal(userId: string, mealId: string): Promise<boolean>;
  getDailySummary(userId: string, date: string): Promise<DailySummary>;

  listTemplates(userId: string): Promise<MealTemplate[]>;
  createTemplate(
    userId: string,
    input: Omit<MealTemplate, "id">,
  ): Promise<MealTemplate>;
  updateTemplate(userId: string, template: MealTemplate): Promise<MealTemplate>;
  deleteTemplate(userId: string, templateId: string): Promise<boolean>;
  queryMemory(userId: string, normalizedText: string): Promise<MemoryMatch[]>;
  createMemory(input: {
    userId: string;
    normalizedText: string;
    label: string;
    templateId?: string;
    confidence: number;
  }): Promise<void>;

  createAgentConversation(
    userId: string,
    input?: { title?: string },
  ): Promise<AgentConversationRecord>;
  getAgentConversation(
    userId: string,
    conversationId: string,
  ): Promise<AgentConversationRecord | undefined>;
  listAgentConversations(
    userId: string,
    limit?: number,
  ): Promise<AgentConversationRecord[]>;
  addAgentConversationMessage(
    userId: string,
    conversationId: string,
    input: Omit<
      AgentConversationMessageRecord,
      "id" | "conversationId" | "userId" | "createdAt"
    >,
  ): Promise<AgentConversationMessageRecord>;
  listAgentConversationMessages(
    userId: string,
    conversationId: string,
  ): Promise<AgentConversationMessageRecord[]>;
  deleteAgentConversation(
    userId: string,
    conversationId: string,
  ): Promise<boolean>;
  hideAgentConversationFromUser(
    userId: string,
    conversationId: string,
  ): Promise<boolean>;

  recordActionCall(
    input: Omit<ActionCallRecord, "id" | "createdAt">,
  ): Promise<ActionCallRecord>;
  recordAuditEvent(
    input: Omit<AuditEventRecord, "id" | "createdAt">,
  ): Promise<AuditEventRecord>;
  listActionCalls(userId: string): Promise<ActionCallRecord[]>;
  listAdminActionCalls(
    filter: AdminActionCallFilter,
  ): Promise<ActionCallRecord[]>;
  listAuditEvents(userId: string): Promise<AuditEventRecord[]>;

  listAdminAgentConversations(
    filter: AdminConversationFilter,
  ): Promise<AgentConversationRecord[]>;
  getAdminAgentConversationMessages(
    conversationId: string,
    includeHidden?: boolean,
  ): Promise<AgentConversationMessageRecord[]>;
  listAgentConversationMessagesByTrace(
    traceId: string,
    includeHidden?: boolean,
  ): Promise<AgentConversationMessageRecord[]>;

  createTelemetryEvent(
    input: Omit<TelemetryEventRecord, "id" | "createdAt">,
  ): Promise<TelemetryEventRecord>;
  listTelemetryEvents(
    filter: TelemetryEventFilter,
  ): Promise<TelemetryEventRecord[]>;
  createLlmRun(
    input: Omit<LlmRunRecord, "id" | "createdAt">,
  ): Promise<LlmRunRecord>;
  listLlmRuns(filter: LlmRunFilter): Promise<LlmRunRecord[]>;
  createAgentTurnTelemetry(
    input: Omit<AgentTurnTelemetryRecord, "id" | "createdAt">,
  ): Promise<AgentTurnTelemetryRecord>;
  listAgentTurnTelemetry(
    filter: AgentTurnTelemetryFilter,
  ): Promise<AgentTurnTelemetryRecord[]>;
  createAgentToolCallTelemetry(
    input: Omit<AgentToolCallTelemetryRecord, "id" | "createdAt">,
  ): Promise<AgentToolCallTelemetryRecord>;
  listAgentToolCallTelemetry(
    filter: AgentToolCallTelemetryFilter,
  ): Promise<AgentToolCallTelemetryRecord[]>;
  createLlmProviderCall(
    input: Omit<LlmProviderCallRecord, "id" | "createdAt">,
  ): Promise<LlmProviderCallRecord>;
  listLlmProviderCalls(
    filter: LlmProviderCallFilter,
  ): Promise<LlmProviderCallRecord[]>;
  createTranscriptionRecord(
    input: Omit<TranscriptionRecord, "id" | "createdAt">,
  ): Promise<TranscriptionRecord>;
  listTranscriptionRecords(
    filter: TranscriptionRecordFilter,
  ): Promise<TranscriptionRecord[]>;
  getLlmCostOverview(filter: LlmCostFilter): Promise<LlmCostOverview>;
  createFoodSearchEvent(
    input: Omit<FoodSearchEventRecord, "id" | "createdAt">,
  ): Promise<FoodSearchEventRecord>;
  listFoodSearchEvents(
    filter: FoodSearchEventFilter,
  ): Promise<FoodSearchEventRecord[]>;
  getTelemetryOverview(input: {
    from: string;
    to: string;
  }): Promise<TelemetryOverview>;
}
