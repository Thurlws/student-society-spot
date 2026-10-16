import { Loader2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { useData } from "@/lib/api/store";
import type { Announcement } from "@/lib/types";
import { Button } from "@/components/ui/button";
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

/** Posts an announcement for a society, or edits `announcement` when given. */
export function AnnouncementDialog({
  open,
  onClose,
  societyId,
  announcement,
}: {
  open: boolean;
  onClose: () => void;
  societyId: string;
  announcement?: Announcement | undefined;
}) {
  const { postAnnouncement, editAnnouncement } = useData();
  const saved = () => ({
    title: announcement?.title ?? "",
    body: announcement?.body ?? "",
    pinned: !!announcement?.pinned,
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
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{announcement ? "Edit announcement" : "New announcement"}</DialogTitle>
          <DialogDescription>
            {announcement
              ? "Changed wording is marked as edited. Nobody is notified again."
              : "Shown on the society page, members' feeds and their in-app notifications."}
          </DialogDescription>
        </DialogHeader>
        <form
          className="space-y-4"
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            const o = announcement
              ? await editAnnouncement(announcement.id, f)
              : await postAnnouncement(societyId, f);
            setBusy(false);
            if (!o.ok) {
              setErr(o.error);
              return;
            }
            toast.success(announcement ? "Announcement updated" : "Announcement published");
            setErr("");
            onClose();
          }}
        >
          <div className="space-y-1.5">
            <Label htmlFor="at">Title</Label>
            <Input
              id="at"
              value={f.title}
              onChange={(e) => setF({ ...f, title: e.target.value })}
              maxLength={100}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="ab">Message</Label>
            <Textarea
              id="ab"
              rows={5}
              value={f.body}
              onChange={(e) => setF({ ...f, body: e.target.value })}
              maxLength={1000}
            />
          </div>
          <div className="flex items-center gap-2">
            <Switch
              id="ap"
              checked={f.pinned}
              onCheckedChange={(pinned) => setF({ ...f, pinned })}
            />
            <Label htmlFor="ap">Pin to top</Label>
          </div>
          {err && <p className="text-sm text-destructive">{err}</p>}
          <DialogFooter>
            <Button type="button" variant="ghost" onClick={onClose}>
              Cancel
            </Button>
            <Button type="submit" disabled={busy}>
              {busy && <Loader2 className="animate-spin" />}
              {announcement ? "Save changes" : "Publish"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
