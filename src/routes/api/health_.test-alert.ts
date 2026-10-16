import { createFileRoute } from "@tanstack/react-router";

// POST with `Authorization: Bearer <MONITORING_TOKEN>` sends a test error to the error
// tracker, to check that alerts reach someone. Not found unless MONITORING_TOKEN is set.
export const Route = createFileRoute("/api/health_/test-alert")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        const { refuseWithoutMonitoringToken, reportError, parseDsn } =
          await import("@/lib/monitoring.server");
        const refused = await refuseWithoutMonitoringToken(request);
        if (refused) return refused;
        if (!parseDsn(process.env["SENTRY_DSN"]))
          return Response.json({ sent: false, reason: "SENTRY_DSN isn't set." }, { status: 503 });
        await reportError(new Error("Test alert from SocConnect. Nothing is broken."), {
          source: "server",
          route: "/api/health/test-alert",
          area: "test",
        });
        return Response.json({ sent: true });
      },
    },
  },
});
