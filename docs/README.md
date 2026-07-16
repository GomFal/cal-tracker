# Documentation Map

This directory is the planning source of truth until implementation creates executable contracts, migrations, and tests.

## Current Structure Assessment

The current two-file structure is acceptable for pre-implementation planning, but it is not enough by itself once implementation starts.

Current authoritative files:

| File | Owns | Does not own |
| --- | --- | --- |
| `app-description.md` | Product vision, MVP scope, system architecture, action-layer rules, Flutter/backend boundaries, mobile OS adapter strategy, API surface, scoped decisions, testing/development order. | Detailed SQL schema, vector index design, backup mechanics. |
| `db-vector-architecture.md` | PostgreSQL/pgvector architecture, tables, field requirements, vector retrieval, migrations, local/production DB deployment, backup/restore rules. | Product UX, action semantics beyond DB effects, Flutter UI architecture. |
| `voice-agent-gap-analysis.md` | Current implementation gaps for voice input, STT, OpenRouter agent orchestration, and the technical slices needed to align the code with the MVP plan. | General product scope, database table ownership, production deployment. |
| `spec-usual-foods-flow.md` | Task specification for usual ingredients inside the usual meals area, including manual CRUD, AI-assisted drafts, search priority, backend contracts, Flutter UI, and tests. | General nutrition source strategy outside usual foods, unrelated dashboard or onboarding UX. |
| `food-data-quality-cleanse-findings.md` | Food corpus quality findings, search eligibility meaning, invalid nutrition/duplicate/suspicious row slices, and operational use of `food-quality`. | Runtime ranking strategy, normalized search query plans. |
| `food-data-quality-normalized-search-plan.md` | Implemented PostgreSQL normalized food search runbook: quality/normalization tables, scripts, env flags, rollout sequence, and runtime search behavior. | General product nutrition-source priority outside normalized PostgreSQL search. |
| `food-search-benchmark-acceptance-plan.md` | Reusable food search benchmark and primary-position validation commands, metrics, acceptance gates, and profiling workflow. | Data normalization rules and production rollout sequencing. |
| `production-host-access-hardening.md` | Fail-safe migration from direct root/password SSH to a nominal key-only operator, fail2ban, explicit UFW policy, validation and basic console recovery. | GitHub Actions deployment-user migration, VPN access, or long-term emergency-key custody. |
| `trusted-production-deployments.md` | Pinned SSH host identity, dedicated deployment account, immutable backend image references and release traceability. | GitHub environment approvals, signed tags, or deployment execution. |
| `container-runtime-hardening.md` | Backend container privilege, capability and resource policy; isolated runtime smoke and operational tuning. | Read-only filesystems or additional PostgreSQL hardening. |
| `software-supply-chain-controls.md` | Bun and production base-image versions, frozen lockfile policy and the MVP update procedure. | SBOM, attestations, container signing, new scanners or commit-pinned Actions. |
| `runtime-dependency-remediation.md` | Runtime dependency security updates, audit evidence and temporary non-applicable development-tool findings. | A general vulnerability-management SLA or automatic dependency updates. |
| `trusted-production-apk-signing.md` | Android production signing identity, protected CI secrets, certificate verification, offline custody and recovery/rotation procedure. | Play Store migration or in-app updater redesign. |

This split is intentional:

```text
app-description.md = what the app must do and which system boundaries matter
db-vector-architecture.md = how persistent data and vector memory must work
```

The risk is that `app-description.md` is broad. If it grows much further, coding agents will need a more modular docs tree to avoid missing details or relying on stale sections.

## Reading Order for Coding Agents

For any task:

```text
1. Read this README.
2. Read the relevant section of app-description.md.
3. Read db-vector-architecture.md only if the task touches persistence, memory, search, migrations, auth/session storage, audit, or deployment.
4. Prefer executable contracts, migrations, and tests over prose once those files exist.
```

Task-specific reading:

| Task type | Required docs |
| --- | --- |
| Product behavior or MVP scope | `app-description.md` -> Project Summary, MVP Scope, Non-Negotiable Principle |
| Backend action implementation | `app-description.md` -> Canonical Action Layer, Initial Canonical Actions, Confirmation Policy, Permissions |
| Internal agent work | `app-description.md` -> Internal Agent Requirements, Safety Rules, Action Layer |
| Voice input, STT, or OpenRouter agent work | `voice-agent-gap-analysis.md`; then `app-description.md` -> Internal Agent Requirements, Safety Rules, Action Layer |
| Usual ingredients, usual meals tab, or user-owned food priority | `spec-usual-foods-flow.md`; then `app-description.md` -> Nutrition Source Priority and Canonical Action Layer |
| Flutter UI work | `app-description.md` -> Flutter Architecture, API Requirements, Confirmation Policy |
| Android AppFunctions or iOS App Intents | `app-description.md` -> Mobile OS Agent Integrations, Target Launch Platforms |
| Database schema/migrations | `db-vector-architecture.md` -> Core Tables, Table Responsibilities, Required Constraints and Indexes |
| Vector memory/retrieval | `db-vector-architecture.md` -> Retrieval Flow, User-Scoped Vector Query, Retrieval Ranking, Memory Creation and Update Rules |
| Production deployment | `db-vector-architecture.md` -> Production Deployment, Backup and Restore; `trusted-production-deployments.md`; `production-host-access-hardening.md` when changing administrative SSH or host firewall access |
| Auth/session storage | `app-description.md` -> Authentication decision; `db-vector-architecture.md` -> users, user_credentials, auth_sessions, password_reset_tokens |
| Food data quality cleanup | `food-data-quality-cleanse-findings.md`; then `food-data-quality-normalized-search-plan.md` -> Operational Commands |
| Normalized PostgreSQL food search | `food-data-quality-normalized-search-plan.md`; then `db-vector-architecture.md` if migrations or schema ownership are touched |
| Food search ranking or index optimization | `food-data-quality-normalized-search-plan.md` -> Runtime Search Behavior; then `food-search-benchmark-acceptance-plan.md` |
| Food search benchmark or acceptance validation | `food-search-benchmark-acceptance-plan.md` |
| Meal proposal food-resolution regressions | `food-search-benchmark-acceptance-plan.md`; then `app-description.md` -> Canonical Action Layer |

## Authority and Conflict Rules

If documents disagree:

* `app-description.md` wins for product behavior, action semantics, UI/backend boundaries, and scoped architecture decisions.
* `db-vector-architecture.md` wins for database tables, fields, indexes, vector search, migrations, backups, and deployment database behavior.
* Generated schemas, migrations, and tests win over prose after implementation exists.
* When a code change changes behavior, update the owning doc in the same task.

Do not copy business logic into platform adapters or database scripts just because a doc example shows a flow. The backend action executor remains the implementation authority for app behavior.

## Current Closed Decisions

Closed decisions currently live in `app-description.md` under `Scoped Architecture Decisions`:

```text
Authentication: custom backend-owned sessions.
Target launch platforms: Android and iOS mobile only.
Minimum OS versions: Android 10/API 29 for core app, iOS 17.0 for core app.
OS-agent spikes: Android AppFunctions on API 36+, iOS App Intents on iOS 17+.
Nutrition source priority: user data first, USDA FoodData Central for generic single ingredients and portion metadata, Open Food Facts for branded/barcode packaged products, then explicit user-provided custom nutrition. LLM-only and unprovenanced seed nutrition values are not authoritative.
Production database: self-hosted PostgreSQL + pgvector in Docker on the VPS.
Embeddings: disabled by default while costs are evaluated; when enabled, OpenRouter `baai/bge-m3` with 1024-dimensional vectors.
Trusted auto-commit: included in MVP, off by default, safe familiar templates only.
```

`app-description.md` also contains the current Open Decisions section. It should remain explicit even when there are no blocking open decisions.

## When to Split the Docs Further

Do not split files just to make the tree look complete. Split when a section becomes an implementation surface that coding agents will edit or reference independently.

Recommended future structure:

```text
docs/
  README.md
  app-description.md
  db-vector-architecture.md

  architecture/
    action-layer.md
    backend-agent.md
    mobile-os-integrations.md
    confirmation-policy.md

  api/
    actions.md
    rest-api.md

  mobile/
    flutter-architecture.md
    app-intents-appfunctions.md

  operations/
    deployment.md
    backups-restore.md

  decisions/
    0001-custom-backend-auth.md
    0002-self-hosted-postgres.md
    0003-trusted-auto-commit.md
```

Split triggers:

* Action definitions start being generated from code.
* API contracts become large enough to need their own changelog.
* Mobile OS adapter implementation begins.
* Deployment scripts are added.
* Multiple developers or agents edit the same large document frequently.
* A decision needs history, alternatives, or reversal criteria.

## Documentation Rules

* Keep docs concise enough that an agent can find the relevant rule quickly.
* Keep closed decisions separate from open questions.
* Prefer tables for ownership, priority, and compatibility rules.
* Prefer executable examples only when they define a contract or migration-relevant behavior.
* Do not duplicate long schemas across multiple docs. Link to the owning doc instead.
* When implementation starts, keep prose docs aligned with code-generated schemas and migrations.
