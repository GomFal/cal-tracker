import { describe, expect, it } from "vitest";
import { gramsFromPercentages, macroCaloriesFromGrams } from "../utils/macroGoals.js";
import { buildTestApp, registerAndAuth } from "./testApp.js";

describe("macro goals", () => {
  it("derives whole gram targets from percentage presets", () => {
    const grams = gramsFromPercentages(2000, {
      proteinPct: 35,
      carbsPct: 35,
      fatPct: 30
    });

    expect(grams).toEqual({
      proteinGrams: 175,
      carbsGrams: 175,
      fatGrams: 67
    });
    expect(macroCaloriesFromGrams(grams)).toBe(2003);
  });

  it("persists preset macro metadata and derived grams", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const update = await request("http://localhost/v1/goals", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: "2026-05-18",
        calories: 2000,
        calorieTargetSource: "calculator",
        macroMode: "percentage",
        macroSource: "preset",
        macroPreset: "high_protein",
        proteinPct: 35,
        carbsPct: 35,
        fatPct: 30
      })
    });

    expect(update.status).toBe(200);
    const body = await update.json() as {
      goals: {
        target: { calories: number; proteinGrams: number; carbsGrams: number; fatGrams: number };
        macroMode: string;
        macroSource: string;
        macroPreset: string;
        proteinPct: number;
        carbsPct: number;
        fatPct: number;
        macroCalories: number;
        calorieDeltaKcal: number;
      };
    };

    expect(body.goals.target).toEqual({
      calories: 2000,
      proteinGrams: 175,
      carbsGrams: 175,
      fatGrams: 67
    });
    expect(body.goals.macroMode).toBe("percentage");
    expect(body.goals.macroSource).toBe("preset");
    expect(body.goals.macroPreset).toBe("high_protein");
    expect(body.goals.proteinPct).toBe(35);
    expect(body.goals.carbsPct).toBe(35);
    expect(body.goals.fatPct).toBe(30);
    expect(body.goals.macroCalories).toBe(2003);
    expect(body.goals.calorieDeltaKcal).toBe(3);

    const summary = await request(
      "http://localhost/v1/summary/daily?date=2026-05-18",
      { headers: auth.authHeader }
    ).then((response) => response.json() as Promise<{
      output: { summary: { target: { proteinGrams: number }; consumed: { proteinGrams: number }; macroPreset: string } };
    }>);

    expect(summary.output.summary.target.proteinGrams).toBe(175);
    expect(summary.output.summary.consumed.proteinGrams).toBe(0);
    expect(summary.output.summary.macroPreset).toBe("high_protein");
  });

  it("persists custom gram targets and calorie delta", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const update = await request("http://localhost/v1/goals", {
      method: "PUT",
      headers: auth.authHeader,
      body: JSON.stringify({
        date: "2026-05-18",
        calories: 2000,
        macroMode: "grams",
        macroSource: "custom",
        proteinGrams: 180,
        carbsGrams: 180,
        fatGrams: 80
      })
    });

    expect(update.status).toBe(200);
    const body = await update.json() as {
      goals: {
        target: { calories: number; proteinGrams: number; carbsGrams: number; fatGrams: number };
        macroMode: string;
        macroSource: string;
        macroCalories: number;
        calorieDeltaKcal: number;
      };
    };

    expect(body.goals.target).toEqual({
      calories: 2000,
      proteinGrams: 180,
      carbsGrams: 180,
      fatGrams: 80
    });
    expect(body.goals.macroMode).toBe("grams");
    expect(body.goals.macroSource).toBe("custom");
    expect(body.goals.macroCalories).toBe(2160);
    expect(body.goals.calorieDeltaKcal).toBe(160);
  });
});
