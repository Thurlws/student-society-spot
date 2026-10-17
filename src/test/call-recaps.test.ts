// @vitest-environment node
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";

type Row = Record<string, unknown>;

/** Just enough of supabase-js for writeRecap: filters, one row or many, inserts and updates. */
function fakeDb(tables: Record<string, Row[]>) {
  return {
    from(table: string) {
      let rows = [...(tables[table] ??= [])];
      let patch: Row | null = null;
      const q = {
        select: () => q,
        order: () => q,
        eq: (c: string, v: unknown) => ((rows = rows.filter((r) => r[c] === v)), q),
        gte: (c: string, v: string) => ((rows = rows.filter((r) => String(r[c]) >= v)), q),
        limit: (n: number) => ((rows = rows.slice(0, n)), q),
        insert: (row: Row) => {
          const saved = {
            id: `recap-${tables[table]!.length + 1}`,
            created_at: new Date().toISOString(),
            ...row,
          };
          tables[table]!.push(saved);
          rows = [saved];
          return q;
        },
        update: (p: Row) => ((patch = p), q),
        maybeSingle: async () => ({ data: rows[0] ?? null, error: null }),
        single: async () => ({
          data: rows[0] ?? null,
          error: rows[0] ? null : { message: "none" },
        }),
        then: (done: (r: { data: Row[]; error: null }) => void) => {
          if (patch) for (const r of rows) Object.assign(r, patch);
          done({ data: rows, error: null });
        },
      };
      return q;
    },
    rpc: async () => ({ data: true, error: null }),
  };
}

const hoisted = vi.hoisted(() => ({
  admin: null as unknown,
  aiObject: vi.fn(),
}));
vi.mock("@/integrations/supabase/client.server", () => ({
  get supabaseAdmin() {
    return hoisted.admin;
  },
}));
vi.mock("@/lib/ai.server", () => ({ aiObject: hoisted.aiObject }));

const { writeRecap } = await import("@/lib/calls.server");

const room = {
  id: "room-1",
  name: "Lounge",
  society_id: "soc-1",
  societies: { name: "Chess Society", short_name: "Chess" },
};
const call = {
  roomId: "room-1",
  durationSec: 1800,
  transcript: [{ speaker: "Aoife", text: "We agreed to book the hall.", at: 5 }],
};
const minutesAgo = (m: number) => new Date(Date.now() - m * 60_000).toISOString();

let db: Record<string, Row[]>;
const asUser = (rooms: Row[]) =>
  fakeDb({ ...db, call_rooms: rooms }) as unknown as SupabaseClient<Database>;

beforeEach(() => {
  db = {
    // The room exists; asUser decides whether RLS lets this person see it.
    call_rooms: [room],
    call_participants: [
      { id: "p1", room_id: "room-1", user_id: "aoife", joined_at: minutesAgo(31) },
      { id: "p2", room_id: "room-1", user_id: "brian", joined_at: minutesAgo(30) },
    ],
    society_roles: [],
    call_recaps: [],
  };
  hoisted.admin = fakeDb(db);
  hoisted.aiObject.mockReset();
  hoisted.aiObject.mockResolvedValue({
    overview: "Booked the hall.",
    topics: [],
    decisions: [],
    actionItems: [],
  });
});

describe("call recaps", () => {
  it("refuses someone who can no longer see the room, even if they once joined it", async () => {
    // RLS hides the room from a removed member; their old call_participants row is still there.
    await expect(writeRecap(asUser([]), "aoife", call)).rejects.toThrow(/Only members/);
    expect(db["call_recaps"]).toHaveLength(0);
    expect(hoisted.aiObject).not.toHaveBeenCalled();
  });

  it("writes one recap per call: the next person to leave gets the same one and can read it", async () => {
    const first = await writeRecap(asUser([room]), "aoife", call);
    expect(first.source).toBe("ai");
    expect(db["call_recaps"]![0]!["summary"]).toMatchObject({
      source: "ai",
      overview: "Booked the hall.",
    });

    db["call_participants"]!.push({
      id: "p3",
      room_id: "room-1",
      user_id: "ciara",
      joined_at: minutesAgo(1),
    });
    const second = await writeRecap(asUser([room]), "ciara", call);

    expect(second).toEqual({ id: first.id, source: "existing" });
    expect(db["call_recaps"]).toHaveLength(1);
    expect(db["call_recaps"]![0]!["participant_ids"]).toEqual(["aoife", "brian", "ciara"]);
    expect(hoisted.aiObject).toHaveBeenCalledTimes(1);
  });

  it("doesn't reuse the recap of an earlier call in the same room", async () => {
    db["call_recaps"]!.push({
      id: "old",
      room_id: "room-1",
      participant_ids: ["aoife"],
      created_at: minutesAgo(6),
    });
    const r = await writeRecap(asUser([room]), "aoife", { ...call, durationSec: 300 });
    expect(r.id).not.toBe("old");
    expect(db["call_recaps"]).toHaveLength(2);
  });

  it("keeps the basic recap, marked as such, when the AI fails", async () => {
    hoisted.aiObject.mockRejectedValue(new Error("gateway down"));
    const r = await writeRecap(asUser([room]), "aoife", call);
    expect(r.source).toBe("fallback");
    expect(db["call_recaps"]![0]!["summary"]).toMatchObject({ source: "fallback" });
  });
});
