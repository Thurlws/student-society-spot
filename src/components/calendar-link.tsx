import { CalendarPlus, Copy, Loader2, Unlink } from "lucide-react";
import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  calendarFeedStatus,
  calendarFeedUrl,
  createCalendarFeed,
  deleteCalendarFeed,
  googleSubscribeUrl,
} from "@/lib/api/calendar-feed";
import { formatDate, toDublin } from "@/lib/format";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

/** Settings: a personal link that puts your registered events in your own calendar app. */
export function CalendarLink() {
  const qc = useQueryClient();
  const status = useQuery({ queryKey: ["calendar-feed"], queryFn: calendarFeedStatus });
  // Shown once, right after it's made; the database keeps only a hash.
  const [token, setToken] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const run = async (fn: () => Promise<void>) => {
    setBusy(true);
    try {
      await fn();
      await qc.invalidateQueries({ queryKey: ["calendar-feed"] });
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Something went wrong. Try again.");
    } finally {
      setBusy(false);
    }
  };
  const make = () =>
    run(async () => {
      setToken(await createCalendarFeed());
    });

  if (status.isPending) return <p className="text-sm text-muted-foreground">Loading…</p>;
  if (status.data === "missing")
    return <p className="text-sm text-muted-foreground">Calendar links aren't switched on yet.</p>;

  const url = token ? calendarFeedUrl(window.location.origin, token) : null;
  return (
    <div className="space-y-4 text-sm">
      {url ? (
        <>
          <div className="flex gap-2">
            <Input
              readOnly
              value={url}
              aria-label="Your calendar link"
              onFocus={(e) => e.target.select()}
            />
            <Button
              variant="outline"
              onClick={async () => {
                await navigator.clipboard.writeText(url);
                toast.success("Link copied");
              }}
            >
              <Copy />
              Copy
            </Button>
          </div>
          <p className="text-muted-foreground">
            Copy it now: it's only shown once. Then add it to your calendar app.
          </p>
          <div className="flex flex-wrap gap-2">
            <a
              className={buttonVariants()}
              href={googleSubscribeUrl(url)}
              target="_blank"
              rel="noreferrer"
            >
              <CalendarPlus />
              Add to Google Calendar
            </a>
            <a
              className={buttonVariants({ variant: "outline" })}
              href={url.replace(/^https?:/, "webcal:")}
            >
              Apple Calendar or Outlook
            </a>
          </div>
        </>
      ) : status.data ? (
        <>
          <p>
            Your calendar link is on. You made it on {formatDate(toDublin(status.data).date)}. It's
            only shown when it's made, so if you've lost it, make a new one.
          </p>
          <div className="flex flex-wrap gap-2">
            <Button disabled={busy} onClick={make}>
              {busy && <Loader2 className="animate-spin" />}
              Make a new link
            </Button>
            <Button
              variant="outline"
              disabled={busy}
              onClick={() =>
                run(async () => {
                  await deleteCalendarFeed();
                  toast("Calendar link turned off");
                })
              }
            >
              <Unlink />
              Turn it off
            </Button>
          </div>
        </>
      ) : (
        <Button disabled={busy} onClick={make}>
          {busy ? <Loader2 className="animate-spin" /> : <CalendarPlus />}
          Make my calendar link
        </Button>
      )}
      <p className="text-xs text-muted-foreground">
        It lists the events you've registered for, and calendar apps pick up changes and
        cancellations. Google Calendar checks every few hours, so changes can take a while to
        appear. Anyone with the link can see which events you've registered for, so don't share it.
        Making a new link turns the old one off.
      </p>
    </div>
  );
}
