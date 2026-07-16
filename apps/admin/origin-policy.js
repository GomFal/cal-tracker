/* BetterCalories Admin · trusted API origins.
 *
 * Keep this dependency-free so the same policy can run in the browser and in
 * the repository's Node-based security tests.
 */
((root) => {
  "use strict";

  const approvedApiOrigins = Object.freeze([
    "http://localhost:3000",
    "https://dev-api.bettercalories.app",
    "https://api.bettercalories.app",
  ]);
  const approvedApiOriginSet = new Set(approvedApiOrigins);

  function policyError(message) {
    const error = new Error(message);
    error.code = "unapproved_api_origin";
    return error;
  }

  function normalizeApiBase(raw) {
    const value = String(raw || "").trim();
    let url;
    try {
      url = new URL(value);
    } catch (_) {
      throw policyError("Select an approved API environment.");
    }

    if (
      url.username ||
      url.password ||
      url.search ||
      url.hash ||
      (url.pathname && url.pathname !== "/") ||
      !approvedApiOriginSet.has(url.origin)
    ) {
      throw policyError("Select an approved API environment.");
    }

    return url.origin;
  }

  function resolveApiUrl(apiBase, path) {
    const origin = normalizeApiBase(apiBase);
    if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
      throw policyError("Admin API paths must be relative to the selected environment.");
    }

    const resolved = new URL(path, `${origin}/`);
    if (resolved.origin !== origin) {
      throw policyError("The admin API request left the selected environment.");
    }
    return resolved.toString();
  }

  function createAuthorizedHeaders(apiBase, requestUrl, token, additionalHeaders = {}) {
    const origin = normalizeApiBase(apiBase);
    let request;
    try {
      request = new URL(requestUrl);
    } catch (_) {
      throw policyError("The admin API request URL is invalid.");
    }
    if (request.origin !== origin || !approvedApiOriginSet.has(request.origin)) {
      throw policyError("Refusing to send admin credentials to an unapproved origin.");
    }

    const headers = { ...additionalHeaders };
    if (token) {
      // Production and deployed development are HTTPS-only. Plain HTTP is an
      // explicit loopback exception for the local backend on the same host.
      if (request.protocol !== "https:" && request.origin !== "http://localhost:3000") {
        throw policyError("Refusing to send admin credentials over an insecure connection.");
      }
      headers.Authorization = `Bearer ${token}`;
    }
    return headers;
  }

  function defaultApiBaseFor(locationLike) {
    const hostname = locationLike?.hostname;
    if (hostname === "api.bettercalories.app") return "https://api.bettercalories.app";
    if (hostname === "dev-api.bettercalories.app") return "https://dev-api.bettercalories.app";
    return "http://localhost:3000";
  }

  root.AdminOriginPolicy = Object.freeze({
    approvedApiOrigins,
    normalizeApiBase,
    resolveApiUrl,
    createAuthorizedHeaders,
    defaultApiBaseFor,
  });
})(typeof globalThis !== "undefined" ? globalThis : window);
