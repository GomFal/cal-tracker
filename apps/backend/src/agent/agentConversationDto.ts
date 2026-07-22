import type {
  AgentConversationMessageRecord,
  AgentConversationRecord,
  AgentToolExecutionRecord,
} from "../repository/types.js";

/**
 * The user-facing history deliberately exposes the versioned execution
 * snapshots rather than repository rows. This keeps DB implementation details
 * and any future internal columns out of the mobile cache/API.
 */
export function agentConversationHistoryDto(input: {
  conversation: AgentConversationRecord;
  messages: AgentConversationMessageRecord[];
  toolExecutions: AgentToolExecutionRecord[];
}) {
  return {
    conversation: {
      id: input.conversation.id,
      title: input.conversation.title,
      ...(input.conversation.hiddenFromUserAt
        ? { hiddenFromUserAt: input.conversation.hiddenFromUserAt }
        : {}),
      createdAt: input.conversation.createdAt,
      updatedAt: input.conversation.updatedAt,
    },
    messages: input.messages.map((message) => ({
      id: message.id,
      conversationId: message.conversationId,
      role: message.role,
      content: message.content,
      ...(message.toolCalls !== undefined
        ? { toolCalls: message.toolCalls }
        : {}),
      ...(message.toolCallId ? { toolCallId: message.toolCallId } : {}),
      ...(message.traceId ? { traceId: message.traceId } : {}),
      ...(message.turnId ? { turnId: message.turnId } : {}),
      ...(message.inputMode ? { inputMode: message.inputMode } : {}),
      ...(message.source ? { source: message.source } : {}),
      ...(message.activeProposalId
        ? { activeProposalId: message.activeProposalId }
        : {}),
      ...(message.metadata !== undefined ? { metadata: message.metadata } : {}),
      createdAt: message.createdAt,
    })),
    toolExecutions: input.toolExecutions.map((execution) => execution.snapshot),
  };
}
