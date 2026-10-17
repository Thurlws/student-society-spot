import type { Event } from "@/lib/types";

/** Calendar files (RFC 5545): one event to download, or the feed behind a calendar link. */
const esc = (s: string) =>
  s.replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
const ymd = (iso: string) => iso.replace(/-/g, "");
const hm = (t: string) => `${t.replace(":", "")}00`;

function nextDay(iso: string) {
  const [y, m, d] = iso.split("-").map(Number) as [number, number, number];
  return new Date(Date.UTC(y, m - 1, d + 1)).toISOString().slice(0, 10);
}

/** UTC timestamp in iCalendar form, e.g. 20261016T091500Z. */
const stamp = (d: Date) => `${d.toISOString().replace(/[-:]/g, "").slice(0, 15)}Z`;

/** Lines longer than 75 bytes continue on the next line after a space, as the standard asks. */
function fold(line: string) {
  const bytes = new TextEncoder();
  const out: string[] = [];
  let cur = "";
  for (const ch of line) {
    // 74 after the first line: the leading space counts.
    if (bytes.encode(cur + ch).length > (out.length ? 74 : 75)) {
      out.push(cur);
      cur = "";
    }
    cur += ch;
  }
  out.push(cur);
  return out.join("\r\n ");
}
const calendar = (lines: string[]) => lines.map(fold).join("\r\n");

/** Start and end as local Dublin date-times (floating), e.g. 20261105T193000. */
function localTimes(e: Event) {
  const start = `${ymd(e.date)}T${hm(e.start)}`;
  // An end time earlier than the start (e.g. 18:00–02:00) means the event runs past midnight.
  const end = e.end ? `${ymd(e.end < e.start ? nextDay(e.date) : e.date)}T${hm(e.end)}` : undefined;
  return { start, end };
}

/** Builds a single-event iCalendar file using floating local times. */
export function eventToIcs(e: Event, societyName: string, now = new Date()) {
  const { start, end } = localTimes(e);
  return calendar([
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//SocConnect//Events//EN",
    "BEGIN:VEVENT",
    `UID:event-${e.id}@socconnect`,
    `DTSTAMP:${stamp(now)}`,
    `DTSTART:${start}`,
    end ? `DTEND:${end}` : "DURATION:PT1H",
    `SUMMARY:${esc(e.title)}`,
    `LOCATION:${esc(e.venue)}`,
    `DESCRIPTION:${esc(`${societyName}: ${e.description}`)}`,
    "END:VEVENT",
    "END:VCALENDAR",
  ]);
}

export function downloadIcs(e: Event, societyName: string) {
  const url = URL.createObjectURL(
    new Blob([eventToIcs(e, societyName)], { type: "text/calendar" }),
  );
  const a = document.createElement("a");
  a.href = url;
  a.download = `${e.id}.ics`;
  a.click();
  URL.revokeObjectURL(url);
}

/**
 * Google Calendar's page for adding an event, filled in. Nothing is sent to Google until the
 * person opens it. Times are Dublin's; an event without an end lasts an hour.
 */
export function googleCalendarUrl(e: Event, societyName: string) {
  const { start, end } = localTimes(e);
  const [h, m] = e.start.split(":").map(Number) as [number, number];
  const hourLater =
    h === 23
      ? `${ymd(nextDay(e.date))}T00${String(m).padStart(2, "0")}00`
      : `${ymd(e.date)}T${String(h + 1).padStart(2, "0")}${String(m).padStart(2, "0")}00`;
  const p = new URLSearchParams({
    action: "TEMPLATE",
    text: e.title,
    dates: `${start}/${end ?? hourLater}`,
    ctz: "Europe/Dublin",
    details: `${societyName}: ${e.description}`,
    location: e.venue,
  });
  return `https://calendar.google.com/calendar/render?${p.toString()}`;
}

/** An event behind a calendar link, as the database gives it (calendar_feed_events, 0036). */
export type FeedEvent = {
  id: string;
  title: string;
  description: string;
  startsAt: string;
  endsAt: string | null;
  venue: string;
  cancelled: boolean;
  society: string;
};

/**
 * The calendar a calendar app subscribes to. Times are UTC, so every app places them right;
 * cancelled events stay, marked cancelled, so subscribed calendars drop or strike them.
 */
export function feedToIcs(events: FeedEvent[], appUrl: string, now = new Date()) {
  return calendar([
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//SocConnect//Events//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    "X-WR-CALNAME:SocConnect",
    "X-WR-CALDESC:Events you registered for on SocConnect",
    "X-WR-TIMEZONE:Europe/Dublin",
    // How often to check for changes; Google decides for itself.
    "REFRESH-INTERVAL;VALUE=DURATION:PT4H",
    "X-PUBLISHED-TTL:PT4H",
    ...events.flatMap((e) => [
      "BEGIN:VEVENT",
      `UID:event-${e.id}@socconnect`,
      `DTSTAMP:${stamp(now)}`,
      `DTSTART:${stamp(new Date(e.startsAt))}`,
      e.endsAt ? `DTEND:${stamp(new Date(e.endsAt))}` : "DURATION:PT1H",
      `SUMMARY:${esc(e.cancelled ? `Cancelled: ${e.title}` : e.title)}`,
      `LOCATION:${esc(e.venue)}`,
      `DESCRIPTION:${esc(`${e.society}: ${e.description}`)}`,
      `URL:${appUrl}/events/${e.id}`,
      `STATUS:${e.cancelled ? "CANCELLED" : "CONFIRMED"}`,
      "END:VEVENT",
    ]),
    "END:VCALENDAR",
  ]);
}
