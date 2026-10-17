import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { APICallError, simulateReadableStream } from "ai";
import { MockLanguageModelV4 } from "ai/test";

// The gateway refuses every call in a test with this status; 0 answers "Fits." instead.
let status = 402;
const refuse = (statusCode: number) =>
  new APICallError({
    message: "Refused",
    url: "https://ai.gateway.lovable.dev/v1/responses",
    requestBodyValues: {},
    statusCode,
  });
const model = new MockLanguageModelV4({
  doStream: async ({ providerOptions }) => {
    if (status) throw refuse(status);
    const tokens = { total: 1, noCache: 1, cacheRead: 0, cacheWrite: 0 };
    return {
      stream: simulateReadableStream({
        chunks: [
          { type: "stream-start", warnings: [] },
          { type: "text-start", id: "t" },
          { type: "text-delta", id: "t", delta: "Fits." },
          { type: "text-end", id: "t" },
          {
            type: "finish",
            finishReason: { unified: "stop", raw: "stop" },
            usage: { inputTokens: tokens, outputTokens: { total: 1, text: 1, reasoning: 0 } },
          },
        ],
      }),
    };
  },
});
vi.mock("@ai-sdk/openai", () => ({ createOpenAI: () => ({ responses: () => model }) }));

const { aiObject, aiText } = await import("@/lib/ai.server");
const { z } = await import("zod");

describe("AI gateway errors", () => {
  beforeAll(() => vi.stubEnv("LOVABLE_API_KEY", "test"));
  afterAll(() => vi.unstubAllEnvs());

  it("asks for a quick answer with the least reasoning the model takes, in one call", async () => {
    status = 0;
    const before = model.doStreamCalls.length;
    await expect(aiText("x", [{ role: "user", content: "x" }], { quick: true })).resolves.toBe(
      "Fits.",
    );
    expect(model.doStreamCalls.slice(before)).toHaveLength(1);
    expect(model.doStreamCalls.at(-1)?.providerOptions?.["openai"]?.["reasoningEffort"]).toBe(
      "low",
    );
  });

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
