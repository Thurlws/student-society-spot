import { describe, expect, it } from "vitest";
import { allowReport, buildEnvelope, parseDsn, scrub } from "@/lib/monitoring.server";

describe("Error reporting", () => {
  it("reads a Sentry DSN, and refuses anything else", () => {
    expect(parseDsn("https://abc123@o1.ingest.de.sentry.io/4507")).toEqual({
      endpoint: "https://o1.ingest.de.sentry.io/api/4507/envelope/",
      key: "abc123",
    });
    expect(parseDsn(undefined)).toBeNull();
    expect(parseDsn("not a url")).toBeNull();
    expect(parseDsn("http://abc@tracker.example.com/1")).toBeNull();
    expect(parseDsn("https://tracker.example.com/1")).toBeNull();
  });

  it("scrubs addresses, tokens and keys", () => {
    expect(
      scrub(
        "jane.doe@mytudublin.ie sent Bearer abc.def and eyJhbGciOi.eyJzdWIi.c2lnbmF0dXJl with sb_secret_N7UND0Ugj",
      ),
    ).toBe("[email] sent Bearer [token] and [token] with sb_secret_[key]");
  });

  it("builds an envelope without the query string or personal data", () => {
    const error = new Error("No row for jane@mytudublin.ie");
    error.stack =
      "Error: x\n    at load (/app/src/lib/api/fetch.ts:12:3)\n    at /app/src/server.ts:40:9";
    const [header, item, body] = buildEnvelope(
      error,
      { source: "server", route: "/auth/confirm?token_hash=secret", area: "sign-in" },
      "production",
      new Date("2026-10-16T10:00:00Z"),
      "abc",
    ).split("\n");
    expect(JSON.parse(header!)).toEqual({ event_id: "abc", sent_at: "2026-10-16T10:00:00.000Z" });
    expect(JSON.parse(item!)).toEqual({ type: "event" });
    const event = JSON.parse(body!);
    expect(event.transaction).toBe("/auth/confirm");
    expect(event.tags).toEqual({ source: "server", area: "sign-in" });
    expect(event.exception.values[0].value).toBe("No row for [email]");
    expect(
      event.exception.values[0].stacktrace.frames.map((f: { lineno: number }) => f.lineno),
    ).toEqual([40, 12]);
  });

  it("sends at most 20 reports a minute", () => {
    const t = 1_000_000_000;
    const allowed = Array.from({ length: 25 }, () => allowReport(t)).filter(Boolean).length;
    expect(allowed).toBe(20);
    expect(allowReport(t + 61_000)).toBe(true);
  });
});
