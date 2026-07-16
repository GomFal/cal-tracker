import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const policySource = readFileSync(new URL("./origin-policy.js", import.meta.url), "utf8");
const context = vm.createContext({ URL });
vm.runInContext(policySource, context, { filename: "origin-policy.js" });
const policy = context.AdminOriginPolicy;

assert.deepEqual(Array.from(policy.approvedApiOrigins), [
  "http://localhost:3000",
  "https://dev-api.bettercalories.app",
  "https://api.bettercalories.app",
]);

for (const origin of policy.approvedApiOrigins) {
  assert.equal(policy.normalizeApiBase(`${origin}/`), origin);
  assert.equal(
    policy.resolveApiUrl(origin, "/v1/admin/telemetry/overview"),
    `${origin}/v1/admin/telemetry/overview`,
  );
  const headers = policy.createAuthorizedHeaders(
    origin,
    `${origin}/v1/admin/telemetry/overview?status=error`,
    "admin-token",
    { Accept: "application/json" },
  );
  assert.equal(headers.Authorization, "Bearer admin-token");
  assert.equal(headers.Accept, "application/json");
}

for (const rejected of [
  "https://attacker.example",
  "http://dev-api.bettercalories.app",
  "https://api.bettercalories.app.attacker.example",
  "https://api.bettercalories.app/v1",
  "https://user:password@api.bettercalories.app",
  "http://127.0.0.1:3000",
  "http://localhost:4174",
]) {
  assert.throws(() => policy.normalizeApiBase(rejected), { code: "unapproved_api_origin" });
}

assert.throws(
  () => policy.resolveApiUrl("https://api.bettercalories.app", "https://attacker.example/collect"),
  { code: "unapproved_api_origin" },
);
assert.throws(
  () => policy.resolveApiUrl("https://api.bettercalories.app", "//attacker.example/collect"),
  { code: "unapproved_api_origin" },
);
assert.throws(
  () => policy.createAuthorizedHeaders(
    "https://api.bettercalories.app",
    "https://attacker.example/collect",
    "admin-token",
  ),
  { code: "unapproved_api_origin" },
);
assert.throws(
  () => policy.createAuthorizedHeaders(
    "https://dev-api.bettercalories.app",
    "https://api.bettercalories.app/v1/admin/telemetry/overview",
    "admin-token",
  ),
  { code: "unapproved_api_origin" },
);

assert.equal(
  policy.defaultApiBaseFor({ hostname: "dev-api.bettercalories.app" }),
  "https://dev-api.bettercalories.app",
);
assert.equal(
  policy.defaultApiBaseFor({ hostname: "api.bettercalories.app" }),
  "https://api.bettercalories.app",
);
assert.equal(policy.defaultApiBaseFor({ hostname: "localhost" }), "http://localhost:3000");

console.log("Admin origin policy tests passed.");
