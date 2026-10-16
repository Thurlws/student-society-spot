import { supabase } from "@/integrations/supabase/client";
import type { AuditEntry, AuditNames } from "@/lib/audit";

/** A table or function that isn't in production yet: the code can be published before its migration. */
export const missingInDatabase = (e: { code?: string } | null) =>
  !!e && ["PGRST202", "PGRST205", "42P01", "42883"].includes(e.code ?? "");

export const ACTIVITY_PAGE = 50;

/**
 * The newest audit log entries for a university, plus platform-level ones for platform admins
 * (RLS hides those from everyone else), with the names the reader is allowed to see.
 * Null when the audit log isn't in the database yet (migration 0024).
 */
export async function loadActivity(
  universityId: string,
  before?: number,
): Promise<{ entries: AuditEntry[]; names: AuditNames } | null> {
  let q = supabase
    .from("audit_log")
    .select("*")
    .or(`university_id.eq.${universityId},university_id.is.null`)
    .order("id", { ascending: false })
    .limit(ACTIVITY_PAGE);
  if (before) q = q.lt("id", before);
  const { data, error } = await q;
  if (missingInDatabase(error)) return null;
  if (error) throw new Error(error.message);
  const entries: AuditEntry[] = (data ?? []).map((r) => ({
    id: r.id,
    at: r.at,
    actorId: r.actor_id,
    actorRole: r.actor_role,
    action: r.action,
    universityId: r.university_id,
    societyId: r.society_id,
    subjectId: r.subject_id,
    details: (r.details ?? {}) as Record<string, unknown>,
  }));
  const people = [
    ...new Set(entries.flatMap((e) => [e.actorId, e.subjectId]).filter((x): x is string => !!x)),
  ];
  const societies = [...new Set(entries.map((e) => e.societyId).filter((x): x is string => !!x))];
  const [p, s] = await Promise.all([
    people.length
      ? supabase.from("profiles").select("id, display_name").in("id", people)
      : { data: [] },
    societies.length
      ? supabase.from("societies").select("id, short_name").in("id", societies)
      : { data: [] },
  ]);
  return {
    entries,
    names: {
      people: Object.fromEntries((p.data ?? []).map((x) => [x.id, x.display_name || "Unnamed"])),
      societies: Object.fromEntries((s.data ?? []).map((x) => [x.id, x.short_name])),
    },
  };
}
