import { createFileRoute } from "@tanstack/react-router";

// For an uptime monitor: 200 when the app server is up and both the database and sign-in
// (Supabase Auth) answer, 503 when either doesn't. Public, so it says nothing else.
export const Route = createFileRoute("/api/health")({
  server: {
    handlers: {
      GET: async () => {
        const [database, auth] = await Promise.all([databaseAnswers(), authAnswers()]);
        const state = (up: boolean) => (up ? "ok" : "unreachable");
        return Response.json(
          {
            status: database && auth ? "ok" : "down",
            database: state(database),
            auth: state(auth),
          },
          { status: database && auth ? 200 : 503, headers: { "cache-control": "no-store" } },
        );
      },
    },
  },
});

/** Supabase Auth's own health check: with it down nobody can sign in, though pages still load. */
async function authAnswers() {
  const url = process.env["SUPABASE_URL"];
  const key = process.env["SUPABASE_PUBLISHABLE_KEY"];
  if (!url || !key) return false;
  try {
    const r = await fetch(`${url}/auth/v1/health`, {
      headers: { apikey: key },
      signal: AbortSignal.timeout(5000),
    });
    return r.ok;
  } catch {
    return false;
  }
}

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
