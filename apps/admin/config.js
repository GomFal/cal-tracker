/* BetterCalories Admin · Telemetry
 * Static admin panel defaults.
 *
 * This file is loaded before app.js. It exposes a small global
 * namespace with default values for the local admin panel. The actual
 * selected API environment is read from localStorage. The admin token is
 * read from sessionStorage at runtime in app.js, never hardcoded here.
 */
window.AdminTelemetry = window.AdminTelemetry || {};

Object.assign(window.AdminTelemetry, {
  // The policy script owns the exact allowlist. Unknown hosting origins fall
  // back to the loopback backend and can only select a listed environment.
  defaultApiBase: window.AdminOriginPolicy.defaultApiBaseFor(window.location),
  approvedApiOrigins: window.AdminOriginPolicy.approvedApiOrigins,

  // apiBase uses localStorage. apiToken and username use sessionStorage.
  storageKeys: {
    apiBase: "bc.admin.apiBase",
    apiToken: "bc.admin.apiToken",
    apiTokenOrigin: "bc.admin.apiTokenOrigin",
    adminUsername: "bc.admin.username",
  },

  // Endpoint paths. The admin panel calls them as `${apiBase}${path}`.
  endpoints: {
    adminLogin: "/v1/admin/auth/login",
    overview: "/v1/admin/telemetry/overview",
    events: "/v1/admin/telemetry/events",
    llmRuns: "/v1/admin/telemetry/llm-runs",
    conversations: "/v1/admin/telemetry/conversations",
    conversation: (conversationId, includeHidden = true) =>
      `/v1/admin/telemetry/conversations/${encodeURIComponent(conversationId)}?includeHidden=${includeHidden ? "true" : "false"}`,
    agentTurns: "/v1/admin/telemetry/agent-turns",
    agentToolCalls: "/v1/admin/telemetry/agent-tool-calls",
    actionCalls: "/v1/admin/telemetry/action-calls",
    llmCost: "/v1/admin/telemetry/llm-cost",
    providerCalls: "/v1/admin/telemetry/llm-provider-calls",
    transcriptions: "/v1/admin/telemetry/transcriptions",
    foodSearch: "/v1/admin/telemetry/food-search",
    trace: (traceId) => `/v1/admin/telemetry/traces/${encodeURIComponent(traceId)}`,
  },

  // Default paging for list endpoints.
  defaults: {
    eventsLimit: 100,
    llmLimit: 100,
    conversationsLimit: 100,
    agentTurnsLimit: 100,
    actionCallsLimit: 100,
    providerCallsLimit: 100,
    transcriptionsLimit: 100,
    foodLimit: 100,
  },
});
