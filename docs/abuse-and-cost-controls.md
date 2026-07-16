# Abuse and provider-cost controls

The backend applies a small in-memory protection layer before authentication,
email delivery, LLM, or STT work begins. It intentionally has no Redis or
subscription-plan logic for the MVP.

## Default policies

| Bucket | Default |
| --- | --- |
| Registration, login, confirmation and password recovery | 10 requests per 60 seconds per client IP |
| Confirmation and password-reset email attempts | 3 requests per 3,600 seconds per normalized recipient |
| LLM and STT endpoint operations | 60 requests per 3,600 seconds per user |
| Shared-network safety net | 600 LLM/STT requests per 3,600 seconds per IP |
| Global safety net | 6,000 LLM/STT requests per 3,600 seconds |
| Concurrent LLM/STT work | 2 per user and 50 globally |

The cost bucket covers agent runs and chat, audio chat, standalone STT, voice
meal runs, usual-food and usual-meal drafts, and the equivalent dynamic draft
action routes. It does not charge deterministic CRUD such as meal correction,
commit, or deletion.

Every accepted endpoint request spends one combined LLM/STT unit, including a
request that later fails validation or at a provider. A user-initiated retry is
a new unit. Internal provider iterations are represented in provider telemetry
but do not spend extra endpoint quota. A request rejected for rate or
concurrency does not spend any other bucket and cannot reach the provider.
Concurrency is released after a normal response, an exception, SSE completion,
or client stream cancellation.

## Response and operations

Rejections return HTTP `429`, a `Retry-After` header in seconds, and the stable
`rate_limit_exceeded` error contract. Public responses never expose the bucket,
recipient, IP, user, or current counter.

Set `RATE_LIMIT_COST_OPERATIONS_ENABLED=false` and restart the active backend to
pause all protected provider work. Each admission, release, threshold alert,
and block is written as structured `abuse.*` logging with only keyed, truncated
identifier hashes. Existing provider telemetry remains the source of actual cost;
blocked events report avoided provider calls.

All thresholds and windows are environment variables documented in
`.env.example`. A value of `0` disables only the loose cost-IP, cost-global, or
global-concurrency safety net. Core per-user, auth, email, and user-concurrency
limits must remain positive.

Expired windows are pruned opportunistically, and `RATE_LIMIT_MAX_BUCKETS`
(100,000 by default) is a hard cardinality bound. If active unique identities
fill it, new buckets fail closed with the same public `429`; existing buckets
continue enforcing their current quota. Multi-bucket cost admission reserves
capacity atomically, so a rejected operation cannot partially spend quota.

## IP trust and deployment limits

Direct/local traffic ignores forwarded IP headers and uses the official
`@hono/node-server` connection-info adapter. Production explicitly trusts
`X-Real-IP` because the backend ports bind only to loopback and Nginx overwrites
that header; Nginx also discards client-supplied forwarding chains.

Counters are local to one backend process and reset on restart or deployment.
This matches the current blue/green setup because Nginx sends traffic to one
active slot. Before routing traffic to several backend replicas at once, move
these counters to shared atomic storage so the configured thresholds remain
global.
