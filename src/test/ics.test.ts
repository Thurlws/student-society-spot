import { describe, expect, it } from "vitest";
import { eventToIcs } from "@/lib/ics";
import type { Event } from "@/lib/types";

const event: Event = {
  id: "9b2f4c1e-0000-4000-8000-000000000001", title: "Quiz night", description: "Teams of four, prizes", societyId: "gaming",
  date: "2026-11-05", start: "19:30", end: "22:00", venue: "Aungier St, room 2.01", category: "Social", attendees: 0, tags: [],
};

describe("eventToIcs", () => {
  it("uses the event id, the time it was made and no demo labels", () => {
    const ics = eventToIcs(event, "Gaming Society", new Date("2026-10-16T09:15:42Z"));
    expect(ics).toContain(`UID:event-${event.id}@socconnect`);
    expect(ics).toContain("DTSTAMP:20261016T091542Z");
    expect(ics).toContain("DTSTART:20261105T193000");
    expect(ics).toContain("LOCATION:Aungier St\\, room 2.01");
    expect(ics.toLowerCase()).not.toContain("demo");
  });

  it("ends on the next day when the end time is before the start", () => {
    const ics = eventToIcs({ ...event, start: "21:00", end: "01:00" }, "Gaming Society");
    expect(ics).toContain("DTEND:20261106T010000");
  });
});
