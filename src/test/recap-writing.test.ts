import { describe, expect, it } from "vitest";
import { recapStillWriting } from "@/lib/api/fetch";

const summary = (source: "ai" | "fallback") => ({
  source,
  overview: "",
  topics: [],
  decisions: [],
  actionItems: [],
});

describe("recapStillWriting", () => {
  const now = Date.parse("2026-10-17T21:00:30Z");
  it("waits for the AI only for a new recap that still has the basic summary", () => {
    const at = "2026-10-17T21:00:10Z";
    expect(recapStillWriting({ summary: summary("fallback"), createdAt: at }, now)).toBe(true);
    expect(recapStillWriting({ summary: summary("ai"), createdAt: at }, now)).toBe(false);
  });
  it("gives up after a minute, when the AI must have failed", () => {
    const at = "2026-10-17T20:59:00Z";
    expect(recapStillWriting({ summary: summary("fallback"), createdAt: at }, now)).toBe(false);
    expect(recapStillWriting(null, now)).toBe(false);
  });
});
