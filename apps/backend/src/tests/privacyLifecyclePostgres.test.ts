import postgres from "postgres";
import { execFile } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { promisify } from "node:util";
import { afterAll, describe, expect, it } from "vitest";
import { PostgresRepository } from "../repository/postgres.js";

const enabled = process.env.RUN_PRIVACY_POSTGRES_TESTS === "1";
const databaseUrl = process.env.DATABASE_URL ?? "";

const describePostgres = enabled ? describe : describe.skip;
const execFileAsync = promisify(execFile);
const overlayScript = resolve(
  import.meta.dirname,
  "../../../../infra/deploy/privacy-ledger-overlay.sh",
);

async function runOverlay(
  action: "export" | "import",
  overlayDirectory: string,
): Promise<void> {
  const url = new URL(databaseUrl);
  const { stderr } = await execFileAsync("bash", [overlayScript, action, "dev"], {
    env: {
      ...globalThis.process.env,
      CAL_TRACKER_PRIVACY_LEDGER_DIR: overlayDirectory,
      POSTGRES_CONTAINER: "cal-tracker-postgres-1",
      POSTGRES_DATABASE: url.pathname.slice(1),
      POSTGRES_USER: decodeURIComponent(url.username),
      PRIVACY_LEDGER_SCHEMA: globalThis.process.env.DATABASE_SCHEMA ?? "public",
    },
  });
  expect(stderr).toBe("");
}

describePostgres("privacy lifecycle PostgreSQL integration", () => {
  const repository = new PostgresRepository(databaseUrl);
  const sql = postgres(databaseUrl, { max: 1 });
  const ledgerIds: string[] = [];

  afterAll(async () => {
    if (ledgerIds.length > 0) {
      await sql`DELETE FROM privacy_deletion_requests WHERE conversation_id = ANY(${ledgerIds}::uuid[])`;
    }
    await repository.close();
    await sql.end({ timeout: 5 });
  });

  it("enforces account cascade, tombstone guards, restore reapply, and isolated savepoints", async () => {
    const account = await repository.createUser({
      email: `privacy-account-${crypto.randomUUID()}@example.com`,
      displayName: "Privacy account",
      scopes: [],
    });
    const accountConversation = await repository.createAgentConversation(account.id);
    ledgerIds.push(accountConversation.id);
    await repository.addAgentConversationMessage(account.id, accountConversation.id, {
      role: "user",
      content: "account private content",
      traceId: `trace-${crypto.randomUUID()}`,
    });
    await repository.createTranscriptionRecord({
      traceId: `trace-${crypto.randomUUID()}`,
      userId: account.id,
      conversationId: accountConversation.id,
      surface: "agent_chat_audio",
      transcriptText: "account private transcript",
      transcriptLength: 26,
      status: "completed",
      metadata: {},
    });

    await sql`DELETE FROM users WHERE id = ${account.id}`;
    const accountLedger = await sql`
      SELECT * FROM privacy_deletion_requests
      WHERE conversation_id = ${accountConversation.id}
    `;
    expect(accountLedger).toHaveLength(1);
    expect(accountLedger[0]?.status).toBe("purged");
    expect(accountLedger[0]?.result_code).toBe("account_deleted_cascade");
    expect(await sql`SELECT id FROM transcription_records WHERE user_id = ${account.id}`).toHaveLength(0);
    expect(await sql`SELECT id FROM agent_conversations WHERE id = ${accountConversation.id}`).toHaveLength(0);

    const owner = await repository.createUser({
      email: `privacy-owner-${crypto.randomUUID()}@example.com`,
      displayName: "Privacy owner",
      scopes: [],
    });
    const guarded = await repository.createAgentConversation(owner.id);
    ledgerIds.push(guarded.id);
    await repository.requestAgentConversationDeletion(owner.id, guarded.id);
    const rejected = await sql`
      INSERT INTO agent_messages (conversation_id, user_id, role, content)
      VALUES (${guarded.id}, ${owner.id}, 'user', 'must be rejected')
      RETURNING id
    `;
    expect(rejected).toHaveLength(0);
    await repository.runPrivacyLifecycle();

    // Export the live, external overlay, then simulate an old backup that has
    // neither the tombstone nor the already-purged conversation.
    const overlayDirectory = await mkdtemp(`${tmpdir()}/privacy-overlay-`);
    await runOverlay("export", overlayDirectory);
    await sql`DELETE FROM privacy_deletion_requests WHERE conversation_id = ${guarded.id}`;
    await sql`
      INSERT INTO agent_conversations (id, user_id, title)
      VALUES (${guarded.id}, ${owner.id}, 'restored sensitive title')
    `;
    await sql`
      INSERT INTO agent_messages (conversation_id, user_id, role, content)
      VALUES (${guarded.id}, ${owner.id}, 'user', 'content from old backup')
    `;
    try {
      await runOverlay("import", overlayDirectory);
      expect(await sql`
        SELECT id FROM privacy_deletion_requests WHERE conversation_id = ${guarded.id}
      `).toHaveLength(1);
      const reapply = await repository.runPrivacyLifecycle({
        reapplyBefore: new Date(Date.now() + 1000).toISOString(),
        batchSize: 100,
      });
      expect(reapply.purged).toBeGreaterThanOrEqual(1);
      expect(await sql`SELECT id FROM agent_conversations WHERE id = ${guarded.id}`).toHaveLength(0);

      // Re-importing an older overlay must not replace a ledger entry that is
      // already present (for example, one created after the restored dump).
      await sql`
        UPDATE privacy_deletion_requests
        SET result_code = 'newer_current_entry'
        WHERE conversation_id = ${guarded.id}
      `;
      await runOverlay("import", overlayDirectory);
      const preserved = await sql`
        SELECT result_code FROM privacy_deletion_requests WHERE conversation_id = ${guarded.id}
      `;
      expect(preserved[0]?.result_code).toBe("newer_current_entry");
    } finally {
      await rm(overlayDirectory, { recursive: true, force: true });
    }

    const blocked = await repository.createAgentConversation(owner.id);
    const healthy = await repository.createAgentConversation(owner.id);
    ledgerIds.push(blocked.id, healthy.id);
    await repository.requestAgentConversationDeletion(owner.id, blocked.id);
    await repository.requestAgentConversationDeletion(owner.id, healthy.id);
    const blockerTable = `privacy_blocker_${crypto.randomUUID().replaceAll("-", "")}`;
    await sql.unsafe(
      `CREATE TABLE "${blockerTable}" (conversation_id uuid PRIMARY KEY REFERENCES agent_conversations(id) ON DELETE RESTRICT)`,
    );
    try {
      await sql.unsafe(
        `INSERT INTO "${blockerTable}" (conversation_id) VALUES ('${blocked.id}')`,
      );
      const isolated = await repository.runPrivacyLifecycle({ batchSize: 100 });
      expect(isolated.failed).toBe(1);
      expect(isolated.purged).toBeGreaterThanOrEqual(1);
      expect(await repository.getAgentConversationDeletion(owner.id, blocked.id)).toMatchObject({
        status: "failed",
        resultCode: "purge_retry_required",
      });
      await sql.unsafe(`DELETE FROM "${blockerTable}"`);
      expect(await repository.runPrivacyLifecycle({ batchSize: 100 })).toMatchObject({
        failed: 0,
      });
      expect(await repository.getAgentConversationDeletion(owner.id, blocked.id)).toMatchObject({
        status: "purged",
      });
    } finally {
      await sql.unsafe(`DROP TABLE IF EXISTS "${blockerTable}"`);
      await sql`DELETE FROM users WHERE id = ${owner.id}`;
    }
  }, 30_000);
});
