import { describe, expect, it } from "vitest";
import { estimateCalories } from "../nutrition/calorieEstimator.js";
import { buildTestApp, registerAndAuth } from "./testApp.js";

describe("calorie estimator", () => {
  it("calculates a male maintenance target with Mifflin-St Jeor and activity factor", () => {
    const estimate = estimateCalories({
      age: 30,
      sex: "male",
      heightCm: 180,
      weightKg: 80,
      activityLevel: "moderately_active",
      goal: "maintain",
    });

    expect(estimate.bmr).toBe(1780);
    expect(estimate.maintenanceCalories).toBe(2760);
    expect(estimate.targetCalories).toBe(2760);
    expect(estimate.recommendedRange).toEqual({ min: 2610, max: 2910 });
  });

  it("calculates a female moderate fat-loss target with bounded deficit", () => {
    const estimate = estimateCalories({
      age: 35,
      sex: "female",
      heightCm: 165,
      weightKg: 70,
      activityLevel: "lightly_active",
      goal: "lose_fat",
      pace: "moderate",
    });

    expect(estimate.bmr).toBe(1395);
    expect(estimate.maintenanceCalories).toBe(1920);
    expect(estimate.adjustmentCalories).toBe(300);
    expect(estimate.targetCalories).toBe(1620);
  });

  it("covers every goal, pace, and activity combination without invalid targets", () => {
    const activityLevels = [
      "sedentary",
      "lightly_active",
      "moderately_active",
      "very_active",
      "extra_active",
    ] as const;
    const scenarios = [
      { goal: "lose_fat", paces: ["slow", "moderate", "aggressive"] },
      { goal: "maintain", paces: [undefined] },
      { goal: "gain_muscle", paces: ["lean", "standard", "aggressive"] },
    ] as const;

    for (const activityLevel of activityLevels) {
      for (const scenario of scenarios) {
        for (const pace of scenario.paces) {
          const estimate = estimateCalories({
            age: 29,
            sex: "male",
            heightCm: 178,
            weightKg: 82,
            activityLevel,
            goal: scenario.goal,
            pace,
          });
          expect(estimate.targetCalories).toBeGreaterThanOrEqual(800);
          expect(estimate.targetCalories).toBeLessThanOrEqual(10000);
          expect(estimate.recommendedRange.min).toBeGreaterThanOrEqual(800);
          expect(estimate.recommendedRange.max).toBeLessThanOrEqual(10000);
        }
      }
    }
  });

  it("returns calculator estimates through the authenticated API", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const response = await request("http://localhost/v1/goals/calorie-estimate", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({
        age: 31,
        sex: "female",
        heightCm: 168,
        weightKg: 64,
        activityLevel: "moderately_active",
        goal: "gain_muscle",
        pace: "standard",
      }),
    });

    expect(response.status).toBe(200);
    const body = await response.json() as { targetCalories: number; warnings: string[] };
    expect(body.targetCalories).toBeGreaterThan(2000);
    expect(body.warnings).toEqual([]);
  });

  it("rejects recomposition as a calorie estimate goal", async () => {
    const { request } = buildTestApp();
    const auth = await registerAndAuth(request);

    const response = await request("http://localhost/v1/goals/calorie-estimate", {
      method: "POST",
      headers: auth.authHeader,
      body: JSON.stringify({
        age: 31,
        sex: "female",
        heightCm: 168,
        weightKg: 64,
        activityLevel: "moderately_active",
        goal: "recomposition",
      }),
    });

    expect(response.status).toBe(400);
  });
});
