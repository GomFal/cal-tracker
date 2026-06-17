import { describe, expect, it } from "vitest";
import { buildTestApp, registerAndAuth } from "./testApp.js";

describe("food search endpoint", () => {
  it("returns limited food results and candidate groups", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: { ...authHeader, "accept-language": "en-US" },
      body: JSON.stringify({ query: "bread", limit: 1 }),
    });
    const body = (await response.json()) as {
      items: Array<{ name: string }>;
      candidateGroups?: Array<{ candidates: Array<{ name: string }> }>;
    };

    expect(response.status).toBe(200);
    expect(body.items).toHaveLength(1);
    expect(body.items[0]?.name).toBe("Bread");
    expect(body.candidateGroups).toHaveLength(1);
    expect(body.candidateGroups?.[0]?.candidates).toHaveLength(1);
  });

  it("prefers exact local Open Food Facts matches over decorated product names", async () => {
    const { request, repository } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);
    await repository.upsertFoodItem({
      name: "Honey Pork Ribs",
      normalizedName: "honey pork ribs",
      canonicalName: "Honey Pork Ribs",
      brand: "The Standard Meat Co",
      barcode: "2222222222222",
      source: "openfoodfacts",
      externalSource: "openfoodfacts",
      externalId: "honey-pork-ribs",
      dataType: "Open Food Facts",
      foodKey: "es",
      servingGrams: 100,
      calories: 230,
      proteinGrams: 14,
      carbsGrams: 12,
      fatGrams: 14,
    });
    await repository.upsertFoodItem({
      name: "Pork ribs",
      normalizedName: "pork ribs",
      canonicalName: "Pork ribs",
      barcode: "3333333333333",
      source: "openfoodfacts",
      externalSource: "openfoodfacts",
      externalId: "pork-ribs",
      dataType: "Open Food Facts",
      foodKey: "en",
      servingGrams: 100,
      calories: 193,
      proteinGrams: 12.14,
      carbsGrams: 17.86,
      fatGrams: 9.29,
    });

    const response = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: { ...authHeader, "accept-language": "es-ES" },
      body: JSON.stringify({ query: "pork ribs", limit: 5 }),
    });
    const body = (await response.json()) as {
      items: Array<{ name: string }>;
      candidateGroups?: Array<{ candidates: Array<{ name: string }> }>;
    };

    expect(response.status).toBe(200);
    expect(body.items[0]?.name).toBe("Pork ribs");
    expect(body.candidateGroups?.[0]?.candidates[0]?.name).toBe("Pork ribs");
    expect(body.candidateGroups?.[0]?.candidates.map((candidate) => candidate.name)).toContain("Honey Pork Ribs");
  });

  it("uses the same full-corpus search for broad and brand-token ingredient queries", async () => {
    const { request, repository } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);
    await repository.upsertFoodItem({
      name: "Arroz",
      normalizedName: "arroz",
      canonicalName: "arroz",
      source: "usda_fdc",
      externalSource: "usda_fdc",
      externalId: "generic-arroz",
      dataType: "SR Legacy",
      foodKey: "es",
      servingGrams: 100,
      calories: 130,
      proteinGrams: 2.7,
      carbsGrams: 28,
      fatGrams: 0.3,
    });
    await repository.upsertFoodItem({
      name: "Arroz Hacendado",
      normalizedName: "arroz hacendado",
      canonicalName: "arroz hacendado",
      brand: "Hacendado",
      barcode: "8480000000017",
      source: "openfoodfacts",
      externalSource: "openfoodfacts",
      externalId: "arroz-hacendado",
      dataType: "Open Food Facts",
      foodKey: "es",
      servingGrams: 100,
      calories: 131,
      proteinGrams: 2.6,
      carbsGrams: 28.1,
      fatGrams: 0.4,
    });

    const broadResponse = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: { ...authHeader, "accept-language": "es-ES" },
      body: JSON.stringify({ query: "arroz", limit: 5 }),
    });
    const broadBody = (await broadResponse.json()) as {
      items: Array<{ name: string }>;
      candidateGroups?: Array<{ candidates: Array<{ name: string }> }>;
    };

    expect(broadResponse.status).toBe(200);
    expect(broadBody.items[0]?.name).toBe("Arroz");
    expect(broadBody.candidateGroups?.[0]?.candidates.map((candidate) => candidate.name)).toContain("Arroz Hacendado");

    const brandResponse = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: { ...authHeader, "accept-language": "es-ES" },
      body: JSON.stringify({ query: "arroz hacendado", limit: 5 }),
    });
    const brandBody = (await brandResponse.json()) as {
      items: Array<{ name: string }>;
      candidateGroups?: Array<{ candidates: Array<{ name: string }> }>;
    };

    expect(brandResponse.status).toBe(200);
    expect(brandBody.items[0]?.name).toBe("Arroz Hacendado");
    expect(brandBody.candidateGroups?.[0]?.candidates[0]?.name).toBe("Arroz Hacendado");
  });

  it("rejects empty search queries", async () => {
    const { request } = buildTestApp();
    const { authHeader } = await registerAndAuth(request);

    const response = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: authHeader,
      body: JSON.stringify({ query: "   " }),
    });

    expect(response.status).toBe(400);
  });
});
