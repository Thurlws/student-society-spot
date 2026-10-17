import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { Download, LogOut, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { useAuth } from "@/lib/auth";
import { deleteMyAccount } from "@/lib/account.functions";
import { downloadMyData } from "@/lib/api/my-data";
import { useData } from "@/lib/api/store";
import { pageHead } from "@/lib/seo";
import { PageHeader } from "@/components/cards";
import { ProfileForm } from "@/components/profile-form";
import { CalendarLink } from "@/components/calendar-link";
import { Badge } from "@/components/ui/badge";
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
  head: () => pageHead("Settings", "Your profile, interests, notifications and data."),
  component: SettingsPage,
});

const SECTIONS = [
  { id: "profile", label: "Profile" },
  { id: "interests", label: "Interests" },
  { id: "notifications", label: "Notifications" },
  { id: "calendar", label: "Calendar" },
  { id: "account", label: "Your data and account" },
] as const;

function Card({
  id,
  title,
  desc,
  children,
}: {
  id: (typeof SECTIONS)[number]["id"];
  title: string;
  desc?: string;
  children: React.ReactNode;
}) {
  return (
    <section
      id={id}
      aria-labelledby={`${id}-title`}
      className="scroll-mt-6 rounded-xl border bg-card p-6 shadow-soft"
    >
      <h2 id={`${id}-title`} className="font-semibold">
        {title}
      </h2>
      {desc && <p className="mt-0.5 text-sm text-muted-foreground">{desc}</p>}
      <div className="mt-5">{children}</div>
    </section>
  );
}

function SettingsPage() {
  const { user, interests, toggleInterest, prefs, setPref, allInterests } = useData();
  const { email, access } = useAuth();
  const roles = [
    access.is_admin && "Platform admin",
    access.university_admin && "University admin",
    ...access.committee.map((c) => `${c.position}, ${c.short_name}`),
  ].filter(Boolean) as string[];

  return (
    <div className="mx-auto max-w-5xl">
      <PageHeader title="Settings" subtitle="Your profile, what you hear about, and your data." />
      <div className="grid gap-8 lg:grid-cols-[180px_minmax(0,1fr)]">
        <nav aria-label="Settings sections" className="hidden lg:block">
          <ul className="sticky top-6 space-y-1 text-sm">
            {SECTIONS.map((s) => (
              <li key={s.id}>
                <a
                  href={`#${s.id}`}
                  className="block rounded-lg px-3 py-1.5 text-muted-foreground hover:bg-muted hover:text-foreground"
                >
                  {s.label}
                </a>
              </li>
            ))}
          </ul>
        </nav>
        <div className="min-w-0 space-y-6">
          <Card id="profile" title="Profile" desc="What members of your societies see.">
            <div className="mb-6 flex items-center gap-4">
              <span className="flex size-14 shrink-0 items-center justify-center rounded-full bg-ink font-display text-lg font-semibold text-ink-foreground">
                {user.initials}
              </span>
              <div className="min-w-0">
                <p className="truncate font-semibold">{user.name}</p>
                <p className="truncate text-sm text-muted-foreground">
                  {email}
                  {access.university && `, ${access.university.short_name}`}
                </p>
                {roles.length > 0 && (
                  <div className="mt-1.5 flex flex-wrap gap-1.5">
                    {roles.map((r) => (
                      <Badge key={r} variant="soft">
                        {r}
                      </Badge>
                    ))}
                  </div>
                )}
              </div>
            </div>
            <ProfileForm />
          </Card>
          <Card
            id="interests"
            title="Interests"
            desc="Used to suggest societies on your home page. Changes save as you tap."
          >
            <div className="flex flex-wrap gap-2">
              {allInterests.map((i) => {
                const on = interests.includes(i);
                return (
                  <button
                    key={i}
                    type="button"
                    aria-pressed={on}
                    onClick={async () => {
                      const o = await toggleInterest(i);
                      if (!o.ok) toast.error(o.error);
                    }}
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
            id="notifications"
            title="Notifications"
            desc="Shown in SocConnect (the bell at the top). Decisions about your membership requests always are."
          >
            <div className="divide-y">
              {(
                [
                  ["announcements", "Announcements", "New posts from your societies"],
                  [
                    "events",
                    "Events",
                    "New events, changes and cancellations, registrations, scheduled calls",
                  ],
                  [
                    "discussions",
                    "Discussions",
                    "Activity such as call recaps shared to a channel",
                  ],
                ] as const
              ).map(([k, l, d]) => (
                <div
                  key={k}
                  className="flex items-center justify-between gap-4 py-3 first:pt-0 last:pb-0"
                >
                  <div>
                    <Label htmlFor={`pref-${k}`}>{l}</Label>
                    <p className="text-xs text-muted-foreground">{d}</p>
                  </div>
                  <Switch
                    id={`pref-${k}`}
                    checked={prefs[k]}
                    onCheckedChange={(v) => setPref(k, v)}
                  />
                </div>
              ))}
            </div>
          </Card>
          <Card
            id="calendar"
            title="Calendar"
            desc="Your registered events in Google Calendar, Apple Calendar or Outlook, kept up to date."
          >
            <CalendarLink />
          </Card>
          <Card
            id="account"
            title="Your data and account"
            desc="You sign in with your university email. Nothing here is shared outside SocConnect."
          >
            <YourData />
          </Card>
        </div>
      </div>
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
    <div className="divide-y">
      <div className="flex flex-wrap items-center justify-between gap-3 pb-4">
        <div>
          <p className="text-sm font-medium">Download your data</p>
          <p className="text-xs text-muted-foreground">
            Everything SocConnect holds about you, as a file you can keep.
          </p>
        </div>
        <Button variant="outline" onClick={download}>
          <Download />
          Download my data
        </Button>
      </div>
      <div className="flex flex-wrap items-center justify-between gap-3 py-4">
        <div>
          <p className="text-sm font-medium">Sign out</p>
          <p className="text-xs text-muted-foreground">
            On this device. Sign in again with a new link.
          </p>
        </div>
        <Button
          variant="outline"
          onClick={async () => {
            await signOut();
            navigate({ to: "/welcome" });
          }}
        >
          <LogOut />
          Sign out
        </Button>
      </div>
      <div className="flex flex-wrap items-center justify-between gap-3 py-4">
        <div>
          <p className="text-sm font-medium text-destructive">Delete your account</p>
          <p className="text-xs text-muted-foreground">
            Removes your profile, memberships, registrations, messages and requests. It can't be
            undone.
          </p>
        </div>
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button variant="destructive" disabled={busy}>
              <Trash2 />
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
      <p className="pt-4 text-sm text-muted-foreground">
        What we keep, why and for how long is in the{" "}
        <Link to="/privacy" className="underline hover:text-foreground">
          privacy notice
        </Link>
        ; the rules are in the{" "}
        <Link to="/terms" className="underline hover:text-foreground">
          terms of use
        </Link>
        .
      </p>
    </div>
  );
}
