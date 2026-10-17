import { createFileRoute } from "@tanstack/react-router";

// For an uptime monitor that sends `Authorization: Bearer <MONITORING_TOKEN>`: whether the
// nightly jobs (transcript and data purges, lapsed sessions) ran and worked in the last 26 hours
// (nightly_job_runs, migration 0033). 200 when they did, 503 when one failed or didn't run, with
// the job's name. Not found unless MONITORING_TOKEN is set.
export const Route = createFileRoute("/api/health_/jobs")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const { refuseWithoutMonitoringToken, jobsHealth } =
          await import("@/lib/monitoring.server");
        const refused = await refuseWithoutMonitoringToken(request);
        if (refused) return refused;
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        const { data, error } = await supabaseAdmin.rpc("nightly_job_runs");
        const health = error
          ? { status: "unknown" as const, failing: [] }
          : jobsHealth(data as { job: string; last_run: string | null; status: string | null }[]);
        return Response.json(health, {
          status: health.status === "ok" ? 200 : 503,
          headers: { "cache-control": "no-store" },
        });
      },
    },
  },
});
