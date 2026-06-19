/* BetterCalories Admin · Telemetry
 * Vanilla JS application logic for the static admin panel.
 *
 * Features:
 *  - Configurable API base URL persisted in localStorage.
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
  const STORAGE = {
    apiBase: cfg.storageKeys?.apiBase || "bc.admin.apiBase",
    apiToken: cfg.storageKeys?.apiToken || "bc.admin.apiToken",
    adminUsername: cfg.storageKeys?.adminUsername || "bc.admin.username",
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
      else if (k === "html") node.innerHTML = v;
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
    migrateLegacyToken();
    try {
      return {
        apiBase: localStorage.getItem(STORAGE.apiBase) || "",
        apiToken: sessionStorage.getItem(STORAGE.apiToken) || "",
        adminUsername: sessionStorage.getItem(STORAGE.adminUsername) || "",
      };
    } catch (err) {
      console.warn("browser storage unavailable", err);
      return { apiBase: "", apiToken: "", adminUsername: "" };
    }
  }

  function writeStoredConfig({ apiBase, apiToken, adminUsername }) {
    try {
      if (apiBase != null) localStorage.setItem(STORAGE.apiBase, apiBase);
      if (apiToken != null) sessionStorage.setItem(STORAGE.apiToken, apiToken);
      if (adminUsername != null) sessionStorage.setItem(STORAGE.adminUsername, adminUsername);
    } catch (err) {
      console.warn("browser storage write failed", err);
    }
  }

  function clearSession() {
    try {
      sessionStorage.removeItem(STORAGE.apiToken);
      sessionStorage.removeItem(STORAGE.adminUsername);
      localStorage.removeItem(STORAGE.apiToken);
    } catch (err) {
      console.warn("sessionStorage clear failed", err);
    }
  }

  function migrateLegacyToken() {
    try {
      const legacy = localStorage.getItem(STORAGE.apiToken);
      if (legacy && !sessionStorage.getItem(STORAGE.apiToken)) {
        sessionStorage.setItem(STORAGE.apiToken, legacy);
      }
      localStorage.removeItem(STORAGE.apiToken);
    } catch (_) {
      /* ignore storage migration failures */
    }
  }

  /* ========== Status indicator ========== */

  const statusPill = () => $("#status-pill");
  const statusMessage = () => $("#status-message");

  function setStatus(state_, message, opts = {}) {
    const pill = statusPill();
    const msg = statusMessage();
    if (!pill || !msg) return;
    pill.dataset.state = state_;
    pill.textContent = state_;
    if (opts.html) msg.innerHTML = message;
    else msg.textContent = message;
  }

  function setStatusLoading(label) {
    setStatus("loading", label || "Loading…");
  }

  function setStatusError(err) {
    const { status, message, url } = err;
    const code = err?.body?.error?.code || err?.body?.code;
    if ((status === 401 && code !== "invalid_admin_credentials") || code === "token_expired" || code === "admin_token_required" || code === "admin_token_invalid") {
      setStatus("error", `Your admin session expired. Sign in again.${url ? ` · <code>${escapeHtml(url)}</code>` : ""}`, { html: true });
      return;
    }
    if (status === 403 || code === "permission_denied" || code === "admin_scope_required") {
      setStatus("error", `This token is not authorized for admin telemetry.${url ? ` · <code>${escapeHtml(url)}</code>` : ""}`, { html: true });
      return;
    }
    let body = message || "Request failed";
    if (status) body = `${status} · ${body}`;
    if (url) body += ` · <code>${escapeHtml(url)}</code>`;
    setStatus("error", body, { html: true });
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
    return (raw || "").trim().replace(/\/+$/, "");
  }

  function buildUrl(path) {
    const base = normalizeBase(state.apiBase || DEFAULT_API_BASE);
    if (!base) throw new Error("API base URL is not configured.");
    if (path.startsWith("http")) return path;
    return `${base}${path.startsWith("/") ? "" : "/"}${path}`;
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

    const headers = { Accept: "application/json" };
    if (state.apiToken) headers.Authorization = `Bearer ${state.apiToken}`;

    let response;
    try {
      response = await fetch(url, { method: "GET", headers, signal: ctrl.signal });
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
    renderConversationDetail([]);
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
    writeStoredConfig({ apiToken: token, adminUsername: normalizedUsername });
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

  function escapeHtml(value) {
    if (value == null) return "";
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

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
      typeof value === "string" ? value : JSON.stringify(value);
    if (!raw) return "—";
    return raw.length > max ? `${raw.slice(0, max - 1)}…` : raw;
  }

  function costAmount(row) {
    const amount = row?.providerCostAmount ?? row?.estimatedCostAmount ?? row?.totalCostAmount;
    return formatMoney(amount, row?.costCurrency || "USD");
  }

  function traceCell(value) {
    if (!value) return el("td", { class: "mono", text: "—" });
    const text = String(value);
    const node = el("td", { class: "mono", text });
    node.title = text;
    return node;
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
    if (!isSignedIn()) return;
    const hash = (location.hash || "").replace(/^#/, "");
    if (hash && $$(".view").some((v) => v.id === hash)) {
      activateTab(hash);
    }
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
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(10, "No events match the current filters."));
      return;
    }
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
      tr.append(el("td", { class: "mono", text: row.userId || "—" }));
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
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(11, "No LLM runs match the current filters."));
      return;
    }
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
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(6, "No conversations match the current filters."));
      return;
    }
    for (const row of rows) {
      const tr = el("tr", {
        class: row.hiddenFromUserAt ? "is-warning" : "",
        onClick: () => loadConversationDetail(row.id, true),
      });
      tr.append(
        el("td", { text: formatTimestamp(row.updatedAt) }),
        el("td", { class: "wrap", text: row.title || "—" }),
        el("td", { class: "mono", text: row.userId || "—" }),
        el("td", { class: "mono" }, copyableSpan(row.id)),
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
      return;
    }
    for (const row of rows) {
      const text = String(row.content || "");
      const tr = el("tr", {});
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.turnId || "—" }),
        el("td", { class: "mono", text: row.role || "—" }),
        el("td", { class: "mono", text: row.inputMode || "—" }),
        el("td", { class: "mono", text: row.source || "—" }),
      );
      tr.append(traceCell(row.traceId));
      tr.append(
        el("td", { class: "mono", text: row.activeProposalId || "—" }),
        el("td", { class: "wrap", text: text.length > 240 ? `${text.slice(0, 239)}…` : text || "—" }),
      );
      tbody.appendChild(tr);
    }
  }

  function renderAgentTurnsTable(rows, selector = "#agent-turns-table tbody") {
    const tbody = $(selector);
    if (!tbody) return;
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(14, "No agent turns match the current filters."));
      return;
    }
    for (const row of rows) {
      const tr = el("tr", { class: row.status === "failure" ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.userId || "—" }),
        el("td", { class: "mono", text: row.conversationId || "—" }),
        el("td", { class: "mono", text: row.turnId || "—" }),
      );
      tr.append(traceCell(row.traceId));
      tr.append(
        el("td", { class: "mono", text: row.inputMode || "—" }),
        el("td", { class: "mono", text: row.model || "—" }),
        el("td", { class: "mono", text: row.resultKind || "—" }),
        el("td", { class: "mono", text: row.stopReason || "—" }),
        el("td", { class: "numeric", text: formatNumber(row.toolCallCount) }),
        el("td", { class: "numeric", text: formatNumber(row.totalTokens) }),
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
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(10, "No action calls match the current filters."));
      return;
    }
    for (const row of rows) {
      const tr = el("tr", { class: row.error ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.actionId || "—" }),
        el("td", { class: "mono", text: row.source || "—" }),
        el("td", { class: "mono", text: row.userId || "—" }),
      );
      tr.append(traceCell(row.traceId));
      tr.append(
        el("td", { class: "numeric", text: formatDuration(row.latencyMs) }),
        el("td", { class: "mono", text: row.confirmationStatus || "—" }),
        el("td", { class: "wrap mono", text: jsonPreview(row.input) }),
        el("td", { class: "wrap mono", text: jsonPreview(row.output) }),
        el("td", { class: "wrap mono", text: jsonPreview(row.error) }),
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
    if (rows.length === 0) {
      tbody.appendChild(renderEmptyRow(8, "No cost records match the current filters."));
      return;
    }
    for (const row of rows) {
      const tr = el("tr", { class: row.unknownCostCount > 0 ? "is-warning" : "" });
      tr.append(
        el("td", { class: "mono", text: row.group }),
        el("td", { class: "mono", text: row.key || "unknown" }),
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

  function renderProviderCallsTable(rows, selector = "#provider-calls-table tbody") {
    const tbody = $(selector);
    if (!tbody) return;
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(13, "No provider calls match the current filters."));
      return;
    }
    for (const row of rows) {
      const tr = el("tr", { class: row.status === "failure" ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.provider || "—" }),
        el("td", { class: "mono", text: row.requestedModel || "—" }),
        el("td", { class: "mono", text: row.servedModel || "—" }),
        el("td", { class: "mono", text: row.providerGenerationId || row.providerRequestId || "—" }),
      );
      tr.append(traceCell(row.traceId));
      tr.append(
        el("td", { class: "mono", text: row.turnId || "—" }),
        el("td", { class: "numeric", text: formatNumber(row.totalTokens) }),
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
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(13, "No transcriptions match the current filters."));
      return;
    }
    for (const row of rows) {
      const tr = el("tr", { class: row.status === "failed" ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.surface || "—" }),
        el("td", { class: "mono", text: row.userId || "—" }),
        el("td", { class: "mono", text: row.conversationId || "—" }),
      );
      tr.append(traceCell(row.traceId));
      tr.append(
        el("td", { class: "mono", text: row.provider || "—" }),
        el("td", { class: "mono", text: row.model || "—" }),
        el("td", { class: "mono", text: row.audioMimeType ? `${row.audioMimeType} · ${formatNumber(row.audioBytes)} B` : formatNumber(row.audioBytes) }),
        el("td", { class: "numeric", text: formatNumber(row.transcriptLength) }),
        el("td", { class: "numeric", text: formatDuration(row.durationMs) }),
        el("td", {}, statusTag(row.status)),
        el("td", { class: "wrap", text: row.transcriptText || "—" }),
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
      tbody.appendChild(renderEmptyRow(8, "No provider calls recorded for this trace."));
      return;
    }
    for (const row of rows) {
      const tr = el("tr", { class: row.status === "failure" ? "is-error" : "" });
      tr.append(
        el("td", { text: formatTimestamp(row.createdAt) }),
        el("td", { class: "mono", text: row.provider || "—" }),
        el("td", { class: "mono", text: row.servedModel || row.requestedModel || "—" }),
        el("td", { class: "mono", text: row.providerGenerationId || row.providerRequestId || "—" }),
        el("td", { class: "mono", text: row.turnId || "—" }),
        el("td", { class: "numeric", text: formatNumber(row.totalTokens) }),
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
        el("td", { class: "mono", text: row.conversationId || "—" }),
        el("td", { class: "mono", text: row.turnId || "—" }),
        el("td", { class: "numeric", text: formatNumber(row.transcriptLength) }),
        el("td", {}, statusTag(row.status)),
        el("td", { class: "wrap", text: row.transcriptText || row.errorMessage || "—" }),
      );
      tbody.appendChild(tr);
    }
  }

  function renderFoodTable(rows) {
    const tbody = $("#food-table tbody");
    tbody.replaceChildren();
    if (!rows || rows.length === 0) {
      tbody.appendChild(renderEmptyRow(9, "No food search events match the current filters."));
      return;
    }
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
      el("dd", { class: "mono" }, copyableSpan(traceId)),
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
          el("td", { class: "mono", text: row.conversationId || "—" }),
          el("td", { class: "mono", text: row.turnId || "—" }),
          el("td", { class: "mono", text: row.role || "—" }),
          el("td", { class: "mono", text: row.inputMode || "—" }),
          el("td", { class: "mono", text: row.source || "—" }),
          el("td", { class: "wrap", text: text.length > 220 ? `${text.slice(0, 219)}…` : text || "—" }),
        );
        traceMessagesBody.appendChild(tr);
      }
    }

    const traceAgentTurnsBody = $("#trace-agent-turns-table tbody");
    traceAgentTurnsBody.replaceChildren();
    if (agentTurns.length === 0) {
      traceAgentTurnsBody.appendChild(renderEmptyRow(9, "No agent turns recorded for this trace."));
    } else {
      for (const row of agentTurns) {
        const tr = el("tr", { class: row.status === "failure" ? "is-error" : "" });
        tr.append(
          el("td", { text: formatTimestamp(row.createdAt) }),
          el("td", { class: "mono", text: row.conversationId || "—" }),
          el("td", { class: "mono", text: row.turnId || "—" }),
          el("td", { class: "mono", text: row.inputMode || "—" }),
          el("td", { class: "mono", text: row.resultKind || "—" }),
          el("td", { class: "numeric", text: formatNumber(row.toolCallCount) }),
          el("td", { class: "numeric", text: formatNumber(row.totalTokens) }),
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
          el("td", { class: "mono", text: row.actionId || "—" }),
          el("td", { class: "mono", text: row.turnId || "—" }),
          el("td", {}, statusTag(row.status || row.confirmationStatus)),
          el("td", { class: "numeric", text: formatDuration(row.durationMs ?? row.latencyMs) }),
          el("td", { class: "wrap mono", text: jsonPreview(row.resultSummary ?? row.output ?? row.error ?? row.input ?? row.arguments) }),
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
        const displayQuery = query.length > 80 ? `${query.slice(0, 77)}…` : query;

        const tr = el("tr", { class: row.zeroResults ? "is-warning" : "" });
        tr.append(
          el("td", { text: formatTimestamp(row.createdAt) }),
          el("td", { class: "wrap", text: displayQuery || "—" }),
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
      const data = await apiGet(ENDPOINTS.conversations || "/v1/admin/telemetry/conversations", { params });
      const rows = extractList(data, ["conversations", "items", "data", "results"]);
      renderConversationsTable(rows);
      renderConversationDetail([]);
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
      renderConversationDetail(rows);
      setStatusSuccess(`Loaded ${rows.length} conversation message${rows.length === 1 ? "" : "s"}.`);
    } catch (err) {
      if (err.code === "aborted") return;
      renderConversationDetail([]);
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

    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      const base = normalizeBase(baseInput.value);
      if (!base) {
        setStatusError({ message: "API base URL is required." });
        baseInput.focus();
        return;
      }
      state.apiBase = base;
      baseInput.value = base;
      writeStoredConfig({ apiBase: state.apiBase });

      if (state.apiToken) {
        setStatusSuccess(`Saved API base · ${state.apiBase}`);
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
        setStatusSuccess("Signed in. Loading overview…");
        await loadOverview({});
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
    bindConfigForm();
    bindFilterForms();
    bindGlobalHotkeys();
    if (isSignedIn()) {
      bootstrapTabFromHash();
      loadOverview({});
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
