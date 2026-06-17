import { ActionExecutor } from "../actions/executor.js";
import type { GoogleTokenVerifier } from "../auth/google.js";
import { AuthService } from "../auth/service.js";
import { loadConfig } from "../config/env.js";
import { createApp } from "../http/app.js";
import type { MealItem } from "@cal-tracker/contracts";
import {
  FoodResolver,
  LocalFoodDataProvider,
} from "../nutrition/foodResolver.js";
import { ResolverNutritionProvider } from "../nutrition/provider.js";
import { InMemoryRepository } from "../repository/inMemory.js";
import type {
  SpeechToTextInput,
  SpeechToTextProvider,
  TranscriptionResult,
} from "../stt/speechToTextProvider.js";
import type { ChatAgentProvider, AgentToolDecision } from "../agent/chatAgentProvider.js";
import type { UsualFoodDraftProvider } from "../agent/usualFoodDraftProvider.js";
import type { UsualMealDraftProvider } from "../agent/usualMealDraftProvider.js";
import type { LocalRunLogger } from "../observability/localRunLogger.js";
import { TelemetryService as DbTelemetryService } from "../telemetry/service.js";
import type { TelemetryService } from "../telemetry/telemetryService.js";
import { seedTestFoods } from "./foodFixtures.js";

export class FakeSpeechToTextProvider implements SpeechToTextProvider {
  readonly inputs: SpeechToTextInput[] = [];

  constructor(private readonly transcript = "fake transcript from test") {}

  async transcribe(input: SpeechToTextInput): Promise<TranscriptionResult> {
    this.inputs.push(input);
    return { text: this.transcript, provider: "test", model: "test-model" };
  }
}

export class FakeChatAgentProvider implements ChatAgentProvider {
  constructor(private readonly decision: AgentToolDecision) {}
  async runWithTools(): Promise<AgentToolDecision> {
    return this.decision;
  }
}

export const testBreadItem: MealItem = {
  name: "Bread",
  quantity: 100,
  unit: "g",
  calories: 265,
  proteinGrams: 9,
  carbsGrams: 49,
  fatGrams: 3.2,
  source: "test_fixture",
};

export function buildTestApp(options?: {
  agentProvider?: ChatAgentProvider;
  sttProvider?: SpeechToTextProvider;
  runLogger?: LocalRunLogger;
  googleTokenVerifier?: GoogleTokenVerifier;
  usualFoodDraftProvider?: UsualFoodDraftProvider;
  usualMealDraftProvider?: UsualMealDraftProvider;
  telemetryService?: TelemetryService;
}) {
  const config = loadConfig({ NODE_ENV: "test" } as NodeJS.ProcessEnv);
  const repository = InMemoryRepository.seeded();
  seedTestFoods(repository);
  const authService = new AuthService(config, repository, options?.googleTokenVerifier);
  const foodResolver = new FoodResolver(
    new LocalFoodDataProvider(repository, { allowSeededPortionFallback: true }),
    config.FOOD_RESOLVER_MIN_CONFIDENCE
  );
  const nutritionProvider = new ResolverNutritionProvider(foodResolver);
  const actionExecutor = new ActionExecutor(
    config,
    repository,
    nutritionProvider,
    undefined,
    options?.usualFoodDraftProvider,
    options?.usualMealDraftProvider,
  );
  const sttProvider = options?.sttProvider ?? new FakeSpeechToTextProvider();
  const defaultAgentProvider = new FakeChatAgentProvider({
    toolCalls: [
      {
        id: "call_default",
        type: "function",
        function: {
          name: "propose_meal_log",
          arguments: JSON.stringify({
            text: "usual breakfast",
            mentions: [
              {
                originalText: "100 grams of bread",
                canonicalName: "bread",
                canonicalEnglishName: "bread",
                language: "en",
                quantity: 100,
                unit: "g",
                rawUnitText: "grams",
                unitKind: "metric",
                confidence: 0.95,
              },
            ],
          }),
        },
      },
    ],
    rawResponse: {},
  });
  const agentProvider = options?.agentProvider ?? defaultAgentProvider;
  const app = createApp({ config, repository, authService, actionExecutor, sttProvider, agentProvider, runLogger: options?.runLogger, telemetryService: options?.telemetryService });
  const request = (input: string, init?: RequestInit) => Promise.resolve(app.request(input, init));
  const telemetry = new DbTelemetryService(repository, { enabled: true });
  return { app, request, config, repository, authService, actionExecutor, sttProvider, agentProvider, telemetry };
}

export async function createTestUsualBreakfastTemplate(
  request: (input: string, init?: RequestInit) => Promise<Response>,
  authHeader: Record<string, string>
) {
  const response = await request("http://localhost/v1/meal-templates", {
    method: "POST",
    headers: authHeader,
    body: JSON.stringify({
      title: "Usual breakfast",
      trustedAutoCommitEnabled: false,
      items: [testBreadItem],
      aliases: ["usual breakfast", "normal breakfast"]
    })
  });
  return response.json() as Promise<{ output: { template: { id: string; items: MealItem[]; aliases: string[] } } }>;
}

export async function loginAdmin(request: (input: string, init?: RequestInit) => Promise<Response>) {
  const response = await request("http://localhost/v1/admin/auth/login", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ username: "admin", password: "admin-password-123" })
  });
  const body = await response.json() as { accessToken: string; username: string };
  return {
    ...body,
    authHeader: { authorization: `Bearer ${body.accessToken}`, "content-type": "application/json" }
  };
}

export async function registerAndAuth(request: (input: string, init?: RequestInit) => Promise<Response>) {
  const response = await request("http://localhost/v1/auth/register", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: "test@example.com", password: "password123", displayName: "Test User" })
  });
  const body = await response.json() as { accessToken: string; refreshToken: string; user: { id: string } };
  return {
    ...body,
    authHeader: { authorization: `Bearer ${body.accessToken}`, "content-type": "application/json" }
  };
}
