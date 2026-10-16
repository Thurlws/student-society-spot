import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Loader2, Search, UserX } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import {
  findPeople,
  loadSuspended,
  reinstateUser,
  suspendUser,
  type Person,
} from "@/lib/api/admin";
import { useAuth } from "@/lib/auth";
import { formatDate, toDublin } from "@/lib/format";
import { firstIssue, suspensionReasonInput } from "@/lib/validation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
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

const day = (iso: string) => formatDate(toDublin(iso).date, { month: "short", year: "numeric" });

/** Suspends one person (migration 0025). The database decides who may suspend whom. */
export function SuspendDialog({
  person,
  onClose,
}: {
  person: { userId: string; name: string };
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    const parsed = suspensionReasonInput.safeParse(reason);
    if (!parsed.success) return void toast.error(firstIssue(parsed.error));
    setBusy(true);
    const o = await suspendUser(person.userId, parsed.data);
    setBusy(false);
    if (!o.ok) return void toast.error(o.error);
    toast.success(`${person.name} is suspended`);
    void qc.invalidateQueries({ queryKey: ["admin"] });
    onClose();
  };
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Suspend {person.name}?</DialogTitle>
          <DialogDescription>
            They keep their account but can't see or do anything in SocConnect until the suspension
            is lifted. Their memberships, seats and messages stay as they are.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={submit} className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="suspension-reason">Reason (they see this)</Label>
            <Textarea
              id="suspension-reason"
              rows={3}
              maxLength={300}
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              required
            />
          </div>
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" variant="destructive" disabled={busy}>
              {busy && <Loader2 className="animate-spin" />}
              Suspend
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function PersonRow({ person, onSuspend }: { person: Person; onSuspend: (p: Person) => void }) {
  const { session } = useAuth();
  const qc = useQueryClient();
  const [busy, setBusy] = useState(false);
  const lift = async () => {
    setBusy(true);
    const o = await reinstateUser(person.userId);
    setBusy(false);
    if (!o.ok) return void toast.error(o.error);
    toast.success(`${person.name}'s suspension is lifted`);
    void qc.invalidateQueries({ queryKey: ["admin"] });
  };
  return (
    <li className="flex flex-wrap items-start justify-between gap-2 py-2">
      <div>
        <p>{person.name}</p>
        <p className="text-xs text-muted-foreground">
          {[person.course, person.year, `joined ${day(person.joinedAt)}`]
            .filter(Boolean)
            .join(", ")}
        </p>
        {person.suspendedAt && (
          <p className="text-xs text-destructive">
            Suspended {day(person.suspendedAt)}: {person.suspensionReason}
          </p>
        )}
      </div>
      {person.suspendedAt ? (
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button variant="outline" size="sm" disabled={busy}>
              Lift suspension
            </Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>Lift {person.name}'s suspension?</AlertDialogTitle>
              <AlertDialogDescription>
                They get their societies, seats and messages back straight away.
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>Cancel</AlertDialogCancel>
              <AlertDialogAction onClick={lift}>Lift suspension</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
      ) : (
        person.userId !== session?.user.id && (
          <Button variant="outline" size="sm" onClick={() => onSuspend(person)}>
            <UserX />
            Suspend
          </Button>
        )
      )}
    </li>
  );
}

/** /admin: find someone at the university, suspend them, and see who is suspended. */
export function PeopleAdmin({ universityId }: { universityId: string }) {
  const [query, setQuery] = useState("");
  const [searched, setSearched] = useState("");
  const [suspending, setSuspending] = useState<Person | null>(null);
  const suspended = useQuery({
    queryKey: ["admin", "suspended", universityId],
    queryFn: () => loadSuspended(universityId),
  });
  const results = useQuery({
    queryKey: ["admin", "people", universityId, searched],
    queryFn: () => findPeople(universityId, searched),
    enabled: searched.length >= 2,
  });
  if (suspended.data === null) return null;

  return (
    <section className="rounded-xl border bg-card p-6 shadow-soft">
      <h2 className="font-semibold">People</h2>
      <p className="text-sm text-muted-foreground">
        Find someone by name or by their exact email address. Suspending an account stops it seeing
        or doing anything until you lift the suspension.
      </p>
      <form
        className="mt-4 flex flex-col gap-2 sm:flex-row"
        onSubmit={(e) => {
          e.preventDefault();
          setSearched(query.trim());
        }}
      >
        <Input
          aria-label="Name or email address"
          placeholder="Name or email address"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          minLength={2}
          required
        />
        <Button type="submit" variant="outline">
          <Search />
          Find
        </Button>
      </form>
      {searched.length >= 2 && (
        <div className="mt-3">
          {results.isLoading && <div className="h-10 animate-pulse rounded-lg bg-muted" />}
          {results.isError && (
            <p className="text-sm text-destructive">{(results.error as Error).message}</p>
          )}
          {results.data?.length === 0 && (
            <p className="text-sm text-muted-foreground">Nobody found.</p>
          )}
          <ul className="divide-y text-sm">
            {results.data?.map((p) => (
              <PersonRow key={p.userId} person={p} onSuspend={setSuspending} />
            ))}
          </ul>
        </div>
      )}
      <div className="mt-5 border-t pt-4">
        <h3 className="text-sm font-semibold">Suspended</h3>
        {suspended.data?.length === 0 && (
          <p className="mt-2 text-sm text-muted-foreground">Nobody is suspended.</p>
        )}
        <ul className="mt-1 divide-y text-sm">
          {suspended.data?.map((p) => (
            <PersonRow key={p.userId} person={p} onSuspend={setSuspending} />
          ))}
        </ul>
      </div>
      {suspending && <SuspendDialog person={suspending} onClose={() => setSuspending(null)} />}
    </section>
  );
}
