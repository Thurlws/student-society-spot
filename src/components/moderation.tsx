import { Flag, Loader2, MoreHorizontal, ShieldAlert, Trash2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { useData } from "@/lib/api/store";
import { timeAgo } from "@/lib/format";
import type { DiscussionMessage, MessageReport } from "@/lib/types";
import { Button, buttonVariants } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
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

/** Delete (own), remove (committee or admin) or report a discussion message. The database decides who may do which. */
export function MessageActions({
  message,
  societyId,
  societyName,
}: {
  message: DiscussionMessage;
  societyId: string;
  societyName: string;
}) {
  const { user, canManage, isAdmin, deleteMessage, reportMessage, messageReports } = useData();
  const [dialog, setDialog] = useState<null | "delete" | "report">(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const own = message.authorId === user.id;
  const moderator = canManage(societyId) || isAdmin;
  const reported = messageReports.some((r) => r.messageId === message.id && r.reportedByMe);
  return (
    <>
      {/* Not modal, so the dialogs it opens get pointer events back when they close. */}
      <DropdownMenu modal={false}>
        <DropdownMenuTrigger asChild>
          <Button
            size="icon"
            variant="ghost"
            className="size-7 text-muted-foreground"
            aria-label={`Actions for ${message.author}'s message`}
          >
            <MoreHorizontal />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {(own || moderator) && (
            <DropdownMenuItem onSelect={() => setDialog("delete")}>
              <Trash2 />
              {own ? "Delete" : "Remove message"}
            </DropdownMenuItem>
          )}
          {!own && (
            <DropdownMenuItem
              disabled={reported}
              onSelect={() => {
                setReason("");
                setDialog("report");
              }}
            >
              <Flag />
              {reported ? "Reported" : "Report to the committee"}
            </DropdownMenuItem>
          )}
        </DropdownMenuContent>
      </DropdownMenu>

      <AlertDialog open={dialog === "delete"} onOpenChange={(o) => !o && setDialog(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {own ? "Delete your message?" : `Remove ${message.author}'s message?`}
            </AlertDialogTitle>
            <AlertDialogDescription>
              It disappears for everyone in the channel. This can't be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep it</AlertDialogCancel>
            <AlertDialogAction
              className={buttonVariants({ variant: "destructive" })}
              onClick={async () => {
                const o = await deleteMessage(message.id);
                if (o.ok) toast(own ? "Message deleted" : "Message removed");
                else toast.error(o.error);
              }}
            >
              {own ? "Delete" : "Remove"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      <Dialog open={dialog === "report"} onOpenChange={(o) => !o && setDialog(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Report this message</DialogTitle>
            <DialogDescription>
              The {societyName} committee and the platform admins see your report. {message.author}{" "}
              isn't told who reported it.
            </DialogDescription>
          </DialogHeader>
          <form
            className="space-y-3"
            onSubmit={async (e) => {
              e.preventDefault();
              setBusy(true);
              const o = await reportMessage(message.id, reason);
              setBusy(false);
              if (!o.ok) {
                toast.error(o.error);
                return;
              }
              toast.success("Reported. Thanks for letting the committee know.");
              setDialog(null);
            }}
          >
            <blockquote className="rounded-lg border-l-4 bg-muted/50 px-3 py-2 text-sm text-muted-foreground">
              {message.body}
            </blockquote>
            <div className="space-y-1.5">
              <Label htmlFor="report-reason">What's wrong with it? (optional)</Label>
              <Textarea
                id="report-reason"
                rows={3}
                maxLength={300}
                value={reason}
                onChange={(e) => setReason(e.target.value)}
              />
            </div>
            <DialogFooter>
              <Button type="button" variant="ghost" onClick={() => setDialog(null)}>
                Cancel
              </Button>
              <Button type="submit" disabled={busy}>
                {busy && <Loader2 className="animate-spin" />}
                Send report
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </>
  );
}

/**
 * Open reports, one card per message: the committee dashboard passes its society, the admin
 * page shows every society's. Removing deletes the message; keeping it closes the reports.
 */
export function ReportedMessages({ societyId }: { societyId?: string }) {
  const { messageReports, getSociety, deleteMessage, dismissMessageReports, canManage, isAdmin } =
    useData();
  const [busy, setBusy] = useState<string | null>(null);
  const open = messageReports.filter(
    (r) => (societyId ? r.societyId === societyId : true) && (isAdmin || canManage(r.societyId)),
  );
  const byMessage = new Map<string, MessageReport[]>();
  for (const r of open) byMessage.set(r.messageId, [...(byMessage.get(r.messageId) ?? []), r]);
  if (!byMessage.size) return null;
  const run = async (
    messageId: string,
    p: Promise<{ ok: boolean; error?: string }>,
    done: string,
  ) => {
    setBusy(messageId);
    const o = await p;
    setBusy(null);
    if (o.ok) toast(done);
    else toast.error(o.error ?? "Something went wrong. Try again.");
  };
  return (
    <section className="rounded-xl border border-destructive/30 bg-card p-5 shadow-soft">
      <h2 className="flex items-center gap-2 font-semibold">
        <ShieldAlert className="size-4 text-destructive" />
        Reported messages
      </h2>
      <ul className="mt-4 space-y-3">
        {[...byMessage.entries()].map(([messageId, reports]) => {
          const first = reports[0]!;
          const reasons = reports.map((r) => r.reason).filter(Boolean);
          return (
            <li key={messageId} className="rounded-lg border p-3">
              <p className="text-xs text-muted-foreground">
                {[
                  !societyId && getSociety(first.societyId)?.shortName,
                  `${first.author} wrote`,
                  `reported ${reports.length === 1 ? "once" : `${reports.length} times`}`,
                  timeAgo(first.createdAt),
                ]
                  .filter(Boolean)
                  .join(", ")}
              </p>
              <blockquote className="mt-1.5 whitespace-pre-line text-sm">
                {first.excerpt}
              </blockquote>
              {reasons.length > 0 && (
                <ul className="mt-2 list-disc pl-5 text-xs text-muted-foreground">
                  {reasons.map((x, i) => (
                    <li key={i}>{x}</li>
                  ))}
                </ul>
              )}
              <div className="mt-3 flex flex-wrap gap-2">
                <AlertDialog>
                  <AlertDialogTrigger asChild>
                    <Button
                      size="sm"
                      variant="destructive"
                      disabled={busy === messageId}
                      aria-label={`Remove message from ${first.author}`}
                    >
                      <Trash2 />
                      Remove message
                    </Button>
                  </AlertDialogTrigger>
                  <AlertDialogContent>
                    <AlertDialogHeader>
                      <AlertDialogTitle>Remove {first.author}'s message?</AlertDialogTitle>
                      <AlertDialogDescription>
                        It disappears for everyone in the channel. This can't be undone.
                      </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                      <AlertDialogCancel>Cancel</AlertDialogCancel>
                      <AlertDialogAction
                        className={buttonVariants({ variant: "destructive" })}
                        onClick={() => run(messageId, deleteMessage(messageId), "Message removed")}
                      >
                        Remove
                      </AlertDialogAction>
                    </AlertDialogFooter>
                  </AlertDialogContent>
                </AlertDialog>
                <Button
                  size="sm"
                  variant="outline"
                  disabled={busy === messageId}
                  aria-label={`Keep message from ${first.author}`}
                  onClick={() =>
                    run(
                      messageId,
                      dismissMessageReports(messageId),
                      "Report closed. The message stays.",
                    )
                  }
                >
                  Keep message
                </Button>
              </div>
            </li>
          );
        })}
      </ul>
    </section>
  );
}
