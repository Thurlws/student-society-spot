import { describe, expect, it } from "vitest";
import { groupMessages } from "@/lib/message-groups";
import type { DiscussionMessage } from "@/lib/types";

const msg = (id: string, authorId: string, createdAt: string): DiscussionMessage => ({
  id,
  channelId: "general",
  author: authorId === "d" ? "Davit" : "Aoife",
  authorId,
  body: id,
  createdAt,
});

describe("groupMessages", () => {
  it("puts one person's messages in a row under one name", () => {
    const groups = groupMessages([
      msg("1", "a", "2026-10-12T10:00:00Z"),
      msg("2", "d", "2026-10-12T10:01:00Z"),
      msg("3", "d", "2026-10-12T10:02:00Z"),
      msg("4", "d", "2026-10-12T10:03:00Z"),
      msg("5", "a", "2026-10-12T10:04:00Z"),
    ]);
    expect(groups.map((g) => g.messages.map((m) => m.id))).toEqual([["1"], ["2", "3", "4"], ["5"]]);
    expect(groups.map((g) => g.author)).toEqual(["Aoife", "Davit", "Aoife"]);
  });

  it("starts a new group after a pause of more than seven minutes", () => {
    const groups = groupMessages([
      msg("1", "d", "2026-10-12T10:00:00Z"),
      msg("2", "d", "2026-10-12T10:07:00Z"),
      msg("3", "d", "2026-10-12T10:15:00Z"),
    ]);
    expect(groups.map((g) => g.messages.map((m) => m.id))).toEqual([["1", "2"], ["3"]]);
  });

  it("starts a new group, with a date line, on a new day in Dublin", () => {
    // 22:58 and 23:02 UTC are 23:58 and 00:02 in Dublin (summer time): two different days.
    const groups = groupMessages([
      msg("1", "d", "2026-10-12T22:58:00Z"),
      msg("2", "d", "2026-10-12T23:02:00Z"),
    ]);
    expect(groups.map((g) => [g.day, g.startsDay])).toEqual([
      ["2026-10-12", true],
      ["2026-10-13", true],
    ]);
  });

  it("returns nothing for an empty channel", () => {
    expect(groupMessages([])).toEqual([]);
  });
});
