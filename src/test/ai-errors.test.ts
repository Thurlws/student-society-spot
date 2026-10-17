import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { APICallError } from "ai";
import { MockLanguageModelV4 } from "ai/test";

// The gateway answers with this status for every call in a test.
let status = 402;
const model = new MockLanguageModelV4({
  doStream: async () => {
    throw new APICallError({
      message: "Refused",
      url: "https://ai.gateway.lovable.dev/v1/responses",
      requestBodyValues: {},
      statusCode: status,
    });
  },
});
vi.mock("@ai-sdk/openai", () => ({ createOpenAI: () => ({ responses: () => model }) }));

const { aiObject, aiText } = await import("@/lib/ai.server");
const { z } = await import("zod");

describe("AI gateway errors", () => {
  beforeAll(() => vi.stubEnv("LOVABLE_API_KEY", "test"));
  afterAll(() => vi.unstubAllEnvs());

  // streamText alone reports every failure as "No output generated" with no status, so
  // safeError never paused AI for 402/403.
  it.each([402, 403, 429])("keep the gateway's %i", async (code) => {
    status = code;
    await expect(aiText("x", [{ role: "user", content: "x" }])).rejects.toMatchObject({
      status: code,
    });
    await expect(aiObject("x", "x", z.object({ a: z.string() }))).rejects.toMatchObject({
      status: code,
    });
  });

  it("explains a busy gateway", async () => {
    status = 429;
    await expect(aiText("x", [{ role: "user", content: "x" }])).rejects.toThrow(/busy/);
  });
});
