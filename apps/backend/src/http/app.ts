import {
  adminLoginRequestSchema,
  agentChatRequestSchema,
  agentRunRequestSchema,
  commitAgentChatProposalRequestSchema,
  calorieEstimateRequestSchema,
  dailyHydrationUpdateSchema,
  emailConfirmationRequestSchema,
  executeActionRequestSchema,
  foodSearchRequestSchema,
  goalsUpdateSchema,
  googleLoginRequestSchema,
  loginRequestSchema,
  logoutRequestSchema,
  passwordResetConfirmSchema,
  passwordResetRequestSchema,
  refreshRequestSchema,
  registerRequestSchema,
  settingsUpdateSchema,
  usualFoodDraftRequestSchema,
  usualMealDraftRequestSchema,
  uuidSchema,
  type ActionContext,
  type ActionSource,
  type MealProposal,
} from "@cal-tracker/contracts";
import { cors } from "hono/cors";
import { Hono, type Context } from "hono";
import { HTTPException } from "hono/http-exception";
import { getConnInfo } from "@hono/node-server/conninfo";
import { isIP } from "node:net";
import { ActionExecutor } from "../actions/executor.js";
import { AdminAuthService } from "../auth/adminService.js";
import { AuthService } from "../auth/service.js";
import type { AppConfig } from "../config/env.js";
import { authMiddleware } from "../middleware/auth.js";
import { formatErrorResponse } from "../middleware/errors.js";
import {
  getTraceId,
  requestIdMiddleware,
} from "../middleware/requestContext.js";
import type {
  AppRepository,
  PrivacyDeletionRequest,
  StoredUser,
} from "../repository/types.js";
import type {
  SpeechToTextProvider,
  TranscriptionResult,
} from "../stt/speechToTextProvider.js";
import {
  readAudioBuffer,
  validateAudioUpload,
} from "../stt/audioValidation.js";
import {
  AgentChatService,
  type AgentChatEvent,
} from "../agent/agentChatService.js";
import { agentConversationHistoryDto } from "../agent/agentConversationDto.js";
import { AgentService, type AgentRunResult } from "../agent/agentService.js";
import type { ChatAgentProvider } from "../agent/chatAgentProvider.js";
import { RemoteChatAgentProvider } from "../agent/chatAgentProvider.js";
import { estimateCalories } from "../nutrition/calorieEstimator.js";
import { validateMacroGoalUpdate } from "../utils/macroGoals.js";
import {
  summarizeError,
  type LocalRunLogger,
} from "../observability/localRunLogger.js";
import {
  registerAdminTelemetryRoutes,
  registerClientTelemetryRoutes,
} from "./adminTelemetry.js";
import {
  TelemetryService as DbTelemetryService,
  type TelemetryEventInput,
} from "../telemetry/service.js";
import {
  FireAndForgetTelemetryService,
  hashQueryForTelemetry,
  type FoodSearchTelemetryEvent,
  type SttTelemetryEvent,
  type TelemetryService,
  type VoiceMealRunTelemetryEvent,
} from "../telemetry/telemetryService.js";
import {
  InMemoryAbuseProtection,
  type CostOperationLease,
} from "../security/abuseProtection.js";
import {
  PublicAiErrorException,
  createPublicAiError,
} from "../errors/publicAiErrors.js";
import {
  safeErrorDiagnostic,
  safeErrorDiagnosticMessage,
} from "../observability/sensitiveDataRedaction.js";

const AUTH_RATE_LIMITED_PATHS = new Set([
  "/auth/password-reset/confirm",
  "/v1/admin/auth/login",
  "/v1/auth/email/confirm",
  "/v1/auth/google/login",
  "/v1/auth/login",
  "/v1/auth/password-reset/confirm",
  "/v1/auth/password-reset/request",
  "/v1/auth/register",
]);

const EMAIL_RATE_LIMITED_PATHS = new Set([
  "/v1/auth/password-reset/request",
  "/v1/auth/register",
]);

// Each accepted request spends one unit from the shared LLM/STT bucket. A
// user retry is a new operation; provider-internal iterations are measured by
// provider telemetry but do not spend additional endpoint quota.
const COST_RATE_LIMITED_PATHS = new Set([
  "/v1/agent/chat",
  "/v1/agent/chat/audio",
  "/v1/agent/runs",
  "/v1/meal-templates/draft",
  "/v1/stt/transcriptions",
  "/v1/usual-foods/draft",
  "/v1/voice/meal-runs",
]);

const COST_RATE_LIMITED_ACTIONS = new Set([
  "draft_usual_food",
  "draft_usual_meal",
]);

export function createApp(input: {
  config: AppConfig;
  repository: AppRepository;
  authService: AuthService;
  actionExecutor: ActionExecutor;
  sttProvider: SpeechToTextProvider;
  agentProvider?: ChatAgentProvider;
  runLogger?: LocalRunLogger;
  telemetryService?: TelemetryService;
  abuseProtection?: InMemoryAbuseProtection;
}) {
  const app = new Hono<{
    Variables: { authUser: StoredUser; traceId: string };
  }>();
  const {
    config,
    repository,
    authService,
    actionExecutor,
    sttProvider,
    agentProvider,
    runLogger,
  } = input;
  const telemetry = new DbTelemetryService(repository, { enabled: true });
  const telemetryService: TelemetryService = new FireAndForgetTelemetryService(
    input.telemetryService ?? telemetry,
  );
  const adminAuthService = new AdminAuthService(config);
  const abuseProtection =
    input.abuseProtection ?? new InMemoryAbuseProtection(config);
  const costOperationStates = new WeakMap<
    Context,
    { lease: CostOperationLease; managedByStream: boolean }
  >();

  const resolvedAgentProvider =
    agentProvider ??
    new RemoteChatAgentProvider(
      config.OPENROUTER_API_KEY,
      "https://openrouter.ai/api/v1",
      30000,
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
  const agentService = new AgentService(
    resolvedAgentProvider,
    actionExecutor,
    config.OPENROUTER_MODEL,
    runLogger,
    telemetryService,
  );
  const agentChatService = new AgentChatService(
    resolvedAgentProvider,
    actionExecutor,
    repository,
    config.OPENROUTER_MODEL,
    runLogger,
    telemetryService,
    config.FOOD_RESOLVER_MIN_CONFIDENCE,
  );

  async function runMealInput(input: {
    c: Context;
    user: StoredUser;
    text: string;
    source: ActionSource;
    inputMode: MealInputMode;
    activeProposalId?: string;
    activeProposal?: MealProposal | null;
  }): Promise<MealInputRunResult> {
    const text = input.text.trim();
    if (text.length === 0) {
      return {
        text,
        agentMs: 0,
        activeProposal: input.activeProposal ?? undefined,
        result: {
          kind: "clarification_required" as const,
          message:
            input.inputMode === "voice"
              ? "I could not understand enough audio to create a meal. Please try again or type the meal."
              : "I could not understand enough input to create a meal. Please try again.",
          options: [],
        },
      };
    }

    const activeProposal = input.activeProposalId
      ? input.activeProposal !== undefined
        ? (input.activeProposal ?? undefined)
        : await actionExecutor.getProposalForAgentContext(
            input.user.id,
            input.activeProposalId,
          )
      : undefined;
    const context = buildActionContext(input.c, input.user, input.source);
    const startedAt = Date.now();
    const result = await agentService.run(
      text,
      context,
      input.activeProposalId,
      {
        activeProposal: input.activeProposalId
          ? (activeProposal ?? null)
          : undefined,
        inputMode: input.inputMode,
      },
    );

    return {
      text,
      agentMs: Date.now() - startedAt,
      activeProposal,
      result,
    };
  }

  app.use("*", requestIdMiddleware);
  app.use(
    "*",
    cors({
      origin: (origin) => {
        if (!origin) return "";
        return config.corsAllowedOrigins.includes(origin) ? origin : "";
      },
      allowHeaders: [
        "Authorization",
        "Content-Type",
        "X-Request-Id",
        "X-App-Version",
        "X-App-Build",
        "X-Client-Platform",
        "X-Client-Session-Id",
      ],
      exposeHeaders: ["Retry-After", "X-Request-Id"],
      allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    }),
  );

  app.use("*", async (c, next) => {
    const path = new URL(c.req.url).pathname;
    if (!path.startsWith("/v1/") || path === "/v1/health") {
      await next();
      return;
    }
    const started = Date.now();
    try {
      await next();
      const responseStatus = c.res.status;
      recordBackendTelemetry({
        telemetry,
        event: {
          traceId: getTraceId(c),
          userId: maybeAuthUser(c)?.id,
          eventType: "backend.api_request_completed",
          flow: requestFlowForPath(path),
          surface: "backend",
          severity: severityForStatus(responseStatus),
          status: responseStatus >= 400 ? "failure" : "success",
          route: path,
          method: c.req.method,
          durationMs: Date.now() - started,
          appVersion: c.req.header("x-app-version"),
          appBuild: c.req.header("x-app-build"),
          platform: c.req.header("x-client-platform"),
          locale: c.req.header("accept-language")?.split(",")[0],
          metadata: {
            responseStatus,
            userAgent: c.req.header("user-agent"),
            clientSessionId: c.req.header("x-client-session-id"),
          },
        },
      });
    } catch (error) {
      const summary = summarizeError(error);
      recordBackendTelemetry({
        telemetry,
        event: {
          traceId: getTraceId(c),
          userId: maybeAuthUser(c)?.id,
          eventType: "backend.api_request_failed",
          flow: requestFlowForPath(path),
          surface: "backend",
          severity: "error",
          status: "failure",
          route: path,
          method: c.req.method,
          durationMs: Date.now() - started,
          errorCode:
            error instanceof HTTPException
              ? httpErrorCodeForTelemetry(error.status)
              : undefined,
          errorMessage:
            typeof summary.message === "string" ? summary.message : undefined,
          appVersion: c.req.header("x-app-version"),
          appBuild: c.req.header("x-app-build"),
          platform: c.req.header("x-client-platform"),
          locale: c.req.header("accept-language")?.split(",")[0],
          metadata: {
            userAgent: c.req.header("user-agent"),
            clientSessionId: c.req.header("x-client-session-id"),
          },
        },
      });
      throw error;
    }
  });

  app.use("*", async (c, next) => {
    const path = new URL(c.req.url).pathname;
    if (c.req.method === "POST" && AUTH_RATE_LIMITED_PATHS.has(path)) {
      abuseProtection.consumeAuthAttempt(resolveClientIp(c, config), path);
    }
    await next();
  });

  app.use("*", async (c, next) => {
    const path = new URL(c.req.url).pathname;
    if (c.req.method === "POST" && EMAIL_RATE_LIMITED_PATHS.has(path)) {
      const email = await readEmailFromJsonRequest(c);
      if (email) abuseProtection.consumeEmailAttempt(email, path);
    }
    await next();
  });

  app.onError((err, c) => {
    return formatErrorResponse(c, err);
  });

  app.get("/v1/health", (c) =>
    c.json({ ok: true, service: "cal-tracker-backend" }),
  );

  app.post("/v1/auth/register", async (c) =>
    c.json(
      await authService.register(
        registerRequestSchema.parse(await c.req.json()),
        c.req.header("accept-language")?.split(",")[0],
      ),
    ),
  );
  app.post("/v1/auth/login", async (c) =>
    c.json(
      await authService.login(loginRequestSchema.parse(await c.req.json())),
    ),
  );
  app.post("/v1/auth/google/login", async (c) =>
    c.json(
      await authService.loginWithGoogle(
        googleLoginRequestSchema.parse(await c.req.json()),
      ),
    ),
  );
  app.post("/v1/auth/email/confirm", async (c) => {
    const body = emailConfirmationRequestSchema.parse(await c.req.json());
    return c.json(await authService.confirmEmail(body.token));
  });
  app.post("/v1/auth/refresh", async (c) => {
    const body = refreshRequestSchema.parse(await c.req.json());
    return c.json(await authService.refresh(body.refreshToken));
  });
  app.post("/v1/auth/logout", async (c) => {
    const body = logoutRequestSchema.parse(
      await c.req.json().catch(() => ({})),
    );
    await authService.logout(body.refreshToken);
    return c.json({ ok: true });
  });
  app.get("/auth/email/confirm", (c) =>
    c.html(emailConfirmationFallbackHtml()),
  );
  app.get("/auth/password-reset/confirm", (c) =>
    c.html(
      passwordResetFormHtml(c.req.query("token") ?? "", c.req.query("lang")),
    ),
  );
  app.post("/auth/password-reset/confirm", async (c) => {
    const form = await c.req.parseBody();
    const body = passwordResetConfirmSchema.parse({
      token: form.token,
      newPassword: form.newPassword,
    });
    const matches = form.confirmPassword === body.newPassword;
    const ok =
      matches &&
      (await authService.confirmPasswordReset(body.token, body.newPassword));
    return c.html(passwordResetResultHtml(ok, String(form.lang ?? "")));
  });
  app.get("/.well-known/assetlinks.json", (c) =>
    c.json(androidAssetLinks(config)),
  );
  app.get("/.well-known/apple-app-site-association", (c) =>
    c.json(appleAppSiteAssociation(config)),
  );
  app.post("/v1/auth/password-reset/request", async (c) => {
    const body = passwordResetRequestSchema.parse(await c.req.json());
    return c.json(
      await authService.requestPasswordReset(
        body.email,
        c.req.header("accept-language")?.split(",")[0],
      ),
    );
  });
  app.post("/v1/auth/password-reset/confirm", async (c) => {
    const body = passwordResetConfirmSchema.parse(await c.req.json());
    return c.json({
      ok: await authService.confirmPasswordReset(body.token, body.newPassword),
    });
  });
  app.post("/v1/admin/auth/login", async (c) => {
    const body = adminLoginRequestSchema.parse(await c.req.json());
    return c.json(await adminAuthService.login(body));
  });

  app.use("/v1/*", async (c, next) => {
    const path = new URL(c.req.url).pathname;
    const publicPaths = [
      "/v1/health",
      "/v1/auth/register",
      "/v1/auth/login",
      "/v1/auth/email/confirm",
      "/v1/auth/google/login",
      "/v1/auth/refresh",
      "/v1/auth/logout",
      "/v1/auth/password-reset/request",
      "/v1/auth/password-reset/confirm",
      "/v1/admin/auth/login",
    ];
    if (publicPaths.includes(path) || path.startsWith("/v1/admin/telemetry/"))
      return next();
    return authMiddleware(config, repository)(c, next);
  });

  app.use("/v1/*", async (c, next) => {
    const path = new URL(c.req.url).pathname;
    if (c.req.method !== "POST" || !isCostRateLimitedPath(path)) return next();

    const lease = abuseProtection.acquireCostOperation({
      userId: c.get("authUser").id,
      clientIp: resolveClientIp(c, config),
      route: path,
    });
    const state = { lease, managedByStream: false };
    costOperationStates.set(c, state);
    try {
      await next();
    } finally {
      if (!state.managedByStream) lease.release();
    }
  });

  app.get("/v1/auth/me", (c) => c.json(publicUser(c.get("authUser"))));
  app.post("/v1/auth/logout-all", async (c) => {
    const user = c.get("authUser");
    await authService.logoutAll(user.id);
    return c.json({ ok: true });
  });
  app.put("/v1/settings", async (c) => {
    const user = c.get("authUser");
    const body = settingsUpdateSchema.parse(await c.req.json());
    return c.json({
      user: publicUser(
        await repository.updateTrustedMode(
          user.id,
          body.trustedModeEnabled ?? false,
        ),
      ),
    });
  });
  app.put("/v1/goals", async (c) => {
    const user = c.get("authUser");
    const body = goalsUpdateSchema.parse(await c.req.json());
    const date = body.date ?? new Date().toISOString().slice(0, 10);
    if (body.macroMode !== undefined) {
      const currentGoals = await repository.getDailyGoals(user.id, date);
      if (
        !currentGoals.calorieTargetConfigured &&
        body.calories === undefined
      ) {
        throw new HTTPException(400, {
          message: "calories must be configured before macros",
        });
      }
      const validationError = validateMacroGoalUpdate(
        body,
        body.calories ?? currentGoals.target.calories,
      );
      if (validationError != null) {
        throw new HTTPException(400, { message: validationError });
      }
    }
    const goals = await repository.updateDailyGoals(user.id, {
      date,
      calories: body.calories,
      hydrationGoalLiters: body.hydrationGoalLiters,
      calorieTargetSource: body.calorieTargetSource,
      macroMode: body.macroMode,
      macroSource: body.macroSource,
      macroPreset: body.macroPreset,
      proteinPct: body.proteinPct,
      carbsPct: body.carbsPct,
      fatPct: body.fatPct,
      proteinGrams: body.proteinGrams,
      carbsGrams: body.carbsGrams,
      fatGrams: body.fatGrams,
      macroCalories: body.macroCalories,
      calorieDeltaKcal: body.calorieDeltaKcal,
    });
    const summary = await repository.getDailySummary(user.id, date);
    return c.json({ goals, summary });
  });
  app.put("/v1/hydration/daily", async (c) => {
    const user = c.get("authUser");
    const body = dailyHydrationUpdateSchema.parse(await c.req.json());
    const date = body.date ?? new Date().toISOString().slice(0, 10);
    const summary = await repository.updateDailyHydration(
      user.id,
      date,
      body.waterConsumedLiters,
    );
    return c.json({ summary });
  });
  app.post("/v1/goals/calorie-estimate", async (c) => {
    const body = calorieEstimateRequestSchema.parse(await c.req.json());
    return c.json(estimateCalories(body));
  });

  app.get("/v1/actions", (c) =>
    c.json({ actions: actionExecutor.listActions() }),
  );
  app.post("/v1/actions/:actionId/execute", async (c) => {
    const user = c.get("authUser");
    const actionId = c.req.param("actionId");
    if (isReviewedUsualWriteAction(actionId)) {
      throw new HTTPException(404, {
        message: "Use the reviewed usual foods or meal templates endpoints.",
      });
    }
    const body = executeActionRequestSchema.parse(await c.req.json());
    const context = buildActionContext(c, user, body.source);
    return c.json(await actionExecutor.execute(actionId, body.input, context));
  });

  app.post("/v1/foods/search", async (c) => {
    const user = c.get("authUser");
    const body = foodSearchRequestSchema.parse(await c.req.json());
    const traceId = getTraceId(c);
    const startedAt = Date.now();
    const result = await actionExecutor.execute(
      "search_nutrition_database",
      {
        query: body.query,
        ...(body.barcode ? { barcode: body.barcode } : {}),
      },
      buildActionContext(c, user, "flutter"),
    );
    const limited = limitFoodSearchOutput(result.output, body.limit);
    recordFoodSearchTelemetry({
      telemetryService,
      event: {
        flow: "food_search",
        surface: "backend",
        traceId,
        userId: user.id,
        queryLength: body.query.length,
        queryHash: hashQueryForTelemetry(body.query),
        locale: c.req.header("accept-language")?.split(",")[0],
        barcode: body.barcode,
        resultCount: limited.items.length,
        candidateGroupCount: Array.isArray(limited.candidateGroups)
          ? limited.candidateGroups.length
          : 0,
        topScore: extractTopMatchScore(limited.items),
        topExternalSource: extractTopExternalSource(limited.items),
        topResultType: extractTopResultType(limited.items),
        zeroResults: limited.items.length === 0,
        lowConfidence: isLowConfidenceSearch(
          limited.items,
          config.FOOD_RESOLVER_MIN_CONFIDENCE,
        ),
        durationMs: Date.now() - startedAt,
        metadata: {
          limit: body.limit,
          actionCallId: result.actionCallId,
        },
      },
    });
    return c.json(limited);
  });

  app.post("/v1/usual-foods/draft", async (c) => {
    const user = c.get("authUser");
    const body = usualFoodDraftRequestSchema.parse(await c.req.json());
    const result = await actionExecutor.execute(
      "draft_usual_food",
      body,
      buildActionContext(c, user, "flutter"),
    );
    return c.json(result.output);
  });

  app.post("/v1/meal-templates/draft", async (c) => {
    const user = c.get("authUser");
    const body = usualMealDraftRequestSchema.parse(await c.req.json());
    const result = await actionExecutor.execute(
      "draft_usual_meal",
      body,
      buildActionContext(c, user, "flutter"),
    );
    return c.json(result.output);
  });

  app.post("/v1/agent/runs", async (c) => {
    const user = c.get("authUser");
    const body = agentRunRequestSchema.parse(await c.req.json());
    const run = await runMealInput({
      c,
      user,
      text: body.text,
      source: body.source,
      inputMode: "text",
      activeProposalId: body.activeProposalId,
    });
    return c.json(run.result);
  });

  app.post("/v1/agent/chat", async (c) => {
    const user = c.get("authUser");
    const body = agentChatRequestSchema.parse(await c.req.json());
    return streamAgentChat(
      c,
      agentChatService.chat({
        text: body.message,
        context: buildActionContext(c, user, body.source),
        conversationId: body.conversationId,
        activeProposalId: body.activeProposalId,
        inputMode: "text",
      }),
      costLeaseForStream(c, costOperationStates),
    );
  });

  app.post("/v1/agent/chat/audio", async (c) => {
    const routeStarted = Date.now();
    const user = c.get("authUser");
    const traceId = getTraceId(c);
    const upload = await parseAudioUpload(
      c,
      user,
      traceId,
      "agent.chat_audio",
      {
        parseSource: true,
      },
    );
    if (upload instanceof Response) return upload;

    return streamAgentChat(
      c,
      (async function* () {
        yield {
          type: "thinking",
          message: "Transcribing audio...",
        } as AgentChatEvent;
        let transcription: TranscriptionResult;
        try {
          transcription = await sttProvider.transcribe({
            audio: upload.buffer,
            filename: upload.filename,
            mimeType: upload.mimeType,
            userId: user.id,
            traceId,
          });
        } catch (error) {
          await logLocalRun(runLogger, {
            type: "agent.chat_audio",
            traceId,
            userId: user.id,
            source: upload.source ?? "flutter",
            errorStage: "stt",
            errorDiagnostic: summarizeError(error),
            timingsMs: { total: Date.now() - routeStarted },
          });
          recordTranscriptionTelemetry({
            telemetryService,
            event: {
              traceId,
              userId: user.id,
              surface: "agent_chat_audio",
              audioMimeType: upload.mimeType,
              audioBytes: upload.buffer.byteLength,
              transcriptLength: 0,
              durationMs: Date.now() - routeStarted,
              status: "failed",
              errorCode: "stt_provider_failed",
              errorMessage: safeErrorDiagnosticMessage(error),
              metadata: {
                filename: upload.filename,
                source: upload.source ?? "flutter",
              },
            },
          });
          yield {
            type: "error",
            error: createPublicAiError("provider_unavailable", traceId),
          } as AgentChatEvent;
          return;
        }
        yield {
          type: "transcription_completed",
          transcript: transcription.text,
        } as AgentChatEvent;
        let transcriptionRecorded = false;
        const chatEvents = agentChatService.chat({
          text: transcription.text,
          context: buildActionContext(c, user, upload.source ?? "flutter"),
          conversationId: upload.conversationId,
          activeProposalId: upload.activeProposalId,
          inputMode: "voice",
        });
        for await (const event of chatEvents) {
          if (event.type === "conversation_started" && !transcriptionRecorded) {
            transcriptionRecorded = true;
            recordTranscriptionTelemetry({
              telemetryService,
              event: {
                traceId,
                userId: user.id,
                conversationId: event.conversationId,
                turnId: event.turnId,
                surface: "agent_chat_audio",
                provider: transcription.provider,
                model: transcription.model,
                audioMimeType: upload.mimeType,
                audioBytes: upload.buffer.byteLength,
                transcriptText: transcription.text,
                transcriptLength: transcription.text.length,
                durationMs: Date.now() - routeStarted,
                status: "completed",
                metadata: {
                  filename: upload.filename,
                  source: upload.source ?? "flutter",
                },
              },
            });
          }
          yield event;
        }
      })(),
      costLeaseForStream(c, costOperationStates),
    );
  });

  app.post(
    "/v1/agent/conversations/:conversationId/meal-proposals/:proposalId/commit",
    async (c) => {
      const user = c.get("authUser");
      const body = commitAgentChatProposalRequestSchema.parse(
        await c.req.json(),
      );
      try {
        const committed = await agentChatService.commitProposalDirect({
          context: buildActionContext(c, user, "flutter"),
          conversationId: c.req.param("conversationId"),
          proposalId: c.req.param("proposalId"),
          sourceToolCallId: body.sourceToolCallId,
          clientMutationId: body.clientMutationId,
        });
        return c.json({
          actionId: committed.actionId,
          clientMutationId: committed.clientMutationId,
          reused: committed.reused,
          result: committed.result,
          conversationMessage: committed.conversationMessage,
        });
      } catch (error) {
        if (
          error instanceof Error &&
          [
            "agent_conversation_not_found",
            "proposal_not_found",
            "agent_proposal_source_not_found",
          ].includes(error.message)
        ) {
          throw new HTTPException(404);
        }
        throw error;
      }
    },
  );

  app.get("/v1/agent/conversations", async (c) => {
    const user = c.get("authUser");
    return c.json({
      conversations: await repository.listAgentConversations(user.id),
    });
  });

  app.get("/v1/agent/conversations/:id", async (c) => {
    const user = c.get("authUser");
    const conversationId = c.req.param("id");
    const conversation = await repository.getAgentConversation(
      user.id,
      conversationId,
    );
    if (!conversation) {
      throw new HTTPException(404, {
        message: "agent_conversation_not_found",
      });
    }
    const [messages, toolExecutions] = await Promise.all([
      repository.listAgentConversationMessages(user.id, conversationId),
      repository.listAgentToolExecutions(user.id, conversationId),
    ]);
    return c.json(
      agentConversationHistoryDto({ conversation, messages, toolExecutions }),
    );
  });

  app.delete("/v1/agent/conversations/:id", async (c) => {
    const user = c.get("authUser");
    const deletion = await repository.requestAgentConversationDeletion(
      user.id,
      c.req.param("id"),
    );
    if (!deletion) {
      throw new HTTPException(404, { message: "agent_conversation_not_found" });
    }
    return c.json(deletionResponse(deletion), 202);
  });

  app.get("/v1/agent/conversations/:id/deletion", async (c) => {
    const user = c.get("authUser");
    const deletion = await repository.getAgentConversationDeletion(
      user.id,
      c.req.param("id"),
    );
    if (!deletion) {
      throw new HTTPException(404, { message: "agent_conversation_not_found" });
    }
    return c.json(deletionResponse(deletion));
  });

  app.post("/v1/stt/transcriptions", async (c) => {
    const user = c.get("authUser");
    const traceId = getTraceId(c);
    const upload = await parseAudioUpload(
      c,
      user,
      traceId,
      "stt.transcription",
    );
    if (upload instanceof Response) return upload;
    console.info("stt.transcription.started", {
      traceId,
      userId: user.id,
      filename: upload.filename,
      mimeType: upload.mimeType,
      bytes: upload.buffer.byteLength,
    });
    recordSttTelemetry({
      telemetryService,
      event: {
        flow: "stt",
        surface: "stt",
        traceId,
        userId: user.id,
        outcome: "started",
        stage: "transcription",
        filename: upload.filename,
        mimeType: upload.mimeType,
        bytes: upload.buffer.byteLength,
      },
    });

    let result: TranscriptionResult;
    try {
      result = await sttProvider.transcribe({
        audio: upload.buffer,
        filename: upload.filename,
        mimeType: upload.mimeType,
        userId: user.id,
        traceId,
      });
    } catch (error) {
      console.error("stt.transcription.failed", {
        traceId,
        userId: user.id,
        mimeType: upload.mimeType,
        bytes: upload.buffer.byteLength,
        error: safeErrorDiagnostic(error),
      });
      recordSttTelemetry({
        telemetryService,
        event: {
          flow: "stt",
          surface: "stt",
          traceId,
          userId: user.id,
          outcome: "failed",
          stage: "transcription",
          filename: upload.filename,
          mimeType: upload.mimeType,
          bytes: upload.buffer.byteLength,
          errorCode: "stt_provider_failed",
          errorMessage: safeErrorDiagnosticMessage(error),
        },
      });
      recordTranscriptionTelemetry({
        telemetryService,
        event: {
          traceId,
          userId: user.id,
          surface: "stt",
          audioMimeType: upload.mimeType,
          audioBytes: upload.buffer.byteLength,
          transcriptLength: 0,
          status: "failed",
          errorCode: "stt_provider_failed",
          errorMessage: safeErrorDiagnosticMessage(error),
          metadata: { filename: upload.filename },
        },
      });
      throw new PublicAiErrorException(
        "provider_unavailable",
        traceId,
        503,
        error,
      );
    }

    console.info("stt.transcription.completed", {
      traceId,
      userId: user.id,
      provider: result.provider,
      model: result.model,
      transcriptLength: result.text.length,
    });
    recordSttTelemetry({
      telemetryService,
      event: {
        flow: "stt",
        surface: "stt",
        traceId,
        userId: user.id,
        outcome: "completed",
        stage: "transcription",
        filename: upload.filename,
        mimeType: upload.mimeType,
        bytes: upload.buffer.byteLength,
        provider: result.provider,
        model: result.model,
        transcriptLength: result.text.length,
      },
    });
    recordTranscriptionTelemetry({
      telemetryService,
      event: {
        traceId,
        userId: user.id,
        surface: "stt",
        provider: result.provider,
        model: result.model,
        audioMimeType: upload.mimeType,
        audioBytes: upload.buffer.byteLength,
        transcriptText: result.text,
        transcriptLength: result.text.length,
        status: "completed",
        metadata: { filename: upload.filename },
      },
    });

    return c.json({
      transcript: result.text,
      provider: result.provider,
      model: result.model,
      traceId,
    });
  });

  app.post("/v1/voice/meal-runs", async (c) => {
    const routeStarted = Date.now();
    const user = c.get("authUser");
    const traceId = getTraceId(c);
    const upload = await parseAudioUpload(c, user, traceId, "voice.meal_run", {
      parseSource: true,
    });
    if (upload instanceof Response) return upload;

    console.info("voice.meal_run.started", {
      traceId,
      userId: user.id,
      filename: upload.filename,
      mimeType: upload.mimeType,
      bytes: upload.buffer.byteLength,
    });
    recordVoiceMealRunTelemetry({
      telemetryService,
      event: {
        flow: "voice_meal",
        surface: "agent",
        traceId,
        userId: user.id,
        outcome: "started",
        stage: "voice_meal_run",
        filename: upload.filename,
        mimeType: upload.mimeType,
        bytes: upload.buffer.byteLength,
        source: upload.source ?? "flutter",
        metadata: upload.activeProposalId
          ? {
              hasActiveProposal: true,
              activeProposalId: upload.activeProposalId,
            }
          : undefined,
      },
    });

    let transcription: TranscriptionResult;
    let sttMs = 0;
    let activeProposal: MealProposal | undefined;
    try {
      const sttStarted = Date.now();
      activeProposal = upload.activeProposalId
        ? await actionExecutor.getProposalForAgentContext(
            user.id,
            upload.activeProposalId,
          )
        : undefined;
      transcription = await sttProvider.transcribe({
        audio: upload.buffer,
        filename: upload.filename,
        mimeType: upload.mimeType,
        userId: user.id,
        traceId,
      });
      sttMs = Date.now() - sttStarted;
    } catch (error) {
      console.error("voice.meal_run.transcription_failed", {
        traceId,
        userId: user.id,
        mimeType: upload.mimeType,
        bytes: upload.buffer.byteLength,
        error: safeErrorDiagnostic(error),
      });
      await logLocalRun(runLogger, {
        type: "voice.meal_run",
        traceId,
        userId: user.id,
        source: upload.source ?? "flutter",
        audio: {
          filename: upload.filename,
          mimeType: upload.mimeType,
          bytes: upload.buffer.byteLength,
        },
        errorStage: "stt",
        errorDiagnostic: summarizeError(error),
        timingsMs: {
          stt: Date.now() - routeStarted,
          total: Date.now() - routeStarted,
        },
      });
      recordVoiceMealRunTelemetry({
        telemetryService,
        event: {
          flow: "voice_meal",
          surface: "agent",
          traceId,
          userId: user.id,
          outcome: "failed",
          stage: "voice_meal_run",
          filename: upload.filename,
          mimeType: upload.mimeType,
          bytes: upload.buffer.byteLength,
          source: upload.source ?? "flutter",
          errorStage: "stt",
          errorMessage: safeErrorDiagnosticMessage(error),
          timingsMs: {
            stt: Date.now() - routeStarted,
            total: Date.now() - routeStarted,
          },
          metadata: { errorCode: "stt_provider_failed" },
        },
      });
      recordTranscriptionTelemetry({
        telemetryService,
        event: {
          traceId,
          userId: user.id,
          surface: "voice_meal",
          audioMimeType: upload.mimeType,
          audioBytes: upload.buffer.byteLength,
          transcriptLength: 0,
          durationMs: Date.now() - routeStarted,
          status: "failed",
          errorCode: "stt_provider_failed",
          errorMessage: safeErrorDiagnosticMessage(error),
          metadata: {
            filename: upload.filename,
            source: upload.source ?? "flutter",
          },
        },
      });
      throw new PublicAiErrorException(
        "provider_unavailable",
        traceId,
        503,
        error,
      );
    }

    const transcript = transcription.text;
    const mealInput = await runMealInput({
      c,
      user,
      text: transcript,
      source: upload.source ?? "flutter",
      inputMode: "voice",
      activeProposalId: upload.activeProposalId,
      activeProposal: activeProposal ?? null,
    });

    console.info("voice.meal_run.completed", {
      traceId,
      userId: user.id,
      provider: transcription.provider,
      model: transcription.model,
      transcriptLength: transcript.length,
      resultKind: mealInput.result.kind,
    });
    await logLocalRun(runLogger, {
      type: "voice.meal_run",
      traceId,
      userId: user.id,
      source: upload.source ?? "flutter",
      audio: {
        filename: upload.filename,
        mimeType: upload.mimeType,
        bytes: upload.buffer.byteLength,
      },
      transcript,
      provider: transcription.provider,
      model: transcription.model,
      resultKind: mealInput.result.kind,
      timingsMs: {
        stt: sttMs,
        agent: mealInput.agentMs,
        total: Date.now() - routeStarted,
      },
    });
    recordVoiceMealRunTelemetry({
      telemetryService,
      event: {
        flow: "voice_meal",
        surface: "agent",
        traceId,
        userId: user.id,
        outcome: "completed",
        stage: "voice_meal_run",
        filename: upload.filename,
        mimeType: upload.mimeType,
        bytes: upload.buffer.byteLength,
        source: upload.source ?? "flutter",
        provider: transcription.provider,
        model: transcription.model,
        transcriptLength: transcript.length,
        resultKind: mealInput.result.kind,
        timingsMs: {
          stt: sttMs,
          agent: mealInput.agentMs,
          total: Date.now() - routeStarted,
        },
      },
    });
    recordTranscriptionTelemetry({
      telemetryService,
      event: {
        traceId,
        userId: user.id,
        surface: "voice_meal",
        provider: transcription.provider,
        model: transcription.model,
        audioMimeType: upload.mimeType,
        audioBytes: upload.buffer.byteLength,
        transcriptText: transcript,
        transcriptLength: transcript.length,
        durationMs: sttMs,
        status: "completed",
        downstreamResultKind: mealInput.result.kind,
        metadata: {
          filename: upload.filename,
          source: upload.source ?? "flutter",
        },
      },
    });

    return c.json({
      transcript,
      provider: transcription.provider,
      model: transcription.model,
      traceId,
      result: mealInput.result,
    });
  });

  app.post("/v1/meals/proposals", async (c) => {
    const user = c.get("authUser");
    const body = await c.req.json();
    return c.json(
      await actionExecutor.execute(
        "propose_meal_log",
        body,
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.post("/v1/meals/proposals/:id/commit", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "commit_meal",
        {
          ...(await c.req.json().catch(() => ({}))),
          proposalId: c.req.param("id"),
        },
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.post("/v1/meals/:id/correct", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "correct_meal",
        { ...(await c.req.json()), mealId: c.req.param("id") },
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.delete("/v1/meals/:id", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "delete_meal",
        {
          mealId: c.req.param("id"),
          confirmationToken: c.req.query("confirmationToken"),
        },
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.get("/v1/summary/daily", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "get_daily_summary",
        { date: c.req.query("date") },
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.get("/v1/meals", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "get_meal_history",
        { limit: Number(c.req.query("limit") ?? 25) },
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.get("/v1/meal-templates", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "get_usual_meals",
        {},
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.get("/v1/usual-foods", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "get_usual_foods",
        {},
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.post("/v1/usual-foods", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "create_usual_food",
        await c.req.json(),
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.put("/v1/usual-foods/:id", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "update_usual_food",
        { ...(await c.req.json()), usualFoodId: c.req.param("id") },
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.delete("/v1/usual-foods/:id", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "delete_usual_food",
        { usualFoodId: c.req.param("id") },
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.post("/v1/meal-templates", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "create_meal_template",
        await c.req.json(),
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.put("/v1/meal-templates/:id", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "update_meal_template",
        { ...(await c.req.json()), templateId: c.req.param("id") },
        buildActionContext(c, user, "flutter"),
      ),
    );
  });
  app.delete("/v1/meal-templates/:id", async (c) => {
    const user = c.get("authUser");
    return c.json(
      await actionExecutor.execute(
        "delete_meal_template",
        { templateId: c.req.param("id") },
        buildActionContext(c, user, "flutter"),
      ),
    );
  });

  registerClientTelemetryRoutes({ app, telemetry });
  registerAdminTelemetryRoutes({ app, adminAuthService, telemetry });

  return app;
}

type ParsedAudioUpload = {
  buffer: Buffer;
  filename: string;
  mimeType: string;
  source?: ActionSource;
  activeProposalId?: string;
  conversationId?: string;
};

type MealInputMode = "text" | "voice";

type MealInputRunResult = {
  text: string;
  agentMs: number;
  activeProposal?: MealProposal;
  result: AgentRunResult;
};

async function parseAudioUpload(
  c: Context,
  user: StoredUser,
  traceId: string,
  logPrefix: string,
  options: { parseSource?: boolean } = {},
): Promise<ParsedAudioUpload | Response> {
  let body: Record<string, unknown>;
  try {
    body = await c.req.parseBody({ all: true });
  } catch (error) {
    console.warn(`${logPrefix}.invalid_multipart`, {
      traceId,
      userId: user.id,
      error: safeErrorDiagnostic(error),
    });
    return c.json(
      {
        error: createPublicAiError("validation_error", traceId),
      },
      400,
    );
  }

  const source = options.parseSource
    ? parseMultipartActionSource(body.source)
    : undefined;
  if (options.parseSource && source === null) {
    console.warn(`${logPrefix}.invalid_source`, {
      traceId,
      userId: user.id,
      sourcePresent: body.source !== undefined,
      sourceType: typeof body.source,
    });
    return c.json(
      {
        error: createPublicAiError("validation_error", traceId),
      },
      400,
    );
  }
  const activeProposalId = parseOptionalMultipartUuid(body.activeProposalId);
  if (activeProposalId === null) {
    console.warn(`${logPrefix}.invalid_active_proposal`, {
      traceId,
      userId: user.id,
      activeProposalIdPresent: body.activeProposalId !== undefined,
      activeProposalIdType: typeof body.activeProposalId,
    });
    return c.json(
      {
        error: createPublicAiError("validation_error", traceId),
      },
      400,
    );
  }
  const conversationId = parseOptionalMultipartUuid(body.conversationId);
  if (conversationId === null) {
    console.warn(`${logPrefix}.invalid_conversation`, {
      traceId,
      userId: user.id,
      conversationIdPresent: body.conversationId !== undefined,
      conversationIdType: typeof body.conversationId,
    });
    return c.json(
      {
        error: createPublicAiError("validation_error", traceId),
      },
      400,
    );
  }

  const audioField = body.audio;
  if (!audioField || (Array.isArray(audioField) && audioField.length === 0)) {
    console.warn(`${logPrefix}.missing_audio`, {
      traceId,
      userId: user.id,
    });
    return c.json(
      {
        error: createPublicAiError("validation_error", traceId),
      },
      400,
    );
  }
  const file = Array.isArray(audioField) ? audioField[0] : audioField;

  const validation = validateAudioUpload(file);
  if (!validation.ok) {
    console.warn(`${logPrefix}.invalid_audio`, {
      traceId,
      userId: user.id,
      status: validation.status,
      error: validation.error,
    });
    return c.json(
      {
        error: createPublicAiError("validation_error", traceId),
      },
      validation.status,
    );
  }

  return {
    buffer: await readAudioBuffer(file),
    filename: validation.filename,
    mimeType: validation.mimeType,
    source: source ?? undefined,
    activeProposalId: activeProposalId ?? undefined,
    conversationId: conversationId ?? undefined,
  };
}

function streamAgentChat(
  c: Context,
  events: AsyncIterable<AgentChatEvent>,
  lease?: CostOperationLease,
): Response {
  const encoder = new TextEncoder();
  const traceId = getTraceId(c);
  const iterator = events[Symbol.asyncIterator]();
  let closed = false;

  const finish = async () => {
    if (closed) return;
    closed = true;
    try {
      await iterator.return?.();
    } finally {
      lease?.release();
    }
  };
  const stream = new ReadableStream<Uint8Array>({
    async pull(controller) {
      if (closed) return;
      try {
        const next = await iterator.next();
        if (next.done) {
          controller.close();
          await finish();
          return;
        }
        controller.enqueue(
          encoder.encode(`data: ${JSON.stringify(next.value)}\n\n`),
        );
        if (next.value.type === "done" || next.value.type === "error") {
          controller.close();
          await finish();
        }
      } catch (error) {
        try {
          controller.enqueue(
            encoder.encode(
              `data: ${JSON.stringify({
                type: "error",
                error: createPublicAiError("internal_error", traceId),
              })}\n\n`,
            ),
          );
          controller.close();
        } finally {
          console.error("agent.chat_stream.failed", {
            traceId,
            error: safeErrorDiagnostic(error),
          });
          await finish();
        }
      }
    },
    async cancel() {
      await finish();
    },
  });
  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    },
  });
}

function costLeaseForStream(
  c: Context,
  states: WeakMap<
    Context,
    { lease: CostOperationLease; managedByStream: boolean }
  >,
): CostOperationLease | undefined {
  const state = states.get(c);
  if (!state) return undefined;
  state.managedByStream = true;
  return state.lease;
}

async function readEmailFromJsonRequest(
  c: Context,
): Promise<string | undefined> {
  if (
    !c.req.header("content-type")?.toLowerCase().includes("application/json")
  ) {
    return undefined;
  }
  try {
    const body = (await c.req.raw.clone().json()) as { email?: unknown };
    return typeof body.email === "string" && body.email.trim().length > 0
      ? body.email
      : undefined;
  } catch {
    return undefined;
  }
}

function resolveClientIp(c: Context, config: AppConfig): string {
  if (config.RATE_LIMIT_TRUST_PROXY_HEADERS) {
    const forwarded = normalizeIp(c.req.header("x-real-ip"));
    if (forwarded) return forwarded;
  }
  try {
    return normalizeIp(getConnInfo(c).remote.address) ?? "unavailable";
  } catch {
    // Hono's in-process app.request() test adapter has no socket. Production
    // uses @hono/node-server, where getConnInfo is the adapter's supported API.
    return "unavailable";
  }
}

function normalizeIp(value: string | undefined): string | undefined {
  const normalized = value?.trim();
  if (!normalized || isIP(normalized) === 0) return undefined;
  return normalized;
}

function isCostRateLimitedPath(path: string): boolean {
  if (COST_RATE_LIMITED_PATHS.has(path)) return true;
  const segments = path.split("/");
  return (
    segments.length === 5 &&
    segments[1] === "v1" &&
    segments[2] === "actions" &&
    COST_RATE_LIMITED_ACTIONS.has(segments[3] ?? "") &&
    segments[4] === "execute"
  );
}

function parseMultipartActionSource(value: unknown): ActionSource | null {
  const source = Array.isArray(value) ? value[0] : value;
  if (source == null) return "flutter";
  if (
    source === "flutter" ||
    source === "ios_appintents" ||
    source === "android_appfunctions"
  ) {
    return source;
  }
  return null;
}

function parseOptionalMultipartUuid(value: unknown): string | null | undefined {
  const raw = Array.isArray(value) ? value[0] : value;
  if (raw == null || raw === "") return undefined;
  if (typeof raw !== "string") return null;
  const parsed = uuidSchema.safeParse(raw);
  return parsed.success ? parsed.data : null;
}

async function logLocalRun(
  runLogger: LocalRunLogger | undefined,
  event: Record<string, unknown>,
): Promise<void> {
  try {
    await runLogger?.log(event);
  } catch (error) {
    console.warn("local_run_log.failed", summarizeError(error));
  }
}

function limitFoodSearchOutput(
  output: unknown,
  limit: number,
): {
  items: unknown[];
  candidateGroups?: unknown[];
} {
  if (typeof output !== "object" || output === null || Array.isArray(output)) {
    return { items: [] };
  }

  const value = output as {
    items?: unknown;
    candidateGroups?: unknown;
    candidates?: unknown;
  };
  const items = Array.isArray(value.items) ? value.items.slice(0, limit) : [];
  const groupsValue = value.candidateGroups ?? value.candidates;
  const candidateGroups = Array.isArray(groupsValue)
    ? groupsValue.map((group) => limitFoodCandidateGroup(group, limit))
    : undefined;

  return {
    items,
    ...(candidateGroups ? { candidateGroups } : {}),
  };
}

function limitFoodCandidateGroup(group: unknown, limit: number): unknown {
  if (typeof group !== "object" || group === null || Array.isArray(group)) {
    return group;
  }
  const value = group as { candidates?: unknown };
  if (!Array.isArray(value.candidates)) return group;
  return { ...value, candidates: value.candidates.slice(0, limit) };
}

function maybeAuthUser(c: Context): StoredUser | undefined {
  return c.get("authUser") as StoredUser | undefined;
}

function severityForStatus(status: number): "info" | "warning" | "error" {
  if (status >= 500) return "error";
  if (status >= 400) return "warning";
  return "info";
}

function requestFlowForPath(path: string): string | undefined {
  if (path.includes("/voice/")) return "voice_meal";
  if (path.includes("/stt/")) return "stt";
  if (path.includes("/foods/search")) return "food_search";
  if (path.includes("/agent/")) return "llm_run";
  if (path.includes("/telemetry")) return "telemetry";
  if (path.includes("/auth/")) return "auth";
  return undefined;
}

function httpErrorCodeForTelemetry(status: number): string {
  if (status === 401) return "authentication_required";
  if (status === 403) return "permission_denied";
  if (status === 404) return "not_found";
  return `http_${status}`;
}

function buildActionContext(
  c: Context,
  user: StoredUser,
  source: ActionSource,
): ActionContext {
  return {
    actorUserId: user.id,
    actorType: source === "internal_agent" ? "internal_agent" : "user",
    source,
    scopes: user.scopes,
    timezone: c.req.header("x-user-timezone") ?? "UTC",
    locale: c.req.header("accept-language")?.split(",")[0] ?? "en-US",
    trustedModeEnabled: false,
    traceId: getTraceId(c),
  };
}

function isReviewedUsualWriteAction(actionId: string): boolean {
  return (
    actionId === "create_usual_food" ||
    actionId === "update_usual_food" ||
    actionId === "delete_usual_food" ||
    actionId === "create_meal_template" ||
    actionId === "update_meal_template" ||
    actionId === "delete_meal_template"
  );
}

function publicUser(user: StoredUser) {
  const { passwordHash: _passwordHash, scopes: _scopes, ...publicValue } = user;
  return publicValue;
}

function emailConfirmationFallbackHtml(): string {
  return `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Confirm BetterCalories</title>
  </head>
  <body style="font-family:Arial,sans-serif;color:#18201b;line-height:1.5;margin:32px">
    <h1>Open BetterCalories</h1>
    <p>If the app is installed, this link opens it and finishes your sign in.</p>
    <p>If nothing happened, install or open BetterCalories and tap the email link again.</p>
  </body>
</html>`;
}

function passwordResetFormHtml(
  token: string,
  requestedLocale?: string,
): string {
  const locale = requestedLocale === "es" ? "es" : "en";
  const copy =
    locale === "es"
      ? {
          title: "Restablece tu contraseña",
          password: "Contraseña nueva",
          confirm: "Repite la contraseña",
          submit: "Guardar contraseña",
        }
      : {
          title: "Reset your password",
          password: "New password",
          confirm: "Repeat password",
          submit: "Save password",
        };
  return `<!doctype html>
<html lang="${locale}">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${copy.title} · BetterCalories</title>
  </head>
  <body style="font-family:Arial,sans-serif;color:#18201b;line-height:1.5;margin:32px;max-width:480px">
    <h1>${copy.title}</h1>
    <form method="post" action="/auth/password-reset/confirm">
      <input type="hidden" name="token" value="${escapeHtmlAttribute(token)}">
      <input type="hidden" name="lang" value="${locale}">
      <p><label>${copy.password}<br><input name="newPassword" type="password" minlength="8" required autocomplete="new-password"></label></p>
      <p><label>${copy.confirm}<br><input name="confirmPassword" type="password" minlength="8" required autocomplete="new-password"></label></p>
      <button type="submit">${copy.submit}</button>
    </form>
  </body>
</html>`;
}

function passwordResetResultHtml(
  ok: boolean,
  requestedLocale?: string,
): string {
  const locale = requestedLocale === "es" ? "es" : "en";
  const title = ok
    ? locale === "es"
      ? "Contraseña actualizada"
      : "Password updated"
    : locale === "es"
      ? "No se pudo actualizar"
      : "Could not update password";
  const message = ok
    ? locale === "es"
      ? "Ya puedes volver a BetterCalories e iniciar sesión."
      : "You can return to BetterCalories and sign in now."
    : locale === "es"
      ? "El enlace no es válido, ha caducado o las contraseñas no coinciden."
      : "The link is invalid, expired, or the passwords do not match.";
  return `<!doctype html>
<html lang="${locale}">
  <head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${title} · BetterCalories</title></head>
  <body style="font-family:Arial,sans-serif;color:#18201b;line-height:1.5;margin:32px;max-width:480px">
    <h1>${title}</h1>
    <p>${message}</p>
  </body>
</html>`;
}

function escapeHtmlAttribute(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll('"', "&quot;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
}

function androidAssetLinks(config: AppConfig) {
  if (config.mobileAndroidSha256CertFingerprints.length === 0) return [];
  return config.mobileAndroidAppLinkPackages.map((packageName) => ({
    relation: ["delegate_permission/common.handle_all_urls"],
    target: {
      namespace: "android_app",
      package_name: packageName,
      sha256_cert_fingerprints: config.mobileAndroidSha256CertFingerprints,
    },
  }));
}

function appleAppSiteAssociation(config: AppConfig) {
  return {
    applinks: {
      apps: [],
      details: config.mobileIosAppIds.map((appID) => ({
        appIDs: [appID],
        components: [
          {
            "/": "/auth/email/confirm",
            comment: "BetterCalories email confirmation links",
          },
        ],
      })),
    },
  };
}

function recordBackendTelemetry(input: {
  telemetry: DbTelemetryService;
  event: TelemetryEventInput;
}): void {
  recordTelemetry("backend_event", () =>
    input.telemetry.recordEvent(input.event),
  );
}

function deletionResponse(deletion: PrivacyDeletionRequest) {
  return {
    ok: true,
    deleted: true,
    hidden: true,
    status: deletion.status,
    requestedAt: deletion.requestedAt,
    purgeDueAt: deletion.purgeDueAt,
    purgedAt: deletion.purgedAt ?? null,
  };
}

function recordFoodSearchTelemetry(input: {
  telemetryService: TelemetryService;
  event: FoodSearchTelemetryEvent;
}): void {
  recordTelemetry("food_search", () =>
    input.telemetryService.recordFoodSearchEvent(input.event),
  );
}

function recordSttTelemetry(input: {
  telemetryService: TelemetryService;
  event: SttTelemetryEvent;
}): void {
  recordTelemetry("stt", () =>
    input.telemetryService.recordSttEvent(input.event),
  );
}

function recordVoiceMealRunTelemetry(input: {
  telemetryService: TelemetryService;
  event: VoiceMealRunTelemetryEvent;
}): void {
  recordTelemetry("voice_meal_run", () =>
    input.telemetryService.recordVoiceMealRunEvent(input.event),
  );
}

function recordTranscriptionTelemetry(input: {
  telemetryService: TelemetryService;
  event: Parameters<TelemetryService["recordTranscriptionRecord"]>[0];
}): void {
  recordTelemetry("transcription_record", () =>
    input.telemetryService.recordTranscriptionRecord(input.event),
  );
}

function recordTelemetry(label: string, emit: () => Promise<unknown>): void {
  try {
    void emit().catch((error) => {
      console.warn(`telemetry.${label}.failed`, summarizeError(error));
    });
  } catch (error) {
    console.warn(`telemetry.${label}.failed`, summarizeError(error));
  }
}

function isLowConfidenceSearch(
  items: unknown[],
  minConfidence: number,
): boolean {
  if (items.length === 0) return false;
  const top = items[0] as { confidence?: unknown; matchScore?: unknown };
  const confidence =
    typeof top.confidence === "number"
      ? top.confidence
      : typeof top.matchScore === "number"
        ? top.matchScore
        : undefined;
  if (typeof confidence !== "number") return false;
  return confidence < minConfidence;
}

function extractTopMatchScore(items: unknown[]): number | undefined {
  if (items.length === 0) return undefined;
  const top = items[0] as { confidence?: unknown; matchScore?: unknown };
  if (typeof top.confidence === "number") return top.confidence;
  if (typeof top.matchScore === "number") return top.matchScore;
  return undefined;
}

function extractTopExternalSource(items: unknown[]): string | undefined {
  if (items.length === 0) return undefined;
  const top = items[0] as { externalSource?: unknown; source?: unknown };
  if (typeof top.externalSource === "string") return top.externalSource;
  if (typeof top.source === "string") return top.source;
  return undefined;
}

function extractTopResultType(items: unknown[]): string | undefined {
  if (items.length === 0) return undefined;
  const top = items[0] as { resultType?: unknown };
  return typeof top.resultType === "string" ? top.resultType : undefined;
}
