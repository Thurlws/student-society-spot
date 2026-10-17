import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import { fallbackAnswer } from "./call-recap-fallback";
import type { TranscriptLine } from "./types";

const line = z.object({ speaker: z.string().max(80), text: z.string().max(2000), at: z.number() });

/** The call's recap, written once per call and saved server-side (calls.server.ts); returns its id. */
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
    const { writeRecap } = await import("./calls.server");
    return writeRecap(context.supabase, context.userId, data);
  });

/** Questions about a recap the caller can read (RLS). Q&A is saved on the recap. */
export const askAboutCall = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator(
    z.object({ recapId: z.string().uuid(), question: z.string().trim().min(1).max(1000) }),
  )
  .handler(async ({ data, context }) => {
    const { reserveQuota, transcriptToText } = await import("./calls.server");
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
        const { log } = await import("./monitoring.server");
        log("warn", "ai.fallback", { area: "ai", feature: "question" }, e);
        answer = fallbackAnswer(transcript, data.question);
      }
    }
    const qa = [
      ...history,
      { role: "user" as const, content: data.question },
      { role: "assistant" as const, content: answer },
    ];
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const { error } = await supabaseAdmin.from("call_recaps").update({ qa }).eq("id", recap.id);
    if (error) {
      // The answer still goes back; only its place in the recap's history is lost.
      const { log } = await import("./monitoring.server");
      log("warn", "recap.qa_not_saved", { area: "calls" }, error.message);
    }
    return { answer };
  });

async function transcribe(audio: string, mime: string) {
  const { aiTranscribe } = await import("./ai.server");
  try {
    const bin = Uint8Array.from(atob(audio), (c) => c.charCodeAt(0));
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
    const { reserveQuota } = await import("./calls.server");
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
    const { reserveQuota } = await import("./calls.server");
    if (!(await reserveQuota(creator, "transcribe"))) return { text: "", error: CAPTION_LIMIT };
    return transcribe(data.audio, data.mime);
  });

const CAPTION_LIMIT = "Captions have reached their hourly limit. Type into the transcript instead.";
