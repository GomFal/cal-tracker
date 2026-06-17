import {
  defaultUserScopes,
  type CalorieTargetSource,
  type CreateUsualFoodRequest,
  type DailyGoals,
  type MacroGoalMetadata,
  type Meal,
  type MealItem,
  type MealLabel,
  type MealProposal,
  type MealTemplate,
  type NutritionSnapshot,
  type UpdateUsualFoodRequest,
  type UsualFood,
} from "@cal-tracker/contracts";
import { newId } from "../utils/ids.js";
import { normalizeText } from "../utils/normalize.js";
import { applyMacroGoalUpdate } from "../utils/macroGoals.js";
import { subtractNutrition, sumNutrition } from "../utils/nutrition.js";
import { fuzzyFoodScore, lexicalFoodScore } from "./foodSearchScoring.js";
import type {
  ActionCallRecord,
  AgentConversationMessageRecord,
  AgentConversationRecord,
  AppRepository,
  AuditEventRecord,
  AuthIdentityProvider,
  AuthIdentityRecord,
  FoodFeedbackRecord,
  FoodItemRecord,
  FoodItemEmbeddingRecord,
  FoodHybridSearchInput,
  FoodSearchCandidate,
  FoodSearchEventFilter,
  FoodSearchEventRecord,
  LlmRunFilter,
  LlmRunRecord,
  MemoryMatch,
  StoredSession,
  StoredUser,
  TelemetryEventFilter,
  TelemetryEventRecord,
  TelemetryOverview,
  UpsertFoodItemEmbeddingInput,
  UserFoodPreference,
  UpdateDailyGoalsInput,
} from "./types.js";

const ACTIVE_EMBEDDING_DIMENSIONS = 1024;
const DEFAULT_FOOD_SEARCH_LIMIT = 50;
const MAX_FOOD_SEARCH_LIMIT = 100;
const LEXICAL_SCORE_WEIGHT = 0.7;
const VECTOR_SCORE_WEIGHT = 0.25;
const LEXICAL_ONLY_SCORE_WEIGHT = 0.95;
const PREFERENCE_SCORE_WEIGHT = 0.05;
const PREFERENCE_SCORE_NORMALIZER = 10;
const USER_FOOD_SCORE_BOOST = 0.15;
const USUAL_FOOD_SOURCE = "user_custom";
const USUAL_FOOD_ALIASES_KEY = "usualFoodAliases";

export class InMemoryRepository implements AppRepository {
  private users = new Map<string, StoredUser>();
  private authIdentities = new Map<string, AuthIdentityRecord>();
  private sessions = new Map<string, StoredSession>();
  private passwordResetTokens = new Map<
    string,
    { userId: string; expiresAt: string; usedAt?: string }
  >();
  private foods = new Map<string, FoodItemRecord>();
  private targets = new Map<string, NutritionSnapshot>();
  private hydrationGoals = new Map<string, number>();
  private dailyWater = new Map<string, number>();
  private calorieTargetConfigured = new Map<string, boolean>();
  private calorieTargetSources = new Map<string, CalorieTargetSource>();
  private macroGoalMetadata = new Map<string, MacroGoalMetadata>();
  private dailyGoalSnapshots = new Map<string, DailyGoals>();
  private proposals = new Map<string, MealProposal & { userId: string }>();
  private meals = new Map<string, Meal & { userId: string }>();
  private templates = new Map<string, MealTemplate & { userId: string }>();
  private memories = new Map<
    string,
    {
      id: string;
      userId: string;
      normalizedText: string;
      label: string;
      templateId?: string;
      confidence: number;
      usageCount: number;
    }
  >();
  private foodEmbeddings = new Map<
    string,
    FoodItemEmbeddingRecord & { embedding: number[] }
  >();
  private foodPreferences = new Map<string, UserFoodPreference>();
  private foodFeedbackEvents: Array<
    FoodFeedbackRecord & { createdAt: string }
  > = [];
  private actionCalls: ActionCallRecord[] = [];
  private auditEvents: AuditEventRecord[] = [];
  private telemetryEvents: TelemetryEventRecord[] = [];
  private llmRuns: LlmRunRecord[] = [];
  private foodSearchEvents: FoodSearchEventRecord[] = [];
  private agentConversations = new Map<string, AgentConversationRecord>();
  private agentConversationMessages = new Map<
    string,
    AgentConversationMessageRecord[]
  >();

  static seeded(): InMemoryRepository {
    return new InMemoryRepository();
  }

  async createUser(input: {
    email: string;
    displayName: string;
    passwordHash?: string;
    scopes?: typeof defaultUserScopes;
  }): Promise<StoredUser> {
    if (await this.findUserByEmail(input.email)) {
      throw new Error("email_already_registered");
    }
    const user: StoredUser = {
      id: newId(),
      email: input.email.toLowerCase(),
      displayName: input.displayName,
      trustedModeEnabled: false,
      createdAt: new Date().toISOString(),
      ...(input.passwordHash ? { passwordHash: input.passwordHash } : {}),
      scopes: input.scopes ?? defaultUserScopes,
    };
    this.users.set(user.id, user);
    this.targets.set(user.id, {
      calories: 2200,
      proteinGrams: 0,
      carbsGrams: 0,
      fatGrams: 0,
    });
    this.hydrationGoals.set(user.id, 0);
    this.calorieTargetConfigured.set(user.id, false);
    this.calorieTargetSources.set(user.id, "default");
    return user;
  }

  async findUserByEmail(email: string): Promise<StoredUser | undefined> {
    return [...this.users.values()].find(
      (user) => user.email === email.toLowerCase(),
    );
  }

  async findUserById(id: string): Promise<StoredUser | undefined> {
    return this.users.get(id);
  }

  async updateTrustedMode(
    userId: string,
    enabled: boolean,
  ): Promise<StoredUser> {
    const user = this.requireUser(userId);
    user.trustedModeEnabled = false;
    return user;
  }

  async findAuthIdentity(
    provider: AuthIdentityProvider,
    providerUserId: string,
  ): Promise<AuthIdentityRecord | undefined> {
    return this.authIdentities.get(`${provider}:${providerUserId}`);
  }

  async linkAuthIdentity(input: {
    userId: string;
    provider: AuthIdentityProvider;
    providerUserId: string;
    email: string;
  }): Promise<AuthIdentityRecord> {
    const key = `${input.provider}:${input.providerUserId}`;
    const existing = this.authIdentities.get(key);
    if (existing) return existing;
    const now = new Date().toISOString();
    const identity: AuthIdentityRecord = {
      id: newId(),
      userId: input.userId,
      provider: input.provider,
      providerUserId: input.providerUserId,
      email: input.email.toLowerCase(),
      createdAt: now,
      updatedAt: now,
    };
    this.authIdentities.set(key, identity);
    return identity;
  }

  async createSession(
    input: Omit<StoredSession, "createdAt">,
  ): Promise<StoredSession> {
    const session = { ...input, createdAt: new Date().toISOString() };
    this.sessions.set(session.id, session);
    return session;
  }

  async findSessionByRefreshTokenHash(
    hash: string,
  ): Promise<StoredSession | undefined> {
    const now = Date.now();
    return [...this.sessions.values()].find(
      (session) =>
        session.refreshTokenHash === hash &&
        !session.revokedAt &&
        Date.parse(session.expiresAt) > now,
    );
  }

  async revokeSession(sessionId: string): Promise<void> {
    const session = this.sessions.get(sessionId);
    if (session) session.revokedAt = new Date().toISOString();
  }

  async revokeAllSessions(userId: string): Promise<void> {
    for (const session of this.sessions.values()) {
      if (session.userId === userId)
        session.revokedAt = new Date().toISOString();
    }
  }

  async rotateSession(
    sessionId: string,
    nextHash: string,
    expiresAt: string,
  ): Promise<StoredSession> {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error("session_not_found");
    session.refreshTokenHash = nextHash;
    session.expiresAt = expiresAt;
    session.rotatedAt = new Date().toISOString();
    return session;
  }

  async createPasswordReset(input: {
    userId: string;
    tokenHash: string;
    expiresAt: string;
  }): Promise<void> {
    this.passwordResetTokens.set(input.tokenHash, {
      userId: input.userId,
      expiresAt: input.expiresAt,
    });
  }

  async consumePasswordReset(
    tokenHash: string,
    newPasswordHash: string,
  ): Promise<boolean> {
    const reset = this.passwordResetTokens.get(tokenHash);
    if (!reset || reset.usedAt || Date.parse(reset.expiresAt) < Date.now())
      return false;
    const user = this.requireUser(reset.userId);
    user.passwordHash = newPasswordHash;
    reset.usedAt = new Date().toISOString();
    return true;
  }

  async listFoods(userId?: string): Promise<FoodItemRecord[]> {
    return [...this.foods.values()].filter(
      (food) =>
        !food.deletedAt && (!userId || !food.userId || food.userId === userId),
    );
  }

  async searchFoods(
    userId: string,
    query: string,
    barcode?: string,
  ): Promise<FoodItemRecord[]> {
    const candidates = await this.searchFoodsHybrid(userId, { query, barcode });
    return candidates.map(stripFoodSearchCandidate);
  }

  async searchFoodsHybrid(
    userId: string,
    input: FoodHybridSearchInput,
  ): Promise<FoodSearchCandidate[]> {
    const normalized = normalizeText(input.query);
    const limit = sanitizeLimit(input.limit);
    const candidates = new Map<
      string,
      { food: FoodItemRecord; lexicalScore: number; vectorScore?: number }
    >();
    const baseFoods = [...this.foods.values()].filter((food) => {
      if (food.deletedAt) return false;
      if (food.userId && food.userId !== userId) return false;
      return true;
    });
    const primaryFoods = baseFoods;
    const primaryFoodIds = new Set(primaryFoods.map((food) => food.id));

    if (input.barcode) {
      for (const food of primaryFoods) {
        if (food.barcode === input.barcode)
          candidates.set(food.id, { food, lexicalScore: 1 });
      }
    } else if (normalized.length > 0) {
      for (const food of primaryFoods) {
        const lexicalScore =
          lexicalFoodScore(food, normalized) ||
          fuzzyFoodScore(food, normalized);
        if (lexicalScore > 0) candidates.set(food.id, { food, lexicalScore });
      }
    }

    if (!input.barcode && input.embedding) {
      for (const embedding of this.foodEmbeddings.values()) {
        const food = this.foods.get(embedding.foodItemId);
        if (!food || (food.userId && food.userId !== userId)) continue;
        if (!primaryFoodIds.has(food.id)) continue;
        const vectorScore = clampScore(
          cosineSimilarity(input.embedding, embedding.embedding),
        );
        const existing = candidates.get(food.id);
        if (existing) {
          existing.vectorScore = Math.max(
            existing.vectorScore ?? 0,
            vectorScore,
          );
        } else {
          candidates.set(food.id, { food, lexicalScore: 0, vectorScore });
        }
      }
    }

    return [...candidates.values()]
      .map(({ food, lexicalScore, vectorScore }) => {
        const preference = this.foodPreferences.get(
          preferenceKey(userId, food.id),
        );
        const preferenceScore = clamp(
          (preference?.affinityScore ?? 0) / PREFERENCE_SCORE_NORMALIZER,
          -1,
          1,
        );
        const baseScore =
          vectorScore == null
            ? lexicalScore * LEXICAL_ONLY_SCORE_WEIGHT
            : lexicalScore * LEXICAL_SCORE_WEIGHT +
              vectorScore * VECTOR_SCORE_WEIGHT;
        const userFoodBoost =
          food.userId === userId && lexicalScore >= 0.5
            ? USER_FOOD_SCORE_BOOST
            : 0;
        return {
          ...food,
          lexicalScore,
          vectorScore,
          preferenceScore,
          finalScore: clampScore(
            baseScore +
              preferenceScore * PREFERENCE_SCORE_WEIGHT +
              userFoodBoost,
          ),
        };
      })
      .sort(
        (a, b) =>
          b.finalScore - a.finalScore ||
          b.lexicalScore - a.lexicalScore ||
          (b.vectorScore ?? 0) - (a.vectorScore ?? 0) ||
          Number(Boolean(b.userId)) - Number(Boolean(a.userId)) ||
          a.name.localeCompare(b.name),
      )
      .slice(0, limit);
  }

  async upsertFoodItem(
    input: Omit<FoodItemRecord, "id">,
  ): Promise<FoodItemRecord> {
    const normalized = normalizeText(input.normalizedName || input.name);
    const existing = [...this.foods.values()].find((food) => {
      if (input.externalSource && input.externalId) {
        return (
          food.externalSource === input.externalSource &&
          food.externalId === input.externalId
        );
      }
      return (
        food.userId === input.userId &&
        food.normalizedName === normalized &&
        food.source === input.source
      );
    });
    if (existing) {
      const updated = { ...existing, ...input, normalizedName: normalized };
      this.foods.set(existing.id, updated);
      return updated;
    }
    const food = { ...input, id: newId(), normalizedName: normalized };
    this.foods.set(food.id, food);
    return food;
  }

  async listUsualFoods(userId: string): Promise<UsualFood[]> {
    return [...this.foods.values()]
      .filter(
        (food) =>
          food.userId === userId &&
          food.source === USUAL_FOOD_SOURCE &&
          !food.deletedAt,
      )
      .sort(
        (a, b) =>
          Date.parse(b.updatedAt ?? b.createdAt ?? "") -
            Date.parse(a.updatedAt ?? a.createdAt ?? "") ||
          a.name.localeCompare(b.name),
      )
      .map(foodRecordToUsualFood);
  }

  async createUsualFood(
    userId: string,
    input: CreateUsualFoodRequest,
  ): Promise<UsualFood> {
    const now = new Date().toISOString();
    const food: FoodItemRecord = {
      id: newId(),
      userId,
      name: input.name,
      normalizedName: normalizeText(input.name),
      canonicalName: input.canonicalName ?? undefined,
      brand: input.brand ?? undefined,
      barcode: input.barcode ?? undefined,
      source: USUAL_FOOD_SOURCE,
      nutrients: nutrientsWithAliases(input.nutrients, input.aliases),
      servingGrams: input.servingGrams,
      calories: input.nutrition.calories,
      proteinGrams: input.nutrition.proteinGrams,
      carbsGrams: input.nutrition.carbsGrams,
      fatGrams: input.nutrition.fatGrams,
      createdAt: now,
      updatedAt: now,
    };
    this.foods.set(food.id, food);
    // Seed initial preference score so the usual food gets an immediate ranking edge
    void this.recordFoodFeedback({
      userId,
      foodItemId: food.id,
      query: input.name,
      action: "selected",
    });
    return foodRecordToUsualFood(food);
  }

  async updateUsualFood(
    userId: string,
    usualFoodId: string,
    input: UpdateUsualFoodRequest,
  ): Promise<UsualFood | undefined> {
    const existing = this.foods.get(usualFoodId);
    if (
      !existing ||
      existing.userId !== userId ||
      existing.source !== USUAL_FOOD_SOURCE ||
      existing.deletedAt
    ) {
      return undefined;
    }
    const nextAliases =
      input.aliases ?? aliasesFromNutrients(existing.nutrients);
    const nutrients =
      input.nutrients === undefined && input.aliases === undefined
        ? existing.nutrients
        : nutrientsWithAliases(
            input.nutrients ?? publicNutrients(existing.nutrients),
            nextAliases,
          );
    const nextCanonicalName =
      "canonicalName" in input
        ? (input.canonicalName ?? undefined)
        : existing.canonicalName;
    const nextBrand =
      "brand" in input ? (input.brand ?? undefined) : existing.brand;
    const nextBarcode =
      "barcode" in input ? (input.barcode ?? undefined) : existing.barcode;
    const updated: FoodItemRecord = {
      ...existing,
      name: input.name ?? existing.name,
      normalizedName: input.name
        ? normalizeText(input.name)
        : existing.normalizedName,
      canonicalName: nextCanonicalName,
      brand: nextBrand,
      barcode: nextBarcode,
      servingGrams: input.servingGrams ?? existing.servingGrams,
      calories: input.nutrition?.calories ?? existing.calories,
      proteinGrams: input.nutrition?.proteinGrams ?? existing.proteinGrams,
      carbsGrams: input.nutrition?.carbsGrams ?? existing.carbsGrams,
      fatGrams: input.nutrition?.fatGrams ?? existing.fatGrams,
      nutrients,
      updatedAt: new Date().toISOString(),
    };
    this.foods.set(usualFoodId, updated);
    return foodRecordToUsualFood(updated);
  }

  async deleteUsualFood(userId: string, usualFoodId: string): Promise<boolean> {
    const existing = this.foods.get(usualFoodId);
    if (
      !existing ||
      existing.userId !== userId ||
      existing.source !== USUAL_FOOD_SOURCE ||
      existing.deletedAt
    ) {
      return false;
    }
    this.foods.set(usualFoodId, {
      ...existing,
      deletedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
    return true;
  }

  async recordFoodFeedback(
    input: FoodFeedbackRecord,
  ): Promise<UserFoodPreference | undefined> {
    const foodItemId = input.foodItemId ?? this.findFoodForFeedback(input)?.id;
    if (!foodItemId) return undefined;
    this.foodFeedbackEvents.push({
      ...input,
      foodItemId,
      createdAt: new Date().toISOString(),
    });
    const key = preferenceKey(input.userId, foodItemId);
    const existing = this.foodPreferences.get(key);
    const delta = foodFeedbackDelta(input.action);
    const now = new Date().toISOString();
    const preference: UserFoodPreference = existing
      ? {
          ...existing,
          affinityScore: existing.affinityScore + delta,
          positiveFeedbackCount:
            existing.positiveFeedbackCount + (delta > 0 ? 1 : 0),
          negativeFeedbackCount:
            existing.negativeFeedbackCount + (delta < 0 ? 1 : 0),
          lastFeedbackAt: now,
          updatedAt: now,
        }
      : {
          userId: input.userId,
          foodItemId,
          affinityScore: delta,
          positiveFeedbackCount: delta > 0 ? 1 : 0,
          negativeFeedbackCount: delta < 0 ? 1 : 0,
          lastFeedbackAt: now,
          updatedAt: now,
        };
    this.foodPreferences.set(key, preference);
    return preference;
  }

  private findFoodForFeedback(
    input: FoodFeedbackRecord,
  ): FoodItemRecord | undefined {
    if (!input.externalSource || !input.externalId) return undefined;
    return [...this.foods.values()].find(
      (food) =>
        food.externalSource === input.externalSource &&
        food.externalId === input.externalId &&
        (food.userId === undefined || food.userId === input.userId),
    );
  }

  async getUserFoodPreferences(userId: string): Promise<UserFoodPreference[]> {
    return [...this.foodPreferences.values()]
      .filter((preference) => preference.userId === userId)
      .sort(
        (a, b) =>
          b.affinityScore - a.affinityScore ||
          Date.parse(b.updatedAt) - Date.parse(a.updatedAt),
      );
  }

  async upsertFoodItemEmbedding(
    input: UpsertFoodItemEmbeddingInput,
  ): Promise<FoodItemEmbeddingRecord> {
    if (input.embedding.length !== ACTIVE_EMBEDDING_DIMENSIONS)
      throw new Error("invalid_embedding_dimensions");
    const now = new Date().toISOString();
    const key = input.foodItemId;
    const existing = this.foodEmbeddings.get(key);
    const record = {
      id: existing?.id ?? newId(),
      foodItemId: input.foodItemId,
      embeddedText: input.embeddedText,
      embeddedTextHash: input.embeddedTextHash,
      embedding: input.embedding,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    };
    this.foodEmbeddings.set(key, record);
    const { embedding: _embedding, ...publicRecord } = record;
    return publicRecord;
  }

  async getNutritionTarget(userId: string): Promise<NutritionSnapshot> {
    return (
      this.targets.get(userId) ?? {
        calories: 2200,
        proteinGrams: 0,
        carbsGrams: 0,
        fatGrams: 0,
      }
    );
  }

  async getDailyGoals(userId: string, date: string): Promise<DailyGoals> {
    return this.ensureDailyGoalSnapshot(userId, date, {
      target: await this.getNutritionTarget(userId),
      hydrationGoalLiters: this.hydrationGoals.get(userId) ?? 0,
      calorieTargetConfigured:
        this.calorieTargetConfigured.get(userId) ?? false,
      calorieTargetSource: this.calorieTargetSources.get(userId) ?? "default",
      ...this.currentMacroMetadata(userId),
    });
  }

  async updateDailyGoals(
    userId: string,
    input: UpdateDailyGoalsInput,
  ): Promise<DailyGoals> {
    const currentTarget = await this.getNutritionTarget(userId);
    const currentHydration = this.hydrationGoals.get(userId) ?? 0;
    const currentConfigured = this.calorieTargetConfigured.get(userId) ?? false;
    const currentSource = this.calorieTargetSources.get(userId) ?? "default";
    const currentMetadata = this.currentMacroMetadata(userId);
    for (const date of previousDatesInWeek(input.date)) {
      this.ensureDailyGoalSnapshot(userId, date, {
        target: currentTarget,
        hydrationGoalLiters: currentHydration,
        calorieTargetConfigured: currentConfigured,
        calorieTargetSource: currentSource,
        ...currentMetadata,
      });
    }

    const { target: nextTarget, metadata: nextMetadata } = applyMacroGoalUpdate(
      currentTarget,
      currentMetadata,
      input,
      input.calories ?? currentTarget.calories,
    );
    const nextHydration = input.hydrationGoalLiters ?? currentHydration;
    const nextConfigured =
      input.calories === undefined ? currentConfigured : true;
    const nextSource =
      input.calories === undefined
        ? currentSource
        : (input.calorieTargetSource ?? "manual");
    this.targets.set(userId, nextTarget);
    this.hydrationGoals.set(userId, nextHydration);
    this.calorieTargetConfigured.set(userId, nextConfigured);
    this.calorieTargetSources.set(userId, nextSource);
    this.macroGoalMetadata.set(userId, nextMetadata);
    const goals = {
      date: input.date,
      target: nextTarget,
      hydrationGoalLiters: nextHydration,
      calorieTargetConfigured: nextConfigured,
      calorieTargetSource: nextSource,
      ...nextMetadata,
    };
    this.dailyGoalSnapshots.set(dailyGoalKey(userId, input.date), goals);
    const waterKey = dailyGoalKey(userId, input.date);
    this.dailyWater.set(
      waterKey,
      Math.min(this.dailyWater.get(waterKey) ?? 0, nextHydration),
    );
    return goals;
  }

  async updateDailyHydration(
    userId: string,
    date: string,
    waterConsumedLiters: number,
  ): Promise<import("@cal-tracker/contracts").DailySummary> {
    const goals = await this.getDailyGoals(userId, date);
    this.dailyWater.set(
      dailyGoalKey(userId, date),
      Math.min(Math.max(waterConsumedLiters, 0), goals.hydrationGoalLiters),
    );
    return this.getDailySummary(userId, date);
  }

  async listMeals(userId: string, limit = 25): Promise<Meal[]> {
    return [...this.meals.values()]
      .filter((meal) => meal.userId === userId && !meal.deletedAt)
      .sort((a, b) => Date.parse(b.occurredAt) - Date.parse(a.occurredAt))
      .slice(0, limit)
      .map(({ userId: _userId, ...meal }) => meal);
  }

  async getMeal(userId: string, mealId: string): Promise<Meal | undefined> {
    const meal = this.meals.get(mealId);
    if (!meal || meal.userId !== userId || meal.deletedAt) return undefined;
    const { userId: _userId, ...publicMeal } = meal;
    return publicMeal;
  }

  async createProposal(
    userId: string,
    proposal: Omit<MealProposal, "id" | "createdAt">,
  ): Promise<MealProposal> {
    const stored = {
      ...proposal,
      id: newId(),
      createdAt: new Date().toISOString(),
      userId,
    };
    this.proposals.set(stored.id, stored);
    const { userId: _userId, ...publicProposal } = stored;
    return publicProposal;
  }

  async getProposal(
    userId: string,
    proposalId: string,
  ): Promise<MealProposal | undefined> {
    const proposal = this.proposals.get(proposalId);
    if (!proposal || proposal.userId !== userId) return undefined;
    const { userId: _userId, ...publicProposal } = proposal;
    return publicProposal;
  }

  async updateProposal(
    userId: string,
    proposal: MealProposal,
  ): Promise<MealProposal> {
    const existing = this.proposals.get(proposal.id);
    if (!existing || existing.userId !== userId)
      throw new Error("proposal_not_found");
    this.proposals.set(proposal.id, { ...proposal, userId });
    return proposal;
  }

  async createMealFromProposal(
    userId: string,
    proposal: MealProposal,
    occurredAt: string,
    items = proposal.items,
    mealLabel?: MealLabel | null,
  ): Promise<Meal> {
    const nutrition = sumNutrition(items);
    const meal: Meal & { userId: string } = {
      id: newId(),
      title: proposal.title,
      occurredAt,
      mealLabel: mealLabel ?? null,
      nutrition,
      items,
      createdAt: new Date().toISOString(),
      userId,
    };
    this.meals.set(meal.id, meal);
    const updatedProposal = { ...proposal, status: "committed" as const };
    await this.updateProposal(userId, updatedProposal);
    const { userId: _userId, ...publicMeal } = meal;
    return publicMeal;
  }

  async updateMeal(userId: string, meal: Meal): Promise<Meal> {
    const existing = this.meals.get(meal.id);
    if (!existing || existing.userId !== userId)
      throw new Error("meal_not_found");
    this.meals.set(meal.id, { ...meal, userId });
    return meal;
  }

  async softDeleteMeal(userId: string, mealId: string): Promise<boolean> {
    const meal = this.meals.get(mealId);
    if (!meal || meal.userId !== userId || meal.deletedAt) return false;
    meal.deletedAt = new Date().toISOString();
    return true;
  }

  async getDailySummary(
    userId: string,
    date: string,
  ): Promise<import("@cal-tracker/contracts").DailySummary> {
    const meals = (await this.listMeals(userId, 100)).filter(
      (meal) => meal.occurredAt.slice(0, 10) === date,
    );
    const consumed = meals.reduce(
      (total, meal) => ({
        calories: total.calories + meal.nutrition.calories,
        proteinGrams:
          Math.round((total.proteinGrams + meal.nutrition.proteinGrams) * 10) /
          10,
        carbsGrams:
          Math.round((total.carbsGrams + meal.nutrition.carbsGrams) * 10) / 10,
        fatGrams:
          Math.round((total.fatGrams + meal.nutrition.fatGrams) * 10) / 10,
      }),
      { calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0 },
    );
    const goals = await this.getDailyGoals(userId, date);
    return {
      date,
      consumed,
      target: goals.target,
      remaining: subtractNutrition(goals.target, consumed),
      hydrationGoalLiters: goals.hydrationGoalLiters,
      waterConsumedLiters: this.dailyWater.get(dailyGoalKey(userId, date)) ?? 0,
      calorieTargetConfigured: goals.calorieTargetConfigured,
      calorieTargetSource: goals.calorieTargetSource,
      macroMode: goals.macroMode,
      macroSource: goals.macroSource,
      macroPreset: goals.macroPreset,
      proteinPct: goals.proteinPct,
      carbsPct: goals.carbsPct,
      fatPct: goals.fatPct,
      macroCalories: goals.macroCalories,
      calorieDeltaKcal: goals.calorieDeltaKcal,
      meals,
    };
  }

  async listTemplates(userId: string): Promise<MealTemplate[]> {
    return [...this.templates.values()]
      .filter((template) => template.userId === userId)
      .map(({ userId: _userId, ...template }) => template);
  }

  async createTemplate(
    userId: string,
    input: Omit<MealTemplate, "id">,
  ): Promise<MealTemplate> {
    const stored = { ...input, id: newId(), userId };
    this.templates.set(stored.id, stored);
    for (const alias of input.aliases) {
      await this.createMemory({
        userId,
        normalizedText: normalizeText(alias),
        label: alias,
        templateId: stored.id,
        confidence: 1,
      });
    }
    const { userId: _userId, ...template } = stored;
    return template;
  }

  async updateTemplate(
    userId: string,
    template: MealTemplate,
  ): Promise<MealTemplate> {
    const existing = this.templates.get(template.id);
    if (!existing || existing.userId !== userId)
      throw new Error("template_not_found");
    this.templates.set(template.id, { ...template, userId });
    for (const [id, memory] of this.memories) {
      if (memory.userId === userId && memory.templateId === template.id) {
        this.memories.delete(id);
      }
    }
    for (const alias of template.aliases) {
      await this.createMemory({
        userId,
        normalizedText: normalizeText(alias),
        label: alias,
        templateId: template.id,
        confidence: 1,
      });
    }
    return template;
  }

  async deleteTemplate(userId: string, templateId: string): Promise<boolean> {
    const existing = this.templates.get(templateId);
    if (!existing || existing.userId !== userId) return false;
    this.templates.delete(templateId);
    return true;
  }

  async queryMemory(
    userId: string,
    normalizedText: string,
  ): Promise<MemoryMatch[]> {
    const exact = [...this.memories.values()].filter(
      (memory) =>
        memory.userId === userId && memory.normalizedText === normalizedText,
    );
    const fuzzy = [...this.memories.values()].filter(
      (memory) =>
        memory.userId === userId &&
        memory.normalizedText !== normalizedText &&
        (normalizedText.includes(memory.normalizedText) ||
          memory.normalizedText.includes(normalizedText)),
    );
    return [...exact, ...fuzzy].map((memory) => {
      const template = memory.templateId
        ? this.templates.get(memory.templateId)
        : undefined;
      return {
        id: memory.id,
        userId,
        label: memory.label,
        normalizedText: memory.normalizedText,
        confidence:
          exact.includes(memory) ||
          normalizedText.includes(memory.normalizedText)
            ? memory.confidence
            : Math.min(memory.confidence, 0.82),
        template: template ? stripUserId(template) : null,
      };
    });
  }

  async createMemory(input: {
    userId: string;
    normalizedText: string;
    label: string;
    templateId?: string;
    confidence: number;
  }): Promise<void> {
    this.memories.set(`${input.userId}:${input.normalizedText}`, {
      id: newId(),
      usageCount: 0,
      ...input,
    });
  }

  async createAgentConversation(
    userId: string,
    input: { title?: string } = {},
  ): Promise<AgentConversationRecord> {
    this.requireUser(userId);
    const now = new Date().toISOString();
    const conversation: AgentConversationRecord = {
      id: newId(),
      userId,
      title: input.title?.trim() || "New chat",
      createdAt: now,
      updatedAt: now,
    };
    this.agentConversations.set(conversation.id, conversation);
    this.agentConversationMessages.set(conversation.id, []);
    return conversation;
  }

  async getAgentConversation(
    userId: string,
    conversationId: string,
  ): Promise<AgentConversationRecord | undefined> {
    const conversation = this.agentConversations.get(conversationId);
    return conversation?.userId === userId ? conversation : undefined;
  }

  async listAgentConversations(
    userId: string,
    limit = 25,
  ): Promise<AgentConversationRecord[]> {
    return [...this.agentConversations.values()]
      .filter((conversation) => conversation.userId === userId)
      .sort((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt))
      .slice(0, limit);
  }

  async addAgentConversationMessage(
    userId: string,
    conversationId: string,
    input: Omit<
      AgentConversationMessageRecord,
      "id" | "conversationId" | "userId" | "createdAt"
    >,
  ): Promise<AgentConversationMessageRecord> {
    const conversation = await this.getAgentConversation(
      userId,
      conversationId,
    );
    if (!conversation) throw new Error("agent_conversation_not_found");
    const now = new Date().toISOString();
    const message: AgentConversationMessageRecord = {
      ...input,
      id: newId(),
      conversationId,
      userId,
      createdAt: now,
    };
    const messages = this.agentConversationMessages.get(conversationId) ?? [];
    messages.push(message);
    this.agentConversationMessages.set(conversationId, messages);
    this.agentConversations.set(conversationId, {
      ...conversation,
      updatedAt: now,
    });
    return message;
  }

  async listAgentConversationMessages(
    userId: string,
    conversationId: string,
  ): Promise<AgentConversationMessageRecord[]> {
    const conversation = await this.getAgentConversation(
      userId,
      conversationId,
    );
    if (!conversation) return [];
    return [...(this.agentConversationMessages.get(conversationId) ?? [])];
  }

  async deleteAgentConversation(
    userId: string,
    conversationId: string,
  ): Promise<boolean> {
    const conversation = await this.getAgentConversation(
      userId,
      conversationId,
    );
    if (!conversation) return false;
    this.agentConversations.delete(conversationId);
    this.agentConversationMessages.delete(conversationId);
    return true;
  }

  async recordActionCall(
    input: Omit<ActionCallRecord, "id" | "createdAt">,
  ): Promise<ActionCallRecord> {
    const record = {
      ...input,
      id: newId(),
      createdAt: new Date().toISOString(),
    };
    this.actionCalls.push(record);
    return record;
  }

  async recordAuditEvent(
    input: Omit<AuditEventRecord, "id" | "createdAt">,
  ): Promise<AuditEventRecord> {
    const record = {
      ...input,
      id: newId(),
      createdAt: new Date().toISOString(),
    };
    this.auditEvents.push(record);
    return record;
  }

  async listActionCalls(userId: string): Promise<ActionCallRecord[]> {
    return this.actionCalls.filter((call) => call.userId === userId);
  }

  async listAuditEvents(userId: string): Promise<AuditEventRecord[]> {
    return this.auditEvents.filter((event) => event.userId === userId);
  }

  async createTelemetryEvent(
    input: Omit<TelemetryEventRecord, "id" | "createdAt">,
  ): Promise<TelemetryEventRecord> {
    const record: TelemetryEventRecord = {
      ...input,
      id: newId(),
      createdAt: new Date().toISOString(),
    };
    this.telemetryEvents.push(record);
    return record;
  }

  async listTelemetryEvents(
    filter: TelemetryEventFilter,
  ): Promise<TelemetryEventRecord[]> {
    const rows = this.telemetryEvents.filter((event) => {
      if (filter.severity && event.severity !== filter.severity) return false;
      if (filter.eventType && event.eventType !== filter.eventType)
        return false;
      if (filter.surface && event.surface !== filter.surface) return false;
      if (filter.traceId && event.traceId !== filter.traceId) return false;
      if (filter.userId && event.userId !== filter.userId) return false;
      if (filter.from && event.createdAt < filter.from) return false;
      if (filter.to && event.createdAt > filter.to) return false;
      return true;
    });
    rows.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
    return filter.limit !== undefined ? rows.slice(0, filter.limit) : rows;
  }

  async createLlmRun(
    input: Omit<LlmRunRecord, "id" | "createdAt">,
  ): Promise<LlmRunRecord> {
    const record: LlmRunRecord = {
      ...input,
      id: newId(),
      createdAt: new Date().toISOString(),
    };
    this.llmRuns.push(record);
    return record;
  }

  async listLlmRuns(filter: LlmRunFilter): Promise<LlmRunRecord[]> {
    const rows = this.llmRuns.filter((run) => {
      if (filter.resultKind && run.resultKind !== filter.resultKind)
        return false;
      if (filter.selectedTool && run.selectedTool !== filter.selectedTool)
        return false;
      if (filter.executedTool && run.executedTool !== filter.executedTool)
        return false;
      if (filter.traceId && run.traceId !== filter.traceId) return false;
      if (filter.userId && run.userId !== filter.userId) return false;
      if (filter.from && run.createdAt < filter.from) return false;
      if (filter.to && run.createdAt > filter.to) return false;
      return true;
    });
    rows.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
    return filter.limit !== undefined ? rows.slice(0, filter.limit) : rows;
  }

  async createFoodSearchEvent(
    input: Omit<FoodSearchEventRecord, "id" | "createdAt">,
  ): Promise<FoodSearchEventRecord> {
    const record: FoodSearchEventRecord = {
      ...input,
      id: newId(),
      createdAt: new Date().toISOString(),
    };
    this.foodSearchEvents.push(record);
    return record;
  }

  async listFoodSearchEvents(
    filter: FoodSearchEventFilter,
  ): Promise<FoodSearchEventRecord[]> {
    const rows = this.foodSearchEvents.filter((event) => {
      if (
        filter.zeroResults !== undefined &&
        event.zeroResults !== filter.zeroResults
      )
        return false;
      if (
        filter.lowConfidence !== undefined &&
        event.lowConfidence !== filter.lowConfidence
      )
        return false;
      if (filter.path && event.path !== filter.path) return false;
      if (filter.traceId && event.traceId !== filter.traceId) return false;
      if (filter.userId && event.userId !== filter.userId) return false;
      if (filter.from && event.createdAt < filter.from) return false;
      if (filter.to && event.createdAt > filter.to) return false;
      return true;
    });
    rows.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
    return filter.limit !== undefined ? rows.slice(0, filter.limit) : rows;
  }

  async getTelemetryOverview(input: {
    from: string;
    to: string;
  }): Promise<TelemetryOverview> {
    const inRange = (iso: string) => iso >= input.from && iso <= input.to;
    const events = this.telemetryEvents.filter((e) => inRange(e.createdAt));
    const llmRuns = this.llmRuns.filter((r) => inRange(r.createdAt));
    const foodSearches = this.foodSearchEvents.filter((s) =>
      inRange(s.createdAt),
    );
    const eventsBySeverity: Record<string, number> = {};
    const eventsBySurface: Record<string, number> = {};
    const userIds = new Set<string>();
    const traceIds = new Set<string>();
    for (const event of events) {
      eventsBySeverity[event.severity] =
        (eventsBySeverity[event.severity] ?? 0) + 1;
      eventsBySurface[event.surface] =
        (eventsBySurface[event.surface] ?? 0) + 1;
      traceIds.add(event.traceId);
      if (event.userId) userIds.add(event.userId);
    }
    for (const run of llmRuns) {
      traceIds.add(run.traceId);
      if (run.userId) userIds.add(run.userId);
    }
    for (const search of foodSearches) {
      traceIds.add(search.traceId);
      if (search.userId) userIds.add(search.userId);
    }
    const recentResultKinds: Record<string, number> = {};
    for (const run of llmRuns) {
      if (!run.resultKind) continue;
      recentResultKinds[run.resultKind] =
        (recentResultKinds[run.resultKind] ?? 0) + 1;
    }
    const denominator = foodSearches.length || 1;
    const zeroResultCount = foodSearches.filter((s) => s.zeroResults).length;
    const lowConfidenceCount = foodSearches.filter(
      (s) => s.lowConfidence,
    ).length;
    const providerErrorCount = llmRuns.filter((r) => r.providerError).length;
    const llmDenominator = llmRuns.length || 1;
    return {
      from: input.from,
      to: input.to,
      totalEvents: events.length,
      totalLlmRuns: llmRuns.length,
      totalFoodSearchEvents: foodSearches.length,
      uniqueUsers: userIds.size,
      uniqueTraces: traceIds.size,
      eventsBySeverity,
      eventsBySurface,
      recentResultKinds,
      zeroResultRate:
        foodSearches.length === 0 ? 0 : zeroResultCount / denominator,
      lowConfidenceRate:
        foodSearches.length === 0 ? 0 : lowConfidenceCount / denominator,
      providerErrorRate:
        llmRuns.length === 0 ? 0 : providerErrorCount / llmDenominator,
    };
  }

  private requireUser(userId: string): StoredUser {
    const user = this.users.get(userId);
    if (!user) throw new Error("user_not_found");
    return user;
  }

  private ensureDailyGoalSnapshot(
    userId: string,
    date: string,
    goals: Omit<DailyGoals, "date">,
  ): DailyGoals {
    const key = dailyGoalKey(userId, date);
    const existing = this.dailyGoalSnapshots.get(key);
    if (existing) return existing;
    const snapshot = { date, ...goals };
    this.dailyGoalSnapshots.set(key, snapshot);
    return snapshot;
  }

  private currentMacroMetadata(userId: string): MacroGoalMetadata {
    return this.macroGoalMetadata.get(userId) ?? {};
  }
}

function stripUserId<T extends { userId: string }>(
  value: T,
): Omit<T, "userId"> {
  const { userId: _userId, ...rest } = value;
  return rest;
}

function dailyGoalKey(userId: string, date: string) {
  return `${userId}:${date}`;
}

function previousDatesInWeek(date: string): string[] {
  const current = new Date(`${date}T00:00:00.000Z`);
  const day = current.getUTCDay() === 0 ? 7 : current.getUTCDay();
  const dates: string[] = [];
  for (let offset = day - 1; offset > 0; offset--) {
    const value = new Date(current);
    value.setUTCDate(current.getUTCDate() - offset);
    dates.push(value.toISOString().slice(0, 10));
  }
  return dates;
}

function stripFoodSearchCandidate(
  candidate: FoodSearchCandidate,
): FoodItemRecord {
  const {
    lexicalScore: _lexicalScore,
    vectorScore: _vectorScore,
    preferenceScore: _preferenceScore,
    finalScore: _finalScore,
    ...food
  } = candidate;
  return food;
}

function foodRecordToUsualFood(food: FoodItemRecord): UsualFood {
  const nutrients = publicNutrients(food.nutrients);
  return {
    id: food.id,
    name: food.name,
    canonicalName: food.canonicalName,
    brand: food.brand,
    barcode: food.barcode,
    servingGrams: food.servingGrams,
    nutrition: {
      calories: food.calories,
      proteinGrams: food.proteinGrams,
      carbsGrams: food.carbsGrams,
      fatGrams: food.fatGrams,
    },
    ...(Object.keys(nutrients).length > 0 ? { nutrients } : {}),
    aliases: aliasesFromNutrients(food.nutrients),
    createdAt: food.createdAt,
    updatedAt: food.updatedAt,
  };
}

function nutrientsWithAliases(
  nutrients: Record<string, unknown> | undefined,
  aliases: string[] | undefined,
): Record<string, unknown> {
  const next = publicNutrients(nutrients);
  const normalizedAliases = uniqueStrings(
    (aliases ?? []).map((alias) => alias.trim()).filter(Boolean),
  );
  if (normalizedAliases.length > 0)
    next[USUAL_FOOD_ALIASES_KEY] = normalizedAliases;
  return next;
}

function publicNutrients(
  nutrients: Record<string, unknown> | undefined,
): Record<string, unknown> {
  const next = { ...(nutrients ?? {}) };
  delete next[USUAL_FOOD_ALIASES_KEY];
  return next;
}

function aliasesFromNutrients(
  nutrients: Record<string, unknown> | undefined,
): string[] {
  const aliases = nutrients?.[USUAL_FOOD_ALIASES_KEY];
  if (!Array.isArray(aliases)) return [];
  return uniqueStrings(
    aliases
      .map(String)
      .map((alias) => alias.trim())
      .filter(Boolean),
  );
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values)];
}

function sanitizeLimit(limit?: number): number {
  if (!Number.isFinite(limit)) return DEFAULT_FOOD_SEARCH_LIMIT;
  return Math.max(
    1,
    Math.min(MAX_FOOD_SEARCH_LIMIT, Math.floor(limit as number)),
  );
}

function clampScore(score: number): number {
  return clamp(score, 0, 1);
}

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.max(min, Math.min(max, value));
}

function cosineSimilarity(left: number[], right: number[]): number {
  if (left.length !== right.length) return 0;
  let dot = 0;
  let leftMagnitude = 0;
  let rightMagnitude = 0;
  for (let index = 0; index < left.length; index += 1) {
    const leftValue = left[index] ?? 0;
    const rightValue = right[index] ?? 0;
    dot += leftValue * rightValue;
    leftMagnitude += leftValue * leftValue;
    rightMagnitude += rightValue * rightValue;
  }
  if (leftMagnitude === 0 || rightMagnitude === 0) return 0;
  return dot / (Math.sqrt(leftMagnitude) * Math.sqrt(rightMagnitude));
}

function foodFeedbackDelta(action: FoodFeedbackRecord["action"]): number {
  switch (action) {
    case "selected":
      return 1;
    case "logged":
      return 0.75;
    case "corrected":
      return 0.5;
    case "dismissed":
      return -0.5;
    case "rejected":
      return -1;
  }
}

function preferenceKey(userId: string, foodItemId: string): string {
  return `${userId}:${foodItemId}`;
}
