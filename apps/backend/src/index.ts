import { serve } from "@hono/node-server";
import { ActionExecutor } from "./actions/executor.js";
import { AuthService } from "./auth/service.js";
import { loadConfig } from "./config/env.js";
import { OpenRouterEmbeddingProvider } from "./embeddings/provider.js";
import { createApp } from "./http/app.js";
import { MemoryRetrievalService } from "./memory/retrieval.js";
import {
  DeterministicFoodTextExtractor,
  FoodResolver,
  LocalFoodDataProvider,
} from "./nutrition/foodResolver.js";
import { ResolverNutritionProvider } from "./nutrition/provider.js";
import { createLocalRunLogger } from "./observability/localRunLogger.js";
import { PostgresRepository } from "./repository/postgres.js";
import { TypesenseFoodSearch } from "./repository/typesenseFoodSearch.js";
import { RemoteSpeechToTextProvider } from "./stt/speechToTextProvider.js";

const config = loadConfig();
const repository = new PostgresRepository(config.DATABASE_URL);
const foodSearchBackend = config.FOOD_SEARCH_BACKEND === "typesense"
  ? new TypesenseFoodSearch({
      protocol: config.TYPESENSE_PROTOCOL,
      host: config.TYPESENSE_HOST,
      port: config.TYPESENSE_PORT,
      apiKey: config.TYPESENSE_API_KEY,
      collection: config.TYPESENSE_COLLECTION,
    })
  : repository;
const authService = new AuthService(config, repository);
const embeddingProvider = config.EMBEDDINGS_ENABLED
  ? new OpenRouterEmbeddingProvider(
      config.OPENROUTER_API_KEY,
      config.EMBEDDING_MODEL,
      config.EMBEDDING_DIMENSIONS,
    )
  : undefined;
const foodResolver = new FoodResolver(
  new DeterministicFoodTextExtractor(),
  new LocalFoodDataProvider(foodSearchBackend),
  config.FOOD_RESOLVER_MIN_CONFIDENCE,
);
const nutritionProvider = new ResolverNutritionProvider(foodResolver);
const memoryRetrievalService = new MemoryRetrievalService(
  repository,
  embeddingProvider,
);
const actionExecutor = new ActionExecutor(
  config,
  repository,
  nutritionProvider,
  memoryRetrievalService,
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
  runLogger,
});

serve({ fetch: app.fetch, port: config.PORT });
console.log(`Backend listening on ${config.APP_BASE_URL}`);
