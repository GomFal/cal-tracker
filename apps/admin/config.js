/* BetterCalories Admin · Telemetry
 * Static admin panel defaults.
 *
 * This file is loaded before app.js. It exposes a small global
 * namespace with default values for the local admin panel. The actual
 * configured API base URL is read from localStorage. The admin token is
 * read from sessionStorage at runtime in app.js, never hardcoded here.
 */
window.AdminTelemetry = window.AdminTelemetry || {};

Object.assign(window.AdminTelemetry, {
  // Default API base URL used the first time the panel is opened.
  // Operators can override it from the form; the value is stored in
  // localStorage under the keys below.
  defaultApiBase: "http://localhost:3000",

  // apiBase uses localStorage. apiToken and username use sessionStorage.
  storageKeys: {
    apiBase: "bc.admin.apiBase",
    apiToken: "bc.admin.apiToken",
    adminUsername: "bc.admin.username",
  },

  // Endpoint paths. The admin panel calls them as `${apiBase}${path}`.
  endpoints: {
    adminLogin: "/v1/admin/auth/login",
    overview: "/v1/admin/telemetry/overview",
    events: "/v1/admin/telemetry/events",
    llmRuns: "/v1/admin/telemetry/llm-runs",
    foodSearch: "/v1/admin/telemetry/food-search",
    trace: (traceId) => `/v1/admin/telemetry/traces/${encodeURIComponent(traceId)}`,
  },

  // Default paging for list endpoints.
  defaults: {
    eventsLimit: 100,
    llmLimit: 100,
    foodLimit: 100,
  },
});
