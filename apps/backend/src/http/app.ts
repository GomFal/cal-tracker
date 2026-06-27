import {
  adminLoginRequestSchema,
  agentChatRequestSchema,
  agentRunRequestSchema,
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
import type { AppRepository, StoredUser } from "../repository/types.js";
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

export function createApp(input: {
  config: AppConfig;
  repository: AppRepository;
  authService: AuthService;
  actionExecutor: ActionExecutor;
  sttProvider: SpeechToTextProvider;
  agentProvider?: ChatAgentProvider;
  runLogger?: LocalRunLogger;
  telemetryService?: TelemetryService;
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
  app.get("/auth/email/confirm", (c) => c.html(emailConfirmationFallbackHtml()));
  app.get("/.well-known/assetlinks.json", (c) => c.json(androidAssetLinks(config)));
  app.get("/.well-known/apple-app-site-association", (c) =>
    c.json(appleAppSiteAssociation(config)),
  );
  app.post("/v1/auth/password-reset/request", async (c) => {
    const body = passwordResetRequestSchema.parse(await c.req.json());
    return c.json(await authService.requestPasswordReset(body.email));
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
            error: summarizeError(error),
            timingsMs: { total: Date.now() - routeStarted },
          });
          yield {
            type: "error",
            error: error instanceof Error ? error.message : String(error),
          } as AgentChatEvent;
          return;
        }
        yield {
          type: "transcription_completed",
          transcript: transcription.text,
        } as AgentChatEvent;
        yield* agentChatService.chat({
          text: transcription.text,
          context: buildActionContext(c, user, upload.source ?? "flutter"),
          conversationId: upload.conversationId,
          activeProposalId: upload.activeProposalId,
          inputMode: "voice",
        });
      })(),
    );
  });

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
    return c.json({
      conversation,
      messages: await repository.listAgentConversationMessages(
        user.id,
        conversationId,
      ),
    });
  });

  app.delete("/v1/agent/conversations/:id", async (c) => {
    const user = c.get("authUser");
    const hidden = await repository.hideAgentConversationFromUser(
      user.id,
      c.req.param("id"),
    );
    return c.json({
      ok: hidden,
      deleted: hidden,
      hidden,
    });
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
        filename: upload.filename,
        mimeType: upload.mimeType,
        bytes: upload.buffer.byteLength,
        error: error instanceof Error ? error.message : String(error),
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
          errorMessage: error instanceof Error ? error.message : String(error),
        },
      });
      throw error;
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
        filename: upload.filename,
        mimeType: upload.mimeType,
        bytes: upload.buffer.byteLength,
        error: error instanceof Error ? error.message : String(error),
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
        error: summarizeError(error),
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
          errorMessage: error instanceof Error ? error.message : String(error),
          timingsMs: {
            stt: Date.now() - routeStarted,
            total: Date.now() - routeStarted,
          },
          metadata: { errorCode: "stt_provider_failed" },
        },
      });
      throw error;
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
      error: error instanceof Error ? error.message : String(error),
    });
    return c.json(
      {
        error: {
          code: "validation_error",
          message: "Invalid multipart/form-data request.",
          traceId,
        },
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
      source: body.source,
    });
    return c.json(
      {
        error: {
          code: "validation_error",
          message: "Invalid source.",
          traceId,
        },
      },
      400,
    );
  }
  const activeProposalId = parseOptionalMultipartUuid(body.activeProposalId);
  if (activeProposalId === null) {
    console.warn(`${logPrefix}.invalid_active_proposal`, {
      traceId,
      userId: user.id,
      activeProposalId: body.activeProposalId,
    });
    return c.json(
      {
        error: {
          code: "validation_error",
          message: "Invalid active proposal id.",
          traceId,
        },
      },
      400,
    );
  }
  const conversationId = parseOptionalMultipartUuid(body.conversationId);
  if (conversationId === null) {
    console.warn(`${logPrefix}.invalid_conversation`, {
      traceId,
      userId: user.id,
      conversationId: body.conversationId,
    });
    return c.json(
      {
        error: {
          code: "validation_error",
          message: "Invalid conversation id.",
          traceId,
        },
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
        error: {
          code: "validation_error",
          message: "Missing audio file.",
          traceId,
        },
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
        error: { code: "validation_error", message: validation.error, traceId },
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
  _c: Context,
  events: AsyncIterable<AgentChatEvent>,
): Response {
  const encoder = new TextEncoder();
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      try {
        for await (const event of events) {
          controller.enqueue(
            encoder.encode(`data: ${JSON.stringify(event)}\n\n`),
          );
          if (event.type === "done" || event.type === "error") break;
        }
      } catch (error) {
        controller.enqueue(
          encoder.encode(
            `data: ${JSON.stringify({
              type: "error",
              error: error instanceof Error ? error.message : String(error),
            })}\n\n`,
          ),
        );
      } finally {
        controller.close();
      }
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
