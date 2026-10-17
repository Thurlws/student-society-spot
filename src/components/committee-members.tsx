import { Check, Search, UserMinus, X } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { useData } from "@/lib/api/store";
import { formatDate, toDublin } from "@/lib/format";
import type { Society, SocietyMember } from "@/lib/types";
import { FeeBadge } from "@/components/membership-fee";
import { Badge } from "@/components/ui/badge";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";

const initials = (name: string) =>
  name
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2);

/**
 * The Members tab as the society's committee sees it: everyone who joined or asked to, with
 * their fee, and what the committee can do about each. Other people see only the committee
 * and themselves.
 */
export function CommitteeMembers({ society }: { society: Society }) {
  const { societyMembers, resolveRequest, feesEnabled } = useData();
  const [q, setQ] = useState("");
  const all = societyMembers.filter((m) => m.societyId === society.id);
  const shown = all.filter((m) =>
    `${m.name} ${m.course}`.toLowerCase().includes(q.trim().toLowerCase()),
  );
  const pending = shown.filter((m) => m.status === "pending");
  const members = shown.filter((m) => m.status === "member");
  const onCommittee = new Set(society.committee.map((c) => c.userId));
  const showFee = feesEnabled && !!society.membershipFeeCents;

  const decide = async (m: SocietyMember, decision: "approve" | "decline") => {
    const o = await resolveRequest(m.membershipId, decision);
    if (!o.ok) return void toast.error(o.error);
    toast.success(decision === "approve" ? `${m.name} is now a member` : `Declined ${m.name}`);
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-muted-foreground">
          {all.filter((m) => m.status === "member").length} members
          {all.some((m) => m.status === "pending") &&
            `, ${all.filter((m) => m.status === "pending").length} waiting for approval`}
          . Only the committee sees this list.
        </p>
        <div className="relative w-full sm:w-64">
          <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            aria-label="Search members"
            placeholder="Search by name or course"
            className="pl-9"
            value={q}
            onChange={(e) => setQ(e.target.value)}
          />
        </div>
      </div>

      <section className="rounded-xl border bg-card p-5 shadow-soft">
        <h3 className="font-semibold">Committee</h3>
        <ul className="mt-3 divide-y">
          {society.committee.map((c) => (
            <li key={c.userId} className="flex items-center gap-3 py-2.5">
              <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-primary-soft text-xs font-semibold text-primary">
                {initials(c.name)}
              </span>
              <span className="min-w-0">
                <span className="block truncate text-sm font-medium">{c.name}</span>
                <span className="block text-xs text-muted-foreground">{c.position}</span>
              </span>
            </li>
          ))}
        </ul>
        <p className="mt-2 text-xs text-muted-foreground">
          Your university's admins change the committee.
        </p>
      </section>

      {pending.length > 0 && (
        <section className="rounded-xl border bg-card p-5 shadow-soft">
          <h3 className="font-semibold">Waiting for approval</h3>
          <ul className="mt-3 divide-y">
            {pending.map((m) => (
              <MemberRow key={m.membershipId} m={m} fee={showFee}>
                <Button size="sm" variant="outline" onClick={() => decide(m, "decline")}>
                  <X />
                  Decline
                </Button>
                <Button size="sm" onClick={() => decide(m, "approve")}>
                  <Check />
                  Approve
                </Button>
              </MemberRow>
            ))}
          </ul>
        </section>
      )}

      <section className="rounded-xl border bg-card p-5 shadow-soft">
        <h3 className="font-semibold">Members</h3>
        {members.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">
            {q.trim() ? "Nobody matches that search." : "No members yet."}
          </p>
        ) : (
          <ul className="mt-3 divide-y">
            {members.map((m) => (
              <MemberRow key={m.membershipId} m={m} fee={showFee}>
                {onCommittee.has(m.userId) ? (
                  <Badge variant="soft">Committee</Badge>
                ) : (
                  <RemoveMemberButton member={m} societyName={society.shortName} />
                )}
              </MemberRow>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}

function MemberRow({
  m,
  fee,
  children,
}: {
  m: SocietyMember;
  fee: boolean;
  children: React.ReactNode;
}) {
  return (
    <li className="flex flex-wrap items-center gap-3 py-2.5">
      <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-muted text-xs font-semibold">
        {initials(m.name)}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-medium">{m.name}</span>
        <span className="block text-xs text-muted-foreground">
          {[
            m.course,
            `${m.status === "pending" ? "asked" : "joined"} ${formatDate(toDublin(m.since).date, { month: "short", year: "numeric" })}`,
          ]
            .filter(Boolean)
            .join(", ")}
        </span>
      </span>
      <span className="flex shrink-0 items-center gap-2">
        {fee && <FeeBadge fee={m.fee} />}
        {children}
      </span>
    </li>
  );
}

function RemoveMemberButton({
  member,
  societyName,
}: {
  member: SocietyMember;
  societyName: string;
}) {
  const { removeMember } = useData();
  const [reason, setReason] = useState("");
  return (
    <AlertDialog onOpenChange={(open) => open && setReason("")}>
      <AlertDialogTrigger asChild>
        <Button size="sm" variant="ghost" aria-label={`Remove ${member.name}`}>
          <UserMinus />
          Remove
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            Remove {member.name} from {societyName}?
          </AlertDialogTitle>
          <AlertDialogDescription>
            They lose access to members-only discussions, calls and resources, and they're told they
            were removed. They can join again unless the society needs approval.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <div className="space-y-1.5">
          <Label htmlFor="remove-reason">Reason (optional, they see it)</Label>
          <Textarea
            id="remove-reason"
            rows={2}
            maxLength={300}
            value={reason}
            onChange={(e) => setReason(e.target.value)}
          />
        </div>
        <AlertDialogFooter>
          <AlertDialogCancel>Keep them</AlertDialogCancel>
          <AlertDialogAction
            className={buttonVariants({ variant: "destructive" })}
            onClick={async () => {
              const o = await removeMember(member.membershipId, reason);
              if (!o.ok) return void toast.error(o.error);
              toast(`${member.name} was removed`);
            }}
          >
            Remove
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
