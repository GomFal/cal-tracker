import { describe, expect, it } from "vitest";
import { loadConfig } from "../config/env.js";

describe("config", () => {
  it("defaults OpenRouter provider routing to aggressive latency preferences", () => {
    const config = loadConfig({ NODE_ENV: "test" } as NodeJS.ProcessEnv);

    expect(config.OPENROUTER_PROVIDER_SORT).toBe("latency");
    expect(config.OPENROUTER_PROVIDER_MAX_LATENCY_P50).toBe(0.6);
    expect(config.OPENROUTER_PROVIDER_MAX_LATENCY_P90).toBe(1.5);
    expect(config.OPENROUTER_PROVIDER_MAX_LATENCY_P99).toBe(3);
    expect(config.OPENROUTER_PROVIDER_MIN_THROUGHPUT_P50).toBe(80);
    expect(config.OPENROUTER_PROVIDER_MIN_THROUGHPUT_P90).toBe(40);
    expect(config.OPENROUTER_PROVIDER_REQUIRE_PARAMETERS).toBe(false);
    expect(config.OPENROUTER_PROVIDER_ALLOW_FALLBACKS).toBe(true);
    expect(config.EMBEDDINGS_ENABLED).toBe(false);
    expect(config.EMBEDDING_PROVIDER).toBe("openrouter");
    expect(config.EMBEDDING_MODEL).toBe("baai/bge-m3");
    expect(config.EMBEDDING_DIMENSIONS).toBe(1024);
  });

  it("allows OpenRouter provider routing overrides from env", () => {
    const config = loadConfig({
      NODE_ENV: "test",
      OPENROUTER_PROVIDER_SORT: "throughput",
      OPENROUTER_PROVIDER_MAX_LATENCY_P50: "0.4",
      OPENROUTER_PROVIDER_MAX_LATENCY_P90: "1.2",
      OPENROUTER_PROVIDER_MAX_LATENCY_P99: "2.5",
      OPENROUTER_PROVIDER_MIN_THROUGHPUT_P50: "120",
      OPENROUTER_PROVIDER_MIN_THROUGHPUT_P90: "60",
      OPENROUTER_PROVIDER_REQUIRE_PARAMETERS: "true",
      OPENROUTER_PROVIDER_ALLOW_FALLBACKS: "false",
    } as NodeJS.ProcessEnv);

    expect(config.OPENROUTER_PROVIDER_SORT).toBe("throughput");
    expect(config.OPENROUTER_PROVIDER_MAX_LATENCY_P50).toBe(0.4);
    expect(config.OPENROUTER_PROVIDER_MAX_LATENCY_P90).toBe(1.2);
    expect(config.OPENROUTER_PROVIDER_MAX_LATENCY_P99).toBe(2.5);
    expect(config.OPENROUTER_PROVIDER_MIN_THROUGHPUT_P50).toBe(120);
    expect(config.OPENROUTER_PROVIDER_MIN_THROUGHPUT_P90).toBe(60);
    expect(config.OPENROUTER_PROVIDER_REQUIRE_PARAMETERS).toBe(true);
    expect(config.OPENROUTER_PROVIDER_ALLOW_FALLBACKS).toBe(false);
  });
});
