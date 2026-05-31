import { serve } from "@hono/node-server";
import { ActionExecutor } from "./actions/executor.js";
import { AuthService } from "./auth/service.js";
import { loadConfig } from "./config/env.js";
import { OpenRouterEmbeddingProvider } from "./embeddings/provider.js";
import {
  RemoteChatAgentProvider,
} from "./agent/chatAgentProvider.js";
import {
  ToolCallingUsualFoodDraftProvider,
} from "./agent/usualFoodDraftProvider.js";
import {
  ToolCallingUsualMealDraftProvider,
} from "./agent/usualMealDraftProvider.js";
import { createApp } from "./http/app.js";
import { MemoryRetrievalService } from "./memory/retrieval.js";
import {
  FoodResolver,
  LocalFoodDataProvider,
} from "./nutrition/foodResolver.js";
import { ResolverNutritionProvider } from "./nutrition/provider.js";
import { createLocalRunLogger } from "./observability/localRunLogger.js";
import { PostgresRepository } from "./repository/postgres.js";
import { RemoteSpeechToTextProvider } from "./stt/speechToTextProvider.js";

const config = loadConfig();
const repository = new PostgresRepository(config.DATABASE_URL);
const authService = new AuthService(config, repository);
const embeddingProvider = config.EMBEDDINGS_ENABLED
  ? new OpenRouterEmbeddingProvider(
      config.OPENROUTER_API_KEY,
      config.EMBEDDING_MODEL,
      config.EMBEDDING_DIMENSIONS,
    )
  : undefined;
const foodResolver = new FoodResolver(
  new LocalFoodDataProvider(repository),
  config.FOOD_RESOLVER_MIN_CONFIDENCE,
);
const nutritionProvider = new ResolverNutritionProvider(foodResolver);
const agentProvider = new RemoteChatAgentProvider(
  config.OPENROUTER_API_KEY,
  "https://openrouter.ai/api/v1",
  10000,
  {
    sort: config.OPENROUTER_PROVIDER_SORT,
    preferred_max_latency: {
      p50: config.OPENROUTER_PROVIDER_MAX_LATENCY_P50,
      p90: config.OPENROUTER_PROVIDER_MAX_LATENCY_P90,
      p99: config.OPENROUTER_PROVIDER_MAX_LATENCY_P99,
    },
    preferred_min_throughput: {
      p50: config.OPENROUTER_PROVIDER_MIN_THROUGHPUT_P50,
      p90: config.OPENROUTER_PROVIDER_MIN_THROUGHPUT_P90,
    },
    require_parameters: config.OPENROUTER_PROVIDER_REQUIRE_PARAMETERS,
    allow_fallbacks: config.OPENROUTER_PROVIDER_ALLOW_FALLBACKS,
  },
);
const memoryRetrievalService = new MemoryRetrievalService(
  repository,
  embeddingProvider,
);
const actionExecutor = new ActionExecutor(
  config,
  repository,
  nutritionProvider,
  memoryRetrievalService,
  new ToolCallingUsualFoodDraftProvider(agentProvider, config.OPENROUTER_MODEL),
  new ToolCallingUsualMealDraftProvider(agentProvider, config.OPENROUTER_MODEL),
);
const sttProvider = new RemoteSpeechToTextProvider(
  config.STT_API_KEY,
  config.STT_MODEL,
  config.STT_BASE_URL,
);
const runLogger = createLocalRunLogger({
  enabled: config.AGENT_RUN_LOG_ENABLED,
  directory: config.AGENT_RUN_LOG_DIR,
});
const app = createApp({
  config,
  repository,
  authService,
  actionExecutor,
  sttProvider,
  agentProvider,
  runLogger,
});

serve({ fetch: app.fetch, port: config.PORT });
console.log(`Backend listening on ${config.APP_BASE_URL}`);
