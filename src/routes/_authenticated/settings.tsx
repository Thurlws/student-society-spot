import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { toast } from "sonner";
import { useAuth } from "@/lib/auth";
import { deleteMyAccount } from "@/lib/account.functions";
import { downloadMyData } from "@/lib/api/my-data";
import { useData } from "@/lib/api/store";
import { pageHead } from "@/lib/seo";
import { PageHeader } from "@/components/cards";
import { ProfileForm } from "@/components/profile-form";
import { Button, buttonVariants } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/settings")({
  head: () => pageHead("Settings", "Your profile, interests and notification preferences."),
  component: SettingsPage,
});

function Card({
  title,
  desc,
  children,
}: {
  title: string;
  desc?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="rounded-xl border bg-card p-6 shadow-soft">
      <h2 className="font-semibold">{title}</h2>
      {desc && <p className="mt-0.5 text-sm text-muted-foreground">{desc}</p>}
      <div className="mt-5">{children}</div>
    </section>
  );
}

function SettingsPage() {
  const { user, role, interests, toggleInterest, prefs, setPref, allInterests } = useData();
  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title="Settings"
        subtitle="Manage your profile and how SocConnect keeps you informed."
      />
      <Card title="Profile">
        <div className="flex items-center gap-4">
          <span className="flex size-14 items-center justify-center rounded-full bg-ink font-display text-lg font-semibold text-ink-foreground">
            {user.initials}
          </span>
          <div>
            <p className="font-semibold">{user.name}</p>
            <p className="text-sm text-muted-foreground">
              {user.course}, {user.year}
            </p>
            <p className="text-xs text-muted-foreground">
              {role === "committee" ? "Committee member" : "Student"}
            </p>
          </div>
        </div>
      </Card>
      <Card title="Interests" desc="Used for society recommendations on your home page.">
        <div className="flex flex-wrap gap-2">
          {allInterests.map((i) => {
            const on = interests.includes(i);
            return (
              <button
                key={i}
                onClick={() => toggleInterest(i)}
                className={cn(
                  "rounded-full border px-3 py-1.5 text-sm font-medium transition-colors disabled:opacity-60",
                  on
                    ? "border-primary bg-primary-soft text-primary"
                    : "bg-card hover:border-primary/40",
                )}
              >
                {i}
              </button>
            );
          })}
        </div>
      </Card>
      <Card
        title="Notifications"
        desc="In-app notifications only. Membership decisions are always shown."
      >
        <div className="space-y-4">
          {(
            [
              ["announcements", "New announcements from my societies"],
              ["events", "Event updates: new events, registrations, scheduled calls"],
              ["discussions", "Discussion activity, such as shared call recaps"],
            ] as const
          ).map(([k, l]) => (
            <div key={k} className="flex items-center justify-between gap-4">
              <Label htmlFor={k}>{l}</Label>
              <Switch id={k} checked={prefs[k]} onCheckedChange={(v) => setPref(k, v)} />
            </div>
          ))}
          <div className="flex items-center justify-between gap-4">
            <Label htmlFor="email" className="text-muted-foreground">
              Weekly email digest (not available yet)
            </Label>
            <Switch id="email" checked={false} disabled />
          </div>
        </div>
      </Card>
      <Card title="Account" desc="You're signed in with your university email.">
        <ProfileForm />
      </Card>
      <Card
        title="Your data"
        desc="Download what SocConnect holds about you, or delete your account."
      >
        <YourData />
      </Card>
    </div>
  );
}

function YourData() {
  const { session, signOut } = useAuth();
  const navigate = useNavigate();
  const remove = useServerFn(deleteMyAccount);
  const [busy, setBusy] = useState(false);

  const download = () => session && downloadMyData(session.user.id, session.user.email);

  const del = async () => {
    setBusy(true);
    try {
      await remove();
    } catch {
      setBusy(false);
      return void toast.error(
        "Couldn't delete your account. Try again, or contact the SocConnect team.",
      );
    }
    await signOut().catch(() => {});
    navigate({ to: "/welcome" });
  };

  return (
    <div className="flex flex-wrap gap-3">
      <Button variant="outline" onClick={download}>
        Download my data
      </Button>
      <AlertDialog>
        <AlertDialogTrigger asChild>
          <Button variant="destructive" disabled={busy}>
            Delete my account
          </Button>
        </AlertDialogTrigger>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete your account?</AlertDialogTitle>
            <AlertDialogDescription>
              This removes your profile, memberships, event registrations, messages and requests,
              and any committee seats you hold. It can't be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction
              className={buttonVariants({ variant: "destructive" })}
              onClick={del}
              disabled={busy}
            >
              Delete my account
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
