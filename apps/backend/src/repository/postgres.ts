import { defaultUserScopes, type CalorieTargetSource, type DailyGoals, type MacroGoalMetadata, type Meal, type MealItem, type MealLabel, type MealProposal, type MealTemplate, type NutritionSnapshot, type PermissionScope } from "@cal-tracker/contracts";
import { sql as dbSql, type SQL } from "drizzle-orm";
import { createDbClient, type AppDb, type AppDbClient } from "../db/client.js";
import { newId } from "../utils/ids.js";
import { applyMacroGoalUpdate } from "../utils/macroGoals.js";
import { withSpan, withSyncSpan } from "../observability/profiler.js";
import { normalizeText } from "../utils/normalize.js";
import { subtractNutrition, sumNutrition } from "../utils/nutrition.js";
import type {
  ActionCallRecord,
  AppRepository,
  AuditEventRecord,
  AuthIdentityProvider,
  AuthIdentityRecord,
  EmbeddingModelRecord,
  FoodFeedbackRecord,
  FoodItemRecord,
  FoodItemEmbeddingRecord,
  FoodHybridSearchInput,
  FoodPortionRecord,
  FoodSearchCandidate,
  MemoryMatch,
  StoredSession,
  StoredUser,
  UpsertFoodItemEmbeddingInput,
  UpdateDailyGoalsInput,
  UserFoodPreference
} from "./types.js";

const ACTIVE_EMBEDDING_MODEL = { provider: "local", model: "bge-m3", dimensions: 1024 };
const DEFAULT_FOOD_SEARCH_LIMIT = 50;
const MAX_FOOD_SEARCH_LIMIT = 100;
const LEXICAL_SCORE_WEIGHT = 0.7;
const VECTOR_SCORE_WEIGHT = 0.25;
const LEXICAL_ONLY_SCORE_WEIGHT = 0.95;
const PREFERENCE_SCORE_WEIGHT = 0.05;
const PREFERENCE_SCORE_NORMALIZER = 10;
const FOOD_SEARCH_CACHE_TTL_MS = 5 * 60 * 1000;
const FOOD_SEARCH_CACHE_MAX_ENTRIES = 500;

type FoodSearchProfile = {
  scope: "generic" | "market";
  locales: string[];
};

type DbExecutor = {
  execute(query: SQL): Promise<unknown>;
};

export class PostgresRepository implements AppRepository {
  private readonly client: AppDbClient;
  private readonly db: AppDb;
  private readonly foodSearchCache = new Map<string, { expiresAt: number; value: FoodSearchCandidate[] }>();

  constructor(databaseUrl: string) {
    this.client = createDbClient(databaseUrl);
    this.db = this.client.db;
  }

  async close(): Promise<void> {
    await this.client.close();
  }

  private execute<T extends Record<string, unknown> = Record<string, unknown>>(query: SQL): Promise<T[]> {
    return executeRows(this.db, query);
  }

  async createUser(input: { email: string; displayName: string; passwordHash?: string; scopes: PermissionScope[] }): Promise<StoredUser> {
    return this.db.transaction(async (tx) => {
      const [row] = await executeRows(tx, dbSql`
        INSERT INTO users (email, display_name)
        VALUES (${input.email.toLowerCase()}, ${input.displayName})
        RETURNING id, email, display_name, trusted_mode_enabled, created_at
      `);
      if (input.passwordHash) {
        await executeRows(tx, dbSql`INSERT INTO user_credentials (user_id, password_hash) VALUES (${row.id}, ${input.passwordHash})`);
      }
      await executeRows(tx, dbSql`
        INSERT INTO nutrition_targets (
          user_id, calories, protein_grams, carbs_grams, fat_grams, hydration_goal_glasses,
          calorie_target_configured, calorie_target_source
        )
        VALUES (${row.id}, 2200, 160, 240, 70, 12, false, 'default')
      `);
      return this.mapUser(row, input.passwordHash, input.scopes);
    });
  }

  async findUserByEmail(email: string): Promise<StoredUser | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT u.id, u.email, u.display_name, u.trusted_mode_enabled, u.created_at, c.password_hash
      FROM users u
      LEFT JOIN user_credentials c ON c.user_id = u.id
      WHERE lower(u.email) = lower(${email}) AND u.deleted_at IS NULL
    `);
    return row ? this.mapUser(row, row.password_hash as string | undefined, defaultUserScopes) : undefined;
  }

  async findUserById(id: string): Promise<StoredUser | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT u.id, u.email, u.display_name, u.trusted_mode_enabled, u.created_at, c.password_hash
      FROM users u
      LEFT JOIN user_credentials c ON c.user_id = u.id
      WHERE u.id = ${id} AND u.deleted_at IS NULL
    `);
    return row ? this.mapUser(row, row.password_hash as string | undefined, defaultUserScopes) : undefined;
  }

  async updateTrustedMode(userId: string, enabled: boolean): Promise<StoredUser> {
    await this.execute(dbSql`UPDATE users SET trusted_mode_enabled = ${enabled} WHERE id = ${userId}`);
    const user = await this.findUserById(userId);
    if (!user) throw new Error("user_not_found");
    return user;
  }

  async findAuthIdentity(provider: AuthIdentityProvider, providerUserId: string): Promise<AuthIdentityRecord | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT id, user_id, provider, provider_user_id, email, created_at, updated_at
      FROM auth_identities
      WHERE provider = ${provider} AND provider_user_id = ${providerUserId}
      LIMIT 1
    `);
    return row ? mapAuthIdentity(row) : undefined;
  }

  async linkAuthIdentity(input: { userId: string; provider: AuthIdentityProvider; providerUserId: string; email: string }): Promise<AuthIdentityRecord> {
    const [row] = await this.execute(dbSql`
      INSERT INTO auth_identities (user_id, provider, provider_user_id, email)
      VALUES (${input.userId}, ${input.provider}, ${input.providerUserId}, ${input.email.toLowerCase()})
      ON CONFLICT (provider, provider_user_id)
      DO UPDATE SET email = EXCLUDED.email, updated_at = now()
      RETURNING id, user_id, provider, provider_user_id, email, created_at, updated_at
    `);
    return mapAuthIdentity(row);
  }

  async createSession(input: Omit<StoredSession, "createdAt">): Promise<StoredSession> {
    const [row] = await this.execute(dbSql`
      INSERT INTO auth_sessions (id, user_id, refresh_token_hash, expires_at, revoked_at, rotated_at)
      VALUES (${input.id}, ${input.userId}, ${input.refreshTokenHash}, ${input.expiresAt}, ${input.revokedAt ?? null}, ${input.rotatedAt ?? null})
      RETURNING *
    `);
    return mapSession(row);
  }

  async findSessionByRefreshTokenHash(hash: string): Promise<StoredSession | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT * FROM auth_sessions
      WHERE refresh_token_hash = ${hash} AND revoked_at IS NULL AND expires_at > now()
      LIMIT 1
    `);
    return row ? mapSession(row) : undefined;
  }

  async revokeSession(sessionId: string): Promise<void> {
    await this.execute(dbSql`UPDATE auth_sessions SET revoked_at = now() WHERE id = ${sessionId}`);
  }

  async revokeAllSessions(userId: string): Promise<void> {
    await this.execute(dbSql`UPDATE auth_sessions SET revoked_at = now() WHERE user_id = ${userId} AND revoked_at IS NULL`);
  }

  async rotateSession(sessionId: string, nextHash: string, expiresAt: string): Promise<StoredSession> {
    const [row] = await this.execute(dbSql`
      UPDATE auth_sessions
      SET refresh_token_hash = ${nextHash}, expires_at = ${expiresAt}, rotated_at = now()
      WHERE id = ${sessionId}
      RETURNING *
    `);
    return mapSession(row);
  }

  async createPasswordReset(input: { userId: string; tokenHash: string; expiresAt: string }): Promise<void> {
    await this.execute(dbSql`
      INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
      VALUES (${input.userId}, ${input.tokenHash}, ${input.expiresAt})
    `);
  }

  async consumePasswordReset(tokenHash: string, newPasswordHash: string): Promise<boolean> {
    return this.db.transaction(async (tx) => {
      const [reset] = await executeRows(tx, dbSql`
        UPDATE password_reset_tokens
        SET used_at = now()
        WHERE token_hash = ${tokenHash} AND used_at IS NULL AND expires_at > now()
        RETURNING user_id
      `);
      if (!reset) return false;
      await executeRows(tx, dbSql`UPDATE user_credentials SET password_hash = ${newPasswordHash}, updated_at = now() WHERE user_id = ${reset.user_id}`);
      return true;
    });
  }

  async listFoods(userId: string): Promise<FoodItemRecord[]> {
    const rows = await this.execute(dbSql`SELECT * FROM food_items WHERE user_id IS NULL OR user_id = ${userId}`);
    return this.mapFoodsWithPortions(rows);
  }

  async searchFoods(userId: string, query: string, barcode?: string): Promise<FoodItemRecord[]> {
    const candidates = await this.searchFoodsHybrid(userId, { query, barcode });
    return candidates.map(stripFoodSearchCandidate);
  }

  async searchFoodsHybrid(userId: string, input: FoodHybridSearchInput): Promise<FoodSearchCandidate[]> {
    return withSpan(
      "PostgresRepository.searchFoodsHybrid",
      {
        query: input.query,
        hasBarcode: Boolean(input.barcode),
        hasEmbedding: Boolean(input.embedding),
        excludeBranded: Boolean(input.excludeBranded),
        limit: input.limit,
      },
      () => this.searchFoodsHybridInternal(userId, input),
    );
  }

  private async searchFoodsHybridInternal(userId: string, input: FoodHybridSearchInput): Promise<FoodSearchCandidate[]> {
    const limit = sanitizeLimit(input.limit);
    const normalized = normalizeText(input.query);
    const cacheKey = foodSearchCacheKey(userId, input, normalized, limit);
    const cached = this.getCachedFoodSearch(cacheKey);
    if (cached) return cached.map(cloneFoodSearchCandidate);

    const candidateRows = new Map<string, { row: Record<string, unknown>; lexicalScore: number; vectorScore?: number }>();
    const includeBranded = !input.excludeBranded;

    if (input.barcode) {
      const barcode = input.barcode;
      const rows = await withSpan(
        "PostgresRepository.searchFoodsHybrid.barcodeQuery",
        { limit },
        () => this.execute(dbSql`
        SELECT *, 1::float AS search_score
        FROM food_items
        WHERE (user_id IS NULL OR user_id = ${userId}) AND barcode = ${barcode}
        LIMIT ${limit}
      `),
      );
      for (const row of rows) {
        candidateRows.set(row.id as string, { row, lexicalScore: 1 });
      }
    } else if (normalized.length > 0) {
      const rows = await this.searchFoodDocuments(userId, input, normalized, limit, includeBranded);
      for (const row of rows) {
        candidateRows.set(row.id as string, { row, lexicalScore: clampScore(Number(row.search_score ?? 0)) });
      }
    }

    if (candidateRows.size === 0 && !input.barcode && input.embedding && input.embeddingModelId) {
      const vectorLiteral = toVectorLiteral(input.embedding);
      const embeddingModelId = input.embeddingModelId;
      const rows = await withSpan(
        "PostgresRepository.searchFoodsHybrid.vectorQuery",
        { limit: Math.max(limit, DEFAULT_FOOD_SEARCH_LIMIT), includeBranded },
        () => this.execute(dbSql`
        SELECT food_items.*,
               1 - (food_item_embeddings.embedding <=> ${vectorLiteral}::vector) AS vector_score
        FROM food_item_embeddings
        JOIN food_items ON food_items.id = food_item_embeddings.food_item_id
        WHERE food_item_embeddings.embedding_model_id = ${embeddingModelId}
          AND (food_items.user_id IS NULL OR food_items.user_id = ${userId})
          AND (${includeBranded} OR food_items.data_type IS DISTINCT FROM 'Branded')
        ORDER BY food_item_embeddings.embedding <=> ${vectorLiteral}::vector
        LIMIT ${Math.max(limit, DEFAULT_FOOD_SEARCH_LIMIT)}
      `),
      );
      for (const row of rows) {
        const foodId = row.id as string;
        const existing = candidateRows.get(foodId);
        const vectorScore = clampScore(Number(row.vector_score ?? 0));
        if (existing) {
          existing.vectorScore = Math.max(existing.vectorScore ?? 0, vectorScore);
        } else {
          candidateRows.set(foodId, { row, lexicalScore: 0, vectorScore });
        }
      }
    }

    const merged = [...candidateRows.values()];
    if (merged.length === 0) {
      this.setCachedFoodSearch(cacheKey, []);
      return [];
    }

    const foods = await withSpan(
      "PostgresRepository.mapFoodsWithPortions",
      { rowCount: merged.length },
      () => this.mapFoodsWithPortions(merged.map((candidate) => candidate.row)),
    );
    const scoresByFoodId = new Map(merged.map((candidate) => [candidate.row.id as string, candidate]));
    const preferenceScores = await withSpan(
      "PostgresRepository.getPreferenceScoreMap",
      { foodCount: foods.length },
      () => this.getPreferenceScoreMap(userId, foods.map((food) => food.id)),
    );

    const ranked = withSyncSpan(
      "PostgresRepository.rankFoodCandidates",
      { foodCount: foods.length, limit },
      () => foods.map((food) => {
        const scores = scoresByFoodId.get(food.id);
        const lexicalScore = clampScore(scores?.lexicalScore ?? 0);
        const vectorScore = scores?.vectorScore == null ? undefined : clampScore(scores.vectorScore);
        const preferenceScore = clamp((preferenceScores.get(food.id) ?? 0) / PREFERENCE_SCORE_NORMALIZER, -1, 1);
        const baseScore = vectorScore == null
          ? lexicalScore * LEXICAL_ONLY_SCORE_WEIGHT
          : lexicalScore * LEXICAL_SCORE_WEIGHT + vectorScore * VECTOR_SCORE_WEIGHT;
        return {
          ...food,
          lexicalScore,
          vectorScore,
          preferenceScore,
          finalScore: clampScore(baseScore + preferenceScore * PREFERENCE_SCORE_WEIGHT)
        };
      })
      .sort((a, b) => b.finalScore - a.finalScore || b.lexicalScore - a.lexicalScore || (b.vectorScore ?? 0) - (a.vectorScore ?? 0))
      .slice(0, limit),
    );
    this.setCachedFoodSearch(cacheKey, ranked);
    return ranked.map(cloneFoodSearchCandidate);
  }

  private async searchFoodDocuments(
    userId: string,
    input: FoodHybridSearchInput,
    normalized: string,
    limit: number,
    includeBranded: boolean,
  ): Promise<Record<string, unknown>[]> {
    const rows: Record<string, unknown>[] = [];
    const seen = new Set<string>();
    const profiles = foodSearchProfiles(input, includeBranded);
    for (const profile of profiles) {
      const profileRows = await withSpan(
        "PostgresRepository.searchFoodsHybrid.documentQuery",
        { limit: Math.max(limit * 4, DEFAULT_FOOD_SEARCH_LIMIT), scope: profile.scope, locales: profile.locales },
        () => this.queryFoodSearchDocuments(userId, normalized, profile, limit),
      );
      for (const row of profileRows) {
        const id = row.id as string;
        if (seen.has(id)) continue;
        seen.add(id);
        rows.push(row);
      }
      if (rows.length >= limit) break;
    }
    return rows;
  }

  private async queryFoodSearchDocuments(
    userId: string,
    normalized: string,
    profile: FoodSearchProfile,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const exactRows = await this.queryFoodSearchDocumentsExact(userId, normalized, profile, limit);
    if (exactRows.length >= limit) return exactRows;
    const seen = new Set(exactRows.map((row) => row.id as string));
    const fuzzyRows = await this.queryFoodSearchDocumentsFuzzy(userId, normalized, profile, limit);
    return [
      ...exactRows,
      ...fuzzyRows.filter((row) => !seen.has(row.id as string)),
    ];
  }

  private async queryFoodSearchDocumentsExact(
    userId: string,
    normalized: string,
    profile: FoodSearchProfile,
    limit: number,
  ): Promise<Record<string, unknown>[]> {
    const searchLimit = Math.max(limit * 4, DEFAULT_FOOD_SEARCH_LIMIT);
    const prefix = `${normalized}%`;
    const tokenContains = `% ${normalized}%`;
    const locale0 = profile.locales[0] ?? "any";
    const locale1 = profile.locales[1] ?? locale0;
    const locale2 = profile.locales[2] ?? locale1;
    const locale3 = profile.locales[3] ?? locale2;
    return this.execute(dbSql`
      SELECT food_items.*,
             GREATEST(
               CASE WHEN food_search_documents.search_text = ${normalized} THEN 1::float ELSE 0::float END,
               CASE WHEN food_search_documents.search_text LIKE ${prefix} THEN 0.92::float ELSE 0::float END,
               CASE WHEN food_search_documents.search_text LIKE ${tokenContains} THEN 0.84::float ELSE 0::float END
             ) AS search_score
      FROM food_search_documents
      JOIN food_items ON food_items.id = food_search_documents.food_item_id
      WHERE (food_search_documents.user_id IS NULL OR food_search_documents.user_id = ${userId})
        AND food_search_documents.scope = ${profile.scope}
        AND food_search_documents.locale IN ${sqlList(profile.locales)}
        AND (
          food_search_documents.search_text = ${normalized}
          OR food_search_documents.search_text LIKE ${prefix}
          OR food_search_documents.search_text LIKE ${tokenContains}
        )
      ORDER BY
        CASE WHEN food_search_documents.user_id = ${userId} THEN 0 ELSE 1 END,
        CASE
          WHEN food_search_documents.locale = ${locale0} THEN 0
          WHEN food_search_documents.locale = ${locale1} THEN 1
          WHEN food_search_documents.locale = ${locale2} THEN 2
          WHEN food_search_documents.locale = ${locale3} THEN 3
          ELSE 4
        END,
        food_search_documents.rank_bucket,
        search_score DESC,
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
             similarity(food_search_documents.search_text, ${normalized}) AS search_score
      FROM food_search_documents
      JOIN food_items ON food_items.id = food_search_documents.food_item_id
      WHERE (food_search_documents.user_id IS NULL OR food_search_documents.user_id = ${userId})
        AND food_search_documents.scope = ${profile.scope}
        AND food_search_documents.locale IN ${sqlList(profile.locales)}
        AND food_search_documents.search_text % ${normalized}
      ORDER BY
        CASE WHEN food_search_documents.user_id = ${userId} THEN 0 ELSE 1 END,
        CASE
          WHEN food_search_documents.locale = ${locale0} THEN 0
          WHEN food_search_documents.locale = ${locale1} THEN 1
          WHEN food_search_documents.locale = ${locale2} THEN 2
          WHEN food_search_documents.locale = ${locale3} THEN 3
          ELSE 4
        END,
        food_search_documents.rank_bucket,
        search_score DESC,
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

  async upsertFoodItem(input: Omit<FoodItemRecord, "id">): Promise<FoodItemRecord> {
    const normalizedName = normalizeText(input.normalizedName || input.name);
    const [existing] = input.externalSource && input.externalId
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
            fat_grams = ${input.fatGrams}
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

  private async upsertFoodSearchDocument(food: FoodItemRecord): Promise<void> {
    const document = foodSearchDocumentForFood(food);
    if (!document) return;
    await this.execute(dbSql`
      INSERT INTO food_search_documents (
        food_item_id, user_id, locale, scope, search_text, rank_bucket,
        source, external_source, data_type, food_key, updated_at
      )
      VALUES (
        ${food.id}, ${food.userId ?? null}, ${document.locale}, ${document.scope},
        ${document.searchText}, ${document.rankBucket}, ${food.source},
        ${food.externalSource ?? null}, ${food.dataType ?? null}, ${food.foodKey ?? null}, now()
      )
      ON CONFLICT (food_item_id) DO UPDATE SET
        user_id = EXCLUDED.user_id,
        locale = EXCLUDED.locale,
        scope = EXCLUDED.scope,
        search_text = EXCLUDED.search_text,
        rank_bucket = EXCLUDED.rank_bucket,
        source = EXCLUDED.source,
        external_source = EXCLUDED.external_source,
        data_type = EXCLUDED.data_type,
        food_key = EXCLUDED.food_key,
        updated_at = now()
    `);
  }

  async recordFoodFeedback(input: FoodFeedbackRecord): Promise<UserFoodPreference | undefined> {
    const normalizedQuery = normalizeText(input.query);
    const delta = foodFeedbackDelta(input.action);
    const positiveDelta = delta > 0 ? 1 : 0;
    const negativeDelta = delta < 0 ? 1 : 0;

    const [preference] = await this.db.transaction(async (tx) => {
      const foodItemId = input.foodItemId ?? (input.externalSource && input.externalId
        ? (await executeRows(tx, dbSql`
            SELECT id
            FROM food_items
            WHERE external_source = ${input.externalSource}
              AND external_id = ${input.externalId}
              AND (user_id IS NULL OR user_id = ${input.userId})
            ORDER BY CASE WHEN user_id = ${input.userId} THEN 0 ELSE 1 END
            LIMIT 1
          `))[0]?.id as string | undefined
        : undefined);
      if (!foodItemId) return [];

      await executeRows(tx, dbSql`
        INSERT INTO user_food_feedback_events (user_id, food_item_id, query_text, normalized_query, action, metadata_json)
        VALUES (
          ${input.userId},
          ${foodItemId},
          ${input.query},
          ${normalizedQuery},
          ${input.action},
          ${jsonb(input.metadata ?? {})}
        )
      `);
      return executeRows(tx, dbSql`
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
      `);
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

  async getActiveEmbeddingModel(): Promise<EmbeddingModelRecord | undefined> {
    const [row] = await this.execute(dbSql`
      SELECT *
      FROM embedding_models
      WHERE provider = ${ACTIVE_EMBEDDING_MODEL.provider}
        AND model = ${ACTIVE_EMBEDDING_MODEL.model}
        AND dimensions = ${ACTIVE_EMBEDDING_MODEL.dimensions}
      ORDER BY created_at DESC
      LIMIT 1
    `);
    return row ? mapEmbeddingModel(row) : undefined;
  }

  async upsertFoodItemEmbedding(input: UpsertFoodItemEmbeddingInput): Promise<FoodItemEmbeddingRecord> {
    const embedding = toVectorLiteral(input.embedding);
    const [row] = await this.execute(dbSql`
      INSERT INTO food_item_embeddings (
        food_item_id, embedding_model_id, embedded_text, embedded_text_hash, embedding, updated_at
      )
      VALUES (
        ${input.foodItemId},
        ${input.embeddingModelId},
        ${input.embeddedText},
        ${input.embeddedTextHash},
        ${embedding}::vector,
        now()
      )
      ON CONFLICT (food_item_id, embedding_model_id)
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
    const [row] = await this.execute(dbSql`SELECT * FROM nutrition_targets WHERE user_id = ${userId}`);
    return row ? mapNutrition(row) : { calories: 2200, proteinGrams: 160, carbsGrams: 240, fatGrams: 70 };
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
        user_id, target_date, calories, protein_grams, carbs_grams, fat_grams, hydration_goal_glasses,
        calorie_target_configured, calorie_target_source, calorie_target_configured_at,
        macro_mode, macro_source, macro_preset, protein_pct, carbs_pct, fat_pct, macro_calories, calorie_delta_kcal
      )
      VALUES (
        ${userId}, ${date}, ${current.target.calories}, ${current.target.proteinGrams}, ${current.target.carbsGrams}, ${current.target.fatGrams}, ${current.hydrationGoalGlasses},
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

  async updateDailyGoals(userId: string, input: UpdateDailyGoalsInput): Promise<DailyGoals> {
    return this.db.transaction(async (tx) => {
      const current = await this.getCurrentGoals(userId, tx);
      for (const snapshotDate of previousDatesInWeek(input.date)) {
        await executeRows(tx, dbSql`
          INSERT INTO daily_goal_snapshots (
            user_id, target_date, calories, protein_grams, carbs_grams, fat_grams, hydration_goal_glasses,
            calorie_target_configured, calorie_target_source, calorie_target_configured_at,
            macro_mode, macro_source, macro_preset, protein_pct, carbs_pct, fat_pct, macro_calories, calorie_delta_kcal
          )
          VALUES (
            ${userId}, ${snapshotDate}, ${current.target.calories}, ${current.target.proteinGrams}, ${current.target.carbsGrams}, ${current.target.fatGrams}, ${current.hydrationGoalGlasses},
            ${current.calorieTargetConfigured}, ${current.calorieTargetSource}, ${current.calorieTargetConfiguredAt ?? null},
            ${current.macroMode ?? null}, ${current.macroSource ?? null}, ${current.macroPreset ?? null},
            ${current.proteinPct ?? null}, ${current.carbsPct ?? null}, ${current.fatPct ?? null},
            ${current.macroCalories ?? null}, ${current.calorieDeltaKcal ?? null}
          )
          ON CONFLICT (user_id, target_date) DO NOTHING
        `);
      }

      const { target: nextTarget, metadata: nextMacroMetadata } = applyMacroGoalUpdate(
        current.target,
        current,
        input,
        input.calories ?? current.target.calories
      );
      const nextHydration = input.hydrationGoalGlasses ?? current.hydrationGoalGlasses;
      const calorieTargetWasUpdated = input.calories !== undefined;
      const nextConfigured = calorieTargetWasUpdated ? true : current.calorieTargetConfigured;
      const nextSource = calorieTargetWasUpdated ? input.calorieTargetSource ?? "manual" : current.calorieTargetSource;
      const nextConfiguredAt = calorieTargetWasUpdated ? new Date().toISOString() : current.calorieTargetConfiguredAt;
      await executeRows(tx, dbSql`
        INSERT INTO nutrition_targets (
          user_id, calories, protein_grams, carbs_grams, fat_grams, hydration_goal_glasses,
          calorie_target_configured, calorie_target_source, calorie_target_configured_at,
          macro_mode, macro_source, macro_preset, protein_pct, carbs_pct, fat_pct, macro_calories, calorie_delta_kcal,
          updated_at
        )
        VALUES (
          ${userId}, ${nextTarget.calories}, ${nextTarget.proteinGrams}, ${nextTarget.carbsGrams}, ${nextTarget.fatGrams}, ${nextHydration},
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
      `);
      const [row] = await executeRows(tx, dbSql`
        INSERT INTO daily_goal_snapshots (
          user_id, target_date, calories, protein_grams, carbs_grams, fat_grams, hydration_goal_glasses,
          calorie_target_configured, calorie_target_source, calorie_target_configured_at,
          macro_mode, macro_source, macro_preset, protein_pct, carbs_pct, fat_pct, macro_calories, calorie_delta_kcal,
          updated_at
        )
        VALUES (
          ${userId}, ${input.date}, ${nextTarget.calories}, ${nextTarget.proteinGrams}, ${nextTarget.carbsGrams}, ${nextTarget.fatGrams}, ${nextHydration},
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
      `);
      return mapDailyGoals(row);
    });
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
    const [row] = await this.execute(dbSql`SELECT * FROM meals WHERE id = ${mealId} AND user_id = ${userId} AND deleted_at IS NULL`);
    return row ? this.mapMeal(row) : undefined;
  }

  async createProposal(userId: string, proposal: Omit<MealProposal, "id" | "createdAt">): Promise<MealProposal> {
    return withSpan(
      "PostgresRepository.createProposal",
      { itemCount: proposal.items.length },
      () => this.db.transaction(async (tx) => {
        const id = newId();
        const [row] = await withSpan(
          "PostgresRepository.createProposal.insertProposal",
          undefined,
          () => executeRows(tx, dbSql`
          INSERT INTO meal_proposals (id, user_id, phrase, title, status, confidence, requires_confirmation, trusted_auto_commit_eligible, source, calories, protein_grams, carbs_grams, fat_grams)
          VALUES (${id}, ${userId}, ${proposal.phrase}, ${proposal.title}, ${proposal.status}, ${proposal.confidence}, ${proposal.requiresConfirmation}, ${proposal.trustedAutoCommitEligible}, ${proposal.source}, ${proposal.nutrition.calories}, ${proposal.nutrition.proteinGrams}, ${proposal.nutrition.carbsGrams}, ${proposal.nutrition.fatGrams})
          RETURNING *
        `),
        );
        await withSpan(
          "PostgresRepository.createProposal.insertItems",
          { itemCount: proposal.items.length },
          () => Promise.all(proposal.items.map((item) => insertProposalItem(tx, id, item))),
        );
        return this.mapProposal(row, proposal.title, tx);
      }),
    );
  }

  async getProposal(userId: string, proposalId: string): Promise<MealProposal | undefined> {
    const [row] = await this.execute(dbSql`SELECT * FROM meal_proposals WHERE id = ${proposalId} AND user_id = ${userId}`);
    return row ? this.mapProposal(row) : undefined;
  }

  async updateProposal(userId: string, proposal: MealProposal): Promise<MealProposal> {
    await this.db.transaction(async (tx) => {
      await executeRows(tx, dbSql`
        UPDATE meal_proposals
        SET status = ${proposal.status}, calories = ${proposal.nutrition.calories}, protein_grams = ${proposal.nutrition.proteinGrams}, carbs_grams = ${proposal.nutrition.carbsGrams}, fat_grams = ${proposal.nutrition.fatGrams}
        WHERE id = ${proposal.id} AND user_id = ${userId}
      `);
      await executeRows(tx, dbSql`DELETE FROM meal_proposal_items WHERE proposal_id = ${proposal.id}`);
      for (const item of proposal.items) await insertProposalItem(tx, proposal.id, item);
    });
    return proposal;
  }

  async createMealFromProposal(userId: string, proposal: MealProposal, occurredAt: string, items = proposal.items, mealLabel?: MealLabel | null): Promise<Meal> {
    return this.db.transaction(async (tx) => {
      const id = newId();
      const nutrition = sumNutrition(items);
      const [row] = await executeRows(tx, dbSql`
        INSERT INTO meals (id, user_id, proposal_id, title, occurred_at, meal_type, meal_type_label, calories, protein_grams, carbs_grams, fat_grams)
        VALUES (${id}, ${userId}, ${proposal.id}, ${proposal.title}, ${occurredAt}, ${mealLabel?.type ?? null}, ${mealLabel?.label ?? null}, ${nutrition.calories}, ${nutrition.proteinGrams}, ${nutrition.carbsGrams}, ${nutrition.fatGrams})
        RETURNING *
      `);
      for (const item of items) await insertMealItem(tx, id, item);
      await executeRows(tx, dbSql`UPDATE meal_proposals SET status = 'committed' WHERE id = ${proposal.id}`);
      return this.mapMeal(row, tx);
    });
  }

  async updateMeal(userId: string, meal: Meal): Promise<Meal> {
    await this.db.transaction(async (tx) => {
      await executeRows(tx, dbSql`
        UPDATE meals
        SET calories = ${meal.nutrition.calories}, protein_grams = ${meal.nutrition.proteinGrams}, carbs_grams = ${meal.nutrition.carbsGrams}, fat_grams = ${meal.nutrition.fatGrams}
        WHERE id = ${meal.id} AND user_id = ${userId}
      `);
      await executeRows(tx, dbSql`DELETE FROM meal_items WHERE meal_id = ${meal.id}`);
      for (const item of meal.items) await insertMealItem(tx, meal.id, item);
    });
    return meal;
  }

  async softDeleteMeal(userId: string, mealId: string): Promise<boolean> {
    const rows = await this.execute(dbSql`UPDATE meals SET deleted_at = now() WHERE id = ${mealId} AND user_id = ${userId} AND deleted_at IS NULL RETURNING id`);
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
    const consumed = meals.reduce((total, meal) => ({
      calories: total.calories + meal.nutrition.calories,
      proteinGrams: total.proteinGrams + meal.nutrition.proteinGrams,
      carbsGrams: total.carbsGrams + meal.nutrition.carbsGrams,
      fatGrams: total.fatGrams + meal.nutrition.fatGrams
    }), { calories: 0, proteinGrams: 0, carbsGrams: 0, fatGrams: 0 });
    const goals = await this.getDailyGoals(userId, date);
    return {
      date,
      consumed,
      target: goals.target,
      remaining: subtractNutrition(goals.target, consumed),
      hydrationGoalGlasses: goals.hydrationGoalGlasses,
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
      meals
    };
  }

  async listTemplates(userId: string): Promise<MealTemplate[]> {
    const rows = await this.execute(dbSql`SELECT * FROM meal_templates WHERE user_id = ${userId} AND deleted_at IS NULL`);
    return this.mapTemplates(rows);
  }

  async createTemplate(userId: string, input: Omit<MealTemplate, "id">): Promise<MealTemplate> {
    return this.db.transaction(async (tx) => {
      const id = newId();
      const [row] = await executeRows(tx, dbSql`
        INSERT INTO meal_templates (id, user_id, title, normalized_title, trusted_auto_commit_enabled, calories, protein_grams, carbs_grams, fat_grams)
        VALUES (${id}, ${userId}, ${input.title}, ${normalizeText(input.title)}, ${input.trustedAutoCommitEnabled}, ${input.nutrition.calories}, ${input.nutrition.proteinGrams}, ${input.nutrition.carbsGrams}, ${input.nutrition.fatGrams})
        RETURNING *
      `);
      for (const item of input.items) await insertTemplateItem(tx, id, item);
      for (const alias of input.aliases) {
        await executeRows(tx, dbSql`
          INSERT INTO food_memories (user_id, normalized_text, label, meal_template_id, confidence)
          VALUES (${userId}, ${normalizeText(alias)}, ${alias}, ${id}, 1)
          ON CONFLICT DO NOTHING
        `);
      }
      return this.mapTemplate(row, tx);
    });
  }

  async updateTemplate(userId: string, template: MealTemplate): Promise<MealTemplate> {
    await this.db.transaction(async (tx) => {
      await executeRows(tx, dbSql`
        UPDATE meal_templates
        SET title = ${template.title}, normalized_title = ${normalizeText(template.title)}, trusted_auto_commit_enabled = ${template.trustedAutoCommitEnabled}, calories = ${template.nutrition.calories}, protein_grams = ${template.nutrition.proteinGrams}, carbs_grams = ${template.nutrition.carbsGrams}, fat_grams = ${template.nutrition.fatGrams}
        WHERE id = ${template.id} AND user_id = ${userId}
      `);
      await executeRows(tx, dbSql`DELETE FROM meal_template_items WHERE template_id = ${template.id}`);
      for (const item of template.items) await insertTemplateItem(tx, template.id, item);
    });
    return template;
  }

  async deleteTemplate(userId: string, templateId: string): Promise<boolean> {
    const rows = await this.execute(dbSql`UPDATE meal_templates SET deleted_at = now() WHERE id = ${templateId} AND user_id = ${userId} RETURNING id`);
    return rows.length > 0;
  }

  async queryMemory(userId: string, normalizedText: string): Promise<MemoryMatch[]> {
    const rows = await this.execute(dbSql`
      SELECT * FROM food_memories
      WHERE user_id = ${userId}
        AND (${normalizedText} = normalized_text OR ${normalizedText} LIKE '%' || normalized_text || '%' OR normalized_text LIKE '%' || ${normalizedText} || '%')
      ORDER BY CASE WHEN ${normalizedText} = normalized_text THEN 0 ELSE 1 END, usage_count DESC
      LIMIT 5
    `);
    return Promise.all(rows.map(async (row) => ({
      id: row.id as string,
      userId,
      label: row.label as string,
      normalizedText: row.normalized_text as string,
      confidence: normalizedText === row.normalized_text || normalizedText.includes(row.normalized_text as string) ? Number(row.confidence) : Math.min(Number(row.confidence), 0.82),
      template: row.meal_template_id ? await this.getTemplateById(userId, row.meal_template_id as string) : null
    })));
  }

  async createMemory(input: { userId: string; normalizedText: string; label: string; templateId?: string; confidence: number }): Promise<void> {
    await this.execute(dbSql`
      INSERT INTO food_memories (user_id, normalized_text, label, meal_template_id, confidence)
      VALUES (${input.userId}, ${input.normalizedText}, ${input.label}, ${input.templateId ?? null}, ${input.confidence})
      ON CONFLICT DO NOTHING
    `);
  }

  async recordActionCall(input: Omit<ActionCallRecord, "id" | "createdAt">): Promise<ActionCallRecord> {
    const [row] = await withSpan(
      "PostgresRepository.recordActionCall",
      { actionId: input.actionId, status: input.confirmationStatus },
      () => this.execute(dbSql`
      INSERT INTO action_calls (user_id, action_id, source, input_json, output_json, error_json, confirmation_status, trace_id, latency_ms)
      VALUES (${input.userId}, ${input.actionId}, ${input.source}, ${jsonb(input.input)}, ${jsonb(input.output ?? null)}, ${jsonb(input.error ?? null)}, ${input.confirmationStatus}, ${input.traceId}, ${input.latencyMs})
      RETURNING *
    `),
    );
    return mapActionCall(row);
  }

  async recordAuditEvent(input: Omit<AuditEventRecord, "id" | "createdAt">): Promise<AuditEventRecord> {
    const [row] = await withSpan(
      "PostgresRepository.recordAuditEvent",
      { eventType: input.eventType },
      () => this.execute(dbSql`
      INSERT INTO audit_events (user_id, event_type, metadata_json, trace_id)
      VALUES (${input.userId ?? null}, ${input.eventType}, ${jsonb(input.metadata)}, ${input.traceId})
      RETURNING *
    `),
    );
    return mapAuditEvent(row);
  }

  async listActionCalls(userId: string): Promise<ActionCallRecord[]> {
    const rows = await this.execute(dbSql`SELECT * FROM action_calls WHERE user_id = ${userId} ORDER BY created_at`);
    return rows.map(mapActionCall);
  }

  async listAuditEvents(userId: string): Promise<AuditEventRecord[]> {
    const rows = await this.execute(dbSql`SELECT * FROM audit_events WHERE user_id = ${userId} ORDER BY created_at`);
    return rows.map(mapAuditEvent);
  }

  private async mapMeals(rows: Record<string, unknown>[], dbClient: DbExecutor = this.db): Promise<Meal[]> {
    if (rows.length === 0) return [];
    const items = await executeRows(dbClient, dbSql`
      SELECT *
      FROM meal_items
      WHERE meal_id IN ${sqlList(rows.map((row) => row.id as string))}
      ORDER BY meal_id, id
    `);
    const itemsByMealId = groupRowsByString(items, "meal_id");
    return rows.map((row) => this.mapMealRow(row, itemsByMealId.get(row.id as string) ?? []));
  }

  private async mapMeal(row: Record<string, unknown>, dbClient: DbExecutor = this.db): Promise<Meal> {
    const [meal] = await this.mapMeals([row], dbClient);
    return meal;
  }

  private mapMealRow(row: Record<string, unknown>, items: Record<string, unknown>[]): Meal {
    return {
      id: row.id as string,
      title: row.title as string,
      occurredAt: toIso(row.occurred_at),
      mealLabel: mapMealLabel(row),
      nutrition: mapNutrition(row),
      items: items.map(mapItem),
      createdAt: toIso(row.created_at),
      deletedAt: row.deleted_at ? toIso(row.deleted_at) : undefined
    };
  }

  private async mapProposal(row: Record<string, unknown>, fallbackTitle = "Meal", dbClient: DbExecutor = this.db): Promise<MealProposal> {
    const items = await executeRows(dbClient, dbSql`SELECT * FROM meal_proposal_items WHERE proposal_id = ${row.id as string}`);
    return {
      id: row.id as string,
      phrase: row.phrase as string,
      title: row.title as string || fallbackTitle,
      status: row.status as MealProposal["status"],
      confidence: Number(row.confidence),
      requiresConfirmation: Boolean(row.requires_confirmation),
      trustedAutoCommitEligible: Boolean(row.trusted_auto_commit_eligible),
      source: row.source as string,
      nutrition: mapNutrition(row),
      items: items.map(mapItem),
      createdAt: toIso(row.created_at)
    };
  }

  private async mapTemplates(rows: Record<string, unknown>[], dbClient: DbExecutor = this.db): Promise<MealTemplate[]> {
    if (rows.length === 0) return [];
    const templateIds = rows.map((row) => row.id as string);
    const items = await executeRows(dbClient, dbSql`
      SELECT *
      FROM meal_template_items
      WHERE template_id IN ${sqlList(templateIds)}
      ORDER BY template_id, id
    `);
    const aliases = await executeRows(dbClient, dbSql`
      SELECT meal_template_id, label
      FROM food_memories
      WHERE meal_template_id IN ${sqlList(templateIds)}
      ORDER BY meal_template_id, label
    `);
    const itemsByTemplateId = groupRowsByString(items, "template_id");
    const aliasesByTemplateId = groupRowsByString(aliases, "meal_template_id");
    return rows.map((row) => this.mapTemplateRow(
      row,
      itemsByTemplateId.get(row.id as string) ?? [],
      aliasesByTemplateId.get(row.id as string) ?? [],
    ));
  }

  private async mapTemplate(row: Record<string, unknown>, dbClient: DbExecutor = this.db): Promise<MealTemplate> {
    const [template] = await this.mapTemplates([row], dbClient);
    return template;
  }

  private mapTemplateRow(row: Record<string, unknown>, items: Record<string, unknown>[], aliases: Record<string, unknown>[]): MealTemplate {
    return {
      id: row.id as string,
      title: row.title as string,
      trustedAutoCommitEnabled: Boolean(row.trusted_auto_commit_enabled),
      nutrition: mapNutrition(row),
      items: items.map(mapItem),
      aliases: aliases.map((alias) => alias.label as string)
    };
  }

  private async getTemplateById(userId: string, templateId: string): Promise<MealTemplate | null> {
    const [row] = await this.execute(dbSql`SELECT * FROM meal_templates WHERE id = ${templateId} AND user_id = ${userId} AND deleted_at IS NULL`);
    return row ? this.mapTemplate(row) : null;
  }

  private async getCurrentGoals(userId: string, dbClient: DbExecutor = this.db): Promise<Omit<DailyGoals, "date"> & { calorieTargetConfiguredAt?: string }> {
    const [row] = await executeRows(dbClient, dbSql`SELECT * FROM nutrition_targets WHERE user_id = ${userId}`);
    if (!row) {
      return {
        target: { calories: 2200, proteinGrams: 160, carbsGrams: 240, fatGrams: 70 },
        hydrationGoalGlasses: 12,
        calorieTargetConfigured: false,
        calorieTargetSource: "default",
        calorieTargetConfiguredAt: undefined
      };
    }
    return {
      target: mapNutrition(row),
      hydrationGoalGlasses: Number(row.hydration_goal_glasses ?? 12),
      calorieTargetConfigured: Boolean(row.calorie_target_configured),
      calorieTargetSource: parseCalorieTargetSource(row.calorie_target_source),
      calorieTargetConfiguredAt: row.calorie_target_configured_at ? toIso(row.calorie_target_configured_at) : undefined,
      ...mapMacroMetadata(row)
    };
  }

  private async mapFoodsWithPortions(rows: Record<string, unknown>[]): Promise<FoodItemRecord[]> {
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
    return foods.map((food) => ({ ...food, portions: byFoodId.get(food.id) ?? [] }));
  }

  private async getPreferenceScoreMap(userId: string, foodIds: string[]): Promise<Map<string, number>> {
    if (foodIds.length === 0) return new Map();
    const rows = await this.execute(dbSql`
      SELECT food_item_id, affinity_score
      FROM user_food_preferences
      WHERE user_id = ${userId}
        AND food_item_id IN ${sqlList(foodIds)}
    `);
    return new Map(rows.map((row) => [row.food_item_id as string, Number(row.affinity_score)]));
  }

  private mapUser(row: Record<string, unknown>, passwordHash: string | undefined, scopes: PermissionScope[]): StoredUser {
    return {
      id: row.id as string,
      email: row.email as string,
      displayName: row.display_name as string,
      trustedModeEnabled: Boolean(row.trusted_mode_enabled),
      createdAt: toIso(row.created_at),
      ...(passwordHash ? { passwordHash } : {}),
      scopes
    };
  }
}

function mapAuthIdentity(row: Record<string, unknown>): AuthIdentityRecord {
  return {
    id: row.id as string,
    userId: row.user_id as string,
    provider: row.provider as AuthIdentityProvider,
    providerUserId: row.provider_user_id as string,
    email: row.email as string,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at)
  };
}

async function insertProposalItem(dbClient: DbExecutor, proposalId: string, item: MealItem) {
  await executeRows(dbClient, dbSql`
    INSERT INTO meal_proposal_items (
      proposal_id, name, quantity, unit, calories, protein_grams, carbs_grams, fat_grams,
      source, original_text, canonical_name, external_source, external_id, source_url, license, confidence, needs_review
    )
    VALUES (
      ${proposalId}, ${item.name}, ${item.quantity}, ${item.unit}, ${item.calories}, ${item.proteinGrams}, ${item.carbsGrams}, ${item.fatGrams},
      ${item.source}, ${item.originalText ?? null}, ${item.canonicalName ?? null}, ${item.externalSource ?? null}, ${item.externalId ?? null},
      ${item.sourceUrl ?? null}, ${item.license ?? null}, ${item.confidence ?? null}, ${item.needsReview ?? false}
    )
  `);
}

async function insertMealItem(dbClient: DbExecutor, mealId: string, item: MealItem) {
  await executeRows(dbClient, dbSql`
    INSERT INTO meal_items (
      meal_id, name, quantity, unit, calories, protein_grams, carbs_grams, fat_grams,
      source, original_text, canonical_name, external_source, external_id, source_url, license, confidence, needs_review
    )
    VALUES (
      ${mealId}, ${item.name}, ${item.quantity}, ${item.unit}, ${item.calories}, ${item.proteinGrams}, ${item.carbsGrams}, ${item.fatGrams},
      ${item.source}, ${item.originalText ?? null}, ${item.canonicalName ?? null}, ${item.externalSource ?? null}, ${item.externalId ?? null},
      ${item.sourceUrl ?? null}, ${item.license ?? null}, ${item.confidence ?? null}, ${item.needsReview ?? false}
    )
  `);
}

async function insertTemplateItem(dbClient: DbExecutor, templateId: string, item: MealItem) {
  await executeRows(dbClient, dbSql`
    INSERT INTO meal_template_items (
      template_id, name, quantity, unit, calories, protein_grams, carbs_grams, fat_grams,
      source, original_text, canonical_name, external_source, external_id, source_url, license, confidence, needs_review
    )
    VALUES (
      ${templateId}, ${item.name}, ${item.quantity}, ${item.unit}, ${item.calories}, ${item.proteinGrams}, ${item.carbsGrams}, ${item.fatGrams},
      ${item.source}, ${item.originalText ?? null}, ${item.canonicalName ?? null}, ${item.externalSource ?? null}, ${item.externalId ?? null},
      ${item.sourceUrl ?? null}, ${item.license ?? null}, ${item.confidence ?? null}, ${item.needsReview ?? false}
    )
  `);
}

function mapFood(row: Record<string, unknown>): FoodItemRecord {
  return {
    id: row.id as string,
    userId: optionalString(row.user_id),
    name: row.name as string,
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
    publicationDate: row.publication_date ? toDateOnly(row.publication_date) : undefined,
    ndbNumber: optionalString(row.ndb_number),
    foodKey: optionalString(row.food_key),
    ingredients: optionalString(row.ingredients),
    marketCountry: optionalString(row.market_country),
    householdServingFulltext: optionalString(row.household_serving_fulltext),
    nutrients: isRecord(row.nutrients_json) ? row.nutrients_json : undefined,
    portions: [],
    servingGrams: Number(row.serving_grams),
    calories: Number(row.calories),
    proteinGrams: Number(row.protein_grams),
    carbsGrams: Number(row.carbs_grams),
    fatGrams: Number(row.fat_grams)
  };
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
    normalizedAliases: Array.isArray(row.normalized_aliases) ? row.normalized_aliases.map(String) : [],
    kind: (row.kind as string | undefined) ?? "serving",
    sourceDescription: row.source_description as string
  };
}

function mapEmbeddingModel(row: Record<string, unknown>): EmbeddingModelRecord {
  return {
    id: row.id as string,
    provider: row.provider as string,
    model: row.model as string,
    dimensions: Number(row.dimensions)
  };
}

function mapFoodItemEmbedding(row: Record<string, unknown>): FoodItemEmbeddingRecord {
  return {
    id: row.id as string,
    foodItemId: row.food_item_id as string,
    embeddingModelId: row.embedding_model_id as string,
    embeddedText: row.embedded_text as string,
    embeddedTextHash: row.embedded_text_hash as string,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at)
  };
}

function mapUserFoodPreference(row: Record<string, unknown>): UserFoodPreference {
  return {
    userId: row.user_id as string,
    foodItemId: row.food_item_id as string,
    affinityScore: Number(row.affinity_score),
    positiveFeedbackCount: Number(row.positive_feedback_count),
    negativeFeedbackCount: Number(row.negative_feedback_count),
    lastFeedbackAt: toIso(row.last_feedback_at),
    updatedAt: toIso(row.updated_at)
  };
}

function mapNutrition(row: Record<string, unknown>): NutritionSnapshot {
  return {
    calories: Number(row.calories),
    proteinGrams: Number(row.protein_grams),
    carbsGrams: Number(row.carbs_grams),
    fatGrams: Number(row.fat_grams)
  };
}

function mapDailyGoals(row: Record<string, unknown>): DailyGoals {
  return {
    date: toDateOnly(row.target_date),
    target: mapNutrition(row),
    hydrationGoalGlasses: Number(row.hydration_goal_glasses ?? 12),
    calorieTargetConfigured: Boolean(row.calorie_target_configured),
    calorieTargetSource: parseCalorieTargetSource(row.calorie_target_source),
    ...mapMacroMetadata(row)
  };
}

function parseCalorieTargetSource(value: unknown): CalorieTargetSource {
  return value === "manual" || value === "calculator" || value === "default" ? value : "default";
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
    calorieDeltaKcal: optionalNumber(row.calorie_delta_kcal)
  };
}

function parseMacroMode(value: unknown): MacroGoalMetadata["macroMode"] {
  return value === "percentage" || value === "grams" ? value : undefined;
}

function parseMacroSource(value: unknown): MacroGoalMetadata["macroSource"] {
  return value === "preset" || value === "custom" ? value : undefined;
}

function parseMacroPreset(value: unknown): MacroGoalMetadata["macroPreset"] {
  return value === "balanced" || value === "high_protein" || value === "lower_carb" ? value : undefined;
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
    externalSource: row.external_source as string | undefined,
    externalId: row.external_id as string | undefined,
    sourceUrl: row.source_url as string | undefined,
    license: row.license as string | undefined,
    confidence: row.confidence == null ? undefined : Number(row.confidence),
    needsReview: row.needs_review == null ? undefined : Boolean(row.needs_review)
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
    rotatedAt: row.rotated_at ? toIso(row.rotated_at) : undefined
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
    createdAt: toIso(row.created_at)
  };
}

function mapAuditEvent(row: Record<string, unknown>): AuditEventRecord {
  return {
    id: row.id as string,
    userId: row.user_id as string | undefined,
    eventType: row.event_type as string,
    metadata: row.metadata_json,
    traceId: row.trace_id as string,
    createdAt: toIso(row.created_at)
  };
}

function toIso(value: unknown): string {
  return value instanceof Date ? value.toISOString() : new Date(value as string).toISOString();
}

function toDateOnly(value: unknown): string {
  return value instanceof Date ? value.toISOString().slice(0, 10) : String(value).slice(0, 10);
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function optionalNumber(value: unknown): number | undefined {
  return value == null ? undefined : Number(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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

function stripFoodSearchCandidate(candidate: FoodSearchCandidate): FoodItemRecord {
  const {
    lexicalScore: _lexicalScore,
    vectorScore: _vectorScore,
    preferenceScore: _preferenceScore,
    finalScore: _finalScore,
    ...food
  } = candidate;
  return food;
}

function cloneFoodSearchCandidate(candidate: FoodSearchCandidate): FoodSearchCandidate {
  return {
    ...candidate,
    portions: candidate.portions?.map((portion) => ({ ...portion })),
  };
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
    scope: input.scope,
    excludeBranded: input.excludeBranded,
    limit,
  });
}

function foodSearchProfiles(
  input: FoodHybridSearchInput,
  includeBranded: boolean,
): FoodSearchProfile[] {
  const locale = normalizeSearchLocale(input.locale);
  const scope = input.scope ?? (includeBranded ? "market" : "generic");
  if (scope === "market") {
    return [
      {
        scope: "market",
        locales: uniqueStrings([locale, "en", "es", "any"].filter(Boolean) as string[]),
      },
      {
        scope: "generic",
        locales: uniqueStrings([locale, "en", "es", "any"].filter(Boolean) as string[]),
      },
    ];
  }
  if (locale === "es") {
    return [
      { scope: "generic", locales: ["es", "any"] },
      { scope: "generic", locales: ["en"] },
    ];
  }
  if (locale === "en") {
    return [
      { scope: "generic", locales: ["en", "any"] },
      { scope: "generic", locales: ["es"] },
    ];
  }
  return [
    { scope: "generic", locales: ["en", "any"] },
    { scope: "generic", locales: ["es"] },
  ];
}

function foodSearchDocumentForFood(food: FoodItemRecord):
  | { locale: string; scope: "generic" | "market"; searchText: string; rankBucket: number }
  | undefined {
  const searchText = normalizeText(
    [
      food.normalizedName,
      food.canonicalName,
      food.name,
      food.brand,
      food.foodCategory,
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
    (food.source === "openfoodfacts" && food.foodKey === "es") ||
    (food.dataType !== "Branded" && food.source !== "usda_branded" && food.source !== "openfoodfacts")
      ? "generic"
      : "market";
  const rankBucket = food.userId
    ? 0
    : food.source === "openfoodfacts" && food.foodKey === "es"
      ? 1
      : food.dataType === "SR Legacy"
        ? 2
        : food.dataType === "Foundation"
          ? 3
          : food.dataType === "Survey (FNDDS)"
            ? 4
            : food.source === "openfoodfacts" && food.foodKey === "en"
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

async function executeRows<T extends Record<string, unknown> = Record<string, unknown>>(dbClient: DbExecutor, query: SQL): Promise<T[]> {
  return await dbClient.execute(query) as T[];
}

function sqlList(values: readonly string[]): SQL {
  if (values.length === 0) return dbSql`(NULL)`;
  return dbSql`(${dbSql.join(values.map((value) => dbSql`${value}`), dbSql`, `)})`;
}

function jsonb(value: unknown): SQL {
  return dbSql`${JSON.stringify(value)}::jsonb`;
}

function groupRowsByString(rows: Record<string, unknown>[], key: string): Map<string, Record<string, unknown>[]> {
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
  return Math.max(1, Math.min(MAX_FOOD_SEARCH_LIMIT, Math.floor(limit as number)));
}

function clampScore(score: number): number {
  return clamp(score, 0, 1);
}

function clamp(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.max(min, Math.min(max, value));
}

function toVectorLiteral(embedding: number[]): string {
  if (embedding.length !== ACTIVE_EMBEDDING_MODEL.dimensions) {
    throw new Error("invalid_embedding_dimensions");
  }
  return `[${embedding.map((value) => {
    if (!Number.isFinite(value)) throw new Error("invalid_embedding_value");
    return String(value);
  }).join(",")}]`;
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
