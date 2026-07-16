import { rateLimitErrorResponseSchema } from "@cal-tracker/contracts";
import { serve } from "@hono/node-server";
import { createHmac } from "node:crypto";
import { describe, expect, it, vi } from "vitest";

import type {
  AgentToolDecision,
  ChatAgentProvider,
} from "../agent/chatAgentProvider.js";
import { loadConfig, type AppConfig } from "../config/env.js";
import {
  AbuseLimitExceededError,
  InMemoryAbuseProtection,
  type AbuseProtectionLogger,
} from "../security/abuseProtection.js";
import {
  buildTestApp,
  FakeAuthEmailSender,
  registerAndAuth,
  testBreadItem,
} from "./testApp.js";

const noToolDecision: AgentToolDecision = {
  toolCalls: [],
  rawResponse: {},
};

describe("in-memory abuse protection", () => {
  it("enforces an auth window and resets it deterministically", () => {
    let now = 1_000;
    const protection = protectionWith(
      { RATE_LIMIT_AUTH_IP_MAX: 2, RATE_LIMIT_AUTH_WINDOW_SECONDS: 60 },
      () => now,
    );

    protection.consumeAuthAttempt("198.51.100.1", "/v1/auth/login");
    protection.consumeAuthAttempt("198.51.100.1", "/v1/auth/register");
    expect(() =>
      protection.consumeAuthAttempt("198.51.100.1", "/v1/auth/login"),
    ).toThrowError(expect.objectContaining({
      code: "rate_limit_exceeded",
      retryAfterSeconds: 60,
      scope: "auth_ip",
    }));

    now += 60_000;
    expect(() =>
      protection.consumeAuthAttempt("198.51.100.1", "/v1/auth/login"),
    ).not.toThrow();
  });

  it("combines normalized email attempts across registration and recovery", () => {
    const protection = protectionWith({ RATE_LIMIT_EMAIL_RECIPIENT_MAX: 2 });
    protection.consumeEmailAttempt(" User@Example.com ", "/v1/auth/register");
    protection.consumeEmailAttempt(
      "user@example.com",
      "/v1/auth/password-reset/request",
    );

    expect(() =>
      protection.consumeEmailAttempt("USER@example.com", "/v1/auth/register"),
    ).toThrowError(expect.objectContaining({ scope: "email_recipient" }));
  });

  it("prioritizes user quota while keeping a looser shared-IP safety net", () => {
    const protection = protectionWith({
      RATE_LIMIT_COST_USER_MAX: 2,
      RATE_LIMIT_COST_IP_MAX: 10,
      RATE_LIMIT_COST_GLOBAL_MAX: 20,
    });
    protection.acquireCostOperation({
      userId: "user-a",
      clientIp: "203.0.113.8",
      route: "/v1/agent/runs",
    }).release();
    protection.acquireCostOperation({
      userId: "user-a",
      clientIp: "203.0.113.8",
      route: "/v1/stt/transcriptions",
    }).release();

    expect(() => protection.acquireCostOperation({
      userId: "user-a",
      clientIp: "203.0.113.8",
      route: "/v1/agent/runs",
    })).toThrowError(expect.objectContaining({ scope: "cost_user" }));

    expect(() => protection.acquireCostOperation({
      userId: "user-b",
      clientIp: "203.0.113.8",
      route: "/v1/agent/runs",
    }).release()).not.toThrow();
  });

  it("does not spend hourly quota when concurrency rejects an operation", () => {
    const protection = protectionWith({
      RATE_LIMIT_COST_USER_MAX: 3,
      RATE_LIMIT_COST_USER_CONCURRENCY: 2,
    });
    const input = {
      userId: "user-a",
      clientIp: "203.0.113.9",
      route: "/v1/agent/runs",
    };
    const first = protection.acquireCostOperation(input);
    const second = protection.acquireCostOperation(input);
    expect(() => protection.acquireCostOperation(input)).toThrowError(
      expect.objectContaining({ scope: "cost_user_concurrency" }),
    );

    first.release();
    protection.acquireCostOperation(input).release();
    second.release();
    expect(() => protection.acquireCostOperation(input)).toThrowError(
      expect.objectContaining({ scope: "cost_user" }),
    );
  });

  it("supports an auditable emergency pause", () => {
    const logger = fakeLogger();
    const protection = protectionWith(
      { RATE_LIMIT_COST_OPERATIONS_ENABLED: false },
      Date.now,
      logger,
    );

    expect(() => protection.acquireCostOperation({
      userId: "user-a",
      clientIp: "203.0.113.10",
      route: "/v1/agent/runs",
    })).toThrowError(AbuseLimitExceededError);
    expect(logger.warn).toHaveBeenCalledWith(
      "abuse.request_blocked",
      expect.objectContaining({ scope: "cost_emergency_pause" }),
    );
  });

  it("bounds bucket cardinality, preserves active quotas, and reuses expired capacity", () => {
    let now = 1_000;
    const protection = protectionWith(
      {
        RATE_LIMIT_AUTH_IP_MAX: 1,
        RATE_LIMIT_AUTH_WINDOW_SECONDS: 60,
        RATE_LIMIT_MAX_BUCKETS: 1,
      },
      () => now,
    );

    protection.consumeAuthAttempt("198.51.100.1", "/v1/auth/login");
    expect(() =>
      protection.consumeAuthAttempt("198.51.100.2", "/v1/auth/login"),
    ).toThrowError(expect.objectContaining({ scope: "limiter_capacity" }));
    expect(() =>
      protection.consumeAuthAttempt("198.51.100.1", "/v1/auth/login"),
    ).toThrowError(expect.objectContaining({ scope: "auth_ip" }));

    now += 60_000;
    expect(() =>
      protection.consumeAuthAttempt("198.51.100.2", "/v1/auth/login"),
    ).not.toThrow();
  });

  it("reserves all cost buckets atomically when capacity is scarce", () => {
    const config = {
      ...loadConfig({ NODE_ENV: "test" } as NodeJS.ProcessEnv),
      RATE_LIMIT_MAX_BUCKETS: 2,
    };
    const protection = new InMemoryAbuseProtection(config, Date.now, fakeLogger());
    const input = {
      userId: "user-a",
      clientIp: "203.0.113.11",
      route: "/v1/agent/runs",
    };

    expect(() => protection.acquireCostOperation(input)).toThrowError(
      expect.objectContaining({ scope: "limiter_capacity" }),
    );
    config.RATE_LIMIT_COST_GLOBAL_MAX = 0;
    expect(() => protection.acquireCostOperation(input).release()).not.toThrow();
  });
});

describe("abuse protection HTTP integration", () => {
  it("uses the Node adapter socket address for direct traffic", async () => {
    const logger = fakeLogger();
    const { app } = buildTestApp({
      configOverrides: {
        RATE_LIMIT_TRUST_PROXY_HEADERS: false,
        RATE_LIMIT_AUTH_IP_MAX: 1,
      },
      abuseProtectionLogger: logger,
    });
    const server = serve({ fetch: app.fetch, hostname: "127.0.0.1", port: 0 });
    await new Promise<void>((resolve) => server.once("listening", resolve));
    const address = server.address();
    if (!address || typeof address === "string") throw new Error("test_server_address_missing");

    try {
      const response = await fetch(`http://127.0.0.1:${address.port}/v1/auth/login`, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-real-ip": "198.51.100.200",
        },
        body: JSON.stringify({ email: "missing@example.com", password: "password123" }),
      });
      expect(response.status).toBe(401);
      const threshold = logger.warn.mock.calls.find(
        ([event]) => event === "abuse.limit_threshold_reached",
      );
      expect(threshold?.[1]).toMatchObject({
        scope: "auth_ip",
        identifier: createHmac(
          "sha256",
          "test-session-pepper-with-more-than-32-characters",
        )
          .update("127.0.0.1")
          .digest("hex")
          .slice(0, 16),
      });
    } finally {
      await new Promise<void>((resolve, reject) => {
        server.close((error) => error ? reject(error) : resolve());
      });
    }
  });

  it("ignores spoofed forwarding headers when proxy trust is disabled", async () => {
    const { request } = buildTestApp({
      configOverrides: {
        RATE_LIMIT_TRUST_PROXY_HEADERS: false,
        RATE_LIMIT_AUTH_IP_MAX: 1,
      },
      abuseProtectionLogger: fakeLogger(),
    });
    const loginFrom = (ip: string) => request("http://localhost/v1/auth/login", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-real-ip": ip,
      },
      body: JSON.stringify({ email: "missing@example.com", password: "password123" }),
    });

    expect((await loginFrom("198.51.100.1")).status).toBe(401);
    expect((await loginFrom("198.51.100.2")).status).toBe(429);
  });

  it("returns the stable 429 contract and Retry-After for combined auth attempts", async () => {
    const { request } = buildTestApp({
      configOverrides: {
        RATE_LIMIT_TRUST_PROXY_HEADERS: true,
        RATE_LIMIT_AUTH_IP_MAX: 2,
      },
      abuseProtectionLogger: fakeLogger(),
    });
    const requestLogin = () => request("http://localhost/v1/auth/login", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-real-ip": "198.51.100.20",
      },
      body: JSON.stringify({ email: "missing@example.com", password: "password123" }),
    });

    expect((await requestLogin()).status).toBe(401);
    expect((await requestLogin()).status).toBe(401);
    const blocked = await requestLogin();

    expect(blocked.status).toBe(429);
    expect(blocked.headers.get("retry-after")).toBe("60");
    expect(rateLimitErrorResponseSchema.parse(await blocked.json())).toMatchObject({
      error: {
        code: "rate_limit_exceeded",
        details: { retryAfterSeconds: 60 },
      },
    });
  });

  it("limits recipient email attempts before another email can be sent", async () => {
    const sender = new FakeAuthEmailSender();
    const { request } = buildTestApp({
      authEmailSender: sender,
      configOverrides: {
        RATE_LIMIT_AUTH_IP_MAX: 20,
        RATE_LIMIT_EMAIL_RECIPIENT_MAX: 3,
      },
      abuseProtectionLogger: fakeLogger(),
    });
    const registration = () => request("http://localhost/v1/auth/register", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "target@example.com",
        password: "password123",
        displayName: "Target User",
      }),
    });

    for (let attempt = 0; attempt < 3; attempt++) {
      expect((await registration()).status).toBe(200);
    }
    const blocked = await registration();
    expect(blocked.status).toBe(429);
    expect(sender.confirmations).toHaveLength(3);
  });

  it("blocks sequential costly retries before invoking the provider again", async () => {
    const provider = new CountingAgentProvider();
    const { request } = buildTestApp({
      agentProvider: provider,
      configOverrides: { RATE_LIMIT_COST_USER_MAX: 2 },
      abuseProtectionLogger: fakeLogger(),
    });
    const auth = await registerAndAuth(request);
    const run = () => request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({ text: "log a meal" }),
    });

    expect((await run()).status).toBe(200);
    expect((await run()).status).toBe(200);
    expect((await run()).status).toBe(429);
    expect(provider.calls).toBe(2);
  });

  it("caps concurrency and releases it after completed requests", async () => {
    const provider = new ControlledAgentProvider();
    const { request } = buildTestApp({
      agentProvider: provider,
      configOverrides: {
        RATE_LIMIT_COST_USER_MAX: 10,
        RATE_LIMIT_COST_USER_CONCURRENCY: 2,
      },
      abuseProtectionLogger: fakeLogger(),
    });
    const auth = await registerAndAuth(request);
    const run = () => request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({ text: "log a meal" }),
    });

    const first = run();
    const second = run();
    await vi.waitFor(() => expect(provider.calls).toBe(2));
    expect((await run()).status).toBe(429);
    expect(provider.calls).toBe(2);

    provider.resolveAll();
    expect((await first).status).toBe(200);
    expect((await second).status).toBe(200);

    const afterRelease = run();
    await vi.waitFor(() => expect(provider.calls).toBe(3));
    provider.resolveAll();
    expect((await afterRelease).status).toBe(200);
  });

  it("releases concurrency after provider failure", async () => {
    const provider = new FailOnceAgentProvider();
    const { request } = buildTestApp({
      agentProvider: provider,
      configOverrides: {
        RATE_LIMIT_COST_USER_MAX: 10,
        RATE_LIMIT_COST_USER_CONCURRENCY: 1,
      },
      abuseProtectionLogger: fakeLogger(),
    });
    const auth = await registerAndAuth(request);
    const run = () => request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({ text: "log a meal" }),
    });

    expect((await run()).status).toBe(503);
    expect((await run()).status).toBe(200);
    expect(provider.calls).toBe(2);
  });

  it("releases streaming concurrency when the client cancels", async () => {
    const { request } = buildTestApp({
      configOverrides: {
        RATE_LIMIT_COST_USER_MAX: 10,
        RATE_LIMIT_COST_USER_CONCURRENCY: 1,
      },
      abuseProtectionLogger: fakeLogger(),
    });
    const auth = await registerAndAuth(request);
    const chat = () => request("http://localhost/v1/agent/chat", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({ message: "show my summary" }),
    });

    const first = await chat();
    expect(first.status).toBe(200);
    const blocked = await chat();
    expect(blocked.status).toBe(429);
    expect(await blocked.json()).toMatchObject({
      error: { code: "rate_limit_exceeded" },
    });
    await first.body?.cancel();

    const afterCancel = await chat();
    expect(afterCancel.status).toBe(200);
    await afterCancel.body?.cancel();
  });

  it("protects costly dynamic action routes but does not charge deterministic meal edits", async () => {
    const provider = new CountingAgentProvider();
    const draft = {
      calls: 0,
      async draft() {
        this.calls += 1;
        return { explicitFields: [], aliases: [] };
      },
    };
    const { request } = buildTestApp({
      agentProvider: provider,
      usualFoodDraftProvider: draft,
      configOverrides: { RATE_LIMIT_COST_USER_MAX: 1 },
      abuseProtectionLogger: fakeLogger(),
    });
    const auth = await registerAndAuth(request);

    const spent = await request("http://localhost/v1/agent/runs", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({ text: "log a meal" }),
    });
    expect(spent.status).toBe(200);

    const blockedDraft = await request(
      "http://localhost/v1/actions/draft_usual_food/execute",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({ input: { text: "my usual food" } }),
      },
    );
    expect(blockedDraft.status).toBe(429);
    expect(draft.calls).toBe(0);

    const deterministicEdit = await request(
      "http://localhost/v1/meals/00000000-0000-4000-8000-000000000001/correct",
      {
        method: "POST",
        headers: auth.authHeader,
        body: JSON.stringify({ items: [testBreadItem] }),
      },
    );
    expect(deterministicEdit.status).toBe(400);
    expect((await deterministicEdit.json() as { error: { code: string } }).error.code)
      .toBe("meal_not_found");
  });
});

function protectionWith(
  overrides: Partial<AppConfig>,
  now: () => number = Date.now,
  logger: AbuseProtectionLogger = fakeLogger(),
): InMemoryAbuseProtection {
  const config = {
    ...loadConfig({ NODE_ENV: "test" } as NodeJS.ProcessEnv),
    ...overrides,
  };
  return new InMemoryAbuseProtection(config, now, logger);
}

function fakeLogger() {
  return {
    info: vi.fn<AbuseProtectionLogger["info"]>(),
    warn: vi.fn<AbuseProtectionLogger["warn"]>(),
  } satisfies AbuseProtectionLogger;
}

class CountingAgentProvider implements ChatAgentProvider {
  calls = 0;

  async runWithTools(): Promise<AgentToolDecision> {
    this.calls += 1;
    return noToolDecision;
  }
}

class ControlledAgentProvider implements ChatAgentProvider {
  calls = 0;
  private readonly pending: Array<(value: AgentToolDecision) => void> = [];

  async runWithTools(): Promise<AgentToolDecision> {
    this.calls += 1;
    return new Promise((resolve) => this.pending.push(resolve));
  }

  resolveAll(): void {
    for (const resolve of this.pending.splice(0)) resolve(noToolDecision);
  }
}

class FailOnceAgentProvider implements ChatAgentProvider {
  calls = 0;

  async runWithTools(): Promise<AgentToolDecision> {
    this.calls += 1;
    if (this.calls === 1) throw new Error("provider unavailable");
    return noToolDecision;
  }
}
