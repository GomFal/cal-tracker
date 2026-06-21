import type { MealItem } from "@cal-tracker/contracts";
import type { AgentConversationMessageRecord } from "../repository/types.js";

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

export type ToolContentBuildResult = {
  contentValue: Record<string, unknown>;
  candidateRegistry?: CandidateRegistryMetadata;
  selectionState?: AgentCandidateSelectionState;
  rawContentChars: number;
  rawContentApproxTokens: number;
  modelContentChars: number;
  modelContentApproxTokens: number;
};

export function buildToolContentForModel(input: {
  actionId: string;
  actionCallId?: string;
  toolInput: unknown;
  mappedResult: Record<string, unknown>;
  rawOutput: unknown;
  threshold: number;
}): ToolContentBuildResult {
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
  const contentValue = {
    actionId: input.actionId,
    input: compactInput(input.toolInput),
    result: compactMappedResult({
      mappedResult: input.mappedResult,
      selectionState,
      candidateRegistry,
      toolInput: input.toolInput,
    }),
  };
  const modelContentChars = JSON.stringify(contentValue).length;
  return {
    contentValue,
    candidateRegistry,
    selectionState,
    rawContentChars,
    rawContentApproxTokens: approxTokens(rawContentChars),
    modelContentChars,
    modelContentApproxTokens: approxTokens(modelContentChars),
  };
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
  if (!registry) return undefined;
  const selected = findCandidate(registry, selection);
  return selected ? { registry, ...selected } : undefined;
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

function compactMappedResult(input: {
  mappedResult: Record<string, unknown>;
  selectionState?: AgentCandidateSelectionState;
  candidateRegistry?: CandidateRegistryMetadata;
  toolInput: unknown;
}): Record<string, unknown> {
  const { mappedResult, selectionState, candidateRegistry, toolInput } = input;
  if (selectionState) {
    return compactObject({
      kind: mappedResult.kind,
      message: mappedResult.message,
      selectionState,
      candidatePreview: candidateRegistry
        ? candidatePreviewNotation(candidateRegistry, toolInput)
        : undefined,
    });
  }
  return compactObject({
    ...mappedResult,
    options: undefined,
    candidateGroups: undefined,
  });
}

function candidatePreviewNotation(
  registry: CandidateRegistryMetadata,
  toolInput: unknown,
): string {
  const query = stringValue(recordValue(toolInput)?.query);
  const rows: string[] = [
    `search q=${tonValue(query)} ref=${tonValue(registry.searchRef)} total=${registry.candidateCount} shown=${Math.min(10, registry.candidateCount)}`,
    "cols=n|ref|name|qty|kcal|p|c|f|conf|score|src|id",
  ];
  let shown = 0;
  for (const group of registry.groups) {
    for (const candidate of group.candidates) {
      if (shown >= 10) return rows.join("\n");
      const item = candidate.item;
      rows.push([
        candidate.candidateIndex,
        shortCandidateRef(group.groupIndex, candidate.candidateIndex),
        tonValue(item.name),
        tonValue(`${item.quantity}${item.unit}`),
        numberValue(item.calories),
        numberValue(item.proteinGrams),
        numberValue(item.carbsGrams),
        numberValue(item.fatGrams),
        numberValue(item.confidence),
        numberValue(item.matchScore),
        tonValue(item.externalSource),
        tonValue(item.externalId),
      ].join("|"));
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
        groupIndex === undefined ||
        groupIndex === group.groupIndex;
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

function tonValue(value: unknown): string {
  return String(value ?? "")
    .replace(/[|\r\n\t]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}
