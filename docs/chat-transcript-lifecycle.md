# Chat and transcript lifecycle

## Published MVP policy

| Category | Active-system lifetime | Deletion behavior |
| --- | --- | --- |
| Conversation and messages | Until the user deletes the chat or the account disappears | Hidden immediately; permanently purged in less than 24 hours. No trash. |
| Temporary audio | Only while recording/upload/transcription is active | Mobile files are deleted after success, failure, cancellation, invalid audio, or service disposal. The backend processes uploads in memory and does not write audio files. |
| Transcript and chat-derived diagnostic rows | Same as the owning chat | Purged by conversation, trace, and turn correlation. Admin and user APIs exclude a tombstoned chat immediately. |
| Raw telemetry fields | At most 30 days | Raw text/metadata fields are scrubbed; aggregate counters and safe hashes may remain. Local JSONL run logs rotate after 30 days. |
| Suppression ledger | Durable | Contains only request ID, pseudonymous user UUID, conversation UUID, timestamps, attempts, status, and result code. It has no user FK, so it survives account deletion. A restricted CSV overlay outside PostgreSQL preserves it across an older database restore. |
| Database backups | At most 30 days | Schema dumps older than 30 days are deleted by `backup-postgres-schema.sh`. The backup job also refreshes the external suppression overlay. |

No legal-retention exception is implemented. Any future exception needs a
separate product/legal decision and must not silently bypass the ledger.

## Runtime operation

`DELETE /v1/agent/conversations/:id` returns `202` with `pending`,
`requestedAt`, and the latest `purgeDueAt`. Repeating the request returns the
same owned ledger entry. `GET /v1/agent/conversations/:id/deletion` exposes the
current status only to that user.

The backend starts a non-blocking hourly worker. It processes at most 25 rows,
does not overlap within a process, and PostgreSQL uses a global advisory lock,
`SKIP LOCKED`, and one savepoint per deletion. A failed row records only
`purge_retry_required`; it cannot block the rest of the batch and is retried.

Conversation writes and deletion take the same per-conversation advisory lock.
Database triggers reject message, candidate, transcript, and telemetry inserts
after the tombstone commits. Service-level checks additionally stop provider and
tool work as early as possible.

## Restore runbook (mandatory order)

1. Keep every backend slot stopped or otherwise unreachable. Do not reopen the
   proxy while restore is in progress.
2. Run `restore-postgres-schema.sh <dev|pro> <dump> <backend-image>`. It writes
   a fail-closed marker, stops both environment slots, exports the live ledger
   to `/srv/cal-tracker/privacy-ledger-overlays/`, restores the dump, migrates,
   and merges the overlay with `ON CONFLICT DO NOTHING` so it never replaces a
   ledger entry already present in the restored database.
3. The script then runs `bun dist/scripts/apply-privacy-suppressions.js` with
   the restored schema's `DATABASE_URL` and `DATABASE_SCHEMA`.
4. Require JSON output with `"ok":true` and `"totalFailed":0`. A non-zero exit
   means the service remains closed while the failed ledger rows are inspected
   and the same restore/suppression process is retried. A missing or malformed
   overlay also aborts, and `deploy.sh` refuses to run while the marker exists.
5. Search operationally for sampled suppressed conversation IDs; there must be
   no conversation, message, transcript, action, or telemetry content.
6. Only then run the normal deploy to start a backend slot and reopen the proxy.

The normal deployment script refuses an incomplete restore and reapplies
suppression before starting the next slot.
The pre-restore live export is mandatory. If the source database is unavailable
or the export fails, the script aborts and leaves the marker in place; a
well-formed periodic overlay is only defense in depth and is not proof that the
latest tombstones are present. Off-host/disaster-resilient backup replication
and explicitly verified external overlays are outside this MVP and remain an
operational follow-up.
The command fixes a restore-specific case that the hourly worker cannot infer:
it reapplies already-`purged` ledger rows using a fixed run cutoff, in bounded
batches, while preserving the original request and purge timestamps.

## Verification

The opt-in PostgreSQL integration test performs real inserts/deletes against a
local database and verifies account cascade, trigger guards, restored content,
savepoint isolation, and retry:

```bash
RUN_PRIVACY_POSTGRES_TESTS=1 \
  bun --env-file=apps/backend/.env test \
  apps/backend/src/tests/privacyLifecyclePostgres.test.ts
```

The test only deletes users and rows that it creates and removes its ledger
fixtures afterwards. Run it after applying migrations.
