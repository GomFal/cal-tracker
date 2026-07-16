import { sql, type SQL } from "drizzle-orm";
import { PgDialect } from "drizzle-orm/pg-core";
import { describe, expect, it, vi } from "vitest";
import { InMemoryRepository } from "../repository/inMemory.js";
import { PostgresRepository } from "../repository/postgres.js";

describe("password reset repository semantics", () => {
  it("consumes an in-memory reset once, revokes all sessions, and rejects expired tokens", async () => {
    const repository = InMemoryRepository.seeded();
    const user = await repository.createUser({
      email: "reset@example.com",
      displayName: "Reset User",
      passwordHash: "old-password-hash",
      emailVerifiedAt: new Date().toISOString(),
      scopes: [],
    });
    await repository.createSession({
      id: "session-1",
      userId: user.id,
      refreshTokenHash: "refresh-1",
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
    });
    await repository.createSession({
      id: "session-2",
      userId: user.id,
      refreshTokenHash: "refresh-2",
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
    });
    await repository.createPasswordReset({
      userId: user.id,
      tokenHash: "valid-reset-hash",
      expiresAt: new Date(Date.now() + 60_000).toISOString(),
    });

    const confirmations = await Promise.all([
      repository.consumePasswordReset("valid-reset-hash", "new-password-hash"),
      repository.consumePasswordReset("valid-reset-hash", "other-password-hash"),
    ]);

    expect(confirmations.sort()).toEqual([false, true]);
    await expect(repository.findSessionByRefreshTokenHash("refresh-1")).resolves.toBeUndefined();
    await expect(repository.findSessionByRefreshTokenHash("refresh-2")).resolves.toBeUndefined();
    await expect(
      repository.rotateSession(
        "session-1",
        "rotated-after-reset",
        new Date(Date.now() + 60_000).toISOString(),
      ),
    ).resolves.toBeUndefined();
    await expect(repository.findUserById(user.id)).resolves.toMatchObject({
      passwordHash: "new-password-hash",
    });

    const audits = await repository.listAuditEvents(user.id);
    expect(audits).toHaveLength(1);
    expect(audits[0]).toMatchObject({
      eventType: "auth.password_reset_completed",
      metadata: { sessionRevocation: "all" },
    });

    await repository.createPasswordReset({
      userId: user.id,
      tokenHash: "expired-reset-hash",
      expiresAt: new Date(Date.now() - 1).toISOString(),
    });
    await expect(
      repository.consumePasswordReset("expired-reset-hash", "expired-password-hash"),
    ).resolves.toBe(false);
    await expect(repository.findUserById(user.id)).resolves.toMatchObject({
      passwordHash: "new-password-hash",
    });
    await expect(repository.listAuditEvents(user.id)).resolves.toHaveLength(1);
  });

  it("runs the PostgreSQL credential update, global revocation, and audit in one transaction", async () => {
    const statements: string[] = [];
    const repository = postgresRepositoryWithTransaction(async (query) => {
      const text = sqlText(query);
      statements.push(text);
      if (text.includes("UPDATE password_reset_tokens")) {
        return [{ user_id: "00000000-0000-4000-8000-000000000001" }];
      }
      return [];
    });

    await expect(
      repository.consumePasswordReset("reset-hash", "new-password-hash"),
    ).resolves.toBe(true);

    expect(statements).toHaveLength(4);
    expect(statements[0]).toContain("UPDATE password_reset_tokens");
    expect(statements[0]).toContain("used_at IS NULL");
    expect(statements[0]).toContain("expires_at > now()");
    expect(statements[1]).toContain("INSERT INTO user_credentials");
    expect(statements[1]).toContain("ON CONFLICT (user_id)");
    expect(statements[2]).toContain("UPDATE auth_sessions");
    expect(statements[2]).toContain("revoked_at IS NULL");
    expect(statements[3]).toContain("INSERT INTO audit_events");
    expect(statements[3]).toContain("auth.password_reset_completed");
  });

  it("does not commit a new password if PostgreSQL session revocation fails", async () => {
    const committed = {
      password: "old-password-hash",
      resetUsed: false,
      sessionsRevoked: false,
      auditCount: 0,
    };
    const repository = postgresRepositoryWithStatefulTransaction(committed);

    await expect(
      repository.consumePasswordReset("reset-hash", "new-password-hash"),
    ).rejects.toThrow("session_revocation_failed");

    expect(committed).toEqual({
      password: "old-password-hash",
      resetUsed: false,
      sessionsRevoked: false,
      auditCount: 0,
    });
  });
});

type TransactionExecutor = (query: SQL) => Promise<Record<string, unknown>[]>;

function postgresRepositoryWithTransaction(execute: TransactionExecutor): PostgresRepository {
  const repository = new PostgresRepository("postgres://unused");
  Object.defineProperty(repository, "db", {
    value: {
      transaction: vi.fn(async <T>(callback: (tx: { execute: TransactionExecutor }) => Promise<T>) =>
        callback({ execute })),
    },
  });
  return repository;
}

function postgresRepositoryWithStatefulTransaction(committed: {
  password: string;
  resetUsed: boolean;
  sessionsRevoked: boolean;
  auditCount: number;
}): PostgresRepository {
  const repository = new PostgresRepository("postgres://unused");
  Object.defineProperty(repository, "db", {
    value: {
      transaction: vi.fn(async <T>(callback: (tx: { execute: TransactionExecutor }) => Promise<T>) => {
        const pending = { ...committed };
        const result = await callback({
          execute: async (query) => {
            const text = sqlText(query);
            if (text.includes("UPDATE password_reset_tokens")) {
              pending.resetUsed = true;
              return [{ user_id: "00000000-0000-4000-8000-000000000001" }];
            }
            if (text.includes("INSERT INTO user_credentials")) {
              pending.password = "new-password-hash";
              return [];
            }
            if (text.includes("UPDATE auth_sessions")) {
              throw new Error("session_revocation_failed");
            }
            if (text.includes("INSERT INTO audit_events")) {
              pending.auditCount += 1;
            }
            return [];
          },
        });
        Object.assign(committed, pending);
        return result;
      }),
    },
  });
  return repository;
}

const dialect = new PgDialect();

function sqlText(query: SQL): string {
  return dialect.sqlToQuery(sql`${query}`).sql.replace(/\s+/g, " ").trim();
}
