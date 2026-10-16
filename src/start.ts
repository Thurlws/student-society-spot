import { createStart, createCsrfMiddleware, createMiddleware } from "@tanstack/react-start";

import { renderErrorPage } from "./lib/error-page";
import { log, reportError } from "./lib/monitoring.server";
import { attachSupabaseAuth } from "@/integrations/supabase/auth-attacher";

const errorMiddleware = createMiddleware().server(async ({ next, request }) => {
  try {
    return await next();
  } catch (error) {
    if (error != null && typeof error === "object" && "statusCode" in error) {
      throw error;
    }
    console.error(error);
    void reportError(error, { source: "server", route: new URL(request.url).pathname });
    return new Response(renderErrorPage(), {
      status: 500,
      headers: { "content-type": "text/html; charset=utf-8" },
    });
  }
});

// Start installs this automatically when src/start.ts is absent; defining the
// file opts out, so re-add it explicitly to keep server functions protected
// from cross-site requests.
const csrfMiddleware = createCsrfMiddleware({
  filter: (ctx) => ctx.handlerType === "serverFn",
});

// One log line per server function call (its name and how long it took), and a warning to the
// error tracker when one fails or takes over 5 seconds. Many failures are refusals people are
// meant to see (a quota, a permission); the tracker groups them by function and message.
const logServerFunctions = createMiddleware({ type: "function" }).server(
  async ({ next, serverFnMeta }) => {
    const started = Date.now();
    const fn = serverFnMeta.name;
    try {
      const result = await next();
      const ms = Date.now() - started;
      log(ms > 5000 ? "warn" : "info", ms > 5000 ? "server_fn.slow" : "server_fn", { fn, ms });
      return result;
    } catch (error) {
      log("warn", "server_fn.failed", { fn, ms: Date.now() - started }, error);
      throw error;
    }
  },
);

export const startInstance = createStart(() => ({
  requestMiddleware: [errorMiddleware, csrfMiddleware],
  functionMiddleware: [attachSupabaseAuth, logServerFunctions],
}));
