import { Loader2, Trash2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { useData } from "@/lib/api/store";
import type { DiscussionChannel } from "@/lib/types";
import { channelName } from "@/lib/validation";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogDescription,
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

/** Adds a channel to a society, or changes and deletes `channel` when given. Committee only. */
export function ChannelDialog({
  open,
  onClose,
  societyId,
  channel,
  onDeleted,
}: {
  open: boolean;
  onClose: () => void;
  societyId: string;
  channel?: DiscussionChannel | undefined;
  onDeleted?: () => void;
}) {
  const { createChannel, updateChannel } = useData();
  const saved = () => ({
    name: channel?.name ?? "",
    description: channel?.description ?? "",
    committeeOnly: !!channel?.committeeOnly,
  });
  const [f, setF] = useState(saved);
  const [err, setErr] = useState("");
  const [busy, setBusy] = useState(false);
  // Start from the saved values each time the dialog opens.
  const [wasOpen, setWasOpen] = useState(open);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (open) {
      setF(saved());
      setErr("");
    }
  }
  const shown = channelName(f.name);
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{channel ? `Edit #${channel.name}` : "New channel"}</DialogTitle>
          <DialogDescription>Only members of the society can read its channels.</DialogDescription>
        </DialogHeader>
        <form
          className="space-y-4"
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            const o = channel
              ? await updateChannel(channel.id, f)
              : await createChannel(societyId, f);
            setBusy(false);
            if (!o.ok) {
              setErr(o.error);
              return;
            }
            toast.success(channel ? "Channel updated" : `#${shown} added`);
            onClose();
          }}
        >
          <div className="space-y-1.5">
            <Label htmlFor="cn">Name</Label>
            <Input
              id="cn"
              value={f.name}
              onChange={(e) => setF({ ...f, name: e.target.value })}
              maxLength={40}
              placeholder="lifts-and-kit"
            />
            {f.name && shown !== f.name && (
              <p className="text-xs text-muted-foreground">Shown as #{shown || "…"}</p>
            )}
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="cd">Description</Label>
            <Textarea
              id="cd"
              rows={2}
              value={f.description}
              onChange={(e) => setF({ ...f, description: e.target.value })}
              maxLength={200}
              placeholder="What this channel is for"
            />
          </div>
          <div className="flex items-start gap-2">
            <Switch
              id="co"
              checked={f.committeeOnly}
              onCheckedChange={(committeeOnly) => setF({ ...f, committeeOnly })}
            />
            <Label htmlFor="co" className="leading-snug">
              Only the committee posts
              <span className="block text-xs font-normal text-muted-foreground">
                Members can still read it. Good for notices.
              </span>
            </Label>
          </div>
          {err && <p className="text-sm text-destructive">{err}</p>}
          <DialogFooter className="gap-2 sm:justify-between">
            {channel && channel.slug !== "general" ? (
              <DeleteChannelButton
                channel={channel}
                onDeleted={() => {
                  onClose();
                  onDeleted?.();
                }}
              />
            ) : (
              <span />
            )}
            <div className="flex gap-2">
              <Button type="button" variant="ghost" onClick={onClose}>
                Cancel
              </Button>
              <Button type="submit" disabled={busy}>
                {busy && <Loader2 className="animate-spin" />}
                {channel ? "Save changes" : "Add channel"}
              </Button>
            </div>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function DeleteChannelButton({
  channel,
  onDeleted,
}: {
  channel: DiscussionChannel;
  onDeleted: () => void;
}) {
  const { deleteChannel } = useData();
  return (
    <AlertDialog>
      <AlertDialogTrigger asChild>
        <Button type="button" variant="ghost" className="text-destructive">
          <Trash2 />
          Delete
        </Button>
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>Delete #{channel.name}?</AlertDialogTitle>
          <AlertDialogDescription>
            Every message in it is deleted too, and the people who wrote them are told. It can't be
            undone.
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Keep it</AlertDialogCancel>
          <AlertDialogAction
            className={buttonVariants({ variant: "destructive" })}
            onClick={async () => {
              const o = await deleteChannel(channel.id);
              if (!o.ok) return void toast.error(o.error);
              toast(`#${channel.name} deleted`);
              onDeleted();
            }}
          >
            Delete channel
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
