import type { AppRepository, PrivacyLifecycleResult } from "../repository/types.js";
import { pruneLocalRunLogs } from "../observability/localRunLogger.js";

const DEFAULT_INTERVAL_MS = 60 * 60 * 1000;

export type PrivacyLifecycleWorker = { stop(): void; runNow(): Promise<PrivacyLifecycleResult | undefined> };

export function startPrivacyLifecycleWorker(input: {
  repository: AppRepository;
  runLogDirectory?: string;
  intervalMs?: number;
  batchSize?: number;
}): PrivacyLifecycleWorker {
  let running = false;
  let stopped = false;
  const runNow = async () => {
    if (running || stopped) return undefined;
    running = true;
    try {
      const result = await input.repository.runPrivacyLifecycle({ batchSize: input.batchSize ?? 25 });
      if (input.runLogDirectory) {
        await pruneLocalRunLogs({ directory: input.runLogDirectory, maxAgeDays: 30 });
      }
      return result;
    } catch (error) {
      console.warn("privacy.lifecycle.failed", {
        errorClass: error instanceof Error ? error.name : typeof error,
      });
      return undefined;
    } finally {
      running = false;
    }
  };
  const timer = setInterval(() => void runNow(), input.intervalMs ?? DEFAULT_INTERVAL_MS);
  timer.unref();
  queueMicrotask(() => void runNow());
  return {
    stop() {
      stopped = true;
      clearInterval(timer);
    },
    runNow,
  };
}
