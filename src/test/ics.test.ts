import { describe, expect, it } from "vitest";
import { eventToIcs, feedToIcs, googleCalendarUrl } from "@/lib/ics";
import type { Event } from "@/lib/types";

const event: Event = {
  id: "9b2f4c1e-0000-4000-8000-000000000001",
  title: "Quiz night",
  description: "Teams of four, prizes",
  societyId: "gaming",
  date: "2026-11-05",
  start: "19:30",
  end: "22:00",
  startsAt: "2026-11-05T19:30:00Z",
  endsAt: "2026-11-05T22:00:00Z",
  venue: "Aungier St, room 2.01",
  category: "Social",
  attendees: 0,
  tags: [],
};

describe("eventToIcs", () => {
  it("uses the event id, the time it was made and no demo labels", () => {
    const ics = eventToIcs(event, "Gaming Society", new Date("2026-10-16T09:15:42Z"));
    expect(ics).toContain(`UID:event-${event.id}@socconnect`);
    expect(ics).toContain("DTSTAMP:20261016T091542Z");
    expect(ics).toContain("DTSTART:20261105T193000Z");
    expect(ics).toContain("LOCATION:Aungier St\\, room 2.01");
    expect(ics.toLowerCase()).not.toContain("demo");
  });

  it("writes UTC, so summer events land at the right hour on a device in any time zone", () => {
    // 19:30 in Dublin in June is 18:30 UTC; a floating 19:30 would show at 19:30 wherever it's opened.
    const june = { ...event, startsAt: "2026-06-10T18:30:00Z", endsAt: "2026-06-11T00:30:00Z" };
    const ics = eventToIcs(june, "Gaming Society");
    expect(ics).toContain("DTSTART:20260610T183000Z");
    expect(ics).toContain("DTEND:20260611T003000Z");
  });

  it("gives an event without an end an hour", () => {
    expect(eventToIcs({ ...event, endsAt: undefined }, "G")).toContain("DURATION:PT1H");
  });
});

describe("googleCalendarUrl", () => {
  it("fills in Google Calendar's add-event page in Dublin time", () => {
    const url = new URL(googleCalendarUrl(event, "Gaming Society"));
    expect(url.origin + url.pathname).toBe("https://calendar.google.com/calendar/render");
    expect(url.searchParams.get("action")).toBe("TEMPLATE");
    expect(url.searchParams.get("dates")).toBe("20261105T193000/20261105T220000");
    expect(url.searchParams.get("ctz")).toBe("Europe/Dublin");
    expect(url.searchParams.get("location")).toBe("Aungier St, room 2.01");
  });

  it("gives an event without an end an hour, past midnight too", () => {
    const dates = (start: string) =>
      new URL(googleCalendarUrl({ ...event, start, end: undefined }, "G")).searchParams.get(
        "dates",
      );
    expect(dates("19:30")).toBe("20261105T193000/20261105T203000");
    expect(dates("23:15")).toBe("20261105T231500/20261106T001500");
  });
});

describe("feedToIcs", () => {
  const feed = (cancelled: boolean, description = "Bring a pen") =>
    feedToIcs(
      [
        {
          id: event.id,
          title: "Quiz night",
          description,
          startsAt: "2026-11-05T19:30:00Z",
          endsAt: null,
          venue: "Room 1",
          cancelled,
          society: "Gaming Society",
        },
      ],
      "https://socconnect.example",
      new Date("2026-10-16T09:15:42Z"),
    );

  it("lists the events in UTC with a link back", () => {
    const ics = feed(false);
    expect(ics).toContain("X-WR-CALNAME:SocConnect");
    expect(ics).toContain("DTSTART:20261105T193000Z");
    expect(ics).toContain("DURATION:PT1H");
    expect(ics).toContain(`URL:https://socconnect.example/events/${event.id}`);
    expect(ics).toContain("STATUS:CONFIRMED");
  });

  it("keeps cancelled events, marked", () => {
    const ics = feed(true);
    expect(ics).toContain("SUMMARY:Cancelled: Quiz night");
    expect(ics).toContain("STATUS:CANCELLED");
  });

  it("folds long lines at 75 bytes", () => {
    const ics = feed(false, "é".repeat(100));
    for (const line of ics.split("\r\n"))
      expect(new TextEncoder().encode(line).length).toBeLessThanOrEqual(75);
    // Unfolding gives the text back.
    expect(ics.replace(/\r\n /g, "")).toContain(`DESCRIPTION:Gaming Society: ${"é".repeat(100)}`);
  });
});
