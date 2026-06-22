import { buildToolContentForModel, ultraCompactToolContent } from "../src/agent/toolContent.js";

const candidates = Array.from({ length: 20 }, (_, index) => ({
  name: `Candidate ${index + 1}`,
  quantity: 100,
  unit: "g",
  calories: 180 + index,
  proteinGrams: 6,
  carbsGrams: 28,
  fatGrams: 3,
  source: "database",
  originalText: "bread",
  canonicalName: `candidate ${index + 1}`,
  externalSource: "test",
  externalId: `candidate-${index + 1}`,
  confidence: 0.6,
  needsReview: true,
  sourceUrl: `https://example.com/foods/${index + 1}`,
  license: "verbose license text",
  displayDetails: ["detail one", "detail two", "detail three"],
  rank: index + 1,
  matchScore: 0.6,
}));

const mappedResult = {
  kind: "nutrition_search",
  message: "I found matching nutrition items.",
  items: candidates,
  candidateGroups: [{ candidates }],
  options: [{ candidates }],
};

const rawOutput = {
  items: candidates,
  candidates: [{ candidates }],
  candidateGroups: [{ candidates }],
};

const legacy = JSON.stringify({
  actionId: "search_nutrition_database",
  input: { query: "bread" },
  result: mappedResult,
  rawOutput,
});
const built = buildToolContentForModel({
  actionId: "search_nutrition_database",
  actionCallId: "measure-search-1",
  toolInput: { query: "bread" },
  mappedResult,
  rawOutput,
  threshold: 0.75,
});
const ultra = ultraCompactToolContent(built.modelContent, {
  serializerVersion: built.serializerVersion,
});
const oldMetadata = JSON.stringify({
  candidateRegistry: built.candidateRegistry,
  serializerVersion: built.serializerVersion,
});
const newMetadata = JSON.stringify({
  candidateRegistryRef: built.candidateRegistry?.searchRef,
  searchRef: built.candidateRegistry?.searchRef,
  candidateCount: built.candidateRegistry?.candidateCount,
  groupCount: built.candidateRegistry?.groupCount,
  serializerVersion: built.serializerVersion,
});

const rows = [
  measure("legacy_full_json", legacy),
  measure("compact_json_ton", built.modelContent),
  measure("ultra_ton", ultra),
  measure("old_message_metadata", oldMetadata),
  measure("new_message_metadata", newMetadata),
];

for (const row of rows) {
  console.log(
    [
      row.label,
      `chars=${row.chars}`,
      `approx_tokens=${row.approxTokens}`,
      row.label === "compact_json_ton"
        ? `compression_ratio=${built.compressionRatio.toFixed(4)}`
        : undefined,
    ]
      .filter(Boolean)
      .join(" "),
  );
}

console.log(`omitted_paths=${built.omittedPaths.join(",")}`);
console.log(`ton_tables=${JSON.stringify(built.tonTables)}`);

function measure(label: string, value: string): {
  label: string;
  chars: number;
  approxTokens: number;
} {
  return {
    label,
    chars: value.length,
    approxTokens: Math.ceil(value.length / 4),
  };
}
