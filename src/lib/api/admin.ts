import { supabase } from "@/integrations/supabase/client";
import type { AuditEntry, AuditNames } from "@/lib/audit";
import type { Json } from "@/integrations/supabase/types";
import type { ImportRow } from "@/lib/society-import";
import type { Outcome } from "@/lib/validation";

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

export type Person = {
  userId: string;
  name: string;
  course: string;
  year: string;
  joinedAt: string;
  suspendedAt: string | null;
  suspensionReason: string;
};

const errorText = (e: { message: string }) => e.message.replace(/^.*?ERROR:\s*/, "");

/** People at a university the caller manages, by part of their name or their exact email address. */
export async function findPeople(universityId: string, query: string): Promise<Person[]> {
  const { data, error } = await supabase.rpc("find_people", {
    _university_id: universityId,
    _query: query,
  });
  if (error) throw new Error(errorText(error));
  return (data ?? []).map((p) => ({
    userId: p.user_id,
    name: p.display_name || "Unnamed",
    course: p.course,
    year: p.year,
    joinedAt: p.joined_at,
    suspendedAt: p.suspended_at,
    suspensionReason: p.suspension_reason,
  }));
}

/** Everyone currently suspended at a university. Null before migration 0025. */
export async function loadSuspended(universityId: string): Promise<Person[] | null> {
  const { data, error } = await supabase
    .from("university_members")
    .select(
      "user_id, joined_at, suspended_at, suspension_reason, profiles(display_name, course, year)",
    )
    .eq("university_id", universityId)
    .not("suspended_at", "is", null)
    .order("suspended_at", { ascending: false });
  if (error?.code === "42703" || missingInDatabase(error)) return null;
  if (error) throw new Error(errorText(error));
  return (data ?? []).map((m) => {
    const p = m.profiles as { display_name: string; course: string; year: string } | null;
    return {
      userId: m.user_id,
      name: p?.display_name || "Unnamed",
      course: p?.course ?? "",
      year: p?.year ?? "",
      joinedAt: m.joined_at,
      suspendedAt: m.suspended_at,
      suspensionReason: m.suspension_reason,
    };
  });
}

export async function suspendUser(userId: string, reason: string): Promise<Outcome> {
  const { error } = await supabase.rpc("suspend_user", { _user_id: userId, _reason: reason });
  return error ? { ok: false, error: errorText(error) } : { ok: true };
}

export async function reinstateUser(userId: string): Promise<Outcome> {
  const { error } = await supabase.rpc("reinstate_user", { _user_id: userId });
  return error ? { ok: false, error: errorText(error) } : { ok: true };
}

export type ImportResult = { created: number; updated: number; tags_added: number };

/** Creates or updates a university's societies from a file's rows (migration 0028). */
export async function importSocieties(
  universityId: string,
  rows: ImportRow[],
): Promise<{ ok: true; result: ImportResult } | { ok: false; error: string }> {
  const { data, error } = await supabase.rpc("import_societies", {
    _university_id: universityId,
    _rows: rows as unknown as Json,
  });
  if (error)
    return {
      ok: false,
      error: missingInDatabase(error)
        ? "Importing needs a database update (migration 0028) first."
        : errorText(error),
    };
  return { ok: true, result: data as unknown as ImportResult };
}
