import { createFileRoute, Link } from "@tanstack/react-router";
import {
  CalendarPlus,
  Check,
  Megaphone,
  PencilLine,
  ShieldCheck,
  UserPlus,
  Users,
  X,
  CalendarDays,
  BookmarkCheck,
} from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { useData } from "@/lib/api/store";
import { todayIso } from "@/lib/format";
import { pageHead } from "@/lib/seo";
import { formatDate, timeAgo } from "@/lib/format";
import { PageHeader, EmptyState } from "@/components/cards";
import { SocietyAvatar } from "@/components/society-avatar";
import { CommitteeRequestsSummary } from "@/components/support-requests";
import { EventDialog } from "@/components/event-dialog";
import { AnnouncementDialog } from "@/components/announcement-dialog";
import { ReportedMessages } from "@/components/moderation";
import { CommitteeFees } from "@/components/membership-fee";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export const Route = createFileRoute("/_authenticated/committee")({
  // Report notifications link here with the society they're about.
  validateSearch: (s: Record<string, unknown>): { society?: string } =>
    typeof s["society"] === "string" ? { society: s["society"] } : {},
  head: () =>
    pageHead(
      "Committee Dashboard",
      "Manage your society: announcements, events, members and profile.",
    ),
  component: Committee,
});

function Committee() {
  const d = useData();
  const [modal, setModal] = useState<null | "ann" | "event" | "edit">(null);
  const seats = d.committeeSeats;
  const { society } = Route.useSearch();
  const [picked, setPicked] = useState(society ?? null);
  // A notification can change the society in the URL while the page is already open.
  const [linked, setLinked] = useState(society);
  if (society !== linked) {
    setLinked(society);
    setPicked(society ?? null);
  }
  if (!seats.length) {
    return (
      <EmptyState
        icon={ShieldCheck}
        title="Committee access only"
        body="This area is for society committee members. A platform admin can add you to your society's committee."
      />
    );
  }
  const slug = picked && seats.some((c) => c.slug === picked) ? picked : seats[0]!.slug;
  const found = d.getSociety(slug);
  const picker = seats.length > 1 && (
    <Select value={slug} onValueChange={setPicked}>
      <SelectTrigger className="w-56">
        <SelectValue />
      </SelectTrigger>
      <SelectContent>
        {seats.map((c) => (
          <SelectItem key={c.slug} value={c.slug}>
            {c.short_name}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
  if (!found) {
    const seat = seats.find((c) => c.slug === slug)!;
    return (
      <EmptyState
        icon={ShieldCheck}
        title={`${seat.short_name} committee`}
        body={`You're ${seat.position}. Your society's dashboard tools switch to live data in the next update.`}
        action={picker || undefined}
      />
    );
  }
  const s = found;
  const reqs = d.requests.filter((r) => r.societyId === s.id);
  const resolved = d.resolvedRequests.filter((r) => r.societyId === s.id);
  const upcoming = d.events.filter((e) => e.societyId === s.id && e.date >= todayIso());
  const live = upcoming.filter((e) => !e.cancelled);
  const anns = d.announcements.filter((a) => a.societyId === s.id);
  const saved = d.proposals.filter((p) => d.savedProposals.includes(p.id));

  return (
    <div className="space-y-8">
      <PageHeader
        title={`${s.shortName} committee`}
        subtitle={`You're managing ${s.name} as ${s.committee[0]?.position ?? "committee member"}.`}
        actions={
          <div className="flex gap-2">
            {picker}
            <Button variant="outline" asChild>
              <Link to="/societies/$societyId" params={{ societyId: s.id }}>
                View public page
              </Link>
            </Button>
          </div>
        }
      />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {[
          { l: "Members", v: s.memberCount, icon: Users },
          { l: "Pending requests", v: reqs.length, icon: UserPlus },
          { l: "Upcoming events", v: live.length, icon: CalendarDays },
          { l: "Announcements", v: anns.length, icon: Megaphone },
        ].map((x) => (
          <div key={x.l} className="rounded-xl border bg-card p-5 shadow-soft">
            <x.icon className="size-4 text-primary" />
            <p className="mt-3 font-display text-3xl font-semibold">{x.v}</p>
            <p className="text-xs text-muted-foreground">{x.l}</p>
          </div>
        ))}
      </div>

      <div className="grid gap-3 sm:grid-cols-3">
        {[
          {
            k: "ann" as const,
            l: "Post announcement",
            d: "Members' feeds and notifications",
            icon: Megaphone,
          },
          {
            k: "event" as const,
            l: "Create event",
            d: "Publish to the events page",
            icon: CalendarPlus,
          },
          {
            k: "edit" as const,
            l: "Edit society profile",
            d: "Name, tagline and description",
            icon: PencilLine,
          },
        ].map((q) => (
          <button
            key={q.k}
            onClick={() => setModal(q.k)}
            className="card-interactive flex items-center gap-4 rounded-xl border bg-card p-4 text-left shadow-soft"
          >
            <span className="flex size-10 items-center justify-center rounded-lg bg-primary-soft text-primary">
              <q.icon className="size-5" />
            </span>
            <span>
              <span className="block font-semibold">{q.l}</span>
              <span className="text-xs text-muted-foreground">{q.d}</span>
            </span>
          </button>
        ))}
      </div>

      <ReportedMessages societyId={s.id} />

      <CommitteeRequestsSummary societyId={s.id} />

      <CommitteeFees key={s.id} society={s} />

      <div className="grid gap-6 lg:grid-cols-2">
        <section className="rounded-xl border bg-card p-5 shadow-soft">
          <h2 className="font-semibold">Membership requests</h2>
          <div className="mt-4 space-y-3">
            {reqs.length === 0 && (
              <p className="py-6 text-center text-sm text-muted-foreground">
                Nobody is waiting to join.
              </p>
            )}
            {reqs.map((r) => (
              <div key={r.id} className="flex items-start gap-3 rounded-lg border p-3">
                <span className="flex size-9 items-center justify-center rounded-full bg-muted text-xs font-semibold">
                  {r.name
                    .split(" ")
                    .map((p) => p[0])
                    .join("")}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-semibold">
                    {r.name} <span className="font-normal text-muted-foreground">{r.course}</span>
                  </p>
                  {r.message && <p className="text-sm text-muted-foreground">“{r.message}”</p>}
                  <p className="text-[11px] text-muted-foreground">{timeAgo(r.requestedAt)}</p>
                </div>
                <div className="flex gap-1">
                  <Button
                    size="icon"
                    variant="outline"
                    aria-label={`Decline ${r.name}`}
                    onClick={async () => {
                      const o = await d.resolveRequest(r.id, "decline");
                      if (o.ok) toast(`Declined ${r.name} — they were not added as a member`);
                      else toast.error(o.error);
                    }}
                  >
                    <X />
                  </Button>
                  <Button
                    size="icon"
                    aria-label={`Approve ${r.name}`}
                    onClick={async () => {
                      const o = await d.resolveRequest(r.id, "approve");
                      if (o.ok) toast.success(`${r.name} is now a member of ${s.shortName}`);
                      else toast.error(o.error);
                    }}
                  >
                    <Check />
                  </Button>
                </div>
              </div>
            ))}
          </div>
          {resolved.length > 0 && (
            <>
              <h3 className="mt-6 text-sm font-semibold">Recently reviewed</h3>
              <ul className="mt-2 space-y-1.5">
                {resolved.slice(0, 5).map((r) => (
                  <li key={r.id} className="flex items-center justify-between gap-2 text-sm">
                    <span className="truncate">
                      {r.name} <span className="text-muted-foreground">{r.course}</span>
                    </span>
                    <span
                      className={
                        r.outcome === "approved"
                          ? "shrink-0 rounded-full bg-success/15 px-2 py-0.5 text-xs font-medium text-success"
                          : "shrink-0 rounded-full bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground"
                      }
                    >
                      {r.outcome === "approved" ? "Approved" : "Declined"}
                    </span>
                  </li>
                ))}
              </ul>
            </>
          )}
        </section>
        <section className="rounded-xl border bg-card p-5 shadow-soft">
          <h2 className="font-semibold">Upcoming events</h2>
          <div className="mt-4 space-y-2">
            {upcoming.map((e) => (
              <Link
                key={e.id}
                to="/events/$eventId"
                params={{ eventId: e.id }}
                className="flex items-center justify-between rounded-lg border p-3 hover:border-primary/30"
              >
                <span>
                  <span className="block text-sm font-semibold">{e.title}</span>
                  <span className="text-xs text-muted-foreground">
                    {formatDate(e.date)}, {e.start}, {e.venue}
                  </span>
                </span>
                <span className="text-xs text-muted-foreground">
                  {e.cancelled
                    ? "Cancelled"
                    : `${d.attendeeCount(e)}${e.capacity ? `/${e.capacity}` : ""}`}
                </span>
              </Link>
            ))}
          </div>
          {saved.length > 0 && (
            <>
              <h3 className="mt-6 text-sm font-semibold">Saved collaboration ideas</h3>
              <div className="mt-2 space-y-2">
                {saved.map((p) => (
                  <Link
                    key={p.id}
                    to="/society-pulse"
                    className="flex items-center gap-2 rounded-lg bg-primary-soft/50 p-2.5 text-sm"
                  >
                    <BookmarkCheck className="size-4 text-primary" />
                    {p.title}
                  </Link>
                ))}
              </div>
            </>
          )}
        </section>
      </div>

      <AnnouncementDialog open={modal === "ann"} onClose={() => setModal(null)} societyId={s.id} />
      <EventDialog open={modal === "event"} onClose={() => setModal(null)} societyId={s.id} />
      <EditDialog open={modal === "edit"} onClose={() => setModal(null)} societyId={s.id} />
    </div>
  );
}

function EditDialog({
  open,
  onClose,
  societyId,
}: {
  open: boolean;
  onClose: () => void;
  societyId: string;
}) {
  const { getSociety, editSociety } = useData();
  const s = getSociety(societyId)!;
  const saved = () => ({ tagline: s.tagline, description: s.description, meets: s.meets });
  const [f, setF] = useState(saved);
  // Start from the selected society's saved profile each time the dialog opens. Radix doesn't
  // call onOpenChange when the parent opens it, and the society picker can change meanwhile.
  const [wasOpen, setWasOpen] = useState(open);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (open) setF(saved());
  }
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <SocietyAvatar society={s} size="sm" />
            Edit {s.shortName}
          </DialogTitle>
        </DialogHeader>
        <form
          className="space-y-3"
          onSubmit={async (e) => {
            e.preventDefault();
            const o = await editSociety(societyId, f);
            if (!o.ok) {
              toast.error(o.error);
              return;
            }
            toast.success("Society profile updated");
            onClose();
          }}
        >
          <div className="space-y-1.5">
            <Label htmlFor="soc-tagline">Tagline</Label>
            <Input
              id="soc-tagline"
              value={f.tagline}
              onChange={(e) => setF({ ...f, tagline: e.target.value })}
              maxLength={140}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="soc-description">Description</Label>
            <Textarea
              id="soc-description"
              rows={8}
              value={f.description}
              onChange={(e) => setF({ ...f, description: e.target.value })}
              maxLength={2000}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="soc-meets">When & where you meet</Label>
            <Input
              id="soc-meets"
              value={f.meets}
              onChange={(e) => setF({ ...f, meets: e.target.value })}
              maxLength={140}
            />
          </div>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit">Save changes</Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
