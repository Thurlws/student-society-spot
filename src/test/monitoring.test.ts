import { afterEach, describe, expect, it, vi } from "vitest";
import {
  allowReport,
  buildEnvelope,
  buildLogEnvelope,
  flushLogs,
  log,
  logEntry,
  parseDsn,
  scrub,
  type LogEntry,
} from "@/lib/monitoring.server";

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

  it("marks warnings and tags the server function", () => {
    const body = buildEnvelope(
      new Error("Out of credits"),
      { source: "server", area: "ai", level: "warning", fn: "askSociety" },
      "production",
    ).split("\n")[2]!;
    const event = JSON.parse(body);
    expect(event.level).toBe("warning");
    expect(event.tags).toEqual({ source: "server", area: "ai", fn: "askSociety" });
  });

  it("writes one scrubbed JSON line per log entry", () => {
    const spy = vi.spyOn(console, "log").mockImplementation(() => {});
    log("info", "server_fn", { fn: "joinSociety", ms: 42 }, new Error("for jane@mytudublin.ie"));
    const line = JSON.parse(spy.mock.calls[0]![0] as string);
    spy.mockRestore();
    expect(line).toMatchObject({ level: "info", event: "server_fn", fn: "joinSociety", ms: 42 });
    expect(line.error).toBe("for [email]");
  });

  it("sends at most 20 reports a minute", () => {
    const t = 1_000_000_000;
    const allowed = Array.from({ length: 25 }, () => allowReport(t)).filter(Boolean).length;
    expect(allowed).toBe(20);
    expect(allowReport(t + 61_000)).toBe(true);
  });
});

describe("Logs to Sentry", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  /** The envelopes posted to the tracker, as [item header, payload] pairs. */
  function captureFetch() {
    const sent: { item: { type: string; item_count?: number }; payload: unknown }[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (_url: string, init: { body: string }) => {
        const [, item, payload] = init.body.split("\n");
        sent.push({ item: JSON.parse(item!), payload: JSON.parse(payload!) });
        return new Response("{}");
      }),
    );
    return sent;
  }

  it("turns a log line into Sentry's format, typed and scrubbed", () => {
    const entry = logEntry(
      "warn",
      "server_fn.failed",
      { fn: "joinSociety", ms: 42, ratio: 0.5, ok: false, empty: null, who: "jane@mytudublin.ie" },
      "No row for jane@mytudublin.ie",
      "production",
      1_760_000_000_123,
    );
    expect(entry.timestamp).toBe(1_760_000_000.123);
    expect(entry.trace_id).toMatch(/^[0-9a-f]{32}$/);
    expect(entry.level).toBe("warn");
    expect(entry.body).toBe("server_fn.failed: No row for [email]");
    expect(entry.attributes).toMatchObject({
      event: { value: "server_fn.failed", type: "string" },
      fn: { value: "joinSociety", type: "string" },
      ms: { value: 42, type: "integer" },
      ratio: { value: 0.5, type: "double" },
      ok: { value: false, type: "boolean" },
      who: { value: "[email]", type: "string" },
      error: { value: "No row for [email]", type: "string" },
      "sentry.environment": { value: "production", type: "string" },
    });
    expect(entry.attributes).not.toHaveProperty("empty");
  });

  it("numbers lines that share a millisecond, and restarts when it changes", () => {
    const seq = (ms: number) =>
      logEntry("info", "x", {}, undefined, "production", ms).attributes[
        "sentry.timestamp.sequence"
      ]!.value;
    expect([seq(5), seq(5), seq(5), seq(6), seq(6)]).toEqual([0, 1, 2, 0, 1]);
  });

  it("builds a log envelope", () => {
    const entry = logEntry("info", "server_fn", { fn: "a" }, undefined, "production");
    const [header, item, payload] = buildLogEnvelope(
      [entry, entry],
      new Date("2026-10-16T10:00:00Z"),
    ).split("\n");
    expect(JSON.parse(header!)).toEqual({ sent_at: "2026-10-16T10:00:00.000Z" });
    expect(JSON.parse(item!)).toEqual({
      type: "log",
      item_count: 2,
      content_type: "application/vnd.sentry.items.log+json",
    });
    expect(JSON.parse(payload!)).toEqual({ version: 2, items: [entry, entry] });
  });

  it("sends the request's lines in envelopes of at most 100, with warnings as issues too", async () => {
    vi.stubEnv("SENTRY_DSN", "https://abc@o1.ingest.de.sentry.io/1");
    vi.spyOn(console, "log").mockImplementation(() => {});
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const sent = captureFetch();
    for (let i = 0; i < 149; i++) log("info", "server_fn", { fn: "f", ms: i });
    log("warn", "ai.fallback", { area: "ai" });
    await flushLogs();
    const logs = sent.filter((s) => s.item.type === "log");
    expect(logs.map((s) => s.item.item_count)).toEqual([100, 50]);
    expect(sent.filter((s) => s.item.type === "event")).toHaveLength(1);
    // Nothing is left for the next request.
    sent.length = 0;
    await flushLogs();
    expect(sent).toHaveLength(0);
  });

  it("gives a warning's log line and its issue the same trace", async () => {
    vi.stubEnv("SENTRY_DSN", "https://abc@o1.ingest.de.sentry.io/1");
    vi.spyOn(console, "warn").mockImplementation(() => {});
    const sent = captureFetch();
    log("warn", "server_fn.slow", { fn: "f", ms: 6000 });
    await flushLogs();
    const line = (sent.find((s) => s.item.type === "log")!.payload as { items: LogEntry[] })
      .items[0]!;
    const event = sent.find((s) => s.item.type === "event")!.payload as {
      contexts: { trace: { trace_id: string; span_id: string } };
    };
    expect(line.trace_id).toMatch(/^[0-9a-f]{32}$/);
    expect(event.contexts.trace.trace_id).toBe(line.trace_id);
    expect(event.contexts.trace.span_id).toMatch(/^[0-9a-f]{16}$/);
  });

  it("keeps everything on the server without SENTRY_DSN", async () => {
    vi.stubEnv("SENTRY_DSN", "");
    vi.spyOn(console, "log").mockImplementation(() => {});
    const sent = captureFetch();
    log("info", "server_fn", { fn: "f", ms: 1 });
    await flushLogs();
    expect(sent).toHaveLength(0);
  });
});
