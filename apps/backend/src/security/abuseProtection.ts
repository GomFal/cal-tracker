import { createHmac } from "node:crypto";

import type { AppConfig } from "../config/env.js";

type AbuseScope =
  | "auth_ip"
  | "email_recipient"
  | "cost_user"
  | "cost_ip"
  | "cost_global"
  | "cost_user_concurrency"
  | "cost_global_concurrency"
  | "cost_emergency_pause"
  | "limiter_capacity";

type LimitPolicy = {
  scope: AbuseScope;
  key: string;
  maximum: number;
  windowMs: number;
};

type WindowState = {
  count: number;
  startedAt: number;
  expiresAt: number;
  alerted: boolean;
};

type AbuseLogFields = Record<string, boolean | number | string | undefined>;

export type AbuseProtectionLogger = {
  info(event: string, fields: AbuseLogFields): void;
  warn(event: string, fields: AbuseLogFields): void;
};

export type CostOperationLease = {
  release(): void;
};

export class AbuseLimitExceededError extends Error {
  readonly code = "rate_limit_exceeded";

  constructor(
    public readonly retryAfterSeconds: number,
    public readonly scope: AbuseScope,
  ) {
    super("rate_limit_exceeded");
  }
}

export class InMemoryAbuseProtection {
  private readonly windows = new Map<string, WindowState>();
  private readonly userConcurrency = new Map<string, number>();
  private globalConcurrency = 0;
  private commitsSinceCleanup = 0;

  constructor(
    private readonly config: AppConfig,
    private readonly now: () => number = Date.now,
    private readonly logger: AbuseProtectionLogger = console,
  ) {}

  consumeAuthAttempt(clientIp: string, route: string): void {
    this.consume(
      {
        scope: "auth_ip",
        key: fingerprint(clientIp, this.config.SESSION_TOKEN_PEPPER),
        maximum: this.config.RATE_LIMIT_AUTH_IP_MAX,
        windowMs: this.config.RATE_LIMIT_AUTH_WINDOW_SECONDS * 1000,
      },
      1,
      route,
    );
  }

  consumeEmailAttempt(recipient: string, route: string): void {
    this.consume(
      {
        scope: "email_recipient",
        key: fingerprint(
          recipient.trim().toLowerCase(),
          this.config.SESSION_TOKEN_PEPPER,
        ),
        maximum: this.config.RATE_LIMIT_EMAIL_RECIPIENT_MAX,
        windowMs: this.config.RATE_LIMIT_EMAIL_WINDOW_SECONDS * 1000,
      },
      1,
      route,
    );
  }

  acquireCostOperation(input: {
    userId: string;
    clientIp: string;
    route: string;
  }): CostOperationLease {
    if (!this.config.RATE_LIMIT_COST_OPERATIONS_ENABLED) {
      this.blocked("cost_emergency_pause", input.route, this.config.RATE_LIMIT_EMERGENCY_RETRY_AFTER_SECONDS, {
        estimatedProviderCallsAvoided: 1,
      });
    }

    const userKey = fingerprint(input.userId, this.config.SESSION_TOKEN_PEPPER);
    const ipKey = fingerprint(input.clientIp, this.config.SESSION_TOKEN_PEPPER);
    if (
      this.userConcurrency.get(userKey) !== undefined &&
      this.userConcurrency.get(userKey)! >= this.config.RATE_LIMIT_COST_USER_CONCURRENCY
    ) {
      this.blocked(
        "cost_user_concurrency",
        input.route,
        this.config.RATE_LIMIT_CONCURRENCY_RETRY_AFTER_SECONDS,
        {
          estimatedProviderCallsAvoided: 1,
          identifier: userKey,
          maximum: this.config.RATE_LIMIT_COST_USER_CONCURRENCY,
        },
      );
    }
    if (
      this.config.RATE_LIMIT_COST_GLOBAL_CONCURRENCY > 0 &&
      this.globalConcurrency >= this.config.RATE_LIMIT_COST_GLOBAL_CONCURRENCY
    ) {
      this.blocked(
        "cost_global_concurrency",
        input.route,
        this.config.RATE_LIMIT_CONCURRENCY_RETRY_AFTER_SECONDS,
        {
          estimatedProviderCallsAvoided: 1,
          maximum: this.config.RATE_LIMIT_COST_GLOBAL_CONCURRENCY,
        },
      );
    }

    const windowMs = this.config.RATE_LIMIT_COST_WINDOW_SECONDS * 1000;
    const policies: LimitPolicy[] = [
      {
        scope: "cost_user",
        key: userKey,
        maximum: this.config.RATE_LIMIT_COST_USER_MAX,
        windowMs,
      },
      {
        scope: "cost_ip",
        key: ipKey,
        maximum: this.config.RATE_LIMIT_COST_IP_MAX,
        windowMs,
      },
      {
        scope: "cost_global",
        key: "all",
        maximum: this.config.RATE_LIMIT_COST_GLOBAL_MAX,
        windowMs,
      },
    ];

    // Check every shared bucket before mutating any of them. This keeps a
    // rejected request from spending another quota as a side effect.
    for (const policy of policies) {
      const rejection = this.inspect(policy, 1);
      if (rejection !== undefined) {
        this.blocked(policy.scope, input.route, rejection, {
          estimatedProviderCallsAvoided: 1,
          identifier: policy.key,
          maximum: policy.maximum,
        });
      }
    }
    this.ensureWindowCapacity(policies, input.route);
    for (const policy of policies) {
      this.commit(policy, 1, input.route);
    }

    this.userConcurrency.set(
      userKey,
      (this.userConcurrency.get(userKey) ?? 0) + 1,
    );
    this.globalConcurrency += 1;
    this.logger.info("abuse.cost_operation_admitted", {
      route: input.route,
      user: userKey,
      clientIp: ipKey,
      activeForUser: this.userConcurrency.get(userKey),
      activeGlobal: this.globalConcurrency,
    });

    let released = false;
    return {
      release: () => {
        if (released) return;
        released = true;
        const currentForUser = this.userConcurrency.get(userKey) ?? 0;
        if (currentForUser <= 1) this.userConcurrency.delete(userKey);
        else this.userConcurrency.set(userKey, currentForUser - 1);
        this.globalConcurrency = Math.max(0, this.globalConcurrency - 1);
        this.logger.info("abuse.cost_operation_released", {
          route: input.route,
          user: userKey,
          activeForUser: this.userConcurrency.get(userKey) ?? 0,
          activeGlobal: this.globalConcurrency,
        });
      },
    };
  }

  private consume(policy: LimitPolicy, amount: number, route: string): void {
    const rejection = this.inspect(policy, amount);
    if (rejection !== undefined) {
      this.blocked(policy.scope, route, rejection, {
        identifier: policy.key,
        maximum: policy.maximum,
      });
    }
    this.ensureWindowCapacity([policy], route);
    this.commit(policy, amount, route);
  }

  private inspect(policy: LimitPolicy, amount: number): number | undefined {
    if (policy.maximum <= 0) return undefined;
    const now = this.now();
    const bucketKey = this.bucketKey(policy);
    const existing = this.windows.get(bucketKey);
    if (!existing || now - existing.startedAt >= policy.windowMs) {
      return amount > policy.maximum
        ? Math.max(1, Math.ceil(policy.windowMs / 1000))
        : undefined;
    }
    if (existing.count + amount <= policy.maximum) return undefined;
    return Math.max(
      1,
      Math.ceil((existing.startedAt + policy.windowMs - now) / 1000),
    );
  }

  private commit(policy: LimitPolicy, amount: number, route: string): void {
    if (policy.maximum <= 0) return;
    const now = this.now();
    const bucketKey = this.bucketKey(policy);
    const existing = this.windows.get(bucketKey);
    const state = !existing || now - existing.startedAt >= policy.windowMs
      ? {
          count: amount,
          startedAt: now,
          expiresAt: now + policy.windowMs,
          alerted: false,
        }
      : { ...existing, count: existing.count + amount };
    const alertAt = Math.max(
      1,
      Math.ceil(policy.maximum * this.config.RATE_LIMIT_ALERT_PERCENT / 100),
    );
    if (!state.alerted && state.count >= alertAt) {
      state.alerted = true;
      this.logger.warn("abuse.limit_threshold_reached", {
        scope: policy.scope,
        route,
        identifier: policy.key,
        count: state.count,
        maximum: policy.maximum,
        windowSeconds: policy.windowMs / 1000,
      });
    }
    this.windows.set(bucketKey, state);
    this.commitsSinceCleanup += 1;
    if (this.commitsSinceCleanup >= 1024) this.removeExpiredWindows(now);
  }

  private bucketKey(policy: LimitPolicy): string {
    return `${policy.scope}:${policy.key}`;
  }

  private ensureWindowCapacity(policies: LimitPolicy[], route: string): void {
    const enabledPolicies = policies.filter((policy) => policy.maximum > 0);
    const missingBeforeCleanup = new Set(
      enabledPolicies
        .map((policy) => this.bucketKey(policy))
        .filter((key) => !this.windows.has(key)),
    ).size;
    if (
      this.windows.size + missingBeforeCleanup <=
      this.config.RATE_LIMIT_MAX_BUCKETS
    ) {
      return;
    }

    const now = this.now();
    this.removeExpiredWindows(now);
    const missingAfterCleanup = new Set(
      enabledPolicies
        .map((policy) => this.bucketKey(policy))
        .filter((key) => !this.windows.has(key)),
    ).size;
    if (
      this.windows.size + missingAfterCleanup <=
      this.config.RATE_LIMIT_MAX_BUCKETS
    ) {
      return;
    }

    this.blocked(
      "limiter_capacity",
      route,
      this.config.RATE_LIMIT_EMERGENCY_RETRY_AFTER_SECONDS,
      {
        maximum: this.config.RATE_LIMIT_MAX_BUCKETS,
        estimatedProviderCallsAvoided: 1,
      },
    );
  }

  private removeExpiredWindows(now: number): void {
    this.commitsSinceCleanup = 0;
    for (const [key, state] of this.windows) {
      if (state.expiresAt <= now) this.windows.delete(key);
    }
  }

  private blocked(
    scope: AbuseScope,
    route: string,
    retryAfterSeconds: number,
    fields: AbuseLogFields = {},
  ): never {
    this.logger.warn("abuse.request_blocked", {
      scope,
      route,
      retryAfterSeconds,
      ...fields,
    });
    throw new AbuseLimitExceededError(retryAfterSeconds, scope);
  }
}

function fingerprint(value: string, pepper: string): string {
  return createHmac("sha256", pepper).update(value).digest("hex").slice(0, 16);
}
