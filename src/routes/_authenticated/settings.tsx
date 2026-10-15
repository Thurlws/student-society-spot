import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useServerFn } from "@tanstack/react-start";
import { useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/lib/auth";
import { deleteMyAccount } from "@/lib/account.functions";
import { useData } from "@/lib/api/store";
import { pageHead } from "@/lib/seo";
import { PageHeader } from "@/components/cards";
import { ProfileForm } from "@/components/profile-form";
import { Button, buttonVariants } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription,
  AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/_authenticated/settings")({
  head: () => pageHead("Settings", "Your profile, interests and notification preferences."),
  component: SettingsPage,
});

function Card({ title, desc, children }: { title: string; desc?: string; children: React.ReactNode }) {
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
      <PageHeader title="Settings" subtitle="Manage your profile and how SocConnect keeps you informed." />
      <Card title="Profile">
        <div className="flex items-center gap-4">
          <span className="flex size-14 items-center justify-center rounded-full bg-ink font-display text-lg font-semibold text-ink-foreground">{user.initials}</span>
          <div>
            <p className="font-semibold">{user.name}</p>
            <p className="text-sm text-muted-foreground">{user.course}, {user.year}</p>
            <p className="text-xs text-muted-foreground">{role === "committee" ? "Committee member" : "Student"}</p>
          </div>
        </div>
      </Card>
      <Card title="Interests" desc="Used for society recommendations on your home page.">
        <div className="flex flex-wrap gap-2">
          {allInterests.map((i) => {
            const on = interests.includes(i);
            return (
              <button key={i} onClick={() => toggleInterest(i)} className={cn("rounded-full border px-3 py-1.5 text-sm font-medium transition-colors disabled:opacity-60", on ? "border-primary bg-primary-soft text-primary" : "bg-card hover:border-primary/40")}>{i}</button>
            );
          })}
        </div>
      </Card>
      <Card title="Notifications" desc="In-app notifications only. Membership decisions are always shown.">
        <div className="space-y-4">
          {([
            ["announcements", "New announcements from my societies"],
            ["events", "Event updates: new events, registrations, scheduled calls"],
            ["discussions", "Discussion activity, such as shared call recaps"],
          ] as const).map(([k, l]) => (
            <div key={k} className="flex items-center justify-between gap-4">
              <Label htmlFor={k}>{l}</Label>
              <Switch id={k} checked={prefs[k]} onCheckedChange={(v) => setPref(k, v)} />
            </div>
          ))}
          <div className="flex items-center justify-between gap-4">
            <Label htmlFor="email" className="text-muted-foreground">Weekly email digest (not available yet)</Label>
            <Switch id="email" checked={false} disabled />
          </div>
        </div>
      </Card>
      <Card title="Account" desc="You're signed in with your university email.">
        <ProfileForm />
      </Card>
      <Card title="Your data" desc="Download what SocConnect holds about you, or delete your account.">
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

  const download = async () => {
    const uid = session?.user.id;
    if (!uid) return;
    // Row-level security only returns this person's own rows.
    const parts = await Promise.all([
      supabase.from("profiles").select("display_name, course, year, onboarded_at, created_at").eq("id", uid),
      supabase.from("profile_interests").select("interests(name)").eq("profile_id", uid),
      supabase.from("notification_prefs").select("announcements, events, discussions, email").eq("user_id", uid),
      supabase.from("society_memberships").select("status, message, requested_at, decided_at, societies(name)").eq("user_id", uid),
      supabase.from("society_roles").select("position, societies(name)").eq("user_id", uid),
      supabase.from("event_registrations").select("created_at, events(title, starts_at)").eq("user_id", uid),
      supabase.from("messages").select("body, created_at").eq("author_id", uid),
      supabase.from("support_requests").select("title, description, category, status, resolution, created_at").eq("submitted_by", uid),
      supabase.from("notifications").select("title, body, created_at, read_at").eq("user_id", uid),
      supabase.from("ai_usage").select("feature, created_at").eq("user_id", uid),
    ]);
    const keys = ["profile", "interests", "notificationSettings", "memberships", "committeeRoles", "eventRegistrations", "messages", "memberRequests", "notifications", "aiUsage"];
    const data = Object.fromEntries(keys.map((k, i) => [k, parts[i]!.data ?? []]));
    const blob = new Blob([JSON.stringify({ exportedAt: new Date().toISOString(), email: session?.user.email, ...data }, null, 2)], { type: "application/json" });
    const a = Object.assign(document.createElement("a"), { href: URL.createObjectURL(blob), download: "socconnect-my-data.json" });
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  };

  const del = async () => {
    setBusy(true);
    try {
      await remove();
    } catch {
      setBusy(false);
      return void toast.error("Couldn't delete your account. Try again, or contact the SocConnect team.");
    }
    await signOut().catch(() => {});
    navigate({ to: "/welcome" });
  };

  return (
    <div className="flex flex-wrap gap-3">
      <Button variant="outline" onClick={download}>Download my data</Button>
      <AlertDialog>
        <AlertDialogTrigger asChild><Button variant="destructive" disabled={busy}>Delete my account</Button></AlertDialogTrigger>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete your account?</AlertDialogTitle>
            <AlertDialogDescription>
              This removes your profile, memberships, event registrations, messages and requests, and any committee seats you hold. It can't be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction className={buttonVariants({ variant: "destructive" })} onClick={del} disabled={busy}>Delete my account</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
