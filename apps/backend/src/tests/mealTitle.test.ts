import type { MealItem } from "@cal-tracker/contracts";
import { describe, expect, it } from "vitest";
import { buildMealTitle, MealTitleError } from "../utils/mealTitle.js";

function item(
  name: string,
  canonicalName = name,
  language?: string,
): MealItem {
  return {
    name,
    canonicalName,
    language,
    quantity: 100,
    unit: "g",
    calories: 100,
    proteinGrams: 10,
    carbsGrams: 10,
    fatGrams: 1,
    source: "test_fixture",
  };
}

describe("buildMealTitle", () => {
  it("rejects empty ingredient lists", () => {
    expect(() => buildMealTitle([])).toThrow(MealTitleError);
  });

  it.each([
    {
      label: "one ingredient",
      items: [item("Chicken, meatless", "chicken", "en")],
      expected: "Chicken",
    },
    {
      label: "two English ingredients",
      items: [
        item("Chicken, meatless", "chicken", "en"),
        item("Rice, black, unenriched, raw", "rice", "en"),
      ],
      expected: "Chicken and rice",
    },
    {
      label: "three English ingredients",
      items: [
        item("Chicken, meatless", "chicken", "en"),
        item("Rice, black, unenriched, raw", "rice", "en"),
        item("Bread, wheat", "bread", "en"),
      ],
      expected: "Chicken, rice and bread",
    },
    {
      label: "four English ingredients",
      items: [
        item("Chicken, meatless", "chicken", "en"),
        item("Rice, black, unenriched, raw", "rice", "en"),
        item("Bread, wheat", "bread", "en"),
        item("Butter, salted", "butter", "en"),
      ],
      expected: "Chicken, rice, bread and butter",
    },
    {
      label: "five English ingredients",
      items: [
        item("Chicken, meatless", "chicken", "en"),
        item("Rice, black, unenriched, raw", "rice", "en"),
        item("Bread, wheat", "bread", "en"),
        item("Butter, salted", "butter", "en"),
        item("Ham", "ham", "en"),
      ],
      expected: "Chicken, rice, bread +2",
    },
    {
      label: "two Spanish ingredients",
      items: [
        item("Chicken, meatless", "pollo", "es"),
        item("Rice, black, unenriched, raw", "arroz", "es"),
      ],
      expected: "Pollo y arroz",
    },
    {
      label: "three Spanish ingredients",
      items: [
        item("Chicken, meatless", "pollo", "es"),
        item("Rice, black, unenriched, raw", "arroz", "es"),
        item("Bread, wheat", "pan", "es"),
      ],
      expected: "Pollo, arroz y pan",
    },
    {
      label: "five Spanish ingredients",
      items: [
        item("Chicken, meatless", "pollo", "es"),
        item("Rice, black, unenriched, raw", "arroz", "es"),
        item("Bread, wheat", "pan", "es"),
        item("Butter, salted", "mantequilla", "es"),
        item("Ham", "jamon", "es"),
      ],
      expected: "Pollo, arroz, pan +2",
    },
    {
      label: "capitalized new first ingredient after deletion",
      items: [
        item("Rice, black, unenriched, raw", "arroz", "es"),
        item("Bread, wheat", "pan", "es"),
      ],
      expected: "Arroz y pan",
    },
    {
      label: "non-ASCII first ingredient",
      items: [item("Ñame", "ñame", "es")],
      expected: "Ñame",
    },
    {
      label: "mixed language ingredients",
      items: [
        item("Chicken, meatless", "pollo", "es"),
        item("Beef", "beef", "en"),
      ],
      expected: "Pollo, beef",
    },
    {
      label: "many mixed language ingredients",
      items: [
        item("Chicken, meatless", "pollo", "es"),
        item("Ham", "jamon", "es"),
        item("Beef", "beef", "en"),
        item("Croissant", "croissant", "fr"),
        item("Rice, black, unenriched, raw", "arroz", "es"),
        item("Bread, wheat", "pan", "es"),
      ],
      expected: "Pollo, jamon, beef +3",
    },
    {
      label: "missing item language",
      items: [
        item("Chicken, meatless", "pollo", "es"),
        item("Rice, black, unenriched, raw", "rice"),
      ],
      expected: "Pollo, rice",
    },
    {
      label: "unsupported item language",
      items: [
        item("Chicken, meatless", "poulet", "fr"),
        item("Rice, black, unenriched, raw", "riz", "fr"),
      ],
      expected: "Poulet, riz",
    },
  ])("formats $label", ({ items, expected }) => {
    expect(buildMealTitle(items)).toBe(expected);
  });
});
