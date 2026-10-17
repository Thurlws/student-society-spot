// Server-only: call recaps and AI quotas. Kept out of calls.functions.ts, which also ships to the
// browser, so the admin client stays on the server and the rules can be tested on their own.
import { z } from "zod";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Database } from "@/integrations/supabase/types";
import { fallbackSummary } from "./call-recap-fallback";
import type { CallSummary, TranscriptLine } from "./types";

/** Hourly AI quota per user. The limits and the lock live in reserve_society_ai (migration 0009). */
export async function reserveQuota(userId: string, feature: "summary" | "question" | "transcribe") {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data, error } = await supabaseAdmin.rpc("reserve_society_ai", {
    _uid: userId,
    _feature: feature,
  });
  return !error && data === true;
}

// A type, not the interface, so it's assignable to the jsonb column.
type Line = Pick<TranscriptLine, "speaker" | "text" | "at">;
export type RecapInput = { roomId: string; transcript: Line[]; durationSec: number };

export const transcriptToText = (t: Line[]) =>
  t
    .map(
      (l) =>
        `[${Math.floor(l.at / 60)}:${String(Math.floor(l.at % 60)).padStart(2, "0")}] ${l.speaker}: ${l.text}`,
    )
    .join("\n");

const summarySchema = z.object({
  overview: z.string(),
  topics: z.array(z.string()),
  decisions: z.array(z.string()),
  actionItems: z.array(z.object({ owner: z.string(), task: z.string() })),
});

const CHECK_FAILED = "Couldn't check this call. Try again.";
const SAVE_FAILED = "Couldn't save the recap. Try again.";

/**
 * Writes the recap of a call in a room the caller can see (RLS: the society's current members
 * and committee) and either took part in or is on the committee of. Everyone in a call has the
 * same transcript, so a call gets one recap: whoever leaves first writes it, and anyone leaving
 * in the next ten minutes gets that one and can read it. "existing" says it was someone else's.
 */
export async function writeRecap(
  supabase: SupabaseClient<Database>,
  userId: string,
  data: RecapInput,
): Promise<{ id: string; source: "ai" | "fallback" | "existing" }> {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data: room, error: roomError } = await supabase
    .from("call_rooms")
    .select("id, name, society_id, societies(name, short_name)")
    .eq("id", data.roomId)
    .maybeSingle();
  if (roomError) throw new Error(CHECK_FAILED);
  if (!room) throw new Error("Only members of this society can create its call recaps.");
  const [joined, committee] = await Promise.all([
    supabase
      .from("call_participants")
      .select("id")
      .eq("room_id", room.id)
      .eq("user_id", userId)
      .limit(1),
    supabase
      .from("society_roles")
      .select("id")
      .eq("society_id", room.society_id)
      .eq("user_id", userId)
      .limit(1),
  ]);
  if (joined.error || committee.error) throw new Error(CHECK_FAILED);
  if (!joined.data?.length && !committee.data?.length)
    throw new Error("Only people who took part in this call can create its recap.");

  // Made since this person's call started, and at most ten minutes ago: an earlier call in the
  // same drop-in room is never reused.
  const since = new Date(Date.now() - Math.min(data.durationSec, 600) * 1000).toISOString();
  const { data: existing, error: existingError } = await supabaseAdmin
    .from("call_recaps")
    .select("id, participant_ids")
    .eq("room_id", room.id)
    .gte("created_at", since)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (existingError) throw new Error(SAVE_FAILED);
  if (existing) {
    if (!existing.participant_ids.includes(userId)) {
      const { error } = await supabaseAdmin
        .from("call_recaps")
        .update({ participant_ids: [...existing.participant_ids, userId] })
        .eq("id", existing.id);
      if (error) throw new Error(SAVE_FAILED);
    }
    return { id: existing.id, source: "existing" };
  }

  // Everyone who took part in this call within its duration (plus a margin) can read the recap.
  const joinedSince = new Date(Date.now() - (data.durationSec + 600) * 1000).toISOString();
  const { data: people, error: peopleError } = await supabaseAdmin
    .from("call_participants")
    .select("user_id, guest_name, profiles(display_name)")
    .eq("room_id", room.id)
    .gte("joined_at", joinedSince);
  if (peopleError) throw new Error(SAVE_FAILED);
  const ids = [
    ...new Set([userId, ...(people ?? []).map((p) => p.user_id).filter((x): x is string => !!x)]),
  ];
  const names = [
    ...new Set(
      [
        ...(people ?? []).map(
          (p) =>
            (p.profiles as unknown as { display_name: string } | null)?.display_name ||
            p.guest_name ||
            "",
        ),
        ...data.transcript.map((l) => l.speaker),
      ].filter(Boolean),
    ),
  ];

  // Saved with the basic summary first, so people leaving while the AI writes find this recap
  // instead of starting another; the AI's summary replaces it below.
  const soc = room.societies as unknown as { name: string; short_name: string };
  const basic: CallSummary = {
    ...fallbackSummary(data.transcript, data.durationSec),
    source: "fallback",
  };
  const { data: saved, error } = await supabaseAdmin
    .from("call_recaps")
    .insert({
      room_id: room.id,
      society_id: room.society_id,
      title: `${room.name} — ${soc.short_name}`,
      started_at: new Date(Date.now() - data.durationSec * 1000).toISOString(),
      duration_sec: data.durationSec,
      participants: names,
      participant_ids: ids,
      transcript: data.transcript,
      summary: basic as unknown as Record<string, never>,
      created_by: userId,
    })
    .select("id")
    .single();
  if (error || !saved) throw new Error(SAVE_FAILED);

  if (!(await reserveQuota(userId, "summary"))) return { id: saved.id, source: "fallback" };
  try {
    const { aiObject } = await import("./ai.server");
    const summary: CallSummary = {
      ...(await aiObject(
        "You summarise student society video calls. Write in a friendly, clear tone — not corporate, not slangy. Overview: 1–2 sentences. Topics: short labels. Decisions: only things actually agreed. Action items: who will do what; use 'Someone' if no owner was named. Use empty arrays when there is nothing. Never invent facts.",
        `Society: ${soc.name}\nCall: ${room.name}\n\nTranscript:\n${transcriptToText(data.transcript)}`,
        summarySchema,
      )),
      source: "ai",
    };
    const { error: updateError } = await supabaseAdmin
      .from("call_recaps")
      .update({ summary: summary as unknown as Record<string, never> })
      .eq("id", saved.id);
    if (updateError) throw new Error(updateError.message);
    return { id: saved.id, source: "ai" };
  } catch (e) {
    const { log } = await import("./monitoring.server");
    log("warn", "ai.fallback", { area: "ai", feature: "summary" }, e);
    return { id: saved.id, source: "fallback" };
  }
}
