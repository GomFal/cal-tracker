import type { MealItem } from "@cal-tracker/contracts";
import type { AgentConversationMessageRecord } from "../repository/types.js";

export const MODEL_FACING_SERIALIZER_VERSION = "hybrid-ton-v1";

export type ModelFacingRepresentation =
  | "full_json"
  | "compact_json_ton"
  | "ultra_ton";

export type AgentChatCandidateSelection = {
  searchRef?: string;
  candidateRef?: string;
  groupIndex?: number;
  candidateIndex?: number;
};

export type AgentCandidateSelectionState = {
  status: "candidate_preview";
  searchRef: string;
  candidateCount: number;
  groupCount: number;
  threshold: number;
  topConfidence?: number;
};

export type CandidateRegistryMetadata = {
  kind: "agent_candidate_registry";
  searchRef: string;
  actionId: string;
  actionCallId?: string;
  threshold: number;
  candidateCount: number;
  groupCount: number;
  groups: Array<{
    groupIndex: number;
    mention?: unknown;
    candidates: Array<{
      candidateRef: string;
      candidateIndex: number;
      item: MealItem;
    }>;
  }>;
};

export type ModelFacingTonTable = {
  path: string;
  rows: number;
  shown: number;
  columns: string[];
};

export type ToolContentBuildResult = {
  contentValue: Record<string, unknown>;
  modelContent: string;
  representation: ModelFacingRepresentation;
  serializerVersion: string;
  candidateRegistry?: CandidateRegistryMetadata;
  selectionState?: AgentCandidateSelectionState;
  rawContentChars: number;
  rawContentApproxTokens: number;
  modelContentChars: number;
  modelContentApproxTokens: number;
  compressionRatio: number;
  omittedPaths: string[];
  preservedPaths: string[];
  tonTables: ModelFacingTonTable[];
};

export type ModelFacingSerializationInput = {
  actionId: string;
  actionCallId?: string;
  toolInput: unknown;
  mappedResult: Record<string, unknown>;
  rawOutput: unknown;
  threshold: number;
  mode?: ModelFacingRepresentation;
  context?: {
    age?: "current_turn" | "recent_history" | "older_history";
    maxRows?: number;
  };
};

const DEFAULT_TABLE_MAX_ROWS = 10;

export function serializeForModel(
  input: ModelFacingSerializationInput,
): ToolContentBuildResult {
  const rawContentValue = {
    actionId: input.actionId,
    input: input.toolInput,
    result: input.mappedResult,
    rawOutput: input.rawOutput,
  };
  const rawContentChars = JSON.stringify(rawContentValue).length;
  const candidateRegistry = buildCandidateRegistry(input);
  const selectionState = candidateRegistry
    ? selectionStateForRegistry(candidateRegistry)
    : undefined;
  const tonTables: ModelFacingTonTable[] = [];
  const omittedPaths: string[] = ["rawOutput"];
  const preservedPaths: string[] = [
    "actionId",
    "tool",
    "input",
    "result.kind",
    "result.message",
  ];
  const result = compactMappedResult({
    mappedResult: input.mappedResult,
    selectionState,
    candidateRegistry,
    toolInput: input.toolInput,
    tonTables,
    omittedPaths,
    preservedPaths,
    maxRows: input.context?.maxRows ?? DEFAULT_TABLE_MAX_ROWS,
  });
  const contentValue = compactObject({
    tool: input.actionId,
    actionId: input.actionId,
    input: compactInput(input.toolInput),
    result,
  });
  const modelContent = serializeContentValue(
    contentValue,
    input.mode ?? "compact_json_ton",
  );
  const modelContentChars = modelContent.length;
  return {
    contentValue,
    modelContent,
    representation: input.mode ?? "compact_json_ton",
    serializerVersion: MODEL_FACING_SERIALIZER_VERSION,
    candidateRegistry,
    selectionState,
    rawContentChars,
    rawContentApproxTokens: approxTokens(rawContentChars),
    modelContentChars,
    modelContentApproxTokens: approxTokens(modelContentChars),
    compressionRatio: rawContentChars > 0 ? modelContentChars / rawContentChars : 1,
    omittedPaths,
    preservedPaths,
    tonTables,
  };
}

export function buildToolContentForModel(
  input: ModelFacingSerializationInput,
): ToolContentBuildResult {
  return serializeForModel(input);
}

export function resolveCandidateReferenceFromMessages(
  messages: AgentConversationMessageRecord[],
  selection: AgentChatCandidateSelection,
): {
  registry: CandidateRegistryMetadata;
  candidateRef: string;
  item: MealItem;
} | undefined {
  const registries = messages
    .map((message) => candidateRegistryFromMetadata(message.metadata))
    .filter((value): value is CandidateRegistryMetadata => Boolean(value))
    .reverse();
  const registry = selection.searchRef
    ? registries.find((candidate) => candidate.searchRef === selection.searchRef)
    : registries[0];
  return resolveCandidateReferenceFromRegistry(registry, selection);
}

export function resolveCandidateReferenceFromRegistry(
  registry: CandidateRegistryMetadata | undefined,
  selection: AgentChatCandidateSelection,
): {
  registry: CandidateRegistryMetadata;
  candidateRef: string;
  item: MealItem;
} | undefined {
  const selected = findCandidate(registry, selection);
  return registry && selected ? { registry, ...selected } : undefined;
}

export function selectedCandidateContent(input: {
  selection: AgentChatCandidateSelection;
  resolved: {
    registry: CandidateRegistryMetadata;
    candidateRef: string;
    item: MealItem;
  };
}): Record<string, unknown> {
  return {
    actionId: "resolve_candidate_reference",
    input: compactInput(input.selection),
    result: {
      kind: "candidate_reference",
      message: "Selected nutrition candidate resolved.",
      searchRef: input.resolved.registry.searchRef,
      candidateRef: input.resolved.candidateRef,
      selectedItem: mealItemForToolUse(input.resolved.item),
    },
  };
}

export function approxTokens(chars: number): number {
  return Math.ceil(chars / 4);
}

export function mealItemForToolUse(item: MealItem): Record<string, unknown> {
  return compactObject({
    id: item.id,
    name: item.name,
    quantity: item.quantity,
    unit: item.unit,
    calories: item.calories,
    proteinGrams: item.proteinGrams,
    carbsGrams: item.carbsGrams,
    fatGrams: item.fatGrams,
    source: item.source,
    originalText: item.originalText,
    canonicalName: item.canonicalName,
    language: item.language,
    externalSource: item.externalSource,
    externalId: item.externalId,
    confidence: item.confidence,
    needsReview: item.needsReview,
    resolvedGrams: item.resolvedGrams,
    portionDescription: item.portionDescription,
    rank: item.rank,
    matchScore: item.matchScore,
  });
}

export function ultraCompactToolContent(
  content: string,
  metadata: unknown,
): string {
  const parsed = safeParseRecord(content);
  const meta = recordValue(metadata);
  const actionId = stringValue(parsed?.actionId ?? parsed?.tool ?? meta?.actionId);
  const result = recordValue(parsed?.result);
  const kind = stringValue(result?.kind ?? meta?.resultKind);
  const searchRef = stringValue(
    result?.searchRef ??
      recordValue(result?.selectionState)?.searchRef ??
      meta?.searchRef ??
      meta?.candidateRegistryRef,
  );
  const table = stringValue(result?.candidatePreview ?? result?.table);
  const header = [
    `tool=${tonValue(actionId)}`,
    kind ? `kind=${tonValue(kind)}` : undefined,
    searchRef ? `ref=${tonValue(searchRef)}` : undefined,
    `chars=${content.length}`,
  ].filter(Boolean);
  if (table) return `${header.join(" ")}\n${table}`;
  const message = stringValue(result?.message);
  return `${header.join(" ")}${message ? ` msg=${tonValue(message)}` : ""}`;
}

function compactMappedResult(input: {
  mappedResult: Record<string, unknown>;
  selectionState?: AgentCandidateSelectionState;
  candidateRegistry?: CandidateRegistryMetadata;
  toolInput: unknown;
  tonTables: ModelFacingTonTable[];
  omittedPaths: string[];
  preservedPaths: string[];
  maxRows: number;
}): Record<string, unknown> {
  const {
    mappedResult,
    selectionState,
    candidateRegistry,
    toolInput,
    tonTables,
    omittedPaths,
    preservedPaths,
    maxRows,
  } = input;
  if (selectionState) {
    const candidatePreview = candidateRegistry
      ? candidatePreviewNotation(candidateRegistry, toolInput, maxRows)
      : undefined;
    if (candidateRegistry) {
      tonTables.push({
        path: "result.candidatePreview",
        rows: candidateRegistry.candidateCount,
        shown: Math.min(maxRows, candidateRegistry.candidateCount),
        columns: ["n", "ref", "name", "qty", "kcal", "p", "c", "f", "conf", "score", "src", "id"],
      });
      omittedPaths.push("result.items", "result.options", "result.candidateGroups");
      preservedPaths.push("result.selectionState", "result.candidatePreview");
    }
    return compactObject({
      kind: mappedResult.kind,
      message: mappedResult.message,
      selectionState,
      candidatePreview,
    });
  }

  const table = firstKnownTable(mappedResult, maxRows);
  if (table) {
    tonTables.push(table.metadata);
    omittedPaths.push(table.sourcePath);
    preservedPaths.push("result.table");
  }

  return compactObject({
    kind: mappedResult.kind,
    status: mappedResult.status,
    message: mappedResult.message,
    errorCode: mappedResult.errorCode,
    errorMessage: mappedResult.errorMessage,
    proposal: compactProposal(recordValue(mappedResult.proposal)),
    meal: compactMeal(recordValue(mappedResult.meal)),
    summary: compactSummary(recordValue(mappedResult.summary)),
    remaining: compactNutrition(recordValue(mappedResult.remaining)),
    selectedItem: compactMealItem(recordValue(mappedResult.selectedItem)),
    table: table?.content,
    itemCount: arrayLength(mappedResult.items),
    mealCount: arrayLength(mappedResult.meals),
    templateCount: arrayLength(mappedResult.templates),
  });
}

function firstKnownTable(
  mappedResult: Record<string, unknown>,
  maxRows: number,
): { sourcePath: string; content: string; metadata: ModelFacingTonTable } | undefined {
  const candidates: Array<{ path: string; value: unknown }> = [
    { path: "result.items", value: mappedResult.items },
    { path: "result.meals", value: mappedResult.meals },
    { path: "result.templates", value: mappedResult.templates },
    { path: "result.usualFoods", value: mappedResult.usualFoods },
    { path: "result.matches", value: mappedResult.matches },
  ];
  for (const candidate of candidates) {
    const rows = Array.isArray(candidate.value)
      ? candidate.value.map(recordValue).filter((row): row is Record<string, unknown> => Boolean(row))
      : [];
    if (rows.length === 0) continue;
    const table = tonTableForRows(candidate.path, rows, maxRows);
    if (table) return table;
  }
  return undefined;
}

function tonTableForRows(
  sourcePath: string,
  rows: Record<string, unknown>[],
  maxRows: number,
): { sourcePath: string; content: string; metadata: ModelFacingTonTable } {
  const profile = rowProfile(rows[0] ?? {});
  const shownRows = rows.slice(0, maxRows);
  const lines = [
    `${sourcePath.replace(/^result\./, "")} total=${rows.length} shown=${shownRows.length}`,
    `cols=${profile.columns.join("|")}`,
    ...shownRows.map((row, index) =>
      profile.values(row, index + 1).map(tonValue).join("|"),
    ),
  ];
  if (shownRows.length < rows.length) {
    lines.push(`omitted rows=${rows.length - shownRows.length} reason=budget`);
  }
  return {
    sourcePath,
    content: lines.join("\n"),
    metadata: {
      path: sourcePath,
      rows: rows.length,
      shown: shownRows.length,
      columns: profile.columns,
    },
  };
}

function rowProfile(row: Record<string, unknown>): {
  columns: string[];
  values(row: Record<string, unknown>, index: number): unknown[];
} {
  if ("title" in row || "items" in row) {
    return {
      columns: ["n", "id", "time", "title", "kcal", "p", "c", "f", "items"],
      values: (value, index) => [
        index,
        value.id,
        value.loggedAt ?? value.createdAt ?? value.updatedAt,
        value.title ?? value.name,
        value.calories,
        value.proteinGrams,
        value.carbsGrams,
        value.fatGrams,
        arrayLength(value.items),
      ],
    };
  }
  if ("calories" in row || "proteinGrams" in row || "externalSource" in row) {
    return {
      columns: ["n", "id", "name", "qty", "kcal", "p", "c", "f", "src"],
      values: (value, index) => [
        index,
        value.id ?? value.externalId,
        value.name,
        quantityText(value),
        value.calories,
        value.proteinGrams,
        value.carbsGrams,
        value.fatGrams,
        value.externalSource ?? value.source,
      ],
    };
  }
  return {
    columns: ["n", "id", "name", "title", "kind", "status", "summary"],
    values: (value, index) => [
      index,
      value.id,
      value.name,
      value.title,
      value.kind,
      value.status,
      value.summary ?? value.message ?? value.label,
    ],
  };
}

function buildCandidateRegistry(input: {
  actionId: string;
  actionCallId?: string;
  mappedResult: Record<string, unknown>;
  rawOutput: unknown;
  threshold: number;
}): CandidateRegistryMetadata | undefined {
  const groups = candidateGroupsForResult(input.mappedResult, input.rawOutput);
  if (groups.length === 0) return undefined;
  const searchRef = input.actionCallId ?? `search_${Date.now()}`;
  const registryGroups = groups.map((group, groupOffset) => {
    const groupIndex = groupOffset + 1;
    return {
      groupIndex,
      mention: group.mention,
      candidates: group.candidates.map((item, candidateOffset) => {
        const candidateIndex = candidateOffset + 1;
        return {
          candidateRef: candidateRef(searchRef, groupIndex, candidateIndex),
          candidateIndex,
          item,
        };
      }),
    };
  });
  const candidateCount = registryGroups.reduce(
    (sum, group) => sum + group.candidates.length,
    0,
  );
  if (candidateCount === 0) return undefined;
  return {
    kind: "agent_candidate_registry",
    searchRef,
    actionId: input.actionId,
    actionCallId: input.actionCallId,
    threshold: input.threshold,
    candidateCount,
    groupCount: registryGroups.length,
    groups: registryGroups,
  };
}

function candidateGroupsForResult(
  mappedResult: Record<string, unknown>,
  rawOutput: unknown,
): Array<{ mention?: unknown; candidates: MealItem[] }> {
  const values = [
    mappedResult.candidateGroups,
    mappedResult.options,
    recordValue(rawOutput)?.candidateGroups,
    recordValue(rawOutput)?.candidates,
  ];
  for (const value of values) {
    const groups = parseCandidateGroups(value);
    if (groups.length > 0) return groups;
  }
  const items = parseMealItems(mappedResult.items ?? recordValue(rawOutput)?.items);
  return items.length > 0 ? [{ candidates: items }] : [];
}

function parseCandidateGroups(
  value: unknown,
): Array<{ mention?: unknown; candidates: MealItem[] }> {
  if (!Array.isArray(value)) return [];
  const groups: Array<{ mention?: unknown; candidates: MealItem[] } | undefined> = value
    .map((entry) => {
      const record = recordValue(entry);
      const candidates = parseMealItems(record?.candidates);
      return candidates.length > 0
        ? { mention: record?.mention, candidates }
        : undefined;
    });
  return groups.filter(
    (entry): entry is { mention?: unknown; candidates: MealItem[] } =>
      Boolean(entry),
  );
}

function parseMealItems(value: unknown): MealItem[] {
  return Array.isArray(value)
    ? value.filter((item): item is MealItem => Boolean(recordValue(item)?.name))
    : [];
}

function selectionStateForRegistry(
  registry: CandidateRegistryMetadata,
): AgentCandidateSelectionState {
  const first = registry.groups[0]?.candidates[0];
  const topConfidence =
    typeof first?.item.confidence === "number" ? first.item.confidence : undefined;
  return {
    status: "candidate_preview",
    searchRef: registry.searchRef,
    candidateCount: registry.candidateCount,
    groupCount: registry.groupCount,
    threshold: registry.threshold,
    topConfidence,
  };
}

function candidatePreviewNotation(
  registry: CandidateRegistryMetadata,
  toolInput: unknown,
  maxRows: number,
): string {
  const query = stringValue(recordValue(toolInput)?.query);
  const shownLimit = Math.min(maxRows, registry.candidateCount);
  const rows: string[] = [
    `search q=${tonValue(query)} ref=${tonValue(registry.searchRef)} total=${registry.candidateCount} shown=${shownLimit}`,
    "cols=n|ref|name|qty|kcal|p|c|f|conf|score|src|id",
  ];
  let shown = 0;
  for (const group of registry.groups) {
    for (const candidate of group.candidates) {
      if (shown >= shownLimit) {
        if (shown < registry.candidateCount) {
          rows.push(`omitted rows=${registry.candidateCount - shown} reason=budget`);
        }
        return rows.join("\n");
      }
      const item = candidate.item;
      rows.push([
        candidate.candidateIndex,
        shortCandidateRef(group.groupIndex, candidate.candidateIndex),
        item.name,
        `${item.quantity}${item.unit}`,
        numberValue(item.calories),
        numberValue(item.proteinGrams),
        numberValue(item.carbsGrams),
        numberValue(item.fatGrams),
        numberValue(item.confidence),
        numberValue(item.matchScore),
        item.externalSource,
        item.externalId,
      ].map(tonValue).join("|"));
      shown++;
    }
  }
  return rows.join("\n");
}

function findCandidate(
  registry: CandidateRegistryMetadata | undefined,
  selection: AgentChatCandidateSelection,
): { candidateRef: string; item: MealItem } | undefined {
  if (!registry) return undefined;
  const shortRefSelection = parseShortCandidateRef(selection.candidateRef);
  const groupIndex = selection.groupIndex ?? shortRefSelection?.groupIndex;
  const candidateIndex =
    selection.candidateIndex ?? shortRefSelection?.candidateIndex;
  if (!selection.candidateRef && candidateIndex === undefined) {
    return undefined;
  }
  for (const group of registry.groups) {
    for (const candidate of group.candidates) {
      if (selection.candidateRef && candidate.candidateRef === selection.candidateRef) {
        return { candidateRef: candidate.candidateRef, item: candidate.item };
      }
      const groupMatches =
        groupIndex === undefined || groupIndex === group.groupIndex;
      const candidateMatches =
        candidateIndex === undefined ||
        candidateIndex === candidate.candidateIndex;
      if (!selection.candidateRef && groupMatches && candidateMatches) {
        return { candidateRef: candidate.candidateRef, item: candidate.item };
      }
      if (selection.candidateRef && shortRefSelection && groupMatches && candidateMatches) {
        return { candidateRef: candidate.candidateRef, item: candidate.item };
      }
    }
  }
  return undefined;
}

function candidateRegistryFromMetadata(
  metadata: unknown,
): CandidateRegistryMetadata | undefined {
  const registry = recordValue(metadata)?.candidateRegistry;
  const value = recordValue(registry);
  return value?.kind === "agent_candidate_registry"
    ? (value as CandidateRegistryMetadata)
    : undefined;
}

function candidateRef(
  searchRef: string,
  groupIndex: number,
  candidateIndex: number,
): string {
  return `${searchRef}:g${groupIndex}:c${candidateIndex}`;
}

function shortCandidateRef(groupIndex: number, candidateIndex: number): string {
  return `g${groupIndex}c${candidateIndex}`;
}

function parseShortCandidateRef(
  value: string | undefined,
): { groupIndex: number; candidateIndex: number } | undefined {
  const match = value?.match(/^g(\d+)c(\d+)$/);
  if (!match) return undefined;
  return {
    groupIndex: Number(match[1]),
    candidateIndex: Number(match[2]),
  };
}

function compactInput(input: unknown): unknown {
  if (!input || typeof input !== "object" || Array.isArray(input)) return input;
  const record = input as Record<string, unknown>;
  return compactObject({
    query: record.query,
    barcode: record.barcode,
    text: record.text,
    phrase: record.phrase,
    title: record.title,
    searchRef: record.searchRef,
    candidateRef: record.candidateRef,
    groupIndex: record.groupIndex,
    candidateIndex: record.candidateIndex,
  });
}

function compactProposal(value: Record<string, unknown> | undefined): unknown {
  if (!value) return undefined;
  return compactObject({
    id: value.id,
    title: value.title,
    status: value.status,
    totalCalories: value.totalCalories ?? value.calories,
    totalProteinGrams: value.totalProteinGrams ?? value.proteinGrams,
    totalCarbsGrams: value.totalCarbsGrams ?? value.carbsGrams,
    totalFatGrams: value.totalFatGrams ?? value.fatGrams,
    itemCount: arrayLength(value.items),
  });
}

function compactMeal(value: Record<string, unknown> | undefined): unknown {
  if (!value) return undefined;
  return compactObject({
    id: value.id,
    title: value.title ?? value.name,
    loggedAt: value.loggedAt,
    calories: value.calories,
    proteinGrams: value.proteinGrams,
    carbsGrams: value.carbsGrams,
    fatGrams: value.fatGrams,
    itemCount: arrayLength(value.items),
  });
}

function compactSummary(value: Record<string, unknown> | undefined): unknown {
  if (!value) return undefined;
  return compactObject({
    date: value.date,
    calories: value.calories,
    proteinGrams: value.proteinGrams,
    carbsGrams: value.carbsGrams,
    fatGrams: value.fatGrams,
    mealCount: arrayLength(value.meals),
  });
}

function compactNutrition(value: Record<string, unknown> | undefined): unknown {
  if (!value) return undefined;
  return compactObject({
    calories: value.calories,
    proteinGrams: value.proteinGrams,
    carbsGrams: value.carbsGrams,
    fatGrams: value.fatGrams,
  });
}

function compactMealItem(value: Record<string, unknown> | undefined): unknown {
  if (!value) return undefined;
  return compactObject({
    id: value.id,
    name: value.name,
    quantity: value.quantity,
    unit: value.unit,
    calories: value.calories,
    proteinGrams: value.proteinGrams,
    carbsGrams: value.carbsGrams,
    fatGrams: value.fatGrams,
    source: value.externalSource ?? value.source,
  });
}

function serializeContentValue(
  value: Record<string, unknown>,
  mode: ModelFacingRepresentation,
): string {
  if (mode === "ultra_ton") {
    return ultraCompactToolContent(JSON.stringify(value), undefined);
  }
  return JSON.stringify(value);
}

function safeParseRecord(value: string): Record<string, unknown> | undefined {
  try {
    return recordValue(JSON.parse(value));
  } catch {
    return undefined;
  }
}

function compactObject<T extends Record<string, unknown>>(value: T): T {
  return Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  ) as T;
}

function recordValue(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function numberValue(value: unknown): string {
  return typeof value === "number" && Number.isFinite(value)
    ? Number(value.toFixed(3)).toString()
    : "";
}

function quantityText(value: Record<string, unknown>): string {
  return `${value.quantity ?? ""}${value.unit ?? ""}`;
}

function arrayLength(value: unknown): number | undefined {
  return Array.isArray(value) ? value.length : undefined;
}

function tonValue(value: unknown): string {
  return String(value ?? "")
    .replace(/[|\r\n\t]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
