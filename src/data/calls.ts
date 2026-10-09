import type { CallRecap, CallRoom } from "@/lib/types";

/** Always-open drop-in rooms (Discord-style) for every society. Moves to the database in Phase 3. */
export const roomsFor = (societies: { id: string }[]): CallRoom[] =>
  societies.flatMap((s) => [
    { id: `${s.id}-lounge`, societyId: s.id, name: "Lounge", kind: "room" as const, description: "Drop in, say hi, hang out" },
    { id: `${s.id}-huddle`, societyId: s.id, name: "Planning huddle", kind: "room" as const, description: "Quick catch-ups about upcoming plans" },
  ]);

/** Real presence arrives with Phase 3; never invent people. */
export function roomPresence(_roomId: string): string[] {
  return [];
}

export const initialMeetings: CallRoom[] = [];
export const initialRecaps: CallRecap[] = [];

export function callScript(societyName: string, others: string[]): { speaker: string; text: string }[] {
  const [a = "Priya Nair", b = "Sam Okafor", c = a] = others;
  return [
    { speaker: a, text: `Hey everyone! Good to see the ${societyName} crew.` },
    { speaker: b, text: "Hi! Shall we go through the plan for next week?" },
    { speaker: a, text: "Yes — I think we need to confirm the room booking by Wednesday." },
    { speaker: c, text: "I can take that, I'll email the students' union tomorrow." },
    { speaker: b, text: "We should also post an announcement so members know about it." },
    { speaker: a, text: "Good shout. Let's keep the budget under 150 euro this time." },
    { speaker: b, text: "Agreed. Could we team up with another society to share costs?" },
    { speaker: c, text: "Society Pulse suggested a few — I'll reach out to one." },
    { speaker: a, text: "Great, so: room booking, announcement, and a collab outreach." },
  ];
}
