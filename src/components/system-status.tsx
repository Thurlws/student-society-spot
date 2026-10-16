import { useQuery } from "@tanstack/react-query";
import { useServerFn } from "@tanstack/react-start";
import { CheckCircle2, CircleAlert, CircleMinus, Loader2, RefreshCw, Send } from "lucide-react";
import { useState, type ReactNode } from "react";
import { toast } from "sonner";
import { formatDate, toDublin } from "@/lib/format";
import { getSystemStatus, sendTestAlert, type SystemStatus } from "@/lib/system.functions";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

type State = "ok" | "warn" | "off";

const when = (iso: string) => {
  const d = toDublin(iso);
  return `${formatDate(d.date, { day: "numeric", month: "short" })}, ${d.time}`;
};

function Row({
  state,
  title,
  children,
  action,
}: {
  state: State;
  title: string;
  children: ReactNode;
  action?: ReactNode;
}) {
  const Icon = state === "ok" ? CheckCircle2 : state === "warn" ? CircleAlert : CircleMinus;
  return (
    <li className="flex flex-wrap items-start gap-3 px-5 py-4">
      <Icon
        aria-hidden
        className={cn(
          "mt-0.5 size-5 shrink-0",
          state === "ok"
            ? "text-success"
            : state === "warn"
              ? "text-destructive"
              : "text-muted-foreground",
        )}
      />
      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold">
          {title}
          <span className="sr-only">
            : {state === "ok" ? "working" : state === "warn" ? "needs attention" : "not set up"}
          </span>
        </p>
        <div className="text-sm text-muted-foreground">{children}</div>
      </div>
      {action}
    </li>
  );
}

/** /admin → System, for platform admins: what's set up, what's working, and a test alert. */
export function SystemPanel() {
  const fetchStatus = useServerFn(getSystemStatus);
  const testAlert = useServerFn(sendTestAlert);
  const [sending, setSending] = useState(false);
  const q = useQuery<SystemStatus>({
    queryKey: ["admin", "system"],
    queryFn: () => fetchStatus(),
  });
  const s = q.data;

  if (q.isLoading) return <div className="h-64 animate-pulse rounded-xl bg-muted" />;
  if (!s)
    return (
      <p className="text-sm text-destructive">
        Couldn't load the system status. {q.error instanceof Error ? q.error.message : ""}
      </p>
    );

  const sendTest = async () => {
    setSending(true);
    try {
      await testAlert();
      toast.success("Test alert sent. It should reach your error tracker within a minute.");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Couldn't send the test alert.");
    }
    setSending(false);
  };

  const signIn = s.signIn;
  const signInState: State = !signIn ? "off" : signIn.status === "ok" ? "ok" : "warn";
  const failedJobs = (s.jobs ?? []).filter((j) => j.status && j.status !== "succeeded");

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-sm text-muted-foreground">
          Whether each part of SocConnect is set up and working. Settings marked as secrets live in
          Lovable Cloud.
        </p>
        <Button
          variant="outline"
          size="sm"
          onClick={() => void q.refetch()}
          disabled={q.isFetching}
        >
          <RefreshCw className={cn(q.isFetching && "animate-spin")} />
          Check again
        </Button>
      </div>
      <ul className="divide-y overflow-hidden rounded-xl border bg-card shadow-soft">
        <Row
          state={s.errorAlerts ? "ok" : "off"}
          title="Error alerts"
          action={
            <Button
              variant="outline"
              size="sm"
              onClick={sendTest}
              disabled={!s.errorAlerts || sending}
            >
              {sending ? <Loader2 className="animate-spin" /> : <Send />}
              Send test alert
            </Button>
          }
        >
          {s.errorAlerts
            ? `Errors and warnings go to Sentry as issues, and the server's log to its Logs page (environment: ${s.environment}).`
            : "Off. Add the SENTRY_DSN secret to get an email when something breaks."}
        </Row>
        <Row state={s.uptimeToken ? "ok" : "off"} title="Uptime checks">
          {s.uptimeToken
            ? "Ready: an uptime monitor can check /api/health and /api/health/sign-in."
            : "Off. Add the MONITORING_TOKEN secret, then point an uptime monitor at /api/health."}
        </Row>
        <Row state={signInState} title="Sign-in emails, last 24 hours">
          {!signIn
            ? "Not available yet."
            : `New accounts: ${signIn.new_accounts.used} of ${signIn.new_accounts.sent} links used. Returning: ${signIn.returning.used} of ${signIn.returning.sent} used.${
                signIn.status === "ok"
                  ? ""
                  : " Few links are being used, so emails may not be arriving: check quarantine."
              }`}
        </Row>
        <Row state={!s.ai.key ? "off" : s.ai.pausedUntil ? "warn" : "ok"} title="AI features">
          {!s.ai.key
            ? "Off: the AI gateway key isn't set."
            : s.ai.pausedUntil
              ? `Paused until ${when(s.ai.pausedUntil)}: ${s.ai.reason ?? "the gateway refused"}. Usually it's out of credits.`
              : "Working."}
        </Row>
        <Row state={s.calls ? "ok" : "off"} title="Video calls">
          {s.calls ? "On." : "Off: the LiveKit secrets aren't set."}
        </Row>
        <Row state={!s.jobs ? "off" : failedJobs.length ? "warn" : "ok"} title="Nightly jobs">
          {!s.jobs ? (
            "Shown once database update 0033 is in."
          ) : (
            <ul className="mt-1 space-y-0.5">
              {s.jobs.map((j) => (
                <li key={j.job}>
                  <span className="font-medium text-foreground">{j.job}</span>:{" "}
                  {j.last_run
                    ? `${j.status === "succeeded" ? "ran" : `failed (${j.message ?? j.status})`} ${when(j.last_run)}`
                    : "hasn't run yet"}
                </li>
              ))}
            </ul>
          )}
        </Row>
      </ul>
    </div>
  );
}
