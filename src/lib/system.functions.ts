import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import type { SupabaseClient } from "@supabase/supabase-js";

export type JobRun = {
  job: string;
  schedule: string;
  last_run: string | null;
  status: string | null;
  message: string | null;
};

export type SignInHealth = {
  status: "ok" | "degraded";
  new_accounts: { sent: number; used: number };
  returning: { sent: number; used: number };
};

export type SystemStatus = {
  errorAlerts: boolean;
  environment: string;
  uptimeToken: boolean;
  calls: boolean;
  ai: { key: boolean; pausedUntil: string | null; reason: string | null };
  /** Null until migration 0027 is in, or if it couldn't be read. */
  signIn: SignInHealth | null;
  /** Null until migration 0033 is in, or if it couldn't be read. */
  jobs: JobRun[] | null;
};

async function requirePlatformAdmin(supabase: SupabaseClient) {
  const { data } = await supabase.rpc("my_access");
  if (!(data as { is_admin?: boolean } | null)?.is_admin)
    throw new Error("Only platform admins can see the system status.");
}

/** /admin → System: is each part of SocConnect set up and working? Platform admins only. */
export const getSystemStatus = createServerFn({ method: "GET" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }): Promise<SystemStatus> => {
    await requirePlatformAdmin(context.supabase);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { parseDsn } = await import("./monitoring.server");
    const { liveKitConfig } = await import("./livekit.server");
    const [signIn, jobs, ai] = await Promise.all([
      supabaseAdmin.rpc("sign_in_health"),
      supabaseAdmin.rpc("nightly_job_runs"),
      supabaseAdmin
        .from("society_ai_state")
        .select("message, created_at")
        .eq("feature", "all")
        .maybeSingle(),
    ]);
    // A credits or access error pauses AI for 15 minutes (society-ai.functions.ts).
    const until = ai.data ? Date.parse(ai.data.created_at) + 15 * 60_000 : 0;
    const paused = until > Date.now();
    return {
      errorAlerts: !!parseDsn(process.env["SENTRY_DSN"]),
      environment: process.env["SENTRY_ENVIRONMENT"] || "production",
      uptimeToken: !!process.env["MONITORING_TOKEN"],
      calls: liveKitConfig() !== null,
      ai: {
        key: !!process.env["LOVABLE_API_KEY"],
        pausedUntil: paused ? new Date(until).toISOString() : null,
        reason: paused ? (ai.data?.message ?? null) : null,
      },
      signIn: signIn.error ? null : (signIn.data as SignInHealth),
      jobs: jobs.error ? null : (jobs.data as JobRun[]),
    };
  });

/** Sends a test error to the error tracker, so you can see an alert arrive. Platform admins only. */
export const sendTestAlert = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .handler(async ({ context }) => {
    await requirePlatformAdmin(context.supabase);
    const { parseDsn, reportError } = await import("./monitoring.server");
    if (!parseDsn(process.env["SENTRY_DSN"]))
      throw new Error("Error alerts aren't set up yet: add SENTRY_DSN in Lovable Cloud's secrets.");
    await reportError(new Error("Test alert from SocConnect. Nothing is broken."), {
      source: "server",
      route: "/admin",
      area: "test",
    });
    return { sent: true };
  });
