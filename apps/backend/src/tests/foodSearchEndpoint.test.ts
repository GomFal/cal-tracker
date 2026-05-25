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
