import type { FoodItemRecord } from "./types.js";
import { normalizeText } from "../utils/normalize.js";

const EXACT_MATCH_SCORE = 1;
const FIRST_TOKEN_PHRASE_SCORE = 0.94;
const LATER_TOKEN_PHRASE_SCORE = 0.82;
const REORDERED_TOKEN_SCORE = 0.78;
const STRING_PREFIX_SCORE = 0.62;
const STRING_CONTAINS_SCORE = 0.45;
const BRAND_SCORE_CAP = 0.5;
const CATEGORY_SCORE_CAP = 0.35;

export function lexicalFoodScore(food: FoodItemRecord, normalizedQuery: string): number {
  const query = normalizeText(normalizedQuery);
  if (!query) return 0;
  const queryTokens = tokenizeSearchText(query);
  if (queryTokens.length === 0) return 0;

  const primaryScore = Math.max(
    scoreSearchText(food.normalizedName, query, queryTokens),
    scoreSearchText(food.canonicalName, query, queryTokens),
    scoreSearchText(food.name, query, queryTokens),
  );
  const brandScore = Math.min(
    BRAND_SCORE_CAP,
    scoreSearchText(food.brand, query, queryTokens),
  );
  const categoryScore = Math.min(
    CATEGORY_SCORE_CAP,
    scoreSearchText(food.foodCategory, query, queryTokens),
  );
  return clampScore(Math.max(primaryScore, brandScore, categoryScore));
}

function scoreSearchText(value: string | undefined, query: string, queryTokens: string[]): number {
  if (!value) return 0;
  const text = normalizeText(value);
  if (!text) return 0;
  const textTokens = tokenizeSearchText(text);
  if (textTokens.length === 0) return 0;

  if (text === query || tokensEqual(textTokens, queryTokens)) return EXACT_MATCH_SCORE;
  if (
    textTokens.length < queryTokens.length &&
    (startsWithTokenPhrase(queryTokens, textTokens) ||
      containsTokenPhrase(queryTokens, textTokens))
  ) {
    return compactnessAdjustedScore(REORDERED_TOKEN_SCORE, queryTokens, textTokens);
  }
  if (startsWithTokenPhrase(textTokens, queryTokens)) {
    return compactnessAdjustedScore(FIRST_TOKEN_PHRASE_SCORE, textTokens, queryTokens);
  }
  if (containsTokenPhrase(textTokens, queryTokens)) {
    return compactnessAdjustedScore(LATER_TOKEN_PHRASE_SCORE, textTokens, queryTokens);
  }
  if (queryTokens.length > 1 && queryTokens.every((token) => textTokens.includes(token))) {
    const score = textTokens.some((token, index) => index < 3 && queryTokens.includes(token))
      ? REORDERED_TOKEN_SCORE
      : LATER_TOKEN_PHRASE_SCORE - 0.1;
    return compactnessAdjustedScore(score, textTokens, queryTokens);
  }
  if (text.startsWith(query)) {
    return compactnessAdjustedScore(STRING_PREFIX_SCORE, textTokens, queryTokens);
  }
  if (text.includes(query)) {
    return compactnessAdjustedScore(STRING_CONTAINS_SCORE, textTokens, queryTokens);
  }
  return 0;
}

function compactnessAdjustedScore(score: number, textTokens: string[], queryTokens: string[]): number {
  const extraTokenCount = Math.max(0, textTokens.length - queryTokens.length);
  const extraCharCount = Math.max(0, textTokens.join(" ").length - queryTokens.join(" ").length);
  return clampScore(score - Math.min(0.12, extraTokenCount * 0.015 + extraCharCount * 0.001));
}

function tokenizeSearchText(value: string): string[] {
  return normalizeText(value)
    .split(/\s+/)
    .filter(Boolean)
    .map(singularizeToken);
}

function singularizeToken(token: string): string {
  if (token.length > 3 && token.endsWith("ies")) return `${token.slice(0, -3)}y`;
  if (token.length > 4 && token.endsWith("oes")) return token.slice(0, -2);
  if (token.length > 3 && token.endsWith("s") && !token.endsWith("ss")) return token.slice(0, -1);
  return token;
}

function startsWithTokenPhrase(tokens: string[], phraseTokens: string[]): boolean {
  if (phraseTokens.length > tokens.length) return false;
  return phraseTokens.every((token, index) => tokens[index] === token);
}

function containsTokenPhrase(tokens: string[], phraseTokens: string[]): boolean {
  if (phraseTokens.length > tokens.length) return false;
  for (let index = 1; index <= tokens.length - phraseTokens.length; index++) {
    if (phraseTokens.every((token, phraseIndex) => tokens[index + phraseIndex] === token)) {
      return true;
    }
  }
  return false;
}

function tokensEqual(left: string[], right: string[]): boolean {
  return left.length === right.length && left.every((token, index) => token === right[index]);
}

function clampScore(value: number): number {
  return Math.max(0, Math.min(1, value));
}
