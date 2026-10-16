import { useInfiniteQuery } from "@tanstack/react-query";
import { History, Loader2 } from "lucide-react";
import { ACTIVITY_PAGE, loadActivity } from "@/lib/api/admin";
import { auditActor, describeAuditEntry } from "@/lib/audit";
import { formatDate, toDublin } from "@/lib/format";
import { Button } from "@/components/ui/button";

const when = (iso: string) => {
  const d = toDublin(iso);
  return `${formatDate(d.date, { day: "numeric", month: "short", year: "numeric" })}, ${d.time}`;
};

/** /admin: who changed what (migration 0024). Platform admins also see platform-level entries. */
export function ActivityLog({ universityId }: { universityId: string }) {
  const q = useInfiniteQuery({
    queryKey: ["admin", "activity", universityId],
    queryFn: ({ pageParam }) => loadActivity(universityId, pageParam),
    initialPageParam: undefined as number | undefined,
    getNextPageParam: (last) =>
      last && last.entries.length === ACTIVITY_PAGE ? last.entries.at(-1)!.id : undefined,
  });
  const pages = q.data?.pages ?? [];
  if (pages[0] === null) return null;
  const rows = pages.flatMap((p) =>
    (p?.entries ?? []).map((e) => ({ e, names: p!.names, key: e.id })),
  );

  return (
    <section className="rounded-xl border bg-card p-6 shadow-soft">
      <h2 className="flex items-center gap-2 font-semibold">
        <History className="size-4" />
        Activity
      </h2>
      <p className="text-sm text-muted-foreground">
        Admin rights, committee seats, invites, society changes and moderation. Entries can't be
        changed or deleted.
      </p>
      {q.isLoading && <div className="mt-4 h-20 animate-pulse rounded-lg bg-muted" />}
      {q.isError && <p className="mt-4 text-sm text-destructive">Couldn't load the activity.</p>}
      {!q.isLoading && !q.isError && rows.length === 0 && (
        <p className="mt-4 text-sm text-muted-foreground">Nothing recorded yet.</p>
      )}
      <ul className="mt-4 divide-y text-sm">
        {rows.map(({ e, names, key }) => (
          <li key={key} className="py-2">
            <p>{describeAuditEntry(e, names)}</p>
            <p className="text-xs text-muted-foreground">
              {auditActor(e, names)}, {when(e.at)}
            </p>
          </li>
        ))}
      </ul>
      {q.hasNextPage && (
        <Button
          variant="outline"
          size="sm"
          className="mt-3"
          disabled={q.isFetchingNextPage}
          onClick={() => void q.fetchNextPage()}
        >
          {q.isFetchingNextPage && <Loader2 className="animate-spin" />}
          Show older
        </Button>
      )}
    </section>
  );
}
