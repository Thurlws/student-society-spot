// Server errors to an error tracker that speaks Sentry's protocol (Sentry's EU region at
// de.sentry.io, or a self-hosted GlitchTip), without its SDK, so it works on every host the
// build targets. Nothing leaves the server unless SENTRY_DSN is set. Reports carry the error
// and the page's path, with email addresses, tokens and keys scrubbed; never request bodies,
// cookies, headers or user ids.

type Dsn = { endpoint: string; key: string };

/** https://<key>@<host>/<project> to where envelopes go. Null for anything else. */
export function parseDsn(dsn: string | undefined): Dsn | null {
  if (!dsn) return null;
  try {
    const u = new URL(dsn);
    const project = u.pathname.replace(/^\/+|\/+$/g, "");
    // Plain http only to a tracker on this machine, for trying it out.
    const local = u.hostname === "localhost" || u.hostname === "127.0.0.1";
    if (!(u.protocol === "https:" || (local && u.protocol === "http:"))) return null;
    if (!u.username || !/^\d+$/.test(project)) return null;
    return { endpoint: `${u.protocol}//${u.host}/api/${project}/envelope/`, key: u.username };
  } catch {
    return null;
  }
}

/** Removes email addresses, JWTs, bearer tokens and Supabase keys from text. */
export function scrub(text: string) {
  return text
    .replace(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, "[email]")
    .replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[token]")
    .replace(/(Bearer\s+)\S+/gi, "$1[token]")
    .replace(/(sb_(?:secret|publishable)_)[A-Za-z0-9_-]+/g, "$1[key]");
}

/** V8 stack lines as Sentry frames, oldest call first. */
function frames(stack: string | undefined) {
  return (stack ?? "")
    .split("\n")
    .map((l) => l.match(/^\s*at (?:(.+?) \()?(.+?):(\d+):(\d+)\)?$/))
    .filter((m): m is RegExpMatchArray => !!m)
    .map((m) => ({
      function: m[1] ?? "?",
      filename: scrub(m[2]!),
      lineno: Number(m[3]),
      colno: Number(m[4]),
    }))
    .reverse();
}

export type ErrorContext = {
  /** Where it came from: the server, or a browser through reportClientError. */
  source: "server" | "browser";
  /** The page's path, without the query string (which can hold sign-in tokens). */
  route?: string;
  /** What the person was doing, for alert rules: "sign-in" for failed sign-in emails. */
  area?: string;
};

/** One error as a Sentry envelope: a header line, an item header line and the event. */
export function buildEnvelope(
  error: unknown,
  context: ErrorContext,
  environment: string,
  now = new Date(),
  eventId = crypto.randomUUID().replace(/-/g, ""),
) {
  const e = error instanceof Error ? error : new Error(String(error));
  const stack = frames(e.stack);
  const event = {
    event_id: eventId,
    timestamp: now.toISOString(),
    platform: "javascript",
    level: "error",
    environment,
    tags: {
      source: context.source,
      ...(context.area ? { area: context.area } : {}),
    },
    ...(context.route ? { transaction: scrub(context.route.split("?")[0]!) } : {}),
    exception: {
      values: [
        {
          type: e.name || "Error",
          value: scrub(e.message).slice(0, 2000),
          ...(stack.length ? { stacktrace: { frames: stack } } : {}),
        },
      ],
    },
  };
  return [
    JSON.stringify({ event_id: eventId, sent_at: now.toISOString() }),
    JSON.stringify({ type: "event" }),
    JSON.stringify(event),
  ].join("\n");
}

// A loop of failures shouldn't use up the tracker's quota: at most 20 reports a minute per
// server instance.
const recent: number[] = [];
export function allowReport(now = Date.now()) {
  while (recent.length && now - recent[0]! > 60_000) recent.shift();
  if (recent.length >= 20) return false;
  recent.push(now);
  return true;
}

/** Sends one error to the tracker. Never throws: reporting must not break the request. */
export async function reportError(error: unknown, context: ErrorContext) {
  const dsn = parseDsn(process.env["SENTRY_DSN"]);
  if (!dsn || !allowReport()) return;
  try {
    await fetch(dsn.endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/x-sentry-envelope",
        "x-sentry-auth": `Sentry sentry_version=7, sentry_key=${dsn.key}, sentry_client=socconnect/1`,
      },
      body: buildEnvelope(error, context, process.env["SENTRY_ENVIRONMENT"] || "production"),
      signal: AbortSignal.timeout(3000),
    });
  } catch {
    // The tracker being down is not worth a second error.
  }
}
