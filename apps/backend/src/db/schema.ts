import { relations, sql } from "drizzle-orm";
import {
  boolean,
  check,
  customType,
  date,
  index,
  integer,
  jsonb,
  numeric,
  pgTable,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
  vector,
} from "drizzle-orm/pg-core";

type JsonObject = Record<string, unknown>;

const tsvector = customType<{ data: string }>({
  dataType() {
    return "tsvector";
  },
});

const timestamps = {
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
};

export const schemaMigrations = pgTable("schema_migrations", {
  filename: text("filename").primaryKey().notNull(),
  appliedAt: timestamp("applied_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const users = pgTable(
  "users",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    email: text("email").notNull(),
    displayName: text("display_name").notNull(),
    trustedModeEnabled: boolean("trusted_mode_enabled")
      .notNull()
      .default(false),
    emailVerifiedAt: timestamp("email_verified_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (table) => [
    uniqueIndex("users_active_email_unique")
      .on(sql`lower(${table.email})`)
      .where(sql`${table.deletedAt} IS NULL`),
  ],
);

export const pendingRegistrations = pgTable(
  "pending_registrations",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    email: text("email").notNull(),
    displayName: text("display_name").notNull(),
    passwordHash: text("password_hash").notNull(),
    tokenHash: text("token_hash").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    consumedAt: timestamp("consumed_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("pending_registrations_active_email_unique")
      .on(sql`lower(${table.email})`)
      .where(sql`${table.consumedAt} IS NULL`),
    uniqueIndex("pending_registrations_active_token_unique")
      .on(table.tokenHash)
      .where(sql`${table.consumedAt} IS NULL`),
  ],
);

export const userCredentials = pgTable("user_credentials", {
  userId: uuid("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  passwordHash: text("password_hash").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const authIdentities = pgTable(
  "auth_identities",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    provider: text("provider").notNull(),
    providerUserId: text("provider_user_id").notNull(),
    email: text("email").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("auth_identities_provider_user_unique").on(
      table.provider,
      table.providerUserId,
    ),
    index("auth_identities_user_idx").on(table.userId),
  ],
);

export const authSessions = pgTable(
  "auth_sessions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    refreshTokenHash: text("refresh_token_hash").notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    revokedAt: timestamp("revoked_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    rotatedAt: timestamp("rotated_at", { withTimezone: true }),
  },
  (table) => [
    index("auth_sessions_active_idx")
      .on(table.userId, table.expiresAt)
      .where(sql`${table.revokedAt} IS NULL`),
  ],
);

export const passwordResetTokens = pgTable("password_reset_tokens", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  tokenHash: text("token_hash").notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  usedAt: timestamp("used_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const nutritionTargets = pgTable("nutrition_targets", {
  userId: uuid("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
  calories: integer("calories").notNull(),
  proteinGrams: numeric("protein_grams", { precision: 10, scale: 2 }).notNull(),
  carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
  fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
  hydrationGoalGlasses: integer("hydration_goal_glasses").notNull().default(0),
  hydrationGoalLiters: numeric("hydration_goal_liters", {
    precision: 5,
    scale: 2,
  })
    .notNull()
    .default("0"),
  calorieTargetConfigured: boolean("calorie_target_configured")
    .notNull()
    .default(false),
  calorieTargetSource: text("calorie_target_source")
    .notNull()
    .default("default"),
  calorieTargetConfiguredAt: timestamp("calorie_target_configured_at", {
    withTimezone: true,
  }),
  macroMode: text("macro_mode"),
  macroSource: text("macro_source"),
  macroPreset: text("macro_preset"),
  proteinPct: integer("protein_pct"),
  carbsPct: integer("carbs_pct"),
  fatPct: integer("fat_pct"),
  macroCalories: integer("macro_calories"),
  calorieDeltaKcal: integer("calorie_delta_kcal"),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const dailyGoalSnapshots = pgTable(
  "daily_goal_snapshots",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    targetDate: date("target_date").notNull(),
    calories: integer("calories").notNull(),
    proteinGrams: numeric("protein_grams", {
      precision: 10,
      scale: 2,
    }).notNull(),
    carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
    fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
    hydrationGoalGlasses: integer("hydration_goal_glasses")
      .notNull()
      .default(0),
    hydrationGoalLiters: numeric("hydration_goal_liters", {
      precision: 5,
      scale: 2,
    })
      .notNull()
      .default("0"),
    waterConsumedLiters: numeric("water_consumed_liters", {
      precision: 5,
      scale: 2,
    })
      .notNull()
      .default("0"),
    calorieTargetConfigured: boolean("calorie_target_configured")
      .notNull()
      .default(false),
    calorieTargetSource: text("calorie_target_source")
      .notNull()
      .default("default"),
    calorieTargetConfiguredAt: timestamp("calorie_target_configured_at", {
      withTimezone: true,
    }),
    macroMode: text("macro_mode"),
    macroSource: text("macro_source"),
    macroPreset: text("macro_preset"),
    proteinPct: integer("protein_pct"),
    carbsPct: integer("carbs_pct"),
    fatPct: integer("fat_pct"),
    macroCalories: integer("macro_calories"),
    calorieDeltaKcal: integer("calorie_delta_kcal"),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.targetDate] }),
    index("daily_goal_snapshots_user_date_idx").on(
      table.userId,
      table.targetDate,
    ),
  ],
);

export const foodItems = pgTable(
  "food_items",
  {
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
    nutrientsJson: jsonb("nutrients_json")
      .$type<JsonObject>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    servingGrams: numeric("serving_grams", { precision: 10, scale: 2 })
      .notNull()
      .default("100"),
    calories: integer("calories").notNull(),
    proteinGrams: numeric("protein_grams", {
      precision: 10,
      scale: 2,
    }).notNull(),
    carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
    fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
  },
  (table) => [
    index("food_items_external_source_id_idx")
      .on(table.externalSource, table.externalId)
      .where(
        sql`${table.externalSource} IS NOT NULL AND ${table.externalId} IS NOT NULL`,
      ),
    index("food_items_external_source_id_lookup_idx")
      .on(table.externalSource, table.externalId)
      .where(
        sql`${table.externalSource} IS NOT NULL AND ${table.externalId} IS NOT NULL`,
      ),
    index("food_items_barcode_lookup_idx")
      .on(table.barcode)
      .where(sql`${table.barcode} IS NOT NULL`),
    index("food_items_data_type_lookup_idx")
      .on(table.dataType)
      .where(sql`${table.dataType} IS NOT NULL`),
    index("food_items_food_key_lookup_idx")
      .on(table.foodKey)
      .where(sql`${table.foodKey} IS NOT NULL`),
    index("food_items_ndb_number_lookup_idx")
      .on(table.ndbNumber)
      .where(sql`${table.ndbNumber} IS NOT NULL`),
    index("food_items_canonical_name_idx")
      .on(table.canonicalName)
      .where(sql`${table.canonicalName} IS NOT NULL`),
    index("food_items_normalized_name_trgm_idx").using(
      "gin",
      table.normalizedName.op("gin_trgm_ops"),
    ),
    index("food_items_canonical_name_trgm_idx")
      .using("gin", table.canonicalName.op("gin_trgm_ops"))
      .where(sql`${table.canonicalName} IS NOT NULL`),
    index("food_items_brand_trgm_idx")
      .using("gin", table.brand.op("gin_trgm_ops"))
      .where(sql`${table.brand} IS NOT NULL`),
    index("food_items_usda_normalized_name_trgm_idx")
      .using("gin", table.normalizedName.op("gin_trgm_ops"))
      .where(sql`${table.externalSource} = 'usda_fdc'`),
    index("food_items_usda_canonical_name_trgm_idx")
      .using("gin", table.canonicalName.op("gin_trgm_ops"))
      .where(
        sql`${table.externalSource} = 'usda_fdc' AND ${table.canonicalName} IS NOT NULL`,
      ),
    index("food_items_usda_brand_trgm_idx")
      .using("gin", table.brand.op("gin_trgm_ops"))
      .where(
        sql`${table.externalSource} = 'usda_fdc' AND ${table.brand} IS NOT NULL`,
      ),
  ],
);

export const foodPortions = pgTable(
  "food_portions",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    foodItemId: uuid("food_item_id")
      .notNull()
      .references(() => foodItems.id, { onDelete: "cascade" }),
    usdaPortionId: text("usda_portion_id"),
    amount: numeric("amount", { precision: 10, scale: 4 }),
    unit: text("unit"),
    modifier: text("modifier"),
    description: text("description"),
    gramWeight: numeric("gram_weight", { precision: 10, scale: 4 }).notNull(),
    normalizedAliases: text("normalized_aliases")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    kind: text("kind").notNull().default("serving"),
    sourceDescription: text("source_description").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("food_portions_food_item_id_idx").on(table.foodItemId),
    index("food_portions_aliases_gin_idx").using(
      "gin",
      table.normalizedAliases,
    ),
    uniqueIndex("food_portions_food_usda_portion_unique")
      .on(table.foodItemId, table.usdaPortionId)
      .where(sql`${table.usdaPortionId} IS NOT NULL`),
  ],
);

export const foodSearchDocuments = pgTable(
  "food_search_documents",
  {
    foodItemId: uuid("food_item_id")
      .primaryKey()
      .references(() => foodItems.id, { onDelete: "cascade" }),
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
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("food_search_documents_generic_es_trgm_idx")
      .using("gin", table.searchText.op("gin_trgm_ops"))
      .where(sql`${table.scope} = 'generic' AND ${table.locale} = 'es'`),
    index("food_search_documents_generic_en_trgm_idx")
      .using("gin", table.searchText.op("gin_trgm_ops"))
      .where(sql`${table.scope} = 'generic' AND ${table.locale} = 'en'`),
    index("food_search_documents_generic_trgm_idx")
      .using("gin", table.searchText.op("gin_trgm_ops"))
      .where(sql`${table.scope} = 'generic'`),
    index("food_search_documents_market_trgm_idx")
      .using("gin", table.searchText.op("gin_trgm_ops"))
      .where(sql`${table.scope} = 'market'`),
    index("food_search_documents_search_vector_idx").using(
      "gin",
      table.searchVector,
    ),
    index("food_search_documents_scope_locale_rank_idx").on(
      table.scope,
      table.locale,
      table.rankBucket,
    ),
    index("food_search_documents_user_idx")
      .on(table.userId)
      .where(sql`${table.userId} IS NOT NULL`),
  ],
);

export const foodItemQuality = pgTable(
  "food_item_quality",
  {
    foodItemId: uuid("food_item_id")
      .primaryKey()
      .references(() => foodItems.id, { onDelete: "cascade" }),
    qualityStatus: text("quality_status").notNull(),
    isSearchEligible: boolean("is_search_eligible").notNull(),
    canonicalFoodItemId: uuid("canonical_food_item_id").references(
      () => foodItems.id,
      { onDelete: "set null" },
    ),
    qualityScore: numeric("quality_score", {
      precision: 6,
      scale: 4,
    }).notNull(),
    qualityFlags: text("quality_flags")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    qualityVersion: text("quality_version").notNull(),
    metadata: jsonb("metadata")
      .$type<JsonObject>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    check(
      "food_item_quality_status_check",
      sql`${table.qualityStatus} IN ('valid', 'duplicate', 'suspicious', 'quarantined')`,
    ),
    index("food_item_quality_eligible_status_idx").on(
      table.isSearchEligible,
      table.qualityStatus,
    ),
    index("food_item_quality_flags_gin_idx").using("gin", table.qualityFlags),
    index("food_item_quality_canonical_idx")
      .on(table.canonicalFoodItemId)
      .where(sql`${table.canonicalFoodItemId} IS NOT NULL`),
  ],
);

export const foodNormalizationSampleSets = pgTable(
  "food_normalization_sample_sets",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    name: text("name").notNull(),
    description: text("description").notNull(),
    seed: text("seed").notNull(),
    qualityVersion: text("quality_version").notNull(),
    normalizationVersion: text("normalization_version").notNull(),
    criteriaJson: jsonb("criteria_json").$type<JsonObject>().notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("food_normalization_sample_sets_name_unique").on(table.name),
  ],
);

export const foodNormalizationSampleItems = pgTable(
  "food_normalization_sample_items",
  {
    sampleSetId: uuid("sample_set_id")
      .notNull()
      .references(() => foodNormalizationSampleSets.id, {
        onDelete: "cascade",
      }),
    foodItemId: uuid("food_item_id")
      .notNull()
      .references(() => foodItems.id, { onDelete: "cascade" }),
    sampleReason: text("sample_reason").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.sampleSetId, table.foodItemId] }),
    index("food_normalization_sample_items_sample_food_idx").on(
      table.sampleSetId,
      table.foodItemId,
    ),
    index("food_normalization_sample_items_reason_idx").on(
      table.sampleSetId,
      table.sampleReason,
    ),
  ],
);

export const foodNormalizedSearchDocuments = pgTable(
  "food_normalized_search_documents",
  {
    foodItemId: uuid("food_item_id")
      .primaryKey()
      .references(() => foodItems.id, { onDelete: "cascade" }),
    userId: uuid("user_id").references(() => users.id, { onDelete: "cascade" }),
    locale: text("locale").notNull(),
    resultType: text("result_type").notNull(),
    displayName: text("display_name").notNull(),
    baseName: text("base_name").notNull(),
    variantName: text("variant_name"),
    brandDisplay: text("brand_display"),
    primaryEntityName: text("primary_entity_name").notNull().default(""),
    primaryEntityAliases: text("primary_entity_aliases")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    secondaryEntityAliases: text("secondary_entity_aliases")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    identityTokenKeys: text("identity_token_keys")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    primaryEntityCategory: text("primary_entity_category"),
    primaryEntityCategoryCoherence: numeric(
      "primary_entity_category_coherence",
      { precision: 6, scale: 4 },
    )
      .notNull()
      .default("0"),
    primaryEntityRepresentativeness: numeric(
      "primary_entity_representativeness",
      { precision: 6, scale: 4 },
    )
      .notNull()
      .default("0"),
    searchText: text("search_text").notNull(),
    searchAliases: text("search_aliases")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    searchVector: tsvector("search_vector").notNull(),
    rankBucket: integer("rank_bucket").notNull(),
    normalizationVersion: text("normalization_version").notNull(),
    normalizationSource: text("normalization_source").notNull(),
    normalizationConfidence: numeric("normalization_confidence", {
      precision: 6,
      scale: 4,
    }).notNull(),
    qualityFlags: text("quality_flags")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    metadata: jsonb("metadata")
      .$type<JsonObject>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    check(
      "food_normalized_search_documents_result_type_check",
      sql`${table.resultType} IN ('generic_food', 'product', 'custom_food')`,
    ),
    index("food_normalized_search_documents_search_text_trgm_idx").using(
      "gin",
      table.searchText.op("gin_trgm_ops"),
    ),
    index("food_normalized_search_documents_base_name_trgm_idx").using(
      "gin",
      sql`lower(${table.baseName}) gin_trgm_ops`,
    ),
    index("food_normalized_search_documents_display_name_trgm_idx").using(
      "gin",
      sql`lower(${table.displayName}) gin_trgm_ops`,
    ),
    index("food_normalized_search_documents_brand_display_trgm_idx").using(
      "gin",
      sql`lower(${table.brandDisplay}) gin_trgm_ops`,
    ),
    index("food_normalized_search_documents_base_name_lower_idx").on(
      sql`lower(${table.baseName})`,
    ),
    index("food_normalized_search_documents_display_name_lower_idx").on(
      sql`lower(${table.displayName})`,
    ),
    index("food_normalized_search_documents_brand_display_lower_idx").on(
      sql`lower(${table.brandDisplay})`,
    ),
    index("food_normalized_search_documents_primary_aliases_gin_idx").using(
      "gin",
      table.primaryEntityAliases,
    ),
    index("food_normalized_search_documents_secondary_aliases_gin_idx").using(
      "gin",
      table.secondaryEntityAliases,
    ),
    index("food_normalized_search_documents_identity_token_keys_gin_idx").using(
      "gin",
      table.identityTokenKeys,
    ),
    index("food_normalized_search_documents_search_vector_idx").using(
      "gin",
      table.searchVector,
    ),
    index("food_normalized_search_documents_locale_type_rank_idx").on(
      table.locale,
      table.resultType,
      table.rankBucket,
    ),
    index("food_normalized_search_documents_user_idx")
      .on(table.userId)
      .where(sql`${table.userId} IS NOT NULL`),
  ],
);

export const foodNormalizationReview = pgTable(
  "food_normalization_review",
  {
    foodItemId: uuid("food_item_id")
      .primaryKey()
      .references(() => foodItems.id, { onDelete: "cascade" }),
    normalizationVersion: text("normalization_version").notNull(),
    reviewStatus: text("review_status").notNull(),
    severity: text("severity").notNull(),
    issueCodes: text("issue_codes")
      .array()
      .notNull()
      .default(sql`'{}'::text[]`),
    rawName: text("raw_name").notNull(),
    rawBrand: text("raw_brand"),
    rawSource: text("raw_source"),
    rawExternalSource: text("raw_external_source"),
    rawDataType: text("raw_data_type"),
    displayName: text("display_name"),
    baseName: text("base_name"),
    variantName: text("variant_name"),
    brandDisplay: text("brand_display"),
    primaryEntityName: text("primary_entity_name"),
    locale: text("locale"),
    resultType: text("result_type"),
    normalizationConfidence: numeric("normalization_confidence", {
      precision: 6,
      scale: 4,
    }),
    metrics: jsonb("metrics")
      .$type<JsonObject>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    metadata: jsonb("metadata")
      .$type<JsonObject>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    check(
      "food_normalization_review_status_check",
      sql`${table.reviewStatus} IN ('valid', 'needs_review', 'failed')`,
    ),
    check(
      "food_normalization_review_severity_check",
      sql`${table.severity} IN ('info', 'warning', 'error')`,
    ),
    index("food_normalization_review_status_severity_idx").on(
      table.reviewStatus,
      table.severity,
    ),
    index("food_normalization_review_issue_codes_gin_idx").using(
      "gin",
      table.issueCodes,
    ),
    index("food_normalization_review_version_idx").on(
      table.normalizationVersion,
    ),
    index("food_normalization_review_display_idx").on(
      table.locale,
      table.resultType,
      sql`lower(${table.displayName})`,
    ),
  ],
);

export const referenceDataImports = pgTable(
  "reference_data_imports",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    source: text("source").notNull(),
    targetSchema: text("target_schema").notNull(),
    manifestSha256: text("manifest_sha256").notNull(),
    manifestJson: jsonb("manifest_json").$type<JsonObject>().notNull(),
    foodCount: integer("food_count").notNull(),
    portionCount: integer("portion_count").notNull(),
    importedAt: timestamp("imported_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("reference_data_imports_source_schema_manifest_unique").on(
      table.source,
      table.targetSchema,
      table.manifestSha256,
    ),
    index("reference_data_imports_source_imported_at_idx").on(
      table.source,
      table.importedAt,
    ),
  ],
);

export const mealProposals = pgTable("meal_proposals", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  phrase: text("phrase").notNull(),
  title: text("title").notNull(),
  status: text("status").notNull(),
  confidence: numeric("confidence", { precision: 5, scale: 4 }).notNull(),
  requiresConfirmation: boolean("requires_confirmation")
    .notNull()
    .default(true),
  trustedAutoCommitEligible: boolean("trusted_auto_commit_eligible")
    .notNull()
    .default(false),
  source: text("source").notNull(),
  calories: integer("calories").notNull(),
  proteinGrams: numeric("protein_grams", { precision: 10, scale: 2 }).notNull(),
  carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
  fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

function mealItemColumns() {
  return {
    id: uuid("id").primaryKey().defaultRandom(),
    name: text("name").notNull(),
    quantity: numeric("quantity", { precision: 10, scale: 2 }).notNull(),
    unit: text("unit").notNull(),
    calories: integer("calories").notNull(),
    proteinGrams: numeric("protein_grams", {
      precision: 10,
      scale: 2,
    }).notNull(),
    carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
    fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
    source: text("source").notNull().default("snapshot"),
    originalText: text("original_text"),
    canonicalName: text("canonical_name"),
    language: text("language"),
    externalSource: text("external_source"),
    externalId: text("external_id"),
    sourceUrl: text("source_url"),
    license: text("license"),
    confidence: numeric("confidence", { precision: 5, scale: 4 }),
    needsReview: boolean("needs_review").notNull().default(false),
  };
}

export const mealProposalItems = pgTable("meal_proposal_items", {
  ...mealItemColumns(),
  proposalId: uuid("proposal_id")
    .notNull()
    .references(() => mealProposals.id, { onDelete: "cascade" }),
  foodItemId: uuid("food_item_id").references(() => foodItems.id),
});

export const meals = pgTable(
  "meals",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    proposalId: uuid("proposal_id").references(() => mealProposals.id),
    title: text("title").notNull(),
    occurredAt: timestamp("occurred_at", { withTimezone: true }).notNull(),
    mealType: text("meal_type"),
    mealTypeLabel: text("meal_type_label"),
    calories: integer("calories").notNull(),
    proteinGrams: numeric("protein_grams", {
      precision: 10,
      scale: 2,
    }).notNull(),
    carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
    fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
    deletedAt: timestamp("deleted_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("meals_user_occurred_at_idx")
      .on(table.userId, table.occurredAt)
      .where(sql`${table.deletedAt} IS NULL`),
    check(
      "meals_meal_type_check",
      sql`(${table.mealType} IS NULL AND ${table.mealTypeLabel} IS NULL) OR (${table.mealType} = ANY (ARRAY['breakfast','lunch','dinner','snack','pre_workout','post_workout','other']) AND ${table.mealTypeLabel} IS NOT NULL AND btrim(${table.mealTypeLabel}) <> '' AND char_length(${table.mealTypeLabel}) <= 40)`,
    ),
  ],
);

export const mealItems = pgTable("meal_items", {
  ...mealItemColumns(),
  mealId: uuid("meal_id")
    .notNull()
    .references(() => meals.id, { onDelete: "cascade" }),
});

export const mealTemplates = pgTable("meal_templates", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  title: text("title").notNull(),
  normalizedTitle: text("normalized_title").notNull(),
  trustedAutoCommitEnabled: boolean("trusted_auto_commit_enabled")
    .notNull()
    .default(false),
  calories: integer("calories").notNull(),
  proteinGrams: numeric("protein_grams", { precision: 10, scale: 2 }).notNull(),
  carbsGrams: numeric("carbs_grams", { precision: 10, scale: 2 }).notNull(),
  fatGrams: numeric("fat_grams", { precision: 10, scale: 2 }).notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  deletedAt: timestamp("deleted_at", { withTimezone: true }),
});

export const mealTemplateItems = pgTable("meal_template_items", {
  ...mealItemColumns(),
  templateId: uuid("template_id")
    .notNull()
    .references(() => mealTemplates.id, { onDelete: "cascade" }),
});

export const foodMemories = pgTable(
  "food_memories",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    normalizedText: text("normalized_text").notNull(),
    label: text("label").notNull(),
    mealTemplateId: uuid("meal_template_id").references(() => mealTemplates.id),
    usageCount: integer("usage_count").notNull().default(0),
    confidence: numeric("confidence", { precision: 5, scale: 4 })
      .notNull()
      .default("1"),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    lastUsedAt: timestamp("last_used_at", { withTimezone: true }),
  },
  (table) => [
    uniqueIndex("food_memories_user_normalized_unique").on(
      table.userId,
      table.normalizedText,
    ),
  ],
);

export const foodMemoryEmbeddings = pgTable(
  "food_memory_embeddings",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    foodMemoryId: uuid("food_memory_id")
      .notNull()
      .references(() => foodMemories.id, { onDelete: "cascade" }),
    embedding: vector("embedding", { dimensions: 1024 }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("food_memory_embeddings_memory_unique").on(table.foodMemoryId),
  ],
);

export const foodItemEmbeddings = pgTable(
  "food_item_embeddings",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    foodItemId: uuid("food_item_id")
      .notNull()
      .references(() => foodItems.id, { onDelete: "cascade" }),
    embeddedText: text("embedded_text").notNull(),
    embeddedTextHash: text("embedded_text_hash").notNull(),
    embedding: vector("embedding", { dimensions: 1024 }).notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("food_item_embeddings_food_unique").on(table.foodItemId),
    index("food_item_embeddings_hash_idx").on(table.embeddedTextHash),
  ],
);

export const userFoodFeedbackEvents = pgTable(
  "user_food_feedback_events",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    foodItemId: uuid("food_item_id")
      .notNull()
      .references(() => foodItems.id, { onDelete: "cascade" }),
    queryText: text("query_text").notNull(),
    normalizedQuery: text("normalized_query").notNull(),
    action: text("action").notNull(),
    metadataJson: jsonb("metadata_json")
      .$type<JsonObject>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("user_food_feedback_events_user_created_idx").on(
      table.userId,
      table.createdAt,
    ),
    index("user_food_feedback_events_user_food_idx").on(
      table.userId,
      table.foodItemId,
      table.createdAt,
    ),
    index("user_food_feedback_events_query_idx").on(
      table.userId,
      table.normalizedQuery,
    ),
  ],
);

export const userFoodPreferences = pgTable(
  "user_food_preferences",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    foodItemId: uuid("food_item_id")
      .notNull()
      .references(() => foodItems.id, { onDelete: "cascade" }),
    affinityScore: numeric("affinity_score", { precision: 8, scale: 4 })
      .notNull()
      .default("0"),
    positiveFeedbackCount: integer("positive_feedback_count")
      .notNull()
      .default(0),
    negativeFeedbackCount: integer("negative_feedback_count")
      .notNull()
      .default(0),
    lastFeedbackAt: timestamp("last_feedback_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.foodItemId] }),
    index("user_food_preferences_user_score_idx").on(
      table.userId,
      table.affinityScore,
      table.updatedAt,
    ),
    index("user_food_preferences_food_idx").on(table.foodItemId),
  ],
);

export const corrections = pgTable("corrections", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  mealId: uuid("meal_id").references(() => meals.id),
  proposalId: uuid("proposal_id").references(() => mealProposals.id),
  correctionText: text("correction_text").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const confirmationRequests = pgTable("confirmation_requests", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  actionId: text("action_id").notNull(),
  inputJson: jsonb("input_json").$type<JsonObject>().notNull(),
  status: text("status").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  resolvedAt: timestamp("resolved_at", { withTimezone: true }),
});

export const actionCalls = pgTable("action_calls", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  actionId: text("action_id").notNull(),
  source: text("source").notNull(),
  inputJson: jsonb("input_json").$type<unknown>().notNull(),
  outputJson: jsonb("output_json").$type<unknown>(),
  errorJson: jsonb("error_json").$type<unknown>(),
  confirmationStatus: text("confirmation_status").notNull(),
  traceId: text("trace_id").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  latencyMs: integer("latency_ms").notNull(),
});

export const auditEvents = pgTable("audit_events", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").references(() => users.id, { onDelete: "set null" }),
  eventType: text("event_type").notNull(),
  metadataJson: jsonb("metadata_json")
    .$type<unknown>()
    .notNull()
    .default(sql`'{}'::jsonb`),
  traceId: text("trace_id").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const telemetryEvents = pgTable(
  "telemetry_events",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    traceId: text("trace_id").notNull(),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    sessionId: text("session_id"),
    eventType: text("event_type").notNull(),
    flow: text("flow"),
    surface: text("surface").notNull(),
    severity: text("severity").notNull(),
    status: text("status"),
    route: text("route"),
    method: text("method"),
    actionId: text("action_id"),
    durationMs: integer("duration_ms"),
    errorCode: text("error_code"),
    errorMessage: text("error_message"),
    appVersion: text("app_version"),
    appBuild: text("app_build"),
    platform: text("platform"),
    locale: text("locale"),
    metadataJson: jsonb("metadata_json")
      .$type<Record<string, unknown>>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("telemetry_events_created_at_idx").on(sql`${table.createdAt} DESC`),
    index("telemetry_events_trace_id_idx").on(table.traceId),
    index("telemetry_events_user_id_created_at_idx").on(
      table.userId,
      sql`${table.createdAt} DESC`,
    ),
    index("telemetry_events_event_type_created_at_idx").on(
      table.eventType,
      sql`${table.createdAt} DESC`,
    ),
    index("telemetry_events_severity_created_at_idx").on(
      table.severity,
      sql`${table.createdAt} DESC`,
    ),
  ],
);

export const llmRuns = pgTable(
  "llm_runs",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    traceId: text("trace_id").notNull(),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    source: text("source"),
    locale: text("locale"),
    timezone: text("timezone"),
    conversationId: uuid("conversation_id"),
    turnId: uuid("turn_id"),
    provider: text("provider"),
    providerRequestId: text("provider_request_id"),
    providerGenerationId: text("provider_generation_id"),
    model: text("model").notNull(),
    inputMode: text("input_mode"),
    activeProposalId: uuid("active_proposal_id"),
    decisionSource: text("decision_source"),
    selectedTool: text("selected_tool"),
    executedTool: text("executed_tool"),
    resultKind: text("result_kind"),
    actionCallId: uuid("action_call_id"),
    promptChars: integer("prompt_chars"),
    toolsJsonChars: integer("tools_json_chars"),
    messagesJsonChars: integer("messages_json_chars"),
    requestPayloadChars: integer("request_payload_chars"),
    promptTokens: integer("prompt_tokens"),
    completionTokens: integer("completion_tokens"),
    totalTokens: integer("total_tokens"),
    reasoningTokens: integer("reasoning_tokens"),
    firstByteMs: integer("first_byte_ms"),
    firstToolCallMs: integer("first_tool_call_ms"),
    largestStreamGapMs: integer("largest_stream_gap_ms"),
    llmMs: integer("llm_ms"),
    actionMs: integer("action_ms"),
    totalMs: integer("total_ms"),
    emptyToolCall: boolean("empty_tool_call").notNull().default(false),
    invalidToolArguments: boolean("invalid_tool_arguments")
      .notNull()
      .default(false),
    providerError: boolean("provider_error").notNull().default(false),
    providerCostAmount: numeric("provider_cost_amount", {
      precision: 12,
      scale: 6,
    }),
    estimatedCostAmount: numeric("estimated_cost_amount", {
      precision: 12,
      scale: 6,
    }),
    costCurrency: text("cost_currency"),
    costSource: text("cost_source"),
    pricingSnapshotJson: jsonb("pricing_snapshot_json")
      .$type<Record<string, unknown>>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    metadataJson: jsonb("metadata_json")
      .$type<Record<string, unknown>>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("llm_runs_created_at_idx").on(sql`${table.createdAt} DESC`),
    index("llm_runs_trace_id_idx").on(table.traceId),
    index("llm_runs_conversation_created_at_idx").on(
      table.conversationId,
      sql`${table.createdAt} DESC`,
    ),
    index("llm_runs_turn_id_idx").on(table.turnId),
    index("llm_runs_user_id_created_at_idx").on(
      table.userId,
      sql`${table.createdAt} DESC`,
    ),
    index("llm_runs_result_kind_created_at_idx").on(
      table.resultKind,
      sql`${table.createdAt} DESC`,
    ),
    index("llm_runs_selected_tool_created_at_idx").on(
      table.selectedTool,
      sql`${table.createdAt} DESC`,
    ),
  ],
);

export const foodSearchEvents = pgTable(
  "food_search_events",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    traceId: text("trace_id").notNull(),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    queryText: text("query_text"),
    queryHash: text("query_hash"),
    queryLength: integer("query_length").notNull().default(0),
    locale: text("locale"),
    barcodePresent: boolean("barcode_present").notNull().default(false),
    normalizedSearchEnabled: boolean("normalized_search_enabled"),
    normalizedScope: text("normalized_scope"),
    path: text("path"),
    resultCount: integer("result_count").notNull().default(0),
    candidateGroupCount: integer("candidate_group_count"),
    topScore: numeric("top_score", { precision: 8, scale: 4 }),
    topExternalSource: text("top_external_source"),
    topResultType: text("top_result_type"),
    zeroResults: boolean("zero_results").notNull().default(false),
    lowConfidence: boolean("low_confidence").notNull().default(false),
    selectedRank: integer("selected_rank"),
    durationMs: integer("duration_ms"),
    metadataJson: jsonb("metadata_json")
      .$type<Record<string, unknown>>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("food_search_events_created_at_idx").on(sql`${table.createdAt} DESC`),
    index("food_search_events_trace_id_idx").on(table.traceId),
    index("food_search_events_user_id_created_at_idx").on(
      table.userId,
      sql`${table.createdAt} DESC`,
    ),
    index("food_search_events_zero_results_created_at_idx").on(
      table.zeroResults,
      sql`${table.createdAt} DESC`,
    ),
    index("food_search_events_low_confidence_created_at_idx").on(
      table.lowConfidence,
      sql`${table.createdAt} DESC`,
    ),
  ],
);

export const agentConversations = pgTable(
  "agent_conversations",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    title: text("title").notNull().default("New chat"),
    hiddenFromUserAt: timestamp("hidden_from_user_at", {
      withTimezone: true,
    }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    updatedAt: timestamp("updated_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("agent_conversations_user_updated_idx").on(
      table.userId,
      table.updatedAt,
    ),
    index("agent_conversations_user_visible_updated_idx").on(
      table.userId,
      table.hiddenFromUserAt,
      table.updatedAt,
    ),
  ],
);

export const agentMessages = pgTable(
  "agent_messages",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    conversationId: uuid("conversation_id")
      .notNull()
      .references(() => agentConversations.id, { onDelete: "cascade" }),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    role: text("role").notNull(),
    content: text("content").notNull().default(""),
    toolCallsJson: jsonb("tool_calls_json").$type<unknown>(),
    toolCallId: text("tool_call_id"),
    traceId: text("trace_id"),
    turnId: uuid("turn_id"),
    inputMode: text("input_mode"),
    source: text("source"),
    activeProposalId: uuid("active_proposal_id"),
    metadataJson: jsonb("metadata_json").$type<unknown>(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("agent_messages_conversation_created_idx").on(
      table.conversationId,
      table.createdAt,
    ),
    index("agent_messages_user_created_idx").on(table.userId, table.createdAt),
    index("agent_messages_trace_id_idx").on(table.traceId),
    index("agent_messages_turn_id_idx").on(table.turnId),
    index("agent_messages_conversation_turn_idx").on(
      table.conversationId,
      table.turnId,
      table.createdAt,
    ),
    check(
      "agent_messages_role_check",
      sql`${table.role} IN ('user','assistant','tool')`,
    ),
  ],
);

export const agentCandidateRegistries = pgTable(
  "agent_candidate_registries",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    conversationId: uuid("conversation_id")
      .notNull()
      .references(() => agentConversations.id, { onDelete: "cascade" }),
    messageId: uuid("message_id").references(() => agentMessages.id, {
      onDelete: "set null",
    }),
    traceId: text("trace_id"),
    turnId: uuid("turn_id"),
    actionCallId: uuid("action_call_id"),
    searchRef: text("search_ref").notNull(),
    actionId: text("action_id").notNull(),
    candidateCount: integer("candidate_count").notNull(),
    groupCount: integer("group_count").notNull(),
    threshold: numeric("threshold"),
    registryJson: jsonb("registry_json").$type<JsonObject>().notNull(),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("agent_candidate_registries_user_search_ref_unique").on(
      table.userId,
      table.searchRef,
    ),
    index("agent_candidate_registries_conversation_created_idx").on(
      table.conversationId,
      sql`${table.createdAt} DESC`,
    ),
    index("agent_candidate_registries_turn_id_idx").on(table.turnId),
    index("agent_candidate_registries_trace_id_idx").on(table.traceId),
  ],
);

export const agentTurnTelemetry = pgTable(
  "agent_turn_telemetry",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    conversationId: uuid("conversation_id").references(
      () => agentConversations.id,
      { onDelete: "set null" },
    ),
    traceId: text("trace_id").notNull(),
    turnId: uuid("turn_id").notNull(),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    inputMode: text("input_mode"),
    source: text("source"),
    activeProposalId: uuid("active_proposal_id"),
    model: text("model"),
    inputText: text("input_text"),
    assistantText: text("assistant_text"),
    resultKind: text("result_kind"),
    stopReason: text("stop_reason"),
    iterationCount: integer("iteration_count").notNull().default(0),
    toolCallCount: integer("tool_call_count").notNull().default(0),
    promptChars: integer("prompt_chars"),
    messagesJsonChars: integer("messages_json_chars"),
    toolsJsonChars: integer("tools_json_chars"),
    requestPayloadChars: integer("request_payload_chars"),
    promptTokens: integer("prompt_tokens"),
    completionTokens: integer("completion_tokens"),
    totalTokens: integer("total_tokens"),
    reasoningTokens: integer("reasoning_tokens"),
    providerCostAmount: numeric("provider_cost_amount", {
      precision: 12,
      scale: 6,
    }),
    estimatedCostAmount: numeric("estimated_cost_amount", {
      precision: 12,
      scale: 6,
    }),
    costCurrency: text("cost_currency"),
    costSource: text("cost_source"),
    pricingSnapshotJson: jsonb("pricing_snapshot_json")
      .$type<Record<string, unknown>>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    firstByteMs: integer("first_byte_ms"),
    firstToolCallMs: integer("first_tool_call_ms"),
    largestStreamGapMs: integer("largest_stream_gap_ms"),
    llmMs: integer("llm_ms"),
    actionMs: integer("action_ms"),
    totalMs: integer("total_ms"),
    status: text("status").notNull().default("success"),
    errorCode: text("error_code"),
    errorMessage: text("error_message"),
    metadataJson: jsonb("metadata_json")
      .$type<Record<string, unknown>>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    completedAt: timestamp("completed_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    uniqueIndex("agent_turn_telemetry_turn_id_unique").on(table.turnId),
    index("agent_turn_telemetry_created_at_idx").on(
      sql`${table.createdAt} DESC`,
    ),
    index("agent_turn_telemetry_trace_id_idx").on(table.traceId),
    index("agent_turn_telemetry_user_created_at_idx").on(
      table.userId,
      sql`${table.createdAt} DESC`,
    ),
    index("agent_turn_telemetry_conversation_created_at_idx").on(
      table.conversationId,
      sql`${table.createdAt} DESC`,
    ),
  ],
);

export const agentToolCallTelemetry = pgTable(
  "agent_tool_call_telemetry",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    agentTurnId: uuid("agent_turn_id").references(
      () => agentTurnTelemetry.id,
      { onDelete: "set null" },
    ),
    conversationId: uuid("conversation_id").references(
      () => agentConversations.id,
      { onDelete: "set null" },
    ),
    traceId: text("trace_id").notNull(),
    turnId: uuid("turn_id"),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    toolCallId: text("tool_call_id"),
    actionCallId: uuid("action_call_id"),
    actionId: text("action_id").notNull(),
    argumentsJson: jsonb("arguments_json").$type<unknown>(),
    resultSummaryJson: jsonb("result_summary_json").$type<unknown>(),
    status: text("status").notNull(),
    errorMessage: text("error_message"),
    startedAt: timestamp("started_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
    completedAt: timestamp("completed_at", { withTimezone: true }),
    durationMs: integer("duration_ms"),
    metadataJson: jsonb("metadata_json")
      .$type<Record<string, unknown>>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("agent_tool_call_telemetry_created_at_idx").on(
      sql`${table.createdAt} DESC`,
    ),
    index("agent_tool_call_telemetry_trace_id_idx").on(table.traceId),
    index("agent_tool_call_telemetry_turn_id_idx").on(table.turnId),
    index("agent_tool_call_telemetry_action_call_id_idx").on(
      table.actionCallId,
    ),
    index("agent_tool_call_telemetry_user_created_at_idx").on(
      table.userId,
      sql`${table.createdAt} DESC`,
    ),
  ],
);

export const llmProviderCalls = pgTable(
  "llm_provider_calls",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    traceId: text("trace_id").notNull(),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    conversationId: uuid("conversation_id").references(
      () => agentConversations.id,
      { onDelete: "set null" },
    ),
    agentTurnId: uuid("agent_turn_id").references(
      () => agentTurnTelemetry.id,
      { onDelete: "set null" },
    ),
    turnId: uuid("turn_id"),
    actionCallId: uuid("action_call_id"),
    featureSurface: text("feature_surface").notNull(),
    provider: text("provider").notNull(),
    providerRequestId: text("provider_request_id"),
    providerGenerationId: text("provider_generation_id"),
    requestedModel: text("requested_model").notNull(),
    servedModel: text("served_model"),
    routingJson: jsonb("routing_json").$type<unknown>(),
    inputMode: text("input_mode"),
    promptTokens: integer("prompt_tokens"),
    completionTokens: integer("completion_tokens"),
    totalTokens: integer("total_tokens"),
    reasoningTokens: integer("reasoning_tokens"),
    cachedInputTokens: integer("cached_input_tokens"),
    audioTokens: integer("audio_tokens"),
    imageTokens: integer("image_tokens"),
    providerCostAmount: numeric("provider_cost_amount", {
      precision: 12,
      scale: 6,
    }),
    estimatedCostAmount: numeric("estimated_cost_amount", {
      precision: 12,
      scale: 6,
    }),
    costCurrency: text("cost_currency"),
    costSource: text("cost_source").notNull().default("unknown"),
    inputTokenUnitPrice: numeric("input_token_unit_price", {
      precision: 12,
      scale: 8,
    }),
    outputTokenUnitPrice: numeric("output_token_unit_price", {
      precision: 12,
      scale: 8,
    }),
    reasoningTokenUnitPrice: numeric("reasoning_token_unit_price", {
      precision: 12,
      scale: 8,
    }),
    cachedInputTokenUnitPrice: numeric("cached_input_token_unit_price", {
      precision: 12,
      scale: 8,
    }),
    audioTokenUnitPrice: numeric("audio_token_unit_price", {
      precision: 12,
      scale: 8,
    }),
    imageTokenUnitPrice: numeric("image_token_unit_price", {
      precision: 12,
      scale: 8,
    }),
    pricingSource: text("pricing_source"),
    pricingVersion: text("pricing_version"),
    pricingEffectiveAt: timestamp("pricing_effective_at", {
      withTimezone: true,
    }),
    status: text("status").notNull(),
    errorCode: text("error_code"),
    errorMessage: text("error_message"),
    durationMs: integer("duration_ms"),
    metadataJson: jsonb("metadata_json")
      .$type<Record<string, unknown>>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("llm_provider_calls_created_at_idx").on(
      sql`${table.createdAt} DESC`,
    ),
    index("llm_provider_calls_trace_id_idx").on(table.traceId),
    index("llm_provider_calls_user_created_at_idx").on(
      table.userId,
      sql`${table.createdAt} DESC`,
    ),
    index("llm_provider_calls_conversation_created_at_idx").on(
      table.conversationId,
      sql`${table.createdAt} DESC`,
    ),
    index("llm_provider_calls_turn_id_idx").on(table.turnId),
    index("llm_provider_calls_model_created_at_idx").on(
      table.requestedModel,
      sql`${table.createdAt} DESC`,
    ),
  ],
);

export const transcriptionRecords = pgTable(
  "transcription_records",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    traceId: text("trace_id").notNull(),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    conversationId: uuid("conversation_id").references(
      () => agentConversations.id,
      { onDelete: "set null" },
    ),
    turnId: uuid("turn_id"),
    surface: text("surface").notNull(),
    provider: text("provider"),
    model: text("model"),
    language: text("language"),
    audioMimeType: text("audio_mime_type"),
    audioBytes: integer("audio_bytes"),
    audioDurationMs: integer("audio_duration_ms"),
    transcriptText: text("transcript_text"),
    transcriptLength: integer("transcript_length").notNull().default(0),
    durationMs: integer("duration_ms"),
    status: text("status").notNull(),
    errorCode: text("error_code"),
    errorMessage: text("error_message"),
    downstreamResultKind: text("downstream_result_kind"),
    metadataJson: jsonb("metadata_json")
      .$type<Record<string, unknown>>()
      .notNull()
      .default(sql`'{}'::jsonb`),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("transcription_records_created_at_idx").on(
      sql`${table.createdAt} DESC`,
    ),
    index("transcription_records_trace_id_idx").on(table.traceId),
    index("transcription_records_user_created_at_idx").on(
      table.userId,
      sql`${table.createdAt} DESC`,
    ),
    index("transcription_records_conversation_created_at_idx").on(
      table.conversationId,
      sql`${table.createdAt} DESC`,
    ),
    index("transcription_records_turn_id_idx").on(table.turnId),
  ],
);

export const agentConnections = pgTable("agent_connections", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  source: text("source").notNull(),
  scopes: text("scopes").array().notNull(),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const outboxJobs = pgTable("outbox_jobs", {
  id: uuid("id").primaryKey().defaultRandom(),
  jobType: text("job_type").notNull(),
  payloadJson: jsonb("payload_json").$type<JsonObject>().notNull(),
  status: text("status").notNull().default("pending"),
  attempts: integer("attempts").notNull().default(0),
  runAfter: timestamp("run_after", { withTimezone: true })
    .notNull()
    .defaultNow(),
  createdAt: timestamp("created_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .notNull()
    .defaultNow(),
});

export const foodAliases = pgTable(
  "food_aliases",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    userId: uuid("user_id").references(() => users.id, { onDelete: "cascade" }),
    aliasText: text("alias_text").notNull(),
    normalizedAlias: text("normalized_alias").notNull(),
    locale: text("locale").notNull().default("und"),
    canonicalEnglishName: text("canonical_english_name").notNull(),
    foodItemId: uuid("food_item_id").references(() => foodItems.id, {
      onDelete: "set null",
    }),
    source: text("source").notNull(),
    confidence: numeric("confidence", { precision: 5, scale: 4 })
      .notNull()
      .default("1"),
    createdAt: timestamp("created_at", { withTimezone: true })
      .notNull()
      .defaultNow(),
  },
  (table) => [
    index("food_aliases_normalized_alias_idx").on(table.normalizedAlias),
  ],
);

export const usersRelations = relations(users, ({ one, many }) => ({
  credential: one(userCredentials),
  identities: many(authIdentities),
  sessions: many(authSessions),
  meals: many(meals),
  templates: many(mealTemplates),
  memories: many(foodMemories),
  actionCalls: many(actionCalls),
  auditEvents: many(auditEvents),
  telemetryEvents: many(telemetryEvents),
  llmRuns: many(llmRuns),
  agentTurns: many(agentTurnTelemetry),
  llmProviderCalls: many(llmProviderCalls),
  transcriptionRecords: many(transcriptionRecords),
  foodSearchEvents: many(foodSearchEvents),
  agentConversations: many(agentConversations),
  agentMessages: many(agentMessages),
  agentCandidateRegistries: many(agentCandidateRegistries),
}));

export const foodItemsRelations = relations(foodItems, ({ one, many }) => ({
  user: one(users, { fields: [foodItems.userId], references: [users.id] }),
  portions: many(foodPortions),
  searchDocument: one(foodSearchDocuments),
  quality: one(foodItemQuality),
  normalizedSearchDocument: one(foodNormalizedSearchDocuments),
  embeddings: many(foodItemEmbeddings),
}));

export const mealsRelations = relations(meals, ({ one, many }) => ({
  user: one(users, { fields: [meals.userId], references: [users.id] }),
  proposal: one(mealProposals, {
    fields: [meals.proposalId],
    references: [mealProposals.id],
  }),
  items: many(mealItems),
}));

export const mealProposalsRelations = relations(
  mealProposals,
  ({ one, many }) => ({
    user: one(users, {
      fields: [mealProposals.userId],
      references: [users.id],
    }),
    items: many(mealProposalItems),
  }),
);

export const mealTemplatesRelations = relations(
  mealTemplates,
  ({ one, many }) => ({
    user: one(users, {
      fields: [mealTemplates.userId],
      references: [users.id],
    }),
    items: many(mealTemplateItems),
    aliases: many(foodMemories),
  }),
);

export const foodMemoriesRelations = relations(foodMemories, ({ one }) => ({
  user: one(users, { fields: [foodMemories.userId], references: [users.id] }),
  template: one(mealTemplates, {
    fields: [foodMemories.mealTemplateId],
    references: [mealTemplates.id],
  }),
}));

export const agentConversationsRelations = relations(
  agentConversations,
  ({ one, many }) => ({
    user: one(users, {
      fields: [agentConversations.userId],
      references: [users.id],
    }),
    messages: many(agentMessages),
    turns: many(agentTurnTelemetry),
    toolCalls: many(agentToolCallTelemetry),
    providerCalls: many(llmProviderCalls),
    transcriptionRecords: many(transcriptionRecords),
    candidateRegistries: many(agentCandidateRegistries),
  }),
);

export const agentMessagesRelations = relations(
  agentMessages,
  ({ one, many }) => ({
    user: one(users, {
      fields: [agentMessages.userId],
      references: [users.id],
    }),
    conversation: one(agentConversations, {
      fields: [agentMessages.conversationId],
      references: [agentConversations.id],
    }),
    candidateRegistries: many(agentCandidateRegistries),
  }),
);

export const agentCandidateRegistriesRelations = relations(
  agentCandidateRegistries,
  ({ one }) => ({
    user: one(users, {
      fields: [agentCandidateRegistries.userId],
      references: [users.id],
    }),
    conversation: one(agentConversations, {
      fields: [agentCandidateRegistries.conversationId],
      references: [agentConversations.id],
    }),
    message: one(agentMessages, {
      fields: [agentCandidateRegistries.messageId],
      references: [agentMessages.id],
    }),
  }),
);

export const agentTurnTelemetryRelations = relations(
  agentTurnTelemetry,
  ({ one, many }) => ({
    user: one(users, {
      fields: [agentTurnTelemetry.userId],
      references: [users.id],
    }),
    conversation: one(agentConversations, {
      fields: [agentTurnTelemetry.conversationId],
      references: [agentConversations.id],
    }),
    toolCalls: many(agentToolCallTelemetry),
    providerCalls: many(llmProviderCalls),
  }),
);

export const agentToolCallTelemetryRelations = relations(
  agentToolCallTelemetry,
  ({ one }) => ({
    user: one(users, {
      fields: [agentToolCallTelemetry.userId],
      references: [users.id],
    }),
    conversation: one(agentConversations, {
      fields: [agentToolCallTelemetry.conversationId],
      references: [agentConversations.id],
    }),
    turn: one(agentTurnTelemetry, {
      fields: [agentToolCallTelemetry.agentTurnId],
      references: [agentTurnTelemetry.id],
    }),
  }),
);

export const llmProviderCallsRelations = relations(
  llmProviderCalls,
  ({ one }) => ({
    user: one(users, {
      fields: [llmProviderCalls.userId],
      references: [users.id],
    }),
    conversation: one(agentConversations, {
      fields: [llmProviderCalls.conversationId],
      references: [agentConversations.id],
    }),
    turn: one(agentTurnTelemetry, {
      fields: [llmProviderCalls.agentTurnId],
      references: [agentTurnTelemetry.id],
    }),
  }),
);

export const transcriptionRecordsRelations = relations(
  transcriptionRecords,
  ({ one }) => ({
    user: one(users, {
      fields: [transcriptionRecords.userId],
      references: [users.id],
    }),
    conversation: one(agentConversations, {
      fields: [transcriptionRecords.conversationId],
      references: [agentConversations.id],
    }),
  }),
);
