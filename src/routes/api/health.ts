import { createFileRoute } from "@tanstack/react-router";

// For an uptime monitor: 200 when the app server is up and the database answers, 503 when
// it doesn't. Public, so it says nothing else.
export const Route = createFileRoute("/api/health")({
  server: {
    handlers: {
      GET: async () => {
        const database = await databaseAnswers();
        return Response.json(
          { status: database ? "ok" : "down", database: database ? "ok" : "unreachable" },
          { status: database ? 200 : 503, headers: { "cache-control": "no-store" } },
        );
      },
    },
  },
});

/** One cheap call through the same API the app uses, with the public key. */
async function databaseAnswers() {
  const url = process.env["SUPABASE_URL"];
  const key = process.env["SUPABASE_PUBLISHABLE_KEY"];
  if (!url || !key) return false;
  try {
    const r = await fetch(`${url}/rest/v1/rpc/email_domain_allowed`, {
      method: "POST",
      headers: { apikey: key, "content-type": "application/json" },
      body: JSON.stringify({ _email: "health@example.com" }),
      signal: AbortSignal.timeout(5000),
    });
    return r.ok;
  } catch {
    return false;
  }
}
