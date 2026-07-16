import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(new URL("../..", import.meta.url).pathname);
const read = (path) => readFileSync(resolve(root, path), "utf8");
const securityHeaders = read("infra/deploy/nginx/security-headers.conf");
const apiConfig = read("infra/deploy/nginx/api.bettercalories.app.conf");
const webConfig = read("infra/deploy/nginx/bettercalories.app.conf");
const bootstrap = read("infra/deploy/bootstrap-server.sh");
const landing = read("apps/landing/index.html");

const requiredHeaders = [
  "Strict-Transport-Security",
  "Content-Security-Policy",
  "X-Content-Type-Options",
  "X-Frame-Options",
  "Referrer-Policy",
  "Permissions-Policy",
];
for (const header of requiredHeaders) {
  assert.match(
    securityHeaders,
    new RegExp(`add_header\\s+${header}\\s+[^\\n]+\\s+always;`),
    `${header} must be added with "always" so Nginx error responses are covered`,
  );
}

const hsts = securityHeaders.match(/add_header\s+Strict-Transport-Security\s+"([^"]+)"/i)?.[1];
assert.equal(hsts, "max-age=31536000");
assert.doesNotMatch(hsts, /includeSubDomains|preload/i);

const csp = securityHeaders.match(/add_header\s+Content-Security-Policy\s+"([^"]+)"/i)?.[1];
assert.ok(csp, "CSP must be configured");
assert.match(csp, /frame-ancestors 'none'/);
assert.match(csp, /object-src 'none'/);
assert.match(csp, /script-src 'self'/);
assert.doesNotMatch(csp, /'unsafe-eval'|'unsafe-inline'/);
assert.match(csp, /https:\/\/api\.bettercalories\.app/);
assert.match(csp, /https:\/\/dev-api\.bettercalories\.app/);
assert.match(csp, /http:\/\/localhost:3000/);

const jsonLd = landing.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)?.[1];
assert.ok(jsonLd, "landing JSON-LD block must exist");
const jsonLdHash = createHash("sha256").update(jsonLd).digest("base64");
assert.match(csp, new RegExp(`'sha256-${jsonLdHash.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}'`));

function blocks(source, directive) {
  const results = [];
  const startPattern = new RegExp(`\\b${directive}\\b[^\\n{]*\\{`, "g");
  for (const match of source.matchAll(startPattern)) {
    const start = match.index;
    const open = source.indexOf("{", start);
    let depth = 0;
    let quote = null;
    for (let i = open; i < source.length; i += 1) {
      const char = source[i];
      if (quote) {
        if (char === quote && source[i - 1] !== "\\") quote = null;
        continue;
      }
      if (char === '"' || char === "'") {
        quote = char;
      } else if (char === "{") {
        depth += 1;
      } else if (char === "}") {
        depth -= 1;
        if (depth === 0) {
          results.push(source.slice(start, i + 1));
          break;
        }
      }
    }
  }
  return results;
}

const configs = [apiConfig, webConfig];
const tlsServers = configs.flatMap((config) => blocks(config, "server"))
  .filter((server) => /listen\s+(?:\[::\]:)?443\s+ssl/.test(server));
assert.equal(tlsServers.length, 4, "dev, prod, apex and www HTTPS servers must be covered");
for (const server of tlsServers) {
  assert.match(server, /include \/etc\/nginx\/snippets\/cal-tracker-security-headers\.conf;/);
  assert.match(server, /server_tokens off;/);
}
assert.ok(tlsServers.some((server) => /server_name api\.bettercalories\.app;/.test(server)));
assert.ok(tlsServers.some((server) => /server_name dev-api\.bettercalories\.app;/.test(server)));

for (const location of blocks(apiConfig, "location").filter((block) => /add_header\s+/.test(block))) {
  assert.match(
    location,
    /include \/etc\/nginx\/snippets\/cal-tracker-security-headers\.conf;/,
    "locations with their own add_header must re-include security headers to preserve Nginx inheritance",
  );
}

assert.match(
  bootstrap,
  /cp nginx\/security-headers\.conf \/etc\/nginx\/snippets\/cal-tracker-security-headers\.conf/,
);
assert.ok(
  bootstrap.indexOf("cp nginx/security-headers.conf") < bootstrap.lastIndexOf("nginx -t"),
  "the security header snippet must be installed before final Nginx validation",
);

console.log("Nginx web security policy tests passed for dev, prod and error responses.");
