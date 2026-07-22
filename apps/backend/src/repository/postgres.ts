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
  type PermissionScope,
  type UpdateUsualFoodRequest,
  type UsualFood,
} from "@cal-tracker/contracts";
import { sql as dbSql, type SQL } from "drizzle-orm";
import { createDbClient, type AppDb, type AppDbClient } from "../db/client.js";
import { newId } from "../utils/ids.js";
import { applyMacroGoalUpdate } from "../utils/macroGoals.js";
import { withSpan, withSyncSpan } from "../observability/profiler.js";
import { normalizeText } from "../utils/normalize.js";
import { normalizedIdentityTokenKeys } from "../foodData/normalization.js";
import { subtractNutrition, sumNutrition } from "../utils/nutrition.js";
import { lexicalFoodScore } from "./foodSearchScoring.js";
import type {
  ActionCallRecord,
  AdminActionCallFilter,
  AdminConversationFilter,
  AgentToolCallTelemetryFilter,
  AgentToolCallTelemetryRecord,
  AgentToolExecutionRecord,
  AgentChatProposalCommit,
  AgentTurnTelemetryFilter,
  AgentTurnTelemetryRecord,
  AgentCandidateRegistryRecord,
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
  FoodPortionRecord,
  FoodSearchCandidate,
  FoodSearchEventFilter,
  FoodSearchEventRecord,
  LlmCostFilter,
  LlmCostOverview,
  LlmRunFilter,
  LlmRunRecord,
  LlmProviderCallFilter,
  LlmProviderCallRecord,
  MemoryMatch,
  PendingRegistrationRecord,
  PrivacyDeletionRequest,
  PrivacyLifecycleResult,
  StoredSession,
  StoredUser,
  TelemetryEventFilter,
  TelemetryEventRecord,
  TelemetryOverview,
  TranscriptionRecord,
  TranscriptionRecordFilter,
  UpsertFoodItemEmbeddingInput,
  UpdateDailyGoalsInput,
  UserFoodPreference,
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
const FOOD_SEARCH_CACHE_TTL_MS = 5 * 60 * 1000;
const FOOD_SEARCH_CACHE_MAX_ENTRIES = 500;
const USUAL_FOOD_SOURCE = "user_custom";
const USUAL_FOOD_ALIASES_KEY = "usualFoodAliases";

type FoodSearchProfile = {
  scope: "generic" | "market";
  locales: string[];
  continueAfterLimit?: boolean;
  scopeRank: number;
};

type NormalizedFoodSearchProfile = {
  locales: string[];
};

type FoodSearchRowCandidate = {
  row: Record<string, unknown>;
  lexicalScore: number;
  vectorScore?: number;
  scopeRank?: number;
};

type FoodSearchRankedCandidate = {
  candidate: FoodSearchCandidate;
  scopeRank: number;
};

type DbExecutor = {
  execute(query: SQL): Promise<unknown>;
};

type PostgresRepositoryOptions = {
  normalizedSearchEnabled?: boolean;
  normalizedSearchScope?: "sample" | "full";
  normalizedSearchSampleSet?: string;
};

export class PostgresRepository implements AppRepository {
  private readonly client: AppDbClient;
  private readonly db: AppDb;
  private readonly normalizedSearchEnabled: boolean;
  private readonly normalizedSearchScope: "sample" | "full";
  private readonly normalizedSearchSampleSet: string;
  private readonly foodSearchCache = new Map<
    string,
    { expiresAt: number; value: FoodSearchCandidate[] }
  >();

  constructor(databaseUrl: string, options: PostgresRepositoryOptions = {}) {
    this.client = createDbClient(databaseUrl);
    this.db = this.client.db;
    this.normalizedSearchEnabled = Boolean(options.normalizedSearchEnabled);
    this.normalizedSearchScope = options.normalizedSearchScope ?? "sample";
    this.normalizedSearchSampleSet =
      options.normalizedSearchSampleSet ?? "normalized_search_v1";
  }

  async close(): Promise<void> {
    await this.client.close();
  }

  private execute<T extends Record<string, unknown> = Record<string, unknown>>(
    query: SQL,
  ): Promise<T[]> {
    return executeRows(this.db, query);
  }

  async createUser(input: {
    email: string;
    displayName: string;
    passwordHash?: string;
    emailVerifiedAt?: string;
    scopes: PermissionScope[];
  }): Promise<StoredUser> {
    return this.db.transaction(async (tx) => {
      const emailVerifiedAt = input.emailVerifiedAt ?? new Date().toISOString();
      const [row] = await executeRows(
        tx,
        dbSql`
        INSERT INTO users (email, display_name, email_verified_at)
        VALUES (${input.email.toLowerCase()}, ${input.displayName}, ${emailVerifiedAt})
        RETURNING id, email, display_name, trusted_mode_enabled, email_verified_at, created_at
      `,
      );
      if (input.passwordHash) {
        await executeRows(
          tx,
          dbSql`INSERT INTO user_credentials (user_id, password_hash) VALUES (${row.id}, ${input.passwordHash})`,
        );
      }
      await executeRows(
        tx,
        dbSql`
        INSERT INTO nutrition_targets (
          user_id, calories, protein_grams, carbs_grams, fat_grams, hydration_goal_glasses, hydration_goal_liters,
          calorie_target_configured, calorie_target_source
        )
        VALUES (${row.id}, 2200, 0, 0, 0, 0, 0, false, 'default')
      `,
      );
      return this.mapUser(row, input.passwordHash, input.scopes);
    });
  }

  async findUserByEmail(email: string): Promise<StoredUser | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT u.id, u.email, u.display_name, u.trusted_mode_enabled, u.email_verified_at, u.created_at, c.password_hash
      FROM users u
      LEFT JOIN user_credentials c ON c.user_id = u.id
      WHERE lower(u.email) = lower(${email}) AND u.deleted_at IS NULL
    `);
    return row
      ? this.mapUser(
          row,
          row.password_hash as string | undefined,
          defaultUserScopes,
        )
      : undefined;
  }

  async findUserById(id: string): Promise<StoredUser | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT u.id, u.email, u.display_name, u.trusted_mode_enabled, u.email_verified_at, u.created_at, c.password_hash
      FROM users u
      LEFT JOIN user_credentials c ON c.user_id = u.id
      WHERE u.id = ${id} AND u.deleted_at IS NULL
    `);
    return row
      ? this.mapUser(
          row,
          row.password_hash as string | undefined,
          defaultUserScopes,
        )
      : undefined;
  }

  async updateTrustedMode(
    userId: string,
    enabled: boolean,
  ): Promise<StoredUser> {
    await this.execute(
      dbSql`UPDATE users SET trusted_mode_enabled = ${enabled} WHERE id = ${userId}`,
    );
    const user = await this.findUserById(userId);
    if (!user) throw new Error("user_not_found");
    return user;
  }

  async upsertPendingRegistration(input: {
    email: string;
    displayName: string;
    passwordHash: string;
    tokenHash: string;
    expiresAt: string;
  }): Promise<PendingRegistrationRecord> {
    return this.db.transaction(async (tx) => {
      await executeRows(
        tx,
        dbSql`
          UPDATE pending_registrations
          SET consumed_at = now(), updated_at = now()
          WHERE lower(email) = lower(${input.email}) AND consumed_at IS NULL
        `,
      );
      const [row] = await executeRows(
        tx,
        dbSql`
          INSERT INTO pending_registrations (email, display_name, password_hash, token_hash, expires_at)
          VALUES (${input.email.toLowerCase()}, ${input.displayName}, ${input.passwordHash}, ${input.tokenHash}, ${input.expiresAt})
          RETURNING *
        `,
      );
      return mapPendingRegistration(row);
    });
  }

  async findPendingRegistrationByEmail(
    email: string,
  ): Promise<PendingRegistrationRecord | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT *
      FROM pending_registrations
      WHERE lower(email) = lower(${email}) AND consumed_at IS NULL AND expires_at > now()
      ORDER BY created_at DESC
      LIMIT 1
    `);
    return row ? mapPendingRegistration(row) : undefined;
  }

  async consumePendingRegistration(
    tokenHash: string,
  ): Promise<PendingRegistrationRecord | undefined> {
    const [row] = await this.execute(dbSql`
      UPDATE pending_registrations
      SET consumed_at = now(), updated_at = now()
      WHERE token_hash = ${tokenHash} AND consumed_at IS NULL AND expires_at > now()
      RETURNING *
    `);
    return row ? mapPendingRegistration(row) : undefined;
  }

  async findAuthIdentity(
    provider: AuthIdentityProvider,
    providerUserId: string,
  ): Promise<AuthIdentityRecord | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT id, user_id, provider, provider_user_id, email, created_at, updated_at
      FROM auth_identities
      WHERE provider = ${provider} AND provider_user_id = ${providerUserId}
      LIMIT 1
    `);
    return row ? mapAuthIdentity(row) : undefined;
  }

  async linkAuthIdentity(input: {
    userId: string;
    provider: AuthIdentityProvider;
    providerUserId: string;
    email: string;
  }): Promise<AuthIdentityRecord> {
    const [row] = await this.execute(dbSql`
      INSERT INTO auth_identities (user_id, provider, provider_user_id, email)
      VALUES (${input.userId}, ${input.provider}, ${input.providerUserId}, ${input.email.toLowerCase()})
      ON CONFLICT (provider, provider_user_id)
      DO UPDATE SET email = EXCLUDED.email, updated_at = now()
      RETURNING id, user_id, provider, provider_user_id, email, created_at, updated_at
    `);
    return mapAuthIdentity(row);
  }

  async createSession(
    input: Omit<StoredSession, "createdAt">,
  ): Promise<StoredSession> {
    const [row] = await this.execute(dbSql`
      INSERT INTO auth_sessions (id, user_id, refresh_token_hash, expires_at, revoked_at, rotated_at)
      VALUES (${input.id}, ${input.userId}, ${input.refreshTokenHash}, ${input.expiresAt}, ${input.revokedAt ?? null}, ${input.rotatedAt ?? null})
      RETURNING *
    `);
    return mapSession(row);
  }

  async findSessionByRefreshTokenHash(
    hash: string,
  ): Promise<StoredSession | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT * FROM auth_sessions
      WHERE refresh_token_hash = ${hash} AND revoked_at IS NULL AND expires_at > now()
      LIMIT 1
    `);
    return row ? mapSession(row) : undefined;
  }

  async revokeSession(sessionId: string): Promise<void> {
    await this.execute(
      dbSql`UPDATE auth_sessions SET revoked_at = now() WHERE id = ${sessionId}`,
    );
  }

  async revokeAllSessions(userId: string): Promise<void> {
    await this.execute(
      dbSql`UPDATE auth_sessions SET revoked_at = now() WHERE user_id = ${userId} AND revoked_at IS NULL`,
    );
  }

  async rotateSession(
    sessionId: string,
    nextHash: string,
    expiresAt: string,
  ): Promise<StoredSession | undefined> {
    const [row] = await this.execute(dbSql`
      UPDATE auth_sessions
      SET refresh_token_hash = ${nextHash}, expires_at = ${expiresAt}, rotated_at = now()
      WHERE id = ${sessionId} AND revoked_at IS NULL AND expires_at > now()
      RETURNING *
    `);
    return row ? mapSession(row) : undefined;
  }

  async createPasswordReset(input: {
    userId: string;
    tokenHash: string;
    expiresAt: string;
  }): Promise<void> {
    await this.execute(dbSql`
      INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
      VALUES (${input.userId}, ${input.tokenHash}, ${input.expiresAt})
    `);
  }

  async consumePasswordReset(
    tokenHash: string,
    newPasswordHash: string,
  ): Promise<boolean> {
    return this.db.transaction(async (tx) => {
      const [reset] = await executeRows(
        tx,
        dbSql`
        UPDATE password_reset_tokens
        SET used_at = now()
        WHERE token_hash = ${tokenHash} AND used_at IS NULL AND expires_at > now()
        RETURNING user_id
      `,
      );
      if (!reset) return false;
      await executeRows(
        tx,
        dbSql`
          INSERT INTO user_credentials (user_id, password_hash)
          VALUES (${reset.user_id}, ${newPasswordHash})
          ON CONFLICT (user_id)
          DO UPDATE SET password_hash = EXCLUDED.password_hash, updated_at = now()
        `,
      );
      await executeRows(
        tx,
        dbSql`
          UPDATE auth_sessions
          SET revoked_at = now()
          WHERE user_id = ${reset.user_id} AND revoked_at IS NULL
        `,
      );
      await executeRows(
        tx,
        dbSql`
          INSERT INTO audit_events (user_id, event_type, metadata_json, trace_id)
          VALUES (
            ${reset.user_id},
            'auth.password_reset_completed',
            ${jsonb({ sessionRevocation: "all" })},
            'auth-reset-confirm'
          )
        `,
      );
      return true;
    });
  }

  async listFoods(userId: string): Promise<FoodItemRecord[]> {
    const rows = await this.execute(
      dbSql`SELECT * FROM food_items WHERE deleted_at IS NULL AND (user_id IS NULL OR user_id = ${userId})`,
    );
    return this.mapFoodsWithPortions(rows);
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
    return withSpan(
      "PostgresRepository.searchFoodsHybrid",
      {
        query: input.query,
        hasBarcode: Boolean(input.barcode),
        hasEmbedding: Boolean(input.embedding),
        limit: input.limit,
      },
      () => this.searchFoodsHybridInternal(userId, input),
    );
  }

  private async searchFoodsHybridInternal(
    userId: string,
    input: FoodHybridSearchInput,
  ): Promise<FoodSearchCandidate[]> {
    const limit = sanitizeLimit(input.limit);
    const normalized = normalizeText(input.query);
    const cacheKey = foodSearchCacheKey(userId, input, normalized, limit);
    const cached = this.getCachedFoodSearch(cacheKey);
    if (cached) return cached.map(cloneFoodSearchCandidate);

    const candidateRows = new Map<string, FoodSearchRowCandidate>();
    if (this.normalizedSearchEnabled) {
      const rows = await this.searchNormalizedFoodDocuments(
        userId,
        input,
        normalized,
        limit,
      );
      for (const row of rows) {
        mergeFoodSearchRowCandidate(candidateRows, {
          row,
          lexicalScore: clampScore(Number(row.search_score ?? 0)),
          scopeRank: foodSearchScopeRankFromRow(row),
        });
      }
      if (candidateRows.size > 0) {
        return this.rankFoodSearchRows(
          userId,
          input,
          normalized,
          limit,
          candidateRows,
          cacheKey,
          true,
        );
      }
      // Fall through to legacy search path when normalized search finds nothing
      // This ensures user-custom foods (usual foods) in food_search_documents are found
    }

    if (input.barcode) {
      const barcode = input.barcode;
      const rows = await withSpan(
        "PostgresRepository.searchFoodsHybrid.barcodeQuery",
        { limit },
        () =>
          this.execute(dbSql`
        SELECT *, 1::float AS search_score
        FROM food_items
        WHERE deleted_at IS NULL AND (user_id IS NULL OR user_id = ${userId}) AND barcode = ${barcode}
        LIMIT ${limit}
      `),
      );
      for (const row of rows) {
        mergeFoodSearchRowCandidate(candidateRows, {
          row,
          lexicalScore: 1,
          scopeRank: foodSearchScopeRankFromRow(row),
        });
      }
    } else if (normalized.length > 0) {
      const rows = await this.searchFoodDocuments(
        userId,
        input,
        normalized,
        limit,
      );
      for (const row of rows) {
        mergeFoodSearchRowCandidate(candidateRows, {
          row,
          lexicalScore: clampScore(Number(row.search_score ?? 0)),
          scopeRank: foodSearchScopeRankFromRow(row),
        });
      }
    }

    if (candidateRows.size === 0 && !input.barcode && input.embedding) {
      const vectorLiteral = toVectorLiteral(input.embedding);
      const rows = await withSpan(
        "PostgresRepository.searchFoodsHybrid.vectorQuery",
        { limit: Math.max(limit, DEFAULT_FOOD_SEARCH_LIMIT) },
        () =>
          this.execute(dbSql`
        SELECT food_items.*,
               1 - (food_item_embeddings.embedding <=> ${vectorLiteral}::vector) AS vector_score
        FROM food_item_embeddings
        JOIN food_items ON food_items.id = food_item_embeddings.food_item_id
        WHERE food_items.deleted_at IS NULL
          AND (food_items.user_id IS NULL OR food_items.user_id = ${userId})
        ORDER BY food_item_embeddings.embedding <=> ${vectorLiteral}::vector
        LIMIT ${Math.max(limit, DEFAULT_FOOD_SEARCH_LIMIT)}
      `),
      );
      for (const row of rows) {
        const foodId = row.id as string;
        const existing = candidateRows.get(foodId);
        const vectorScore = clampScore(Number(row.vector_score ?? 0));
        if (existing) {
          existing.vectorScore = Math.max(
            existing.vectorScore ?? 0,
            vectorScore,
          );
        } else {
          candidateRows.set(foodId, { row, lexicalScore: 0, vectorScore });
        }
      }
    }

    if (candidateRows.size === 0) {
      this.setCachedFoodSearch(cacheKey, []);
      return [];
    }
    return this.rankFoodSearchRows(
      userId,
      input,
      normalized,
      limit,
      candidateRows,
      cacheKey,
      false,
    );
  }

  private async rankFoodSearchRows(
    userId: string,
    input: FoodHybridSearchInput,
    normalized: string,
    limit: number,
    candidateRows: Map<string, FoodSearchRowCandidate>,
    cacheKey: string,
    useStoredLexicalScore: boolean,
  ): Promise<FoodSearchCandidate[]> {
    const merged = [...candidateRows.values()];
    const foods = await withSpan(
      "PostgresRepository.mapFoodsWithPortions",
      { rowCount: merged.length },
      () => this.mapFoodsWithPortions(merged.map((candidate) => candidate.row)),
    );
    const scoresByFoodId = new Map(
      merged.map((candidate) => [candidate.row.id as string, candidate]),
    );
    const preferenceScores = await withSpan(
      "PostgresRepository.getPreferenceScoreMap",
      { foodCount: foods.length },
      () =>
        this.getPreferenceScoreMap(
          userId,
          foods.map((food) => food.id),
        ),
    );

    const ranked = withSyncSpan(
      "PostgresRepository.rankFoodCandidates",
      { foodCount: foods.length, limit },
      () =>
        foods
          .map<FoodSearchRankedCandidate>((food) => {
            const scores = scoresByFoodId.get(food.id);
            const computedLexicalScore =
              normalized.length > 0 && !input.barcode
                ? lexicalFoodScore(food, normalized)
                : 0;
            const rawLexicalScore = useStoredLexicalScore
              ? (scores?.lexicalScore ?? computedLexicalScore)
              : computedLexicalScore > 0
                ? computedLexicalScore
                : (scores?.lexicalScore ?? 0);
            const lexicalScore = clampScore(rawLexicalScore);
            const vectorScore =
              scores?.vectorScore == null
                ? undefined
                : clampScore(scores.vectorScore);
            const preferenceScore = clamp(
              (preferenceScores.get(food.id) ?? 0) /
                PREFERENCE_SCORE_NORMALIZER,
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
              candidate: {
                ...food,
                lexicalScore,
                vectorScore,
                preferenceScore,
                finalScore: clampScore(
                  baseScore +
                    preferenceScore * PREFERENCE_SCORE_WEIGHT +
                    userFoodBoost,
                ),
              },
              scopeRank: foodSearchScopeRankForSort(input, scores?.scopeRank),
            };
          })
          .sort(compareFoodSearchRankedCandidates)
          .map((entry) => entry.candidate)
          .slice(0, limit),
    );
    this.setCachedFoodSearch(cacheKey, ranked);
    return ranked.map(cloneFoodSearchCandidate);
  }

  private async searchNormalizedFoodDocuments(
    userId: string,
    input: FoodHybridSearchInput,
    normalized: string,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    if (input.barcode) {
      const rows = await withSpan(
        "PostgresRepository.searchFoodsHybrid.normalizedBarcodeQuery",
        { limit, sampleSet: this.normalizedSearchSampleSet },
        () =>
          this.execute(dbSql`
          SELECT food_items.*,
                 food_normalized_search_documents.display_name AS search_display_name,
                 food_normalized_search_documents.display_name AS search_normalized_display_name,
                 food_normalized_search_documents.base_name AS search_normalized_base_name,
                 food_normalized_search_documents.variant_name AS search_normalized_variant_name,
                 food_normalized_search_documents.result_type AS search_normalized_result_type,
                 food_normalized_search_documents.brand_display AS search_normalized_brand_display,
                 food_normalized_search_documents.primary_entity_name AS search_primary_entity_name,
                 food_normalized_search_documents.primary_entity_aliases AS search_primary_entity_aliases,
                 food_normalized_search_documents.secondary_entity_aliases AS search_secondary_entity_aliases,
                 food_normalized_search_documents.primary_entity_category AS search_primary_entity_category,
                 food_normalized_search_documents.primary_entity_category_coherence AS search_primary_entity_category_coherence,
                 food_normalized_search_documents.primary_entity_representativeness AS search_primary_entity_representativeness,
                 food_normalized_search_documents.metadata AS search_normalized_metadata,
                 0::int AS search_scope_rank,
                 1::float AS search_score
          FROM food_normalized_search_documents
          JOIN food_items ON food_items.id = food_normalized_search_documents.food_item_id
          JOIN food_item_quality ON food_item_quality.food_item_id = food_items.id
          JOIN food_normalization_review ON food_normalization_review.food_item_id = food_items.id
            AND food_normalization_review.normalization_version = food_normalized_search_documents.normalization_version
          ${this.normalizedFoodSearchSampleJoinSql()}
          WHERE (food_normalized_search_documents.user_id IS NULL OR food_normalized_search_documents.user_id = ${userId})
            AND food_item_quality.is_search_eligible
            AND food_normalization_review.review_status = 'valid'
            ${this.normalizedFoodSearchSamplePredicateSql()}
            AND food_items.barcode = ${input.barcode}
          ORDER BY
            CASE WHEN food_normalized_search_documents.user_id = ${userId} THEN 0 ELSE 1 END,
            food_normalized_search_documents.rank_bucket,
            food_normalized_search_documents.display_name
          LIMIT ${limit}
        `),
      );
      return rows;
    }
    if (normalized.length === 0) return [];

    const profile = normalizedFoodSearchProfile(input);
    return withSpan(
      "PostgresRepository.searchFoodsHybrid.normalizedDocumentQuery",
      {
        limit: normalizedFoodSearchLimit(limit),
        locales: profile.locales,
        sampleSet: this.normalizedSearchSampleSet,
      },
      () =>
        this.queryNormalizedFoodDocuments(userId, normalized, profile, limit),
    );
  }

  private async queryNormalizedFoodDocuments(
    userId: string,
    normalized: string,
    profile: NormalizedFoodSearchProfile,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const queryIdentityKey = normalizedIdentityTokenKeys([normalized])[0];
    const strongRows = await this.queryNormalizedFoodDocumentsStrongIdentity(
      userId,
      normalized,
      queryIdentityKey,
      profile,
      limit,
    );
    if (normalizedStrongIdentityCanShortCircuit(strongRows, limit))
      return strongRows;
    const textRows = await this.queryNormalizedFoodDocumentsText(
      userId,
      normalized,
      queryIdentityKey,
      profile,
      limit,
    );
    const mergedRows = mergeNormalizedFoodDocumentRows(
      limit * 2,
      strongRows,
      textRows,
    );
    if (mergedRows.length > 0) return mergedRows;
    const fuzzyRows = await this.queryNormalizedFoodDocumentsFuzzy(
      userId,
      normalized,
      queryIdentityKey,
      profile,
      limit,
    );
    return fuzzyRows;
  }

  private normalizedFoodSearchSampleJoinSql(): SQL {
    if (this.normalizedSearchScope === "full") return dbSql``;
    return dbSql`
      JOIN food_normalization_sample_items ON food_normalization_sample_items.food_item_id = food_items.id
      JOIN food_normalization_sample_sets ON food_normalization_sample_sets.id = food_normalization_sample_items.sample_set_id
    `;
  }

  private normalizedFoodSearchSamplePredicateSql(): SQL {
    if (this.normalizedSearchScope === "full") return dbSql``;
    return dbSql`AND food_normalization_sample_sets.name = ${this.normalizedSearchSampleSet}`;
  }

  private async queryNormalizedFoodDocumentsStrongIdentity(
    userId: string,
    normalized: string,
    queryIdentityKey: string | undefined,
    profile: NormalizedFoodSearchProfile,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const tokenRows = queryIdentityKey
      ? await this.queryNormalizedFoodDocumentsStrongIdentityRows(
          userId,
          normalized,
          queryIdentityKey,
          profile,
          limit,
          normalizedFoodIdentityTokenKeyPredicateSql(queryIdentityKey),
        )
      : [];
    if (normalizedStrongIdentityCanShortCircuit(tokenRows, limit))
      return tokenRows;
    const broadRows = await this.queryNormalizedFoodDocumentsStrongIdentityRows(
      userId,
      normalized,
      queryIdentityKey,
      profile,
      limit,
      normalizedFoodStrongIdentityPredicateSql(normalized, undefined),
    );
    return mergeNormalizedFoodDocumentRows(limit * 2, tokenRows, broadRows);
  }

  private async queryNormalizedFoodDocumentsStrongIdentityRows(
    userId: string,
    normalized: string,
    queryIdentityKey: string | undefined,
    profile: NormalizedFoodSearchProfile,
    limit: number,
    predicate: SQL,
  ): Promise<Record<string, unknown>[]> {
    const searchLimit = normalizedFoodSearchLimit(limit);
    const searchScore = normalizedFoodTextSearchScoreSql(
      normalized,
      queryIdentityKey,
    );
    const locale0 = profile.locales[0] ?? "any";
    const locale1 = profile.locales[1] ?? locale0;
    const locale2 = profile.locales[2] ?? locale1;
    const locale3 = profile.locales[3] ?? locale2;
    return this.execute(dbSql`
      WITH base_rows AS (
        SELECT food_items.*,
               food_normalized_search_documents.display_name AS search_display_name,
               food_normalized_search_documents.display_name AS search_normalized_display_name,
               food_normalized_search_documents.base_name AS search_normalized_base_name,
               food_normalized_search_documents.variant_name AS search_normalized_variant_name,
               food_normalized_search_documents.result_type AS search_normalized_result_type,
               food_normalized_search_documents.brand_display AS search_normalized_brand_display,
               food_normalized_search_documents.primary_entity_name AS search_primary_entity_name,
               food_normalized_search_documents.primary_entity_aliases AS search_primary_entity_aliases,
               food_normalized_search_documents.secondary_entity_aliases AS search_secondary_entity_aliases,
               food_normalized_search_documents.primary_entity_category AS search_primary_entity_category,
               food_normalized_search_documents.primary_entity_category_coherence AS search_primary_entity_category_coherence,
               food_normalized_search_documents.primary_entity_representativeness AS search_primary_entity_representativeness,
               food_normalized_search_documents.metadata AS search_normalized_metadata,
               ${searchScore} AS search_score_base,
               LEAST(
                 0.04::float,
                 GREATEST(
                   count(*) OVER (PARTITION BY lower(food_normalized_search_documents.display_name))::float - 1::float,
                   0::float
                 ) * 0.002::float
               ) AS search_display_frequency_bonus,
               CASE WHEN food_normalized_search_documents.user_id = ${userId} THEN 0 ELSE 1 END AS search_user_rank,
               CASE
                 WHEN food_normalized_search_documents.locale = ${locale0} THEN 0
                 WHEN food_normalized_search_documents.locale = ${locale1} THEN 1
                 WHEN food_normalized_search_documents.locale = ${locale2} THEN 2
                 WHEN food_normalized_search_documents.locale = ${locale3} THEN 3
                 ELSE 4
               END AS search_locale_rank,
               CASE food_normalized_search_documents.result_type
                 WHEN 'generic_food' THEN 0
                 WHEN 'product' THEN 1
                 ELSE 2
               END AS search_result_type_rank,
               food_normalized_search_documents.rank_bucket AS search_rank_bucket,
               food_normalized_search_documents.normalization_confidence AS search_normalization_confidence
        FROM food_normalized_search_documents
        JOIN food_items ON food_items.id = food_normalized_search_documents.food_item_id
        JOIN food_item_quality ON food_item_quality.food_item_id = food_items.id
        JOIN food_normalization_review ON food_normalization_review.food_item_id = food_items.id
          AND food_normalization_review.normalization_version = food_normalized_search_documents.normalization_version
        ${this.normalizedFoodSearchSampleJoinSql()}
        WHERE (food_normalized_search_documents.user_id IS NULL OR food_normalized_search_documents.user_id = ${userId})
          AND food_item_quality.is_search_eligible
          AND food_normalization_review.review_status = 'valid'
          ${this.normalizedFoodSearchSamplePredicateSql()}
          AND food_normalized_search_documents.locale IN ${sqlList(profile.locales)}
          AND (${predicate})
      ),
      scored_rows AS (
        SELECT base_rows.*,
               LEAST(1::float, search_score_base + search_display_frequency_bonus) AS search_score
        FROM base_rows
      ),
      ranked_rows AS (
        SELECT scored_rows.*,
               row_number() OVER (
                 PARTITION BY lower(search_display_name)
                 ORDER BY
                   search_result_type_rank,
                   search_score DESC,
                   search_user_rank,
                   search_locale_rank,
                   search_rank_bucket,
                   search_normalization_confidence DESC,
                   id
               ) AS search_display_rank
        FROM scored_rows
      )
      SELECT *
      FROM ranked_rows
      WHERE search_display_rank = 1
      ORDER BY
        search_user_rank,
        search_result_type_rank,
        search_score DESC,
        search_locale_rank,
        search_rank_bucket,
        char_length(search_display_name),
        search_display_name
      LIMIT ${searchLimit}
    `);
  }

  private async queryNormalizedFoodDocumentsText(
    userId: string,
    normalized: string,
    queryIdentityKey: string | undefined,
    profile: NormalizedFoodSearchProfile,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const searchLimit = normalizedFoodSearchLimit(limit);
    const searchScore = normalizedFoodTextSearchScoreSql(
      normalized,
      queryIdentityKey,
    );
    const locale0 = profile.locales[0] ?? "any";
    const locale1 = profile.locales[1] ?? locale0;
    const locale2 = profile.locales[2] ?? locale1;
    const locale3 = profile.locales[3] ?? locale2;
    return this.execute(dbSql`
      WITH base_rows AS (
        SELECT food_items.*,
               food_normalized_search_documents.display_name AS search_display_name,
               food_normalized_search_documents.display_name AS search_normalized_display_name,
               food_normalized_search_documents.base_name AS search_normalized_base_name,
               food_normalized_search_documents.variant_name AS search_normalized_variant_name,
               food_normalized_search_documents.result_type AS search_normalized_result_type,
               food_normalized_search_documents.brand_display AS search_normalized_brand_display,
               food_normalized_search_documents.primary_entity_name AS search_primary_entity_name,
               food_normalized_search_documents.primary_entity_aliases AS search_primary_entity_aliases,
               food_normalized_search_documents.secondary_entity_aliases AS search_secondary_entity_aliases,
               food_normalized_search_documents.primary_entity_category AS search_primary_entity_category,
               food_normalized_search_documents.primary_entity_category_coherence AS search_primary_entity_category_coherence,
               food_normalized_search_documents.primary_entity_representativeness AS search_primary_entity_representativeness,
               food_normalized_search_documents.metadata AS search_normalized_metadata,
               ${searchScore} AS search_score_base,
               LEAST(
                 0.04::float,
                 GREATEST(
                   count(*) OVER (PARTITION BY lower(food_normalized_search_documents.display_name))::float - 1::float,
                   0::float
                 ) * 0.002::float
               ) AS search_display_frequency_bonus,
               CASE WHEN food_normalized_search_documents.user_id = ${userId} THEN 0 ELSE 1 END AS search_user_rank,
               CASE
                 WHEN food_normalized_search_documents.locale = ${locale0} THEN 0
                 WHEN food_normalized_search_documents.locale = ${locale1} THEN 1
                 WHEN food_normalized_search_documents.locale = ${locale2} THEN 2
                 WHEN food_normalized_search_documents.locale = ${locale3} THEN 3
                 ELSE 4
               END AS search_locale_rank,
               CASE food_normalized_search_documents.result_type
                 WHEN 'generic_food' THEN 0
                 WHEN 'product' THEN 1
                 ELSE 2
               END AS search_result_type_rank,
               food_normalized_search_documents.rank_bucket AS search_rank_bucket,
               food_normalized_search_documents.normalization_confidence AS search_normalization_confidence
        FROM food_normalized_search_documents
        JOIN food_items ON food_items.id = food_normalized_search_documents.food_item_id
        JOIN food_item_quality ON food_item_quality.food_item_id = food_items.id
        JOIN food_normalization_review ON food_normalization_review.food_item_id = food_items.id
          AND food_normalization_review.normalization_version = food_normalized_search_documents.normalization_version
        ${this.normalizedFoodSearchSampleJoinSql()}
        WHERE (food_normalized_search_documents.user_id IS NULL OR food_normalized_search_documents.user_id = ${userId})
          AND food_item_quality.is_search_eligible
          AND food_normalization_review.review_status = 'valid'
          ${this.normalizedFoodSearchSamplePredicateSql()}
          AND food_normalized_search_documents.locale IN ${sqlList(profile.locales)}
          AND (${normalizedFoodTextSearchPredicateSql(normalized)})
      ),
      scored_rows AS (
        SELECT base_rows.*,
               LEAST(1::float, search_score_base + search_display_frequency_bonus) AS search_score
        FROM base_rows
      ),
      ranked_rows AS (
        SELECT scored_rows.*,
               row_number() OVER (
                 PARTITION BY lower(search_display_name)
                 ORDER BY
                   search_result_type_rank,
                   search_score DESC,
                   search_user_rank,
                   search_locale_rank,
                   search_rank_bucket,
                   search_normalization_confidence DESC,
                   id
               ) AS search_display_rank
        FROM scored_rows
      )
      SELECT *
      FROM ranked_rows
      WHERE search_display_rank = 1
      ORDER BY
        search_user_rank,
        search_result_type_rank,
        search_score DESC,
        search_locale_rank,
        search_rank_bucket,
        char_length(search_display_name),
        search_display_name
      LIMIT ${searchLimit}
    `);
  }

  private async queryNormalizedFoodDocumentsFuzzy(
    userId: string,
    normalized: string,
    queryIdentityKey: string | undefined,
    profile: NormalizedFoodSearchProfile,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const searchLimit = normalizedFoodSearchLimit(limit);
    const locale0 = profile.locales[0] ?? "any";
    const locale1 = profile.locales[1] ?? locale0;
    const locale2 = profile.locales[2] ?? locale1;
    const locale3 = profile.locales[3] ?? locale2;
    return this.execute(dbSql`
      WITH base_rows AS (
        SELECT food_items.*,
               food_normalized_search_documents.display_name AS search_display_name,
               food_normalized_search_documents.display_name AS search_normalized_display_name,
               food_normalized_search_documents.base_name AS search_normalized_base_name,
               food_normalized_search_documents.variant_name AS search_normalized_variant_name,
               food_normalized_search_documents.result_type AS search_normalized_result_type,
               food_normalized_search_documents.brand_display AS search_normalized_brand_display,
               food_normalized_search_documents.primary_entity_name AS search_primary_entity_name,
               food_normalized_search_documents.primary_entity_aliases AS search_primary_entity_aliases,
               food_normalized_search_documents.secondary_entity_aliases AS search_secondary_entity_aliases,
               food_normalized_search_documents.primary_entity_category AS search_primary_entity_category,
               food_normalized_search_documents.primary_entity_category_coherence AS search_primary_entity_category_coherence,
               food_normalized_search_documents.primary_entity_representativeness AS search_primary_entity_representativeness,
               food_normalized_search_documents.metadata AS search_normalized_metadata,
               GREATEST(
                 similarity(food_normalized_search_documents.search_text, ${normalized}),
                 word_similarity(${normalized}, food_normalized_search_documents.search_text),
                 strict_word_similarity(${normalized}, food_normalized_search_documents.search_text),
                 ${normalizedFoodSearchScoreSql(normalized, queryIdentityKey)}
               ) AS search_score_base,
               LEAST(
                 0.04::float,
                 GREATEST(
                   count(*) OVER (PARTITION BY lower(food_normalized_search_documents.display_name))::float - 1::float,
                   0::float
                 ) * 0.002::float
               ) AS search_display_frequency_bonus,
               CASE WHEN food_normalized_search_documents.user_id = ${userId} THEN 0 ELSE 1 END AS search_user_rank,
               CASE
                 WHEN food_normalized_search_documents.locale = ${locale0} THEN 0
                 WHEN food_normalized_search_documents.locale = ${locale1} THEN 1
                 WHEN food_normalized_search_documents.locale = ${locale2} THEN 2
                 WHEN food_normalized_search_documents.locale = ${locale3} THEN 3
                 ELSE 4
               END AS search_locale_rank,
               CASE food_normalized_search_documents.result_type
                 WHEN 'generic_food' THEN 0
                 WHEN 'product' THEN 1
                 ELSE 2
               END AS search_result_type_rank,
               food_normalized_search_documents.rank_bucket AS search_rank_bucket,
               food_normalized_search_documents.normalization_confidence AS search_normalization_confidence
        FROM food_normalized_search_documents
        JOIN food_items ON food_items.id = food_normalized_search_documents.food_item_id
        JOIN food_item_quality ON food_item_quality.food_item_id = food_items.id
        JOIN food_normalization_review ON food_normalization_review.food_item_id = food_items.id
          AND food_normalization_review.normalization_version = food_normalized_search_documents.normalization_version
        ${this.normalizedFoodSearchSampleJoinSql()}
        WHERE (food_normalized_search_documents.user_id IS NULL OR food_normalized_search_documents.user_id = ${userId})
          AND food_item_quality.is_search_eligible
          AND food_normalization_review.review_status = 'valid'
          ${this.normalizedFoodSearchSamplePredicateSql()}
          AND food_normalized_search_documents.locale IN ${sqlList(profile.locales)}
          AND (
            food_normalized_search_documents.search_text % ${normalized}
            OR ${normalized} <% food_normalized_search_documents.search_text
            OR ${normalized} <<% food_normalized_search_documents.search_text
          )
      ),
      scored_rows AS (
        SELECT base_rows.*,
               LEAST(1::float, search_score_base + search_display_frequency_bonus) AS search_score
        FROM base_rows
      ),
      ranked_rows AS (
        SELECT scored_rows.*,
               row_number() OVER (
                 PARTITION BY lower(search_display_name)
                 ORDER BY
                   search_result_type_rank,
                   search_score DESC,
                   search_user_rank,
                   search_locale_rank,
                   search_rank_bucket,
                   search_normalization_confidence DESC,
                   id
               ) AS search_display_rank
        FROM scored_rows
      )
      SELECT *
      FROM ranked_rows
      WHERE search_display_rank = 1
      ORDER BY
        search_user_rank,
        search_result_type_rank,
        search_score DESC,
        search_locale_rank,
        search_rank_bucket,
        char_length(search_display_name),
        search_display_name
      LIMIT ${searchLimit}
    `);
  }

  private async searchFoodDocuments(
    userId: string,
    input: FoodHybridSearchInput,
    normalized: string,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const rows: Record<string, unknown>[] = [];
    const seen = new Set<string>();
    const profiles = foodSearchProfiles(input);
    for (const profile of profiles) {
      const profileRows = await withSpan(
        "PostgresRepository.searchFoodsHybrid.documentQuery",
        {
          limit: Math.max(limit * 4, DEFAULT_FOOD_SEARCH_LIMIT),
          scope: profile.scope,
          locales: profile.locales,
        },
        () => this.queryFoodSearchDocuments(userId, normalized, profile, limit),
      );
      for (const row of profileRows) {
        const id = row.id as string;
        if (seen.has(id)) continue;
        seen.add(id);
        rows.push(row);
      }
      if (rows.length >= limit && !profile.continueAfterLimit) break;
    }
    return rows;
  }

  private async queryFoodSearchDocuments(
    userId: string,
    normalized: string,
    profile: FoodSearchProfile,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const textRows = await this.queryFoodSearchDocumentsText(
      userId,
      normalized,
      profile,
      limit,
    );
    if (textRows.length >= limit) return textRows;
    const seen = new Set(textRows.map((row) => row.id as string));
    const fuzzyRows = await this.queryFoodSearchDocumentsFuzzy(
      userId,
      normalized,
      profile,
      limit,
    );
    return [
      ...textRows,
      ...fuzzyRows.filter((row) => !seen.has(row.id as string)),
    ];
  }

  private async queryFoodSearchDocumentsText(
    userId: string,
    normalized: string,
    profile: FoodSearchProfile,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const searchLimit = Math.max(limit * 4, DEFAULT_FOOD_SEARCH_LIMIT);
    const searchScore = foodTextSearchScoreSql(normalized);
    const locale0 = profile.locales[0] ?? "any";
    const locale1 = profile.locales[1] ?? locale0;
    const locale2 = profile.locales[2] ?? locale1;
    const locale3 = profile.locales[3] ?? locale2;
    return this.execute(dbSql`
      SELECT food_items.*,
             ${profile.scopeRank}::int AS search_scope_rank,
             ${searchScore} AS search_score
      FROM food_search_documents
      JOIN food_items ON food_items.id = food_search_documents.food_item_id
      WHERE (food_search_documents.user_id IS NULL OR food_search_documents.user_id = ${userId})
        AND food_items.deleted_at IS NULL
        AND food_search_documents.scope = ${profile.scope}
        AND food_search_documents.locale IN ${sqlList(profile.locales)}
        AND (${foodTextSearchPredicateSql(normalized)})
      ORDER BY
        CASE WHEN food_search_documents.user_id = ${userId} THEN 0 ELSE 1 END,
        search_score DESC,
        CASE
          WHEN food_search_documents.locale = ${locale0} THEN 0
          WHEN food_search_documents.locale = ${locale1} THEN 1
          WHEN food_search_documents.locale = ${locale2} THEN 2
          WHEN food_search_documents.locale = ${locale3} THEN 3
          ELSE 4
        END,
        food_search_documents.rank_bucket,
        char_length(food_search_documents.search_text),
        food_items.name
      LIMIT ${searchLimit}
    `);
  }

  private async queryFoodSearchDocumentsFuzzy(
    userId: string,
    normalized: string,
    profile: FoodSearchProfile,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const searchLimit = Math.max(limit * 4, DEFAULT_FOOD_SEARCH_LIMIT);
    const locale0 = profile.locales[0] ?? "any";
    const locale1 = profile.locales[1] ?? locale0;
    const locale2 = profile.locales[2] ?? locale1;
    const locale3 = profile.locales[3] ?? locale2;
    return this.execute(dbSql`
      SELECT food_items.*,
             ${profile.scopeRank}::int AS search_scope_rank,
             GREATEST(
               similarity(food_search_documents.search_text, ${normalized}),
               word_similarity(${normalized}, food_search_documents.search_text),
               strict_word_similarity(${normalized}, food_search_documents.search_text),
               ${foodSearchScoreSql(normalized)}
             ) AS search_score
      FROM food_search_documents
      JOIN food_items ON food_items.id = food_search_documents.food_item_id
      WHERE (food_search_documents.user_id IS NULL OR food_search_documents.user_id = ${userId})
        AND food_items.deleted_at IS NULL
        AND food_search_documents.scope = ${profile.scope}
        AND food_search_documents.locale IN ${sqlList(profile.locales)}
        AND (
          food_search_documents.search_text % ${normalized}
          OR ${normalized} <% food_search_documents.search_text
          OR ${normalized} <<% food_search_documents.search_text
        )
      ORDER BY
        CASE WHEN food_search_documents.user_id = ${userId} THEN 0 ELSE 1 END,
        search_score DESC,
        CASE
          WHEN food_search_documents.locale = ${locale0} THEN 0
          WHEN food_search_documents.locale = ${locale1} THEN 1
          WHEN food_search_documents.locale = ${locale2} THEN 2
          WHEN food_search_documents.locale = ${locale3} THEN 3
          ELSE 4
        END,
        food_search_documents.rank_bucket,
        char_length(food_search_documents.search_text),
        food_items.name
      LIMIT ${searchLimit}
    `);
  }

  private getCachedFoodSearch(key: string): FoodSearchCandidate[] | undefined {
    const cached = this.foodSearchCache.get(key);
    if (!cached) return undefined;
    if (cached.expiresAt < Date.now()) {
      this.foodSearchCache.delete(key);
      return undefined;
    }
    this.foodSearchCache.delete(key);
    this.foodSearchCache.set(key, cached);
    return cached.value;
  }

  private setCachedFoodSearch(key: string, value: FoodSearchCandidate[]): void {
    if (this.foodSearchCache.size >= FOOD_SEARCH_CACHE_MAX_ENTRIES) {
      const oldest = this.foodSearchCache.keys().next().value;
      if (oldest) this.foodSearchCache.delete(oldest);
    }
    this.foodSearchCache.set(key, {
      expiresAt: Date.now() + FOOD_SEARCH_CACHE_TTL_MS,
      value: value.map(cloneFoodSearchCandidate),
    });
  }

  async upsertFoodItem(
    input: Omit<FoodItemRecord, "id">,
  ): Promise<FoodItemRecord> {
    const normalizedName = normalizeText(input.normalizedName || input.name);
    const [existing] =
      input.externalSource && input.externalId
        ? await this.execute(dbSql`
          SELECT * FROM food_items
          WHERE external_source = ${input.externalSource}
            AND external_id = ${input.externalId}
            AND (user_id IS NULL OR user_id = ${input.userId ?? null})
          LIMIT 1
        `)
        : await this.execute(dbSql`
          SELECT * FROM food_items
          WHERE normalized_name = ${normalizedName}
            AND source = ${input.source}
            AND user_id IS NOT DISTINCT FROM ${input.userId ?? null}
          LIMIT 1
        `);
    if (existing) {
      const [row] = await this.execute(dbSql`
        UPDATE food_items
        SET name = ${input.name},
            normalized_name = ${normalizedName},
            canonical_name = ${input.canonicalName ?? input.name},
            brand = ${input.brand ?? null},
            barcode = ${input.barcode ?? null},
            source = ${input.source},
            external_source = ${input.externalSource ?? null},
            external_id = ${input.externalId ?? null},
            source_url = ${input.sourceUrl ?? null},
            license = ${input.license ?? null},
            fetched_at = ${input.fetchedAt ?? new Date().toISOString()},
            data_type = ${input.dataType ?? null},
            food_category = ${input.foodCategory ?? null},
            publication_date = ${input.publicationDate ?? null},
            ndb_number = ${input.ndbNumber ?? null},
            food_key = ${input.foodKey ?? null},
            ingredients = ${input.ingredients ?? null},
            market_country = ${input.marketCountry ?? null},
            household_serving_fulltext = ${input.householdServingFulltext ?? null},
            nutrients_json = ${jsonb(input.nutrients ?? {})},
            serving_grams = ${input.servingGrams},
            calories = ${input.calories},
            protein_grams = ${input.proteinGrams},
            carbs_grams = ${input.carbsGrams},
            fat_grams = ${input.fatGrams},
            updated_at = now(),
            deleted_at = NULL
        WHERE id = ${existing.id as string}
        RETURNING *
      `);
      this.foodSearchCache.clear();
      await this.upsertFoodSearchDocument(mapFood(row));
      return mapFood(row);
    }
    const [row] = await this.execute(dbSql`
      INSERT INTO food_items (
        user_id, name, normalized_name, canonical_name, brand, barcode, source,
        external_source, external_id, source_url, license, fetched_at,
        data_type, food_category, publication_date, ndb_number, food_key,
        ingredients, market_country, household_serving_fulltext, nutrients_json,
        serving_grams, calories, protein_grams, carbs_grams, fat_grams
      )
      VALUES (
        ${input.userId ?? null}, ${input.name}, ${normalizedName}, ${input.canonicalName ?? input.name},
        ${input.brand ?? null}, ${input.barcode ?? null}, ${input.source},
        ${input.externalSource ?? null}, ${input.externalId ?? null}, ${input.sourceUrl ?? null},
        ${input.license ?? null}, ${input.fetchedAt ?? new Date().toISOString()},
        ${input.dataType ?? null}, ${input.foodCategory ?? null}, ${input.publicationDate ?? null},
        ${input.ndbNumber ?? null}, ${input.foodKey ?? null}, ${input.ingredients ?? null},
        ${input.marketCountry ?? null}, ${input.householdServingFulltext ?? null},
        ${jsonb(input.nutrients ?? {})},
        ${input.servingGrams}, ${input.calories}, ${input.proteinGrams}, ${input.carbsGrams}, ${input.fatGrams}
      )
      RETURNING *
    `);
    this.foodSearchCache.clear();
    await this.upsertFoodSearchDocument(mapFood(row));
    return mapFood(row);
  }

  async listUsualFoods(userId: string): Promise<UsualFood[]> {
    const rows = await this.execute(dbSql`
      SELECT *
      FROM food_items
      WHERE user_id = ${userId}
        AND source = ${USUAL_FOOD_SOURCE}
        AND deleted_at IS NULL
      ORDER BY updated_at DESC NULLS LAST, created_at DESC, name
    `);
    return rows.map((row) => foodRecordToUsualFood(mapFood(row)));
  }

  async createUsualFood(
    userId: string,
    input: CreateUsualFoodRequest,
  ): Promise<UsualFood> {
    const [row] = await this.execute(dbSql`
      INSERT INTO food_items (
        user_id, name, normalized_name, canonical_name, brand, barcode, source,
        external_source, external_id, nutrients_json, serving_grams, calories,
        protein_grams, carbs_grams, fat_grams, updated_at
      )
      VALUES (
        ${userId}, ${input.name}, ${normalizeText(input.name)}, ${input.canonicalName ?? null},
        ${input.brand ?? null}, ${input.barcode ?? null}, ${USUAL_FOOD_SOURCE},
        NULL, NULL, ${jsonb(nutrientsWithAliases(input.nutrients, input.aliases))},
        ${input.servingGrams}, ${input.nutrition.calories}, ${input.nutrition.proteinGrams},
        ${input.nutrition.carbsGrams}, ${input.nutrition.fatGrams}, now()
      )
      RETURNING *
    `);
    this.foodSearchCache.clear();
    await this.upsertFoodSearchDocument(mapFood(row));
    // Seed initial preference score so the usual food gets an immediate ranking edge
    await this.recordFoodFeedback({
      userId,
      foodItemId: row.id as string,
      query: input.name,
      action: "selected",
    }).catch(() => {
      // Non-critical; preference seeding should not block usual food creation
    });
    return foodRecordToUsualFood(mapFood(row));
  }

  async updateUsualFood(
    userId: string,
    usualFoodId: string,
    input: UpdateUsualFoodRequest,
  ): Promise<UsualFood | undefined> {
    const [existing] = await this.execute(dbSql`
      SELECT *
      FROM food_items
      WHERE id = ${usualFoodId}
        AND user_id = ${userId}
        AND source = ${USUAL_FOOD_SOURCE}
        AND deleted_at IS NULL
      LIMIT 1
    `);
    if (!existing) return undefined;
    const existingFood = mapFood(existing);
    const nextName = input.name ?? existingFood.name;
    const nextCanonicalName =
      "canonicalName" in input
        ? (input.canonicalName ?? null)
        : (existingFood.canonicalName ?? null);
    const nextBrand =
      "brand" in input ? (input.brand ?? null) : (existingFood.brand ?? null);
    const nextBarcode =
      "barcode" in input
        ? (input.barcode ?? null)
        : (existingFood.barcode ?? null);
    const nextAliases =
      input.aliases ?? aliasesFromNutrients(existingFood.nutrients);
    const nextNutrients =
      input.nutrients === undefined && input.aliases === undefined
        ? (existingFood.nutrients ?? {})
        : nutrientsWithAliases(
            input.nutrients ?? publicNutrients(existingFood.nutrients),
            nextAliases,
          );
    const [row] = await this.execute(dbSql`
      UPDATE food_items
      SET name = ${nextName},
          normalized_name = ${normalizeText(nextName)},
          canonical_name = ${nextCanonicalName},
          brand = ${nextBrand},
          barcode = ${nextBarcode},
          nutrients_json = ${jsonb(nextNutrients)},
          serving_grams = ${input.servingGrams ?? existingFood.servingGrams},
          calories = ${input.nutrition?.calories ?? existingFood.calories},
          protein_grams = ${input.nutrition?.proteinGrams ?? existingFood.proteinGrams},
          carbs_grams = ${input.nutrition?.carbsGrams ?? existingFood.carbsGrams},
          fat_grams = ${input.nutrition?.fatGrams ?? existingFood.fatGrams},
          updated_at = now()
      WHERE id = ${usualFoodId}
        AND user_id = ${userId}
        AND source = ${USUAL_FOOD_SOURCE}
        AND deleted_at IS NULL
      RETURNING *
    `);
    if (!row) return undefined;
    this.foodSearchCache.clear();
    await this.upsertFoodSearchDocument(mapFood(row));
    return foodRecordToUsualFood(mapFood(row));
  }

  async deleteUsualFood(userId: string, usualFoodId: string): Promise<boolean> {
    const rows = await this.execute(dbSql`
      UPDATE food_items
      SET deleted_at = now(), updated_at = now()
      WHERE id = ${usualFoodId}
        AND user_id = ${userId}
        AND source = ${USUAL_FOOD_SOURCE}
        AND deleted_at IS NULL
      RETURNING id
    `);
    if (rows.length === 0) return false;
    await this.execute(
      dbSql`DELETE FROM food_search_documents WHERE food_item_id = ${usualFoodId}`,
    );
    this.foodSearchCache.clear();
    return true;
  }

  private async upsertFoodSearchDocument(food: FoodItemRecord): Promise<void> {
    const document = foodSearchDocumentForFood(food);
    if (!document) {
      await this.execute(
        dbSql`DELETE FROM food_search_documents WHERE food_item_id = ${food.id}`,
      );
      return;
    }
    await this.execute(dbSql`
      INSERT INTO food_search_documents (
        food_item_id, user_id, locale, scope, search_text, search_vector, rank_bucket,
        source, external_source, data_type, food_key, updated_at
      )
      VALUES (
        ${food.id}, ${food.userId ?? null}, ${document.locale}, ${document.scope},
        ${document.searchText}, to_tsvector('simple', ${document.searchText}), ${document.rankBucket}, ${food.source},
        ${food.externalSource ?? null}, ${food.dataType ?? null}, ${food.foodKey ?? null}, now()
      )
      ON CONFLICT (food_item_id) DO UPDATE SET
        user_id = EXCLUDED.user_id,
        locale = EXCLUDED.locale,
        scope = EXCLUDED.scope,
        search_text = EXCLUDED.search_text,
        search_vector = EXCLUDED.search_vector,
        rank_bucket = EXCLUDED.rank_bucket,
        source = EXCLUDED.source,
        external_source = EXCLUDED.external_source,
        data_type = EXCLUDED.data_type,
        food_key = EXCLUDED.food_key,
        updated_at = now()
    `);
  }

  async recordFoodFeedback(
    input: FoodFeedbackRecord,
  ): Promise<UserFoodPreference | undefined> {
    const normalizedQuery = normalizeText(input.query);
    const delta = foodFeedbackDelta(input.action);
    const positiveDelta = delta > 0 ? 1 : 0;
    const negativeDelta = delta < 0 ? 1 : 0;

    const [preference] = await this.db.transaction(async (tx) => {
      const foodItemId =
        input.foodItemId ??
        (input.externalSource && input.externalId
          ? ((
              await executeRows(
                tx,
                dbSql`
            SELECT id
            FROM food_items
            WHERE external_source = ${input.externalSource}
              AND external_id = ${input.externalId}
              AND (user_id IS NULL OR user_id = ${input.userId})
            ORDER BY CASE WHEN user_id = ${input.userId} THEN 0 ELSE 1 END
            LIMIT 1
          `,
              )
            )[0]?.id as string | undefined)
          : undefined);
      if (!foodItemId) return [];

      await executeRows(
        tx,
        dbSql`
        INSERT INTO user_food_feedback_events (user_id, food_item_id, query_text, normalized_query, action, metadata_json)
        VALUES (
          ${input.userId},
          ${foodItemId},
          ${input.query},
          ${normalizedQuery},
          ${input.action},
          ${jsonb(input.metadata ?? {})}
        )
      `,
      );
      return executeRows(
        tx,
        dbSql`
        INSERT INTO user_food_preferences (
          user_id, food_item_id, affinity_score, positive_feedback_count, negative_feedback_count, last_feedback_at, updated_at
        )
        VALUES (${input.userId}, ${foodItemId}, ${delta}, ${positiveDelta}, ${negativeDelta}, now(), now())
        ON CONFLICT (user_id, food_item_id)
        DO UPDATE SET
          affinity_score = user_food_preferences.affinity_score + EXCLUDED.affinity_score,
          positive_feedback_count = user_food_preferences.positive_feedback_count + EXCLUDED.positive_feedback_count,
          negative_feedback_count = user_food_preferences.negative_feedback_count + EXCLUDED.negative_feedback_count,
          last_feedback_at = now(),
          updated_at = now()
        RETURNING *
      `,
      );
    });
    this.foodSearchCache.clear();
    return preference ? mapUserFoodPreference(preference) : undefined;
  }

  async getUserFoodPreferences(userId: string): Promise<UserFoodPreference[]> {
    const rows = await this.execute(dbSql`
      SELECT *
      FROM user_food_preferences
      WHERE user_id = ${userId}
      ORDER BY affinity_score DESC, updated_at DESC
    `);
    return rows.map(mapUserFoodPreference);
  }

  async upsertFoodItemEmbedding(
    input: UpsertFoodItemEmbeddingInput,
  ): Promise<FoodItemEmbeddingRecord> {
    const embedding = toVectorLiteral(input.embedding);
    const [row] = await this.execute(dbSql`
      INSERT INTO food_item_embeddings (
        food_item_id, embedded_text, embedded_text_hash, embedding, updated_at
      )
      VALUES (
        ${input.foodItemId},
        ${input.embeddedText},
        ${input.embeddedTextHash},
        ${embedding}::vector,
        now()
      )
      ON CONFLICT (food_item_id)
      DO UPDATE SET
        embedded_text = EXCLUDED.embedded_text,
        embedded_text_hash = EXCLUDED.embedded_text_hash,
        embedding = EXCLUDED.embedding,
        updated_at = now()
      RETURNING *
    `);
    return mapFoodItemEmbedding(row);
  }

  async getNutritionTarget(userId: string): Promise<NutritionSnapshot> {
    const [row] = await this.execute(
      dbSql`SELECT * FROM nutrition_targets WHERE user_id = ${userId}`,
    );
    return row
      ? mapNutrition(row)
      : { calories: 2200, proteinGrams: 0, carbsGrams: 0, fatGrams: 0 };
  }

  async getDailyGoals(userId: string, date: string): Promise<DailyGoals> {
    const [existing] = await this.execute(dbSql`
      SELECT *
      FROM daily_goal_snapshots
      WHERE user_id = ${userId} AND target_date = ${date}
    `);
    if (existing) return mapDailyGoals(existing);

    const current = await this.getCurrentGoals(userId);
    const [inserted] = await this.execute(dbSql`
      INSERT INTO daily_goal_snapshots (
        user_id, target_date, calories, protein_grams, carbs_grams, fat_grams, hydration_goal_glasses, hydration_goal_liters, water_consumed_liters,
        calorie_target_configured, calorie_target_source, calorie_target_configured_at,
        macro_mode, macro_source, macro_preset, protein_pct, carbs_pct, fat_pct, macro_calories, calorie_delta_kcal
      )
      VALUES (
        ${userId}, ${date}, ${current.target.calories}, ${current.target.proteinGrams}, ${current.target.carbsGrams}, ${current.target.fatGrams}, 0, ${current.hydrationGoalLiters}, 0,
        ${current.calorieTargetConfigured}, ${current.calorieTargetSource}, ${current.calorieTargetConfiguredAt ?? null},
        ${current.macroMode ?? null}, ${current.macroSource ?? null}, ${current.macroPreset ?? null},
        ${current.proteinPct ?? null}, ${current.carbsPct ?? null}, ${current.fatPct ?? null},
        ${current.macroCalories ?? null}, ${current.calorieDeltaKcal ?? null}
      )
      ON CONFLICT (user_id, target_date) DO NOTHING
      RETURNING *
    `);
    if (inserted) return mapDailyGoals(inserted);
    const [row] = await this.execute(dbSql`
      SELECT *
      FROM daily_goal_snapshots
      WHERE user_id = ${userId} AND target_date = ${date}
    `);
    return mapDailyGoals(row);
  }

  async updateDailyGoals(
    userId: string,
    input: UpdateDailyGoalsInput,
  ): Promise<DailyGoals> {
    return this.db.transaction(async (tx) => {
      const current = await this.getCurrentGoals(userId, tx);
      for (const snapshotDate of previousDatesInWeek(input.date)) {
        await executeRows(
          tx,
          dbSql`
          INSERT INTO daily_goal_snapshots (
            user_id, target_date, calories, protein_grams, carbs_grams, fat_grams, hydration_goal_glasses, hydration_goal_liters, water_consumed_liters,
            calorie_target_configured, calorie_target_source, calorie_target_configured_at,
            macro_mode, macro_source, macro_preset, protein_pct, carbs_pct, fat_pct, macro_calories, calorie_delta_kcal
          )
          VALUES (
            ${userId}, ${snapshotDate}, ${current.target.calories}, ${current.target.proteinGrams}, ${current.target.carbsGrams}, ${current.target.fatGrams}, 0, ${current.hydrationGoalLiters}, 0,
            ${current.calorieTargetConfigured}, ${current.calorieTargetSource}, ${current.calorieTargetConfiguredAt ?? null},
            ${current.macroMode ?? null}, ${current.macroSource ?? null}, ${current.macroPreset ?? null},
            ${current.proteinPct ?? null}, ${current.carbsPct ?? null}, ${current.fatPct ?? null},
            ${current.macroCalories ?? null}, ${current.calorieDeltaKcal ?? null}
          )
          ON CONFLICT (user_id, target_date) DO NOTHING
        `,
        );
      }

      const { target: nextTarget, metadata: nextMacroMetadata } =
        applyMacroGoalUpdate(
          current.target,
          current,
          input,
          input.calories ?? current.target.calories,
        );
      const nextHydrationLiters =
        input.hydrationGoalLiters ?? current.hydrationGoalLiters;
      const calorieTargetWasUpdated = input.calories !== undefined;
      const nextConfigured = calorieTargetWasUpdated
        ? true
        : current.calorieTargetConfigured;
      const nextSource = calorieTargetWasUpdated
        ? (input.calorieTargetSource ?? "manual")
        : current.calorieTargetSource;
      const nextConfiguredAt = calorieTargetWasUpdated
        ? new Date().toISOString()
        : current.calorieTargetConfiguredAt;
      await executeRows(
        tx,
        dbSql`
        INSERT INTO nutrition_targets (
          user_id, calories, protein_grams, carbs_grams, fat_grams, hydration_goal_glasses, hydration_goal_liters,
          calorie_target_configured, calorie_target_source, calorie_target_configured_at,
          macro_mode, macro_source, macro_preset, protein_pct, carbs_pct, fat_pct, macro_calories, calorie_delta_kcal,
          updated_at
        )
        VALUES (
          ${userId}, ${nextTarget.calories}, ${nextTarget.proteinGrams}, ${nextTarget.carbsGrams}, ${nextTarget.fatGrams}, 0, ${nextHydrationLiters},
          ${nextConfigured}, ${nextSource}, ${nextConfiguredAt ?? null},
          ${nextMacroMetadata.macroMode ?? null}, ${nextMacroMetadata.macroSource ?? null}, ${nextMacroMetadata.macroPreset ?? null},
          ${nextMacroMetadata.proteinPct ?? null}, ${nextMacroMetadata.carbsPct ?? null}, ${nextMacroMetadata.fatPct ?? null},
          ${nextMacroMetadata.macroCalories ?? null}, ${nextMacroMetadata.calorieDeltaKcal ?? null},
          now()
        )
        ON CONFLICT (user_id) DO UPDATE
        SET calories = EXCLUDED.calories,
            protein_grams = EXCLUDED.protein_grams,
            carbs_grams = EXCLUDED.carbs_grams,
            fat_grams = EXCLUDED.fat_grams,
            hydration_goal_glasses = EXCLUDED.hydration_goal_glasses,
            hydration_goal_liters = EXCLUDED.hydration_goal_liters,
            calorie_target_configured = EXCLUDED.calorie_target_configured,
            calorie_target_source = EXCLUDED.calorie_target_source,
            calorie_target_configured_at = EXCLUDED.calorie_target_configured_at,
            macro_mode = EXCLUDED.macro_mode,
            macro_source = EXCLUDED.macro_source,
            macro_preset = EXCLUDED.macro_preset,
            protein_pct = EXCLUDED.protein_pct,
            carbs_pct = EXCLUDED.carbs_pct,
            fat_pct = EXCLUDED.fat_pct,
            macro_calories = EXCLUDED.macro_calories,
            calorie_delta_kcal = EXCLUDED.calorie_delta_kcal,
            updated_at = now()
      `,
      );
      const [row] = await executeRows(
        tx,
        dbSql`
        INSERT INTO daily_goal_snapshots (
          user_id, target_date, calories, protein_grams, carbs_grams, fat_grams, hydration_goal_glasses, hydration_goal_liters, water_consumed_liters,
          calorie_target_configured, calorie_target_source, calorie_target_configured_at,
          macro_mode, macro_source, macro_preset, protein_pct, carbs_pct, fat_pct, macro_calories, calorie_delta_kcal,
          updated_at
        )
        VALUES (
          ${userId}, ${input.date}, ${nextTarget.calories}, ${nextTarget.proteinGrams}, ${nextTarget.carbsGrams}, ${nextTarget.fatGrams}, 0, ${nextHydrationLiters}, 0,
          ${nextConfigured}, ${nextSource}, ${nextConfiguredAt ?? null},
          ${nextMacroMetadata.macroMode ?? null}, ${nextMacroMetadata.macroSource ?? null}, ${nextMacroMetadata.macroPreset ?? null},
          ${nextMacroMetadata.proteinPct ?? null}, ${nextMacroMetadata.carbsPct ?? null}, ${nextMacroMetadata.fatPct ?? null},
          ${nextMacroMetadata.macroCalories ?? null}, ${nextMacroMetadata.calorieDeltaKcal ?? null},
          now()
        )
        ON CONFLICT (user_id, target_date) DO UPDATE
        SET calories = EXCLUDED.calories,
            protein_grams = EXCLUDED.protein_grams,
            carbs_grams = EXCLUDED.carbs_grams,
            fat_grams = EXCLUDED.fat_grams,
            hydration_goal_glasses = EXCLUDED.hydration_goal_glasses,
            hydration_goal_liters = EXCLUDED.hydration_goal_liters,
            water_consumed_liters = LEAST(daily_goal_snapshots.water_consumed_liters, EXCLUDED.hydration_goal_liters),
            calorie_target_configured = EXCLUDED.calorie_target_configured,
            calorie_target_source = EXCLUDED.calorie_target_source,
            calorie_target_configured_at = EXCLUDED.calorie_target_configured_at,
            macro_mode = EXCLUDED.macro_mode,
            macro_source = EXCLUDED.macro_source,
            macro_preset = EXCLUDED.macro_preset,
            protein_pct = EXCLUDED.protein_pct,
            carbs_pct = EXCLUDED.carbs_pct,
            fat_pct = EXCLUDED.fat_pct,
            macro_calories = EXCLUDED.macro_calories,
            calorie_delta_kcal = EXCLUDED.calorie_delta_kcal,
            updated_at = now()
        RETURNING *
      `,
      );
      return mapDailyGoals(row);
    });
  }

  async updateDailyHydration(
    userId: string,
    date: string,
    waterConsumedLiters: number,
  ) {
    const goals = await this.getDailyGoals(userId, date);
    const clampedWater = Math.min(
      Math.max(waterConsumedLiters, 0),
      goals.hydrationGoalLiters,
    );
    await this.execute(dbSql`
      UPDATE daily_goal_snapshots
      SET water_consumed_liters = ${clampedWater}, updated_at = now()
      WHERE user_id = ${userId} AND target_date = ${date}
    `);
    return this.getDailySummary(userId, date);
  }

  async listMeals(userId: string, limit = 25): Promise<Meal[]> {
    const rows = await this.execute(dbSql`
      SELECT * FROM meals
      WHERE user_id = ${userId} AND deleted_at IS NULL
      ORDER BY occurred_at DESC
      LIMIT ${limit}
    `);
    return this.mapMeals(rows);
  }

  async getMeal(userId: string, mealId: string): Promise<Meal | undefined> {
    const [row] = await this.execute(
      dbSql`SELECT * FROM meals WHERE id = ${mealId} AND user_id = ${userId} AND deleted_at IS NULL`,
    );
    return row ? this.mapMeal(row) : undefined;
  }

  async createProposal(
    userId: string,
    proposal: Omit<MealProposal, "id" | "createdAt">,
  ): Promise<MealProposal> {
    return withSpan(
      "PostgresRepository.createProposal",
      { itemCount: proposal.items.length },
      () =>
        this.db.transaction(async (tx) => {
          const id = newId();
          const [row] = await withSpan(
            "PostgresRepository.createProposal.insertProposal",
            undefined,
            () =>
              executeRows(
                tx,
                dbSql`
          INSERT INTO meal_proposals (id, user_id, phrase, title, status, confidence, requires_confirmation, trusted_auto_commit_eligible, source, calories, protein_grams, carbs_grams, fat_grams)
          VALUES (${id}, ${userId}, ${proposal.phrase}, ${proposal.title}, ${proposal.status}, ${proposal.confidence}, ${proposal.requiresConfirmation}, ${proposal.trustedAutoCommitEligible}, ${proposal.source}, ${proposal.nutrition.calories}, ${proposal.nutrition.proteinGrams}, ${proposal.nutrition.carbsGrams}, ${proposal.nutrition.fatGrams})
          RETURNING *
        `,
              ),
          );
          await withSpan(
            "PostgresRepository.createProposal.insertItems",
            { itemCount: proposal.items.length },
            () =>
              Promise.all(
                proposal.items.map((item) => insertProposalItem(tx, id, item)),
              ),
          );
          return this.mapProposal(row, proposal.title, tx);
        }),
    );
  }

  async getProposal(
    userId: string,
    proposalId: string,
  ): Promise<MealProposal | undefined> {
    const [row] = await this.execute(
      dbSql`SELECT * FROM meal_proposals WHERE id = ${proposalId} AND user_id = ${userId}`,
    );
    return row ? this.mapProposal(row) : undefined;
  }

  async updateProposal(
    userId: string,
    proposal: MealProposal,
  ): Promise<MealProposal> {
    await this.db.transaction(async (tx) => {
      await executeRows(
        tx,
        dbSql`
        UPDATE meal_proposals
        SET title = ${proposal.title}, status = ${proposal.status}, calories = ${proposal.nutrition.calories}, protein_grams = ${proposal.nutrition.proteinGrams}, carbs_grams = ${proposal.nutrition.carbsGrams}, fat_grams = ${proposal.nutrition.fatGrams}
        WHERE id = ${proposal.id} AND user_id = ${userId}
      `,
      );
      await executeRows(
        tx,
        dbSql`DELETE FROM meal_proposal_items WHERE proposal_id = ${proposal.id}`,
      );
      for (const item of proposal.items)
        await insertProposalItem(tx, proposal.id, item);
    });
    return proposal;
  }

  async createMealFromProposal(
    userId: string,
    proposal: MealProposal,
    occurredAt: string,
    items = proposal.items,
    mealLabel?: MealLabel | null,
  ): Promise<Meal> {
    return this.db.transaction(async (tx) => {
      const id = newId();
      const nutrition = sumNutrition(items);
      const [row] = await executeRows(
        tx,
        dbSql`
        INSERT INTO meals (id, user_id, proposal_id, title, occurred_at, meal_type, meal_type_label, calories, protein_grams, carbs_grams, fat_grams)
        VALUES (${id}, ${userId}, ${proposal.id}, ${proposal.title}, ${occurredAt}, ${mealLabel?.type ?? null}, ${mealLabel?.label ?? null}, ${nutrition.calories}, ${nutrition.proteinGrams}, ${nutrition.carbsGrams}, ${nutrition.fatGrams})
        RETURNING *
      `,
      );
      for (const item of items) await insertMealItem(tx, id, item);
      await executeRows(
        tx,
        dbSql`UPDATE meal_proposals SET status = 'committed' WHERE id = ${proposal.id}`,
      );
      return this.mapMeal(row, tx);
    });
  }

  async updateMeal(userId: string, meal: Meal): Promise<Meal> {
    await this.db.transaction(async (tx) => {
      await executeRows(
        tx,
        dbSql`
        UPDATE meals
        SET calories = ${meal.nutrition.calories}, protein_grams = ${meal.nutrition.proteinGrams}, carbs_grams = ${meal.nutrition.carbsGrams}, fat_grams = ${meal.nutrition.fatGrams}
        WHERE id = ${meal.id} AND user_id = ${userId}
      `,
      );
      await executeRows(
        tx,
        dbSql`DELETE FROM meal_items WHERE meal_id = ${meal.id}`,
      );
      for (const item of meal.items) await insertMealItem(tx, meal.id, item);
    });
    return meal;
  }

  async softDeleteMeal(userId: string, mealId: string): Promise<boolean> {
    const rows = await this.execute(
      dbSql`UPDATE meals SET deleted_at = now() WHERE id = ${mealId} AND user_id = ${userId} AND deleted_at IS NULL RETURNING id`,
    );
    return rows.length > 0;
  }

  async getDailySummary(userId: string, date: string) {
    const start = new Date(`${date}T00:00:00.000Z`);
    const end = new Date(start);
    end.setUTCDate(end.getUTCDate() + 1);
    const rows = await this.execute(dbSql`
      SELECT * FROM meals
      WHERE user_id = ${userId}
        AND deleted_at IS NULL
        AND occurred_at >= ${start.toISOString()}
        AND occurred_at < ${end.toISOString()}
      ORDER BY occurred_at DESC
    `);
    const meals = await this.mapMeals(rows);
    const consumed = meals.reduce(
      (total, meal) => ({
        calories: total.calories + meal.nutrition.calories,
        proteinGrams: total.proteinGrams + meal.nutrition.proteinGrams,
        carbsGrams: total.carbsGrams + meal.nutrition.carbsGrams,
        fatGrams: total.fatGrams + meal.nutrition.fatGrams,
      }),
      { calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0 },
    );
    const goals = await this.getDailyGoals(userId, date);
    const [hydrationRow] = await this.execute(dbSql`
      SELECT water_consumed_liters
      FROM daily_goal_snapshots
      WHERE user_id = ${userId} AND target_date = ${date}
    `);
    return {
      date,
      consumed,
      target: goals.target,
      remaining: subtractNutrition(goals.target, consumed),
      hydrationGoalLiters: goals.hydrationGoalLiters,
      waterConsumedLiters: Number(hydrationRow?.water_consumed_liters ?? 0),
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
    const rows = await this.execute(
      dbSql`SELECT * FROM meal_templates WHERE user_id = ${userId} AND deleted_at IS NULL`,
    );
    return this.mapTemplates(rows);
  }

  async createTemplate(
    userId: string,
    input: Omit<MealTemplate, "id">,
  ): Promise<MealTemplate> {
    return this.db.transaction(async (tx) => {
      const id = newId();
      const [row] = await executeRows(
        tx,
        dbSql`
        INSERT INTO meal_templates (id, user_id, title, normalized_title, trusted_auto_commit_enabled, calories, protein_grams, carbs_grams, fat_grams)
        VALUES (${id}, ${userId}, ${input.title}, ${normalizeText(input.title)}, ${input.trustedAutoCommitEnabled}, ${input.nutrition.calories}, ${input.nutrition.proteinGrams}, ${input.nutrition.carbsGrams}, ${input.nutrition.fatGrams})
        RETURNING *
      `,
      );
      for (const item of input.items) await insertTemplateItem(tx, id, item);
      for (const alias of input.aliases) {
        await executeRows(
          tx,
          dbSql`
          INSERT INTO food_memories (user_id, normalized_text, label, meal_template_id, confidence)
          VALUES (${userId}, ${normalizeText(alias)}, ${alias}, ${id}, 1)
          ON CONFLICT DO NOTHING
        `,
        );
      }
      return this.mapTemplate(row, tx);
    });
  }

  async updateTemplate(
    userId: string,
    template: MealTemplate,
  ): Promise<MealTemplate> {
    await this.db.transaction(async (tx) => {
      await executeRows(
        tx,
        dbSql`
        UPDATE meal_templates
        SET title = ${template.title}, normalized_title = ${normalizeText(template.title)}, trusted_auto_commit_enabled = ${template.trustedAutoCommitEnabled}, calories = ${template.nutrition.calories}, protein_grams = ${template.nutrition.proteinGrams}, carbs_grams = ${template.nutrition.carbsGrams}, fat_grams = ${template.nutrition.fatGrams}
        WHERE id = ${template.id} AND user_id = ${userId}
      `,
      );
      await executeRows(
        tx,
        dbSql`DELETE FROM meal_template_items WHERE template_id = ${template.id}`,
      );
      for (const item of template.items)
        await insertTemplateItem(tx, template.id, item);
      await executeRows(
        tx,
        dbSql`
        DELETE FROM food_memories
        WHERE user_id = ${userId} AND meal_template_id = ${template.id}
      `,
      );
      for (const alias of template.aliases) {
        await executeRows(
          tx,
          dbSql`
          INSERT INTO food_memories (user_id, normalized_text, label, meal_template_id, confidence)
          VALUES (${userId}, ${normalizeText(alias)}, ${alias}, ${template.id}, 1)
          ON CONFLICT DO NOTHING
        `,
        );
      }
    });
    return template;
  }

  async deleteTemplate(userId: string, templateId: string): Promise<boolean> {
    const rows = await this.execute(
      dbSql`UPDATE meal_templates SET deleted_at = now() WHERE id = ${templateId} AND user_id = ${userId} RETURNING id`,
    );
    return rows.length > 0;
  }

  async queryMemory(
    userId: string,
    normalizedText: string,
  ): Promise<MemoryMatch[]> {
    const rows = await this.execute(dbSql`
      SELECT * FROM food_memories
      WHERE user_id = ${userId}
        AND (${normalizedText} = normalized_text OR ${normalizedText} LIKE '%' || normalized_text || '%' OR normalized_text LIKE '%' || ${normalizedText} || '%')
      ORDER BY CASE WHEN ${normalizedText} = normalized_text THEN 0 ELSE 1 END, usage_count DESC
      LIMIT 5
    `);
    return Promise.all(
      rows.map(async (row) => ({
        id: row.id as string,
        userId,
        label: row.label as string,
        normalizedText: row.normalized_text as string,
        confidence:
          normalizedText === row.normalized_text ||
          normalizedText.includes(row.normalized_text as string)
            ? Number(row.confidence)
            : Math.min(Number(row.confidence), 0.82),
        template: row.meal_template_id
          ? await this.getTemplateById(userId, row.meal_template_id as string)
          : null,
      })),
    );
  }

  async createMemory(input: {
    userId: string;
    normalizedText: string;
    label: string;
    templateId?: string;
    confidence: number;
  }): Promise<void> {
    await this.execute(dbSql`
      INSERT INTO food_memories (user_id, normalized_text, label, meal_template_id, confidence)
      VALUES (${input.userId}, ${input.normalizedText}, ${input.label}, ${input.templateId ?? null}, ${input.confidence})
      ON CONFLICT DO NOTHING
    `);
  }

  async createAgentConversation(
    userId: string,
    input: { title?: string } = {},
  ): Promise<AgentConversationRecord> {
    const [row] = await this.execute(dbSql`
      INSERT INTO agent_conversations (user_id, title)
      VALUES (${userId}, ${input.title?.trim() || "New chat"})
      RETURNING *
    `);
    return mapAgentConversation(row);
  }

  async getAgentConversation(
    userId: string,
    conversationId: string,
  ): Promise<AgentConversationRecord | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT * FROM agent_conversations
      WHERE id = ${conversationId} AND user_id = ${userId}
        AND hidden_from_user_at IS NULL
      LIMIT 1
    `);
    return row ? mapAgentConversation(row) : undefined;
  }

  async listAgentConversations(
    userId: string,
    limit = 25,
  ): Promise<AgentConversationRecord[]> {
    const rows = await this.execute(dbSql`
      SELECT * FROM agent_conversations
      WHERE user_id = ${userId}
        AND hidden_from_user_at IS NULL
      ORDER BY updated_at DESC
      LIMIT ${Math.max(1, Math.min(100, Math.floor(limit)))}
    `);
    return rows.map(mapAgentConversation);
  }

  async addAgentConversationMessage(
    userId: string,
    conversationId: string,
    input: Omit<
      AgentConversationMessageRecord,
      "id" | "conversationId" | "userId" | "createdAt"
    >,
  ): Promise<AgentConversationMessageRecord> {
    const [row] = await this.execute(dbSql`
      INSERT INTO agent_messages (
        conversation_id, user_id, role, content, tool_calls_json, tool_call_id,
        trace_id, turn_id, input_mode, source, active_proposal_id, metadata_json
      )
      SELECT
        ${conversationId}, ${userId}, ${input.role}, ${input.content}, ${jsonb(input.toolCalls ?? null)}, ${input.toolCallId ?? null},
        ${input.traceId ?? null}, ${input.turnId ?? null}, ${input.inputMode ?? null}, ${input.source ?? null}, ${input.activeProposalId ?? null}, ${jsonb(input.metadata ?? null)}
      WHERE EXISTS (
        SELECT 1 FROM agent_conversations
        WHERE id = ${conversationId} AND user_id = ${userId}
          AND hidden_from_user_at IS NULL
      )
      RETURNING *
    `);
    if (!row) throw new Error("agent_conversation_not_found");
    await this.execute(dbSql`
      UPDATE agent_conversations
      SET updated_at = now()
      WHERE id = ${conversationId} AND user_id = ${userId}
    `);
    return mapAgentConversationMessage(row);
  }

  async listAgentConversationMessages(
    userId: string,
    conversationId: string,
  ): Promise<AgentConversationMessageRecord[]> {
    const rows = await this.execute(dbSql`
      SELECT message.*
      FROM agent_messages message
      JOIN agent_conversations conversation
        ON conversation.id = message.conversation_id
      WHERE message.conversation_id = ${conversationId}
        AND conversation.user_id = ${userId}
        AND conversation.hidden_from_user_at IS NULL
      ORDER BY message.created_at, message.id
    `);
    return rows.map(mapAgentConversationMessage);
  }

  async saveAgentToolExecution(
    input: Omit<AgentToolExecutionRecord, "id" | "createdAt" | "updatedAt">,
  ): Promise<AgentToolExecutionRecord> {
    const [row] = await this.execute(dbSql`
      INSERT INTO agent_tool_executions (
        user_id, conversation_id, assistant_message_id, turn_id, tool_call_id,
        action_id, iteration, tool_call_index, status, snapshot_json,
        started_at, completed_at
      )
      SELECT
        ${input.userId}, ${input.conversationId}, ${input.assistantMessageId},
        ${input.turnId}, ${input.toolCallId}, ${input.actionId},
        ${input.iteration}, ${input.toolCallIndex}, ${input.status},
        ${jsonb(input.snapshot)}, ${input.snapshot.startedAt},
        ${input.snapshot.completedAt ?? null}
      WHERE EXISTS (
        SELECT 1 FROM agent_conversations
        WHERE id = ${input.conversationId} AND user_id = ${input.userId}
          AND hidden_from_user_at IS NULL
      )
      ON CONFLICT (conversation_id, tool_call_id)
      DO UPDATE SET
        snapshot_json = CASE
          WHEN agent_tool_executions.status = 'started'
            AND EXCLUDED.status <> 'started'
          THEN EXCLUDED.snapshot_json
          ELSE agent_tool_executions.snapshot_json
        END,
        status = CASE
          WHEN agent_tool_executions.status = 'started'
            AND EXCLUDED.status <> 'started'
          THEN EXCLUDED.status
          ELSE agent_tool_executions.status
        END,
        completed_at = CASE
          WHEN agent_tool_executions.status = 'started'
            AND EXCLUDED.status <> 'started'
          THEN EXCLUDED.completed_at
          ELSE agent_tool_executions.completed_at
        END,
        updated_at = CASE
          WHEN agent_tool_executions.status = 'started'
            AND EXCLUDED.status <> 'started'
          THEN now()
          ELSE agent_tool_executions.updated_at
        END
      RETURNING *
    `);
    if (!row) throw new Error("agent_conversation_not_found");
    return mapAgentToolExecution(row);
  }

  async listAgentToolExecutions(
    userId: string,
    conversationId: string,
  ): Promise<AgentToolExecutionRecord[]> {
    const rows = await this.execute(dbSql`
      SELECT execution.*
      FROM agent_tool_executions execution
      JOIN agent_conversations conversation
        ON conversation.id = execution.conversation_id
      JOIN agent_messages assistant_message
        ON assistant_message.id = execution.assistant_message_id
      WHERE execution.conversation_id = ${conversationId}
        AND execution.user_id = ${userId}
        AND conversation.user_id = ${userId}
        AND conversation.hidden_from_user_at IS NULL
      -- The assistant message anchors the chronological turn. Within that
      -- turn, provider iteration and tool position are the semantic order.
      ORDER BY assistant_message.created_at, execution.iteration,
        execution.tool_call_index, execution.created_at
    `);
    return rows.map(mapAgentToolExecution);
  }

  async commitAgentChatProposal(
    userId: string,
    input: {
      conversationId: string;
      proposalId: string;
      sourceToolCallId: string;
      clientMutationId: string;
      traceId: string;
    },
  ): Promise<AgentChatProposalCommit> {
    return this.db.transaction(async (tx) => {
      const [conversationRow] = await executeRows(
        tx,
        dbSql`
          SELECT id
          FROM agent_conversations
          WHERE id = ${input.conversationId}
            AND user_id = ${userId}
            AND hidden_from_user_at IS NULL
          FOR UPDATE
        `,
      );
      if (!conversationRow) throw new Error("agent_conversation_not_found");

      const existing = await this.findDirectChatCommit(tx, userId, input);
      if (existing) return { ...existing, reused: true };

      const [proposalRow] = await executeRows(
        tx,
        dbSql`
          SELECT * FROM meal_proposals
          WHERE id = ${input.proposalId} AND user_id = ${userId}
          FOR UPDATE
        `,
      );
      if (!proposalRow) throw new Error("proposal_not_found");

      // A different mutation key may have won while this request was waiting
      // for the proposal lock. Replay its single persisted result.
      const committedWhileWaiting = await this.findDirectChatCommit(
        tx,
        userId,
        input,
      );
      if (committedWhileWaiting)
        return { ...committedWhileWaiting, reused: true };

      const proposal = await this.mapProposal(proposalRow, "Meal", tx);
      const [existingMealRow] = await executeRows(
        tx,
        dbSql`
          SELECT * FROM meals
          WHERE user_id = ${userId} AND proposal_id = ${input.proposalId}
            AND deleted_at IS NULL
          LIMIT 1
        `,
      );
      let meal = existingMealRow
        ? await this.mapMeal(existingMealRow, tx)
        : undefined;
      if (!meal) {
        const id = newId();
        const nutrition = sumNutrition(proposal.items);
        const [mealRow] = await executeRows(
          tx,
          dbSql`
            INSERT INTO meals (
              id, user_id, proposal_id, title, occurred_at, meal_type,
              meal_type_label, calories, protein_grams, carbs_grams, fat_grams
            ) VALUES (
              ${id}, ${userId}, ${proposal.id}, ${proposal.title}, ${new Date().toISOString()},
              null, null, ${nutrition.calories}, ${nutrition.proteinGrams},
              ${nutrition.carbsGrams}, ${nutrition.fatGrams}
            )
            RETURNING *
          `,
        );
        for (const item of proposal.items) await insertMealItem(tx, id, item);
        meal = await this.mapMeal(mealRow, tx);
      }
      await executeRows(
        tx,
        dbSql`UPDATE meal_proposals SET status = 'committed' WHERE id = ${proposal.id}`,
      );

      const result = {
        kind: "meal_committed",
        sourceProposalId: proposal.id,
        meal,
        message: "Meal logged.",
      };
      const content = JSON.stringify({ actionId: "commit_meal", result });
      const [messageRow] = await executeRows(
        tx,
        dbSql`
          INSERT INTO agent_messages (
            id, conversation_id, user_id, role, content, tool_call_id,
            trace_id, source, active_proposal_id, metadata_json
          ) VALUES (
            ${newId()}, ${input.conversationId}, ${userId}, 'tool', ${content},
            ${input.sourceToolCallId}, ${input.traceId}, 'client_direct_action',
            ${proposal.id}, ${jsonb({
              actionId: "commit_meal",
              resultKind: "meal_committed",
              sourceProposalId: proposal.id,
              sourceToolCallId: input.sourceToolCallId,
              clientMutationId: input.clientMutationId,
              source: "client_direct_action",
            })}
          )
          RETURNING *
        `,
      );
      await executeRows(
        tx,
        dbSql`
          UPDATE agent_conversations SET updated_at = now()
          WHERE id = ${input.conversationId} AND user_id = ${userId}
            AND hidden_from_user_at IS NULL
        `,
      );
      const [actionRow] = await executeRows(
        tx,
        dbSql`
          INSERT INTO agent_direct_actions (
            user_id, action_id, conversation_id, proposal_id, source_tool_call_id,
            client_mutation_id, meal_id, message_id
          ) VALUES (
            ${userId}, 'commit_meal', ${input.conversationId}, ${proposal.id},
            ${input.sourceToolCallId}, ${input.clientMutationId}, ${meal.id}, ${messageRow.id as string}
          )
          RETURNING id
        `,
      );
      if (!actionRow) throw new Error("direct_action_not_persisted");
      return {
        actionId: "commit_meal",
        clientMutationId: input.clientMutationId,
        reused: false,
        meal,
        conversationMessage: mapAgentConversationMessage(messageRow),
        result: agentResultFromConversationMessage(
          mapAgentConversationMessage(messageRow),
        ),
      };
    });
  }

  private async findDirectChatCommit(
    tx: DbExecutor,
    userId: string,
    input: {
      proposalId: string;
      clientMutationId: string;
    },
  ): Promise<Omit<AgentChatProposalCommit, "reused"> | undefined> {
    const [action] = await executeRows(
      tx,
      dbSql`
        SELECT * FROM agent_direct_actions
        WHERE user_id = ${userId} AND action_id = 'commit_meal'
          AND (client_mutation_id = ${input.clientMutationId}
            OR proposal_id = ${input.proposalId})
        ORDER BY created_at
        LIMIT 1
      `,
    );
    if (!action) return undefined;
    const [mealRow] = await executeRows(
      tx,
      dbSql`SELECT * FROM meals WHERE id = ${action.meal_id as string} AND user_id = ${userId}`,
    );
    const [messageRow] = await executeRows(
      tx,
      dbSql`SELECT * FROM agent_messages WHERE id = ${action.message_id as string} AND user_id = ${userId}`,
    );
    if (!mealRow || !messageRow)
      throw new Error("direct_action_result_missing");
    return {
      actionId: "commit_meal",
      clientMutationId: action.client_mutation_id as string,
      meal: await this.mapMeal(mealRow, tx),
      conversationMessage: mapAgentConversationMessage(messageRow),
      result: agentResultFromConversationMessage(
        mapAgentConversationMessage(messageRow),
      ),
    };
  }

  async persistAgentChatProposalCommitResult(
    userId: string,
    input: {
      conversationId: string;
      messageId: string;
      result: unknown;
    },
  ): Promise<AgentConversationMessageRecord> {
    const content = JSON.stringify({
      actionId: "commit_meal",
      result: input.result,
    });
    const [row] = await this.execute(dbSql`
      UPDATE agent_messages
      SET
        content = CASE
          WHEN COALESCE(metadata_json, '{}'::jsonb) ? 'uiResult'
          THEN content
          ELSE ${content}
        END,
        metadata_json = CASE
          WHEN COALESCE(metadata_json, '{}'::jsonb) ? 'uiResult'
          THEN metadata_json
          ELSE COALESCE(metadata_json, '{}'::jsonb) || ${jsonb({ uiResult: input.result })}
        END
      WHERE id = ${input.messageId}
        AND conversation_id = ${input.conversationId}
        AND user_id = ${userId}
      RETURNING *
    `);
    if (!row) throw new Error("agent_direct_action_message_not_found");
    return mapAgentConversationMessage(row);
  }

  async saveAgentCandidateRegistry(
    input: Omit<AgentCandidateRegistryRecord, "id" | "createdAt">,
  ): Promise<AgentCandidateRegistryRecord> {
    const [row] = await this.execute(dbSql`
      INSERT INTO agent_candidate_registries (
        user_id, conversation_id, message_id, trace_id, turn_id, action_call_id,
        search_ref, action_id, candidate_count, group_count, threshold,
        registry_json
      )
      VALUES (
        ${input.userId}, ${input.conversationId}, ${input.messageId ?? null},
        ${input.traceId ?? null}, ${input.turnId ?? null}, ${input.actionCallId ?? null},
        ${input.searchRef}, ${input.actionId}, ${input.candidateCount},
        ${input.groupCount}, ${input.threshold ?? null}, ${jsonb(input.registry)}
      )
      ON CONFLICT (user_id, search_ref)
      DO UPDATE SET
        conversation_id = EXCLUDED.conversation_id,
        message_id = COALESCE(EXCLUDED.message_id, agent_candidate_registries.message_id),
        trace_id = EXCLUDED.trace_id,
        turn_id = EXCLUDED.turn_id,
        action_call_id = EXCLUDED.action_call_id,
        action_id = EXCLUDED.action_id,
        candidate_count = EXCLUDED.candidate_count,
        group_count = EXCLUDED.group_count,
        threshold = EXCLUDED.threshold,
        registry_json = EXCLUDED.registry_json
      RETURNING *
    `);
    return mapAgentCandidateRegistry(row);
  }

  async getAgentCandidateRegistryBySearchRef(
    userId: string,
    searchRef: string,
  ): Promise<AgentCandidateRegistryRecord | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT *
      FROM agent_candidate_registries
      WHERE user_id = ${userId}
        AND search_ref = ${searchRef}
      LIMIT 1
    `);
    return row ? mapAgentCandidateRegistry(row) : undefined;
  }

  async getLatestAgentCandidateRegistry(
    userId: string,
    conversationId: string,
  ): Promise<AgentCandidateRegistryRecord | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT registry.*
      FROM agent_candidate_registries registry
      JOIN agent_conversations conversation
        ON conversation.id = registry.conversation_id
      WHERE registry.user_id = ${userId}
        AND registry.conversation_id = ${conversationId}
        AND conversation.user_id = ${userId}
      ORDER BY registry.created_at DESC, registry.id DESC
      LIMIT 1
    `);
    return row ? mapAgentCandidateRegistry(row) : undefined;
  }

  async listAdminAgentConversations(
    filter: AdminConversationFilter,
  ): Promise<AgentConversationRecord[]> {
    const limit = boundedLimit(filter.limit, 100);
    const rows = await withSpan(
      "PostgresRepository.listAdminAgentConversations",
      {
        limit,
        userId: filter.userId,
        traceId: filter.traceId,
        turnId: filter.turnId,
        includeHidden: filter.includeHidden,
      },
      () =>
        this.execute(dbSql`
          SELECT DISTINCT conversation.*
          FROM agent_conversations conversation
          LEFT JOIN agent_messages message
            ON message.conversation_id = conversation.id
          WHERE (${filter.includeHidden ?? false}::boolean OR conversation.hidden_from_user_at IS NULL)
            AND NOT EXISTS (
              SELECT 1 FROM privacy_deletion_requests suppression
              WHERE suppression.conversation_id = conversation.id
            )
            AND (${filter.userId ?? null}::uuid IS NULL OR conversation.user_id = ${filter.userId ?? null})
            AND (${filter.conversationId ?? null}::uuid IS NULL OR conversation.id = ${filter.conversationId ?? null})
            AND (${filter.traceId ?? null}::text IS NULL OR message.trace_id = ${filter.traceId ?? null})
            AND (${filter.turnId ?? null}::uuid IS NULL OR message.turn_id = ${filter.turnId ?? null})
            AND (${filter.from ?? null}::timestamptz IS NULL OR conversation.updated_at >= ${filter.from ?? null})
            AND (${filter.to ?? null}::timestamptz IS NULL OR conversation.updated_at <= ${filter.to ?? null})
          ORDER BY conversation.updated_at DESC
          LIMIT ${limit}
        `),
    );
    return rows.map(mapAgentConversation);
  }

  async getAdminAgentConversationMessages(
    conversationId: string,
    includeHidden = false,
  ): Promise<AgentConversationMessageRecord[]> {
    const rows = await this.execute(dbSql`
      SELECT message.*
      FROM agent_messages message
      JOIN agent_conversations conversation
        ON conversation.id = message.conversation_id
      WHERE message.conversation_id = ${conversationId}
        AND (${includeHidden}::boolean OR conversation.hidden_from_user_at IS NULL)
        AND NOT EXISTS (
          SELECT 1 FROM privacy_deletion_requests suppression
          WHERE suppression.conversation_id = conversation.id
        )
      ORDER BY message.created_at, message.id
    `);
    return rows.map(mapAgentConversationMessage);
  }

  async listAgentConversationMessagesByTrace(
    traceId: string,
    includeHidden = false,
  ): Promise<AgentConversationMessageRecord[]> {
    const rows = await this.execute(dbSql`
      SELECT message.*
      FROM agent_messages message
      JOIN agent_conversations conversation
        ON conversation.id = message.conversation_id
      WHERE message.trace_id = ${traceId}
        AND (${includeHidden}::boolean OR conversation.hidden_from_user_at IS NULL)
        AND NOT EXISTS (
          SELECT 1 FROM privacy_deletion_requests suppression
          WHERE suppression.conversation_id = conversation.id
        )
      ORDER BY message.created_at, message.id
      LIMIT 500
    `);
    return rows.map(mapAgentConversationMessage);
  }

  async deleteAgentConversation(
    userId: string,
    conversationId: string,
  ): Promise<boolean> {
    return this.hideAgentConversationFromUser(userId, conversationId);
  }

  async hideAgentConversationFromUser(
    userId: string,
    conversationId: string,
  ): Promise<boolean> {
    const rows = await this.execute(dbSql`
      UPDATE agent_conversations
      SET hidden_from_user_at = COALESCE(hidden_from_user_at, now()),
          updated_at = now()
      WHERE id = ${conversationId} AND user_id = ${userId}
        AND hidden_from_user_at IS NULL
      RETURNING id
    `);
    return rows.length > 0;
  }

  async requestAgentConversationDeletion(
    userId: string,
    conversationId: string,
  ): Promise<PrivacyDeletionRequest | undefined> {
    return this.db.transaction(async (tx) => {
      await executeRows(
        tx,
        dbSql`
        SELECT pg_advisory_xact_lock(hashtext(${conversationId}))
      `,
      );
      const existing = await executeRows(
        tx,
        dbSql`
        SELECT * FROM privacy_deletion_requests
        WHERE conversation_id = ${conversationId}
          AND subject_user_id = ${userId}
        LIMIT 1
      `,
      );
      if (existing[0]) return mapPrivacyDeletionRequest(existing[0]);

      const owned = await executeRows(
        tx,
        dbSql`
        SELECT id FROM agent_conversations
        WHERE id = ${conversationId} AND user_id = ${userId}
        FOR UPDATE
      `,
      );
      if (!owned[0]) return undefined;

      const rows = await executeRows(
        tx,
        dbSql`
        INSERT INTO privacy_deletion_requests (
          subject_user_id, conversation_id, purge_due_at
        ) VALUES (
          ${userId}, ${conversationId}, now() + interval '24 hours'
        )
        ON CONFLICT (conversation_id) DO NOTHING
        RETURNING *
      `,
      );
      const request =
        rows[0] ??
        (
          await executeRows(
            tx,
            dbSql`
        SELECT * FROM privacy_deletion_requests
        WHERE conversation_id = ${conversationId}
          AND subject_user_id = ${userId}
        LIMIT 1
      `,
          )
        )[0];
      if (!request) return undefined;
      await executeRows(
        tx,
        dbSql`
        UPDATE agent_conversations
        SET hidden_from_user_at = COALESCE(hidden_from_user_at, now()),
            updated_at = now()
        WHERE id = ${conversationId} AND user_id = ${userId}
      `,
      );
      return mapPrivacyDeletionRequest(request);
    });
  }

  async getAgentConversationDeletion(
    userId: string,
    conversationId: string,
  ): Promise<PrivacyDeletionRequest | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT * FROM privacy_deletion_requests
      WHERE conversation_id = ${conversationId}
        AND subject_user_id = ${userId}
      LIMIT 1
    `);
    return row ? mapPrivacyDeletionRequest(row) : undefined;
  }

  async isAgentConversationSuppressed(
    conversationId: string,
  ): Promise<boolean> {
    const [row] = await this.execute(dbSql`
      SELECT 1 AS suppressed FROM privacy_deletion_requests
      WHERE conversation_id = ${conversationId}
      LIMIT 1
    `);
    return Boolean(row);
  }

  async runPrivacyLifecycle(
    input: {
      now?: string;
      batchSize?: number;
      reapplyBefore?: string;
    } = {},
  ): Promise<PrivacyLifecycleResult> {
    const batchSize = Math.max(
      1,
      Math.min(100, Math.floor(input.batchSize ?? 25)),
    );
    const effectiveNow = input.now ?? new Date().toISOString();
    return this.db.transaction(async (tx) => {
      const [lock] = await executeRows(
        tx,
        dbSql`
        SELECT pg_try_advisory_xact_lock(hashtext('bettercalories-privacy-lifecycle-v1')) AS acquired
      `,
      );
      if (!lock?.acquired) {
        return {
          lockAcquired: false,
          processed: 0,
          purged: 0,
          failed: 0,
          rawTelemetryExpired: 0,
        };
      }
      const requests = await executeRows(
        tx,
        dbSql`
        SELECT * FROM privacy_deletion_requests
        WHERE status IN ('pending', 'failed')
          OR (
            ${input.reapplyBefore ?? null}::timestamptz IS NOT NULL
            AND status = 'purged'
            AND (last_attempt_at IS NULL OR last_attempt_at < ${input.reapplyBefore ?? null})
          )
        ORDER BY requested_at
        LIMIT ${batchSize}
        FOR UPDATE SKIP LOCKED
      `,
      );
      let purged = 0;
      let failed = 0;
      for (const row of requests) {
        try {
          await tx.transaction(async (savepoint) => {
            await purgeConversationContent(
              savepoint,
              row.conversation_id as string,
            );
            await executeRows(
              savepoint,
              dbSql`
              UPDATE privacy_deletion_requests
              SET status = 'purged', purged_at = COALESCE(purged_at, ${effectiveNow}),
                  last_attempt_at = ${effectiveNow}, attempt_count = attempt_count + 1,
                  result_code = 'active_content_purged'
              WHERE id = ${row.id as string}
            `,
            );
          });
          purged++;
        } catch {
          await executeRows(
            tx,
            dbSql`
            UPDATE privacy_deletion_requests
            SET status = 'failed', last_attempt_at = ${effectiveNow},
                attempt_count = attempt_count + 1,
                result_code = 'purge_retry_required'
            WHERE id = ${row.id as string}
          `,
          );
          failed++;
        }
      }

      const cutoff = new Date(
        Date.parse(effectiveNow) - 30 * 24 * 60 * 60 * 1000,
      ).toISOString();
      let rawTelemetryExpired = 0;
      const scrubQueries = [
        dbSql`UPDATE telemetry_events SET error_message = NULL, metadata_json = '{}'::jsonb WHERE created_at < ${cutoff} AND (error_message IS NOT NULL OR metadata_json <> '{}'::jsonb) RETURNING id`,
        dbSql`UPDATE llm_runs SET metadata_json = '{}'::jsonb WHERE created_at < ${cutoff} AND metadata_json <> '{}'::jsonb RETURNING id`,
        dbSql`UPDATE food_search_events SET query_text = NULL, metadata_json = '{}'::jsonb WHERE created_at < ${cutoff} AND (query_text IS NOT NULL OR metadata_json <> '{}'::jsonb) RETURNING id`,
        dbSql`UPDATE agent_turn_telemetry SET input_text = NULL, assistant_text = NULL, error_message = NULL, metadata_json = '{}'::jsonb WHERE created_at < ${cutoff} AND (input_text IS NOT NULL OR assistant_text IS NOT NULL OR error_message IS NOT NULL OR metadata_json <> '{}'::jsonb) RETURNING id`,
        dbSql`UPDATE agent_tool_call_telemetry SET arguments_json = NULL, result_summary_json = NULL, error_message = NULL, metadata_json = '{}'::jsonb WHERE created_at < ${cutoff} AND (arguments_json IS NOT NULL OR result_summary_json IS NOT NULL OR error_message IS NOT NULL OR metadata_json <> '{}'::jsonb) RETURNING id`,
        dbSql`UPDATE llm_provider_calls SET error_message = NULL, metadata_json = '{}'::jsonb WHERE created_at < ${cutoff} AND (error_message IS NOT NULL OR metadata_json <> '{}'::jsonb) RETURNING id`,
        dbSql`UPDATE transcription_records SET transcript_text = NULL, error_message = NULL, metadata_json = '{}'::jsonb WHERE created_at < ${cutoff} AND (transcript_text IS NOT NULL OR error_message IS NOT NULL OR metadata_json <> '{}'::jsonb) RETURNING id`,
      ];
      for (const query of scrubQueries) {
        rawTelemetryExpired += (await executeRows(tx, query)).length;
      }
      return {
        lockAcquired: true,
        processed: requests.length,
        purged,
        failed,
        rawTelemetryExpired,
      };
    });
  }

  async recordActionCall(
    input: Omit<ActionCallRecord, "id" | "createdAt">,
  ): Promise<ActionCallRecord> {
    const [row] = await withSpan(
      "PostgresRepository.recordActionCall",
      { actionId: input.actionId, status: input.confirmationStatus },
      () =>
        this.execute(dbSql`
      INSERT INTO action_calls (user_id, action_id, source, input_json, output_json, error_json, confirmation_status, trace_id, latency_ms)
      VALUES (${input.userId}, ${input.actionId}, ${input.source}, ${jsonb(input.input)}, ${jsonb(input.output ?? null)}, ${jsonb(input.error ?? null)}, ${input.confirmationStatus}, ${input.traceId}, ${input.latencyMs})
      RETURNING *
    `),
    );
    return mapActionCall(row);
  }

  async recordAuditEvent(
    input: Omit<AuditEventRecord, "id" | "createdAt">,
  ): Promise<AuditEventRecord> {
    const [row] = await withSpan(
      "PostgresRepository.recordAuditEvent",
      { eventType: input.eventType },
      () =>
        this.execute(dbSql`
      INSERT INTO audit_events (user_id, event_type, metadata_json, trace_id)
      VALUES (${input.userId ?? null}, ${input.eventType}, ${jsonb(input.metadata)}, ${input.traceId})
      RETURNING *
    `),
    );
    return mapAuditEvent(row);
  }

  async listActionCalls(userId: string): Promise<ActionCallRecord[]> {
    const rows = await this.execute(
      dbSql`SELECT * FROM action_calls WHERE user_id = ${userId} ORDER BY created_at`,
    );
    return rows.map(mapActionCall);
  }

  async listAdminActionCalls(
    filter: AdminActionCallFilter,
  ): Promise<ActionCallRecord[]> {
    const limit = boundedLimit(filter.limit, 100);
    const rows = await withSpan(
      "PostgresRepository.listAdminActionCalls",
      { limit, userId: filter.userId, traceId: filter.traceId },
      () =>
        this.execute(dbSql`
          SELECT * FROM action_calls
          WHERE (${filter.userId ?? null}::uuid IS NULL OR user_id = ${filter.userId ?? null})
            AND (${filter.traceId ?? null}::text IS NULL OR trace_id = ${filter.traceId ?? null})
            AND (${filter.actionId ?? null}::text IS NULL OR action_id = ${filter.actionId ?? null})
            AND (${filter.from ?? null}::timestamptz IS NULL OR created_at >= ${filter.from ?? null})
            AND (${filter.to ?? null}::timestamptz IS NULL OR created_at <= ${filter.to ?? null})
          ORDER BY created_at DESC
          LIMIT ${limit}
        `),
    );
    return rows.map(mapActionCall);
  }

  async listAuditEvents(userId: string): Promise<AuditEventRecord[]> {
    const rows = await this.execute(
      dbSql`SELECT * FROM audit_events WHERE user_id = ${userId} ORDER BY created_at`,
    );
    return rows.map(mapAuditEvent);
  }

  async createTelemetryEvent(
    input: Omit<TelemetryEventRecord, "id" | "createdAt">,
  ): Promise<TelemetryEventRecord> {
    const [row] = await withSpan(
      "PostgresRepository.createTelemetryEvent",
      {
        eventType: input.eventType,
        surface: input.surface,
        severity: input.severity,
      },
      () =>
        this.execute(dbSql`
          INSERT INTO telemetry_events (
            trace_id, user_id, session_id, event_type, flow, surface, severity, status,
            route, method, action_id, duration_ms, error_code, error_message,
            app_version, app_build, platform, locale, metadata_json
          )
          VALUES (
            ${input.traceId}, ${input.userId ?? null}, ${input.sessionId ?? null}, ${input.eventType}, ${input.flow ?? null}, ${input.surface}, ${input.severity}, ${input.status ?? null},
            ${input.route ?? null}, ${input.method ?? null}, ${input.actionId ?? null}, ${input.durationMs ?? null}, ${input.errorCode ?? null}, ${input.errorMessage ?? null},
            ${input.appVersion ?? null}, ${input.appBuild ?? null}, ${input.platform ?? null}, ${input.locale ?? null}, ${jsonb(input.metadata)}
          )
          RETURNING *
        `),
    );
    return mapTelemetryEvent(row);
  }

  async listTelemetryEvents(
    filter: TelemetryEventFilter,
  ): Promise<TelemetryEventRecord[]> {
    const limit = filter.limit ?? 100;
    const rows = await withSpan(
      "PostgresRepository.listTelemetryEvents",
      {
        limit,
        severity: filter.severity,
        eventType: filter.eventType,
        surface: filter.surface,
        traceId: filter.traceId,
        userId: filter.userId,
      },
      () =>
        this.execute(dbSql`
          SELECT * FROM telemetry_events
          WHERE (${filter.severity ?? null}::text IS NULL OR severity = ${filter.severity ?? null})
            AND (${filter.eventType ?? null}::text IS NULL OR event_type = ${filter.eventType ?? null})
            AND (${filter.surface ?? null}::text IS NULL OR surface = ${filter.surface ?? null})
            AND (${filter.traceId ?? null}::text IS NULL OR trace_id = ${filter.traceId ?? null})
            AND (${filter.userId ?? null}::uuid IS NULL OR user_id = ${filter.userId ?? null})
            AND (${filter.from ?? null}::timestamptz IS NULL OR created_at >= ${filter.from ?? null})
            AND (${filter.to ?? null}::timestamptz IS NULL OR created_at <= ${filter.to ?? null})
          ORDER BY created_at DESC
          LIMIT ${limit}
        `),
    );
    return rows.map(mapTelemetryEvent);
  }

  async createLlmRun(
    input: Omit<LlmRunRecord, "id" | "createdAt">,
  ): Promise<LlmRunRecord> {
    const [row] = await withSpan(
      "PostgresRepository.createLlmRun",
      {
        model: input.model,
        resultKind: input.resultKind,
        selectedTool: input.selectedTool,
      },
      () =>
        this.execute(dbSql`
          INSERT INTO llm_runs (
            trace_id, user_id, source, locale, timezone, model, input_mode,
            conversation_id, turn_id, provider, provider_request_id,
            provider_generation_id,
            active_proposal_id, decision_source, selected_tool, executed_tool, result_kind, action_call_id,
            prompt_chars, tools_json_chars, messages_json_chars, request_payload_chars,
            prompt_tokens, completion_tokens, total_tokens, reasoning_tokens,
            first_byte_ms, first_tool_call_ms, largest_stream_gap_ms,
            llm_ms, action_ms, total_ms,
            empty_tool_call, invalid_tool_arguments, provider_error,
            provider_cost_amount, estimated_cost_amount, cost_currency,
            cost_source, pricing_snapshot_json, metadata_json
          )
          VALUES (
            ${input.traceId}, ${input.userId ?? null}, ${input.source ?? null}, ${input.locale ?? null}, ${input.timezone ?? null}, ${input.model}, ${input.inputMode ?? null},
            ${input.conversationId ?? null}, ${input.turnId ?? null}, ${input.provider ?? null}, ${input.providerRequestId ?? null},
            ${input.providerGenerationId ?? null},
            ${input.activeProposalId ?? null}, ${input.decisionSource ?? null}, ${input.selectedTool ?? null}, ${input.executedTool ?? null}, ${input.resultKind ?? null}, ${input.actionCallId ?? null},
            ${input.promptChars ?? null}, ${input.toolsJsonChars ?? null}, ${input.messagesJsonChars ?? null}, ${input.requestPayloadChars ?? null},
            ${input.promptTokens ?? null}, ${input.completionTokens ?? null}, ${input.totalTokens ?? null}, ${input.reasoningTokens ?? null},
            ${input.firstByteMs ?? null}, ${input.firstToolCallMs ?? null}, ${input.largestStreamGapMs ?? null},
            ${input.llmMs ?? null}, ${input.actionMs ?? null}, ${input.totalMs ?? null},
            ${input.emptyToolCall}, ${input.invalidToolArguments}, ${input.providerError},
            ${input.providerCostAmount ?? null}, ${input.estimatedCostAmount ?? null}, ${input.costCurrency ?? null},
            ${input.costSource ?? null}, ${jsonb(input.pricingSnapshot ?? {})}, ${jsonb(input.metadata)}
          )
          RETURNING *
        `),
    );
    return mapLlmRun(row);
  }

  async listLlmRuns(filter: LlmRunFilter): Promise<LlmRunRecord[]> {
    const limit = filter.limit ?? 100;
    const rows = await withSpan(
      "PostgresRepository.listLlmRuns",
      {
        limit,
        resultKind: filter.resultKind,
        selectedTool: filter.selectedTool,
        traceId: filter.traceId,
        userId: filter.userId,
      },
      () =>
        this.execute(dbSql`
          SELECT * FROM llm_runs
          WHERE (${filter.resultKind ?? null}::text IS NULL OR result_kind = ${filter.resultKind ?? null})
            AND (${filter.selectedTool ?? null}::text IS NULL OR selected_tool = ${filter.selectedTool ?? null})
            AND (${filter.executedTool ?? null}::text IS NULL OR executed_tool = ${filter.executedTool ?? null})
            AND (${filter.traceId ?? null}::text IS NULL OR trace_id = ${filter.traceId ?? null})
            AND (${filter.userId ?? null}::uuid IS NULL OR user_id = ${filter.userId ?? null})
            AND (${filter.conversationId ?? null}::uuid IS NULL OR conversation_id = ${filter.conversationId ?? null})
            AND (${filter.turnId ?? null}::uuid IS NULL OR turn_id = ${filter.turnId ?? null})
            AND (${filter.from ?? null}::timestamptz IS NULL OR created_at >= ${filter.from ?? null})
            AND (${filter.to ?? null}::timestamptz IS NULL OR created_at <= ${filter.to ?? null})
          ORDER BY created_at DESC
          LIMIT ${limit}
        `),
    );
    return rows.map(mapLlmRun);
  }

  async createAgentTurnTelemetry(
    input: Omit<AgentTurnTelemetryRecord, "id" | "createdAt">,
  ): Promise<AgentTurnTelemetryRecord> {
    const [row] = await withSpan(
      "PostgresRepository.createAgentTurnTelemetry",
      { traceId: input.traceId, turnId: input.turnId },
      () =>
        this.execute(dbSql`
          INSERT INTO agent_turn_telemetry (
            conversation_id, trace_id, turn_id, user_id, input_mode, source,
            active_proposal_id, model, input_text, assistant_text, result_kind,
            stop_reason, iteration_count, tool_call_count, prompt_chars,
            messages_json_chars, tools_json_chars, request_payload_chars,
            prompt_tokens, completion_tokens, total_tokens, reasoning_tokens,
            provider_cost_amount, estimated_cost_amount, cost_currency,
            cost_source, pricing_snapshot_json, first_byte_ms,
            first_tool_call_ms, largest_stream_gap_ms, llm_ms, action_ms,
            total_ms, status, error_code, error_message, metadata_json,
            completed_at
          )
          VALUES (
            ${input.conversationId ?? null}, ${input.traceId}, ${input.turnId}, ${input.userId ?? null}, ${input.inputMode ?? null}, ${input.source ?? null},
            ${input.activeProposalId ?? null}, ${input.model ?? null}, ${input.inputText ?? null}, ${input.assistantText ?? null}, ${input.resultKind ?? null},
            ${input.stopReason ?? null}, ${input.iterationCount}, ${input.toolCallCount}, ${input.promptChars ?? null},
            ${input.messagesJsonChars ?? null}, ${input.toolsJsonChars ?? null}, ${input.requestPayloadChars ?? null},
            ${input.promptTokens ?? null}, ${input.completionTokens ?? null}, ${input.totalTokens ?? null}, ${input.reasoningTokens ?? null},
            ${input.providerCostAmount ?? null}, ${input.estimatedCostAmount ?? null}, ${input.costCurrency ?? null},
            ${input.costSource ?? null}, ${jsonb(input.pricingSnapshot)}, ${input.firstByteMs ?? null},
            ${input.firstToolCallMs ?? null}, ${input.largestStreamGapMs ?? null}, ${input.llmMs ?? null}, ${input.actionMs ?? null},
            ${input.totalMs ?? null}, ${input.status}, ${input.errorCode ?? null}, ${input.errorMessage ?? null}, ${jsonb(input.metadata)},
            ${input.completedAt ?? null}
          )
          ON CONFLICT (turn_id) DO UPDATE SET
            assistant_text = EXCLUDED.assistant_text,
            result_kind = EXCLUDED.result_kind,
            stop_reason = EXCLUDED.stop_reason,
            iteration_count = EXCLUDED.iteration_count,
            tool_call_count = EXCLUDED.tool_call_count,
            prompt_tokens = EXCLUDED.prompt_tokens,
            completion_tokens = EXCLUDED.completion_tokens,
            total_tokens = EXCLUDED.total_tokens,
            reasoning_tokens = EXCLUDED.reasoning_tokens,
            provider_cost_amount = EXCLUDED.provider_cost_amount,
            estimated_cost_amount = EXCLUDED.estimated_cost_amount,
            cost_currency = EXCLUDED.cost_currency,
            cost_source = EXCLUDED.cost_source,
            pricing_snapshot_json = EXCLUDED.pricing_snapshot_json,
            first_byte_ms = EXCLUDED.first_byte_ms,
            first_tool_call_ms = EXCLUDED.first_tool_call_ms,
            largest_stream_gap_ms = EXCLUDED.largest_stream_gap_ms,
            llm_ms = EXCLUDED.llm_ms,
            action_ms = EXCLUDED.action_ms,
            total_ms = EXCLUDED.total_ms,
            status = EXCLUDED.status,
            error_code = EXCLUDED.error_code,
            error_message = EXCLUDED.error_message,
            metadata_json = EXCLUDED.metadata_json,
            completed_at = EXCLUDED.completed_at
          RETURNING *
        `),
    );
    return mapAgentTurnTelemetry(row);
  }

  async listAgentTurnTelemetry(
    filter: AgentTurnTelemetryFilter,
  ): Promise<AgentTurnTelemetryRecord[]> {
    const limit = boundedLimit(filter.limit, 100);
    const rows = await this.execute(dbSql`
      SELECT * FROM agent_turn_telemetry
      WHERE (${filter.userId ?? null}::uuid IS NULL OR user_id = ${filter.userId ?? null})
        AND (${filter.conversationId ?? null}::uuid IS NULL OR conversation_id = ${filter.conversationId ?? null})
        AND (${filter.traceId ?? null}::text IS NULL OR trace_id = ${filter.traceId ?? null})
        AND (${filter.turnId ?? null}::uuid IS NULL OR turn_id = ${filter.turnId ?? null})
        AND (${filter.inputMode ?? null}::text IS NULL OR input_mode = ${filter.inputMode ?? null})
        AND (${filter.status ?? null}::text IS NULL OR status = ${filter.status ?? null})
        AND (${filter.from ?? null}::timestamptz IS NULL OR created_at >= ${filter.from ?? null})
        AND (${filter.to ?? null}::timestamptz IS NULL OR created_at <= ${filter.to ?? null})
      ORDER BY created_at DESC
      LIMIT ${limit}
    `);
    return rows.map(mapAgentTurnTelemetry);
  }

  async createAgentToolCallTelemetry(
    input: Omit<AgentToolCallTelemetryRecord, "id" | "createdAt">,
  ): Promise<AgentToolCallTelemetryRecord> {
    const [row] = await this.execute(dbSql`
      INSERT INTO agent_tool_call_telemetry (
        agent_turn_id, conversation_id, trace_id, turn_id, user_id,
        tool_call_id, action_call_id, action_id, arguments_json,
        result_summary_json, status, error_message, started_at, completed_at,
        duration_ms, metadata_json
      )
      VALUES (
        ${input.agentTurnId ?? null}, ${input.conversationId ?? null}, ${input.traceId}, ${input.turnId ?? null}, ${input.userId ?? null},
        ${input.toolCallId ?? null}, ${input.actionCallId ?? null}, ${input.actionId}, ${jsonb(input.arguments ?? null)},
        ${jsonb(input.resultSummary ?? null)}, ${input.status}, ${input.errorMessage ?? null}, ${input.startedAt}, ${input.completedAt ?? null},
        ${input.durationMs ?? null}, ${jsonb(input.metadata)}
      )
      RETURNING *
    `);
    return mapAgentToolCallTelemetry(row);
  }

  async listAgentToolCallTelemetry(
    filter: AgentToolCallTelemetryFilter,
  ): Promise<AgentToolCallTelemetryRecord[]> {
    const limit = boundedLimit(filter.limit, 100);
    const rows = await this.execute(dbSql`
      SELECT * FROM agent_tool_call_telemetry
      WHERE (${filter.userId ?? null}::uuid IS NULL OR user_id = ${filter.userId ?? null})
        AND (${filter.conversationId ?? null}::uuid IS NULL OR conversation_id = ${filter.conversationId ?? null})
        AND (${filter.traceId ?? null}::text IS NULL OR trace_id = ${filter.traceId ?? null})
        AND (${filter.turnId ?? null}::uuid IS NULL OR turn_id = ${filter.turnId ?? null})
        AND (${filter.actionId ?? null}::text IS NULL OR action_id = ${filter.actionId ?? null})
        AND (${filter.status ?? null}::text IS NULL OR status = ${filter.status ?? null})
        AND (${filter.from ?? null}::timestamptz IS NULL OR created_at >= ${filter.from ?? null})
        AND (${filter.to ?? null}::timestamptz IS NULL OR created_at <= ${filter.to ?? null})
      ORDER BY created_at DESC
      LIMIT ${limit}
    `);
    return rows.map(mapAgentToolCallTelemetry);
  }

  async createLlmProviderCall(
    input: Omit<LlmProviderCallRecord, "id" | "createdAt">,
  ): Promise<LlmProviderCallRecord> {
    const [row] = await this.execute(dbSql`
      INSERT INTO llm_provider_calls (
        trace_id, user_id, conversation_id, agent_turn_id, turn_id,
        action_call_id, feature_surface, provider, provider_request_id,
        provider_generation_id, requested_model, served_model, routing_json,
        input_mode, prompt_tokens, completion_tokens, total_tokens,
        reasoning_tokens, cached_input_tokens, audio_tokens, image_tokens,
        provider_cost_amount, estimated_cost_amount, cost_currency,
        cost_source, input_token_unit_price, output_token_unit_price,
        reasoning_token_unit_price, cached_input_token_unit_price,
        audio_token_unit_price, image_token_unit_price, pricing_source,
        pricing_version, pricing_effective_at, status, error_code,
        error_message, duration_ms, metadata_json
      )
      VALUES (
        ${input.traceId}, ${input.userId ?? null}, ${input.conversationId ?? null}, ${input.agentTurnId ?? null}, ${input.turnId ?? null},
        ${input.actionCallId ?? null}, ${input.featureSurface}, ${input.provider}, ${input.providerRequestId ?? null},
        ${input.providerGenerationId ?? null}, ${input.requestedModel}, ${input.servedModel ?? null}, ${jsonb(input.routing ?? null)},
        ${input.inputMode ?? null}, ${input.promptTokens ?? null}, ${input.completionTokens ?? null}, ${input.totalTokens ?? null},
        ${input.reasoningTokens ?? null}, ${input.cachedInputTokens ?? null}, ${input.audioTokens ?? null}, ${input.imageTokens ?? null},
        ${input.providerCostAmount ?? null}, ${input.estimatedCostAmount ?? null}, ${input.costCurrency ?? null},
        ${input.costSource}, ${input.inputTokenUnitPrice ?? null}, ${input.outputTokenUnitPrice ?? null},
        ${input.reasoningTokenUnitPrice ?? null}, ${input.cachedInputTokenUnitPrice ?? null},
        ${input.audioTokenUnitPrice ?? null}, ${input.imageTokenUnitPrice ?? null}, ${input.pricingSource ?? null},
        ${input.pricingVersion ?? null}, ${input.pricingEffectiveAt ?? null}, ${input.status}, ${input.errorCode ?? null},
        ${input.errorMessage ?? null}, ${input.durationMs ?? null}, ${jsonb(input.metadata)}
      )
      RETURNING *
    `);
    return mapLlmProviderCall(row);
  }

  async listLlmProviderCalls(
    filter: LlmProviderCallFilter,
  ): Promise<LlmProviderCallRecord[]> {
    const limit = boundedLimit(filter.limit, 100);
    const rows = await this.execute(dbSql`
      SELECT * FROM llm_provider_calls
      WHERE (${filter.userId ?? null}::uuid IS NULL OR user_id = ${filter.userId ?? null})
        AND (${filter.conversationId ?? null}::uuid IS NULL OR conversation_id = ${filter.conversationId ?? null})
        AND (${filter.traceId ?? null}::text IS NULL OR trace_id = ${filter.traceId ?? null})
        AND (${filter.turnId ?? null}::uuid IS NULL OR turn_id = ${filter.turnId ?? null})
        AND (${filter.provider ?? null}::text IS NULL OR provider = ${filter.provider ?? null})
        AND (${filter.model ?? null}::text IS NULL OR requested_model = ${filter.model ?? null})
        AND (${filter.status ?? null}::text IS NULL OR status = ${filter.status ?? null})
        AND (${filter.costSource ?? null}::text IS NULL OR cost_source = ${filter.costSource ?? null})
        AND (${filter.from ?? null}::timestamptz IS NULL OR created_at >= ${filter.from ?? null})
        AND (${filter.to ?? null}::timestamptz IS NULL OR created_at <= ${filter.to ?? null})
      ORDER BY created_at DESC
      LIMIT ${limit}
    `);
    return rows.map(mapLlmProviderCall);
  }

  async createTranscriptionRecord(
    input: Omit<TranscriptionRecord, "id" | "createdAt">,
  ): Promise<TranscriptionRecord> {
    const [row] = await this.execute(dbSql`
      INSERT INTO transcription_records (
        trace_id, user_id, conversation_id, turn_id, surface, provider, model,
        language, audio_mime_type, audio_bytes, audio_duration_ms,
        transcript_text, transcript_length, duration_ms, status, error_code,
        error_message, downstream_result_kind, metadata_json
      )
      VALUES (
        ${input.traceId}, ${input.userId ?? null}, ${input.conversationId ?? null}, ${input.turnId ?? null}, ${input.surface}, ${input.provider ?? null}, ${input.model ?? null},
        ${input.language ?? null}, ${input.audioMimeType ?? null}, ${input.audioBytes ?? null}, ${input.audioDurationMs ?? null},
        ${input.transcriptText ?? null}, ${input.transcriptLength}, ${input.durationMs ?? null}, ${input.status}, ${input.errorCode ?? null},
        ${input.errorMessage ?? null}, ${input.downstreamResultKind ?? null}, ${jsonb(input.metadata)}
      )
      RETURNING *
    `);
    return mapTranscriptionRecord(row);
  }

  async listTranscriptionRecords(
    filter: TranscriptionRecordFilter,
  ): Promise<TranscriptionRecord[]> {
    const limit = boundedLimit(filter.limit, 100);
    const rows = await this.execute(dbSql`
      SELECT * FROM transcription_records
      WHERE (${filter.userId ?? null}::uuid IS NULL OR user_id = ${filter.userId ?? null})
        AND (${filter.conversationId ?? null}::uuid IS NULL OR conversation_id = ${filter.conversationId ?? null})
        AND (${filter.traceId ?? null}::text IS NULL OR trace_id = ${filter.traceId ?? null})
        AND (${filter.turnId ?? null}::uuid IS NULL OR turn_id = ${filter.turnId ?? null})
        AND (${filter.surface ?? null}::text IS NULL OR surface = ${filter.surface ?? null})
        AND (${filter.status ?? null}::text IS NULL OR status = ${filter.status ?? null})
        AND (${filter.from ?? null}::timestamptz IS NULL OR created_at >= ${filter.from ?? null})
        AND (${filter.to ?? null}::timestamptz IS NULL OR created_at <= ${filter.to ?? null})
      ORDER BY created_at DESC
      LIMIT ${limit}
    `);
    return rows.map(mapTranscriptionRecord);
  }

  async getLlmCostOverview(filter: LlmCostFilter): Promise<LlmCostOverview> {
    const rows = await this.execute(dbSql`
      SELECT * FROM llm_provider_calls
      WHERE created_at >= ${filter.from}::timestamptz
        AND created_at <= ${filter.to}::timestamptz
        AND (${filter.userId ?? null}::uuid IS NULL OR user_id = ${filter.userId ?? null})
        AND (${filter.conversationId ?? null}::uuid IS NULL OR conversation_id = ${filter.conversationId ?? null})
        AND (${filter.traceId ?? null}::text IS NULL OR trace_id = ${filter.traceId ?? null})
    `);
    return buildPostgresCostOverview(
      filter.from,
      filter.to,
      rows.map(mapLlmProviderCall),
    );
  }

  async createFoodSearchEvent(
    input: Omit<FoodSearchEventRecord, "id" | "createdAt">,
  ): Promise<FoodSearchEventRecord> {
    const [row] = await withSpan(
      "PostgresRepository.createFoodSearchEvent",
      {
        zeroResults: input.zeroResults,
        lowConfidence: input.lowConfidence,
        path: input.path,
      },
      () =>
        this.execute(dbSql`
          INSERT INTO food_search_events (
            trace_id, user_id, query_text, query_hash, query_length, locale,
            barcode_present, normalized_search_enabled, normalized_scope, path,
            result_count, candidate_group_count, top_score, top_external_source, top_result_type,
            zero_results, low_confidence, selected_rank, duration_ms, metadata_json
          )
          VALUES (
            ${input.traceId}, ${input.userId ?? null}, ${input.queryText ?? null}, ${input.queryHash ?? null}, ${input.queryLength}, ${input.locale ?? null},
            ${input.barcodePresent}, ${input.normalizedSearchEnabled ?? null}, ${input.normalizedScope ?? null}, ${input.path ?? null},
            ${input.resultCount}, ${input.candidateGroupCount ?? null}, ${input.topScore ?? null}, ${input.topExternalSource ?? null}, ${input.topResultType ?? null},
            ${input.zeroResults}, ${input.lowConfidence}, ${input.selectedRank ?? null}, ${input.durationMs ?? null}, ${jsonb(input.metadata)}
          )
          RETURNING *
        `),
    );
    return mapFoodSearchEvent(row);
  }

  async listFoodSearchEvents(
    filter: FoodSearchEventFilter,
  ): Promise<FoodSearchEventRecord[]> {
    const limit = filter.limit ?? 100;
    const rows = await withSpan(
      "PostgresRepository.listFoodSearchEvents",
      {
        limit,
        zeroResults: filter.zeroResults,
        lowConfidence: filter.lowConfidence,
        path: filter.path,
        traceId: filter.traceId,
        userId: filter.userId,
      },
      () =>
        this.execute(dbSql`
          SELECT * FROM food_search_events
          WHERE (${filter.zeroResults ?? null}::boolean IS NULL OR zero_results = ${filter.zeroResults ?? null})
            AND (${filter.lowConfidence ?? null}::boolean IS NULL OR low_confidence = ${filter.lowConfidence ?? null})
            AND (${filter.path ?? null}::text IS NULL OR path = ${filter.path ?? null})
            AND (${filter.traceId ?? null}::text IS NULL OR trace_id = ${filter.traceId ?? null})
            AND (${filter.userId ?? null}::uuid IS NULL OR user_id = ${filter.userId ?? null})
            AND (${filter.from ?? null}::timestamptz IS NULL OR created_at >= ${filter.from ?? null})
            AND (${filter.to ?? null}::timestamptz IS NULL OR created_at <= ${filter.to ?? null})
          ORDER BY created_at DESC
          LIMIT ${limit}
        `),
    );
    return rows.map(mapFoodSearchEvent);
  }

  async getTelemetryOverview(input: {
    from: string;
    to: string;
  }): Promise<TelemetryOverview> {
    const overviewRows = await withSpan(
      "PostgresRepository.getTelemetryOverview",
      { from: input.from, to: input.to },
      () =>
        this.execute(dbSql`
          WITH events_in_range AS (
            SELECT * FROM telemetry_events
            WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz
          ),
          llm_in_range AS (
            SELECT * FROM llm_runs
            WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz
          ),
          food_in_range AS (
            SELECT * FROM food_search_events
            WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz
          ),
          conversations_in_range AS (
            SELECT * FROM agent_conversations
            WHERE updated_at >= ${input.from}::timestamptz AND updated_at <= ${input.to}::timestamptz
          ),
          turns_in_range AS (
            SELECT * FROM agent_turn_telemetry
            WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz
          ),
          provider_calls_in_range AS (
            SELECT * FROM llm_provider_calls
            WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz
          ),
          transcriptions_in_range AS (
            SELECT * FROM transcription_records
            WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz
          ),
          trace_ids_in_range AS (
            SELECT trace_id FROM events_in_range
            UNION
            SELECT trace_id FROM llm_in_range
            UNION
            SELECT trace_id FROM food_in_range
            UNION
            SELECT trace_id FROM turns_in_range
            UNION
            SELECT trace_id FROM provider_calls_in_range
            UNION
            SELECT trace_id FROM transcriptions_in_range
          )
          SELECT
            (SELECT COUNT(*)::int FROM events_in_range) AS total_events,
            (SELECT COUNT(*)::int FROM llm_in_range) AS total_llm_runs,
            (SELECT COUNT(*)::int FROM food_in_range) AS total_food_search_events,
            (SELECT COUNT(*)::int FROM conversations_in_range) AS total_conversations,
            (SELECT COUNT(*)::int FROM turns_in_range) AS total_agent_turns,
            (SELECT COUNT(*)::int FROM provider_calls_in_range) AS total_provider_calls,
            (SELECT COUNT(*)::int FROM transcriptions_in_range) AS total_transcriptions,
            (SELECT COALESCE(SUM(provider_cost_amount), 0)::numeric FROM provider_calls_in_range) AS provider_cost_amount,
            (SELECT COALESCE(SUM(estimated_cost_amount), 0)::numeric FROM provider_calls_in_range) AS estimated_cost_amount,
            (SELECT COUNT(*)::int FROM provider_calls_in_range WHERE cost_source = 'unknown') AS unknown_cost_count,
            (SELECT COUNT(*)::int FROM trace_ids_in_range) AS unique_traces,
            (SELECT COALESCE(SUM(CASE WHEN zero_results THEN 1 ELSE 0 END), 0)::int FROM food_in_range) AS zero_results_count,
            (SELECT COALESCE(SUM(CASE WHEN low_confidence THEN 1 ELSE 0 END), 0)::int FROM food_in_range) AS low_confidence_count,
            (SELECT COALESCE(SUM(CASE WHEN provider_error THEN 1 ELSE 0 END), 0)::int FROM llm_in_range) AS provider_error_count
        `),
    );
    const overview = overviewRows[0] ?? {};
    const totalEvents = Number(overview.total_events ?? 0);
    const totalLlmRuns = Number(overview.total_llm_runs ?? 0);
    const totalFoodSearchEvents = Number(
      overview.total_food_search_events ?? 0,
    );
    const totalConversations = Number(overview.total_conversations ?? 0);
    const totalAgentTurns = Number(overview.total_agent_turns ?? 0);
    const totalProviderCalls = Number(overview.total_provider_calls ?? 0);
    const totalTranscriptions = Number(overview.total_transcriptions ?? 0);
    const providerCostAmount = Number(overview.provider_cost_amount ?? 0);
    const estimatedCostAmount = Number(overview.estimated_cost_amount ?? 0);
    const unknownCostCount = Number(overview.unknown_cost_count ?? 0);
    const zeroResultsCount = Number(overview.zero_results_count ?? 0);
    const lowConfidenceCount = Number(overview.low_confidence_count ?? 0);
    const providerErrorCount = Number(overview.provider_error_count ?? 0);
    const userIdRows = await this.execute(
      dbSql`
        SELECT user_id FROM telemetry_events
        WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz AND user_id IS NOT NULL
        UNION
        SELECT user_id FROM llm_runs
        WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz AND user_id IS NOT NULL
        UNION
        SELECT user_id FROM food_search_events
        WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz AND user_id IS NOT NULL
        UNION
        SELECT user_id FROM agent_turn_telemetry
        WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz AND user_id IS NOT NULL
        UNION
        SELECT user_id FROM llm_provider_calls
        WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz AND user_id IS NOT NULL
        UNION
        SELECT user_id FROM transcription_records
        WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz AND user_id IS NOT NULL
      `,
    );
    const uniqueUsers = new Set(userIdRows.map((row) => row.user_id)).size;
    const severityRows = await this.execute(
      dbSql`SELECT severity, COUNT(*)::int AS count FROM telemetry_events WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz GROUP BY severity`,
    );
    const eventsBySeverity: Record<string, number> = {};
    for (const row of severityRows) {
      eventsBySeverity[row.severity as string] = Number(row.count);
    }
    const surfaceRows = await this.execute(
      dbSql`SELECT surface, COUNT(*)::int AS count FROM telemetry_events WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz GROUP BY surface`,
    );
    const eventsBySurface: Record<string, number> = {};
    for (const row of surfaceRows) {
      eventsBySurface[row.surface as string] = Number(row.count);
    }
    const resultKindRows = await this.execute(
      dbSql`SELECT result_kind, COUNT(*)::int AS count FROM llm_runs WHERE created_at >= ${input.from}::timestamptz AND created_at <= ${input.to}::timestamptz AND result_kind IS NOT NULL GROUP BY result_kind`,
    );
    const recentResultKinds: Record<string, number> = {};
    for (const row of resultKindRows) {
      recentResultKinds[row.result_kind as string] = Number(row.count);
    }
    return {
      from: input.from,
      to: input.to,
      totalEvents,
      totalLlmRuns,
      totalFoodSearchEvents,
      totalConversations,
      totalAgentTurns,
      totalProviderCalls,
      totalTranscriptions,
      providerCostAmount,
      estimatedCostAmount,
      unknownCostCount,
      uniqueUsers,
      uniqueTraces: Number(overview.unique_traces ?? 0),
      eventsBySeverity,
      eventsBySurface,
      recentResultKinds,
      zeroResultRate:
        totalFoodSearchEvents === 0
          ? 0
          : zeroResultsCount / totalFoodSearchEvents,
      lowConfidenceRate:
        totalFoodSearchEvents === 0
          ? 0
          : lowConfidenceCount / totalFoodSearchEvents,
      providerErrorRate:
        totalLlmRuns === 0 ? 0 : providerErrorCount / totalLlmRuns,
    };
  }

  private async mapMeals(
    rows: Record<string, unknown>[],
    dbClient: DbExecutor = this.db,
  ): Promise<Meal[]> {
    if (rows.length === 0) return [];
    const items = await executeRows(
      dbClient,
      dbSql`
      SELECT *
      FROM meal_items
      WHERE meal_id IN ${sqlList(rows.map((row) => row.id as string))}
      ORDER BY meal_id, id
    `,
    );
    const itemsByMealId = groupRowsByString(items, "meal_id");
    return rows.map((row) =>
      this.mapMealRow(row, itemsByMealId.get(row.id as string) ?? []),
    );
  }

  private async mapMeal(
    row: Record<string, unknown>,
    dbClient: DbExecutor = this.db,
  ): Promise<Meal> {
    const [meal] = await this.mapMeals([row], dbClient);
    return meal;
  }

  private mapMealRow(
    row: Record<string, unknown>,
    items: Record<string, unknown>[],
  ): Meal {
    return {
      id: row.id as string,
      title: row.title as string,
      occurredAt: toIso(row.occurred_at),
      mealLabel: mapMealLabel(row),
      nutrition: mapNutrition(row),
      items: items.map(mapItem),
      createdAt: toIso(row.created_at),
      deletedAt: row.deleted_at ? toIso(row.deleted_at) : undefined,
    };
  }

  private async mapProposal(
    row: Record<string, unknown>,
    fallbackTitle = "Meal",
    dbClient: DbExecutor = this.db,
  ): Promise<MealProposal> {
    const items = await executeRows(
      dbClient,
      dbSql`SELECT * FROM meal_proposal_items WHERE proposal_id = ${row.id as string}`,
    );
    return {
      id: row.id as string,
      phrase: row.phrase as string,
      title: (row.title as string) || fallbackTitle,
      status: row.status as MealProposal["status"],
      confidence: Number(row.confidence),
      requiresConfirmation: Boolean(row.requires_confirmation),
      trustedAutoCommitEligible: Boolean(row.trusted_auto_commit_eligible),
      source: row.source as string,
      nutrition: mapNutrition(row),
      items: items.map(mapItem),
      createdAt: toIso(row.created_at),
    };
  }

  private async mapTemplates(
    rows: Record<string, unknown>[],
    dbClient: DbExecutor = this.db,
  ): Promise<MealTemplate[]> {
    if (rows.length === 0) return [];
    const templateIds = rows.map((row) => row.id as string);
    const items = await executeRows(
      dbClient,
      dbSql`
      SELECT *
      FROM meal_template_items
      WHERE template_id IN ${sqlList(templateIds)}
      ORDER BY template_id, id
    `,
    );
    const aliases = await executeRows(
      dbClient,
      dbSql`
      SELECT meal_template_id, label
      FROM food_memories
      WHERE meal_template_id IN ${sqlList(templateIds)}
      ORDER BY meal_template_id, label
    `,
    );
    const itemsByTemplateId = groupRowsByString(items, "template_id");
    const aliasesByTemplateId = groupRowsByString(aliases, "meal_template_id");
    return rows.map((row) =>
      this.mapTemplateRow(
        row,
        itemsByTemplateId.get(row.id as string) ?? [],
        aliasesByTemplateId.get(row.id as string) ?? [],
      ),
    );
  }

  private async mapTemplate(
    row: Record<string, unknown>,
    dbClient: DbExecutor = this.db,
  ): Promise<MealTemplate> {
    const [template] = await this.mapTemplates([row], dbClient);
    return template;
  }

  private mapTemplateRow(
    row: Record<string, unknown>,
    items: Record<string, unknown>[],
    aliases: Record<string, unknown>[],
  ): MealTemplate {
    return {
      id: row.id as string,
      title: row.title as string,
      trustedAutoCommitEnabled: Boolean(row.trusted_auto_commit_enabled),
      nutrition: mapNutrition(row),
      items: items.map(mapItem),
      aliases: aliases.map((alias) => alias.label as string),
    };
  }

  private async getTemplateById(
    userId: string,
    templateId: string,
  ): Promise<MealTemplate | null> {
    const [row] = await this.execute(
      dbSql`SELECT * FROM meal_templates WHERE id = ${templateId} AND user_id = ${userId} AND deleted_at IS NULL`,
    );
    return row ? this.mapTemplate(row) : null;
  }

  private async getCurrentGoals(
    userId: string,
    dbClient: DbExecutor = this.db,
  ): Promise<
    Omit<DailyGoals, "date"> & { calorieTargetConfiguredAt?: string }
  > {
    const [row] = await executeRows(
      dbClient,
      dbSql`SELECT * FROM nutrition_targets WHERE user_id = ${userId}`,
    );
    if (!row) {
      return {
        target: { calories: 2200, proteinGrams: 0, carbsGrams: 0, fatGrams: 0 },
        hydrationGoalLiters: 0,
        calorieTargetConfigured: false,
        calorieTargetSource: "default",
        calorieTargetConfiguredAt: undefined,
      };
    }
    return {
      target: mapNutrition(row),
      hydrationGoalLiters: Number(row.hydration_goal_liters ?? 0),
      calorieTargetConfigured: Boolean(row.calorie_target_configured),
      calorieTargetSource: parseCalorieTargetSource(row.calorie_target_source),
      calorieTargetConfiguredAt: row.calorie_target_configured_at
        ? toIso(row.calorie_target_configured_at)
        : undefined,
      ...mapMacroMetadata(row),
    };
  }

  private async mapFoodsWithPortions(
    rows: Record<string, unknown>[],
  ): Promise<FoodItemRecord[]> {
    if (rows.length === 0) return [];
    const foods = rows.map(mapFood);
    const portions = await this.execute(dbSql`
      SELECT *
      FROM food_portions
      WHERE food_item_id IN ${sqlList(foods.map((food) => food.id))}
      ORDER BY food_item_id, gram_weight, source_description
    `);
    const byFoodId = new Map<string, FoodPortionRecord[]>();
    for (const row of portions) {
      const portion = mapFoodPortion(row);
      const list = byFoodId.get(portion.foodItemId) ?? [];
      list.push(portion);
      byFoodId.set(portion.foodItemId, list);
    }
    return foods.map((food) => ({
      ...food,
      portions: byFoodId.get(food.id) ?? [],
    }));
  }

  private async getPreferenceScoreMap(
    userId: string,
    foodIds: string[],
  ): Promise<Map<string, number>> {
    if (foodIds.length === 0) return new Map();
    const rows = await this.execute(dbSql`
      SELECT food_item_id, affinity_score
      FROM user_food_preferences
      WHERE user_id = ${userId}
        AND food_item_id IN ${sqlList(foodIds)}
    `);
    return new Map(
      rows.map((row) => [
        row.food_item_id as string,
        Number(row.affinity_score),
      ]),
    );
  }

  private mapUser(
    row: Record<string, unknown>,
    passwordHash: string | undefined,
    scopes: PermissionScope[],
  ): StoredUser {
    return {
      id: row.id as string,
      email: row.email as string,
      displayName: row.display_name as string,
      trustedModeEnabled: Boolean(row.trusted_mode_enabled),
      emailVerifiedAt: row.email_verified_at
        ? toIso(row.email_verified_at)
        : undefined,
      createdAt: toIso(row.created_at),
      ...(passwordHash ? { passwordHash } : {}),
      scopes,
    };
  }
}

function mapPendingRegistration(
  row: Record<string, unknown>,
): PendingRegistrationRecord {
  return {
    id: row.id as string,
    email: row.email as string,
    displayName: row.display_name as string,
    passwordHash: row.password_hash as string,
    tokenHash: row.token_hash as string,
    expiresAt: toIso(row.expires_at),
    ...(row.consumed_at ? { consumedAt: toIso(row.consumed_at) } : {}),
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

function mapPrivacyDeletionRequest(
  row: Record<string, unknown>,
): PrivacyDeletionRequest {
  return {
    id: row.id as string,
    subjectUserId: row.subject_user_id as string,
    conversationId: row.conversation_id as string,
    requestedAt: toIso(row.requested_at),
    purgeDueAt: toIso(row.purge_due_at),
    status: row.status as PrivacyDeletionRequest["status"],
    ...(row.purged_at ? { purgedAt: toIso(row.purged_at) } : {}),
    ...(row.last_attempt_at
      ? { lastAttemptAt: toIso(row.last_attempt_at) }
      : {}),
    attemptCount: Number(row.attempt_count ?? 0),
    ...(row.result_code ? { resultCode: row.result_code as string } : {}),
  };
}

async function purgeConversationContent(
  dbClient: DbExecutor,
  conversationId: string,
): Promise<void> {
  // Capture correlation keys before deleting messages. These keys propagate
  // deletion to telemetry and derived operational rows without retaining text.
  const traceRows = await executeRows(
    dbClient,
    dbSql`
    SELECT DISTINCT trace_id FROM (
      SELECT trace_id FROM agent_messages WHERE conversation_id = ${conversationId}
      UNION ALL SELECT trace_id FROM agent_turn_telemetry WHERE conversation_id = ${conversationId}
      UNION ALL SELECT trace_id FROM agent_tool_call_telemetry WHERE conversation_id = ${conversationId}
      UNION ALL SELECT trace_id FROM llm_provider_calls WHERE conversation_id = ${conversationId}
      UNION ALL SELECT trace_id FROM transcription_records WHERE conversation_id = ${conversationId}
      UNION ALL SELECT trace_id FROM llm_runs WHERE conversation_id = ${conversationId}
    ) correlated WHERE trace_id IS NOT NULL
  `,
  );
  const turnRows = await executeRows(
    dbClient,
    dbSql`
    SELECT DISTINCT turn_id FROM (
      SELECT turn_id FROM agent_messages WHERE conversation_id = ${conversationId}
      UNION ALL SELECT turn_id FROM agent_turn_telemetry WHERE conversation_id = ${conversationId}
      UNION ALL SELECT turn_id FROM agent_tool_call_telemetry WHERE conversation_id = ${conversationId}
      UNION ALL SELECT turn_id FROM llm_provider_calls WHERE conversation_id = ${conversationId}
      UNION ALL SELECT turn_id FROM transcription_records WHERE conversation_id = ${conversationId}
      UNION ALL SELECT turn_id FROM llm_runs WHERE conversation_id = ${conversationId}
    ) correlated WHERE turn_id IS NOT NULL
  `,
  );
  const traceIds = traceRows.map((row) => row.trace_id as string);
  const turnIds = turnRows.map((row) => row.turn_id as string);

  if (traceIds.length > 0) {
    await executeRows(
      dbClient,
      dbSql`DELETE FROM action_calls WHERE trace_id IN ${sqlList(traceIds)}`,
    );
    await executeRows(
      dbClient,
      dbSql`DELETE FROM telemetry_events WHERE trace_id IN ${sqlList(traceIds)}`,
    );
    await executeRows(
      dbClient,
      dbSql`DELETE FROM food_search_events WHERE trace_id IN ${sqlList(traceIds)}`,
    );
  }
  await executeRows(
    dbClient,
    dbSql`
    DELETE FROM transcription_records
    WHERE conversation_id = ${conversationId}
      OR (${traceIds.length > 0}::boolean AND trace_id IN ${sqlList(traceIds.length > 0 ? traceIds : ["00000000-privacy-empty"])})
  `,
  );
  await executeRows(
    dbClient,
    dbSql`
    DELETE FROM agent_tool_call_telemetry
    WHERE conversation_id = ${conversationId}
      OR (${traceIds.length > 0}::boolean AND trace_id IN ${sqlList(traceIds.length > 0 ? traceIds : ["00000000-privacy-empty"])})
      OR (${turnIds.length > 0}::boolean AND turn_id IN ${sqlList(turnIds.length > 0 ? turnIds : ["00000000-0000-0000-0000-000000000000"])})
  `,
  );
  await executeRows(
    dbClient,
    dbSql`
    DELETE FROM llm_provider_calls
    WHERE conversation_id = ${conversationId}
      OR (${traceIds.length > 0}::boolean AND trace_id IN ${sqlList(traceIds.length > 0 ? traceIds : ["00000000-privacy-empty"])})
      OR (${turnIds.length > 0}::boolean AND turn_id IN ${sqlList(turnIds.length > 0 ? turnIds : ["00000000-0000-0000-0000-000000000000"])})
  `,
  );
  await executeRows(
    dbClient,
    dbSql`
    DELETE FROM agent_turn_telemetry
    WHERE conversation_id = ${conversationId}
      OR (${traceIds.length > 0}::boolean AND trace_id IN ${sqlList(traceIds.length > 0 ? traceIds : ["00000000-privacy-empty"])})
      OR (${turnIds.length > 0}::boolean AND turn_id IN ${sqlList(turnIds.length > 0 ? turnIds : ["00000000-0000-0000-0000-000000000000"])})
  `,
  );
  await executeRows(
    dbClient,
    dbSql`
    DELETE FROM llm_runs
    WHERE conversation_id = ${conversationId}
      OR (${traceIds.length > 0}::boolean AND trace_id IN ${sqlList(traceIds.length > 0 ? traceIds : ["00000000-privacy-empty"])})
      OR (${turnIds.length > 0}::boolean AND turn_id IN ${sqlList(turnIds.length > 0 ? turnIds : ["00000000-0000-0000-0000-000000000000"])})
  `,
  );
  await executeRows(
    dbClient,
    dbSql`DELETE FROM agent_candidate_registries WHERE conversation_id = ${conversationId}`,
  );
  await executeRows(
    dbClient,
    dbSql`DELETE FROM agent_messages WHERE conversation_id = ${conversationId}`,
  );
  await executeRows(
    dbClient,
    dbSql`DELETE FROM agent_conversations WHERE id = ${conversationId}`,
  );
}

function mapAuthIdentity(row: Record<string, unknown>): AuthIdentityRecord {
  return {
    id: row.id as string,
    userId: row.user_id as string,
    provider: row.provider as AuthIdentityProvider,
    providerUserId: row.provider_user_id as string,
    email: row.email as string,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

async function insertProposalItem(
  dbClient: DbExecutor,
  proposalId: string,
  item: MealItem,
) {
  await executeRows(
    dbClient,
    dbSql`
    INSERT INTO meal_proposal_items (
      proposal_id, name, quantity, unit, calories, protein_grams, carbs_grams, fat_grams,
      source, original_text, canonical_name, language, external_source, external_id, source_url, license, confidence, needs_review
    )
    VALUES (
      ${proposalId}, ${item.name}, ${item.quantity}, ${item.unit}, ${item.calories}, ${item.proteinGrams}, ${item.carbsGrams}, ${item.fatGrams},
      ${item.source}, ${item.originalText ?? null}, ${item.canonicalName ?? null}, ${item.language ?? null}, ${item.externalSource ?? null}, ${item.externalId ?? null},
      ${item.sourceUrl ?? null}, ${item.license ?? null}, ${item.confidence ?? null}, ${item.needsReview ?? false}
    )
  `,
  );
}

async function insertMealItem(
  dbClient: DbExecutor,
  mealId: string,
  item: MealItem,
) {
  await executeRows(
    dbClient,
    dbSql`
    INSERT INTO meal_items (
      meal_id, name, quantity, unit, calories, protein_grams, carbs_grams, fat_grams,
      source, original_text, canonical_name, language, external_source, external_id, source_url, license, confidence, needs_review
    )
    VALUES (
      ${mealId}, ${item.name}, ${item.quantity}, ${item.unit}, ${item.calories}, ${item.proteinGrams}, ${item.carbsGrams}, ${item.fatGrams},
      ${item.source}, ${item.originalText ?? null}, ${item.canonicalName ?? null}, ${item.language ?? null}, ${item.externalSource ?? null}, ${item.externalId ?? null},
      ${item.sourceUrl ?? null}, ${item.license ?? null}, ${item.confidence ?? null}, ${item.needsReview ?? false}
    )
  `,
  );
}

async function insertTemplateItem(
  dbClient: DbExecutor,
  templateId: string,
  item: MealItem,
) {
  await executeRows(
    dbClient,
    dbSql`
    INSERT INTO meal_template_items (
      template_id, name, quantity, unit, calories, protein_grams, carbs_grams, fat_grams,
      source, original_text, canonical_name, language, external_source, external_id, source_url, license, confidence, needs_review
    )
    VALUES (
      ${templateId}, ${item.name}, ${item.quantity}, ${item.unit}, ${item.calories}, ${item.proteinGrams}, ${item.carbsGrams}, ${item.fatGrams},
      ${item.source}, ${item.originalText ?? null}, ${item.canonicalName ?? null}, ${item.language ?? null}, ${item.externalSource ?? null}, ${item.externalId ?? null},
      ${item.sourceUrl ?? null}, ${item.license ?? null}, ${item.confidence ?? null}, ${item.needsReview ?? false}
    )
  `,
  );
}

function mapFood(row: Record<string, unknown>): FoodItemRecord {
  const normalizedDisplayName = optionalString(
    row.search_normalized_display_name,
  );
  const normalizedBaseName = optionalString(row.search_normalized_base_name);
  const normalizedVariantName = optionalString(
    row.search_normalized_variant_name,
  );
  const normalizedResultType = optionalString(
    row.search_normalized_result_type,
  );
  const normalizedBrandDisplay = optionalString(
    row.search_normalized_brand_display,
  );
  const primaryEntityName = optionalString(row.search_primary_entity_name);
  const primaryEntityAliases = arrayOfStrings(
    row.search_primary_entity_aliases,
  );
  const secondaryEntityAliases = arrayOfStrings(
    row.search_secondary_entity_aliases,
  );
  const primaryEntityCategory = optionalString(
    row.search_primary_entity_category,
  );
  const primaryEntityCategoryCoherence =
    row.search_primary_entity_category_coherence == null
      ? undefined
      : Number(row.search_primary_entity_category_coherence);
  const primaryEntityRepresentativeness =
    row.search_primary_entity_representativeness == null
      ? undefined
      : Number(row.search_primary_entity_representativeness);
  const displayDetails = normalizedFoodDisplayDetails(row);
  return {
    id: row.id as string,
    userId: optionalString(row.user_id),
    name: optionalString(row.search_display_name) ?? (row.name as string),
    normalizedName: row.normalized_name as string,
    canonicalName: optionalString(row.canonical_name),
    brand: optionalString(row.brand),
    barcode: optionalString(row.barcode),
    source: row.source as string,
    externalSource: optionalString(row.external_source),
    externalId: optionalString(row.external_id),
    sourceUrl: optionalString(row.source_url),
    license: optionalString(row.license),
    fetchedAt: row.fetched_at ? toIso(row.fetched_at) : undefined,
    dataType: optionalString(row.data_type),
    foodCategory: optionalString(row.food_category),
    publicationDate: row.publication_date
      ? toDateOnly(row.publication_date)
      : undefined,
    ndbNumber: optionalString(row.ndb_number),
    foodKey: optionalString(row.food_key),
    ingredients: optionalString(row.ingredients),
    marketCountry: optionalString(row.market_country),
    normalizedDisplayName,
    normalizedBaseName,
    normalizedVariantName,
    normalizedResultType,
    normalizedBrandDisplay,
    primaryEntityName,
    primaryEntityAliases,
    secondaryEntityAliases,
    primaryEntityCategory,
    primaryEntityCategoryCoherence,
    primaryEntityRepresentativeness,
    displayDetails,
    householdServingFulltext: optionalString(row.household_serving_fulltext),
    nutrients: isRecord(row.nutrients_json) ? row.nutrients_json : undefined,
    portions: [],
    servingGrams: Number(row.serving_grams),
    calories: Number(row.calories),
    proteinGrams: Number(row.protein_grams),
    carbsGrams: Number(row.carbs_grams),
    fatGrams: Number(row.fat_grams),
    createdAt: row.created_at ? toIso(row.created_at) : undefined,
    updatedAt: row.updated_at ? toIso(row.updated_at) : undefined,
    deletedAt: row.deleted_at ? toIso(row.deleted_at) : undefined,
  };
}

function normalizedFoodDisplayDetails(
  row: Record<string, unknown>,
): string[] | undefined {
  const metadata = isRecord(row.search_normalized_metadata)
    ? row.search_normalized_metadata
    : undefined;
  const displayText = normalizeText(
    [row.search_normalized_display_name, row.search_normalized_base_name]
      .filter((value): value is string => typeof value === "string")
      .join(" "),
  );
  const values = [
    ...arrayOfStrings(metadata?.retainedDescriptors),
    ...arrayOfStrings(metadata?.hiddenDescriptors),
    optionalString(row.search_normalized_variant_name),
  ];
  const seen = new Set<string>();
  const details: string[] = [];
  for (const value of values) {
    const trimmed = value?.trim();
    if (!trimmed) continue;
    const key = normalizeText(trimmed);
    if (!key || seen.has(key) || tokenPhraseContained(displayText, key))
      continue;
    seen.add(key);
    details.push(titleCaseDisplay(trimmed));
  }
  return details.length > 0 ? details : undefined;
}

function mapFoodPortion(row: Record<string, unknown>): FoodPortionRecord {
  return {
    id: row.id as string,
    foodItemId: row.food_item_id as string,
    usdaPortionId: optionalString(row.usda_portion_id),
    amount: row.amount == null ? undefined : Number(row.amount),
    unit: optionalString(row.unit),
    modifier: optionalString(row.modifier),
    description: optionalString(row.description),
    gramWeight: Number(row.gram_weight),
    normalizedAliases: Array.isArray(row.normalized_aliases)
      ? row.normalized_aliases.map(String)
      : [],
    kind: (row.kind as string | undefined) ?? "serving",
    sourceDescription: row.source_description as string,
  };
}

function mapFoodItemEmbedding(
  row: Record<string, unknown>,
): FoodItemEmbeddingRecord {
  return {
    id: row.id as string,
    foodItemId: row.food_item_id as string,
    embeddedText: row.embedded_text as string,
    embeddedTextHash: row.embedded_text_hash as string,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

function mapUserFoodPreference(
  row: Record<string, unknown>,
): UserFoodPreference {
  return {
    userId: row.user_id as string,
    foodItemId: row.food_item_id as string,
    affinityScore: Number(row.affinity_score),
    positiveFeedbackCount: Number(row.positive_feedback_count),
    negativeFeedbackCount: Number(row.negative_feedback_count),
    lastFeedbackAt: toIso(row.last_feedback_at),
    updatedAt: toIso(row.updated_at),
  };
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

function mapNutrition(row: Record<string, unknown>): NutritionSnapshot {
  return {
    calories: Number(row.calories),
    proteinGrams: Number(row.protein_grams),
    carbsGrams: Number(row.carbs_grams),
    fatGrams: Number(row.fat_grams),
  };
}

function mapDailyGoals(row: Record<string, unknown>): DailyGoals {
  return {
    date: toDateOnly(row.target_date),
    target: mapNutrition(row),
    hydrationGoalLiters: Number(row.hydration_goal_liters ?? 0),
    calorieTargetConfigured: Boolean(row.calorie_target_configured),
    calorieTargetSource: parseCalorieTargetSource(row.calorie_target_source),
    ...mapMacroMetadata(row),
  };
}

function parseCalorieTargetSource(value: unknown): CalorieTargetSource {
  return value === "manual" || value === "calculator" || value === "default"
    ? value
    : "default";
}

function mapMacroMetadata(row: Record<string, unknown>): MacroGoalMetadata {
  return {
    macroMode: parseMacroMode(row.macro_mode),
    macroSource: parseMacroSource(row.macro_source),
    macroPreset: parseMacroPreset(row.macro_preset),
    proteinPct: optionalNumber(row.protein_pct),
    carbsPct: optionalNumber(row.carbs_pct),
    fatPct: optionalNumber(row.fat_pct),
    macroCalories: optionalNumber(row.macro_calories),
    calorieDeltaKcal: optionalNumber(row.calorie_delta_kcal),
  };
}

function parseMacroMode(value: unknown): MacroGoalMetadata["macroMode"] {
  return value === "percentage" || value === "grams" ? value : undefined;
}

function parseMacroSource(value: unknown): MacroGoalMetadata["macroSource"] {
  return value === "preset" || value === "custom" ? value : undefined;
}

function parseMacroPreset(value: unknown): MacroGoalMetadata["macroPreset"] {
  return value === "balanced" ||
    value === "high_protein" ||
    value === "lower_carb"
    ? value
    : undefined;
}

function mapMealLabel(row: Record<string, unknown>): MealLabel | null {
  const type = row.meal_type as MealLabel["type"] | null | undefined;
  const label = row.meal_type_label as string | null | undefined;
  return type && label ? { type, label } : null;
}

function mapItem(row: Record<string, unknown>): MealItem {
  return {
    name: row.name as string,
    quantity: Number(row.quantity),
    unit: row.unit as string,
    calories: Number(row.calories),
    proteinGrams: Number(row.protein_grams),
    carbsGrams: Number(row.carbs_grams),
    fatGrams: Number(row.fat_grams),
    source: (row.source as string | undefined) ?? "snapshot",
    originalText: row.original_text as string | undefined,
    canonicalName: row.canonical_name as string | undefined,
    language: row.language as string | undefined,
    externalSource: row.external_source as string | undefined,
    externalId: row.external_id as string | undefined,
    sourceUrl: row.source_url as string | undefined,
    license: row.license as string | undefined,
    confidence: row.confidence == null ? undefined : Number(row.confidence),
    needsReview:
      row.needs_review == null ? undefined : Boolean(row.needs_review),
  };
}

function mapSession(row: Record<string, unknown>): StoredSession {
  return {
    id: row.id as string,
    userId: row.user_id as string,
    refreshTokenHash: row.refresh_token_hash as string,
    expiresAt: toIso(row.expires_at),
    revokedAt: row.revoked_at ? toIso(row.revoked_at) : undefined,
    createdAt: toIso(row.created_at),
    rotatedAt: row.rotated_at ? toIso(row.rotated_at) : undefined,
  };
}

function mapAgentConversation(
  row: Record<string, unknown>,
): AgentConversationRecord {
  return {
    id: row.id as string,
    userId: row.user_id as string,
    title: row.title as string,
    hiddenFromUserAt: row.hidden_from_user_at
      ? toIso(row.hidden_from_user_at)
      : undefined,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

function mapAgentConversationMessage(
  row: Record<string, unknown>,
): AgentConversationMessageRecord {
  return {
    id: row.id as string,
    conversationId: row.conversation_id as string,
    userId: row.user_id as string,
    role: row.role as AgentConversationMessageRecord["role"],
    content: row.content as string,
    toolCalls: row.tool_calls_json ?? undefined,
    toolCallId: optionalString(row.tool_call_id),
    traceId: optionalString(row.trace_id),
    turnId: optionalString(row.turn_id),
    inputMode: optionalString(row.input_mode),
    source: optionalString(row.source),
    activeProposalId: optionalString(row.active_proposal_id),
    metadata: row.metadata_json ?? undefined,
    createdAt: toIso(row.created_at),
  };
}

function agentResultFromConversationMessage(
  message: AgentConversationMessageRecord,
): unknown {
  const metadata =
    message.metadata && typeof message.metadata === "object"
      ? (message.metadata as Record<string, unknown>)
      : undefined;
  if (metadata?.uiResult !== undefined) return metadata.uiResult;
  try {
    const content = JSON.parse(message.content) as { result?: unknown };
    return content.result;
  } catch {
    return undefined;
  }
}

function mapAgentToolExecution(
  row: Record<string, unknown>,
): AgentToolExecutionRecord {
  return {
    id: row.id as string,
    userId: row.user_id as string,
    conversationId: row.conversation_id as string,
    assistantMessageId: row.assistant_message_id as string,
    turnId: row.turn_id as string,
    toolCallId: row.tool_call_id as string,
    actionId: row.action_id as string,
    iteration: Number(row.iteration),
    toolCallIndex: Number(row.tool_call_index),
    status: row.status as AgentToolExecutionRecord["status"],
    snapshot: row.snapshot_json as AgentToolExecutionRecord["snapshot"],
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at),
  };
}

function mapAgentCandidateRegistry(
  row: Record<string, unknown>,
): AgentCandidateRegistryRecord {
  return {
    id: row.id as string,
    userId: row.user_id as string,
    conversationId: row.conversation_id as string,
    messageId: optionalString(row.message_id),
    traceId: optionalString(row.trace_id),
    turnId: optionalString(row.turn_id),
    actionCallId: optionalString(row.action_call_id),
    searchRef: row.search_ref as string,
    actionId: row.action_id as string,
    candidateCount: Number(row.candidate_count),
    groupCount: Number(row.group_count),
    threshold: optionalNumber(row.threshold),
    registry: row.registry_json,
    createdAt: toIso(row.created_at),
  };
}

function mapActionCall(row: Record<string, unknown>): ActionCallRecord {
  return {
    id: row.id as string,
    userId: row.user_id as string,
    actionId: row.action_id as string,
    source: row.source as string,
    input: row.input_json,
    output: row.output_json,
    error: row.error_json,
    confirmationStatus: row.confirmation_status as string,
    traceId: row.trace_id as string,
    latencyMs: Number(row.latency_ms),
    createdAt: toIso(row.created_at),
  };
}

function mapAuditEvent(row: Record<string, unknown>): AuditEventRecord {
  return {
    id: row.id as string,
    userId: row.user_id as string | undefined,
    eventType: row.event_type as string,
    metadata: row.metadata_json,
    traceId: row.trace_id as string,
    createdAt: toIso(row.created_at),
  };
}

function mapTelemetryEvent(row: Record<string, unknown>): TelemetryEventRecord {
  return {
    id: row.id as string,
    traceId: row.trace_id as string,
    userId: row.user_id as string | undefined,
    sessionId: row.session_id as string | undefined,
    eventType: row.event_type as string,
    flow: row.flow as string | undefined,
    surface: row.surface as string,
    severity: row.severity as string,
    status: row.status as string | undefined,
    route: row.route as string | undefined,
    method: row.method as string | undefined,
    actionId: row.action_id as string | undefined,
    durationMs: optionalNumber(row.duration_ms),
    errorCode: row.error_code as string | undefined,
    errorMessage: row.error_message as string | undefined,
    appVersion: row.app_version as string | undefined,
    appBuild: row.app_build as string | undefined,
    platform: row.platform as string | undefined,
    locale: row.locale as string | undefined,
    metadata: isRecord(row.metadata_json) ? row.metadata_json : {},
    createdAt: toIso(row.created_at),
  };
}

function mapLlmRun(row: Record<string, unknown>): LlmRunRecord {
  return {
    id: row.id as string,
    traceId: row.trace_id as string,
    userId: row.user_id as string | undefined,
    source: row.source as string | undefined,
    locale: row.locale as string | undefined,
    timezone: row.timezone as string | undefined,
    conversationId: row.conversation_id as string | undefined,
    turnId: row.turn_id as string | undefined,
    provider: row.provider as string | undefined,
    providerRequestId: row.provider_request_id as string | undefined,
    providerGenerationId: row.provider_generation_id as string | undefined,
    model: row.model as string,
    inputMode: row.input_mode as string | undefined,
    activeProposalId: row.active_proposal_id as string | undefined,
    decisionSource: row.decision_source as string | undefined,
    selectedTool: row.selected_tool as string | undefined,
    executedTool: row.executed_tool as string | undefined,
    resultKind: row.result_kind as string | undefined,
    actionCallId: row.action_call_id as string | undefined,
    promptChars: optionalNumber(row.prompt_chars),
    toolsJsonChars: optionalNumber(row.tools_json_chars),
    messagesJsonChars: optionalNumber(row.messages_json_chars),
    requestPayloadChars: optionalNumber(row.request_payload_chars),
    promptTokens: optionalNumber(row.prompt_tokens),
    completionTokens: optionalNumber(row.completion_tokens),
    totalTokens: optionalNumber(row.total_tokens),
    reasoningTokens: optionalNumber(row.reasoning_tokens),
    firstByteMs: optionalNumber(row.first_byte_ms),
    firstToolCallMs: optionalNumber(row.first_tool_call_ms),
    largestStreamGapMs: optionalNumber(row.largest_stream_gap_ms),
    llmMs: optionalNumber(row.llm_ms),
    actionMs: optionalNumber(row.action_ms),
    totalMs: optionalNumber(row.total_ms),
    emptyToolCall: Boolean(row.empty_tool_call),
    invalidToolArguments: Boolean(row.invalid_tool_arguments),
    providerError: Boolean(row.provider_error),
    providerCostAmount: optionalNumber(row.provider_cost_amount),
    estimatedCostAmount: optionalNumber(row.estimated_cost_amount),
    costCurrency: row.cost_currency as string | undefined,
    costSource: row.cost_source as string | undefined,
    pricingSnapshot: isRecord(row.pricing_snapshot_json)
      ? row.pricing_snapshot_json
      : {},
    metadata: isRecord(row.metadata_json) ? row.metadata_json : {},
    createdAt: toIso(row.created_at),
  };
}

function mapAgentTurnTelemetry(
  row: Record<string, unknown>,
): AgentTurnTelemetryRecord {
  return {
    id: row.id as string,
    conversationId: optionalString(row.conversation_id),
    traceId: row.trace_id as string,
    turnId: row.turn_id as string,
    userId: optionalString(row.user_id),
    inputMode: optionalString(row.input_mode),
    source: optionalString(row.source),
    activeProposalId: optionalString(row.active_proposal_id),
    model: optionalString(row.model),
    inputText: optionalString(row.input_text),
    assistantText: optionalString(row.assistant_text),
    resultKind: optionalString(row.result_kind),
    stopReason: optionalString(row.stop_reason),
    iterationCount: Number(row.iteration_count ?? 0),
    toolCallCount: Number(row.tool_call_count ?? 0),
    promptChars: optionalNumber(row.prompt_chars),
    messagesJsonChars: optionalNumber(row.messages_json_chars),
    toolsJsonChars: optionalNumber(row.tools_json_chars),
    requestPayloadChars: optionalNumber(row.request_payload_chars),
    promptTokens: optionalNumber(row.prompt_tokens),
    completionTokens: optionalNumber(row.completion_tokens),
    totalTokens: optionalNumber(row.total_tokens),
    reasoningTokens: optionalNumber(row.reasoning_tokens),
    providerCostAmount: optionalNumber(row.provider_cost_amount),
    estimatedCostAmount: optionalNumber(row.estimated_cost_amount),
    costCurrency: optionalString(row.cost_currency),
    costSource: optionalString(row.cost_source),
    pricingSnapshot: isRecord(row.pricing_snapshot_json)
      ? row.pricing_snapshot_json
      : {},
    firstByteMs: optionalNumber(row.first_byte_ms),
    firstToolCallMs: optionalNumber(row.first_tool_call_ms),
    largestStreamGapMs: optionalNumber(row.largest_stream_gap_ms),
    llmMs: optionalNumber(row.llm_ms),
    actionMs: optionalNumber(row.action_ms),
    totalMs: optionalNumber(row.total_ms),
    status: row.status as string,
    errorCode: optionalString(row.error_code),
    errorMessage: optionalString(row.error_message),
    metadata: isRecord(row.metadata_json) ? row.metadata_json : {},
    completedAt: row.completed_at == null ? undefined : toIso(row.completed_at),
    createdAt: toIso(row.created_at),
  };
}

function mapAgentToolCallTelemetry(
  row: Record<string, unknown>,
): AgentToolCallTelemetryRecord {
  return {
    id: row.id as string,
    agentTurnId: optionalString(row.agent_turn_id),
    conversationId: optionalString(row.conversation_id),
    traceId: row.trace_id as string,
    turnId: optionalString(row.turn_id),
    userId: optionalString(row.user_id),
    toolCallId: optionalString(row.tool_call_id),
    actionCallId: optionalString(row.action_call_id),
    actionId: row.action_id as string,
    arguments: row.arguments_json ?? undefined,
    resultSummary: row.result_summary_json ?? undefined,
    status: row.status as string,
    errorMessage: optionalString(row.error_message),
    startedAt: toIso(row.started_at),
    completedAt: row.completed_at == null ? undefined : toIso(row.completed_at),
    durationMs: optionalNumber(row.duration_ms),
    metadata: isRecord(row.metadata_json) ? row.metadata_json : {},
    createdAt: toIso(row.created_at),
  };
}

function mapLlmProviderCall(
  row: Record<string, unknown>,
): LlmProviderCallRecord {
  return {
    id: row.id as string,
    traceId: row.trace_id as string,
    userId: optionalString(row.user_id),
    conversationId: optionalString(row.conversation_id),
    agentTurnId: optionalString(row.agent_turn_id),
    turnId: optionalString(row.turn_id),
    actionCallId: optionalString(row.action_call_id),
    featureSurface: row.feature_surface as string,
    provider: row.provider as string,
    providerRequestId: optionalString(row.provider_request_id),
    providerGenerationId: optionalString(row.provider_generation_id),
    requestedModel: row.requested_model as string,
    servedModel: optionalString(row.served_model),
    routing: row.routing_json ?? undefined,
    inputMode: optionalString(row.input_mode),
    promptTokens: optionalNumber(row.prompt_tokens),
    completionTokens: optionalNumber(row.completion_tokens),
    totalTokens: optionalNumber(row.total_tokens),
    reasoningTokens: optionalNumber(row.reasoning_tokens),
    cachedInputTokens: optionalNumber(row.cached_input_tokens),
    audioTokens: optionalNumber(row.audio_tokens),
    imageTokens: optionalNumber(row.image_tokens),
    providerCostAmount: optionalNumber(row.provider_cost_amount),
    estimatedCostAmount: optionalNumber(row.estimated_cost_amount),
    costCurrency: optionalString(row.cost_currency),
    costSource: row.cost_source as string,
    inputTokenUnitPrice: optionalNumber(row.input_token_unit_price),
    outputTokenUnitPrice: optionalNumber(row.output_token_unit_price),
    reasoningTokenUnitPrice: optionalNumber(row.reasoning_token_unit_price),
    cachedInputTokenUnitPrice: optionalNumber(
      row.cached_input_token_unit_price,
    ),
    audioTokenUnitPrice: optionalNumber(row.audio_token_unit_price),
    imageTokenUnitPrice: optionalNumber(row.image_token_unit_price),
    pricingSource: optionalString(row.pricing_source),
    pricingVersion: optionalString(row.pricing_version),
    pricingEffectiveAt:
      row.pricing_effective_at == null
        ? undefined
        : toIso(row.pricing_effective_at),
    status: row.status as string,
    errorCode: optionalString(row.error_code),
    errorMessage: optionalString(row.error_message),
    durationMs: optionalNumber(row.duration_ms),
    metadata: isRecord(row.metadata_json) ? row.metadata_json : {},
    createdAt: toIso(row.created_at),
  };
}

function mapTranscriptionRecord(
  row: Record<string, unknown>,
): TranscriptionRecord {
  return {
    id: row.id as string,
    traceId: row.trace_id as string,
    userId: optionalString(row.user_id),
    conversationId: optionalString(row.conversation_id),
    turnId: optionalString(row.turn_id),
    surface: row.surface as string,
    provider: optionalString(row.provider),
    model: optionalString(row.model),
    language: optionalString(row.language),
    audioMimeType: optionalString(row.audio_mime_type),
    audioBytes: optionalNumber(row.audio_bytes),
    audioDurationMs: optionalNumber(row.audio_duration_ms),
    transcriptText: optionalString(row.transcript_text),
    transcriptLength: Number(row.transcript_length ?? 0),
    durationMs: optionalNumber(row.duration_ms),
    status: row.status as string,
    errorCode: optionalString(row.error_code),
    errorMessage: optionalString(row.error_message),
    downstreamResultKind: optionalString(row.downstream_result_kind),
    metadata: isRecord(row.metadata_json) ? row.metadata_json : {},
    createdAt: toIso(row.created_at),
  };
}

function mapFoodSearchEvent(
  row: Record<string, unknown>,
): FoodSearchEventRecord {
  return {
    id: row.id as string,
    traceId: row.trace_id as string,
    userId: row.user_id as string | undefined,
    queryText: row.query_text as string | undefined,
    queryHash: row.query_hash as string | undefined,
    queryLength: Number(row.query_length ?? 0),
    locale: row.locale as string | undefined,
    barcodePresent: Boolean(row.barcode_present),
    normalizedSearchEnabled:
      row.normalized_search_enabled == null
        ? undefined
        : Boolean(row.normalized_search_enabled),
    normalizedScope: row.normalized_scope as string | undefined,
    path: row.path as string | undefined,
    resultCount: Number(row.result_count ?? 0),
    candidateGroupCount: optionalNumber(row.candidate_group_count),
    topScore: row.top_score == null ? undefined : Number(row.top_score),
    topExternalSource: row.top_external_source as string | undefined,
    topResultType: row.top_result_type as string | undefined,
    zeroResults: Boolean(row.zero_results),
    lowConfidence: Boolean(row.low_confidence),
    selectedRank: optionalNumber(row.selected_rank),
    durationMs: optionalNumber(row.duration_ms),
    metadata: isRecord(row.metadata_json) ? row.metadata_json : {},
    createdAt: toIso(row.created_at),
  };
}

function toIso(value: unknown): string {
  return value instanceof Date
    ? value.toISOString()
    : new Date(value as string).toISOString();
}

function toDateOnly(value: unknown): string {
  return value instanceof Date
    ? value.toISOString().slice(0, 10)
    : String(value).slice(0, 10);
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function optionalNumber(value: unknown): number | undefined {
  return value == null ? undefined : Number(value);
}

function boundedLimit(limit: number | undefined, defaultLimit: number): number {
  return Math.max(1, Math.min(500, Math.floor(limit ?? defaultLimit)));
}

function buildPostgresCostOverview(
  from: string,
  to: string,
  calls: LlmProviderCallRecord[],
): LlmCostOverview {
  const providerCost = sumOptionalNumber(
    calls.map((call) => call.providerCostAmount),
  );
  const estimatedCost = sumOptionalNumber(
    calls.map((call) => call.estimatedCostAmount),
  );
  return {
    from,
    to,
    totalProviderCostAmount: providerCost,
    totalEstimatedCostAmount: estimatedCost,
    totalCostAmount: providerCost + estimatedCost,
    unknownCostCount: calls.filter((call) => call.costSource === "unknown")
      .length,
    totalPromptTokens: sumOptionalNumber(
      calls.map((call) => call.promptTokens),
    ),
    totalCompletionTokens: sumOptionalNumber(
      calls.map((call) => call.completionTokens),
    ),
    totalTokens: sumOptionalNumber(calls.map((call) => call.totalTokens)),
    byUser: costBreakdown(calls, (call) => call.userId ?? "unknown"),
    byConversation: costBreakdown(
      calls,
      (call) => call.conversationId ?? "unknown",
    ),
    byTurn: costBreakdown(calls, (call) => call.turnId ?? "unknown"),
    byModel: costBreakdown(calls, (call) => call.requestedModel),
    byProvider: costBreakdown(calls, (call) => call.provider),
    byFeature: costBreakdown(calls, (call) => call.featureSurface),
    byDay: costBreakdown(calls, (call) => call.createdAt.slice(0, 10)),
  };
}

function costBreakdown(
  calls: LlmProviderCallRecord[],
  keyFor: (call: LlmProviderCallRecord) => string,
): LlmCostOverview["byUser"] {
  const grouped = new Map<string, LlmProviderCallRecord[]>();
  for (const call of calls) {
    const key = keyFor(call);
    grouped.set(key, [...(grouped.get(key) ?? []), call]);
  }
  return [...grouped.entries()]
    .map(([key, group]) => {
      const providerCostAmount = sumOptionalNumber(
        group.map((call) => call.providerCostAmount),
      );
      const estimatedCostAmount = sumOptionalNumber(
        group.map((call) => call.estimatedCostAmount),
      );
      return {
        key,
        providerCostAmount,
        estimatedCostAmount,
        totalCostAmount: providerCostAmount + estimatedCostAmount,
        unknownCostCount: group.filter((call) => call.costSource === "unknown")
          .length,
        totalTokens: sumOptionalNumber(group.map((call) => call.totalTokens)),
        callCount: group.length,
      };
    })
    .sort((a, b) => b.totalCostAmount - a.totalCostAmount);
}

function sumOptionalNumber(values: Array<number | undefined>): number {
  return values.reduce<number>((sum, value) => sum + (value ?? 0), 0);
}

function arrayOfStrings(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string")
    : [];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function tokenPhraseContained(text: string, phrase: string): boolean {
  if (!text || !phrase) return false;
  return ` ${text} `.includes(` ${phrase} `);
}

function titleCaseDisplay(value: string): string {
  return value
    .toLowerCase()
    .replace(
      /\b[\p{L}\p{N}][\p{L}\p{N}'%-]*/gu,
      (word) => `${word[0]?.toUpperCase() ?? ""}${word.slice(1)}`,
    );
}

function previousDatesInWeek(date: string): string[] {
  const current = new Date(`${date}T00:00:00.000Z`);
  const weekday = current.getUTCDay() === 0 ? 7 : current.getUTCDay();
  const dates: string[] = [];
  for (let offset = weekday - 1; offset > 0; offset--) {
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

function cloneFoodSearchCandidate(
  candidate: FoodSearchCandidate,
): FoodSearchCandidate {
  return {
    ...candidate,
    portions: candidate.portions?.map((portion) => ({ ...portion })),
  };
}

function mergeFoodSearchRowCandidate(
  candidates: Map<string, FoodSearchRowCandidate>,
  next: FoodSearchRowCandidate,
): void {
  const foodId = optionalString(next.row.id);
  if (!foodId) return;
  const existing = candidates.get(foodId);
  if (!existing) {
    candidates.set(foodId, next);
    return;
  }

  const existingRank = existing.scopeRank ?? Number.MAX_SAFE_INTEGER;
  const nextRank = next.scopeRank ?? Number.MAX_SAFE_INTEGER;
  if (
    nextRank < existingRank ||
    (nextRank === existingRank && next.lexicalScore > existing.lexicalScore)
  ) {
    candidates.set(foodId, {
      ...next,
      vectorScore: maxOptionalScore(existing.vectorScore, next.vectorScore),
    });
    return;
  }
  if (nextRank === existingRank) {
    existing.lexicalScore = Math.max(existing.lexicalScore, next.lexicalScore);
    existing.vectorScore = maxOptionalScore(
      existing.vectorScore,
      next.vectorScore,
    );
  }
}

function maxOptionalScore(
  a: number | undefined,
  b: number | undefined,
): number | undefined {
  if (a == null) return b;
  if (b == null) return a;
  return Math.max(a, b);
}

function foodSearchScopeRankFromRow(
  row: Record<string, unknown>,
): number | undefined {
  const value = row.search_scope_rank;
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const resultTypeRank = row.search_result_type_rank;
  if (typeof resultTypeRank === "number" && Number.isFinite(resultTypeRank)) {
    return resultTypeRank;
  }
  return undefined;
}

function foodSearchScopeRankForSort(
  input: FoodHybridSearchInput,
  scopeRank: number | undefined,
): number {
  if (input.barcode) return 0;
  return scopeRank ?? 0;
}

function compareFoodSearchRankedCandidates(
  a: FoodSearchRankedCandidate,
  b: FoodSearchRankedCandidate,
): number {
  return (
    a.scopeRank - b.scopeRank ||
    b.candidate.finalScore - a.candidate.finalScore ||
    b.candidate.lexicalScore - a.candidate.lexicalScore ||
    (b.candidate.vectorScore ?? 0) - (a.candidate.vectorScore ?? 0) ||
    Number(Boolean(b.candidate.userId)) - Number(Boolean(a.candidate.userId)) ||
    a.candidate.name.localeCompare(b.candidate.name)
  );
}

function mergeNormalizedFoodDocumentRows(
  limit: number,
  ...rowGroups: Record<string, unknown>[][]
): Record<string, unknown>[] {
  const searchLimit = normalizedFoodSearchLimit(limit);
  const merged: Record<string, unknown>[] = [];
  const seenFoodIds = new Set<string>();
  const seenDisplayNames = new Set<string>();

  for (const rows of rowGroups) {
    for (const row of rows) {
      const foodId = optionalString(row.id);
      if (!foodId || seenFoodIds.has(foodId)) continue;
      const displayName =
        optionalString(row.search_display_name) ?? optionalString(row.name);
      const displayKey = displayName?.trim().toLowerCase();
      if (displayKey && seenDisplayNames.has(displayKey)) continue;
      seenFoodIds.add(foodId);
      if (displayKey) seenDisplayNames.add(displayKey);
      merged.push(row);
      if (merged.length >= searchLimit) return merged;
    }
  }

  return merged;
}

function normalizedStrongIdentityCanShortCircuit(
  rows: Record<string, unknown>[],
  limit: number,
): boolean {
  const searchLimit = normalizedFoodSearchLimit(limit);
  if (rows.length < searchLimit) return false;
  const resultRows = rows.slice(0, searchLimit);
  const genericRows = resultRows.filter(
    (row) => row.search_normalized_result_type === "generic_food",
  ).length;
  const productRows = resultRows.filter(
    (row) => row.search_normalized_result_type === "product",
  ).length;
  const topResultType = resultRows[0]?.search_normalized_result_type;
  return (
    genericRows >= productRows ||
    (topResultType === "generic_food" && genericRows > 0)
  );
}

function foodSearchCacheKey(
  userId: string,
  input: FoodHybridSearchInput,
  normalized: string,
  limit: number,
): string {
  return JSON.stringify({
    userId,
    query: normalized,
    barcode: input.barcode,
    locale: normalizeSearchLocale(input.locale),
    limit,
  });
}

function foodTextSearchPredicateSql(normalized: string): SQL {
  const prefixQuery = foodSearchPrefixTsQuery(normalized);
  return dbSql`
    food_search_documents.search_vector @@ websearch_to_tsquery('simple', ${normalized})
    OR food_search_documents.search_vector @@ to_tsquery('simple', ${prefixQuery})
  `;
}

function foodTextSearchScoreSql(normalized: string): SQL {
  const prefixQuery = foodSearchPrefixTsQuery(normalized);
  return dbSql`
    GREATEST(
      ts_rank_cd(food_search_documents.search_vector, websearch_to_tsquery('simple', ${normalized}))::float,
      (ts_rank_cd(food_search_documents.search_vector, to_tsquery('simple', ${prefixQuery})) * 0.9)::float,
      ${foodSearchScoreSql(normalized)}
    )
  `;
}

function normalizedFoodTextSearchPredicateSql(normalized: string): SQL {
  const prefixQuery = foodSearchPrefixTsQuery(normalized);
  const queryTokenCount = normalized.split(/\s+/).filter(Boolean).length;
  const usePrefixQuery = queryTokenCount > 1;
  if (queryTokenCount === 1) {
    const tokenPrefix = `${normalized} %`;
    const tokenContainsMiddle = `% ${normalized} %`;
    const tokenContainsEnd = `% ${normalized}`;
    const baseName = dbSql`lower(COALESCE(food_normalized_search_documents.base_name, ''))`;
    const displayName = dbSql`lower(COALESCE(food_normalized_search_documents.display_name, ''))`;
    const brandDisplay = dbSql`lower(COALESCE(food_normalized_search_documents.brand_display, ''))`;
    return dbSql`
      (
        food_normalized_search_documents.result_type <> 'product'
        AND food_normalized_search_documents.search_vector @@ websearch_to_tsquery('simple', ${normalized})
      )
      OR (
        food_normalized_search_documents.result_type = 'product'
        AND food_normalized_search_documents.search_vector @@ websearch_to_tsquery('simple', ${normalized})
        AND (
          ${baseName} = ${normalized}
          OR ${displayName} = ${normalized}
          OR ${brandDisplay} = ${normalized}
          OR ${baseName} LIKE ${tokenPrefix}
          OR ${displayName} LIKE ${tokenPrefix}
          OR ${brandDisplay} LIKE ${tokenPrefix}
          OR ${baseName} LIKE ${tokenContainsMiddle}
          OR ${baseName} LIKE ${tokenContainsEnd}
          OR ${displayName} LIKE ${tokenContainsMiddle}
          OR ${displayName} LIKE ${tokenContainsEnd}
          OR food_normalized_search_documents.primary_entity_aliases @> ARRAY[${normalized}]::text[]
          OR food_normalized_search_documents.secondary_entity_aliases @> ARRAY[${normalized}]::text[]
        )
      )
    `;
  }
  return dbSql`
    food_normalized_search_documents.search_vector @@ websearch_to_tsquery('simple', ${normalized})
    OR (
      ${usePrefixQuery}
      AND food_normalized_search_documents.search_vector @@ to_tsquery('simple', ${prefixQuery})
    )
  `;
}

function normalizedFoodStrongIdentityPredicateSql(
  normalized: string,
  queryIdentityKey: string | undefined,
): SQL {
  const identityPredicate = queryIdentityKey
    ? dbSql`OR ${normalizedFoodIdentityTokenKeyPredicateSql(queryIdentityKey)}`
    : dbSql``;
  return dbSql`
    lower(food_normalized_search_documents.base_name) = ${normalized}
    OR lower(food_normalized_search_documents.display_name) = ${normalized}
    OR lower(food_normalized_search_documents.brand_display) = ${normalized}
    OR food_normalized_search_documents.primary_entity_aliases @> ARRAY[${normalized}]::text[]
    ${identityPredicate}
  `;
}

function normalizedFoodIdentityTokenKeyPredicateSql(
  queryIdentityKey: string,
): SQL {
  return dbSql`food_normalized_search_documents.identity_token_keys @> ARRAY[${queryIdentityKey}]::text[]`;
}

function normalizedFoodTextSearchScoreSql(
  normalized: string,
  queryIdentityKey: string | undefined,
): SQL {
  const prefixQuery = foodSearchPrefixTsQuery(normalized);
  const usePrefixQuery = normalized.split(/\s+/).filter(Boolean).length > 1;
  return dbSql`
    GREATEST(
      LEAST(0.74::float, ts_rank_cd(food_normalized_search_documents.search_vector, websearch_to_tsquery('simple', ${normalized}))::float),
      CASE
        WHEN ${usePrefixQuery}
        THEN LEAST(0.70::float, (ts_rank_cd(food_normalized_search_documents.search_vector, to_tsquery('simple', ${prefixQuery})) * 0.9)::float)
        ELSE 0::float
      END,
      ${normalizedFoodSearchScoreSql(normalized, queryIdentityKey)}
    )
  `;
}

function foodSearchScoreSql(normalized: string): SQL {
  const prefix = `${normalized}%`;
  const tokenPrefix = `${normalized} %`;
  const tokenContainsMiddle = `% ${normalized} %`;
  const tokenContainsEnd = `% ${normalized}`;
  const queryTokenCount = normalized.split(/\s+/).filter(Boolean).length;
  const normalizedName = dbSql`COALESCE(food_items.normalized_name, '')`;
  const canonicalName = dbSql`COALESCE(food_items.canonical_name, '')`;
  const normalizedNamePenalty = compactnessPenaltySql(
    normalizedName,
    normalized,
    queryTokenCount,
  );
  const canonicalNamePenalty = compactnessPenaltySql(
    canonicalName,
    normalized,
    queryTokenCount,
  );

  return dbSql`
    GREATEST(
      CASE
        WHEN ${normalizedName} = ${normalized}
          OR ${canonicalName} = ${normalized}
          OR food_search_documents.search_text = ${normalized}
        THEN 1::float
        ELSE 0::float
      END,
      CASE
        WHEN ${candidatePhraseInQuerySql(normalizedName, normalized)}
          OR ${candidatePhraseInQuerySql(canonicalName, normalized)}
        THEN 0.78::float
        ELSE 0::float
      END,
      CASE
        WHEN ${normalizedName} LIKE ${tokenPrefix}
          OR ${canonicalName} LIKE ${tokenPrefix}
        THEN GREATEST(
          CASE WHEN ${normalizedName} LIKE ${tokenPrefix} THEN 0.94::float - ${normalizedNamePenalty} ELSE 0::float END,
          CASE WHEN ${canonicalName} LIKE ${tokenPrefix} THEN 0.94::float - ${canonicalNamePenalty} ELSE 0::float END
        )
        ELSE 0::float
      END,
      CASE
        WHEN food_search_documents.search_text LIKE ${tokenPrefix}
        THEN 0.90::float
        ELSE 0::float
      END,
      CASE
        WHEN ${normalizedName} LIKE ${tokenContainsMiddle}
          OR ${normalizedName} LIKE ${tokenContainsEnd}
          OR ${canonicalName} LIKE ${tokenContainsMiddle}
          OR ${canonicalName} LIKE ${tokenContainsEnd}
        THEN GREATEST(
          CASE
            WHEN ${normalizedName} LIKE ${tokenContainsMiddle}
              OR ${normalizedName} LIKE ${tokenContainsEnd}
            THEN 0.82::float - ${normalizedNamePenalty}
            ELSE 0::float
          END,
          CASE
            WHEN ${canonicalName} LIKE ${tokenContainsMiddle}
              OR ${canonicalName} LIKE ${tokenContainsEnd}
            THEN 0.82::float - ${canonicalNamePenalty}
            ELSE 0::float
          END
        )
        ELSE 0::float
      END,
      CASE
        WHEN food_search_documents.search_text LIKE ${tokenContainsMiddle}
          OR food_search_documents.search_text LIKE ${tokenContainsEnd}
        THEN 0.76::float
        ELSE 0::float
      END,
      CASE
        WHEN ${normalizedName} LIKE ${prefix}
          OR ${canonicalName} LIKE ${prefix}
        THEN GREATEST(
          CASE WHEN ${normalizedName} LIKE ${prefix} THEN 0.62::float - ${normalizedNamePenalty} ELSE 0::float END,
          CASE WHEN ${canonicalName} LIKE ${prefix} THEN 0.62::float - ${canonicalNamePenalty} ELSE 0::float END
        )
        ELSE 0::float
      END,
      CASE
        WHEN food_search_documents.search_text LIKE ${prefix}
        THEN 0.58::float
        ELSE 0::float
      END
    )
  `;
}

function normalizedFoodSearchScoreSql(
  normalized: string,
  queryIdentityKey: string | undefined,
): SQL {
  const prefix = `${normalized}%`;
  const tokenPrefix = `${normalized} %`;
  const tokenContainsMiddle = `% ${normalized} %`;
  const tokenContainsEnd = `% ${normalized}`;
  const queryTokenCount = normalized.split(/\s+/).filter(Boolean).length;
  const isMultiTokenQuery = queryTokenCount > 1;
  const isSingleTokenQuery = queryTokenCount === 1;
  const baseName = dbSql`lower(COALESCE(food_normalized_search_documents.base_name, ''))`;
  const displayName = dbSql`lower(COALESCE(food_normalized_search_documents.display_name, ''))`;
  const brandDisplay = dbSql`lower(COALESCE(food_normalized_search_documents.brand_display, ''))`;
  const baseNameWithBrand = dbSql`trim(concat_ws(' ', NULLIF(${baseName}, ''), NULLIF(${brandDisplay}, '')))`;
  const brandWithBaseName = dbSql`trim(concat_ws(' ', NULLIF(${brandDisplay}, ''), NULLIF(${baseName}, '')))`;
  const baseNameSecondToken = dbSql`split_part(${baseName}, ' ', 2)`;
  const primaryEntityName = dbSql`lower(COALESCE(food_normalized_search_documents.primary_entity_name, ''))`;
  const primaryAliases = dbSql`food_normalized_search_documents.primary_entity_aliases`;
  const secondaryAliases = dbSql`food_normalized_search_documents.secondary_entity_aliases`;
  const identityTokenKeyMatch = queryIdentityKey
    ? dbSql`food_normalized_search_documents.identity_token_keys @> ARRAY[${queryIdentityKey}]::text[]`
    : dbSql`false`;
  const primaryEntityCategoryCoherence = dbSql`
    COALESCE(food_normalized_search_documents.primary_entity_category_coherence, 0)::float
  `;
  const primaryEntityRepresentativeness = dbSql`
    COALESCE(food_normalized_search_documents.primary_entity_representativeness, 0)::float
  `;
  const primaryAliasScore = normalizedFoodEntityAliasScoreSql(
    primaryAliases,
    normalized,
    queryTokenCount,
    {
      exact: 0.92,
      prefix: 0.89,
      queryStartsAlias: 0.82,
    },
  );
  const secondaryAliasScore = normalizedFoodEntityAliasScoreSql(
    secondaryAliases,
    normalized,
    queryTokenCount,
    {
      exact: 0.82,
      prefix: 0.72,
      queryStartsAlias: 0.64,
    },
  );
  const baseNamePenalty = compactnessPenaltySql(
    baseName,
    normalized,
    queryTokenCount,
  );
  const displayNamePenalty = compactnessPenaltySql(
    displayName,
    normalized,
    queryTokenCount,
  );
  const structuralTieScore = normalizedFoodStructuralTieScoreSql(
    normalized,
    baseName,
    displayName,
    baseNamePenalty,
    displayNamePenalty,
  );

  return dbSql`
    GREATEST(
      CASE
        WHEN food_items.barcode = ${normalized}
        THEN 1::float
        ELSE 0::float
      END,
      CASE
        WHEN food_normalized_search_documents.result_type = 'generic_food'
          AND ${isMultiTokenQuery}
          AND ${identityTokenKeyMatch}
        THEN LEAST(
          0.98::float,
          0.94::float +
            (${primaryEntityCategoryCoherence} * 0.015::float) +
            (${primaryEntityRepresentativeness} * 0.025::float)
        )
        ELSE 0::float
      END,
      CASE
        WHEN ${isMultiTokenQuery}
          AND (
            food_normalized_search_documents.result_type <> 'product'
              AND (
                food_normalized_search_documents.search_text = ${normalized}
                OR ${displayName} = ${normalized}
                OR ${baseName} = ${normalized}
              )
          )
        THEN 1::float
        ELSE 0::float
      END,
      CASE
        WHEN ${isMultiTokenQuery}
          AND food_normalized_search_documents.result_type = 'product'
          AND (
            ${displayName} = ${normalized}
            OR ${baseName} = ${normalized}
          )
        THEN 0.90::float
        ELSE 0::float
      END,
      CASE
        WHEN ${isMultiTokenQuery}
          AND food_normalized_search_documents.result_type = 'product'
          AND ${brandDisplay} <> ''
          AND (
            ${baseNameWithBrand} = ${normalized}
            OR ${brandWithBaseName} = ${normalized}
          )
        THEN 0.89::float
        ELSE 0::float
      END,
      CASE
        WHEN food_normalized_search_documents.result_type = 'product'
          AND ${isMultiTokenQuery}
          AND ${identityTokenKeyMatch}
        THEN 0.84::float
        ELSE 0::float
      END,
      CASE
        WHEN food_normalized_search_documents.result_type = 'generic_food'
          AND ${primaryAliasScore} > 0::float
        THEN LEAST(
          0.99::float,
          ${primaryAliasScore} +
            (${primaryEntityCategoryCoherence} * 0.025::float) +
            (${primaryEntityRepresentativeness} * 0.045::float) +
            (${structuralTieScore} * 0.025::float)
        )
        WHEN food_normalized_search_documents.result_type = 'product'
          AND ${primaryAliasScore} >= 0.92::float
        THEN CASE WHEN ${isSingleTokenQuery} THEN 0.74::float ELSE 0.90::float END
        WHEN food_normalized_search_documents.result_type = 'product'
        THEN LEAST(0.78::float, ${primaryAliasScore})
        ELSE LEAST(0.90::float, ${primaryAliasScore})
      END,
      CASE
        WHEN food_normalized_search_documents.result_type = 'generic_food'
          AND ${secondaryAliasScore} >= 0.76::float
          AND (
            ${baseName} = ${normalized}
            OR ${displayName} = ${normalized}
            OR ${baseName} LIKE ${tokenPrefix}
            OR ${displayName} LIKE ${tokenPrefix}
          )
        THEN LEAST(
          0.96::float,
          0.91::float +
            (${primaryEntityCategoryCoherence} * 0.015::float) +
            (${primaryEntityRepresentativeness} * 0.025::float)
        )
        ELSE 0::float
      END,
      CASE
        WHEN food_normalized_search_documents.result_type = 'generic_food'
          AND ${isSingleTokenQuery}
          AND ${secondaryAliasScore} > 0::float
          AND ${baseNameSecondToken} = ${normalized}
          AND ${primaryEntityName} ~ '^[[:alpha:]][[:alpha:] ]*$'
        THEN LEAST(
          0.85::float,
          0.82::float +
            (${primaryEntityCategoryCoherence} * 0.010::float) +
            (${primaryEntityRepresentativeness} * 0.015::float)
        )
        ELSE 0::float
      END,
      ${secondaryAliasScore},
      CASE
        WHEN ${brandDisplay} = ${normalized}
          OR (
            ${isMultiTokenQuery}
            AND ${brandDisplay} LIKE ${tokenPrefix}
          )
        THEN 0.62::float
        ELSE 0::float
      END,
      CASE
        WHEN food_normalized_search_documents.result_type = 'product'
          AND (
            ${baseName} = ${normalized}
            OR ${displayName} = ${normalized}
          )
        THEN CASE WHEN ${isSingleTokenQuery} THEN 0.74::float ELSE 0.86::float END
        ELSE 0::float
      END,
      CASE
        WHEN food_normalized_search_documents.result_type = 'generic_food'
          AND (
            ${baseName} LIKE ${tokenPrefix}
            OR ${displayName} LIKE ${tokenPrefix}
          )
        THEN GREATEST(
          CASE WHEN ${baseName} LIKE ${tokenPrefix} THEN 0.74::float - ${baseNamePenalty} ELSE 0::float END,
          CASE WHEN ${displayName} LIKE ${tokenPrefix} THEN 0.74::float - ${displayNamePenalty} ELSE 0::float END
        )
        ELSE 0::float
      END,
      CASE
        WHEN food_normalized_search_documents.result_type = 'generic_food'
          AND (
            ${baseName} LIKE ${tokenContainsMiddle}
            OR ${baseName} LIKE ${tokenContainsEnd}
            OR ${displayName} LIKE ${tokenContainsMiddle}
            OR ${displayName} LIKE ${tokenContainsEnd}
          )
        THEN GREATEST(
          CASE
            WHEN ${baseName} LIKE ${tokenContainsMiddle}
              OR ${baseName} LIKE ${tokenContainsEnd}
            THEN 0.68::float - ${baseNamePenalty}
            ELSE 0::float
          END,
          CASE
            WHEN ${displayName} LIKE ${tokenContainsMiddle}
              OR ${displayName} LIKE ${tokenContainsEnd}
            THEN 0.68::float - ${displayNamePenalty}
            ELSE 0::float
          END
        )
        ELSE 0::float
      END,
      CASE
        WHEN food_normalized_search_documents.result_type = 'generic_food'
          AND (
            ${baseName} LIKE ${prefix}
            OR ${displayName} = ${normalized}
          )
        THEN GREATEST(
          CASE WHEN ${baseName} LIKE ${prefix} THEN 0.58::float - ${baseNamePenalty} ELSE 0::float END,
          CASE WHEN ${displayName} LIKE ${prefix} THEN 0.58::float - ${displayNamePenalty} ELSE 0::float END
        )
        ELSE 0::float
      END
    )
  `;
}

function normalizedFoodEntityAliasScoreSql(
  aliases: SQL,
  normalized: string,
  queryTokenCount: number,
  scores: { exact: number; prefix: number; queryStartsAlias: number },
): SQL {
  const tokenPrefix = `${normalized} %`;
  return dbSql`
    COALESCE((
      SELECT MAX(GREATEST(
        CASE
          WHEN entity_alias.alias = ${normalized}
          THEN ${scores.exact}::float
          ELSE 0::float
        END,
        CASE
          WHEN entity_alias.alias LIKE ${tokenPrefix}
          THEN ${scores.prefix}::float - ${compactnessPenaltySql(dbSql`entity_alias.alias`, normalized, queryTokenCount)}
          ELSE 0::float
        END,
        CASE
          WHEN ${normalized} LIKE entity_alias.alias || ' %'
          THEN ${scores.queryStartsAlias}::float
          ELSE 0::float
        END
      ))
      FROM unnest(${aliases}) AS entity_alias(alias)
      WHERE entity_alias.alias <> ''
    ), 0::float)
  `;
}

function normalizedFoodStructuralTieScoreSql(
  normalized: string,
  baseName: SQL,
  displayName: SQL,
  baseNamePenalty: SQL,
  displayNamePenalty: SQL,
): SQL {
  const prefix = `${normalized}%`;
  const tokenPrefix = `${normalized} %`;
  const tokenContainsMiddle = `% ${normalized} %`;
  const tokenContainsEnd = `% ${normalized}`;
  return dbSql`
    GREATEST(
      CASE
        WHEN ${baseName} = ${normalized}
          OR ${displayName} = ${normalized}
        THEN 1::float
        ELSE 0::float
      END,
      CASE
        WHEN ${baseName} LIKE ${tokenPrefix}
          OR ${displayName} LIKE ${tokenPrefix}
        THEN GREATEST(
          CASE WHEN ${baseName} LIKE ${tokenPrefix} THEN 0.94::float - ${baseNamePenalty} ELSE 0::float END,
          CASE WHEN ${displayName} LIKE ${tokenPrefix} THEN 0.94::float - ${displayNamePenalty} ELSE 0::float END
        )
        ELSE 0::float
      END,
      CASE
        WHEN ${baseName} LIKE ${tokenContainsMiddle}
          OR ${baseName} LIKE ${tokenContainsEnd}
          OR ${displayName} LIKE ${tokenContainsMiddle}
          OR ${displayName} LIKE ${tokenContainsEnd}
        THEN GREATEST(
          CASE
            WHEN ${baseName} LIKE ${tokenContainsMiddle}
              OR ${baseName} LIKE ${tokenContainsEnd}
            THEN 0.82::float - ${baseNamePenalty}
            ELSE 0::float
          END,
          CASE
            WHEN ${displayName} LIKE ${tokenContainsMiddle}
              OR ${displayName} LIKE ${tokenContainsEnd}
            THEN 0.82::float - ${displayNamePenalty}
            ELSE 0::float
          END
        )
        ELSE 0::float
      END,
      CASE
        WHEN ${baseName} LIKE ${prefix}
          OR ${displayName} LIKE ${prefix}
        THEN GREATEST(
          CASE WHEN ${baseName} LIKE ${prefix} THEN 0.62::float - ${baseNamePenalty} ELSE 0::float END,
          CASE WHEN ${displayName} LIKE ${prefix} THEN 0.62::float - ${displayNamePenalty} ELSE 0::float END
        )
        ELSE 0::float
      END
    )
  `;
}

function foodSearchPrefixTsQuery(normalized: string): string {
  return normalized
    .split(/\s+/)
    .filter(Boolean)
    .map((token) => `${token}:*`)
    .join(" & ");
}

function candidatePhraseInQuerySql(text: SQL, normalized: string): SQL {
  const paddedQuery = ` ${normalized} `;
  return dbSql`${text} <> '' AND POSITION(' ' || ${text} || ' ' IN ${paddedQuery}) > 0`;
}

function compactnessPenaltySql(
  text: SQL,
  normalized: string,
  queryTokenCount: number,
): SQL {
  return dbSql`
    LEAST(
      0.12::float,
      GREATEST(
        COALESCE(array_length(regexp_split_to_array(NULLIF(trim(${text}), ''), '[[:space:]]+'), 1), 0) - ${queryTokenCount},
        0
      )::float * 0.015 +
      GREATEST(char_length(trim(${text})) - char_length(${normalized}), 0)::float * 0.001
    )
  `;
}

function normalizedFoodSearchProfile(
  input: FoodHybridSearchInput,
): NormalizedFoodSearchProfile {
  const locale = normalizeSearchLocale(input.locale);
  if (locale === "es") return { locales: ["es", "any", "en"] };
  if (locale === "en") return { locales: ["en", "any", "es"] };
  return { locales: ["en", "any", "es"] };
}

function normalizedFoodSearchLimit(limit: number): number {
  return limit;
}

function foodSearchProfiles(input: FoodHybridSearchInput): FoodSearchProfile[] {
  const locale = normalizeSearchLocale(input.locale);
  const marketLocales = uniqueStrings(
    [locale, "en", "es", "any"].filter(Boolean) as string[],
  );
  const genericProfiles = genericFoodSearchProfiles(locale);
  return [
    ...genericProfiles.map((profile) => ({
      ...profile,
      continueAfterLimit: true,
    })),
    {
      scope: "market",
      locales: marketLocales,
      scopeRank: 1,
    },
  ];
}

function genericFoodSearchProfiles(
  locale: "es" | "en" | undefined,
): FoodSearchProfile[] {
  if (locale === "es") {
    return [
      { scope: "generic", locales: ["es", "any"], scopeRank: 0 },
      { scope: "generic", locales: ["en"], scopeRank: 0 },
    ];
  }
  if (locale === "en") {
    return [
      { scope: "generic", locales: ["en", "any"], scopeRank: 0 },
      { scope: "generic", locales: ["es"], scopeRank: 0 },
    ];
  }
  return [
    { scope: "generic", locales: ["en", "any"], scopeRank: 0 },
    { scope: "generic", locales: ["es"], scopeRank: 0 },
  ];
}

export const postgresFoodSearchTesting = {
  normalizedFoodSearchProfile,
  foodSearchProfiles,
  foodSearchScopeRankForSort,
  compareFoodSearchRankedCandidates,
};

function foodSearchDocumentForFood(food: FoodItemRecord):
  | {
      locale: string;
      scope: "generic" | "market";
      searchText: string;
      rankBucket: number;
    }
  | undefined {
  if (food.deletedAt) return undefined;
  const searchText = normalizeText(
    [
      food.normalizedName,
      food.canonicalName,
      food.name,
      food.brand,
      food.foodCategory,
      ...aliasesFromNutrients(food.nutrients),
    ]
      .filter((value): value is string => Boolean(value))
      .join(" "),
  );
  if (!searchText) return undefined;
  const locale =
    food.foodKey === "es" || food.foodKey === "en"
      ? food.foodKey
      : food.externalSource === "usda_fdc"
        ? "en"
        : "any";
  const scope =
    food.userId ||
    (food.dataType !== "Branded" &&
      food.source !== "usda_branded" &&
      (food.source !== "openfoodfacts" || (!food.barcode && !food.brand)))
      ? "generic"
      : "market";
  const rankBucket = food.userId
    ? 0
    : food.source === "openfoodfacts" &&
        food.foodKey === "es" &&
        !food.barcode &&
        !food.brand
      ? 1
      : food.dataType === "SR Legacy"
        ? 2
        : food.dataType === "Foundation"
          ? 3
          : food.dataType === "Survey (FNDDS)"
            ? 4
            : food.source === "openfoodfacts"
              ? 7
              : food.dataType === "Branded"
                ? 8
                : 6;
  return { locale, scope, searchText, rankBucket };
}

function normalizeSearchLocale(locale?: string): "es" | "en" | undefined {
  const normalized = locale?.toLowerCase();
  if (!normalized) return undefined;
  if (normalized.startsWith("es")) return "es";
  if (normalized.startsWith("en")) return "en";
  return undefined;
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values)];
}

async function executeRows<
  T extends Record<string, unknown> = Record<string, unknown>,
>(dbClient: DbExecutor, query: SQL): Promise<T[]> {
  return (await dbClient.execute(query)) as T[];
}

function sqlList(values: readonly string[]): SQL {
  if (values.length === 0) return dbSql`(NULL)`;
  return dbSql`(${dbSql.join(
    values.map((value) => dbSql`${value}`),
    dbSql`, `,
  )})`;
}

function jsonb(value: unknown): SQL {
  return dbSql`${JSON.stringify(value)}::jsonb`;
}

function groupRowsByString(
  rows: Record<string, unknown>[],
  key: string,
): Map<string, Record<string, unknown>[]> {
  const grouped = new Map<string, Record<string, unknown>[]>();
  for (const row of rows) {
    const value = row[key];
    if (typeof value !== "string") continue;
    const list = grouped.get(value) ?? [];
    list.push(row);
    grouped.set(value, list);
  }
  return grouped;
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

function toVectorLiteral(embedding: number[]): string {
  if (embedding.length !== ACTIVE_EMBEDDING_DIMENSIONS) {
    throw new Error("invalid_embedding_dimensions");
  }
  return `[${embedding
    .map((value) => {
      if (!Number.isFinite(value)) throw new Error("invalid_embedding_value");
      return String(value);
    })
    .join(",")}]`;
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
