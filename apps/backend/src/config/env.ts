import { z } from "zod";

const stringBooleanSchema = z.preprocess((value) => {
  if (typeof value !== "string") return value;
  if (["1", "true", "yes", "on"].includes(value.toLowerCase())) return true;
  if (["0", "false", "no", "off"].includes(value.toLowerCase())) return false;
  return value;
}, z.boolean());

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
  FOOD_SEARCH_BACKEND: z.enum(["postgres", "typesense"]).default("postgres"),
  TYPESENSE_PROTOCOL: z.enum(["http", "https"]).default("http"),
  TYPESENSE_HOST: z.string().min(1).default("localhost"),
  TYPESENSE_PORT: z.coerce.number().int().positive().default(8108),
  TYPESENSE_API_KEY: z.string().min(1).default("xyz"),
  TYPESENSE_COLLECTION: z.string().min(1).default("food_items_demo_v1"),
  EMBEDDINGS_ENABLED: stringBooleanSchema.default(false),
  EMBEDDING_PROVIDER: z.string().min(1).default("openrouter"),
  EMBEDDING_MODEL: z.string().min(1).default("baai/bge-m3"),
  EMBEDDING_DIMENSIONS: z.coerce.number().int().positive().default(1024),
  APP_BASE_URL: z.string().url(),
  CORS_ALLOWED_ORIGINS: z.string().min(1),
  TRUSTED_AUTO_COMMIT_THRESHOLD: z.coerce.number().min(0).max(1).default(0.92),
  AGENT_RUN_LOG_ENABLED: stringBooleanSchema.optional(),
  AGENT_RUN_LOG_DIR: z.string().min(1).default("../../logs/agent-runs"),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_SCHEMA: z.string().regex(/^[A-Za-z_][A-Za-z0-9_]*$/).default("public"),
  NODE_ENV: z.string().default("development")
});

export type AppConfig = Omit<z.infer<typeof envSchema>, "AGENT_RUN_LOG_ENABLED" | "OAUTH_GOOGLE_SECRET" | "GOOGLE_OAUTH_CLIENT_IDS"> & {
  AGENT_RUN_LOG_ENABLED: boolean;
  GOOGLE_OAUTH_CLIENT_IDS: string;
  corsAllowedOrigins: string[];
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
        FOOD_SEARCH_BACKEND: "postgres",
        TYPESENSE_PROTOCOL: "http",
        TYPESENSE_HOST: "localhost",
        TYPESENSE_PORT: "8108",
        TYPESENSE_API_KEY: "xyz",
        TYPESENSE_COLLECTION: "food_items_demo_v1",
        EMBEDDINGS_ENABLED: "false",
        EMBEDDING_PROVIDER: "openrouter",
        EMBEDDING_MODEL: "baai/bge-m3",
        EMBEDDING_DIMENSIONS: "1024",
        APP_BASE_URL: "http://localhost:3000",
        CORS_ALLOWED_ORIGINS: "http://localhost:3000",
        TRUSTED_AUTO_COMMIT_THRESHOLD: "0.92",
        AGENT_RUN_LOG_ENABLED: "false",
        AGENT_RUN_LOG_DIR: "../../logs/agent-runs",
        PORT: "3000",
        DATABASE_SCHEMA: "public",
        NODE_ENV: "test"
      }
    : {};

  const parsed = envSchema.parse({ ...defaults, ...input });
  const databaseUrl = withSearchPath(parsed.DATABASE_URL, parsed.DATABASE_SCHEMA);
  return {
    ...parsed,
    DATABASE_URL: databaseUrl,
    GOOGLE_OAUTH_CLIENT_IDS: parsed.GOOGLE_OAUTH_CLIENT_IDS ?? parsed.OAUTH_GOOGLE_SECRET ?? "",
    AGENT_RUN_LOG_ENABLED:
      parsed.AGENT_RUN_LOG_ENABLED ??
      (parsed.NODE_ENV !== "test" && parsed.NODE_ENV !== "production"),
    corsAllowedOrigins: parsed.CORS_ALLOWED_ORIGINS.split(",").map((origin) => origin.trim())
  };
}

function withSearchPath(databaseUrl: string, schema: string): string {
  if (schema === "public") return databaseUrl;
  const url = new URL(databaseUrl);
  url.searchParams.set("options", `-c search_path=${schema},public`);
  return url.toString();
}
