import type { Event } from "@/lib/types";

/** Builds a single-event iCalendar file (RFC 5545) using floating local times. */
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

export function eventToIcs(e: Event, societyName: string, now = new Date()) {
  const start = `${ymd(e.date)}T${hm(e.start)}`;
  // An end time earlier than the start (e.g. 18:00–02:00) means the event runs past midnight.
  const end = e.end ? `${ymd(e.end < e.start ? nextDay(e.date) : e.date)}T${hm(e.end)}` : undefined;
  return [
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
  ].join("\r\n");
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
