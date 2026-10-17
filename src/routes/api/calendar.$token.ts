import { createFileRoute } from "@tanstack/react-router";
import { feedToIcs, type FeedEvent } from "@/lib/ics";

// A personal calendar link (migration 0036). Google, Apple and Outlook calendars fetch it
// without signing in, so the key in the link is the only check. A link that was never made, was
// replaced or was turned off gets an empty calendar, like one with no events: nothing tells them
// apart, and calendar apps don't drop the subscription with an error.
export const Route = createFileRoute("/api/calendar/$token")({
  server: {
    handlers: {
      GET: async ({ request, params }) => {
        const token = params.token.replace(/\.ics$/, "");
        let events: FeedEvent[] = [];
        if (/^[0-9a-f]{64}$/.test(token)) {
          const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
          const { data, error } = await supabaseAdmin.rpc("calendar_feed_events", {
            _token: token,
          });
          if (error) {
            const { log } = await import("@/lib/monitoring.server");
            log("error", "calendar.feed_failed", { area: "calendar" }, error.message);
            return new Response("The calendar isn't available right now.", { status: 503 });
          }
          events = (data ?? []).map((e) => ({
            id: e.id,
            title: e.title,
            description: e.description,
            startsAt: e.starts_at,
            endsAt: e.ends_at,
            venue: e.venue,
            cancelled: e.cancelled,
            society: e.society,
          }));
        }
        return new Response(feedToIcs(events, new URL(request.url).origin), {
          headers: {
            "content-type": "text/calendar; charset=utf-8",
            "content-disposition": 'inline; filename="socconnect.ics"',
            "cache-control": "private, max-age=900",
          },
        });
      },
    },
  },
});
