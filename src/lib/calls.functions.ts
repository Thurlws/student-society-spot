import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { fallbackAnswer, fallbackSummary } from "./call-recap-fallback";
import type { CallSummary, TranscriptLine } from "./types";

const line = z.object({ speaker: z.string().max(80), text: z.string().max(2000), at: z.number() });
const transcriptToText = (t: z.infer<typeof line>[]) =>
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

/** Hourly AI quota per user. The limits and the lock live in reserve_society_ai (migration 0009). */
async function reserveQuota(userId: string, feature: "summary" | "question" | "transcribe") {
  const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
  const { data, error } = await supabaseAdmin.rpc("reserve_society_ai", {
    _uid: userId,
    _feature: feature,
  });
  return !error && data === true;
}

/**
 * Writes the recap for a call the caller took part in (a call_participants row from their
 * token) or whose society they're on the committee of. Saved server-side; returns its id.
 */
export const summarizeCall = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator(
    z.object({
      roomId: z.string().uuid(),
      transcript: z.array(line).min(1).max(600),
      durationSec: z.number().int().min(0).max(86400),
    }),
  )
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { data: room } = await supabaseAdmin
      .from("call_rooms")
      .select("id, name, society_id, societies(name, short_name)")
      .eq("id", data.roomId)
      .maybeSingle();
    if (!room) throw new Error("That call doesn't exist.");
    const [{ data: joined }, { data: committee }] = await Promise.all([
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
    if (!joined?.length && !committee?.length)
      throw new Error("Only people who took part in this call can create its recap.");

    const soc = room.societies as unknown as { name: string; short_name: string };
    let summary: CallSummary;
    if (!(await reserveQuota(userId, "summary"))) {
      summary = { ...fallbackSummary(data.transcript, data.durationSec), source: "fallback" };
    } else {
      try {
        const { aiObject } = await import("./ai.server");
        summary = {
          ...(await aiObject(
            "You summarise student society video calls. Write in a friendly, clear tone — not corporate, not slangy. Overview: 1–2 sentences. Topics: short labels. Decisions: only things actually agreed. Action items: who will do what; use 'Someone' if no owner was named. Use empty arrays when there is nothing. Never invent facts.",
            `Society: ${soc.name}\nCall: ${room.name}\n\nTranscript:\n${transcriptToText(data.transcript)}`,
            summarySchema,
          )),
          source: "ai",
        };
      } catch (e) {
        console.warn("AI summary unavailable, using fallback:", e instanceof Error ? e.message : e);
        summary = fallbackSummary(data.transcript, data.durationSec);
      }
    }

    // Everyone who took part in this call within its duration (plus a margin) can read the recap.
    const since = new Date(Date.now() - (data.durationSec + 600) * 1000).toISOString();
    const { data: people } = await supabaseAdmin
      .from("call_participants")
      .select("user_id, guest_name, profiles(display_name)")
      .eq("room_id", room.id)
      .gte("joined_at", since);
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
        summary: summary as unknown as Record<string, never>,
        created_by: userId,
      })
      .select("id")
      .single();
    if (error || !saved) throw new Error("Couldn't save the recap. Try again.");
    return { id: saved.id, source: summary.source ?? "ai" };
  });

/** Questions about a recap the caller can read (RLS). Q&A is saved on the recap. */
export const askAboutCall = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator(
    z.object({ recapId: z.string().uuid(), question: z.string().trim().min(1).max(1000) }),
  )
  .handler(async ({ data, context }) => {
    const { data: recap } = await context.supabase
      .from("call_recaps")
      .select("id, title, transcript, qa")
      .eq("id", data.recapId)
      .maybeSingle();
    if (!recap) throw new Error("You can't see this recap.");
    const transcript = (recap.transcript ?? []) as unknown as TranscriptLine[];
    const history = (
      (recap.qa ?? []) as unknown as { role: "user" | "assistant"; content: string }[]
    ).slice(-40);
    let answer: string;
    if (!transcript.length)
      answer =
        "The transcript for this call has been deleted (transcripts are kept for 7 days), so I can only go by the summary above.";
    else if (!(await reserveQuota(context.userId, "question")))
      answer = "You've asked a lot of questions in the last hour — try again a bit later.";
    else {
      try {
        const { aiText } = await import("./ai.server");
        answer = await aiText(
          `You are the SocConnect call assistant. Answer questions about this call using only the transcript below. Be concise and friendly; use short markdown lists when helpful. If the transcript doesn't cover it, say so.\n\nCall: ${recap.title}\nTranscript:\n${transcriptToText(transcript)}`,
          [...history, { role: "user", content: data.question }],
        );
      } catch (e) {
        console.warn("AI Q&A unavailable, using fallback:", e instanceof Error ? e.message : e);
        answer = fallbackAnswer(transcript, data.question);
      }
    }
    const qa = [
      ...history,
      { role: "user" as const, content: data.question },
      { role: "assistant" as const, content: answer },
    ];
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    await supabaseAdmin.from("call_recaps").update({ qa }).eq("id", recap.id);
    return { answer };
  });

async function transcribe(audio: string, mime: string) {
  const { aiTranscribe } = await import("./ai.server");
  const bin = Uint8Array.from(atob(audio), (c) => c.charCodeAt(0));
  try {
    return { text: await aiTranscribe(bin, mime), error: null as string | null };
  } catch (e) {
    return { text: "", error: e instanceof Error ? e.message : "Transcription failed" };
  }
}
const clip = z.object({ audio: z.string().min(10).max(4_000_000), mime: z.string().max(80) });

/** Captions for signed-in members. */
export const transcribeClip = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator(clip)
  .handler(async ({ data, context }) => {
    if (!(await reserveQuota(context.userId, "transcribe")))
      return { text: "", error: CAPTION_LIMIT };
    return transcribe(data.audio, data.mime);
  });

/** Captions for guests: only while their invite code is still valid, on its creator's quota. */
export const transcribeGuestClip = createServerFn({ method: "POST" })
  .inputValidator(clip.extend({ code: z.string().regex(/^[a-z0-9]{8,32}$/) }))
  .handler(async ({ data }) => {
    const { inviteCreator } = await import("./livekit.functions");
    const creator = await inviteCreator(data.code);
    if (!creator) return { text: "", error: "This call link has expired." };
    if (!(await reserveQuota(creator, "transcribe"))) return { text: "", error: CAPTION_LIMIT };
    return transcribe(data.audio, data.mime);
  });

const CAPTION_LIMIT = "Captions have reached their hourly limit. Type into the transcript instead.";
