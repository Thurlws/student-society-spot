import { describe, expect, it } from "vitest";
import { auditActor, describeAuditEntry, type AuditEntry } from "@/lib/audit";

const entry = (over: Partial<AuditEntry>): AuditEntry => ({
  id: 1,
  at: "2026-10-16T10:00:00Z",
  actorId: "admin",
  actorRole: "university_admin",
  action: "committee.added",
  universityId: "tud",
  societyId: "soc",
  subjectId: "jane",
  details: {},
  ...over,
});
const names = { people: { admin: "Aoife Admin", jane: "Jane Doe" }, societies: { soc: "QuizSoc" } };

describe("Audit log sentences", () => {
  it("names the person, the society and the position", () => {
    expect(describeAuditEntry(entry({ details: { position: "Chair" } }), names)).toBe(
      "Jane Doe joined QuizSoc's committee as Chair",
    );
  });

  it("says when the person or society is gone", () => {
    expect(
      describeAuditEntry(
        entry({ action: "committee.removed", subjectId: "gone", societyId: "gone" }),
        names,
      ),
    ).toBe("A deleted account was taken off a deleted society's committee");
  });

  it("describes invites by what they grant", () => {
    expect(
      describeAuditEntry(
        entry({
          action: "invite.created",
          details: { email: "x@mytudublin.ie", role: "university_admin" },
        }),
        names,
      ),
    ).toBe("x@mytudublin.ie was invited as a university admin");
    expect(
      describeAuditEntry(
        entry({
          action: "invite.cancelled",
          details: { email: "x@mytudublin.ie", role: "committee", position: "Treasurer" },
        }),
        names,
      ),
    ).toBe("The invite for x@mytudublin.ie to QuizSoc's committee as Treasurer was cancelled");
  });

  it("tells a rename apart from an address change", () => {
    const from = { name: "Quiz Society", short_name: "QuizSoc", slug: "quiz" };
    expect(
      describeAuditEntry(
        entry({
          action: "society.renamed",
          details: { from, to: { ...from, name: "Totally Official Society" } },
        }),
        names,
      ),
    ).toBe("Quiz Society was renamed Totally Official Society");
    expect(
      describeAuditEntry(
        entry({ action: "society.renamed", details: { from, to: { ...from, slug: "quizsoc" } } }),
        names,
      ),
    ).toBe("Quiz Society's address changed from quiz to quizsoc");
  });

  it("counts dismissed reports", () => {
    expect(
      describeAuditEntry(entry({ action: "reports.dismissed", details: { reports: 2 } }), names),
    ).toBe("2 reports about a message in QuizSoc were closed, and the message stayed");
  });

  it("names the actor when the reader can see them, and their role when not", () => {
    expect(auditActor(entry({}), names)).toBe("Aoife Admin");
    expect(auditActor(entry({ actorId: "hidden", actorRole: "platform_admin" }), names)).toBe(
      "A platform admin",
    );
    expect(auditActor(entry({ actorId: null, actorRole: "system" }), names)).toBe("Automatic");
  });

  it("falls back to the action name for anything new", () => {
    expect(describeAuditEntry(entry({ action: "something.new" }), names)).toBe("something.new");
  });
});
