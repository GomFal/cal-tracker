import {
  agentRunRequestSchema,
  calorieEstimateRequestSchema,
  dailyHydrationUpdateSchema,
  executeActionRequestSchema,
  goalsUpdateSchema,
  googleLoginRequestSchema,
  loginRequestSchema,
  logoutRequestSchema,
  passwordResetConfirmSchema,
  passwordResetRequestSchema,
  refreshRequestSchema,
  registerRequestSchema,
  settingsUpdateSchema,
  uuidSchema,
  type ActionContext,
  type ActionSource,
  type MealProposal,
} from "@cal-tracker/contracts";
import { cors } from "hono/cors";
import { Hono, type Context } from "hono";
import { HTTPException } from "hono/http-exception";
import { ActionExecutor } from "../actions/executor.js";
import { AuthService } from "../auth/service.js";
import type { AppConfig } from "../config/env.js";
import { authMiddleware } from "../middleware/auth.js";
import { formatErrorResponse } from "../middleware/errors.js";
import { getTraceId, requestIdMiddleware } from "../middleware/requestContext.js";
import type { AppRepository, StoredUser } from "../repository/types.js";
import type { SpeechToTextProvider, TranscriptionResult } from "../stt/speechToTextProvider.js";
import { readAudioBuffer, validateAudioUpload } from "../stt/audioValidation.js";
import { AgentService, type AgentRunResult } from "../agent/agentService.js";
import type { ChatAgentProvider } from "../agent/chatAgentProvider.js";
import { RemoteChatAgentProvider } from "../agent/chatAgentProvider.js";
import { estimateCalories } from "../nutrition/calorieEstimator.js";
import { validateMacroGoalUpdate } from "../utils/macroGoals.js";
import {
  summarizeError,
  type LocalRunLogger,
} from "../observability/localRunLogger.js";

export function createApp(input: {
  config: AppConfig;
  repository: AppRepository;
  authService: AuthService;
  actionExecutor: ActionExecutor;
  sttProvider: SpeechToTextProvider;
  agentProvider?: ChatAgentProvider;
  runLogger?: LocalRunLogger;
}) {
  const app = new Hono<{ Variables: { authUser: StoredUser; traceId: string } }>();
  const { config, repository, authService, actionExecutor, sttProvider, agentProvider, runLogger } = input;

  const resolvedAgentProvider = agentProvider ?? new RemoteChatAgentProvider(
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
  const agentService = new AgentService(resolvedAgentProvider, actionExecutor, config.OPENROUTER_MODEL, runLogger);

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
        ? input.activeProposal ?? undefined
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
          ? activeProposal ?? null
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
  app.use("*", cors({
    origin: (origin) => {
      if (!origin) return "";
      return config.corsAllowedOrigins.includes(origin) ? origin : "";
    },
    allowHeaders: ["Authorization", "Content-Type", "X-Request-Id"],
    allowMethods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
  }));

  app.onError((err, c) => {
    return formatErrorResponse(c, err);
  });

  app.get("/v1/health", (c) => c.json({ ok: true, service: "cal-tracker-backend" }));

  app.post("/v1/auth/register", async (c) => c.json(await authService.register(registerRequestSchema.parse(await c.req.json()))));
  app.post("/v1/auth/login", async (c) => c.json(await authService.login(loginRequestSchema.parse(await c.req.json()))));
  app.post("/v1/auth/google/login", async (c) => c.json(await authService.loginWithGoogle(googleLoginRequestSchema.parse(await c.req.json()))));
  app.post("/v1/auth/refresh", async (c) => {
    const body = refreshRequestSchema.parse(await c.req.json());
    return c.json(await authService.refresh(body.refreshToken));
  });
  app.post("/v1/auth/logout", async (c) => {
    const body = logoutRequestSchema.parse(await c.req.json().catch(() => ({})));
    await authService.logout(body.refreshToken);
    return c.json({ ok: true });
  });
  app.post("/v1/auth/password-reset/request", async (c) => {
    const body = passwordResetRequestSchema.parse(await c.req.json());
    return c.json(await authService.requestPasswordReset(body.email));
  });
  app.post("/v1/auth/password-reset/confirm", async (c) => {
    const body = passwordResetConfirmSchema.parse(await c.req.json());
    return c.json({ ok: await authService.confirmPasswordReset(body.token, body.newPassword) });
  });

  app.use("/v1/*", async (c, next) => {
    const publicPaths = ["/v1/health", "/v1/auth/register", "/v1/auth/login", "/v1/auth/google/login", "/v1/auth/refresh", "/v1/auth/logout", "/v1/auth/password-reset/request", "/v1/auth/password-reset/confirm"];
    if (publicPaths.includes(new URL(c.req.url).pathname)) return next();
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
    return c.json({ user: publicUser(await repository.updateTrustedMode(user.id, body.trustedModeEnabled ?? false)) });
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
        throw new HTTPException(400, { message: "calories must be configured before macros" });
      }
      const validationError = validateMacroGoalUpdate(
        body,
        body.calories ?? currentGoals.target.calories
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
      calorieDeltaKcal: body.calorieDeltaKcal
    });
    const summary = await repository.getDailySummary(user.id, date);
    return c.json({ goals, summary });
  });
  app.put("/v1/hydration/daily", async (c) => {
    const user = c.get("authUser");
    const body = dailyHydrationUpdateSchema.parse(await c.req.json());
    const date = body.date ?? new Date().toISOString().slice(0, 10);
    const summary = await repository.updateDailyHydration(user.id, date, body.waterConsumedLiters);
    return c.json({ summary });
  });
  app.post("/v1/goals/calorie-estimate", async (c) => {
    const body = calorieEstimateRequestSchema.parse(await c.req.json());
    return c.json(estimateCalories(body));
  });

  app.get("/v1/actions", (c) => c.json({ actions: actionExecutor.listActions() }));
  app.post("/v1/actions/:actionId/execute", async (c) => {
    const user = c.get("authUser");
    const body = executeActionRequestSchema.parse(await c.req.json());
    const context = buildActionContext(c, user, body.source);
    return c.json(await actionExecutor.execute(c.req.param("actionId"), body.input, context));
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

  app.post("/v1/stt/transcriptions", async (c) => {
    const user = c.get("authUser");
    const traceId = getTraceId(c);
    const upload = await parseAudioUpload(c, user, traceId, "stt.transcription");
    if (upload instanceof Response) return upload;
    console.info("stt.transcription.started", {
      traceId,
      userId: user.id,
      filename: upload.filename,
      mimeType: upload.mimeType,
      bytes: upload.buffer.byteLength,
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
      throw error;
    }

    console.info("stt.transcription.completed", {
      traceId,
      userId: user.id,
      provider: result.provider,
      model: result.model,
      transcriptLength: result.text.length,
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
      const speechHint = upload.activeProposalId
        ? speechHintForProposal(activeProposal)
        : {};
      transcription = await sttProvider.transcribe({
        audio: upload.buffer,
        filename: upload.filename,
        mimeType: upload.mimeType,
        userId: user.id,
        traceId,
        ...speechHint,
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
      throw error;
    }

    const transcript = transcription.text;
    let mealInput: MealInputRunResult;
    try {
      mealInput = await runMealInput({
        c,
        user,
        text: transcript,
        source: upload.source ?? "flutter",
        inputMode: "voice",
        activeProposalId: upload.activeProposalId,
        activeProposal: activeProposal ?? null,
      });
    } catch (error) {
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
        errorStage: "agent",
        error: summarizeError(error),
        timingsMs: {
          stt: sttMs,
          agent: Date.now() - routeStarted - sttMs,
          total: Date.now() - routeStarted,
        },
      });
      throw error;
    }

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
    return c.json(await actionExecutor.execute("propose_meal_log", body, buildActionContext(c, user, "flutter")));
  });
  app.post("/v1/meals/proposals/:id/commit", async (c) => {
    const user = c.get("authUser");
    return c.json(await actionExecutor.execute("commit_meal", { ...(await c.req.json().catch(() => ({}))), proposalId: c.req.param("id") }, buildActionContext(c, user, "flutter")));
  });
  app.post("/v1/meals/:id/correct", async (c) => {
    const user = c.get("authUser");
    return c.json(await actionExecutor.execute("correct_meal", { ...(await c.req.json()), mealId: c.req.param("id") }, buildActionContext(c, user, "flutter")));
  });
  app.delete("/v1/meals/:id", async (c) => {
    const user = c.get("authUser");
    return c.json(await actionExecutor.execute("delete_meal", { mealId: c.req.param("id"), confirmationToken: c.req.query("confirmationToken") }, buildActionContext(c, user, "flutter")));
  });
  app.get("/v1/summary/daily", async (c) => {
    const user = c.get("authUser");
    return c.json(await actionExecutor.execute("get_daily_summary", { date: c.req.query("date") }, buildActionContext(c, user, "flutter")));
  });
  app.get("/v1/meals", async (c) => {
    const user = c.get("authUser");
    return c.json(await actionExecutor.execute("get_meal_history", { limit: Number(c.req.query("limit") ?? 25) }, buildActionContext(c, user, "flutter")));
  });
  app.get("/v1/meal-templates", async (c) => {
    const user = c.get("authUser");
    return c.json(await actionExecutor.execute("get_usual_meals", {}, buildActionContext(c, user, "flutter")));
  });
  app.post("/v1/meal-templates", async (c) => {
    const user = c.get("authUser");
    return c.json(await actionExecutor.execute("create_meal_template", await c.req.json(), buildActionContext(c, user, "flutter")));
  });
  app.put("/v1/meal-templates/:id", async (c) => {
    const user = c.get("authUser");
    return c.json(await actionExecutor.execute(
      "update_meal_template",
      { ...(await c.req.json()), templateId: c.req.param("id") },
      buildActionContext(c, user, "flutter")
    ));
  });
  app.delete("/v1/meal-templates/:id", async (c) => {
    const user = c.get("authUser");
    return c.json(await actionExecutor.execute(
      "delete_meal_template",
      { templateId: c.req.param("id") },
      buildActionContext(c, user, "flutter")
    ));
  });

  return app;
}

type ParsedAudioUpload = {
  buffer: Buffer;
  filename: string;
  mimeType: string;
  source?: ActionSource;
  activeProposalId?: string;
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
    return c.json({
      error: {
        code: "validation_error",
        message: "Invalid multipart/form-data request.",
        traceId,
      },
    }, 400);
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
    return c.json({
      error: {
        code: "validation_error",
        message: "Invalid source.",
        traceId,
      },
    }, 400);
  }
  const activeProposalId = parseOptionalMultipartUuid(body.activeProposalId);
  if (activeProposalId === null) {
    console.warn(`${logPrefix}.invalid_active_proposal`, {
      traceId,
      userId: user.id,
      activeProposalId: body.activeProposalId,
    });
    return c.json({
      error: {
        code: "validation_error",
        message: "Invalid active proposal id.",
        traceId,
      },
    }, 400);
  }

  const audioField = body.audio;
  if (!audioField || (Array.isArray(audioField) && audioField.length === 0)) {
    console.warn(`${logPrefix}.missing_audio`, {
      traceId,
      userId: user.id,
    });
    return c.json({
      error: {
        code: "validation_error",
        message: "Missing audio file.",
        traceId,
      },
    }, 400);
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
    return c.json({
      error: { code: "validation_error", message: validation.error, traceId },
    }, validation.status);
  }

  return {
    buffer: await readAudioBuffer(file),
    filename: validation.filename,
    mimeType: validation.mimeType,
    source: source ?? undefined,
    activeProposalId: activeProposalId ?? undefined,
  };
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

function buildActionContext(c: Context, user: StoredUser, source: ActionSource): ActionContext {
  return {
    actorUserId: user.id,
    actorType: source === "internal_agent" ? "internal_agent" : "user",
    source,
    scopes: user.scopes,
    timezone: c.req.header("x-user-timezone") ?? "UTC",
    locale: c.req.header("accept-language")?.split(",")[0] ?? "en-US",
    trustedModeEnabled: false,
    traceId: getTraceId(c)
  };
}

function speechHintForProposal(proposal?: MealProposal): {
  language?: string;
  prompt?: string;
} {
  const language = speechLanguageFromProposal(proposal);
  return {
    ...(language ? { language } : {}),
    ...(language ? { prompt: speechCorrectionPrompt(language) } : {}),
  };
}

function speechLanguageFromProposal(
  proposal?: MealProposal,
): "es" | "en" | undefined {
  if (!proposal) return undefined;
  return inferSpeechLanguage(
    [
      proposal.phrase,
      proposal.title,
      ...proposal.items.flatMap((item) => [
        item.originalText,
        item.canonicalName,
        item.name,
      ]),
    ]
      .filter((value): value is string => Boolean(value))
      .join(" "),
  );
}

function inferSpeechLanguage(text: string): "es" | "en" | undefined {
  const normalized = text
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  const spanishScore = scoreLanguageTerms(normalized, [
    "anade",
    "agrega",
    "apunta",
    "registra",
    "cambia",
    "corrige",
    "gramo",
    "gramos",
    "kilo",
    "kilos",
    "taza",
    "tazas",
    "cucharada",
    "cucharadas",
    "desayuno",
    "almuerzo",
    "comida",
    "cena",
    "merienda",
    "de",
    "con",
    "sin",
  ]);
  const englishScore = scoreLanguageTerms(normalized, [
    "add",
    "log",
    "record",
    "change",
    "correct",
    "gram",
    "grams",
    "kilogram",
    "kilograms",
    "cup",
    "cups",
    "tablespoon",
    "tablespoons",
    "breakfast",
    "lunch",
    "dinner",
    "snack",
    "of",
    "with",
    "without",
  ]);
  if (spanishScore > englishScore) return "es";
  if (englishScore > spanishScore) return "en";
  return undefined;
}

function scoreLanguageTerms(text: string, terms: string[]): number {
  return terms.reduce(
    (score, term) =>
      score + (new RegExp(`\\b${term}\\b`, "g").exec(text) ? 1 : 0),
    0,
  );
}

function speechCorrectionPrompt(language: "es" | "en"): string {
  if (language === "es") {
    return "Comando de correccion de comida. Transcribe exactamente lo que se dice; no traduzcas. Conserva alimentos, unidades y numeros.";
  }
  return "Meal correction command. Transcribe exactly what is spoken; do not translate. Preserve foods, units, and numbers.";
}

function publicUser(user: StoredUser) {
  const { passwordHash: _passwordHash, scopes: _scopes, ...publicValue } = user;
  return publicValue;
}
