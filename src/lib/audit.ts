// Turns audit log entries (migration 0024) into sentences for /admin. Pure, so it can be tested.

export type AuditEntry = {
  id: number;
  at: string;
  actorId: string | null;
  actorRole: string;
  action: string;
  universityId: string | null;
  societyId: string | null;
  subjectId: string | null;
  details: Record<string, unknown>;
};

/** Names the reader can see: profiles and societies by id. Anything missing was deleted or is out of their reach. */
export type AuditNames = { people: Record<string, string>; societies: Record<string, string> };

const ROLE_LABEL: Record<string, string> = {
  platform_admin: "a platform admin",
  university_admin: "a university admin",
  committee: "a committee member",
  member: "a member",
};

/** Who did it: a name when the reader can see it, otherwise what they were. */
export function auditActor(e: AuditEntry, names: AuditNames) {
  if (e.actorRole === "system" || !e.actorId) return "Automatic";
  return names.people[e.actorId] ?? capitalise(ROLE_LABEL[e.actorRole] ?? "someone");
}

const capitalise = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
const text = (v: unknown) => (typeof v === "string" ? v : "");
const part = (v: unknown, k: string) =>
  v && typeof v === "object" ? text((v as Record<string, unknown>)[k]) : "";

/** What happened, in one sentence. */
export function describeAuditEntry(e: AuditEntry, names: AuditNames) {
  const d = e.details;
  const who = (e.subjectId && names.people[e.subjectId]) || "A deleted account";
  const society =
    (e.societyId && names.societies[e.societyId]) || text(d["name"]) || "a deleted society";
  switch (e.action) {
    case "platform_admin.added":
      return `${who} became a platform admin`;
    case "platform_admin.removed":
      return `${who} is no longer a platform admin`;
    case "university_admin.added":
      return `${who} became a university admin`;
    case "university_admin.removed":
      return `${who} is no longer a university admin`;
    case "committee.added":
      return `${who} joined ${society}'s committee as ${text(d["position"])}`;
    case "committee.changed":
      return `${who}'s position on ${society}'s committee changed from ${part(d["from"], "position")} to ${part(d["to"], "position")}`;
    case "committee.removed":
      return `${who} was taken off ${society}'s committee`;
    case "invite.created":
    case "invite.cancelled": {
      const email = text(d["email"]);
      const as =
        d["role"] === "platform_admin"
          ? "as a platform admin"
          : d["role"] === "university_admin"
            ? "as a university admin"
            : `to ${society}'s committee as ${text(d["position"])}`;
      return e.action === "invite.created"
        ? `${email} was invited ${as}`
        : `The invite for ${email} ${as} was cancelled`;
    }
    case "society.created":
      return `${text(d["name"])} was created`;
    case "society.deleted":
      return `${text(d["name"])} was deleted`;
    case "society.archived":
      return `${society} was archived`;
    case "society.restored":
      return `${society} was restored`;
    case "society.renamed": {
      const from = part(d["from"], "name");
      const to = part(d["to"], "name");
      const fromSlug = part(d["from"], "slug");
      const toSlug = part(d["to"], "slug");
      if (from !== to) return `${from} was renamed ${to}`;
      if (fromSlug !== toSlug) return `${to}'s address changed from ${fromSlug} to ${toSlug}`;
      return `${to}'s short name changed from ${part(d["from"], "short_name")} to ${part(d["to"], "short_name")}`;
    }
    case "society.links_changed":
      return `${society}'s official links were changed`;
    case "society.moved":
      return `${society} was moved to another university`;
    case "university.created":
      return `${text(d["name"])} was added`;
    case "university.renamed":
      return `${part(d["from"], "name")} was renamed ${part(d["to"], "name")}`;
    case "university.deleted":
      return `${text(d["name"])} was deleted`;
    case "domain.added":
      return `@${text(d["domain"])} can now sign in`;
    case "domain.removed":
      return `@${text(d["domain"])} can no longer sign in`;
    case "message.removed":
      return `A message in ${society} #${text(d["channel"])} was removed${d["reported"] ? " after a report" : ""}`;
    case "reports.dismissed": {
      const n = Number(d["reports"]) || 1;
      return `${n === 1 ? "A report" : `${n} reports`} about a message in ${society} ${n === 1 ? "was" : "were"} closed, and the message stayed`;
    }
    case "event.cancelled": {
      const reason = text(d["reason"]);
      return `${society} cancelled ${text(d["title"])}${reason ? `: ${reason}` : ""}`;
    }
    case "account.deleted":
      return "An account was deleted";
    case "person.suspended":
      return `${who} was suspended: ${text(d["reason"])}`;
    case "person.reinstated":
      return `${who}'s suspension was lifted`;
    default:
      return e.action;
  }
}
