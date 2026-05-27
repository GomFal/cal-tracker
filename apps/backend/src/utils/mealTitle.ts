import { existsSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import type { MealItem } from "@cal-tracker/contracts";

const DEFAULT_LOCALE = "en";
const LIST_SEPARATOR_KEY = "mealTitleListSeparator";
const LIST_FINAL_SEPARATOR_KEY = "mealTitleListFinalSeparator";
const MAX_FULL_TITLE_INGREDIENTS = 4;
const MAX_VISIBLE_TITLE_INGREDIENTS = 3;

type MealTitleMessages = {
  listSeparator: string;
  listFinalSeparator: string;
};

const messagesByLocale = new Map<string, MealTitleMessages>();

export class MealTitleError extends Error {
  constructor(public readonly code: "proposal_empty") {
    super(code);
  }
}

export function buildMealTitle(items: MealItem[]): string {
  const connectorLanguage = connectorLanguageFromItems(items);
  const names = items
    .map((item) => (item.canonicalName ?? item.name).trim())
    .filter(Boolean);
  if (names.length === 0) throw new MealTitleError("proposal_empty");
  const hasOverflow = names.length > MAX_FULL_TITLE_INGREDIENTS;
  const visibleNames = hasOverflow
    ? names.slice(0, MAX_VISIBLE_TITLE_INGREDIENTS)
    : names;
  const overflowCount = names.length - visibleNames.length;
  const capitalizationLocale = connectorLanguage ?? DEFAULT_LOCALE;
  if (visibleNames.length === 1) {
    return capitalizeTitle(visibleNames[0]!, capitalizationLocale);
  }

  const messages = mealTitleMessages(connectorLanguage ?? DEFAULT_LOCALE);
  if (hasOverflow || !connectorLanguage) {
    return capitalizeTitle(
      `${visibleNames.join(messages.listSeparator)}${
        hasOverflow ? `${messages.listSeparator}+${overflowCount}` : ""
      }`,
      capitalizationLocale,
    );
  }
  if (visibleNames.length === 2) {
    return capitalizeTitle(
      `${visibleNames[0]}${messages.listFinalSeparator}${visibleNames[1]}`,
      capitalizationLocale,
    );
  }
  return capitalizeTitle(
    `${visibleNames.slice(0, -1).join(messages.listSeparator)}${
      messages.listFinalSeparator
    }${visibleNames[visibleNames.length - 1]}`,
    capitalizationLocale,
  );
}

function mealTitleMessages(locale?: string): MealTitleMessages {
  const language = supportedLanguage(locale) ?? DEFAULT_LOCALE;
  const cached = messagesByLocale.get(language);
  if (cached) return cached;
  const messages = readMealTitleMessages(language);
  messagesByLocale.set(language, messages);
  return messages;
}

function readMealTitleMessages(language: string): MealTitleMessages {
  const arb = readArb(language) ?? readArb(DEFAULT_LOCALE);
  if (!arb) {
    throw new Error("meal_title_localization_missing");
  }
  return {
    listSeparator: requiredArbString(arb, LIST_SEPARATOR_KEY),
    listFinalSeparator: requiredArbString(arb, LIST_FINAL_SEPARATOR_KEY),
  };
}

function readArb(language: string): Record<string, unknown> | undefined {
  for (const directory of arbDirectories()) {
    const filename = path.join(directory, `app_${language}.arb`);
    if (!existsSync(filename)) continue;
    return JSON.parse(readFileSync(filename, "utf8")) as Record<string, unknown>;
  }
  return undefined;
}

function requiredArbString(
  arb: Record<string, unknown>,
  key: string,
): string {
  const value = arb[key];
  if (typeof value !== "string") {
    throw new Error(`meal_title_localization_key_missing:${key}`);
  }
  return value;
}

function languageFromLocale(locale?: string): string | undefined {
  const language = locale
    ?.toLowerCase()
    .split(/[-_]/)[0]
    ?.replace(/[^a-z]/g, "");
  return language || undefined;
}

function connectorLanguageFromItems(items: MealItem[]): string | undefined {
  const languages = items
    .map((item) => item.language?.trim())
    .map(languageFromLocale)
    .filter((language): language is string => Boolean(language));
  const uniqueLanguages = uniqueStrings(languages);
  if (languages.length !== items.length || uniqueLanguages.length !== 1) {
    return undefined;
  }
  return supportedLanguage(uniqueLanguages[0]);
}

function supportedLanguage(locale?: string): string | undefined {
  const language = languageFromLocale(locale);
  if (!language) return undefined;
  return readArb(language) ? language : undefined;
}

function capitalizeTitle(title: string, locale: string): string {
  const first = firstGrapheme(title, locale);
  if (!first) return title;
  return `${first.segment.toLocaleUpperCase(locale)}${title.slice(
    first.segment.length,
  )}`;
}

function firstGrapheme(
  value: string,
  locale: string,
): { segment: string } | undefined {
  if ("Segmenter" in Intl) {
    const iterator = new Intl.Segmenter(locale, {
      granularity: "grapheme",
    }).segment(value)[Symbol.iterator]();
    return iterator.next().value as { segment: string } | undefined;
  }
  const [first] = Array.from(value);
  return first ? { segment: first } : undefined;
}

function arbDirectories(): string[] {
  const currentDirectory = path.dirname(fileURLToPath(import.meta.url));
  return uniqueStrings([
    path.resolve(process.cwd(), "../mobile/lib/l10n"),
    path.resolve(process.cwd(), "apps/mobile/lib/l10n"),
    path.resolve(currentDirectory, "../../../mobile/lib/l10n"),
    path.resolve(currentDirectory, "../../../../mobile/lib/l10n"),
  ]);
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values)];
}
