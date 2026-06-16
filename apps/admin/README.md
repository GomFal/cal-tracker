# BetterCalories Admin · Telemetry

Static, dependency-free admin panel for inspecting the local/dev telemetry
emitted by the BetterCalories backend.

This panel is the first slice of the telemetry work described in
[`specs/admin-telemetry-panel-plan.md`](../../specs/admin-telemetry-panel-plan.md).
It ships the static UI for the backend admin telemetry endpoints.

## Features

- Configurable **API base URL** persisted in `localStorage`
  (`bc.admin.apiBase`).
- **Admin sign in** with username + deployment password against
  `POST /v1/admin/auth/login`. The returned admin access token is kept
  in `sessionStorage` (`bc.admin.apiToken`) and is cleared on sign out
  or when the browser tab closes.
- **Overview** cards: events, errors, warnings, LLM runs, food searches,
  zero-result searches.
- **Events** table with severity, event type, trace id, user id, route,
  duration, and error filters.
- **LLM runs** table with model, result kind, selected/executed tool,
  timings, token usage, and provider-error / empty-tool-call flags.
- **Food search** table with query (truncated), path, result count,
  top score, top source, and zero-result / low-confidence / barcode flags.
- **Trace lookup** that calls `GET /v1/admin/telemetry/traces/:traceId`
  and renders the events, LLM runs, and food search events for that
  trace side by side.
- Click on a trace id to copy it to the clipboard.
- Tab navigation (and `1`–`5` hotkeys to jump between views).
- Visible error states; never silently fails.

## Endpoints consumed

```text
POST /v1/admin/auth/login
GET  /v1/admin/telemetry/overview?from=&to=
GET  /v1/admin/telemetry/events?limit=&severity=&eventType=&traceId=&userId=
GET  /v1/admin/telemetry/llm-runs?limit=&resultKind=&selectedTool=&traceId=&userId=
GET  /v1/admin/telemetry/food-search?limit=&zeroResults=&lowConfidence=&traceId=&userId=
GET  /v1/admin/telemetry/traces/:traceId
```

Telemetry requests use `Authorization: Bearer <admin-token>` after a
successful admin login. The token is only sent to the configured API
base URL and never leaves the browser.

## Backend admin auth configuration

The backend admin login is configured by deployment environment variables:

```env
ADMIN_PANEL_USERNAME=admin
ADMIN_PANEL_PASSWORD_HASH=$argon2id$v=19$m=...
ADMIN_PANEL_TOKEN_SECRET=replace-with-a-random-secret-at-least-32-chars
ADMIN_PANEL_TOKEN_TTL_SECONDS=1800
```

Generate the password hash locally, then store only the hash in the
deployment env/secrets file. Keep the plaintext password in a password
manager, not in the repo or server env:

```bash
cd apps/backend
printf '%s' "$LONG_ADMIN_PASSWORD" | bun run admin:hash-password
```

If any of the required `ADMIN_PANEL_*` auth values are missing, admin
login fails closed and the telemetry endpoints remain inaccessible.

## Local serving

The panel is plain static files; any static server works. The repo ships
a helper script that wraps Python's built-in server:

```bash
bun run admin:serve
# → http://localhost:4174
```

Equivalent commands without the helper:

```bash
# from repo root
python3 -m http.server 4174 --directory apps/admin
# or
npx --yes serve -l 4174 apps/admin
# or
caddy file-server --listen :4174 --root apps/admin
```

Then open <http://localhost:4174>.

### Pointing at the local backend

The default API base URL is `http://localhost:3000`, which matches the
local backend on the host. If you are running the panel from a phone or
emulator, set the API base URL to the address that the backend is
reachable at, for example:

- Android emulator → `http://10.0.2.2:3000`
- Dev environment → `https://dev-api.bettercalories.app`
- Production → `https://api.bettercalories.app`

Enter the admin username and deployment password, then click **Sign in**.
The API base URL is saved in `localStorage`; the admin token is saved only
in `sessionStorage` for the current tab. Use **Sign out** to clear it.

## Validating the panel

A small static validator checks that the panel files are in place and
that the HTML references the expected scripts and styles:

```bash
bun run admin:validate
```

It does not start a browser. For visual verification, open the panel in
a browser (or use the Marionette MCP during development).

## Smoke flow

After starting the backend and a local Postgres with telemetry data:

1. `bun run admin:serve` and open the panel.
2. Configure the API base URL.
3. Enter the admin username and deployment password, then **Sign in**.
4. The status pill should switch to `success` and the overview cards
   should fill after the first request succeeds.
5. Switch through the tabs. The **Raw response** disclosure at the
   bottom of the overview and trace views shows the JSON returned by
   the backend; use it to confirm the wire format.
6. Use the **Trace lookup** tab with a trace id from an event row to
   confirm that the trace view aggregates the matching events, LLM
   runs, and food search entries.
7. Click **Sign out** and confirm the next telemetry request requires a
   new login.

## Files

```text
apps/admin/
├── index.html       # Static entry point
├── styles.css       # Styles (no external assets)
├── config.js        # Defaults: API base URL, storage keys, endpoints
├── app.js           # Vanilla JS application logic
├── validate.mjs     # Static file validator
└── README.md        # This file
```

## Security & privacy notes

- The admin access token is stored in `sessionStorage`, scoped to one
  browser tab. It is only sent to the configured API base URL.
- The deployment password is never stored by the panel.
- Use **Sign out** to remove the token when you are done.
- The panel never sends telemetry of its own to any third party.
- Only the data returned by the admin endpoints is rendered. No raw
  audio or full OpenRouter request/response payloads are exposed here.
