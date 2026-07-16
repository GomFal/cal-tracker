/* BetterCalories Admin · Telemetry
 * Vanilla JS application logic for the static admin panel.
 *
 * Features:
 *  - Approved API environment persisted in localStorage.
 *  - Admin username/password login; token persisted in sessionStorage.
 *  - Tabs: Overview, Events, LLM runs, Food search, Trace lookup.
 *  - Filter forms for each list view.
 *  - Visible error states; never silently fails.
 *  - Defensive against missing fields in API responses.
 *
 * The panel expects the admin endpoints described in
 * specs/admin-telemetry-panel-plan.md:
 *   POST /v1/admin/auth/login
 *   GET /v1/admin/telemetry/overview?from=&to=
 *   GET /v1/admin/telemetry/events?limit=&severity=&eventType=&traceId=&userId=
 *   GET /v1/admin/telemetry/llm-runs?limit=&resultKind=&selectedTool=&traceId=&userId=
 *   GET /v1/admin/telemetry/food-search?limit=&zeroResults=&lowConfidence=&traceId=&userId=
 *   GET /v1/admin/telemetry/traces/:traceId
 */
(() => {
  "use strict";

  const cfg = window.AdminTelemetry || {};
  const originPolicy = window.AdminOriginPolicy;
  if (!originPolicy) throw new Error("Admin origin policy failed to load.");
  const STORAGE = {
    apiBase: cfg.storageKeys?.apiBase || "bc.admin.apiBase",
    apiToken: cfg.storageKeys?.apiToken || "bc.admin.apiToken",
    apiTokenOrigin: cfg.storageKeys?.apiTokenOrigin || "bc.admin.apiTokenOrigin",
    adminUsername: cfg.storageKeys?.adminUsername || "bc.admin.username",
    tableWidths: "bc.admin.tableWidths",
  };
  const ENDPOINTS = cfg.endpoints || {};
  const DEFAULTS = cfg.defaults || {};
  const DEFAULT_API_BASE = cfg.defaultApiBase || "http://localhost:3000";

  /* ========== State ========== */

  const state = {
    apiBase: "",
    apiToken: "",
    adminUsername: "",
    controllers: new Set(),
    tableRows: new Map(),
    conversationDetail: {
      conversationId: null,
      messages: [],
      agentTurns: [],
      providerCalls: [],
      agentToolCalls: [],
      selectedMessageId: null,
    },
  };

  const TABLES = {
    events: {
      tableId: "events-table",
      formId: "events-filters",
      colspan: 10,
      timeField: "createdAt",
      statusField: "status",
      defaultGroupBy: "eventType",
      groupBy: ["eventType", "severity", "status", "surface", "route", "userId", "traceId"],
      numeric: ["durationMs"],
    },
    llm: {
      tableId: "llm-table",
      formId: "llm-filters",
      colspan: 11,
      timeField: "createdAt",
      statusField: "resultKind",
      defaultGroupBy: "model",
      groupBy: ["userId", "conversationId", "turnId", "model", "provider", "resultKind", "selectedTool", "executedTool", "traceId"],
      numeric: ["promptTokens", "completionTokens", "totalTokens", "reasoningTokens", "providerCostAmount", "estimatedCostAmount", "totalMs", "llmMs", "actionMs"],
    },
    conversations: {
      tableId: "conversations-table",
      formId: "conversations-filters",
      colspan: 6,
      timeField: "updatedAt",
      statusField: "hiddenStatus",
      defaultGroupBy: "userId",
      groupBy: ["userId", "hiddenStatus"],
      numeric: [],
    },
    agentTurns: {
      tableId: "agent-turns-table",
      formId: "agent-turns-filters",
      colspan: 17,
      timeField: "createdAt",
      statusField: "status",
      backendStatus: true,
      defaultGroupBy: "conversationId",
      groupBy: ["userId", "conversationId", "traceId", "turnId", "model", "inputMode", "status", "resultKind"],
      numeric: ["iterationCount", "toolCallCount", "promptTokens", "completionTokens", "totalTokens", "reasoningTokens", "providerCostAmount", "estimatedCostAmount", "firstByteMs", "firstToolCallMs", "largestStreamGapMs", "llmMs", "actionMs", "totalMs"],
    },
    actionCalls: {
      tableId: "action-calls-table",
      formId: "action-calls-filters",
      colspan: 10,
      timeField: "createdAt",
      statusField: "errorStatus",
      defaultGroupBy: "actionId",
      groupBy: ["userId", "traceId", "actionId", "source", "confirmationStatus", "errorStatus"],
      numeric: ["latencyMs"],
    },
    llmCost: {
      tableId: "llm-cost-table",
      formId: "llm-cost-filters",
      colspan: 8,
      timeField: null,
      defaultGroupBy: "group",
      groupBy: ["group", "key"],
      numeric: ["providerCostAmount", "estimatedCostAmount", "totalCostAmount", "unknownCostCount", "totalTokens", "callCount"],
    },
    providerCalls: {
      tableId: "provider-calls-table",
      formId: "provider-calls-filters",
      colspan: 16,
      timeField: "createdAt",
      statusField: "status",
      backendStatus: true,
      costSourceField: "costSource",
      defaultGroupBy: "provider",
      groupBy: ["userId", "conversationId", "turnId", "provider", "requestedModel", "servedModel", "status", "costSource", "traceId"],
      numeric: ["promptTokens", "completionTokens", "totalTokens", "reasoningTokens", "providerCostAmount", "estimatedCostAmount", "durationMs"],
    },
    transcriptions: {
      tableId: "transcriptions-table",
      formId: "transcriptions-filters",
      colspan: 13,
      timeField: "createdAt",
      statusField: "status",
      backendStatus: true,
      defaultGroupBy: "surface",
      groupBy: ["userId", "conversationId", "surface", "provider", "model", "status", "traceId"],
      numeric: ["audioBytes", "audioDurationMs", "transcriptLength", "durationMs"],
    },
    food: {
      tableId: "food-table",
      formId: "food-filters",
      colspan: 9,
      timeField: "createdAt",
      defaultGroupBy: "path",
      groupBy: ["userId", "traceId", "path", "zeroResults", "lowConfidence", "topExternalSource", "topResultType", "locale"],
      numeric: ["queryLength", "resultCount", "candidateGroupCount", "topScore", "selectedRank", "durationMs"],
    },
  };

  const TAB_LOADERS = {
    "view-overview": () => loadOverview(readFilters($("#overview-filters"))),
    "view-events": () => loadEvents(readFilters($("#events-filters"))),
    "view-llm": () => loadLlmRuns(readFilters($("#llm-filters"))),
    "view-conversations": () => loadConversations(readFilters($("#conversations-filters"))),
    "view-agent-turns": () => loadAgentTurns(readFilters($("#agent-turns-filters"))),
    "view-action-calls": () => loadActionCalls(readFilters($("#action-calls-filters"))),
    "view-llm-cost": () => loadLlmCost(readFilters($("#llm-cost-filters"))),
    "view-provider-calls": () => loadProviderCalls(readFilters($("#provider-calls-filters"))),
    "view-transcriptions": () => loadTranscriptions(readFilters($("#transcriptions-filters"))),
    "view-food": () => loadFoodSearch(readFilters($("#food-filters"))),
    "view-trace": () => {
      const traceId = ($("#trace-id")?.value || "").trim();
      if (traceId) loadTrace(traceId);
    },
  };

  /* ========== DOM helpers ========== */

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  function el(tag, attrs = {}, children = []) {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) {
      if (v == null || v === false) continue;
      if (k === "class") node.className = v;
      else if (k === "text") node.textContent = v;
      else if (k === "data") {
        for (const [dk, dv] of Object.entries(v)) node.dataset[dk] = dv;
      } else if (k.startsWith("on") && typeof v === "function") {
        node.addEventListener(k.slice(2).toLowerCase(), v);
      } else if (k === "dataset") {
        for (const [dk, dv] of Object.entries(v)) node.dataset[dk] = dv;
      } else if (v === true) {
        node.setAttribute(k, "");
      } else {
        node.setAttribute(k, String(v));
      }
    }
    for (const c of [].concat(children)) {
      if (c == null) continue;
      node.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
    }
    return node;
  }

  /* ========== Storage ========== */

  function readStoredConfig() {
    removeLegacyToken();
    try {
      let apiBase;
      try {
        apiBase = normalizeBase(localStorage.getItem(STORAGE.apiBase) || DEFAULT_API_BASE);
      } catch (_) {
        localStorage.removeItem(STORAGE.apiBase);
        clearSession();
        apiBase = normalizeBase(DEFAULT_API_BASE);
      }
      const apiToken = sessionStorage.getItem(STORAGE.apiToken) || "";
      const apiTokenOrigin = sessionStorage.getItem(STORAGE.apiTokenOrigin) || "";
      if (apiToken && apiTokenOrigin !== apiBase) {
        clearSession();
        return { apiBase, apiToken: "", adminUsername: "" };
      }
      return {
        apiBase,
        apiToken,
        adminUsername: sessionStorage.getItem(STORAGE.adminUsername) || "",
      };
    } catch (err) {
      console.warn("browser storage unavailable", err);
      return { apiBase: "", apiToken: "", adminUsername: "" };
    }
  }

  function writeStoredConfig({ apiBase, apiToken, apiTokenOrigin, adminUsername }) {
    try {
      if (apiBase != null) localStorage.setItem(STORAGE.apiBase, apiBase);
      if (apiToken != null) sessionStorage.setItem(STORAGE.apiToken, apiToken);
      if (apiTokenOrigin != null) sessionStorage.setItem(STORAGE.apiTokenOrigin, apiTokenOrigin);
      if (adminUsername != null) sessionStorage.setItem(STORAGE.adminUsername, adminUsername);
    } catch (err) {
      console.warn("browser storage write failed", err);
    }
  }

  function clearSession() {
    try {
      sessionStorage.removeItem(STORAGE.apiToken);
      sessionStorage.removeItem(STORAGE.apiTokenOrigin);
      sessionStorage.removeItem(STORAGE.adminUsername);
      localStorage.removeItem(STORAGE.apiToken);
    } catch (err) {
      console.warn("sessionStorage clear failed", err);
    }
  }

  function removeLegacyToken() {
    try {
      // Tokens previously stored without an origin binding cannot be trusted
      // after an environment change. Force a one-time reauthentication.
      if (sessionStorage.getItem(STORAGE.apiToken) && !sessionStorage.getItem(STORAGE.apiTokenOrigin)) {
        sessionStorage.removeItem(STORAGE.apiToken);
        sessionStorage.removeItem(STORAGE.adminUsername);
      }
      localStorage.removeItem(STORAGE.apiToken);
    } catch (_) {
      /* ignore storage migration failures */
    }
  }

  /* ========== Status indicator ========== */

  const statusPill = () => $("#status-pill");
  const statusMessage = () => $("#status-message");

  function setStatus(state_, message) {
    const pill = statusPill();
    const msg = statusMessage();
    if (!pill || !msg) return;
    pill.dataset.state = state_;
    pill.textContent = state_;
    msg.textContent = message;
  }

  function setStatusLoading(label) {
    setStatus("loading", label || "Loading…");
  }

  function setStatusError(err) {
    const { status, message, url } = err;
    const code = err?.body?.error?.code || err?.body?.code;
    if ((status === 401 && code !== "invalid_admin_credentials") || code === "token_expired" || code === "admin_token_required" || code === "admin_token_invalid") {
      setStatus("error", `Your admin session expired. Sign in again.${url ? ` · ${url}` : ""}`);
      return;
    }
    if (status === 403 || code === "permission_denied" || code === "admin_scope_required") {
      setStatus("error", `This token is not authorized for admin telemetry.${url ? ` · ${url}` : ""}`);
      return;
    }
    let body = message || "Request failed";
    if (status) body = `${status} · ${body}`;
    if (url) body += ` · ${url}`;
    setStatus("error", body);
  }

  function setStatusSuccess(message) {
    setStatus("success", message);
  }

  function setStatusIdle() {
    setStatus("idle", "Idle.");
  }

  function setStatusLocked() {
    setStatus(
      "locked",
      "Telemetry is locked. Sign in with the admin deployment password to continue.",
    );
  }

  /* ========== HTTP ========== */

  function normalizeBase(raw) {
    return originPolicy.normalizeApiBase(raw);
  }

  function buildUrl(path) {
    return originPolicy.resolveApiUrl(state.apiBase || DEFAULT_API_BASE, path);
  }

  function abortInFlight() {
    for (const ctrl of state.controllers) {
      try {
        ctrl.abort();
      } catch (_) {
        /* ignore */
      }
    }
    state.controllers.clear();
  }

  async function apiGet(path, { params } = {}) {
    if (!isSignedIn()) {
      throw lockedError();
    }
    abortInFlight();
    const ctrl = new AbortController();
    state.controllers.add(ctrl);

    let url;
    try {
      url = buildUrl(path);
    } catch (err) {
      state.controllers.delete(ctrl);
      throw err;
    }

    if (params && typeof params === "object") {
      const qs = new URLSearchParams();
      for (const [k, v] of Object.entries(params)) {
        if (v == null) continue;
        const s = String(v).trim();
        if (!s) continue;
        qs.set(k, s);
      }
      const serialized = qs.toString();
      if (serialized) url += (url.includes("?") ? "&" : "?") + serialized;
    }

    const headers = originPolicy.createAuthorizedHeaders(
      state.apiBase,
      url,
      state.apiToken,
      { Accept: "application/json" },
    );

    let response;
    try {
      response = await fetch(url, { method: "GET", headers, signal: ctrl.signal, redirect: "error" });
    } catch (err) {
      state.controllers.delete(ctrl);
      if (err && err.name === "AbortError") {
        const abortErr = new Error("Request aborted");
        abortErr.code = "aborted";
        throw abortErr;
      }
      const networkErr = new Error(err.message || "Network error");
      networkErr.url = url;
      throw networkErr;
    }

    state.controllers.delete(ctrl);

    const text = await response.text();
    let body = null;
    if (text) {
      try {
        body = JSON.parse(text);
      } catch (_) {
        body = { raw: text };
      }
    }

    if (!response.ok) {
      const apiErr = new Error(extractErrorMessage(body) || response.statusText);
      apiErr.status = response.status;
      apiErr.url = url;
      apiErr.body = body;
      if (response.status === 401) {
        clearSession();
        state.apiToken = "";
        state.adminUsername = "";
        clearProtectedData();
        renderAuthUi();
      }
      throw apiErr;
    }

    return body;
  }

  async function apiPost(path, body) {
    abortInFlight();
    const ctrl = new AbortController();
    state.controllers.add(ctrl);

    let url;
    try {
      url = buildUrl(path);
    } catch (err) {
      state.controllers.delete(ctrl);
      throw err;
    }

    let response;
    try {
      response = await fetch(url, {
        method: "POST",
        headers: { Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify(body),
        signal: ctrl.signal,
        redirect: "error",
      });
    } catch (err) {
      state.controllers.delete(ctrl);
      if (err && err.name === "AbortError") {
        const abortErr = new Error("Request aborted");
        abortErr.code = "aborted";
        throw abortErr;
      }
      const networkErr = new Error(err.message || "Network error");
      networkErr.url = url;
      throw networkErr;
    }

    state.controllers.delete(ctrl);
    const text = await response.text();
    let parsed = null;
    if (text) {
      try {
        parsed = JSON.parse(text);
      } catch (_) {
        parsed = { raw: text };
      }
    }

    if (!response.ok) {
      const apiErr = new Error(extractErrorMessage(parsed) || response.statusText);
      apiErr.status = response.status;
      apiErr.url = url;
      apiErr.body = parsed;
      throw apiErr;
    }

    return parsed;
  }

  function extractErrorMessage(body) {
    if (!body) return null;
    if (typeof body === "string") return body;
    if (body.message) {
      if (Array.isArray(body.message)) return body.message.join("; ");
      if (typeof body.message === "string") return body.message;
    }
    if (body.error) {
      if (typeof body.error === "string") return body.error;
      if (body.error.message) return body.error.message;
    }
    return null;
  }

  function isSignedIn() {
    return Boolean(state.apiToken);
  }

  function lockedError() {
    const err = new Error("Admin sign-in required.");
    err.status = 401;
    err.body = { error: { code: "admin_token_required" } };
    return err;
  }

  function clearProtectedData() {
    abortInFlight();
    setCardsLoading(false);
    $$(".card [data-value]").forEach((node) => {
      node.textContent = "—";
    });
    $$(".card").forEach((card) => {
      card.classList.remove("is-loading", "is-error", "is-warning", "is-success");
    });
    const overviewRaw = $("#overview-raw");
    if (overviewRaw) overviewRaw.textContent = "Sign in to load telemetry.";
    const traceRaw = $("#trace-raw");
    if (traceRaw) traceRaw.textContent = "Sign in to load telemetry.";
    renderEventsTable([]);
    renderLlmTable([]);
    renderConversationsTable([]);
    resetConversationDetailState();
    renderConversationDetail([]);
    renderSelectedMessageAccounting(null);
    renderAgentTurnsTable([], "#conversation-turns-table tbody", "Select a conversation row.");
    renderProviderCallsTable([], "#conversation-provider-calls-table tbody", "Select a conversation row.");
    renderAgentTurnsTable([]);
    renderActionCallsTable([]);
    renderLlmCostView(null);
    renderProviderCallsTable([]);
    renderTranscriptionsTable([]);
    renderFoodTable([]);
    renderTraceView({
      traceId: "—",
      events: [],
      llmRuns: [],
      foodSearchEvents: [],
      conversationMessages: [],
      agentTurns: [],
      agentToolCalls: [],
      actionCalls: [],
      providerCalls: [],
      transcriptions: [],
    });
  }

  async function loginAdmin(username, password) {
    const data = await apiPost(ENDPOINTS.adminLogin || "/v1/admin/auth/login", {
      username,
      password,
    });
    const token = data?.accessToken;
    if (!token) throw new Error("Admin login response did not include a token.");
    const normalizedUsername = data?.username || username;
    state.apiToken = token;
    state.adminUsername = normalizedUsername;
    writeStoredConfig({
      apiToken: token,
      apiTokenOrigin: normalizeBase(state.apiBase),
      adminUsername: normalizedUsername,
    });
    renderAuthUi();
    return data;
  }

  function logoutAdmin() {
    clearSession();
    state.apiToken = "";
    state.adminUsername = "";
    clearProtectedData();
    renderAuthUi();
    setStatusLocked();
  }

  function renderAuthUi() {
    const usernameField = $("#admin-username-field");
    const passwordField = $("#admin-password-field");
    const usernameInput = $("#admin-username");
    const passwordInput = $("#admin-password");
    const session = $("#admin-session");
    const sessionUsername = $("#admin-session-username");
    const submit = $("#admin-login-submit");
    const signout = $("#admin-signout");
    const signedIn = isSignedIn();

    document.body.classList.toggle("is-locked", !signedIn);
    $$(".tab").forEach((btn) => {
      btn.disabled = !signedIn;
      btn.setAttribute("aria-disabled", signedIn ? "false" : "true");
      btn.tabIndex = signedIn ? 0 : -1;
    });
    $$(".filters input, .filters select, .filters button").forEach((control) => {
      control.disabled = !signedIn;
    });

    if (usernameField) usernameField.hidden = signedIn;
    if (passwordField) passwordField.hidden = signedIn;
    if (session) session.hidden = !signedIn;
    if (signout) signout.hidden = !signedIn;
    if (submit) submit.textContent = signedIn ? "Save URL" : "Sign in";
    if (sessionUsername) sessionUsername.textContent = state.adminUsername || "admin";
    if (signedIn) {
      if (passwordInput) passwordInput.value = "";
    } else if (usernameInput && state.adminUsername) {
      usernameInput.value = state.adminUsername;
    }
  }

  function friendlyLoginError(err) {
    const code = err?.body?.error?.code || err?.body?.code;
    if (!err.status) return "Could not reach the admin API. Check the URL and try again.";
    if (err.status === 400 || code === "validation_error") return "Enter the admin username and password.";
    if (err.status === 401 || code === "invalid_admin_credentials") return "Admin username or password is incorrect.";
    if (err.status === 503 || code === "admin_panel_disabled" || code === "admin_panel_misconfigured") return "Admin authentication is not configured on this API environment.";
    return "Could not sign in. Try again.";
  }

  /* ========== Utilities ========== */

  function formatNumber(value) {
    if (value == null || value === "") return "—";
    const n = typeof value === "number" ? value : Number(value);
    if (Number.isFinite(n)) return n.toLocaleString();
    return String(value);
  }

  function formatMoney(value, currency = "USD") {
    if (value == null || value === "") return "—";
    const n = Number(value);
    if (!Number.isFinite(n)) return String(value);
    const suffix = currency || "USD";
    return `${n.toFixed(n >= 1 ? 2 : 6)} ${suffix}`;
  }

  function formatDuration(ms) {
    if (ms == null || ms === "") return "—";
    const n = Number(ms);
    if (!Number.isFinite(n)) return String(ms);
    if (n < 1000) return `${Math.round(n)} ms`;
    return `${(n / 1000).toFixed(2)} s`;
  }

  function formatTimestamp(value) {
    if (!value) return "—";
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return String(value);
    return d.toLocaleString();
  }

  function formatDateTimeLocal(value) {
    if (!value) return "";
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return "";
    const pad = (n) => String(n).padStart(2, "0");
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  function toIsoOrNull(value) {
    if (!value) return null;
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return null;
    return d.toISOString();
  }

  function severityTag(severity) {
    const value = (severity || "info").toLowerCase();
    const cls =
      value === "error"
        ? "tag tag-error"
        : value === "warning" || value === "warn"
          ? "tag tag-warning"
          : value === "success"
            ? "tag tag-success"
            : "tag tag-info";
    return el("span", { class: cls, text: value });
  }

  function statusTag(status) {
    const value = (status || "").toLowerCase();
    if (!value) return el("span", { class: "tag tag-neutral", text: "—" });
    const cls =
      value === "success" || value === "ok"
        ? "tag tag-success"
        : value === "failure" || value === "error" || value === "failed"
          ? "tag tag-error"
          : value === "warning" || value === "partial"
            ? "tag tag-warning"
            : "tag tag-neutral";
    return el("span", { class: cls, text: value });
  }

  function boolTag(label, value) {
    const isTrue = value === true || value === "true";
    const cls = isTrue ? "tag tag-warning" : "tag tag-neutral";
    return el("span", { class: cls, text: isTrue ? `${label} ✓` : `${label} ·` });
  }

  function jsonPreview(value, max = 96) {
    if (value == null) return "—";
    const raw =
      typeof value === "string" ? value : JSON.stringify(value, null, 2);
    if (!raw) return "—";
    return raw.length > max ? `${raw.slice(0, max - 1)}…` : raw;
  }

  function costAmount(row) {
    const amount = row?.providerCostAmount ?? row?.estimatedCostAmount ?? row?.totalCostAmount;
    return formatMoney(amount, row?.costCurrency || "USD");
  }

  function costTotal(rows) {
    let total = 0;
    let found = false;
    for (const row of rows || []) {
      const value = optionalFiniteNumber(
        row?.providerCostAmount ?? row?.estimatedCostAmount ?? row?.totalCostAmount,
      );
      if (value == null) continue;
      total += value;
      found = true;
    }
    return found ? total : null;
  }

  function currencyForRows(rows) {
    return (rows || []).find((row) => row?.costCurrency)?.costCurrency || "USD";
  }

  function fullText(value) {
    if (value == null || value === "") return "";
    return typeof value === "string" ? value : JSON.stringify(value, null, 2);
  }

  function isLikelyId(value) {
    const text = String(value || "");
    return text.length >= 20 || /^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(text);
  }

  function copyableId(value) {
    if (value == null || value === "") return el("span", { text: "—" });
    const text = String(value);
    const wrap = el("span", { class: "copy-id" });
    wrap.append(
      el("span", { class: "copy-id-text mono", text, title: text }),
      el("button", {
        class: "copy-btn",
        type: "button",
        title: "Copy full value",
        "aria-label": "Copy full value",
        onClick: (event) => {
          event.stopPropagation();
          copyToClipboard(text, event.currentTarget);
        },
      }, "Copy"),
    );
    return wrap;
  }

  function idCell(value) {
    return el("td", { class: "mono id-cell" }, copyableId(value));
  }

  function renderExpandableValue(value, { mono = false } = {}) {
    const text = fullText(value);
    if (!text) return el("span", { text: "—" });
    const wrap = el("div", { class: `expandable-value${mono ? " mono" : ""}` });
    const pre = el("pre", { class: "expandable-preview", text });
    const actions = el("div", { class: "cell-actions" });
    actions.append(
      el("button", {
        class: "copy-btn",
        type: "button",
        title: "Copy full value",
        onClick: (event) => {
          event.stopPropagation();
          copyToClipboard(text, event.currentTarget);
        },
      }, "Copy"),
      el("button", {
        class: "copy-btn",
        type: "button",
        title: "Expand or collapse value",
        onClick: (event) => {
          event.stopPropagation();
          const expanded = wrap.classList.toggle("is-expanded");
          event.currentTarget.textContent = expanded ? "Less" : "More";
        },
      }, "More"),
    );
    wrap.append(pre, actions);
    return wrap;
  }

  function textCell(value, className = "wrap") {
    const text = fullText(value);
    if (!text) return el("td", { class: className, text: "—" });
    if (isLikelyId(text)) return idCell(text);
    return el("td", { class: className, text });
  }

  function jsonCell(value) {
    return el("td", { class: "wrap json-cell" }, renderExpandableValue(value, { mono: true }));
  }

  function appendDateParams(params, filters) {
    const fromIso = toIsoOrNull(filters.from);
    const toIso = toIsoOrNull(filters.to);
    if (fromIso) params.from = fromIso;
    if (toIso) params.to = toIso;
  }

  function readTableControls(tableKey) {
    const form = document.getElementById(TABLES[tableKey]?.formId);
    const filters = readFilters(form);
    const config = TABLES[tableKey];
    return {
      sortBy: filters.sortBy || defaultSortField(config),
      sort: filters.sort || "desc",
      status: filters.status || "",
      costSource: filters.costSource || "",
      viewMode: filters.viewMode || "rows",
      groupBy: filters.groupBy || config?.defaultGroupBy,
    };
  }

  function derivedValue(row, key) {
    if (key === "hiddenStatus") return row.hiddenFromUserAt ? "hidden" : "visible";
    if (key === "errorStatus") return row.error ? "error" : "ok";
    if (key === "zeroResults" || key === "lowConfidence") return row[key] ? "true" : "false";
    return row?.[key];
  }

  function applyClientControls(tableKey, rows) {
    const config = TABLES[tableKey];
    const controls = readTableControls(tableKey);
    let next = Array.isArray(rows) ? [...rows] : [];
    if (controls.status && config?.statusField && !config.backendStatus) {
      next = next.filter((row) => String(derivedValue(row, config.statusField) || "") === controls.status);
    }
    if (controls.costSource && config?.costSourceField) {
      next = next.filter((row) => String(row[config.costSourceField] || "") === controls.costSource);
    }
    next = sortRows(next, tableKey, controls);
    state.tableRows.set(tableKey, next);
    return next;
  }

  function sortRows(rows, tableKey, controls = readTableControls(tableKey)) {
    const config = TABLES[tableKey];
    const sortBy = controls.sortBy || defaultSortField(config);
    if (!sortBy) return rows;
    const direction = controls.sort === "asc" ? 1 : -1;
    return [...rows].sort((a, b) => {
      const left = sortableValue(a, sortBy, config);
      const right = sortableValue(b, sortBy, config);
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      if (typeof left === "string" || typeof right === "string") {
        return direction * String(left).localeCompare(String(right));
      }
      return direction * (left - right);
    });
  }

  function sortAggregates(rows, controls) {
    const sortBy = controls.sortBy || "count";
    const direction = controls.sort === "asc" ? 1 : -1;
    return [...rows].sort((a, b) => {
      const left = aggregateSortableValue(a, sortBy);
      const right = aggregateSortableValue(b, sortBy);
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      if (typeof left === "string" || typeof right === "string") {
        return direction * String(left).localeCompare(String(right));
      }
      return direction * (left - right);
    });
  }

  function sortableValue(row, field, config) {
    if (!row) return null;
    if (field === "time") {
      const value = Date.parse(row?.[config?.timeField] || row?.createdAt || row?.updatedAt || "");
      return Number.isFinite(value) ? value : null;
    }
    if (field === "cost") return costSortableValue(row);
    const value = derivedValue(row, field);
    if (value == null || value === "") return null;
    if (field.endsWith("At")) {
      const parsed = Date.parse(value);
      if (Number.isFinite(parsed)) return parsed;
    }
    const numeric = Number(value);
    return Number.isFinite(numeric) && value !== "" ? numeric : String(value);
  }

  function aggregateSortableValue(row, field) {
    if (field === "time") {
      const value = Date.parse(row?.lastSeen || row?.firstSeen || "");
      return Number.isFinite(value) ? value : null;
    }
    if (field === "cost") return Number(row?.totalCost);
    if (field === "totalTokens") return Number(row?.totalTokens);
    if (field === "count") return Number(row?.count);
    const summary = row?.numericSummary?.[field];
    if (summary) return Number(summary.sum ?? summary.median);
    const value = row?.[field];
    if (value == null || value === "") return null;
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : String(value);
  }

  function costSortableValue(row) {
    const total = optionalFiniteNumber(row?.totalCostAmount);
    const provider = optionalFiniteNumber(row?.providerCostAmount);
    const estimated = optionalFiniteNumber(row?.estimatedCostAmount);
    if (total != null) return total;
    if (provider != null) return provider;
    if (estimated != null) return estimated;
    return null;
  }

  function optionalFiniteNumber(value) {
    if (value == null || value === "") return null;
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
  }

  function maybeRenderAggregateRows(tbody, tableKey, rows) {
    const config = TABLES[tableKey];
    if (!config) return false;
    const controls = readTableControls(tableKey);
    if (controls.viewMode !== "aggregate") return false;
    const aggregates = sortAggregates(
      aggregateRows(rows, tableKey, controls.groupBy),
      controls,
    );
    tbody.replaceChildren();
    if (!aggregates.length) {
      tbody.appendChild(renderEmptyRow(config.colspan, "No rows to aggregate."));
      return true;
    }
    for (const row of aggregates) {
      const tr = el("tr", { class: "is-aggregate" });
      tr.append(
        el("td", { class: "mono" }, copyableId(row.key)),
        el("td", { class: "numeric", text: formatNumber(row.count) }),
        el("td", { text: formatTimestamp(row.firstSeen) }),
        el("td", { text: formatTimestamp(row.lastSeen) }),
        el("td", { class: "numeric", text: formatNumber(row.totalTokens) }),
        el("td", { class: "numeric", text: formatMoney(row.totalCost) }),
        el("td", { class: "numeric", text: formatDuration(row.medianLatency) }),
        el("td", { class: "wrap", colspan: Math.max(1, config.colspan - 7) }, renderExpandableValue(row.numericSummary, { mono: true })),
      );
      tbody.appendChild(tr);
    }
    return true;
  }

  function aggregateRows(rows, tableKey, groupBy) {
    const config = TABLES[tableKey];
    const groups = new Map();
    for (const row of rows || []) {
      const key = String(derivedValue(row, groupBy) ?? "unknown");
      const group = groups.get(key) || [];
      group.push(row);
      groups.set(key, group);
    }
    return [...groups.entries()].map(([key, group]) => {
      const times = group
        .map((row) => Date.parse(row?.[config.timeField] || row?.createdAt || row?.updatedAt || ""))
        .filter(Number.isFinite)
        .sort((a, b) => a - b);
      const numericSummary = {};
      for (const field of config.numeric || []) {
        const values = group
          .map((row) => Number(row?.[field]))
          .filter(Number.isFinite);
        if (!values.length) continue;
        numericSummary[field] = {
          sum: roundMetric(values.reduce((sum, value) => sum + value, 0)),
          median: roundMetric(median(values)),
        };
      }
      const totalCost = group.reduce((sum, row) => {
        const provider = Number(row.providerCostAmount);
        const estimated = Number(row.estimatedCostAmount);
        const total = Number(row.totalCostAmount);
        if (Number.isFinite(provider) || Number.isFinite(estimated)) {
          return sum + (Number.isFinite(provider) ? provider : 0) + (Number.isFinite(estimated) ? estimated : 0);
        }
        return sum + (Number.isFinite(total) ? total : 0);
      }, 0);
      const totalTokens = sumNumbers(group, ["totalTokens"]);
      const medianLatency = median(
        group
          .map((row) => Number(row.totalMs ?? row.durationMs ?? row.latencyMs))
          .filter(Number.isFinite),
      );
      return {
        key,
        count: group.length,
        firstSeen: times.length ? new Date(times[0]).toISOString() : undefined,
        lastSeen: times.length ? new Date(times[times.length - 1]).toISOString() : undefined,
        totalTokens,
        totalCost,
        medianLatency,
        numericSummary,
      };
    }).sort((a, b) => b.count - a.count);
  }

  function sumNumbers(rows, fields) {
    let total = 0;
    for (const row of rows) {
      for (const field of fields) {
        const value = Number(row?.[field]);
        if (Number.isFinite(value)) total += value;
      }
    }
    return total;
  }

  function tokenCell(row, field) {
    return el("td", { class: "numeric", text: formatNumber(row?.[field]) });
  }

  function tokenCells(row) {
    return [
      tokenCell(row, "promptTokens"),
      tokenCell(row, "completionTokens"),
      tokenCell(row, "totalTokens"),
      tokenCell(row, "reasoningTokens"),
    ];
  }

  function compactObject(value) {
    return value && typeof value === "object" && !Array.isArray(value) ? value : {};
  }

  function metadataNumber(row, key) {
    const value = compactObject(row?.metadata)?.[key];
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
  }

  function createdAtMs(row) {
    const value = Date.parse(row?.createdAt || row?.startedAt || "");
    return Number.isFinite(value) ? value : null;
  }

  function sortByCreatedDesc(rows) {
    return [...(rows || [])].sort((a, b) => {
      const left = createdAtMs(a);
      const right = createdAtMs(b);
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return right - left;
    });
  }

  function sameTurnRows(rows, turnId) {
    return (rows || []).filter((row) => row?.turnId && row.turnId === turnId);
  }

  function messageHasToolCalls(message) {
    return Array.isArray(message?.toolCalls) && message.toolCalls.length > 0;
  }

  function safeParseMaybeJson(value) {
    if (typeof value !== "string") return value;
    try {
      return JSON.parse(value);
    } catch {
      return value;
    }
  }

  function nearestProviderCallForMessage(message, calls) {
    const messageTime = createdAtMs(message);
    const ordered = sortByCreatedDesc(calls);
    if (messageTime == null) return ordered[0];
    const before = ordered.find((call) => {
      const callTime = createdAtMs(call);
      return callTime != null && callTime <= messageTime;
    });
    return before || ordered[0];
  }

  function selectedProviderCallsForMessage(message) {
    const turnCalls = sameTurnRows(
      state.conversationDetail.providerCalls,
      message?.turnId,
    );
    if (!message || turnCalls.length === 0) {
      return { calls: [], relation: "no provider call", inferred: false };
    }

    if (message.role === "user") {
      return {
        calls: sortByCreatedDesc(turnCalls),
        relation: "message included in prompt",
        inferred: false,
      };
    }

    if (message.role === "tool") {
      const messageTime = createdAtMs(message);
      const later = turnCalls.filter((call) => {
        const callTime = createdAtMs(call);
        return messageTime == null || callTime == null || callTime >= messageTime;
      });
      return {
        calls: sortByCreatedDesc(later),
        relation: "tool result included in later prompt",
        inferred: false,
      };
    }

    const relation = messageHasToolCalls(message)
      ? "LLM generated tool call"
      : "LLM generated assistant message";
    const iteration = metadataNumber(message, "iteration");
    if (iteration != null) {
      const exact = turnCalls.filter((call) => metadataNumber(call, "iteration") === iteration);
      if (exact.length > 0) {
        return { calls: sortByCreatedDesc(exact), relation, inferred: false };
      }
    }
    const nearest = nearestProviderCallForMessage(message, turnCalls);
    return {
      calls: nearest ? [nearest] : sortByCreatedDesc(turnCalls),
      relation,
      inferred: true,
    };
  }

  function selectedToolCallsForMessage(message) {
    const toolTelemetry = state.conversationDetail.agentToolCalls || [];
    if (!message) return [];
    if (message.role === "tool") {
      return toolTelemetry
        .filter((row) => row.toolCallId && row.toolCallId === message.toolCallId)
        .map((row) => ({
          ...row,
          relation: "executed tool result for selected message",
        }));
    }
    if (message.role === "assistant" && messageHasToolCalls(message)) {
      return message.toolCalls.map((toolCall, index) => {
        const match = toolTelemetry.find((row) => row.toolCallId && row.toolCallId === toolCall.id);
        return {
          ...match,
          relation: "generated by selected LLM message",
          toolCallId: toolCall.id,
          actionId: toolCall.function?.name || match?.actionId || "unknown_tool",
          arguments: match?.arguments ?? safeParseMaybeJson(toolCall.function?.arguments || "{}"),
          resultSummary: match?.resultSummary,
          status: match?.status || "generated",
          createdAt: match?.createdAt || message.createdAt,
          durationMs: match?.durationMs,
          errorMessage: match?.errorMessage,
          metadata: {
            ...(match?.metadata || {}),
            generatedToolIndex: index,
          },
        };
      });
    }
    if (message.role === "user") {
      return sortByCreatedDesc(sameTurnRows(toolTelemetry, message.turnId)).map((row) => ({
        ...row,
        relation: "tool call later in selected turn",
      }));
    }
    return [];
  }

  function sumField(rows, field) {
    let total = 0;
    let found = false;
    for (const row of rows || []) {
      const value = Number(row?.[field]);
      if (!Number.isFinite(value)) continue;
      total += value;
      found = true;
    }
    return found ? total : null;
  }

  function median(values) {
    if (!values.length) return undefined;
    const sorted = [...values].sort((a, b) => a - b);
    const middle = Math.floor(sorted.length / 2);
    return sorted.length % 2
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  function roundMetric(value) {
    return Math.round(value * 1_000_000) / 1_000_000;
  }

  function traceCell(value) {
    return idCell(value);
  }

  function copyableSpan(value) {
    if (value == null || value === "") return el("span", { text: "—" });
    const text = String(value);
    const span = el("span", { class: "mono", text });
    span.title = "Click to copy";
    span.tabIndex = 0;
    span.style.cursor = "copy";
    span.addEventListener("click", () => copyToClipboard(text, span));
    span.addEventListener("keydown", (e) => {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        copyToClipboard(text, span);
      }
    });
    return span;
  }

  async function copyToClipboard(text, target) {
    try {
      await navigator.clipboard.writeText(text);
      if (target) flashCopied(target);
    } catch (err) {
      console.warn("Clipboard copy failed", err);
    }
  }

  function flashCopied(target) {
    const original = target.textContent;
    target.textContent = "copied";
    setTimeout(() => {
      target.textContent = original;
    }, 900);
  }

  function readFilters(form) {
    if (!form) return {};
    const fd = new FormData(form);
    const out = {};
    for (const [k, v] of fd.entries()) {
      if (typeof v === "string" && v.trim() === "") continue;
      out[k] = v;
    }
    return out;
  }

  function resetForm(form) {
    if (!form) return;
    form.reset();
  }

  function enhanceFilterForms() {
    for (const [key, config] of Object.entries(TABLES)) {
      const form = document.getElementById(config.formId);
      if (!form) continue;
      const actions = $(".filters-actions", form);
      if (!actions) continue;
      if (config.timeField) {
        insertControl(actions, dateField(`${config.formId}-from`, "from", "From"));
        insertControl(actions, dateField(`${config.formId}-to`, "to", "To"));
      }
      const sortOptions = sortableOptionsFor(config);
      if (sortOptions.length) {
        insertControl(actions, selectField(`${config.formId}-sort-by`, "sortBy", "Sort by", sortOptions));
        insertControl(actions, selectField(`${config.formId}-sort`, "sort", "Order", [
          ["desc", "high/newest"],
          ["asc", "low/oldest"],
        ]));
      }
      if (config.statusField) {
        insertControl(actions, selectField(`${config.formId}-status`, "status", "Status", statusOptionsFor(key)));
      }
      if (config.costSourceField) {
        insertControl(actions, selectField(`${config.formId}-cost-source`, "costSource", "Cost source", [
          ["", "any"],
          ["provider", "provider"],
          ["estimate", "estimate"],
          ["unknown", "unknown"],
        ]));
      }
      insertControl(actions, selectField(`${config.formId}-view-mode`, "viewMode", "View", [
        ["rows", "rows"],
        ["aggregate", "aggregate"],
      ]));
      insertControl(actions, selectField(
        `${config.formId}-group-by`,
        "groupBy",
        "Group by",
        (config.groupBy || []).map((field) => [field, field]),
      ));
    }
  }

  function insertControl(beforeNode, control) {
    const input = $("input, select", control);
    if (input && beforeNode.parentElement?.querySelector(`[name="${input.name}"]`)) return;
    beforeNode.parentElement?.insertBefore(control, beforeNode);
  }

  function dateField(id, name, label) {
    return el("label", { class: "field" }, [
      el("span", { text: label }),
      el("input", { id, name, type: "datetime-local" }),
    ]);
  }

  function selectField(id, name, label, options) {
    const select = el("select", { id, name });
    for (const [value, text] of options) {
      select.appendChild(el("option", { value, text }));
    }
    return el("label", { class: "field field-narrowish" }, [
      el("span", { text: label }),
      select,
    ]);
  }

  function sortableOptionsFor(config) {
    if (!config) return [];
    const options = [];
    const add = (value, label) => {
      if (!value || options.some(([existing]) => existing === value)) return;
      options.push([value, label]);
    };
    if (config.timeField) add("time", "time");
    for (const field of config.numeric || []) {
      if (field === "promptTokens") add(field, "prompt tokens");
      else if (field === "completionTokens") add(field, "completion tokens");
      else if (field === "totalTokens") add(field, "total tokens");
      else if (field === "reasoningTokens") add(field, "reasoning tokens");
      else if (field === "providerCostAmount") add("cost", "cost");
      else if (field === "estimatedCostAmount") add("cost", "cost");
      else if (field === "totalCostAmount") add("cost", "cost");
      else add(field, field);
    }
    return options;
  }

  function defaultSortField(config) {
    if (!config) return "";
    if (config.timeField) return "time";
    const options = sortableOptionsFor(config);
    return options[0]?.[0] || "";
  }

  function statusOptionsFor(tableKey) {
    const base = [["", "any"]];
    if (tableKey === "events") return base.concat([["success", "success"], ["failure", "failure"], ["started", "started"]]);
    if (tableKey === "conversations") return base.concat([["visible", "visible"], ["hidden", "hidden"]]);
    if (tableKey === "actionCalls") return base.concat([["ok", "ok"], ["error", "error"]]);
    if (tableKey === "llm") return base.concat([["proposal", "proposal"], ["assistant_message", "assistant_message"], ["assistant_options", "assistant_options"], ["meal_committed", "meal_committed"], ["clarification_required", "clarification_required"], ["error", "error"]]);
    return base.concat([["success", "success"], ["failure", "failure"], ["failed", "failed"], ["completed", "completed"], ["started", "started"], ["partial", "partial"]]);
  }

  function refreshActiveView() {
    if (!isSignedIn()) return;
    const active = $(".view.is-active");
    if (!active) return;
    TAB_LOADERS[active.id]?.();
  }

  function makeAllTablesResizable() {
    $$(".data-table").forEach(makeTableResizable);
  }

  function makeTableResizable(table) {
    if (!table || table.dataset.resizable === "true") return;
    table.dataset.resizable = "true";
    const tableId = table.id;
    ensureTableColgroup(table);
    applyStoredColumnWidths(table);
    $$("thead th", table).forEach((th, index) => {
      th.classList.add("is-resizable");
      const handle = el("span", { class: "resize-handle", title: "Drag to resize column" });
      th.appendChild(handle);
      handle.addEventListener("mousedown", (event) => {
        event.preventDefault();
        const startX = event.clientX;
        const startWidth = th.getBoundingClientRect().width;
        const onMove = (moveEvent) => {
          const width = Math.max(72, Math.round(startWidth + moveEvent.clientX - startX));
          setColumnWidth(table, index, width);
        };
        const onUp = () => {
          document.removeEventListener("mousemove", onMove);
          document.removeEventListener("mouseup", onUp);
          persistColumnWidths(tableId, table);
        };
        document.addEventListener("mousemove", onMove);
        document.addEventListener("mouseup", onUp);
      });
    });
  }

  function ensureTableColgroup(table) {
    if ($("colgroup", table)) return;
    const columnCount = $$("thead th", table).length;
    if (!columnCount) return;
    const colgroup = el("colgroup");
    for (let i = 0; i < columnCount; i += 1) {
      colgroup.appendChild(el("col"));
    }
    table.insertBefore(colgroup, table.firstElementChild);
  }

  function setColumnWidth(table, index, width) {
    const col = $$("colgroup col", table)[index];
    if (col) col.style.width = `${width}px`;
    const th = $$("thead th", table)[index];
    if (th) th.style.width = `${width}px`;
    $$(`tbody tr td:nth-child(${index + 1})`, table).forEach((td) => {
      td.style.width = `${width}px`;
      td.style.maxWidth = `${width}px`;
    });
  }

  function storedColumnWidths() {
    try {
      return JSON.parse(localStorage.getItem(STORAGE.tableWidths) || "{}");
    } catch (_) {
      return {};
    }
  }

  function applyStoredColumnWidths(table) {
    const widths = storedColumnWidths()[table.id] || [];
    widths.forEach((width, index) => {
      if (Number.isFinite(Number(width))) setColumnWidth(table, index, Number(width));
    });
  }

  function persistColumnWidths(tableId, table) {
    try {
      const all = storedColumnWidths();
      all[tableId] = $$("thead th", table).map((th) => Math.round(th.getBoundingClientRect().width));
      localStorage.setItem(STORAGE.tableWidths, JSON.stringify(all));
    } catch (err) {
      console.warn("table width persistence failed", err);
    }
  }

  /* ========== Tabs ========== */

  function activateTab(target) {
    if (!isSignedIn()) {
      setStatusLocked();
      return;
    }
    $$(".tab").forEach((btn) => {
      const active = btn.dataset.target === target;
      btn.classList.toggle("is-active", active);
      btn.setAttribute("aria-selected", active ? "true" : "false");
    });
    $$(".view").forEach((view) => {
      const active = view.id === target;
      view.classList.toggle("is-active", active);
      if (active) view.removeAttribute("hidden");
      else view.setAttribute("hidden", "");
    });
    if (location.hash !== `#${target}`) {
      history.replaceState(null, "", `#${target}`);
    }
    TAB_LOADERS[target]?.();
  }

  function bindTabs() {
    $$(".tab").forEach((btn) => {
      btn.addEventListener("click", () => {
        if (!isSignedIn()) {
          setStatusLocked();
          return;
        }
        activateTab(btn.dataset.target);
      });
    });
  }

  function bootstrapTabFromHash() {
    if (!isSignedIn()) return false;
    const hash = (location.hash || "").replace(/^#/, "");
    if (hash && $$(".view").some((v) => v.id === hash)) {
      activateTab(hash);
      return true;
    }
    return false;
  }

  /* ========== Renderers ========== */

  function renderEmptyRow(colspan, text = "No records to show.") {
    return el(
      "tr",
      { class: "empty" },
      el("td", { colspan, text }),
    );
  }

  function renderEventsTable(rows) {
    const tbody = $("#events-table tbody");
    rows = applyClientControls("events", rows);
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(10, "No events match the current filters."));
      return;
    }
    if (maybeRenderAggregateRows(tbody, "events", rows)) return;
    for (const row of rows) {
      const severity = (row.severity || "info").toLowerCase();
      const rowClass = severity === "error" ? "is-error" : severity === "warning" ? "is-warning" : "";
      const tr = el("tr", { class: rowClass });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.eventType || "—" }),
        el("td", {}, severityTag(row.severity)),
        el("td", {}, statusTag(row.status)),
        el("td", { text: row.surface || "—" }),
        el("td", { class: "mono", text: row.route || "—" }),
        el("td", { class: "numeric", text: formatDuration(row.durationMs) }),
      );
      tr.append(traceCell(row.traceId));
      tr.append(idCell(row.userId));
      tr.append(
        el("td", { class: "wrap" }, [
          row.errorCode ? el("div", { class: "mono", text: row.errorCode }) : null,
          row.errorMessage ? el("div", { class: "wrap", text: row.errorMessage }) : null,
          !row.errorCode && !row.errorMessage
            ? el("span", { class: "tag tag-neutral", text: "—" })
            : null,
        ]),
      );
      tbody.appendChild(tr);
    }
  }

  function renderLlmTable(rows) {
    const tbody = $("#llm-table tbody");
    rows = applyClientControls("llm", rows);
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(11, "No LLM runs match the current filters."));
      return;
    }
    if (maybeRenderAggregateRows(tbody, "llm", rows)) return;
    for (const row of rows) {
      const flags = el("td", {});
      if (row.emptyToolCall) flags.appendChild(boolTag("empty", true));
      if (row.invalidToolArguments) flags.appendChild(boolTag("invalid_args", true));
      if (row.providerError) flags.appendChild(boolTag("provider_err", true));
      if (!flags.children.length) flags.appendChild(el("span", { class: "tag tag-neutral", text: "—" }));

      const tr = el("tr", { class: row.providerError ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.model || "—" }),
        el("td", { text: row.source || "—" }),
        el("td", { class: "mono", text: row.resultKind || "—" }),
        el("td", { class: "mono", text: row.selectedTool || "—" }),
        el("td", { class: "mono", text: row.executedTool || "—" }),
        el("td", { class: "numeric", text: formatDuration(row.totalMs) }),
        el("td", { class: "numeric", text: formatDuration(row.llmMs) }),
        el("td", { class: "numeric", text: formatNumber(row.totalTokens) }),
        flags,
      );
      tr.append(traceCell(row.traceId));
      tbody.appendChild(tr);
    }
  }

  function renderConversationsTable(rows) {
    const tbody = $("#conversations-table tbody");
    if (!tbody) return;
    rows = applyClientControls("conversations", rows);
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(6, "No conversations match the current filters."));
      return;
    }
    if (maybeRenderAggregateRows(tbody, "conversations", rows)) return;
    for (const row of rows) {
      const tr = el("tr", {
        class: row.hiddenFromUserAt ? "is-warning" : "",
        onClick: () => loadConversationDetail(row.id, true),
      });
      tr.append(
        el("td", { text: formatTimestamp(row.updatedAt) }),
        el("td", { class: "wrap", text: row.title || "—" }),
        idCell(row.userId),
        idCell(row.id),
        el("td", {}, row.hiddenFromUserAt ? statusTag("hidden") : statusTag("visible")),
        el("td", { text: formatTimestamp(row.createdAt) }),
      );
      tbody.appendChild(tr);
    }
  }

  function renderConversationDetail(rows) {
    const tbody = $("#conversation-detail-table tbody");
    if (!tbody) return;
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(8, "Select a conversation row."));
      renderSelectedMessageAccounting(null);
      return;
    }
    const orderedRows = [...rows].sort((a, b) => {
      const left = Date.parse(a?.createdAt || "");
      const right = Date.parse(b?.createdAt || "");
      if (!Number.isFinite(left) && !Number.isFinite(right)) return 0;
      if (!Number.isFinite(left)) return 1;
      if (!Number.isFinite(right)) return -1;
      return right - left;
    });
    for (const row of orderedRows) {
      const text = String(row.content || "");
      const selected = row.id === state.conversationDetail.selectedMessageId;
      const tr = el("tr", {
        class: `is-clickable${selected ? " is-selected" : ""}`,
        tabindex: "0",
        role: "button",
        "aria-selected": selected ? "true" : "false",
        title: "Select message for LLM accounting",
        onClick: () => selectConversationMessage(row.id),
        onKeydown: (event) => {
          if (event.key !== "Enter" && event.key !== " ") return;
          event.preventDefault();
          selectConversationMessage(row.id);
        },
      });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        idCell(row.turnId),
        el("td", { class: "mono", text: row.role || "—" }),
        el("td", { class: "mono", text: row.inputMode || "—" }),
        el("td", { class: "mono", text: row.source || "—" }),
      );
      tr.append(traceCell(row.traceId));
      tr.append(
        idCell(row.activeProposalId),
        el("td", { class: "wrap" }, renderExpandableValue(text)),
      );
      tbody.appendChild(tr);
    }
  }

  function selectConversationMessage(messageId) {
    state.conversationDetail.selectedMessageId = messageId;
    renderConversationDetail(state.conversationDetail.messages);
    renderSelectedMessageAccounting(messageId);
  }

  function renderSelectedMessageAccounting(messageId) {
    const message = (state.conversationDetail.messages || []).find((row) => row.id === messageId);
    const empty = $("#selected-message-empty");
    const meta = $("#selected-message-meta");
    const cards = $("#selected-message-cards");
    const relationTag = $("#selected-message-relation");
    const providerBody = $("#selected-provider-calls-table tbody");
    const toolBody = $("#selected-tool-calls-table tbody");
    if (!empty || !meta || !cards || !relationTag || !providerBody || !toolBody) return;

    if (!message) {
      empty.hidden = false;
      meta.hidden = true;
      cards.hidden = true;
      relationTag.textContent = "select a message";
      relationTag.className = "tag tag-neutral";
      providerBody.replaceChildren(renderEmptyRow(12, "Select a conversation message."));
      toolBody.replaceChildren(renderEmptyRow(8, "No tool call selected."));
      return;
    }

    const providerMatch = selectedProviderCallsForMessage(message);
    const toolRows = selectedToolCallsForMessage(message);
    const providerRows = providerMatch.calls;
    empty.hidden = true;
    meta.hidden = false;
    cards.hidden = false;
    relationTag.textContent = providerMatch.inferred
      ? `${providerMatch.relation} · inferred`
      : providerMatch.relation;
    relationTag.className = providerMatch.inferred ? "tag tag-warning" : "tag tag-info";

    meta.replaceChildren(
      selectedMetaItem("Role", message.role || "—"),
      selectedMetaItem("Time", formatTimestamp(message.createdAt)),
      selectedMetaItem("Message", copyableId(message.id)),
      selectedMetaItem("Turn", copyableId(message.turnId)),
      selectedMetaItem("Trace", copyableId(message.traceId)),
      selectedMetaItem("Iteration", metadataNumber(message, "iteration") ?? "—"),
    );

    renderSelectedMetricCards(providerRows);
    renderSelectedProviderRows(providerRows, providerMatch);
    renderSelectedToolRows(toolRows);
  }

  function selectedMetaItem(label, value) {
    const dt = el("dt", { text: label });
    const dd = el("dd", { class: typeof value === "string" ? "mono" : "" });
    if (typeof value === "string" || typeof value === "number") dd.textContent = String(value);
    else dd.appendChild(value);
    return el("div", {}, [dt, dd]);
  }

  function renderSelectedMetricCards(providerRows) {
    const values = {
      prompt: formatNumber(sumField(providerRows, "promptTokens")),
      completion: formatNumber(sumField(providerRows, "completionTokens")),
      total: formatNumber(sumField(providerRows, "totalTokens")),
      reasoning: formatNumber(sumField(providerRows, "reasoningTokens")),
      cost: formatMoney(costTotal(providerRows), currencyForRows(providerRows)),
      latency: formatDuration(sumField(providerRows, "durationMs")),
      status: providerRows.length
        ? [...new Set(providerRows.map((row) => row.status || "unknown"))].join(", ")
        : "—",
    };
    for (const [key, value] of Object.entries(values)) {
      const card = document.querySelector(`[data-selected-card="${key}"] [data-value]`);
      if (card) card.textContent = value;
    }
  }

  function renderSelectedProviderRows(rows, match) {
    const tbody = $("#selected-provider-calls-table tbody");
    if (!tbody) return;
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(12, "No provider calls match the selected message."));
      return;
    }
    for (const row of sortByCreatedDesc(rows)) {
      const tr = el("tr", { class: row.status === "failure" ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", {}, match.inferred ? statusTag("inferred") : statusTag(match.relation)),
        el("td", { class: "mono", text: row.provider || "—" }),
        el("td", { class: "mono", text: row.servedModel || row.requestedModel || "—" }),
        el("td", { class: "mono id-cell" }, copyableId(row.providerGenerationId || row.providerRequestId || row.id)),
        ...tokenCells(row),
        el("td", { class: "numeric", text: costAmount(row) }),
        el("td", { class: "numeric", text: formatDuration(row.durationMs) }),
        el("td", {}, statusTag(row.status)),
      );
      tbody.appendChild(tr);
    }
  }

  function renderSelectedToolRows(rows) {
    const tbody = $("#selected-tool-calls-table tbody");
    if (!tbody) return;
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(8, "No generated or executed tool call matches this message."));
      return;
    }
    for (const row of sortByCreatedDesc(rows)) {
      const resultOrError = row.errorMessage
        ? { error: row.errorMessage }
        : row.resultSummary;
      const tr = el("tr", {
        class: row.status === "failed" ? "is-error" : "",
      });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt || row.startedAt) }),
        el("td", { class: "mono", text: row.relation || "—" }),
        el("td", { class: "mono", text: row.actionId || "—" }),
        idCell(row.toolCallId),
        el("td", {}, statusTag(row.status)),
        el("td", { class: "numeric", text: formatDuration(row.durationMs) }),
        jsonCell(row.arguments),
        jsonCell(resultOrError),
      );
      tbody.appendChild(tr);
    }
  }

  function resetConversationDetailState() {
    state.conversationDetail = {
      conversationId: null,
      messages: [],
      agentTurns: [],
      providerCalls: [],
      agentToolCalls: [],
      selectedMessageId: null,
    };
  }

  function renderAgentTurnsTable(
    rows,
    selector = "#agent-turns-table tbody",
    emptyText = "No agent turns match the current filters.",
  ) {
    const tbody = $(selector);
    if (!tbody) return;
    if (selector === "#agent-turns-table tbody") rows = applyClientControls("agentTurns", rows);
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(17, emptyText));
      return;
    }
    if (selector === "#agent-turns-table tbody" && maybeRenderAggregateRows(tbody, "agentTurns", rows)) return;
    for (const row of rows) {
      const tr = el("tr", { class: row.status === "failure" ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        idCell(row.userId),
        idCell(row.conversationId),
        idCell(row.turnId),
      );
      tr.append(traceCell(row.traceId));
      tr.append(
        el("td", { class: "mono", text: row.inputMode || "—" }),
        el("td", { class: "mono", text: row.model || "—" }),
        el("td", { class: "mono", text: row.resultKind || "—" }),
        el("td", { class: "mono", text: row.stopReason || "—" }),
        el("td", { class: "numeric", text: formatNumber(row.toolCallCount) }),
        ...tokenCells(row),
        el("td", { class: "numeric", text: costAmount(row) }),
        el("td", { class: "numeric", text: formatDuration(row.totalMs) }),
        el("td", {}, statusTag(row.status)),
      );
      tbody.appendChild(tr);
    }
  }

  function renderActionCallsTable(rows, selector = "#action-calls-table tbody") {
    const tbody = $(selector);
    if (!tbody) return;
    if (selector === "#action-calls-table tbody") rows = applyClientControls("actionCalls", rows);
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(10, "No action calls match the current filters."));
      return;
    }
    if (selector === "#action-calls-table tbody" && maybeRenderAggregateRows(tbody, "actionCalls", rows)) return;
    for (const row of rows) {
      const tr = el("tr", { class: row.error ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        idCell(row.actionId),
        el("td", { class: "mono", text: row.source || "—" }),
        idCell(row.userId),
      );
      tr.append(traceCell(row.traceId));
      tr.append(
        el("td", { class: "numeric", text: formatDuration(row.latencyMs) }),
        el("td", { class: "mono", text: row.confirmationStatus || "—" }),
        jsonCell(row.input),
        jsonCell(row.output),
        jsonCell(row.error),
      );
      tbody.appendChild(tr);
    }
  }

  function renderLlmCostView(data) {
    const cardValues = {
      total: data?.totalCostAmount,
      provider: data?.totalProviderCostAmount,
      estimated: data?.totalEstimatedCostAmount,
      unknown: data?.unknownCostCount,
      tokens: data?.totalTokens,
    };
    for (const [key, value] of Object.entries(cardValues)) {
      const card = document.querySelector(`.card[data-cost-card="${key}"]`);
      if (!card) continue;
      const valueEl = card.querySelector("[data-value]");
      if (valueEl) {
        valueEl.textContent = key === "unknown" || key === "tokens"
          ? formatNumber(value)
          : formatMoney(value);
      }
    }

    const tbody = $("#llm-cost-table tbody");
    if (!tbody) return;
    tbody.replaceChildren();
    if (!data) {
      tbody.appendChild(renderEmptyRow(8, "No cost data loaded yet."));
      return;
    }
    const groups = [
      ["user", data.byUser],
      ["conversation", data.byConversation],
      ["turn", data.byTurn],
      ["model", data.byModel],
      ["provider", data.byProvider],
      ["feature", data.byFeature],
      ["day", data.byDay],
    ];
    const rows = groups.flatMap(([group, entries]) =>
      (entries || []).map((entry) => ({ group, ...entry })),
    );
    state.tableRows.set("llmCost", rows);
    if (rows.length === 0) {
      tbody.appendChild(renderEmptyRow(8, "No cost records match the current filters."));
      return;
    }
    const controls = readTableControls("llmCost");
    const visibleRows = controls.viewMode === "aggregate"
      ? sortAggregates(aggregateRows(rows, "llmCost", controls.groupBy), controls)
      : sortRows(rows, "llmCost", controls);
    if (controls.viewMode === "aggregate") {
      for (const row of visibleRows) {
        const tr = el("tr", { class: "is-aggregate" });
        tr.append(
          el("td", { class: "mono" }, copyableId(row.key)),
          el("td", { class: "numeric", text: formatNumber(row.count) }),
          el("td", { class: "numeric", text: formatMoney(row.totalCost) }),
          el("td", { class: "numeric", text: formatNumber(row.totalTokens) }),
          el("td", { class: "wrap", colspan: 4 }, renderExpandableValue(row.numericSummary, { mono: true })),
        );
        tbody.appendChild(tr);
      }
      return;
    }
    for (const row of visibleRows) {
      const tr = el("tr", { class: row.unknownCostCount > 0 ? "is-warning" : "" });
      tr.append(
        el("td", { class: "mono", text: row.group }),
        el("td", { class: "mono" }, copyableId(row.key || "unknown")),
        el("td", { class: "numeric", text: formatMoney(row.providerCostAmount) }),
        el("td", { class: "numeric", text: formatMoney(row.estimatedCostAmount) }),
        el("td", { class: "numeric", text: formatMoney(row.totalCostAmount) }),
        el("td", { class: "numeric", text: formatNumber(row.unknownCostCount) }),
        el("td", { class: "numeric", text: formatNumber(row.totalTokens) }),
        el("td", { class: "numeric", text: formatNumber(row.callCount) }),
      );
      tbody.appendChild(tr);
    }
  }

  function renderProviderCallsTable(
    rows,
    selector = "#provider-calls-table tbody",
    emptyText = "No provider calls match the current filters.",
  ) {
    const tbody = $(selector);
    if (!tbody) return;
    if (selector === "#provider-calls-table tbody") rows = applyClientControls("providerCalls", rows);
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(16, emptyText));
      return;
    }
    if (selector === "#provider-calls-table tbody" && maybeRenderAggregateRows(tbody, "providerCalls", rows)) return;
    for (const row of rows) {
      const tr = el("tr", { class: row.status === "failure" ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.provider || "—" }),
        el("td", { class: "mono", text: row.requestedModel || "—" }),
        el("td", { class: "mono", text: row.servedModel || "—" }),
        el("td", { class: "mono id-cell" }, copyableId(row.providerGenerationId || row.providerRequestId)),
      );
      tr.append(traceCell(row.traceId));
      tr.append(
        idCell(row.turnId),
        ...tokenCells(row),
        el("td", { class: "numeric", text: costAmount(row) }),
        el("td", { class: "mono", text: row.costSource || "—" }),
        el("td", { class: "numeric", text: formatDuration(row.durationMs) }),
        el("td", {}, statusTag(row.status)),
        el("td", { class: "wrap", text: row.errorMessage || row.errorCode || "—" }),
      );
      tbody.appendChild(tr);
    }
  }

  function renderTranscriptionsTable(rows, selector = "#transcriptions-table tbody") {
    const tbody = $(selector);
    if (!tbody) return;
    if (selector === "#transcriptions-table tbody") rows = applyClientControls("transcriptions", rows);
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(13, "No transcriptions match the current filters."));
      return;
    }
    if (selector === "#transcriptions-table tbody" && maybeRenderAggregateRows(tbody, "transcriptions", rows)) return;
    for (const row of rows) {
      const tr = el("tr", { class: row.status === "failed" ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.surface || "—" }),
        idCell(row.userId),
        idCell(row.conversationId),
      );
      tr.append(traceCell(row.traceId));
      tr.append(
        el("td", { class: "mono", text: row.provider || "—" }),
        el("td", { class: "mono", text: row.model || "—" }),
        el("td", { class: "mono", text: row.audioMimeType ? `${row.audioMimeType} · ${formatNumber(row.audioBytes)} B` : formatNumber(row.audioBytes) }),
        el("td", { class: "numeric", text: formatNumber(row.transcriptLength) }),
        el("td", { class: "numeric", text: formatDuration(row.durationMs) }),
        el("td", {}, statusTag(row.status)),
        el("td", { class: "wrap" }, renderExpandableValue(row.transcriptText)),
        el("td", { class: "wrap", text: row.errorMessage || row.errorCode || "—" }),
      );
      tbody.appendChild(tr);
    }
  }

  function renderTraceProviderCallsTable(rows) {
    const tbody = $("#trace-provider-calls-table tbody");
    if (!tbody) return;
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(11, "No provider calls recorded for this trace."));
      return;
    }
    for (const row of rows) {
      const tr = el("tr", { class: row.status === "failure" ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.provider || "—" }),
        el("td", { class: "mono", text: row.servedModel || row.requestedModel || "—" }),
        el("td", { class: "mono id-cell" }, copyableId(row.providerGenerationId || row.providerRequestId)),
        idCell(row.turnId),
        ...tokenCells(row),
        el("td", { class: "numeric", text: costAmount(row) }),
        el("td", {}, statusTag(row.status)),
      );
      tbody.appendChild(tr);
    }
  }

  function renderTraceTranscriptionsTable(rows) {
    const tbody = $("#trace-transcriptions-table tbody");
    if (!tbody) return;
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(8, "No transcriptions recorded for this trace."));
      return;
    }
    for (const row of rows) {
      const tr = el("tr", { class: row.status === "failed" ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.surface || "—" }),
        el("td", { class: "mono", text: row.provider || "—" }),
        idCell(row.conversationId),
        idCell(row.turnId),
        el("td", { class: "numeric", text: formatNumber(row.transcriptLength) }),
        el("td", {}, statusTag(row.status)),
        el("td", { class: "wrap" }, renderExpandableValue(row.transcriptText || row.errorMessage)),
      );
      tbody.appendChild(tr);
    }
  }

  function renderFoodTable(rows) {
    const tbody = $("#food-table tbody");
    rows = applyClientControls("food", rows);
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(9, "No food search events match the current filters."));
      return;
    }
    if (maybeRenderAggregateRows(tbody, "food", rows)) return;
    for (const row of rows) {
      const flags = el("td", {});
      if (row.zeroResults) flags.appendChild(boolTag("zero", true));
      if (row.lowConfidence) flags.appendChild(boolTag("low_conf", true));
      if (row.barcodePresent) flags.appendChild(boolTag("barcode", true));
      if (!flags.children.length) flags.appendChild(el("span", { class: "tag tag-neutral", text: "—" }));

      const query = row.queryText ? String(row.queryText) : "";
      const displayQuery = query.length > 80 ? `${query.slice(0, 77)}…` : query;

      const tr = el("tr", { class: row.zeroResults ? "is-warning" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "wrap", text: displayQuery || "—" }),
        el("td", { class: "mono", text: row.path || "—" }),
        el("td", { class: "numeric", text: formatNumber(row.resultCount) }),
        el("td", { class: "numeric", text: row.topScore != null ? Number(row.topScore).toFixed(4) : "—" }),
        el("td", { class: "mono", text: row.topExternalSource || "—" }),
        el("td", { class: "mono", text: row.locale || "—" }),
        flags,
      );
      tr.append(traceCell(row.traceId));
      tbody.appendChild(tr);
    }
  }

  function renderTraceView(payload) {
    const summary = $("#trace-summary");
    const meta = $("#trace-meta");
    const summaryTitle = $("#trace-summary-title");

    const traceId = payload?.traceId || "";
    summaryTitle.textContent = `Trace · ${traceId}`;

    const events = Array.isArray(payload?.events) ? payload.events : [];
    const llmRuns = Array.isArray(payload?.llmRuns) ? payload.llmRuns : [];
    const conversationMessages = Array.isArray(payload?.conversationMessages) ? payload.conversationMessages : [];
    const agentTurns = Array.isArray(payload?.agentTurns) ? payload.agentTurns : [];
    const agentToolCalls = Array.isArray(payload?.agentToolCalls) ? payload.agentToolCalls : [];
    const actionCalls = Array.isArray(payload?.actionCalls) ? payload.actionCalls : [];
    const providerCalls = Array.isArray(payload?.providerCalls) ? payload.providerCalls : [];
    const transcriptions = Array.isArray(payload?.transcriptions) ? payload.transcriptions : [];
    const foodSearches = Array.isArray(payload?.foodSearchEvents)
      ? payload.foodSearchEvents
      : Array.isArray(payload?.foodSearches)
        ? payload.foodSearches
        : [];

    const earliest = [
      events,
      llmRuns,
      conversationMessages,
      agentTurns,
      agentToolCalls,
      actionCalls,
      providerCalls,
      transcriptions,
      foodSearches,
    ]
      .flat()
      .map((r) => r?.createdAt)
      .filter(Boolean)
      .map((v) => new Date(v).getTime())
      .filter((n) => Number.isFinite(n))
      .sort((a, b) => a - b)[0];

    meta.replaceChildren(
      el("dt", { text: "Events" }),
      el("dd", { text: formatNumber(events.length) }),
      el("dt", { text: "LLM runs" }),
      el("dd", { text: formatNumber(llmRuns.length) }),
      el("dt", { text: "Messages" }),
      el("dd", { text: formatNumber(conversationMessages.length) }),
      el("dt", { text: "Agent turns" }),
      el("dd", { text: formatNumber(agentTurns.length) }),
      el("dt", { text: "Tool calls" }),
      el("dd", { text: formatNumber(agentToolCalls.length) }),
      el("dt", { text: "Action calls" }),
      el("dd", { text: formatNumber(actionCalls.length) }),
      el("dt", { text: "Provider calls" }),
      el("dd", { text: formatNumber(providerCalls.length) }),
      el("dt", { text: "Transcriptions" }),
      el("dd", { text: formatNumber(transcriptions.length) }),
      el("dt", { text: "Food searches" }),
      el("dd", { text: formatNumber(foodSearches.length) }),
      el("dt", { text: "First seen" }),
      el("dd", { class: "mono", text: earliest ? formatTimestamp(new Date(earliest).toISOString()) : "—" }),
      el("dt", { text: "Trace ID" }),
      el("dd", { class: "mono" }, copyableId(traceId)),
    );

    summary.hidden = false;

    const traceEventsBody = $("#trace-events-table tbody");
    traceEventsBody.replaceChildren();
    if (events.length === 0) {
      traceEventsBody.appendChild(renderEmptyRow(7, "No events recorded for this trace."));
    } else {
      for (const row of events) {
        const severity = (row.severity || "info").toLowerCase();
        const rowClass = severity === "error" ? "is-error" : severity === "warning" ? "is-warning" : "";
        const tr = el("tr", { class: rowClass });
        tr.append(
          el("td", { text: formatTimestamp(row.createdAt) }),
          el("td", { class: "mono", text: row.eventType || "—" }),
          el("td", {}, severityTag(row.severity)),
          el("td", {}, statusTag(row.status)),
          el("td", { class: "mono", text: row.route || "—" }),
          el("td", { class: "numeric", text: formatDuration(row.durationMs) }),
          el("td", { class: "wrap" }, [
            row.errorCode ? el("div", { class: "mono", text: row.errorCode }) : null,
            row.errorMessage ? el("div", { class: "wrap", text: row.errorMessage }) : null,
            !row.errorCode && !row.errorMessage
              ? el("span", { class: "tag tag-neutral", text: "—" })
              : null,
          ]),
        );
        traceEventsBody.appendChild(tr);
      }
    }

    const traceLlmBody = $("#trace-llm-table tbody");
    traceLlmBody.replaceChildren();
    if (llmRuns.length === 0) {
      traceLlmBody.appendChild(renderEmptyRow(7, "No LLM runs recorded for this trace."));
    } else {
      for (const row of llmRuns) {
        const tr = el("tr", { class: row.providerError ? "is-error" : "" });
        tr.append(
          el("td", { text: formatTimestamp(row.createdAt) }),
          el("td", { class: "mono", text: row.model || "—" }),
          el("td", { class: "mono", text: row.resultKind || "—" }),
          el("td", { class: "mono", text: row.selectedTool || "—" }),
          el("td", { class: "mono", text: row.executedTool || "—" }),
          el("td", { class: "numeric", text: formatDuration(row.totalMs) }),
          el("td", { class: "numeric", text: formatNumber(row.totalTokens) }),
        );
        traceLlmBody.appendChild(tr);
      }
    }

    const traceMessagesBody = $("#trace-messages-table tbody");
    traceMessagesBody.replaceChildren();
    if (conversationMessages.length === 0) {
      traceMessagesBody.appendChild(renderEmptyRow(7, "No conversation messages recorded for this trace."));
    } else {
      for (const row of conversationMessages) {
        const text = String(row.content || "");
        const tr = el("tr", {});
        tr.append(
          el("td", { text: formatTimestamp(row.createdAt) }),
          idCell(row.conversationId),
          idCell(row.turnId),
          el("td", { class: "mono", text: row.role || "—" }),
          el("td", { class: "mono", text: row.inputMode || "—" }),
          el("td", { class: "mono", text: row.source || "—" }),
          el("td", { class: "wrap" }, renderExpandableValue(text)),
        );
        traceMessagesBody.appendChild(tr);
      }
    }

    const traceAgentTurnsBody = $("#trace-agent-turns-table tbody");
    traceAgentTurnsBody.replaceChildren();
    if (agentTurns.length === 0) {
      traceAgentTurnsBody.appendChild(renderEmptyRow(12, "No agent turns recorded for this trace."));
    } else {
      for (const row of agentTurns) {
        const tr = el("tr", { class: row.status === "failure" ? "is-error" : "" });
        tr.append(
          el("td", { text: formatTimestamp(row.createdAt) }),
          idCell(row.conversationId),
          idCell(row.turnId),
          el("td", { class: "mono", text: row.inputMode || "—" }),
          el("td", { class: "mono", text: row.resultKind || "—" }),
          el("td", { class: "numeric", text: formatNumber(row.toolCallCount) }),
          ...tokenCells(row),
          el("td", { class: "numeric", text: costAmount(row) }),
          el("td", {}, statusTag(row.status)),
        );
        traceAgentTurnsBody.appendChild(tr);
      }
    }

    const traceToolActionBody = $("#trace-tool-action-table tbody");
    traceToolActionBody.replaceChildren();
    const toolActionRows = [
      ...agentToolCalls.map((row) => ({ kind: "tool", ...row })),
      ...actionCalls.map((row) => ({ kind: "action", ...row })),
    ].sort((a, b) => String(b.createdAt || "").localeCompare(String(a.createdAt || "")));
    if (toolActionRows.length === 0) {
      traceToolActionBody.appendChild(renderEmptyRow(7, "No tool or action calls recorded for this trace."));
    } else {
      for (const row of toolActionRows) {
        const tr = el("tr", { class: row.error || row.status === "failed" ? "is-error" : "" });
        tr.append(
          el("td", { text: formatTimestamp(row.createdAt || row.startedAt) }),
          el("td", { class: "mono", text: row.kind }),
          idCell(row.actionId),
          idCell(row.turnId),
          el("td", {}, statusTag(row.status || row.confirmationStatus)),
          el("td", { class: "numeric", text: formatDuration(row.durationMs ?? row.latencyMs) }),
          jsonCell(row.resultSummary ?? row.output ?? row.error ?? row.input ?? row.arguments),
        );
        traceToolActionBody.appendChild(tr);
      }
    }

    renderTraceProviderCallsTable(providerCalls);
    renderTraceTranscriptionsTable(transcriptions);

    const traceFoodBody = $("#trace-food-table tbody");
    traceFoodBody.replaceChildren();
    if (foodSearches.length === 0) {
      traceFoodBody.appendChild(renderEmptyRow(6, "No food search events recorded for this trace."));
    } else {
      for (const row of foodSearches) {
        const flags = el("td", {});
        if (row.zeroResults) flags.appendChild(boolTag("zero", true));
        if (row.lowConfidence) flags.appendChild(boolTag("low_conf", true));
        if (row.barcodePresent) flags.appendChild(boolTag("barcode", true));
        if (!flags.children.length) flags.appendChild(el("span", { class: "tag tag-neutral", text: "—" }));

        const query = row.queryText ? String(row.queryText) : "";
        const tr = el("tr", { class: row.zeroResults ? "is-warning" : "" });
        tr.append(
          el("td", { text: formatTimestamp(row.createdAt) }),
          el("td", { class: "wrap" }, renderExpandableValue(query)),
          el("td", { class: "mono", text: row.path || "—" }),
          el("td", { class: "numeric", text: formatNumber(row.resultCount) }),
          el("td", { class: "numeric", text: row.topScore != null ? Number(row.topScore).toFixed(4) : "—" }),
          flags,
        );
        traceFoodBody.appendChild(tr);
      }
    }
  }

  /* ========== Overview ========== */

  function applyOverviewCards(data) {
    const cards = {
      events_total: pickNumber(data, ["events", "eventsTotal", "events_total", "totalEvents"]),
      errors: pickNumber(data, ["errors", "errorCount", "error_count"]) ?? pickNumber(data?.eventsBySeverity, ["error"]),
      warnings: pickNumber(data, ["warnings", "warningCount", "warning_count"]) ?? pickNumber(data?.eventsBySeverity, ["warning"]),
      llm_runs: pickNumber(data, ["llmRuns", "llm_runs", "llmRunCount", "llm_run_count", "totalLlmRuns"]),
      food_search: pickNumber(data, ["foodSearch", "food_search", "foodSearchCount", "food_search_count", "totalFoodSearchEvents"]),
      zero_results: pickNumber(data, ["zeroResults", "zero_results", "zeroResultCount", "zeroResultRate"]),
      conversations: pickNumber(data, ["totalConversations", "conversations"]),
      agent_turns: pickNumber(data, ["totalAgentTurns", "agentTurns"]),
      provider_calls: pickNumber(data, ["totalProviderCalls", "providerCalls"]),
      transcriptions: pickNumber(data, ["totalTranscriptions", "transcriptions"]),
      provider_cost: pickNumber(data, ["providerCostAmount", "totalProviderCostAmount"]),
      estimated_cost: pickNumber(data, ["estimatedCostAmount", "totalEstimatedCostAmount"]),
      unknown_cost: pickNumber(data, ["unknownCostCount"]),
    };

    for (const [key, value] of Object.entries(cards)) {
      const card = document.querySelector(`.card[data-card="${key}"]`);
      if (!card) continue;
      card.classList.remove("is-loading", "is-error", "is-warning", "is-success");
      const valueEl = card.querySelector("[data-value]");
      valueEl.textContent =
        key === "provider_cost" || key === "estimated_cost"
          ? formatMoney(value)
          : formatNumber(value);
      if (key === "errors" && value > 0) card.classList.add("is-error");
      if (key === "warnings" && value > 0) card.classList.add("is-warning");
      if (key === "unknown_cost" && value > 0) card.classList.add("is-warning");
      if (key === "llm_runs" || key === "food_search") {
        if (value > 0) card.classList.add("is-success");
      }
    }
  }

  function pickNumber(obj, keys) {
    if (!obj || typeof obj !== "object") return null;
    for (const k of keys) {
      if (obj[k] != null) {
        const n = Number(obj[k]);
        if (Number.isFinite(n)) return n;
      }
    }
    // Allow nested shapes such as { counts: { events: 12 } }
    if (obj.counts && typeof obj.counts === "object") {
      for (const k of keys) {
        if (obj.counts[k] != null) {
          const n = Number(obj.counts[k]);
          if (Number.isFinite(n)) return n;
        }
      }
    }
    return null;
  }

  function setCardsLoading(loading) {
    $$(".card").forEach((card) => {
      card.classList.toggle("is-loading", !!loading);
      if (loading) {
        const v = card.querySelector("[data-value]");
        if (v) v.textContent = "…";
      }
    });
  }

  /* ========== Loaders ========== */

  async function loadOverview(filters) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    setCardsLoading(true);
    setStatusLoading("Loading overview…");
    const params = {};
    const fromIso = toIsoOrNull(filters.from);
    const toIso = toIsoOrNull(filters.to);
    if (fromIso) params.from = fromIso;
    if (toIso) params.to = toIso;
    try {
      const data = await apiGet(ENDPOINTS.overview || "/v1/admin/telemetry/overview", { params });
      applyOverviewCards(data || {});
      $("#overview-raw").textContent = JSON.stringify(data, null, 2);
      setStatusSuccess(`Overview loaded · ${formatTimestamp(new Date().toISOString())}`);
    } catch (err) {
      if (err.code === "aborted") return;
      setStatusError(err);
      $("#overview-raw").textContent = err.body
        ? JSON.stringify(err.body, null, 2)
        : err.message;
    } finally {
      setCardsLoading(false);
    }
  }

  async function loadEvents(filters) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    setStatusLoading("Loading events…");
    try {
      const params = {
        limit: filters.limit || DEFAULTS.eventsLimit || 100,
      };
      if (filters.severity) params.severity = filters.severity;
      if (filters.eventType) params.eventType = filters.eventType;
      if (filters.traceId) params.traceId = filters.traceId;
      if (filters.userId) params.userId = filters.userId;
      appendDateParams(params, filters);

      const data = await apiGet(ENDPOINTS.events || "/v1/admin/telemetry/events", { params });
      const rows = extractList(data, ["events", "items", "data", "results"]);
      renderEventsTable(rows);
      setStatusSuccess(`Loaded ${rows.length} event${rows.length === 1 ? "" : "s"}.`);
    } catch (err) {
      if (err.code === "aborted") return;
      renderEventsTable([]);
      setStatusError(err);
    }
  }

  async function loadLlmRuns(filters) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    setStatusLoading("Loading LLM runs…");
    try {
      const params = {
        limit: filters.limit || DEFAULTS.llmLimit || 100,
      };
      if (filters.resultKind) params.resultKind = filters.resultKind;
      if (filters.selectedTool) params.selectedTool = filters.selectedTool;
      if (filters.traceId) params.traceId = filters.traceId;
      if (filters.userId) params.userId = filters.userId;
      appendDateParams(params, filters);

      const data = await apiGet(ENDPOINTS.llmRuns || "/v1/admin/telemetry/llm-runs", { params });
      const rows = extractList(data, ["runs", "llmRuns", "items", "data", "results"]);
      renderLlmTable(rows);
      setStatusSuccess(`Loaded ${rows.length} LLM run${rows.length === 1 ? "" : "s"}.`);
    } catch (err) {
      if (err.code === "aborted") return;
      renderLlmTable([]);
      setStatusError(err);
    }
  }

  async function loadConversations(filters) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    setStatusLoading("Loading conversations…");
    try {
      const params = {
        limit: filters.limit || DEFAULTS.conversationsLimit || 100,
      };
      if (filters.userId) params.userId = filters.userId;
      if (filters.traceId) params.traceId = filters.traceId;
      if (filters.turnId) params.turnId = filters.turnId;
      if (filters.includeHidden) params.includeHidden = filters.includeHidden;
      appendDateParams(params, filters);
      const data = await apiGet(ENDPOINTS.conversations || "/v1/admin/telemetry/conversations", { params });
      const rows = extractList(data, ["conversations", "items", "data", "results"]);
      renderConversationsTable(rows);
      resetConversationDetailState();
      renderConversationDetail([]);
      renderSelectedMessageAccounting(null);
      renderAgentTurnsTable([], "#conversation-turns-table tbody", "Select a conversation row.");
      renderProviderCallsTable([], "#conversation-provider-calls-table tbody", "Select a conversation row.");
      setStatusSuccess(`Loaded ${rows.length} conversation${rows.length === 1 ? "" : "s"}.`);
    } catch (err) {
      if (err.code === "aborted") return;
      renderConversationsTable([]);
      setStatusError(err);
    }
  }

  async function loadConversationDetail(conversationId, includeHidden = true) {
    if (!conversationId) return;
    setStatusLoading(`Loading conversation ${conversationId}…`);
    try {
      const path = typeof ENDPOINTS.conversation === "function"
        ? ENDPOINTS.conversation(conversationId, includeHidden)
        : `/v1/admin/telemetry/conversations/${encodeURIComponent(conversationId)}?includeHidden=${includeHidden ? "true" : "false"}`;
      const data = await apiGet(path);
      const rows = extractList(data?.messages, ["messages", "items", "data"]);
      const turnsData = await apiGet(ENDPOINTS.agentTurns || "/v1/admin/telemetry/agent-turns", {
        params: { conversationId, limit: 500 },
      });
      const providerData = await apiGet(ENDPOINTS.providerCalls || "/v1/admin/telemetry/llm-provider-calls", {
        params: { conversationId, limit: 500 },
      });
      const toolData = await apiGet(ENDPOINTS.agentToolCalls || "/v1/admin/telemetry/agent-tool-calls", {
        params: { conversationId, limit: 500 },
      });
      const agentTurns = extractList(turnsData, ["agentTurns", "items", "data", "results"]);
      const providerCalls = extractList(providerData, ["providerCalls", "items", "data", "results"]);
      const agentToolCalls = extractList(toolData, ["agentToolCalls", "items", "data", "results"]);
      const orderedMessages = sortByCreatedDesc(rows);
      state.conversationDetail = {
        conversationId,
        messages: orderedMessages,
        agentTurns,
        providerCalls,
        agentToolCalls,
        selectedMessageId: orderedMessages[0]?.id ?? null,
      };
      renderConversationDetail(orderedMessages);
      renderSelectedMessageAccounting(state.conversationDetail.selectedMessageId);
      renderAgentTurnsTable(
        agentTurns,
        "#conversation-turns-table tbody",
        "No agent turns recorded for this conversation.",
      );
      renderProviderCallsTable(
        providerCalls,
        "#conversation-provider-calls-table tbody",
        "No provider calls recorded for this conversation.",
      );
      setStatusSuccess(`Loaded ${rows.length} conversation message${rows.length === 1 ? "" : "s"} · ${agentTurns.length} turn${agentTurns.length === 1 ? "" : "s"} · ${providerCalls.length} provider call${providerCalls.length === 1 ? "" : "s"} · ${agentToolCalls.length} tool call${agentToolCalls.length === 1 ? "" : "s"}.`);
    } catch (err) {
      if (err.code === "aborted") return;
      resetConversationDetailState();
      renderConversationDetail([]);
      renderSelectedMessageAccounting(null);
      renderAgentTurnsTable([], "#conversation-turns-table tbody", "Select a conversation row.");
      renderProviderCallsTable([], "#conversation-provider-calls-table tbody", "Select a conversation row.");
      setStatusError(err);
    }
  }

  async function loadAgentTurns(filters) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    setStatusLoading("Loading agent turns…");
    try {
      const params = { limit: filters.limit || DEFAULTS.agentTurnsLimit || 100 };
      if (filters.userId) params.userId = filters.userId;
      if (filters.conversationId) params.conversationId = filters.conversationId;
      if (filters.traceId) params.traceId = filters.traceId;
      if (filters.turnId) params.turnId = filters.turnId;
      if (filters.status) params.status = filters.status;
      appendDateParams(params, filters);
      const data = await apiGet(ENDPOINTS.agentTurns || "/v1/admin/telemetry/agent-turns", { params });
      const rows = extractList(data, ["agentTurns", "items", "data", "results"]);
      renderAgentTurnsTable(rows);
      setStatusSuccess(`Loaded ${rows.length} agent turn${rows.length === 1 ? "" : "s"}.`);
    } catch (err) {
      if (err.code === "aborted") return;
      renderAgentTurnsTable([]);
      setStatusError(err);
    }
  }

  async function loadActionCalls(filters) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    setStatusLoading("Loading action calls…");
    try {
      const params = { limit: filters.limit || DEFAULTS.actionCallsLimit || 100 };
      if (filters.userId) params.userId = filters.userId;
      if (filters.traceId) params.traceId = filters.traceId;
      if (filters.actionId) params.actionId = filters.actionId;
      appendDateParams(params, filters);
      const data = await apiGet(ENDPOINTS.actionCalls || "/v1/admin/telemetry/action-calls", { params });
      const rows = extractList(data, ["actionCalls", "items", "data", "results"]);
      renderActionCallsTable(rows);
      setStatusSuccess(`Loaded ${rows.length} action call${rows.length === 1 ? "" : "s"}.`);
    } catch (err) {
      if (err.code === "aborted") return;
      renderActionCallsTable([]);
      setStatusError(err);
    }
  }

  async function loadLlmCost(filters) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    setStatusLoading("Loading LLM cost…");
    try {
      const params = {};
      const fromIso = toIsoOrNull(filters.from);
      const toIso = toIsoOrNull(filters.to);
      if (fromIso) params.from = fromIso;
      if (toIso) params.to = toIso;
      if (filters.userId) params.userId = filters.userId;
      if (filters.conversationId) params.conversationId = filters.conversationId;
      if (filters.traceId) params.traceId = filters.traceId;
      const data = await apiGet(ENDPOINTS.llmCost || "/v1/admin/telemetry/llm-cost", { params });
      renderLlmCostView(data);
      setStatusSuccess("Loaded LLM cost breakdowns.");
    } catch (err) {
      if (err.code === "aborted") return;
      renderLlmCostView(null);
      setStatusError(err);
    }
  }

  async function loadProviderCalls(filters) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    setStatusLoading("Loading provider calls…");
    try {
      const params = { limit: filters.limit || DEFAULTS.providerCallsLimit || 100 };
      if (filters.userId) params.userId = filters.userId;
      if (filters.conversationId) params.conversationId = filters.conversationId;
      if (filters.traceId) params.traceId = filters.traceId;
      if (filters.provider) params.provider = filters.provider;
      if (filters.model) params.model = filters.model;
      if (filters.status) params.status = filters.status;
      if (filters.costSource) params.costSource = filters.costSource;
      appendDateParams(params, filters);
      const data = await apiGet(ENDPOINTS.providerCalls || "/v1/admin/telemetry/llm-provider-calls", { params });
      const rows = extractList(data, ["providerCalls", "items", "data", "results"]);
      renderProviderCallsTable(rows);
      setStatusSuccess(`Loaded ${rows.length} provider call${rows.length === 1 ? "" : "s"}.`);
    } catch (err) {
      if (err.code === "aborted") return;
      renderProviderCallsTable([]);
      setStatusError(err);
    }
  }

  async function loadTranscriptions(filters) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    setStatusLoading("Loading transcriptions…");
    try {
      const params = { limit: filters.limit || DEFAULTS.transcriptionsLimit || 100 };
      if (filters.userId) params.userId = filters.userId;
      if (filters.conversationId) params.conversationId = filters.conversationId;
      if (filters.traceId) params.traceId = filters.traceId;
      if (filters.surface) params.surface = filters.surface;
      if (filters.status) params.status = filters.status;
      appendDateParams(params, filters);
      const data = await apiGet(ENDPOINTS.transcriptions || "/v1/admin/telemetry/transcriptions", { params });
      const rows = extractList(data, ["transcriptions", "items", "data", "results"]);
      renderTranscriptionsTable(rows);
      setStatusSuccess(`Loaded ${rows.length} transcription${rows.length === 1 ? "" : "s"}.`);
    } catch (err) {
      if (err.code === "aborted") return;
      renderTranscriptionsTable([]);
      setStatusError(err);
    }
  }

  async function loadFoodSearch(filters) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    setStatusLoading("Loading food search events…");
    try {
      const params = {
        limit: filters.limit || DEFAULTS.foodLimit || 100,
      };
      if (filters.zeroResults != null && filters.zeroResults !== "") {
        params.zeroResults = filters.zeroResults;
      }
      if (filters.lowConfidence != null && filters.lowConfidence !== "") {
        params.lowConfidence = filters.lowConfidence;
      }
      if (filters.traceId) params.traceId = filters.traceId;
      if (filters.userId) params.userId = filters.userId;
      appendDateParams(params, filters);

      const data = await apiGet(ENDPOINTS.foodSearch || "/v1/admin/telemetry/food-search", { params });
      const rows = extractList(data, ["foodSearchEvents", "events", "foodSearches", "items", "data", "results"]);
      renderFoodTable(rows);
      setStatusSuccess(`Loaded ${rows.length} food search event${rows.length === 1 ? "" : "s"}.`);
    } catch (err) {
      if (err.code === "aborted") return;
      renderFoodTable([]);
      setStatusError(err);
    }
  }

  async function loadTrace(traceId) {
    if (!isSignedIn()) {
      renderAuthUi();
      setStatusLocked();
      return;
    }
    if (!traceId) {
      setStatusError({ message: "Trace id is required" });
      return;
    }
    setStatusLoading(`Loading trace ${traceId}…`);
    try {
      const buildTracePath =
        typeof ENDPOINTS.trace === "function"
          ? ENDPOINTS.trace(traceId)
          : `/v1/admin/telemetry/traces/${encodeURIComponent(traceId)}`;
      const data = await apiGet(buildTracePath);
      const payload = {
        traceId,
        events: extractList(data?.events, ["events", "items", "data"]),
        llmRuns: extractList(data?.llmRuns, ["llmRuns", "runs", "items", "data"]),
        foodSearches: extractList(data?.foodSearchEvents ?? data?.foodSearches, ["foodSearchEvents", "foodSearches", "events", "items", "data"]),
        ...data,
      };
      renderTraceView(payload);
      $("#trace-raw").textContent = JSON.stringify(data, null, 2);
      setStatusSuccess(`Trace loaded · ${formatTimestamp(new Date().toISOString())}`);
    } catch (err) {
      if (err.code === "aborted") return;
      setStatusError(err);
      $("#trace-raw").textContent = err.body
        ? JSON.stringify(err.body, null, 2)
        : err.message;
    }
  }

  function extractList(primary, fallbackKeys) {
    if (Array.isArray(primary)) return primary;
    if (!primary || typeof primary !== "object") {
      for (const k of fallbackKeys) {
        const v = primary?.[k];
        if (Array.isArray(v)) return v;
      }
      return [];
    }
    for (const k of fallbackKeys) {
      if (Array.isArray(primary[k])) return primary[k];
    }
    return [];
  }

  /* ========== Form binding ========== */

  function bindConfigForm() {
    const form = $("#config-form");
    const baseInput = $("#api-base");
    const usernameInput = $("#admin-username");
    const passwordInput = $("#admin-password");
    const signoutBtn = $("#admin-signout");
    const submitBtn = $("#admin-login-submit");

    const stored = readStoredConfig();
    state.apiBase = stored.apiBase || DEFAULT_API_BASE;
    state.apiToken = stored.apiToken;
    state.adminUsername = stored.adminUsername;
    baseInput.value = state.apiBase || "";
    usernameInput.value = state.adminUsername || "";
    renderAuthUi();

    function selectApiBase(raw) {
      const nextBase = normalizeBase(raw);
      const changed = Boolean(state.apiBase && state.apiBase !== nextBase);
      const clearedSession = changed && isSignedIn();

      if (changed) abortInFlight();
      state.apiBase = nextBase;
      baseInput.value = nextBase;
      writeStoredConfig({ apiBase: nextBase });

      if (clearedSession) {
        clearSession();
        state.apiToken = "";
        state.adminUsername = "";
        clearProtectedData();
        renderAuthUi();
      }
      return { changed, clearedSession };
    }

    baseInput.addEventListener("change", () => {
      try {
        const selection = selectApiBase(baseInput.value);
        if (selection.clearedSession) {
          setStatus("locked", "API environment changed. Sign in again for this environment.");
          usernameInput.focus();
        } else if (selection.changed) {
          setStatusSuccess(`Selected API environment · ${state.apiBase}`);
        }
      } catch (err) {
        baseInput.value = state.apiBase;
        setStatusError(err);
      }
    });

    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      let selection;
      try {
        selection = selectApiBase(baseInput.value);
      } catch (err) {
        setStatusError(err);
        baseInput.focus();
        return;
      }

      if (selection.clearedSession) {
        setStatus("locked", "API environment changed. Sign in again for this environment.");
        usernameInput.focus();
        return;
      }

      if (state.apiToken) {
        setStatusSuccess(`API environment unchanged · ${state.apiBase}`);
        return;
      }

      const username = usernameInput.value.trim();
      const password = passwordInput.value;
      if (!username || !password) {
        setStatusError({ message: "Admin username and password are required." });
        (!username ? usernameInput : passwordInput).focus();
        return;
      }

      try {
        submitBtn.disabled = true;
        submitBtn.textContent = "Signing in…";
        await loginAdmin(username, password);
        passwordInput.value = "";
        setStatusSuccess("Signed in. Loading telemetry…");
        if (!bootstrapTabFromHash()) {
          await loadOverview({});
        }
      } catch (err) {
        if (err.code !== "aborted") {
          err.message = friendlyLoginError(err);
          setStatusError(err);
        }
      } finally {
        submitBtn.disabled = false;
        renderAuthUi();
      }
    });

    signoutBtn.addEventListener("click", () => {
      logoutAdmin();
      usernameInput.focus();
    });
  }

  function bindFilterForms() {
    const overviewForm = $("#overview-filters");
    overviewForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(overviewForm);
      loadOverview(filters);
    });

    const eventsForm = $("#events-filters");
    eventsForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(eventsForm);
      loadEvents(filters);
    });

    const llmForm = $("#llm-filters");
    llmForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(llmForm);
      loadLlmRuns(filters);
    });

    const conversationsForm = $("#conversations-filters");
    conversationsForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(conversationsForm);
      loadConversations(filters);
    });

    const agentTurnsForm = $("#agent-turns-filters");
    agentTurnsForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(agentTurnsForm);
      loadAgentTurns(filters);
    });

    const actionCallsForm = $("#action-calls-filters");
    actionCallsForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(actionCallsForm);
      loadActionCalls(filters);
    });

    const llmCostForm = $("#llm-cost-filters");
    llmCostForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(llmCostForm);
      loadLlmCost(filters);
    });

    const providerCallsForm = $("#provider-calls-filters");
    providerCallsForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(providerCallsForm);
      loadProviderCalls(filters);
    });

    const transcriptionsForm = $("#transcriptions-filters");
    transcriptionsForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(transcriptionsForm);
      loadTranscriptions(filters);
    });

    const foodForm = $("#food-filters");
    foodForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(foodForm);
      loadFoodSearch(filters);
    });

    const traceForm = $("#trace-filters");
    traceForm.addEventListener("submit", (e) => {
      e.preventDefault();
      const filters = readFilters(traceForm);
      const traceId = (filters.traceId || "").trim();
      if (!traceId) {
        setStatusError({ message: "Trace id is required." });
        return;
      }
      loadTrace(traceId);
    });

    $$("[data-reset]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const form = document.getElementById(btn.dataset.reset);
        resetForm(form);
        if (form === eventsForm) loadEvents({});
        if (form === llmForm) loadLlmRuns({});
        if (form === conversationsForm) loadConversations({});
        if (form === agentTurnsForm) loadAgentTurns({});
        if (form === actionCallsForm) loadActionCalls({});
        if (form === llmCostForm) loadLlmCost({});
        if (form === providerCallsForm) loadProviderCalls({});
        if (form === transcriptionsForm) loadTranscriptions({});
        if (form === foodForm) loadFoodSearch({});
      });
    });

    // Submit on Enter in the trace id field from anywhere in the trace view
    $("#trace-id").addEventListener("keydown", (e) => {
      if (e.key === "Enter") {
        e.preventDefault();
        traceForm.requestSubmit();
      }
    });
  }

  function bindGlobalHotkeys() {
    document.addEventListener("keydown", (e) => {
      // Avoid hijacking modifier shortcuts.
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const target = e.target;
      const isFormControl =
        target &&
        (target.tagName === "INPUT" ||
          target.tagName === "TEXTAREA" ||
          target.tagName === "SELECT" ||
          target.isContentEditable);
      if (isFormControl) return;

      const shortcuts = {
        "1": "view-overview",
        "2": "view-events",
        "3": "view-llm",
        "4": "view-conversations",
        "5": "view-agent-turns",
        "6": "view-action-calls",
        "7": "view-llm-cost",
        "8": "view-provider-calls",
        "9": "view-transcriptions",
        "0": "view-trace",
      };
      const view = shortcuts[e.key];
      if (view) {
        e.preventDefault();
        if (!isSignedIn()) {
          setStatusLocked();
          return;
        }
        activateTab(view);
      }
    });
  }

  /* ========== Init ========== */

  function init() {
    bindTabs();
    enhanceFilterForms();
    makeAllTablesResizable();
    bindConfigForm();
    bindFilterForms();
    bindGlobalHotkeys();
    if (isSignedIn()) {
      if (!bootstrapTabFromHash()) {
        loadOverview({});
      }
    } else {
      clearProtectedData();
      renderAuthUi();
      setStatusLocked();
    }
    window.addEventListener("hashchange", bootstrapTabFromHash);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
