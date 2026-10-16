import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

/**
 * Passes a browser error to the error tracker (monitoring.server.ts): pages that crash, and
 * sign-in emails that fail to send. Signed-out visitors can call it too, so input is short
 * and scrubbed, and the tracker gets at most 20 reports a minute.
 */
export const reportClientError = createServerFn({ method: "POST" })
  .inputValidator(
    z.object({
      name: z.string().max(100),
      message: z.string().max(2000),
      stack: z.string().max(8000).optional(),
      route: z.string().max(300),
      area: z.enum(["page", "sign-in"]),
    }),
  )
  .handler(async ({ data }) => {
    const { reportError } = await import("./monitoring.server");
    const error = Object.assign(new Error(data.message), { name: data.name, stack: data.stack });
    await reportError(error, { source: "browser", route: data.route, area: data.area });
    return { ok: true };
  });
