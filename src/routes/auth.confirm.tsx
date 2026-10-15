import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { Loader2, Waypoints } from "lucide-react";
import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { pageHead } from "@/lib/seo";
import { Button } from "@/components/ui/button";

type LinkType = "email" | "magiclink" | "signup";

/**
 * Where the sign-in email's link lands (template: /auth/confirm?token_hash=…&type=email).
 * The link points at our own domain, which helps spam filters trust the email, and the
 * token is used only when the person presses the button, so mail scanners that open
 * links can't use it up.
 */
export const Route = createFileRoute("/auth/confirm")({
  validateSearch: (s: Record<string, unknown>): { token_hash: string; type: LinkType } => ({
    token_hash: typeof s["token_hash"] === "string" ? s["token_hash"] : "",
    type: s["type"] === "magiclink" || s["type"] === "signup" ? s["type"] : "email",
  }),
  head: () => pageHead("Sign in", "Finish signing in to SocConnect."),
  component: Confirm,
});

function Confirm() {
  const { token_hash, type } = Route.useSearch();
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(token_hash ? "" : "This sign-in link is incomplete. Ask for a new one.");

  const confirm = async () => {
    setBusy(true);
    const { error } = await supabase.auth.verifyOtp({ token_hash, type });
    if (!error) return void navigate({ to: "/" });
    setBusy(false);
    setError(error.code === "otp_expired"
      ? "This link has expired or was already used. Links work once, for 10 minutes."
      : "We couldn't sign you in with this link. Ask for a new one.");
  };

  return (
    <div className="flex min-h-screen items-center justify-center px-6">
      <div className="w-full max-w-sm space-y-4 rounded-2xl border bg-card p-6 shadow-lift">
        <span className="flex size-8 items-center justify-center rounded-lg bg-brand text-primary-foreground"><Waypoints className="size-4" /></span>
        <h1 className="text-xl font-semibold">Sign in to SocConnect</h1>
        {error ? (
          <>
            <p className="text-sm text-destructive">{error}</p>
            <Button asChild className="w-full"><Link to="/welcome">Get a new link</Link></Button>
          </>
        ) : (
          <Button className="w-full" onClick={confirm} disabled={busy}>{busy && <Loader2 className="animate-spin" />}Continue</Button>
        )}
      </div>
    </div>
  );
}
