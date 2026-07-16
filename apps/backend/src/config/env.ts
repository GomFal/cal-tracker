import { z } from "zod";

const stringBooleanSchema = z.preprocess((value) => {
  if (typeof value !== "string") return value;
  if (["1", "true", "yes", "on"].includes(value.toLowerCase())) return true;
  if (["0", "false", "no", "off"].includes(value.toLowerCase())) return false;
  return value;
}, z.boolean());

const optionalSecretSchema = z.string().default("").refine((value) => value.length === 0 || value.length >= 32, {
  message: "Secret must be empty or at least 32 characters",
});

const TEST_ADMIN_PANEL_PASSWORD_HASH = "$argon2id$v=19$m=19456,t=2,p=1$P6DHHU0m9ReHAxn/p7Rm8g$W8oR3o0dv31YYBjJq6psrXd7M+XgnritGIGsDnQUSXA";

const envSchema = z.object({
  DATABASE_URL: z.string().url(),
  JWT_ACCESS_SECRET: z.string().min(32),
  SESSION_TOKEN_PEPPER: z.string().min(32),
  GOOGLE_OAUTH_CLIENT_IDS: z.string().optional(),
  OAUTH_GOOGLE_SECRET: z.string().optional(),
  OPENROUTER_API_KEY: z.string().min(1),
  OPENROUTER_MODEL: z.string().min(1),
  OPENROUTER_PROVIDER_SORT: z.enum(["price", "throughput", "latency"]).default("latency"),
  OPENROUTER_PROVIDER_MAX_LATENCY_P50: z.coerce.number().positive().default(0.6),
  OPENROUTER_PROVIDER_MAX_LATENCY_P90: z.coerce.number().positive().default(1.5),
  OPENROUTER_PROVIDER_MAX_LATENCY_P99: z.coerce.number().positive().default(3),
  OPENROUTER_PROVIDER_MIN_THROUGHPUT_P50: z.coerce.number().positive().default(80),
  OPENROUTER_PROVIDER_MIN_THROUGHPUT_P90: z.coerce.number().positive().default(40),
  OPENROUTER_PROVIDER_REQUIRE_PARAMETERS: stringBooleanSchema.default(false),
  OPENROUTER_PROVIDER_ALLOW_FALLBACKS: stringBooleanSchema.default(true),
  STT_API_KEY: z.string().min(1),
  STT_MODEL: z.string().min(1).default("whisper-large-v3-turbo"),
  STT_BASE_URL: z.string().url().default("https://api.groq.com/openai/v1"),
  FOOD_RESOLVER_MIN_CONFIDENCE: z.coerce.number().min(0).max(1).default(0.75),
  RESEND_API_KEY: z.string().default(""),
  RESEND_FROM_EMAIL: z.string().default(""),
  AUTH_EMAIL_CONFIRMATION_TTL_MINUTES: z.coerce.number().int().min(5).max(1440).default(30),
  RATE_LIMIT_TRUST_PROXY_HEADERS: stringBooleanSchema.default(false),
  RATE_LIMIT_AUTH_IP_MAX: z.coerce.number().int().positive().default(10),
  RATE_LIMIT_AUTH_WINDOW_SECONDS: z.coerce.number().int().positive().default(60),
  RATE_LIMIT_EMAIL_RECIPIENT_MAX: z.coerce.number().int().positive().default(3),
  RATE_LIMIT_EMAIL_WINDOW_SECONDS: z.coerce.number().int().positive().default(3600),
  RATE_LIMIT_COST_OPERATIONS_ENABLED: stringBooleanSchema.default(true),
  RATE_LIMIT_COST_USER_MAX: z.coerce.number().int().positive().default(60),
  RATE_LIMIT_COST_IP_MAX: z.coerce.number().int().nonnegative().default(600),
  RATE_LIMIT_COST_GLOBAL_MAX: z.coerce.number().int().nonnegative().default(6000),
  RATE_LIMIT_COST_WINDOW_SECONDS: z.coerce.number().int().positive().default(3600),
  RATE_LIMIT_COST_USER_CONCURRENCY: z.coerce.number().int().positive().default(2),
  RATE_LIMIT_COST_GLOBAL_CONCURRENCY: z.coerce.number().int().nonnegative().default(50),
  RATE_LIMIT_CONCURRENCY_RETRY_AFTER_SECONDS: z.coerce.number().int().positive().default(5),
  RATE_LIMIT_EMERGENCY_RETRY_AFTER_SECONDS: z.coerce.number().int().positive().default(60),
  RATE_LIMIT_ALERT_PERCENT: z.coerce.number().int().min(1).max(100).default(80),
  RATE_LIMIT_MAX_BUCKETS: z.coerce.number().int().positive().default(100_000),
  MOBILE_ANDROID_APP_LINK_PACKAGES: z.string().default("app.bettercalories,app.bettercalories.dev"),
  MOBILE_ANDROID_SHA256_CERT_FINGERPRINTS: z.string().default(""),
  MOBILE_IOS_APP_IDS: z.string().default(""),
  EMBEDDINGS_ENABLED: stringBooleanSchema.default(false),
  EMBEDDING_PROVIDER: z.string().min(1).default("openrouter"),
  EMBEDDING_MODEL: z.string().min(1).default("baai/bge-m3"),
  EMBEDDING_DIMENSIONS: z.coerce.number().int().positive().default(1024),
  APP_BASE_URL: z.string().url(),
  CORS_ALLOWED_ORIGINS: z.string().min(1),
  TRUSTED_AUTO_COMMIT_THRESHOLD: z.coerce.number().min(0).max(1).default(0.92),
  FOOD_NORMALIZED_SEARCH_ENABLED: stringBooleanSchema.default(false),
  FOOD_NORMALIZED_SEARCH_SCOPE: z.enum(["sample", "full"]).default("sample"),
  FOOD_NORMALIZED_SEARCH_SAMPLE_SET: z.string().min(1).default("normalized_search_v1"),
  AGENT_RUN_LOG_ENABLED: stringBooleanSchema.optional(),
  ADMIN_EMAILS: z.string().default(""),
  ADMIN_PANEL_USERNAME: z.string().max(120).default(""),
  ADMIN_PANEL_PASSWORD_HASH: z.string().default(""),
  ADMIN_PANEL_TOKEN_SECRET: optionalSecretSchema,
  ADMIN_PANEL_TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).max(86_400).default(30 * 60),
  AGENT_RUN_LOG_DIR: z.string().min(1).default("../../logs/agent-runs"),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_SCHEMA: z.string().regex(/^[A-Za-z_][A-Za-z0-9_]*$/).default("public"),
  NODE_ENV: z.string().default("development")
});

export type AppConfig = Omit<z.infer<typeof envSchema>, "AGENT_RUN_LOG_ENABLED" | "OAUTH_GOOGLE_SECRET" | "GOOGLE_OAUTH_CLIENT_IDS" | "ADMIN_EMAILS"> & {
  AGENT_RUN_LOG_ENABLED: boolean;
  GOOGLE_OAUTH_CLIENT_IDS: string;
  ADMIN_EMAILS: string;
  corsAllowedOrigins: string[];
  adminEmails: string[];
  adminPanelEnabled: boolean;
  adminPanelUsername: string;
  mobileAndroidAppLinkPackages: string[];
  mobileAndroidSha256CertFingerprints: string[];
  mobileIosAppIds: string[];
};

export function loadConfig(input: NodeJS.ProcessEnv = process.env): AppConfig {
  const isTest = input.NODE_ENV === "test";
  const defaults = isTest
    ? {
        DATABASE_URL: "postgres://cal_tracker:cal_tracker@localhost:5432/cal_tracker",
        JWT_ACCESS_SECRET: "test-access-secret-with-more-than-32-characters",
        SESSION_TOKEN_PEPPER: "test-session-pepper-with-more-than-32-characters",
        GOOGLE_OAUTH_CLIENT_IDS: "test-google-client-id",
        OPENROUTER_API_KEY: "test-openrouter-key",
        OPENROUTER_MODEL: "test-model",
        OPENROUTER_PROVIDER_SORT: "latency",
        OPENROUTER_PROVIDER_MAX_LATENCY_P50: "0.6",
        OPENROUTER_PROVIDER_MAX_LATENCY_P90: "1.5",
        OPENROUTER_PROVIDER_MAX_LATENCY_P99: "3",
        OPENROUTER_PROVIDER_MIN_THROUGHPUT_P50: "80",
        OPENROUTER_PROVIDER_MIN_THROUGHPUT_P90: "40",
        OPENROUTER_PROVIDER_REQUIRE_PARAMETERS: "false",
        OPENROUTER_PROVIDER_ALLOW_FALLBACKS: "true",
        STT_API_KEY: "test-stt-key",
        STT_MODEL: "test-stt-model",
        STT_BASE_URL: "http://localhost:9999",
        FOOD_RESOLVER_MIN_CONFIDENCE: "0.75",
        RESEND_API_KEY: "",
        RESEND_FROM_EMAIL: "BetterCalories <auth@bettercalories.test>",
        AUTH_EMAIL_CONFIRMATION_TTL_MINUTES: "30",
        RATE_LIMIT_TRUST_PROXY_HEADERS: "false",
        RATE_LIMIT_AUTH_IP_MAX: "10",
        RATE_LIMIT_AUTH_WINDOW_SECONDS: "60",
        RATE_LIMIT_EMAIL_RECIPIENT_MAX: "3",
        RATE_LIMIT_EMAIL_WINDOW_SECONDS: "3600",
        RATE_LIMIT_COST_OPERATIONS_ENABLED: "true",
        RATE_LIMIT_COST_USER_MAX: "60",
        RATE_LIMIT_COST_IP_MAX: "600",
        RATE_LIMIT_COST_GLOBAL_MAX: "6000",
        RATE_LIMIT_COST_WINDOW_SECONDS: "3600",
        RATE_LIMIT_COST_USER_CONCURRENCY: "2",
        RATE_LIMIT_COST_GLOBAL_CONCURRENCY: "50",
        RATE_LIMIT_CONCURRENCY_RETRY_AFTER_SECONDS: "5",
        RATE_LIMIT_EMERGENCY_RETRY_AFTER_SECONDS: "60",
        RATE_LIMIT_ALERT_PERCENT: "80",
        RATE_LIMIT_MAX_BUCKETS: "100000",
        MOBILE_ANDROID_APP_LINK_PACKAGES: "app.bettercalories,app.bettercalories.dev",
        MOBILE_ANDROID_SHA256_CERT_FINGERPRINTS: "",
        MOBILE_IOS_APP_IDS: "",
        EMBEDDINGS_ENABLED: "false",
        EMBEDDING_PROVIDER: "openrouter",
        EMBEDDING_MODEL: "baai/bge-m3",
        EMBEDDING_DIMENSIONS: "1024",
        APP_BASE_URL: "http://localhost:3000",
        CORS_ALLOWED_ORIGINS: "http://localhost:3000",
        TRUSTED_AUTO_COMMIT_THRESHOLD: "0.92",
        FOOD_NORMALIZED_SEARCH_ENABLED: "false",
        FOOD_NORMALIZED_SEARCH_SCOPE: "sample",
        FOOD_NORMALIZED_SEARCH_SAMPLE_SET: "normalized_search_v1",
        AGENT_RUN_LOG_ENABLED: "false",
        AGENT_RUN_LOG_DIR: "../../logs/agent-runs",
        ADMIN_EMAILS: "admin@example.com",
        ADMIN_PANEL_USERNAME: "admin",
        ADMIN_PANEL_PASSWORD_HASH: TEST_ADMIN_PANEL_PASSWORD_HASH,
        ADMIN_PANEL_TOKEN_SECRET: "test-admin-panel-secret-with-more-than-32-characters",
        ADMIN_PANEL_TOKEN_TTL_SECONDS: "1800",
        PORT: "3000",
        DATABASE_SCHEMA: "public",
        NODE_ENV: "test"
      }
    : {};

  const parsed = envSchema.parse({ ...defaults, ...input });
  const adminPanelValues = [
    parsed.ADMIN_PANEL_USERNAME,
    parsed.ADMIN_PANEL_PASSWORD_HASH,
    parsed.ADMIN_PANEL_TOKEN_SECRET,
  ];
  const adminPanelEnabled = adminPanelValues.every((value) => value.trim().length > 0);
  if (!adminPanelEnabled && adminPanelValues.some((value) => value.trim().length > 0)) {
    throw new Error(
      "ADMIN_PANEL_USERNAME, ADMIN_PANEL_PASSWORD_HASH, and ADMIN_PANEL_TOKEN_SECRET must be set together.",
    );
  }
  if (parsed.NODE_ENV === "production" && (!parsed.RESEND_API_KEY.trim() || !parsed.RESEND_FROM_EMAIL.trim())) {
    throw new Error("RESEND_API_KEY and RESEND_FROM_EMAIL must be set in production.");
  }
  const databaseUrl = withSearchPath(parsed.DATABASE_URL, parsed.DATABASE_SCHEMA);
  return {
    ...parsed,
    DATABASE_URL: databaseUrl,
    GOOGLE_OAUTH_CLIENT_IDS: parsed.GOOGLE_OAUTH_CLIENT_IDS ?? parsed.OAUTH_GOOGLE_SECRET ?? "",
    AGENT_RUN_LOG_ENABLED:
      parsed.AGENT_RUN_LOG_ENABLED ??
      (parsed.NODE_ENV !== "test" && parsed.NODE_ENV !== "production"),
    ADMIN_EMAILS: parsed.ADMIN_EMAILS,
    corsAllowedOrigins: parsed.CORS_ALLOWED_ORIGINS.split(",").map((origin) => origin.trim()),
    adminEmails: parsed.ADMIN_EMAILS.split(",").map((email) => email.trim().toLowerCase()).filter(Boolean),
    adminPanelEnabled,
    adminPanelUsername: parsed.ADMIN_PANEL_USERNAME.trim().toLowerCase(),
    mobileAndroidAppLinkPackages: splitCsv(parsed.MOBILE_ANDROID_APP_LINK_PACKAGES),
    mobileAndroidSha256CertFingerprints: splitCsv(parsed.MOBILE_ANDROID_SHA256_CERT_FINGERPRINTS),
    mobileIosAppIds: splitCsv(parsed.MOBILE_IOS_APP_IDS)
  };
}

function splitCsv(value: string): string[] {
  return value.split(",").map((entry) => entry.trim()).filter(Boolean);
}

function withSearchPath(databaseUrl: string, schema: string): string {
  if (schema === "public") return databaseUrl;
  const url = new URL(databaseUrl);
  url.searchParams.set("options", `-c search_path=${schema},public`);
  return url.toString();
}
