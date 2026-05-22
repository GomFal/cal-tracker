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
  PermissionScope
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
  householdServingFulltext?: string;
  nutrients?: Record<string, unknown>;
  portions?: FoodPortionRecord[];
  servingGrams: number;
  calories: number;
  proteinGrams: number;
  carbsGrams: number;
  fatGrams: number;
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

export type EmbeddingModelRecord = {
  id: string;
  provider: string;
  model: string;
  dimensions: number;
};

export type FoodItemEmbeddingRecord = {
  id: string;
  foodItemId: string;
  embeddingModelId: string;
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

export type FoodSearchScope = "generic" | "market";

export type FoodFeedbackAction = "selected" | "logged" | "corrected" | "dismissed" | "rejected";

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
  embeddingModelId?: string;
  limit?: number;
  excludeBranded?: boolean;
  locale?: string;
  scope?: FoodSearchScope;
};

export type UpsertFoodItemEmbeddingInput = {
  foodItemId: string;
  embeddingModelId: string;
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

export interface AppRepository {
  createUser(input: { email: string; displayName: string; passwordHash?: string; scopes: PermissionScope[] }): Promise<StoredUser>;
  findUserByEmail(email: string): Promise<StoredUser | undefined>;
  findUserById(id: string): Promise<StoredUser | undefined>;
  updateTrustedMode(userId: string, enabled: boolean): Promise<StoredUser>;
  findAuthIdentity(provider: AuthIdentityProvider, providerUserId: string): Promise<AuthIdentityRecord | undefined>;
  linkAuthIdentity(input: { userId: string; provider: AuthIdentityProvider; providerUserId: string; email: string }): Promise<AuthIdentityRecord>;

  createSession(input: Omit<StoredSession, "createdAt">): Promise<StoredSession>;
  findSessionByRefreshTokenHash(hash: string): Promise<StoredSession | undefined>;
  revokeSession(sessionId: string): Promise<void>;
  revokeAllSessions(userId: string): Promise<void>;
  rotateSession(sessionId: string, nextHash: string, expiresAt: string): Promise<StoredSession>;

  createPasswordReset(input: { userId: string; tokenHash: string; expiresAt: string }): Promise<void>;
  consumePasswordReset(tokenHash: string, newPasswordHash: string): Promise<boolean>;

  listFoods(userId: string): Promise<FoodItemRecord[]>;
  searchFoods(userId: string, query: string, barcode?: string): Promise<FoodItemRecord[]>;
  searchFoodsHybrid(userId: string, input: FoodHybridSearchInput): Promise<FoodSearchCandidate[]>;
  upsertFoodItem(input: Omit<FoodItemRecord, "id">): Promise<FoodItemRecord>;
  recordFoodFeedback(input: FoodFeedbackRecord): Promise<UserFoodPreference | undefined>;
  getUserFoodPreferences(userId: string): Promise<UserFoodPreference[]>;
  getActiveEmbeddingModel(): Promise<EmbeddingModelRecord | undefined>;
  upsertFoodItemEmbedding(input: UpsertFoodItemEmbeddingInput): Promise<FoodItemEmbeddingRecord>;

  getNutritionTarget(userId: string): Promise<NutritionSnapshot>;
  getDailyGoals(userId: string, date: string): Promise<DailyGoals>;
  updateDailyGoals(userId: string, input: UpdateDailyGoalsInput): Promise<DailyGoals>;
  updateDailyHydration(userId: string, date: string, waterConsumedLiters: number): Promise<DailySummary>;
  listMeals(userId: string, limit?: number): Promise<Meal[]>;
  getMeal(userId: string, mealId: string): Promise<Meal | undefined>;
  createProposal(userId: string, proposal: Omit<MealProposal, "id" | "createdAt">): Promise<MealProposal>;
  getProposal(userId: string, proposalId: string): Promise<MealProposal | undefined>;
  updateProposal(userId: string, proposal: MealProposal): Promise<MealProposal>;
  createMealFromProposal(userId: string, proposal: MealProposal, occurredAt: string, items?: MealItem[], mealLabel?: MealLabel | null): Promise<Meal>;
  updateMeal(userId: string, meal: Meal): Promise<Meal>;
  softDeleteMeal(userId: string, mealId: string): Promise<boolean>;
  getDailySummary(userId: string, date: string): Promise<DailySummary>;

  listTemplates(userId: string): Promise<MealTemplate[]>;
  createTemplate(userId: string, input: Omit<MealTemplate, "id">): Promise<MealTemplate>;
  updateTemplate(userId: string, template: MealTemplate): Promise<MealTemplate>;
  deleteTemplate(userId: string, templateId: string): Promise<boolean>;
  queryMemory(userId: string, normalizedText: string): Promise<MemoryMatch[]>;
  createMemory(input: { userId: string; normalizedText: string; label: string; templateId?: string; confidence: number }): Promise<void>;

  recordActionCall(input: Omit<ActionCallRecord, "id" | "createdAt">): Promise<ActionCallRecord>;
  recordAuditEvent(input: Omit<AuditEventRecord, "id" | "createdAt">): Promise<AuditEventRecord>;
  listActionCalls(userId: string): Promise<ActionCallRecord[]>;
  listAuditEvents(userId: string): Promise<AuditEventRecord[]>;
}
