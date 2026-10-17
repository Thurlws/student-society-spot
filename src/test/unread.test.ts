import { describe, expect, it } from "vitest";
import { nextMarks, unreadIn } from "@/lib/unread";

const msg = (channelId: string, authorId: string, createdAt: string) => ({
  channelId,
  authorId,
  createdAt,
});

describe("unread counts", () => {
  it("starts a channel seen for the first time with nothing new", () => {
    const marks = nextMarks({}, { general: "2026-10-17T10:00:00Z", empty: "" });
    expect(marks).toEqual({ general: "2026-10-17T10:00:00Z", empty: "" });
    expect(
      unreadIn([msg("general", "ann", "2026-10-17T10:00:00Z")], "general", marks["general"], "me"),
    ).toBe(0);
  });

  it("counts other people's later messages, not your own", () => {
    const messages = [
      msg("general", "ann", "2026-10-17T10:05:00Z"),
      msg("general", "me", "2026-10-17T10:06:00Z"),
      msg("events", "bob", "2026-10-17T10:07:00Z"),
      msg("empty", "bob", "2026-10-17T10:08:00Z"),
    ];
    const marks = { general: "2026-10-17T10:00:00Z", events: "2026-10-17T10:07:00Z", empty: "" };
    expect(unreadIn(messages, "general", marks.general, "me")).toBe(1);
    expect(unreadIn(messages, "events", marks.events, "me")).toBe(0);
    expect(unreadIn(messages, "empty", marks.empty, "me")).toBe(1);
    expect(unreadIn(messages, "never-seen", undefined, "me")).toBe(0);
  });

  it("reads the open channel to its newest message and leaves the others", () => {
    const marks = { general: "2026-10-17T10:00:00Z", events: "2026-10-17T10:00:00Z" };
    const newest = { general: "2026-10-17T11:00:00Z", events: "2026-10-17T11:00:00Z" };
    expect(nextMarks(marks, newest, "general")).toEqual({
      general: "2026-10-17T11:00:00Z",
      events: "2026-10-17T10:00:00Z",
    });
    expect(nextMarks(marks, { general: "2026-10-17T10:00:00Z" }, "general")).toBe(marks);
  });
});
