import { loadConfig } from "../src/config/env.js";
import { pruneLocalRunLogs } from "../src/observability/localRunLogger.js";
import { PostgresRepository } from "../src/repository/postgres.js";

const config = loadConfig();
const repository = new PostgresRepository(config.DATABASE_URL);
let totalPurged = 0;
let totalFailed = 0;
const restoreStartedAt = new Date().toISOString();
try {
  for (let batch = 0; batch < 1000; batch++) {
    const result = await repository.runPrivacyLifecycle({
      batchSize: 100,
      reapplyBefore: restoreStartedAt,
    });
    if (!result.lockAcquired) throw new Error("privacy_lifecycle_lock_unavailable");
    totalPurged += result.purged;
    totalFailed += result.failed;
    if (result.processed === 0 || result.failed > 0) break;
  }
  const logsRemoved = await pruneLocalRunLogs({
    directory: config.AGENT_RUN_LOG_DIR,
    maxAgeDays: 30,
  });
  console.log(JSON.stringify({ ok: totalFailed === 0, totalPurged, totalFailed, logsRemoved }));
  if (totalFailed > 0) process.exitCode = 1;
} finally {
  await repository.close();
}
