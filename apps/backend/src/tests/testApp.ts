import { ActionExecutor } from "../actions/executor.js";
import type {
  AuthEmailSender,
  EmailConfirmationInput,
  PasswordResetEmailInput,
} from "../auth/email.js";
import type { GoogleTokenVerifier } from "../auth/google.js";
import { AuthService } from "../auth/service.js";
import { loadConfig, type AppConfig } from "../config/env.js";
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
import {
  InMemoryAbuseProtection,
  type AbuseProtectionLogger,
} from "../security/abuseProtection.js";
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

export class FakeAuthEmailSender implements AuthEmailSender {
  readonly confirmations: EmailConfirmationInput[] = [];
  readonly passwordResets: PasswordResetEmailInput[] = [];

  async sendEmailConfirmation(input: EmailConfirmationInput): Promise<void> {
    this.confirmations.push(input);
  }

  async sendPasswordReset(input: PasswordResetEmailInput): Promise<void> {
    this.passwordResets.push(input);
  }

  latestConfirmationToken(): string {
    const latest = this.confirmations.at(-1);
    if (!latest) throw new Error("confirmation_email_not_sent");
    const token = new URL(latest.confirmationUrl).searchParams.get("token");
    if (!token) throw new Error("confirmation_email_token_missing");
    return token;
  }

  latestPasswordResetToken(): string {
    const latest = this.passwordResets.at(-1);
    if (!latest) throw new Error("password_reset_email_not_sent");
    const token = new URL(latest.resetUrl).searchParams.get("token");
    if (!token) throw new Error("password_reset_token_missing");
    return token;
  }
}

const authEmailSendersByRequest = new WeakMap<
  (input: string, init?: RequestInit) => Promise<Response>,
  FakeAuthEmailSender
>();

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
  authEmailSender?: AuthEmailSender;
  configOverrides?: Partial<AppConfig>;
  rateLimitNow?: () => number;
  abuseProtectionLogger?: AbuseProtectionLogger;
}) {
  const config = {
    ...loadConfig({ NODE_ENV: "test" } as NodeJS.ProcessEnv),
    ...options?.configOverrides,
  };
  const repository = InMemoryRepository.seeded();
  seedTestFoods(repository);
  const authEmailSender = options?.authEmailSender ?? new FakeAuthEmailSender();
  const authService = new AuthService(
    config,
    repository,
    options?.googleTokenVerifier,
    authEmailSender,
  );
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
  const abuseProtection = new InMemoryAbuseProtection(
    config,
    options?.rateLimitNow,
    options?.abuseProtectionLogger,
  );
  const app = createApp({ config, repository, authService, actionExecutor, sttProvider, agentProvider, runLogger: options?.runLogger, telemetryService: options?.telemetryService, abuseProtection });
  const request = (input: string, init?: RequestInit) => Promise.resolve(app.request(input, init));
  if (authEmailSender instanceof FakeAuthEmailSender) {
    authEmailSendersByRequest.set(request, authEmailSender);
  }
  const telemetry = new DbTelemetryService(repository, { enabled: true });
  return { app, request, config, repository, authService, authEmailSender, actionExecutor, sttProvider, agentProvider, telemetry };
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

export async function registerAndAuth(
  request: (input: string, init?: RequestInit) => Promise<Response>,
  input: { email?: string; password?: string; displayName?: string } = {},
) {
  const email = input.email ?? "test@example.com";
  const password = input.password ?? "password123";
  const displayName = input.displayName ?? "Test User";
  const response = await request("http://localhost/v1/auth/register", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, password, displayName })
  });
  if (response.status !== 200) {
    throw new Error(`register_failed_${response.status}`);
  }
  const authEmailSender = authEmailSendersByRequest.get(request);
  if (!authEmailSender) {
    throw new Error("registerAndAuth requires buildTestApp request helpers to expose authEmailSender");
  }
  const token = authEmailSender.latestConfirmationToken();
  const confirm = await request("http://localhost/v1/auth/email/confirm", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ token })
  });
  const body = await confirm.json() as { accessToken: string; refreshToken: string; user: { id: string } };
  return {
    ...body,
    authHeader: { authorization: `Bearer ${body.accessToken}`, "content-type": "application/json" }
  };
}
