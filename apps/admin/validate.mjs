/* BetterCalories Admin · Telemetry
 * Static validation: ensure all required files are present and that
 * the HTML references the expected scripts, styles, and IDs.
 */
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = new URL(".", import.meta.url).pathname;
const fail = (message) => {
  console.error(`✗ ${message}`);
  process.exitCode = 1;
};

const requiredFiles = [
  "index.html",
  "styles.css",
  "app.js",
  "config.js",
  "README.md",
];

for (const file of requiredFiles) {
  if (!existsSync(join(root, file))) {
    fail(`Missing required file: ${file}`);
    continue;
  }
  console.log(`✓ ${file}`);
}

const read = (file) => {
  try {
    return readFileSync(join(root, file), "utf8");
  } catch (err) {
    fail(`Cannot read ${file}: ${err.message}`);
    return "";
  }
};

const index = read("index.html");
const app = read("app.js");
const config = read("config.js");

const requiredHtmlSnippets = [
  ['<title>BetterCalories Admin · Telemetry</title>', "title"],
  ['href="styles.css"', "stylesheet link"],
  ['src="config.js"', "config.js script"],
  ['src="app.js"', "app.js script"],
  ['id="config-form"', "config form"],
  ['id="api-base"', "API base URL input"],
  ['id="admin-username"', "admin username input"],
  ['id="admin-password"', "admin password input"],
  ['id="admin-login-submit"', "admin login button"],
  ['id="admin-signout"', "admin signout button"],
  ['id="admin-session"', "admin session indicator"],
  ['id="status-pill"', "status pill"],
  ['id="view-overview"', "overview view"],
  ['id="view-events"', "events view"],
  ['id="view-llm"', "LLM runs view"],
  ['id="view-food"', "food search view"],
  ['id="view-trace"', "trace view"],
  ['id="events-table"', "events table"],
  ['id="llm-table"', "LLM table"],
  ['id="food-table"', "food table"],
  ['id="trace-events-table"', "trace events table"],
  ['id="trace-llm-table"', "trace LLM table"],
  ['id="trace-food-table"', "trace food table"],
  ['id="trace-summary"', "trace summary section"],
];

for (const [snippet, label] of requiredHtmlSnippets) {
  if (!index.includes(snippet)) {
    fail(`HTML missing ${label}: ${snippet}`);
  } else {
    console.log(`✓ HTML · ${label}`);
  }
}

const requiredConfigKeys = [
  "defaultApiBase",
  "storageKeys",
  "endpoints",
  "adminLogin",
  "overview",
  "events",
  "llmRuns",
  "foodSearch",
  "trace",
];

for (const key of requiredConfigKeys) {
  if (!config.includes(key)) {
    fail(`config.js missing key: ${key}`);
  } else {
    console.log(`✓ config.js · ${key}`);
  }
}

const requiredAppFeatures = [
  ["localStorage", "uses localStorage for API base URL"],
  ["sessionStorage", "uses sessionStorage for admin token"],
  ["apiGet", "apiGet helper"],
  ["apiPost", "apiPost helper"],
  ["loginAdmin", "admin login helper"],
  ["logoutAdmin", "admin logout helper"],
  ["renderEventsTable", "events renderer"],
  ["renderLlmTable", "LLM renderer"],
  ["renderFoodTable", "food renderer"],
  ["renderTraceView", "trace renderer"],
  ["loadOverview", "overview loader"],
  ["loadEvents", "events loader"],
  ["loadLlmRuns", "LLM loader"],
  ["loadFoodSearch", "food search loader"],
  ["loadTrace", "trace loader"],
  ["admin/auth/login", "admin login endpoint"],
  ["admin/telemetry/overview", "overview endpoint"],
  ["admin/telemetry/events", "events endpoint"],
  ["admin/telemetry/llm-runs", "llm-runs endpoint"],
  ["admin/telemetry/food-search", "food-search endpoint"],
  ["admin/telemetry/traces/", "traces endpoint"],
  ["Bearer ", "Authorization header construction"],
  ["invalid_admin_credentials", "handles invalid admin credentials"],
  ["admin_panel_disabled", "handles disabled admin auth"],
];

for (const [snippet, label] of requiredAppFeatures) {
  if (!app.includes(snippet)) {
    fail(`app.js missing ${label}: ${snippet}`);
  } else {
    console.log(`✓ app.js · ${label}`);
  }
}

if (process.exitCode) {
  console.error("\nAdmin panel validation failed.");
} else {
  console.log("\nAdmin panel validation passed.");
}
