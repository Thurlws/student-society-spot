import { supabase } from "@/integrations/supabase/client";

/**
 * Downloads everything SocConnect holds about the signed-in person as JSON. Row-level security
 * only returns their own rows, and it keeps working while an account is suspended.
 */
export async function downloadMyData(uid: string, email: string | undefined) {
  const parts = await Promise.all([
    supabase
      .from("profiles")
      .select("display_name, course, year, onboarded_at, created_at")
      .eq("id", uid),
    supabase.from("profile_interests").select("interests(name)").eq("profile_id", uid),
    supabase
      .from("notification_prefs")
      .select("announcements, events, discussions, email")
      .eq("user_id", uid),
    supabase
      .from("society_memberships")
      .select("status, message, requested_at, decided_at, societies(name)")
      .eq("user_id", uid),
    supabase.from("society_roles").select("position, societies(name)").eq("user_id", uid),
    supabase
      .from("event_registrations")
      .select("created_at, events(title, starts_at)")
      .eq("user_id", uid),
    supabase.from("messages").select("body, created_at").eq("author_id", uid),
    supabase
      .from("support_requests")
      .select("title, description, category, status, resolution, created_at")
      .eq("submitted_by", uid),
    supabase.from("notifications").select("title, body, created_at, read_at").eq("user_id", uid),
    supabase.from("ai_usage").select("feature, created_at").eq("user_id", uid),
  ]);
  const keys = [
    "profile",
    "interests",
    "notificationSettings",
    "memberships",
    "committeeRoles",
    "eventRegistrations",
    "messages",
    "memberRequests",
    "notifications",
    "aiUsage",
  ];
  const data = Object.fromEntries(keys.map((k, i) => [k, parts[i]!.data ?? []]));
  const blob = new Blob(
    [JSON.stringify({ exportedAt: new Date().toISOString(), email, ...data }, null, 2)],
    { type: "application/json" },
  );
  const a = Object.assign(document.createElement("a"), {
    href: URL.createObjectURL(blob),
    download: "socconnect-my-data.json",
  });
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}
