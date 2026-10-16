import { createFileRoute } from "@tanstack/react-router";

// For an uptime monitor that sends `Authorization: Bearer <MONITORING_TOKEN>`: whether
// sign-in emails seem to arrive (migration 0027, sign_in_health). 200 when they do, 503 when
// many links went out and few were used. Not found unless MONITORING_TOKEN is set.
export const Route = createFileRoute("/api/health_/sign-in")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const { refuseWithoutMonitoringToken } = await import("@/lib/monitoring.server");
        const refused = await refuseWithoutMonitoringToken(request);
        if (refused) return refused;
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { data, error } = await supabaseAdmin.rpc("sign_in_health");
        const health = error ? { status: "unknown" } : (data as { status: string });
        return Response.json(health, {
          status: health.status === "ok" ? 200 : 503,
          headers: { "cache-control": "no-store" },
        });
      },
    },
  },
});
