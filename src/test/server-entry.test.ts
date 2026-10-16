import { afterEach, describe, expect, it, vi } from "vitest";
import { log } from "@/lib/monitoring.server";

// The app itself, as a stand-in that logs one line per request.
vi.mock("@tanstack/react-start/server-entry", () => ({
  default: {
    fetch: async () => {
      log("info", "server_fn", { fn: "joinSociety", ms: 12 });
      return new Response("ok");
    },
  },
}));

describe("Server entry", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  async function run(handOver: "request" | "ctx") {
    vi.stubEnv("SENTRY_DSN", "https://abc@o1.ingest.de.sentry.io/1");
    vi.spyOn(console, "log").mockImplementation(() => {});
    const bodies: string[] = [];
    vi.stubGlobal(
      "fetch",
      vi.fn(async (_url: string, init: { body: string }) => {
        bodies.push(init.body);
        return new Response("{}");
      }),
    );
    const pending: Promise<unknown>[] = [];
    const waitUntil = (p: Promise<unknown>) => pending.push(p);
    const request = Object.assign(
      new Request("https://app.example/_serverFn/x"),
      handOver === "request" ? { waitUntil } : {},
    );
    const { default: server } = await import("@/server");
    const response = await server.fetch(
      request,
      {},
      handOver === "ctx" ? { waitUntil } : undefined,
    );
    expect(await response.text()).toBe("ok");
    expect(pending).toHaveLength(1);
    await Promise.all(pending);
    expect(bodies).toHaveLength(1);
    const payload = JSON.parse(bodies[0]!.split("\n")[2]!);
    expect(payload.items[0]).toMatchObject({
      level: "info",
      body: "server_fn",
      attributes: { fn: { value: "joinSociety", type: "string" } },
    });
  }

  // Nitro's Cloudflare entry puts waitUntil on the request; a plain Workers entry passes ctx.
  it("sends the request's log lines after the response, inside the request's waitUntil", () =>
    run("request"));
  it("uses ctx.waitUntil when the host passes it", () => run("ctx"));
});
