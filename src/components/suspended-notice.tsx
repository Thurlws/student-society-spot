import { Link, useNavigate } from "@tanstack/react-router";
import { ShieldOff } from "lucide-react";
import { useAuth } from "@/lib/auth";
import { downloadMyData } from "@/lib/api/my-data";
import { formatDate, toDublin } from "@/lib/format";
import { Button } from "@/components/ui/button";

/** What a suspended account sees instead of the app (migration 0025). */
export function SuspendedNotice() {
  const { access, session, signOut } = useAuth();
  const navigate = useNavigate();
  const s = access.suspended;
  if (!s) return null;
  const university = access.university?.short_name ?? "your university";
  return (
    <div className="mx-auto max-w-xl space-y-5 rounded-xl border bg-card p-8 shadow-soft">
      <ShieldOff className="size-8 text-destructive" />
      <h1 className="font-display text-2xl font-semibold">Your account is suspended</h1>
      <p className="text-muted-foreground">
        An admin suspended your SocConnect account on{" "}
        {formatDate(toDublin(s.at).date, { weekday: "long", month: "long", year: "numeric" })}.
        Until the suspension is lifted you can't see or use societies, events, discussions or calls.
        Your memberships and messages are kept.
      </p>
      <div>
        <p className="text-sm font-semibold">The reason given</p>
        <blockquote className="mt-1 rounded-lg border-l-4 bg-muted/50 px-3 py-2 text-sm">
          {s.reason}
        </blockquote>
      </div>
      <p className="text-sm text-muted-foreground">
        If you think this is wrong, contact {university}'s Students' Union or student services. You
        can still download what SocConnect holds about you. Your account can't be deleted while it's
        suspended; ask them to do it if you want it gone.
      </p>
      <div className="flex flex-wrap gap-3">
        <Button
          variant="outline"
          onClick={() => session && downloadMyData(session.user.id, session.user.email)}
        >
          Download my data
        </Button>
        <Button variant="ghost" asChild>
          <Link to="/privacy">Privacy notice</Link>
        </Button>
        <Button variant="ghost" asChild>
          <Link to="/terms">Terms of use</Link>
        </Button>
        <Button
          variant="ghost"
          onClick={async () => {
            await signOut().catch(() => {});
            navigate({ to: "/welcome" });
          }}
        >
          Sign out
        </Button>
      </div>
    </div>
  );
}
