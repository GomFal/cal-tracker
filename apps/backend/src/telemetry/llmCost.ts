export type LlmTokenMetrics = {
  promptTokens?: number;
  completionTokens?: number;
  totalTokens?: number;
  reasoningTokens?: number;
  cachedInputTokens?: number;
};

export type LlmCostResult = {
  providerCostAmount?: number;
  estimatedCostAmount?: number;
  costCurrency?: string;
  costSource: "provider" | "estimate" | "unknown";
  inputTokenUnitPrice?: number;
  outputTokenUnitPrice?: number;
  reasoningTokenUnitPrice?: number;
  cachedInputTokenUnitPrice?: number;
  pricingSource?: string;
  pricingVersion?: string;
  pricingEffectiveAt?: string;
  pricingSnapshot: Record<string, unknown>;
};

type PricingCatalog = {
  version?: string;
  source?: string;
  currency?: string;
  models?: Record<string, PricingModel>;
};

type PricingModel = {
  inputPerMillion?: number;
  outputPerMillion?: number;
  reasoningPerMillion?: number;
  cachedInputPerMillion?: number;
  effectiveAt?: string;
};

export function resolveLlmCost(input: {
  rawResponse?: unknown;
  model: string;
  metrics: LlmTokenMetrics;
  pricingJson?: string;
}): LlmCostResult {
  const providerCost = extractProviderCost(input.rawResponse);
  if (providerCost !== undefined) {
    return {
      providerCostAmount: providerCost,
      costCurrency: "USD",
      costSource: "provider",
      pricingSnapshot: { source: "provider_response" },
    };
  }

  const catalog = parsePricingCatalog(input.pricingJson ?? process.env.LLM_PRICING_JSON);
  const pricing = catalog?.models?.[input.model];
  if (!pricing) {
    return {
      costSource: "unknown",
      pricingSnapshot: catalog
        ? { source: catalog.source, version: catalog.version, missingModel: input.model }
        : {},
    };
  }

  const inputPrice = pricing.inputPerMillion;
  const outputPrice = pricing.outputPerMillion;
  const reasoningPrice = pricing.reasoningPerMillion;
  const cachedInputPrice = pricing.cachedInputPerMillion;
  const estimated =
    priceComponent(input.metrics.promptTokens, inputPrice) +
    priceComponent(input.metrics.completionTokens, outputPrice) +
    priceComponent(input.metrics.reasoningTokens, reasoningPrice) +
    priceComponent(input.metrics.cachedInputTokens, cachedInputPrice);

  return {
    estimatedCostAmount: roundCost(estimated),
    costCurrency: catalog.currency ?? "USD",
    costSource: "estimate",
    inputTokenUnitPrice: inputPrice,
    outputTokenUnitPrice: outputPrice,
    reasoningTokenUnitPrice: reasoningPrice,
    cachedInputTokenUnitPrice: cachedInputPrice,
    pricingSource: catalog.source,
    pricingVersion: catalog.version,
    pricingEffectiveAt: pricing.effectiveAt,
    pricingSnapshot: {
      source: catalog.source,
      version: catalog.version,
      model: input.model,
      pricing,
    },
  };
}

function extractProviderCost(rawResponse: unknown): number | undefined {
  if (!isRecord(rawResponse)) return undefined;
  const usage = rawResponse.usage;
  if (!isRecord(usage)) return undefined;
  return firstNumber([
    usage.cost,
    usage.total_cost,
    usage.cost_usd,
    usage.total_cost_usd,
  ]);
}

function firstNumber(values: unknown[]): number | undefined {
  for (const value of values) {
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value === "string" && value.trim() !== "") {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) return parsed;
    }
  }
  return undefined;
}

function parsePricingCatalog(raw: string | undefined): PricingCatalog | undefined {
  if (!raw) return undefined;
  try {
    const parsed = JSON.parse(raw);
    return isRecord(parsed) ? (parsed as PricingCatalog) : undefined;
  } catch {
    return undefined;
  }
}

function priceComponent(tokens: number | undefined, perMillion: number | undefined): number {
  if (!tokens || !perMillion) return 0;
  return (tokens / 1_000_000) * perMillion;
}

function roundCost(value: number): number {
  return Math.round(value * 1_000_000) / 1_000_000;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
