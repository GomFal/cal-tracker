import { relations, sql } from "drizzle-orm";
import { boolean, check, customType, date, index, integer, jsonb, numeric, pgTable, primaryKey, text, timestamp, uniqueIndex, uuid, vector } from "drizzle-orm/pg-core";

type JsonObject = Record<string, unknown>;

const tsvector = customType<{ data: string }>({
  dataType() {
    return "tsvector";
  }
});

const timestamps = {
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
};

export const schemaMigrations = pgTable("schema_migrations", {
  filename: text("filename").primaryKey().notNull(),
  appliedAt: timestamp("applied_at", { withTimezone: true }).notNull().defaultNow()
});

export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  email: text("email").notNull(),
  displayName: text("display_name").notNull(),
  trustedModeEnabled: boolean("trusted_mode_enabled").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  deletedAt: timestamp("deleted_at", { withTimezone: true })
}, (table) => [
  uniqueIndex("users_active_email_unique").on(sql`lower(${table.email})`).where(sql`${table.deletedAt} IS NULL`)
]);

export const userCredentials = pgTable("user_credentials", {
  userId: uuid("user_id").primaryKey().references(() => users.id, { onDelete: "cascade" }),
  passwordHash: text("password_hash").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
});

export const authIdentities = pgTable("auth_identities", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  provider: text("provider").notNull(),
  providerUserId: text("provider_user_id").notNull(),
  email: text("email").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  uniqueIndex("auth_identities_provider_user_unique").on(table.provider, table.providerUserId),
  index("auth_identities_user_idx").on(table.userId)
]);

export const authSessions = pgTable("auth_sessions", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  refreshTokenHash: text("refresh_token_hash").notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  rotatedAt: timestamp("rotated_at", { withTimezone: true })
}, (table) => [
  index("auth_sessions_active_idx").on(table.userId, table.expiresAt).where(sql`${table.revokedAt} IS NULL`)
]);

export const passwordResetTokens = pgTable("password_reset_tokens", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  tokenHash: text("token_hash").notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  usedAt: timestamp("used_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
});

export const nutritionTargets = pgTable("nutrition_targets", {
  userId: uuid("user_id").primaryKey().references(() => users.id, { onDelete: "cascade" }),
  calories: integer("calories").notNull(),
  proteinGrams: numeric("protein_grams", { precision: 10, scale: 2 }).notNull(),
  carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
  fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
  hydrationGoalGlasses: integer("hydration_goal_glasses").notNull().default(0),
  hydrationGoalLiters: numeric("hydration_goal_liters", { precision: 5, scale: 2 }).notNull().default("0"),
  calorieTargetConfigured: boolean("calorie_target_configured").notNull().default(false),
  calorieTargetSource: text("calorie_target_source").notNull().default("default"),
  calorieTargetConfiguredAt: timestamp("calorie_target_configured_at", { withTimezone: true }),
  macroMode: text("macro_mode"),
  macroSource: text("macro_source"),
  macroPreset: text("macro_preset"),
  proteinPct: integer("protein_pct"),
  carbsPct: integer("carbs_pct"),
  fatPct: integer("fat_pct"),
  macroCalories: integer("macro_calories"),
  calorieDeltaKcal: integer("calorie_delta_kcal"),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
});

export const dailyGoalSnapshots = pgTable("daily_goal_snapshots", {
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  targetDate: date("target_date").notNull(),
  calories: integer("calories").notNull(),
  proteinGrams: numeric("protein_grams", { precision: 10, scale: 2 }).notNull(),
  carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
  fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
  hydrationGoalGlasses: integer("hydration_goal_glasses").notNull().default(0),
  hydrationGoalLiters: numeric("hydration_goal_liters", { precision: 5, scale: 2 }).notNull().default("0"),
  waterConsumedLiters: numeric("water_consumed_liters", { precision: 5, scale: 2 }).notNull().default("0"),
  calorieTargetConfigured: boolean("calorie_target_configured").notNull().default(false),
  calorieTargetSource: text("calorie_target_source").notNull().default("default"),
  calorieTargetConfiguredAt: timestamp("calorie_target_configured_at", { withTimezone: true }),
  macroMode: text("macro_mode"),
  macroSource: text("macro_source"),
  macroPreset: text("macro_preset"),
  proteinPct: integer("protein_pct"),
  carbsPct: integer("carbs_pct"),
  fatPct: integer("fat_pct"),
  macroCalories: integer("macro_calories"),
  calorieDeltaKcal: integer("calorie_delta_kcal"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  primaryKey({ columns: [table.userId, table.targetDate] }),
  index("daily_goal_snapshots_user_date_idx").on(table.userId, table.targetDate)
]);

export const foodItems = pgTable("food_items", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").references(() => users.id, { onDelete: "cascade" }),
  name: text("name").notNull(),
  normalizedName: text("normalized_name").notNull(),
  canonicalName: text("canonical_name"),
  brand: text("brand"),
  barcode: text("barcode"),
  source: text("source").notNull(),
  externalSource: text("external_source"),
  externalId: text("external_id"),
  sourceUrl: text("source_url"),
  license: text("license"),
  fetchedAt: timestamp("fetched_at", { withTimezone: true }),
  dataType: text("data_type"),
  foodCategory: text("food_category"),
  publicationDate: date("publication_date"),
  ndbNumber: text("ndb_number"),
  foodKey: text("food_key"),
  ingredients: text("ingredients"),
  marketCountry: text("market_country"),
  householdServingFulltext: text("household_serving_fulltext"),
  nutrientsJson: jsonb("nutrients_json").$type<JsonObject>().notNull().default(sql`'{}'::jsonb`),
  servingGrams: numeric("serving_grams", { precision: 10, scale: 2 }).notNull().default("100"),
  calories: integer("calories").notNull(),
  proteinGrams: numeric("protein_grams", { precision: 10, scale: 2 }).notNull(),
  carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
  fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  index("food_items_external_source_id_idx").on(table.externalSource, table.externalId).where(sql`${table.externalSource} IS NOT NULL AND ${table.externalId} IS NOT NULL`),
  index("food_items_external_source_id_lookup_idx").on(table.externalSource, table.externalId).where(sql`${table.externalSource} IS NOT NULL AND ${table.externalId} IS NOT NULL`),
  index("food_items_barcode_lookup_idx").on(table.barcode).where(sql`${table.barcode} IS NOT NULL`),
  index("food_items_data_type_lookup_idx").on(table.dataType).where(sql`${table.dataType} IS NOT NULL`),
  index("food_items_food_key_lookup_idx").on(table.foodKey).where(sql`${table.foodKey} IS NOT NULL`),
  index("food_items_ndb_number_lookup_idx").on(table.ndbNumber).where(sql`${table.ndbNumber} IS NOT NULL`),
  index("food_items_canonical_name_idx").on(table.canonicalName).where(sql`${table.canonicalName} IS NOT NULL`),
  index("food_items_normalized_name_trgm_idx").using("gin", table.normalizedName.op("gin_trgm_ops")),
  index("food_items_canonical_name_trgm_idx").using("gin", table.canonicalName.op("gin_trgm_ops")).where(sql`${table.canonicalName} IS NOT NULL`),
  index("food_items_brand_trgm_idx").using("gin", table.brand.op("gin_trgm_ops")).where(sql`${table.brand} IS NOT NULL`),
  index("food_items_usda_normalized_name_trgm_idx").using("gin", table.normalizedName.op("gin_trgm_ops")).where(sql`${table.externalSource} = 'usda_fdc'`),
  index("food_items_usda_canonical_name_trgm_idx").using("gin", table.canonicalName.op("gin_trgm_ops")).where(sql`${table.externalSource} = 'usda_fdc' AND ${table.canonicalName} IS NOT NULL`),
  index("food_items_usda_brand_trgm_idx").using("gin", table.brand.op("gin_trgm_ops")).where(sql`${table.externalSource} = 'usda_fdc' AND ${table.brand} IS NOT NULL`)
]);

export const foodPortions = pgTable("food_portions", {
  id: uuid("id").primaryKey().defaultRandom(),
  foodItemId: uuid("food_item_id").notNull().references(() => foodItems.id, { onDelete: "cascade" }),
  usdaPortionId: text("usda_portion_id"),
  amount: numeric("amount", { precision: 10, scale: 4 }),
  unit: text("unit"),
  modifier: text("modifier"),
  description: text("description"),
  gramWeight: numeric("gram_weight", { precision: 10, scale: 4 }).notNull(),
  normalizedAliases: text("normalized_aliases").array().notNull().default(sql`'{}'::text[]`),
  kind: text("kind").notNull().default("serving"),
  sourceDescription: text("source_description").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  index("food_portions_food_item_id_idx").on(table.foodItemId),
  index("food_portions_aliases_gin_idx").using("gin", table.normalizedAliases),
  uniqueIndex("food_portions_food_usda_portion_unique").on(table.foodItemId, table.usdaPortionId).where(sql`${table.usdaPortionId} IS NOT NULL`)
]);

export const foodSearchDocuments = pgTable("food_search_documents", {
  foodItemId: uuid("food_item_id").primaryKey().references(() => foodItems.id, { onDelete: "cascade" }),
  userId: uuid("user_id").references(() => users.id, { onDelete: "cascade" }),
  locale: text("locale").notNull(),
  scope: text("scope").notNull(),
  searchText: text("search_text").notNull(),
  searchVector: tsvector("search_vector").notNull(),
  rankBucket: integer("rank_bucket").notNull(),
  source: text("source").notNull(),
  externalSource: text("external_source"),
  dataType: text("data_type"),
  foodKey: text("food_key"),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  index("food_search_documents_generic_es_trgm_idx").using("gin", table.searchText.op("gin_trgm_ops")).where(sql`${table.scope} = 'generic' AND ${table.locale} = 'es'`),
  index("food_search_documents_generic_en_trgm_idx").using("gin", table.searchText.op("gin_trgm_ops")).where(sql`${table.scope} = 'generic' AND ${table.locale} = 'en'`),
  index("food_search_documents_generic_trgm_idx").using("gin", table.searchText.op("gin_trgm_ops")).where(sql`${table.scope} = 'generic'`),
  index("food_search_documents_market_trgm_idx").using("gin", table.searchText.op("gin_trgm_ops")).where(sql`${table.scope} = 'market'`),
  index("food_search_documents_search_vector_idx").using("gin", table.searchVector),
  index("food_search_documents_scope_locale_rank_idx").on(table.scope, table.locale, table.rankBucket),
  index("food_search_documents_user_idx").on(table.userId).where(sql`${table.userId} IS NOT NULL`)
]);

export const referenceDataImports = pgTable("reference_data_imports", {
  id: uuid("id").primaryKey().defaultRandom(),
  source: text("source").notNull(),
  targetSchema: text("target_schema").notNull(),
  manifestSha256: text("manifest_sha256").notNull(),
  manifestJson: jsonb("manifest_json").$type<JsonObject>().notNull(),
  foodCount: integer("food_count").notNull(),
  portionCount: integer("portion_count").notNull(),
  importedAt: timestamp("imported_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  uniqueIndex("reference_data_imports_source_schema_manifest_unique").on(table.source, table.targetSchema, table.manifestSha256),
  index("reference_data_imports_source_imported_at_idx").on(table.source, table.importedAt)
]);

export const mealProposals = pgTable("meal_proposals", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  phrase: text("phrase").notNull(),
  title: text("title").notNull(),
  status: text("status").notNull(),
  confidence: numeric("confidence", { precision: 5, scale: 4 }).notNull(),
  requiresConfirmation: boolean("requires_confirmation").notNull().default(true),
  trustedAutoCommitEligible: boolean("trusted_auto_commit_eligible").notNull().default(false),
  source: text("source").notNull(),
  calories: integer("calories").notNull(),
  proteinGrams: numeric("protein_grams", { precision: 10, scale: 2 }).notNull(),
  carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
  fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
});

function mealItemColumns() {
  return {
    id: uuid("id").primaryKey().defaultRandom(),
    name: text("name").notNull(),
    quantity: numeric("quantity", { precision: 10, scale: 2 }).notNull(),
    unit: text("unit").notNull(),
    calories: integer("calories").notNull(),
    proteinGrams: numeric("protein_grams", { precision: 10, scale: 2 }).notNull(),
    carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
    fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
    source: text("source").notNull().default("snapshot"),
    originalText: text("original_text"),
    canonicalName: text("canonical_name"),
    externalSource: text("external_source"),
    externalId: text("external_id"),
    sourceUrl: text("source_url"),
    license: text("license"),
    confidence: numeric("confidence", { precision: 5, scale: 4 }),
    needsReview: boolean("needs_review").notNull().default(false)
  };
}

export const mealProposalItems = pgTable("meal_proposal_items", {
  ...mealItemColumns(),
  proposalId: uuid("proposal_id").notNull().references(() => mealProposals.id, { onDelete: "cascade" }),
  foodItemId: uuid("food_item_id").references(() => foodItems.id)
});

export const meals = pgTable("meals", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  proposalId: uuid("proposal_id").references(() => mealProposals.id),
  title: text("title").notNull(),
  occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull(),
  mealType: text("meal_type"),
  mealTypeLabel: text("meal_type_label"),
  calories: integer("calories").notNull(),
  proteinGrams: numeric("protein_grams", { precision: 10, scale: 2 }).notNull(),
  carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
  fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
  deletedAt: timestamp("deleted_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  index("meals_user_occurred_at_idx").on(table.userId, table.occurredAt).where(sql`${table.deletedAt} IS NULL`),
  check("meals_meal_type_check", sql`(${table.mealType} IS NULL AND ${table.mealTypeLabel} IS NULL) OR (${table.mealType} = ANY (ARRAY['breakfast','lunch','dinner','snack','pre_workout','post_workout','other']) AND ${table.mealTypeLabel} IS NOT NULL AND btrim(${table.mealTypeLabel}) <> '' AND char_length(${table.mealTypeLabel}) <= 40)`)
]);

export const mealItems = pgTable("meal_items", {
  ...mealItemColumns(),
  mealId: uuid("meal_id").notNull().references(() => meals.id, { onDelete: "cascade" })
});

export const mealTemplates = pgTable("meal_templates", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  title: text("title").notNull(),
  normalizedTitle: text("normalized_title").notNull(),
  trustedAutoCommitEnabled: boolean("trusted_auto_commit_enabled").notNull().default(false),
  calories: integer("calories").notNull(),
  proteinGrams: numeric("protein_grams", { precision: 10, scale: 2 }).notNull(),
  carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
  fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  deletedAt: timestamp("deleted_at", { withTimezone: true })
});

export const mealTemplateItems = pgTable("meal_template_items", {
  ...mealItemColumns(),
  templateId: uuid("template_id").notNull().references(() => mealTemplates.id, { onDelete: "cascade" })
});

export const foodMemories = pgTable("food_memories", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  normalizedText: text("normalized_text").notNull(),
  label: text("label").notNull(),
  mealTemplateId: uuid("meal_template_id").references(() => mealTemplates.id),
  usageCount: integer("usage_count").notNull().default(0),
  confidence: numeric("confidence", { precision: 5, scale: 4 }).notNull().default("1"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  lastUsedAt: timestamp("last_used_at", { withTimezone: true })
}, (table) => [
  uniqueIndex("food_memories_user_normalized_unique").on(table.userId, table.normalizedText)
]);

export const foodMemoryEmbeddings = pgTable("food_memory_embeddings", {
  id: uuid("id").primaryKey().defaultRandom(),
  foodMemoryId: uuid("food_memory_id").notNull().references(() => foodMemories.id, { onDelete: "cascade" }),
  embedding: vector("embedding", { dimensions: 1024 }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  uniqueIndex("food_memory_embeddings_memory_unique").on(table.foodMemoryId)
]);

export const foodItemEmbeddings = pgTable("food_item_embeddings", {
  id: uuid("id").primaryKey().defaultRandom(),
  foodItemId: uuid("food_item_id").notNull().references(() => foodItems.id, { onDelete: "cascade" }),
  embeddedText: text("embedded_text").notNull(),
  embeddedTextHash: text("embedded_text_hash").notNull(),
  embedding: vector("embedding", { dimensions: 1024 }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  uniqueIndex("food_item_embeddings_food_unique").on(table.foodItemId),
  index("food_item_embeddings_hash_idx").on(table.embeddedTextHash)
]);

export const userFoodFeedbackEvents = pgTable("user_food_feedback_events", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  foodItemId: uuid("food_item_id").notNull().references(() => foodItems.id, { onDelete: "cascade" }),
  queryText: text("query_text").notNull(),
  normalizedQuery: text("normalized_query").notNull(),
  action: text("action").notNull(),
  metadataJson: jsonb("metadata_json").$type<JsonObject>().notNull().default(sql`'{}'::jsonb`),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  index("user_food_feedback_events_user_created_idx").on(table.userId, table.createdAt),
  index("user_food_feedback_events_user_food_idx").on(table.userId, table.foodItemId, table.createdAt),
  index("user_food_feedback_events_query_idx").on(table.userId, table.normalizedQuery)
]);

export const userFoodPreferences = pgTable("user_food_preferences", {
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  foodItemId: uuid("food_item_id").notNull().references(() => foodItems.id, { onDelete: "cascade" }),
  affinityScore: numeric("affinity_score", { precision: 8, scale: 4 }).notNull().default("0"),
  positiveFeedbackCount: integer("positive_feedback_count").notNull().default(0),
  negativeFeedbackCount: integer("negative_feedback_count").notNull().default(0),
  lastFeedbackAt: timestamp("last_feedback_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  primaryKey({ columns: [table.userId, table.foodItemId] }),
  index("user_food_preferences_user_score_idx").on(table.userId, table.affinityScore, table.updatedAt),
  index("user_food_preferences_food_idx").on(table.foodItemId)
]);

export const corrections = pgTable("corrections", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  mealId: uuid("meal_id").references(() => meals.id),
  proposalId: uuid("proposal_id").references(() => mealProposals.id),
  correctionText: text("correction_text").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
});

export const confirmationRequests = pgTable("confirmation_requests", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  actionId: text("action_id").notNull(),
  inputJson: jsonb("input_json").$type<JsonObject>().notNull(),
  status: text("status").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  resolvedAt: timestamp("resolved_at", { withTimezone: true })
});

export const actionCalls = pgTable("action_calls", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  actionId: text("action_id").notNull(),
  source: text("source").notNull(),
  inputJson: jsonb("input_json").$type<unknown>().notNull(),
  outputJson: jsonb("output_json").$type<unknown>(),
  errorJson: jsonb("error_json").$type<unknown>(),
  confirmationStatus: text("confirmation_status").notNull(),
  traceId: text("trace_id").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  latencyMs: integer("latency_ms").notNull()
});

export const auditEvents = pgTable("audit_events", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").references(() => users.id, { onDelete: "set null" }),
  eventType: text("event_type").notNull(),
  metadataJson: jsonb("metadata_json").$type<unknown>().notNull().default(sql`'{}'::jsonb`),
  traceId: text("trace_id").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
});

export const agentConnections = pgTable("agent_connections", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id, { onDelete: "cascade" }),
  source: text("source").notNull(),
  scopes: text("scopes").array().notNull(),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
});

export const outboxJobs = pgTable("outbox_jobs", {
  id: uuid("id").primaryKey().defaultRandom(),
  jobType: text("job_type").notNull(),
  payloadJson: jsonb("payload_json").$type<JsonObject>().notNull(),
  status: text("status").notNull().default("pending"),
  attempts: integer("attempts").notNull().default(0),
  runAfter: timestamp("run_after", { withTimezone: true }).notNull().defaultNow(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow()
});

export const foodAliases = pgTable("food_aliases", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").references(() => users.id, { onDelete: "cascade" }),
  aliasText: text("alias_text").notNull(),
  normalizedAlias: text("normalized_alias").notNull(),
  locale: text("locale").notNull().default("und"),
  canonicalEnglishName: text("canonical_english_name").notNull(),
  foodItemId: uuid("food_item_id").references(() => foodItems.id, { onDelete: "set null" }),
  source: text("source").notNull(),
  confidence: numeric("confidence", { precision: 5, scale: 4 }).notNull().default("1"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow()
}, (table) => [
  index("food_aliases_normalized_alias_idx").on(table.normalizedAlias)
]);

export const usersRelations = relations(users, ({ one, many }) => ({
  credential: one(userCredentials),
  identities: many(authIdentities),
  sessions: many(authSessions),
  meals: many(meals),
  templates: many(mealTemplates),
  memories: many(foodMemories),
  actionCalls: many(actionCalls),
  auditEvents: many(auditEvents)
}));

export const foodItemsRelations = relations(foodItems, ({ one, many }) => ({
  user: one(users, { fields: [foodItems.userId], references: [users.id] }),
  portions: many(foodPortions),
  searchDocument: one(foodSearchDocuments),
  embeddings: many(foodItemEmbeddings)
}));

export const mealsRelations = relations(meals, ({ one, many }) => ({
  user: one(users, { fields: [meals.userId], references: [users.id] }),
  proposal: one(mealProposals, { fields: [meals.proposalId], references: [mealProposals.id] }),
  items: many(mealItems)
}));

export const mealProposalsRelations = relations(mealProposals, ({ one, many }) => ({
  user: one(users, { fields: [mealProposals.userId], references: [users.id] }),
  items: many(mealProposalItems)
}));

export const mealTemplatesRelations = relations(mealTemplates, ({ one, many }) => ({
  user: one(users, { fields: [mealTemplates.userId], references: [users.id] }),
  items: many(mealTemplateItems),
  aliases: many(foodMemories)
}));

export const foodMemoriesRelations = relations(foodMemories, ({ one }) => ({
  user: one(users, { fields: [foodMemories.userId], references: [users.id] }),
  template: one(mealTemplates, { fields: [foodMemories.mealTemplateId], references: [mealTemplates.id] })
}));
