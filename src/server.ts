import "./lib/error-capture";

import { consumeLastCapturedError } from "./lib/error-capture";
import { renderErrorPage } from "./lib/error-page";
import { flushLogs, reportError } from "./lib/monitoring.server";

type ServerEntry = {
  fetch: (request: Request, env: unknown, ctx: unknown) => Promise<Response> | Response;
};

let serverEntryPromise: Promise<ServerEntry> | undefined;

async function getServerEntry(): Promise<ServerEntry> {
  if (!serverEntryPromise) {
    serverEntryPromise = import("@tanstack/react-start/server-entry").then(
      (m) => (m.default ?? m) as ServerEntry,
    );
  }
  return serverEntryPromise;
}

// h3 swallows in-handler throws into a normal 500 Response with body
// {"unhandled":true,"message":"HTTPError"} — try/catch alone never fires for those.
async function normalizeCatastrophicSsrResponse(
  response: Response,
  report: (error: unknown) => void,
): Promise<Response> {
  if (response.status < 500) return response;
  const contentType = response.headers.get("content-type") ?? "";
  if (!contentType.includes("application/json")) return response;

  const body = await response.clone().text();
  if (!isH3SwallowedErrorBody(body)) return response;

  const error = consumeLastCapturedError() ?? new Error(`h3 swallowed SSR error: ${body}`);
  console.error(error);
  report(error);
  return new Response(renderErrorPage(), {
    status: 500,
    headers: { "content-type": "text/html; charset=utf-8" },
  });
}

function isH3SwallowedErrorBody(body: string): boolean {
  try {
    const payload = JSON.parse(body) as { unhandled?: unknown; message?: unknown };
    return payload.unhandled === true && payload.message === "HTTPError";
  } catch {
    return false;
  }
}

export default {
  async fetch(request: Request, env: unknown, ctx: unknown) {
    // On Workers, waitUntil keeps reports and log lines going after the response is sent. Nitro
    // hands it over on the request rather than as ctx.
    type WaitUntil = (p: Promise<unknown>) => void;
    const host = ctx as { waitUntil?: WaitUntil } | undefined;
    const keepAlive =
      host?.waitUntil?.bind(host) ?? (request as Request & { waitUntil?: WaitUntil }).waitUntil;
    const waitUntil = (p: Promise<unknown>) => keepAlive?.(p);
    // Sends to the error tracker, if one is set up.
    const report = (error: unknown) => {
      waitUntil(reportError(error, { source: "server", route: new URL(request.url).pathname }));
    };
    try {
      const handler = await getServerEntry();
      const response = await handler.fetch(request, env, ctx);
      return await normalizeCatastrophicSsrResponse(response, report);
    } catch (error) {
      console.error(error);
      report(error);
      return new Response(renderErrorPage(), {
        status: 500,
        headers: { "content-type": "text/html; charset=utf-8" },
      });
    } finally {
      // This request's log lines, and warnings sent from inside it, to the tracker.
      waitUntil(flushLogs());
    }
  },
};
