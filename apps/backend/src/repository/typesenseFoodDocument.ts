import type { FoodItemRecord, FoodPortionRecord } from "./types.js";
import { normalizeText } from "../utils/normalize.js";

export const DEFAULT_TYPESENSE_FOOD_COLLECTION = "food_items_demo_v1";

export type TypesenseFoodDocument = {
  id: string;
  userId?: string;
  isGlobal: boolean;
  searchText: string;
  name: string;
  normalizedName: string;
  canonicalName?: string;
  brand?: string;
  barcode?: string;
  scope: "generic" | "market";
  locale: "es" | "en" | "any";
  source: string;
  externalSource?: string;
  externalId?: string;
  sourceUrl?: string;
  license?: string;
  dataType?: string;
  foodCategory?: string;
  publicationDate?: string;
  ndbNumber?: string;
  foodKey?: string;
  ingredients?: string;
  marketCountry?: string;
  householdServingFulltext?: string;
  rankBucket: number;
  servingGrams: number;
  calories: number;
  proteinGrams: number;
  carbsGrams: number;
  fatGrams: number;
  portions: FoodPortionRecord[];
};

export type TypesenseCollectionSchema = {
  name: string;
  enable_nested_fields: boolean;
  fields: Array<{
    name: string;
    type: string;
    optional?: boolean;
    index?: boolean;
    facet?: boolean;
    sort?: boolean;
  }>;
};

export function typesenseFoodCollectionSchema(
  name = DEFAULT_TYPESENSE_FOOD_COLLECTION,
): TypesenseCollectionSchema {
  return {
    name,
    enable_nested_fields: true,
    fields: [
      { name: "id", type: "string", facet: true },
      { name: "userId", type: "string", optional: true, facet: true },
      { name: "isGlobal", type: "bool", facet: true },
      { name: "searchText", type: "string" },
      { name: "name", type: "string" },
      { name: "normalizedName", type: "string" },
      { name: "canonicalName", type: "string", optional: true },
      { name: "brand", type: "string", optional: true },
      { name: "barcode", type: "string", optional: true, facet: true },
      { name: "scope", type: "string", facet: true },
      { name: "locale", type: "string", facet: true },
      { name: "source", type: "string", facet: true },
      { name: "externalSource", type: "string", optional: true, facet: true },
      { name: "externalId", type: "string", optional: true, facet: true },
      { name: "sourceUrl", type: "string", optional: true, index: false },
      { name: "license", type: "string", optional: true, index: false },
      { name: "dataType", type: "string", optional: true, facet: true },
      { name: "foodCategory", type: "string", optional: true, facet: true },
      { name: "publicationDate", type: "string", optional: true, index: false },
      { name: "ndbNumber", type: "string", optional: true, facet: true },
      { name: "foodKey", type: "string", optional: true, facet: true },
      { name: "ingredients", type: "string", optional: true },
      { name: "marketCountry", type: "string", optional: true, facet: true },
      { name: "householdServingFulltext", type: "string", optional: true },
      { name: "rankBucket", type: "int32", facet: true, sort: true },
      { name: "servingGrams", type: "float", index: false },
      { name: "calories", type: "float", index: false },
      { name: "proteinGrams", type: "float", index: false },
      { name: "carbsGrams", type: "float", index: false },
      { name: "fatGrams", type: "float", index: false },
      { name: "portions", type: "object[]", optional: true, index: false },
    ],
  };
}

export function typesenseFoodDocumentForFood(
  food: FoodItemRecord,
  portions: FoodPortionRecord[] = food.portions ?? [],
  searchDocument?: {
    searchText?: string;
    scope?: "generic" | "market";
    locale?: "es" | "en" | "any";
    rankBucket?: number;
  },
): TypesenseFoodDocument | undefined {
  const searchText = normalizeText(searchDocument?.searchText ??
    [
      food.normalizedName,
      food.canonicalName,
      food.name,
      food.brand,
      food.foodCategory,
      food.ingredients,
    ]
      .filter((value): value is string => Boolean(value))
      .join(" "),
  );
  if (!searchText) return undefined;
  return omitUndefined({
    id: food.id,
    userId: food.userId,
    isGlobal: !food.userId,
    searchText,
    name: food.name,
    normalizedName: food.normalizedName,
    canonicalName: food.canonicalName,
    brand: food.brand,
    barcode: food.barcode,
    scope: searchDocument?.scope ?? typesenseFoodScope(food),
    locale: searchDocument?.locale ?? typesenseFoodLocale(food),
    source: food.source,
    externalSource: food.externalSource,
    externalId: food.externalId,
    sourceUrl: food.sourceUrl,
    license: food.license,
    dataType: food.dataType,
    foodCategory: food.foodCategory,
    publicationDate: food.publicationDate,
    ndbNumber: food.ndbNumber,
    foodKey: food.foodKey,
    ingredients: food.ingredients,
    marketCountry: food.marketCountry,
    householdServingFulltext: food.householdServingFulltext,
    rankBucket: searchDocument?.rankBucket ?? typesenseFoodRankBucket(food),
    servingGrams: food.servingGrams,
    calories: food.calories,
    proteinGrams: food.proteinGrams,
    carbsGrams: food.carbsGrams,
    fatGrams: food.fatGrams,
    portions: portions.map((portion) => omitUndefined({ ...portion })),
  });
}

export function foodRecordFromTypesenseDocument(
  document: TypesenseFoodDocument,
): FoodItemRecord {
  return {
    id: document.id,
    userId: document.userId,
    name: document.name,
    normalizedName: document.normalizedName,
    canonicalName: document.canonicalName,
    brand: document.brand,
    barcode: document.barcode,
    source: document.source,
    externalSource: document.externalSource,
    externalId: document.externalId,
    sourceUrl: document.sourceUrl,
    license: document.license,
    dataType: document.dataType,
    foodCategory: document.foodCategory,
    publicationDate: document.publicationDate,
    ndbNumber: document.ndbNumber,
    foodKey: document.foodKey,
    ingredients: document.ingredients,
    marketCountry: document.marketCountry,
    householdServingFulltext: document.householdServingFulltext,
    portions: (document.portions ?? []).map((portion) => ({ ...portion })),
    servingGrams: document.servingGrams,
    calories: document.calories,
    proteinGrams: document.proteinGrams,
    carbsGrams: document.carbsGrams,
    fatGrams: document.fatGrams,
  };
}

export function typesenseFoodScope(food: FoodItemRecord): "generic" | "market" {
  if (
    food.userId ||
    (
      food.dataType !== "Branded" &&
      food.source !== "usda_branded" &&
      (food.source !== "openfoodfacts" || (!food.barcode && !food.brand))
    )
  ) {
    return "generic";
  }
  return "market";
}

export function typesenseFoodLocale(food: FoodItemRecord): "es" | "en" | "any" {
  if (food.foodKey === "es" || food.foodKey === "en") return food.foodKey;
  if (food.externalSource === "usda_fdc") return "en";
  return "any";
}

export function typesenseFoodRankBucket(food: FoodItemRecord): number {
  if (food.userId) return 0;
  if (food.source === "openfoodfacts" && food.foodKey === "es" && !food.barcode && !food.brand) return 1;
  if (food.dataType === "SR Legacy") return 2;
  if (food.dataType === "Foundation") return 3;
  if (food.dataType === "Survey (FNDDS)") return 4;
  if (food.source === "openfoodfacts") return 7;
  if (food.dataType === "Branded") return 8;
  return 6;
}

function omitUndefined<T extends Record<string, unknown>>(value: T): T {
  return Object.fromEntries(
    Object.entries(value).filter(([, item]) => item !== undefined),
  ) as T;
}
