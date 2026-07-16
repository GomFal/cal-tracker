# Runtime Dependency Remediation

This record captures the MVP security update performed on 2026-07-16. The approved scanner is `bun audit` executed with the repository-pinned Bun 1.3.13 and the committed `bun.lock`.

## Remediation result

The initial lockfile reported 14 advisories: 3 high, 10 moderate and 1 low. The updated lockfile reports 2 advisories: 0 high, 1 moderate and 1 low.

| Package | Previous resolution | Corrected resolution | Result |
| --- | --- | --- | --- |
| `drizzle-orm` | `0.44.7` | `0.45.2` | Fixes high-severity identifier SQL injection advisory `GHSA-gpj5-g38j-94v9`. |
| `hono` | `4.12.18` | `4.12.30` | Fixes `GHSA-88fw-hqm2-52qc` and the eight moderate Hono advisories reported by the initial audit. |
| `vitest` / `vite` | `4.1.5` / `8.0.11` | `4.1.10` / `8.1.5` | Fixes high-severity Vite path traversal advisory `GHSA-fx2h-pf6j-xcff` and the related Windows launch-editor advisory. |

`vite` is constrained to `8.1.5` with the root override because its broad transitive range otherwise allowed Bun to preserve the vulnerable `8.0.11` lock resolution. The override is exact and reviewable; Vite belongs to the test dependency graph and is not imported by the production backend entrypoint.

## Temporary scanner findings

These findings are retained because forcing incompatible transitive versions would expand the MVP change and neither vulnerable operation is used by the deployed backend.

| Advisory | Severity and path | Applicability and compensation | Owner | Review by |
| --- | --- | --- | --- | --- |
| `GHSA-67mh-4wv8-2f99` | Moderate; `drizzle-kit -> @esbuild-kit/esm-loader -> @esbuild-kit/core-utils -> esbuild@0.18.20` | Not applicable to the production execution path: the dependency is reachable only from the `drizzle-kit` development CLI; the deployed entrypoint imports neither package and never starts the affected esbuild development server. Re-evaluate when `drizzle-kit` removes the legacy loader. | Backend maintainer | 2026-08-16 |
| `GHSA-g7r4-m6w7-qqqr` | Low; `tsx`/`vite -> esbuild@0.27.7` | Not applicable to deployed Linux or Linux CI: exploitation requires a Windows esbuild development server and a local attacker. No development server is exposed by production. Re-evaluate when `tsx` accepts esbuild `0.28.1` or newer. | Backend maintainer | 2026-08-16 |

## Reproduction

Use the pinned toolchain and the frozen lockfile:

```bash
bun install --frozen-lockfile
bun run security:audit:runtime
bun run typecheck
bun run test:backend
bun run build
```

The audit validator fails on any high or critical advisory while reporting the lower-severity count for comparison with the exceptions above. A raw evidence snapshot can be obtained with `bun audit --json`; Bun exits non-zero for the documented lower-severity findings, which is why the validator performs severity-aware parsing.

## Compatibility evidence

The updated lockfile was validated with native Bun 1.3.13:

- frozen install, typecheck and workspace build passed;
- the complete backend suite passed: 34 files and 278 tests;
- the focused auth, Hono HTTP/SSE, provider streaming and Drizzle query/guard selection passed: 5 files and 25 tests;
- the `@hono/node-server/conninfo` `getConnInfo` export remained available;
- all legacy and Drizzle migrations applied to a fresh PostgreSQL 16 + pgvector database and a second run was idempotent (20 legacy and 20 Drizzle records);
- the production Docker image built from the frozen lockfile, answered `/v1/health`, connected to the migrated database and returned the expected `401 invalid_credentials` contract for a missing user.
