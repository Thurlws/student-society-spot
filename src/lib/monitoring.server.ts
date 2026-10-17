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
  /** "warning" for a feature that's degraded but still works; errors otherwise. */
  level?: "error" | "warning";
  /** The server function it came from, as a tag to filter and group by. */
  fn?: string;
  /** The trace id of the log line it came from, so Sentry shows the two together. */
  traceId?: string;
};

/** A random id of `bytes` bytes in hex: 16 for trace ids, 8 for span ids. */
const randomId = (bytes: number) =>
  Array.from(crypto.getRandomValues(new Uint8Array(bytes)), (b) =>
    b.toString(16).padStart(2, "0"),
  ).join("");

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
    level: context.level ?? "error",
    environment,
    tags: {
      source: context.source,
      ...(context.area ? { area: context.area } : {}),
      ...(context.fn ? { fn: context.fn } : {}),
    },
    ...(context.route ? { transaction: scrub(context.route.split("?")[0]!) } : {}),
    ...(context.traceId
      ? { contexts: { trace: { trace_id: context.traceId, span_id: randomId(8) } } }
      : {}),
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

const environment = () => process.env["SENTRY_ENVIRONMENT"] || "production";

// Sends still on their way, so the end of a request can wait for them (flushLogs).
const sending = new Set<Promise<void>>();
function track(p: Promise<void>) {
  sending.add(p);
  void p.finally(() => sending.delete(p));
  return p;
}

/** Posts one envelope. Never throws: the tracker being down is not worth a second error. */
function post(dsn: Dsn, body: string) {
  return track(
    fetch(dsn.endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/x-sentry-envelope",
        "x-sentry-auth": `Sentry sentry_version=7, sentry_key=${dsn.key}, sentry_client=socconnect/1`,
      },
      body,
      signal: AbortSignal.timeout(3000),
    }).then(
      () => undefined,
      () => undefined,
    ),
  );
}

/** Sends one error to the tracker. Never throws: reporting must not break the request. */
export async function reportError(error: unknown, context: ErrorContext) {
  const dsn = parseDsn(process.env["SENTRY_DSN"]);
  if (!dsn || !allowReport()) return;
  await post(dsn, buildEnvelope(error, context, environment()));
}

type LogFields = Record<string, string | number | boolean | null | undefined>;
type LogLevel = "info" | "warn" | "error";
type Attribute =
  | { value: string; type: "string" }
  | { value: number; type: "integer" | "double" }
  | { value: boolean; type: "boolean" };
export type LogEntry = {
  timestamp: number;
  trace_id: string;
  level: LogLevel;
  body: string;
  attributes: Record<string, Attribute>;
};

function attribute(value: string | number | boolean): Attribute {
  if (typeof value === "string") return { value: scrub(value), type: "string" };
  if (typeof value === "boolean") return { value, type: "boolean" };
  return { value, type: Number.isInteger(value) ? "integer" : "double" };
}

// Workers freeze the clock while a request runs, so log lines can share a millisecond; Sentry
// orders those by this counter, which restarts whenever the millisecond changes.
let lastMs = -1;
let sequence = 0;

/** A log line in Sentry's log format, with the same fields as the JSON line. */
export function logEntry(
  level: LogLevel,
  event: string,
  fields: LogFields,
  detail: string | undefined,
  env: string,
  now = Date.now(),
  traceId = randomId(16),
): LogEntry {
  sequence = now === lastMs ? sequence + 1 : 0;
  lastMs = now;
  const attributes: Record<string, Attribute> = {
    event: attribute(event),
    "sentry.environment": attribute(env),
    "sentry.sdk.name": attribute("socconnect"),
    "sentry.sdk.version": attribute("1"),
    "sentry.timestamp.sequence": attribute(sequence),
  };
  for (const [key, value] of Object.entries(fields))
    if (value != null && !(typeof value === "number" && !Number.isFinite(value)))
      attributes[key] = attribute(value);
  if (detail) attributes["error"] = attribute(detail.slice(0, 500));
  return {
    timestamp: now / 1000,
    trace_id: traceId,
    level,
    body: scrub(detail ? `${event}: ${detail.slice(0, 500)}` : event),
    attributes,
  };
}

/** Up to 100 log lines as one Sentry envelope (its limit per envelope). */
export function buildLogEnvelope(entries: LogEntry[], now = new Date()) {
  return [
    JSON.stringify({ sent_at: now.toISOString() }),
    JSON.stringify({
      type: "log",
      item_count: entries.length,
      content_type: "application/vnd.sentry.items.log+json",
    }),
    JSON.stringify({ version: 2, items: entries }),
  ].join("\n");
}

// Log lines waiting for the end of the request. Capped, so a burst can't use up memory.
const queue: LogEntry[] = [];
const MAX_QUEUED = 1000;

/**
 * Sends the waiting log lines to the tracker, and waits for them and for any error reports
 * still on their way. src/server.ts calls it after each request, inside waitUntil on Workers,
 * so nothing is cut off when the response goes out. Never throws.
 */
export async function flushLogs() {
  const dsn = parseDsn(process.env["SENTRY_DSN"]);
  while (queue.length) {
    const batch = queue.splice(0, 100);
    if (dsn) void post(dsn, buildLogEnvelope(batch));
  }
  await Promise.all([...sending]);
}

/**
 * One structured line in the server's log (JSON, scrubbed), for the host's log viewer and, when
 * SENTRY_DSN is set, Sentry's Logs. Warnings and errors also go to the error tracker as issues,
 * so someone hears about them. Fields describe what happened (event, function, area, status,
 * counts, milliseconds); never put email addresses, names, message text or ids of people in them.
 */
export function log(
  level: "info" | "warn" | "error",
  event: string,
  fields: LogFields = {},
  error?: unknown,
) {
  const detail = error instanceof Error ? error.message : error != null ? String(error) : undefined;
  const line = scrub(
    JSON.stringify({
      t: new Date().toISOString(),
      level,
      event,
      ...fields,
      ...(detail ? { error: detail.slice(0, 500) } : {}),
    }),
  );
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
  // The log line and the issue it raises share a trace id; otherwise each got its own and
  // Sentry couldn't connect them.
  const traceId = randomId(16);
  if (process.env["SENTRY_DSN"] && queue.length < MAX_QUEUED)
    queue.push(logEntry(level, event, fields, detail, environment(), Date.now(), traceId));
  if (level === "info") return;
  const reported = new Error(detail ? `${event}: ${detail}` : event);
  reported.name = event;
  if (error instanceof Error && error.stack)
    reported.stack = `${reported.name}: ${reported.message}\n${error.stack.split("\n").slice(1).join("\n")}`;
  void reportError(reported, {
    source: "server",
    area: typeof fields["area"] === "string" ? fields["area"] : (event.split(".")[0] ?? event),
    level: level === "warn" ? "warning" : "error",
    traceId,
    ...(typeof fields["fn"] === "string" ? { fn: fields["fn"] } : {}),
  });
}

/** Compares two strings without leaking how much of them matched through timing. */
async function sameSecret(a: string, b: string) {
  const digest = async (s: string) =>
    new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
  const [x, y] = await Promise.all([digest(a), digest(b)]);
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x[i]! ^ y[i]!;
  return diff === 0;
}

/**
 * For the monitoring endpoints: null when the request carries `Authorization: Bearer
 * <MONITORING_TOKEN>`, otherwise the response to send. Without a token set, they don't exist.
 */
export async function refuseWithoutMonitoringToken(request: Request) {
  const token = process.env["MONITORING_TOKEN"];
  if (!token) return new Response("Not found", { status: 404 });
  if (!(await sameSecret(request.headers.get("authorization") ?? "", `Bearer ${token}`)))
    return new Response("Unauthorized", { status: 401 });
  return null;
}
