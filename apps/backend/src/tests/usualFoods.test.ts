import { describe, expect, it } from "vitest";
import { buildTestApp, registerAndAuth } from "./testApp.js";

const usualFoodInput = {
  name: "House rice",
  canonicalName: "rice",
  brand: "Kitchen",
  barcode: "123456789",
  servingGrams: 100,
  nutrition: {
    calories: 360,
    proteinGrams: 7,
    carbsGrams: 79,
    fatGrams: 1,
  },
  nutrients: {
    saltGrams: 0.01,
  },
  aliases: ["daily rice"],
};

describe("usual foods", () => {
  it("creates, lists, updates, searches, and archives current-user usual foods", async () => {
    const { request } = buildTestApp();
    const userA = await registerAndAuth(request);
    const userB = await registerAndAuth(request, { email: "other@example.com" });

    const createdResponse = await request("http://localhost/v1/usual-foods", {
      method: "POST",
      headers: userA.authHeader,
      body: JSON.stringify(usualFoodInput),
    });
    const created = (await createdResponse.json()) as {
      output: {
        usualFood: {
          id: string;
          name: string;
          source?: string;
          aliases: string[];
          nutrients?: Record<string, unknown>;
        };
      };
    };

    expect(createdResponse.status).toBe(200);
    expect(created.output.usualFood.name).toBe("House rice");
    expect(created.output.usualFood.aliases).toEqual(["daily rice"]);
    expect(created.output.usualFood.nutrients).toEqual({ saltGrams: 0.01 });

    const listAResponse = await request("http://localhost/v1/usual-foods", {
      headers: userA.authHeader,
    });
    const listA = (await listAResponse.json()) as {
      output: { usualFoods: Array<{ id: string; name: string }> };
    };
    expect(listA.output.usualFoods.map((food) => food.name)).toEqual([
      "House rice",
    ]);

    const listBResponse = await request("http://localhost/v1/usual-foods", {
      headers: userB.authHeader,
    });
    const listB = (await listBResponse.json()) as {
      output: { usualFoods: Array<{ id: string; name: string }> };
    };
    expect(listB.output.usualFoods).toEqual([]);

    const userASearchResponse = await request(
      "http://localhost/v1/foods/search",
      {
        method: "POST",
        headers: { ...userA.authHeader, "accept-language": "en-US" },
        body: JSON.stringify({ query: "rice", limit: 5 }),
      },
    );
    const userASearch = (await userASearchResponse.json()) as {
      items: Array<{
        name: string;
        source: string;
        externalSource?: string;
        externalId?: string;
      }>;
    };
    expect(userASearch.items[0]).toMatchObject({
      name: "House rice",
      source: "user_custom",
      externalSource: "user_custom",
      externalId: created.output.usualFood.id,
    });
    expect(userASearch.items.map((item) => item.name)).toContain("Cooked rice");

    const userBSearchResponse = await request(
      "http://localhost/v1/foods/search",
      {
        method: "POST",
        headers: { ...userB.authHeader, "accept-language": "en-US" },
        body: JSON.stringify({ query: "rice", limit: 5 }),
      },
    );
    const userBSearch = (await userBSearchResponse.json()) as {
      items: Array<{ name: string }>;
    };
    expect(userBSearch.items.map((item) => item.name)).not.toContain(
      "House rice",
    );
    expect(userBSearch.items[0]?.name).toBe("Cooked rice");

    const updateResponse = await request(
      `http://localhost/v1/usual-foods/${created.output.usualFood.id}`,
      {
        method: "PUT",
        headers: userA.authHeader,
        body: JSON.stringify({
          name: "Updated house rice",
          aliases: ["updated rice"],
        }),
      },
    );
    const updated = (await updateResponse.json()) as {
      output: { usualFood: { name: string; aliases: string[] } };
    };
    expect(updateResponse.status).toBe(200);
    expect(updated.output.usualFood).toMatchObject({
      name: "Updated house rice",
      aliases: ["updated rice"],
    });

    const clearOptionalResponse = await request(
      `http://localhost/v1/usual-foods/${created.output.usualFood.id}`,
      {
        method: "PUT",
        headers: userA.authHeader,
        body: JSON.stringify({
          canonicalName: null,
          brand: null,
          barcode: null,
          aliases: [],
          nutrients: {},
        }),
      },
    );
    const cleared = (await clearOptionalResponse.json()) as {
      output: {
        usualFood: {
          canonicalName?: string;
          brand?: string;
          barcode?: string;
          aliases: string[];
          nutrients?: Record<string, unknown>;
        };
      };
    };
    expect(clearOptionalResponse.status).toBe(200);
    expect(cleared.output.usualFood).toMatchObject({
      aliases: [],
    });
    expect(cleared.output.usualFood.nutrients).toBeUndefined();
    expect(cleared.output.usualFood.canonicalName).toBeUndefined();
    expect(cleared.output.usualFood.brand).toBeUndefined();
    expect(cleared.output.usualFood.barcode).toBeUndefined();

    const crossUserUpdateResponse = await request(
      `http://localhost/v1/usual-foods/${created.output.usualFood.id}`,
      {
        method: "PUT",
        headers: userB.authHeader,
        body: JSON.stringify({ name: "Wrong user edit" }),
      },
    );
    expect(crossUserUpdateResponse.status).toBe(400);

    const deleteResponse = await request(
      `http://localhost/v1/usual-foods/${created.output.usualFood.id}`,
      {
        method: "DELETE",
        headers: userA.authHeader,
      },
    );
    const deleted = (await deleteResponse.json()) as {
      output: { deleted: boolean };
    };
    expect(deleted.output.deleted).toBe(true);

    const deletedSearchResponse = await request(
      "http://localhost/v1/foods/search",
      {
        method: "POST",
        headers: { ...userA.authHeader, "accept-language": "en-US" },
        body: JSON.stringify({ query: "updated rice", limit: 5 }),
      },
    );
    const deletedSearch = (await deletedSearchResponse.json()) as {
      items: Array<{ name: string }>;
    };
    expect(deletedSearch.items.map((item) => item.name)).not.toContain(
      "Updated house rice",
    );
  });

  it("finds usual food by partial match on food name", async () => {
    const { request } = buildTestApp();
    const user = await registerAndAuth(request);

    await request("http://localhost/v1/usual-foods", {
      method: "POST",
      headers: user.authHeader,
      body: JSON.stringify({
        name: "Papa cruda",
        canonicalName: "papa cruda",
        servingGrams: 100,
        nutrition: { calories: 77, proteinGrams: 2, carbsGrams: 17, fatGrams: 0.1 },
      }),
    });

    const searchResponse = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: { ...user.authHeader, "accept-language": "en-US" },
      body: JSON.stringify({ query: "cruda", limit: 5 }),
    });
    const search = (await searchResponse.json()) as {
      items: Array<{ name: string; source: string }>;
    };
    expect(search.items.map((item) => item.name)).toContain("Papa cruda");
    const papaItem = search.items.find((item) => item.name === "Papa cruda");
    expect(papaItem?.source).toBe("user_custom");
  });

  it("finds usual food with Spanish locale", async () => {
    const { request } = buildTestApp();
    const user = await registerAndAuth(request);

    await request("http://localhost/v1/usual-foods", {
      method: "POST",
      headers: user.authHeader,
      body: JSON.stringify({
        name: "Papa cruda",
        canonicalName: "papa cruda",
        servingGrams: 100,
        nutrition: { calories: 77, proteinGrams: 2, carbsGrams: 17, fatGrams: 0.1 },
      }),
    });

    const searchResponse = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: { ...user.authHeader, "accept-language": "es-ES" },
      body: JSON.stringify({ query: "papa", limit: 5 }),
    });
    const search = (await searchResponse.json()) as {
      items: Array<{ name: string; source: string }>;
    };
    expect(search.items.map((item) => item.name)).toContain("Papa cruda");
  });

  it("finds usual food by fuzzy match", async () => {
    const { request } = buildTestApp();
    const user = await registerAndAuth(request);

    await request("http://localhost/v1/usual-foods", {
      method: "POST",
      headers: user.authHeader,
      body: JSON.stringify({
        name: "Pollo asado",
        canonicalName: "pollo asado",
        servingGrams: 100,
        nutrition: { calories: 165, proteinGrams: 25, carbsGrams: 0, fatGrams: 7 },
      }),
    });

    const searchResponse = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: { ...user.authHeader, "accept-language": "en-US" },
      body: JSON.stringify({ query: "pollo asda", limit: 5 }),
    });
    const search = (await searchResponse.json()) as {
      items: Array<{ name: string }>;
    };
    expect(search.items.map((item) => item.name)).toContain("Pollo asado");
  });

  it("ranks usual food above non-user food when searching", async () => {
    const { request } = buildTestApp();
    const user = await registerAndAuth(request);

    await request("http://localhost/v1/usual-foods", {
      method: "POST",
      headers: user.authHeader,
      body: JSON.stringify({
        name: "White rice",
        canonicalName: "rice",
        servingGrams: 100,
        nutrition: { calories: 130, proteinGrams: 2.7, carbsGrams: 28, fatGrams: 0.3 },
      }),
    });

    const searchResponse = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: { ...user.authHeader, "accept-language": "en-US" },
      body: JSON.stringify({ query: "rice", limit: 5 }),
    });
    const search = (await searchResponse.json()) as {
      items: Array<{ name: string; source?: string }>;
    };
    const usualIndex = search.items.findIndex((item) => item.name === "White rice");
    const fixtureIndex = search.items.findIndex((item) => item.name === "Cooked rice");
    expect(usualIndex).toBeGreaterThanOrEqual(0);
    expect(fixtureIndex).toBeGreaterThanOrEqual(0);
    expect(usualIndex).toBeLessThan(fixtureIndex);
  });

  it("does not find usual food after name update with old search term", async () => {
    const { request } = buildTestApp();
    const user = await registerAndAuth(request);

    const createdResponse = await request("http://localhost/v1/usual-foods", {
      method: "POST",
      headers: user.authHeader,
      body: JSON.stringify({
        name: "Oatmeal",
        canonicalName: "oatmeal",
        servingGrams: 100,
        nutrition: { calories: 389, proteinGrams: 16.9, carbsGrams: 66.3, fatGrams: 6.9 },
      }),
    });
    const created = (await createdResponse.json()) as {
      output: { usualFood: { id: string } };
    };

    await request(`http://localhost/v1/usual-foods/${created.output.usualFood.id}`, {
      method: "PUT",
      headers: user.authHeader,
      body: JSON.stringify({
        name: "Steel-cut oats",
        canonicalName: null,
      }),
    });

    const searchResponse = await request("http://localhost/v1/foods/search", {
      method: "POST",
      headers: { ...user.authHeader, "accept-language": "en-US" },
      body: JSON.stringify({ query: "oatmeal", limit: 5 }),
    });
    const search = (await searchResponse.json()) as {
      items: Array<{ name: string }>;
    };
    expect(search.items.map((item) => item.name)).not.toContain("Steel-cut oats");
    // The fixture 'Oats' may still be found since it matches via normalizedName
  });

  it("uses usual food provenance when resolving meal proposal items", async () => {
    const { request } = buildTestApp();
    const user = await registerAndAuth(request);

    const createdResponse = await request("http://localhost/v1/usual-foods", {
      method: "POST",
      headers: user.authHeader,
      body: JSON.stringify(usualFoodInput),
    });
    const created = (await createdResponse.json()) as {
      output: { usualFood: { id: string } };
    };

    const proposalResponse = await request(
      "http://localhost/v1/meals/proposals",
      {
        method: "POST",
        headers: user.authHeader,
        body: JSON.stringify({
          text: "Add rice",
          mentions: [
            {
              originalText: "150 g rice",
              canonicalName: "rice",
              canonicalEnglishName: "rice",
              language: "en",
              quantity: 150,
              unit: "g",
              rawUnitText: "g",
              unitKind: "metric",
              confidence: 0.95,
            },
          ],
        }),
      },
    );
    const proposal = (await proposalResponse.json()) as {
      output: {
        proposal: {
          items: Array<{
            name: string;
            source: string;
            externalSource?: string;
            externalId?: string;
            canonicalName?: string;
          }>;
        };
      };
    };

    expect(proposalResponse.status).toBe(200);
    expect(proposal.output.proposal.items[0]).toMatchObject({
      name: "House rice",
      source: "user_custom",
      externalSource: "user_custom",
      externalId: created.output.usualFood.id,
      canonicalName: "rice",
    });
  });
});
