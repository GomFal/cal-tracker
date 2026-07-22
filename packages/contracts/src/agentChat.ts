/**
 * Public, persisted representation of an agent function execution.
 *
 * This deliberately contains only the mapped UI payload. Provider responses and
 * model-facing tool transcript content must never be stored in this contract.
 */
export type AgentToolExecutionStatus =
  "started" | "completed" | "failed" | "interrupted";

export type AgentToolCallFeedbackSnapshot = {
  id: string;
  actionId: string;
  label: string;
  summary: string;
  input: unknown;
};

export type AgentToolExecutionSnapshot<
  TResult = unknown,
  TWidget = unknown,
  TError = unknown,
> = {
  schemaVersion: 1;
  conversationId: string;
  turnId: string;
  assistantMessageId: string;
  toolCallId: string;
  iteration: number;
  toolCallIndex: number;
  toolCall: AgentToolCallFeedbackSnapshot;
  status: AgentToolExecutionStatus;
  result?: TResult;
  widget?: TWidget;
  error?: TError;
  startedAt: string;
  completedAt?: string;
};
