import { describe, expect, it } from "vitest";
import { buildTestApp, registerAndAuth } from "./testApp.js";

const assistantInput = {
  role: "assistant" as const,
  content: "",
  toolCalls: [],
};

describe("agent tool execution persistence", () => {
  it("keeps the first terminal snapshot idempotently and scopes history to its owner", async () => {
    const { repository, request } = buildTestApp();
    const { user } = await registerAndAuth(request);
    const conversation = await repository.createAgentConversation(user.id);
    const assistant = await repository.addAgentConversationMessage(
      user.id,
      conversation.id,
      assistantInput,
    );
    const startedAt = "2026-06-20T12:00:00.000Z";
    const base = {
      userId: user.id,
      conversationId: conversation.id,
      assistantMessageId: assistant.id,
      turnId: "11111111-1111-1111-1111-111111111111",
      toolCallId: "call_summary",
      actionId: "get_daily_summary",
      iteration: 1,
      toolCallIndex: 1,
    };
    const completed = await repository.saveAgentToolExecution({
      ...base,
      status: "completed",
      snapshot: {
        schemaVersion: 1,
        conversationId: conversation.id,
        turnId: base.turnId,
        assistantMessageId: assistant.id,
        toolCallId: base.toolCallId,
        iteration: 1,
        toolCallIndex: 1,
        toolCall: {
          id: base.toolCallId,
          actionId: base.actionId,
          label: "Daily summary",
          summary: "Reading today",
          input: {},
        },
        status: "completed",
        result: { kind: "summary", message: "Persisted result" },
        startedAt,
        completedAt: startedAt,
      },
    });
    const retry = await repository.saveAgentToolExecution({
      ...base,
      status: "failed",
      snapshot: {
        ...completed.snapshot,
        status: "failed",
        error: { code: "internal_error", message: "Must not replace" },
      },
    });

    expect(retry).toEqual(completed);
    await expect(
      repository.listAgentToolExecutions(user.id, conversation.id),
    ).resolves.toEqual([completed]);
    await expect(
      repository.listAgentToolExecutions("other-user", conversation.id),
    ).resolves.toEqual([]);
  });

  it("preserves the first started snapshot and lists calls by semantic index", async () => {
    const { repository, request } = buildTestApp();
    const { user } = await registerAndAuth(request);
    const conversation = await repository.createAgentConversation(user.id);
    const assistant = await repository.addAgentConversationMessage(
      user.id,
      conversation.id,
      assistantInput,
    );
    const turnId = "11111111-1111-1111-1111-111111111111";
    const snapshot = (toolCallId: string, toolCallIndex: number) => ({
      schemaVersion: 1 as const,
      conversationId: conversation.id,
      turnId,
      assistantMessageId: assistant.id,
      toolCallId,
      iteration: 1,
      toolCallIndex,
      toolCall: {
        id: toolCallId,
        actionId: "get_daily_summary",
        label: "Daily summary",
        summary: "Reading today",
        input: {},
      },
      status: "started" as const,
      startedAt: "2026-06-20T12:00:00.000Z",
    });
    const firstStarted = await repository.saveAgentToolExecution({
      userId: user.id,
      conversationId: conversation.id,
      assistantMessageId: assistant.id,
      turnId,
      toolCallId: "call_first",
      actionId: "get_daily_summary",
      iteration: 1,
      toolCallIndex: 1,
      status: "started",
      snapshot: snapshot("call_first", 1),
    });
    const {
      id: _id,
      createdAt: _createdAt,
      updatedAt: _updatedAt,
      ...startedInput
    } = firstStarted;
    const retriedStarted = await repository.saveAgentToolExecution({
      ...startedInput,
      toolCallIndex: 99,
      snapshot: {
        ...snapshot("call_first", 99),
        toolCall: {
          ...snapshot("call_first", 99).toolCall,
          label: "Must not overwrite",
        },
      },
    });
    await repository.saveAgentToolExecution({
      userId: user.id,
      conversationId: conversation.id,
      assistantMessageId: assistant.id,
      turnId,
      toolCallId: "call_second",
      actionId: "get_daily_summary",
      iteration: 1,
      toolCallIndex: 2,
      status: "started",
      snapshot: snapshot("call_second", 2),
    });

    expect(retriedStarted).toEqual(firstStarted);
    await expect(
      repository.listAgentToolExecutions(user.id, conversation.id),
    ).resolves.toEqual([
      expect.objectContaining({ toolCallId: "call_first", toolCallIndex: 1 }),
      expect.objectContaining({ toolCallId: "call_second", toolCallIndex: 2 }),
    ]);
  });
});
