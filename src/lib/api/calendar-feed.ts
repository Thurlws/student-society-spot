import { supabase } from "@/integrations/supabase/client";

// Personal calendar links (migration 0036). The link itself is shown only when it's made: the
// database keeps a hash of it.

/** The calendar link's address for a key, for calendar apps to subscribe to. */
export const calendarFeedUrl = (origin: string, token: string) =>
  `${origin}/api/calendar/${token}.ics`;

/** Google Calendar's "add calendar from URL" page for that address. */
export const googleSubscribeUrl = (feedUrl: string) =>
  `https://calendar.google.com/calendar/r?cid=${encodeURIComponent(feedUrl.replace(/^https?:/, "webcal:"))}`;

/** When your current link was made, null without one, or "missing" before 0036 is in the database. */
export async function calendarFeedStatus(): Promise<string | null | "missing"> {
  const r = await supabase.from("calendar_feeds").select("created_at").maybeSingle();
  if (r.error) {
    if (r.error.code === "PGRST205" || r.error.code === "42P01") return "missing";
    throw new Error(r.error.message);
  }
  return r.data?.created_at ?? null;
}

/** Makes a new link, turning off the old one, and returns its key. */
export async function createCalendarFeed() {
  const r = await supabase.rpc("create_calendar_feed");
  if (r.error) throw new Error(r.error.message);
  return r.data;
}

export async function deleteCalendarFeed() {
  const r = await supabase.rpc("delete_calendar_feed");
  if (r.error) throw new Error(r.error.message);
}
