import { describe, expect, it } from "vitest";
import { InMemoryRepository } from "../repository/inMemory.js";
import type { PrivacyDeletionRequest } from "../repository/types.js";

async function user(repository: InMemoryRepository, suffix: string) {
  return repository.createUser({
    email: `${suffix}@example.com`,
    displayName: suffix,
    scopes: [],
  });
}

describe("privacy lifecycle", () => {
  it("keeps a content-free tombstone, hides from admin, and purges correlated content idempotently", async () => {
    const repository = new InMemoryRepository();
    const owner = await user(repository, "owner");
    const conversation = await repository.createAgentConversation(owner.id);
    await repository.addAgentConversationMessage(owner.id, conversation.id, {
      role: "user",
      content: "private nutrition text",
      traceId: "trace-private",
      turnId: "11111111-1111-1111-1111-111111111111",
    });
    await repository.createTranscriptionRecord({
      traceId: "trace-private",
      userId: owner.id,
      conversationId: conversation.id,
      turnId: "11111111-1111-1111-1111-111111111111",
      surface: "agent_chat_audio",
      transcriptText: "private transcript",
      transcriptLength: 18,
      status: "completed",
      metadata: {},
    });

    const request = await repository.requestAgentConversationDeletion(owner.id, conversation.id);
    expect(request).toMatchObject({ status: "pending", attemptCount: 0 });
    expect(await repository.listAdminAgentConversations({ includeHidden: true })).toEqual([]);
    expect(await repository.getAdminAgentConversationMessages(conversation.id, true)).toEqual([]);

    const result = await repository.runPrivacyLifecycle();
    expect(result).toMatchObject({ processed: 1, purged: 1, failed: 0 });
    expect(await repository.listTranscriptionRecords({ conversationId: conversation.id })).toEqual([]);
    expect(await repository.runPrivacyLifecycle()).toMatchObject({ processed: 0, purged: 0 });
    const tombstone = await repository.getAgentConversationDeletion(owner.id, conversation.id);
    expect(tombstone).toMatchObject({
      subjectUserId: owner.id,
      conversationId: conversation.id,
      status: "purged",
      resultCode: "active_content_purged",
    });
    expect(JSON.stringify(tombstone)).not.toContain("private");
  });

  it("isolates a failed request, audits it, and retries it without blocking another purge", async () => {
    const repository = new FailOncePrivacyRepository();
    const owner = await user(repository, "retry-owner");
    const first = await repository.createAgentConversation(owner.id);
    const second = await repository.createAgentConversation(owner.id);
    repository.failConversationId = first.id;
    await repository.requestAgentConversationDeletion(owner.id, first.id);
    await repository.requestAgentConversationDeletion(owner.id, second.id);

    expect(await repository.runPrivacyLifecycle()).toMatchObject({
      processed: 2,
      purged: 1,
      failed: 1,
    });
    expect(await repository.getAgentConversationDeletion(owner.id, first.id)).toMatchObject({
      status: "failed",
      attemptCount: 1,
      resultCode: "purge_retry_required",
    });
    expect(await repository.runPrivacyLifecycle()).toMatchObject({
      processed: 1,
      purged: 1,
      failed: 0,
    });
  });

  it("reapplies an already-purged tombstone to content restored from backup", async () => {
    const repository = new InMemoryRepository();
    const owner = await user(repository, "restore-owner");
    const conversation = await repository.createAgentConversation(owner.id);
    await repository.requestAgentConversationDeletion(owner.id, conversation.id);
    await repository.runPrivacyLifecycle({ now: "2026-07-15T00:00:00.000Z" });

    // Simulate a backup restoring active rows while the durable ledger survives.
    const conversations = (repository as unknown as {
      agentConversations: Map<string, unknown>;
      agentConversationMessages: Map<string, unknown[]>;
    });
    conversations.agentConversations.set(conversation.id, conversation);
    conversations.agentConversationMessages.set(conversation.id, [{
      id: "restored-message",
      conversationId: conversation.id,
      userId: owner.id,
      role: "user",
      content: "restored private content",
      createdAt: "2026-07-14T00:00:00.000Z",
    }]);

    const result = await repository.runPrivacyLifecycle({
      now: "2026-07-16T00:00:00.000Z",
      reapplyBefore: "2026-07-15T12:00:00.000Z",
    });
    expect(result).toMatchObject({ processed: 1, purged: 1 });
    expect(conversations.agentConversations.has(conversation.id)).toBe(false);
    expect(conversations.agentConversationMessages.has(conversation.id)).toBe(false);
    expect(await repository.getAgentConversationDeletion(owner.id, conversation.id)).toMatchObject({
      requestedAt: expect.any(String),
      purgedAt: "2026-07-15T00:00:00.000Z",
      attemptCount: 2,
    });
  });

  it("rejects a message atomically when deletion wins a coordinated write race", async () => {
    const repository = new PausedMessageRepository();
    const owner = await user(repository, "race-owner");
    const conversation = await repository.createAgentConversation(owner.id);
    const write = repository.addAgentConversationMessage(owner.id, conversation.id, {
      role: "user",
      content: "must not survive",
    });
    await repository.writePaused;
    await repository.requestAgentConversationDeletion(owner.id, conversation.id);
    repository.resumeWrite();
    await expect(write).rejects.toThrow("agent_conversation_not_found");
    await repository.runPrivacyLifecycle();
    expect(await repository.getAdminAgentConversationMessages(conversation.id, true)).toEqual([]);
  });
});

class FailOncePrivacyRepository extends InMemoryRepository {
  failConversationId?: string;

  protected override async beforePrivacyPurge(request: PrivacyDeletionRequest) {
    if (request.conversationId === this.failConversationId) {
      this.failConversationId = undefined;
      throw new Error("simulated_purge_failure");
    }
  }
}

class PausedMessageRepository extends InMemoryRepository {
  private pause = deferred<void>();
  private entered = deferred<void>();

  get writePaused() { return this.entered.promise; }
  resumeWrite() { this.pause.resolve(undefined); }

  protected override async beforeAgentConversationMessageWrite() {
    this.entered.resolve(undefined);
    await this.pause.promise;
  }
}

function deferred<T>() {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}
