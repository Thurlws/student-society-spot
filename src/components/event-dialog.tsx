import { useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { useData } from "@/lib/api/store";
import { todayIso } from "@/lib/format";
import type { Event } from "@/lib/types";
import { eventCategories, type EventInput } from "@/lib/validation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

const blank = () => ({ title: "", description: "", date: todayIso(), start: "18:00", end: "20:00", venue: "", category: "Workshop", capacity: "40" });
const fromEvent = (e: Event) => ({
  title: e.title, description: e.description, date: e.date, start: e.start, end: e.end ?? "", venue: e.venue, category: e.category,
  capacity: e.capacity === undefined ? "" : String(e.capacity),
});

/** Creates an event for a society, or edits `event` when given. */
export function EventDialog({ open, onClose, societyId, event }: { open: boolean; onClose: () => void; societyId: string; event?: Event | undefined }) {
  const { createEvent, updateEvent } = useData();
  const navigate = useNavigate();
  const [f, setF] = useState(() => (event ? fromEvent(event) : blank()));
  const [err, setErr] = useState("");
  // Start from the saved values each time the dialog opens.
  const [wasOpen, setWasOpen] = useState(open);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (open) { setF(event ? fromEvent(event) : blank()); setErr(""); }
  }
  const set = (k: keyof typeof f) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => setF({ ...f, [k]: e.target.value });
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>{event ? "Edit event" : "Create event"}</DialogTitle>
          <DialogDescription>{event ? "If the time or place changes, everyone registered gets a notification." : "Published immediately to the events page."}</DialogDescription>
        </DialogHeader>
        <form className="space-y-3" onSubmit={async (e) => {
          e.preventDefault();
          const input: EventInput = {
            title: f.title, description: f.description, date: f.date, start: f.start, end: f.end || undefined, venue: f.venue,
            category: f.category as EventInput["category"],
            capacity: f.capacity.trim() === "" ? undefined : Number(f.capacity),
          };
          const o = event ? await updateEvent(event.id, input) : await createEvent(societyId, input);
          if (!o.ok) { setErr(o.error); return; }
          toast.success(event ? "Event updated" : "Event published");
          setErr(""); onClose();
          if (!event && o.id) navigate({ to: "/events/$eventId", params: { eventId: o.id } });
        }}>
          <div className="space-y-1.5"><Label htmlFor="ev-title">Title</Label><Input id="ev-title" value={f.title} onChange={set("title")} maxLength={100} /></div>
          <div className="space-y-1.5"><Label htmlFor="ev-description">Description</Label><Textarea id="ev-description" rows={3} value={f.description} onChange={set("description")} maxLength={1000} /></div>
          <div className="grid grid-cols-3 gap-2">
            <div className="space-y-1.5"><Label htmlFor="ev-date">Date</Label><Input id="ev-date" type="date" value={f.date} onChange={set("date")} /></div>
            <div className="space-y-1.5"><Label htmlFor="ev-start">Start</Label><Input id="ev-start" type="time" value={f.start} onChange={set("start")} /></div>
            <div className="space-y-1.5"><Label htmlFor="ev-end">End</Label><Input id="ev-end" type="time" value={f.end} onChange={set("end")} /></div>
          </div>
          <div className="grid grid-cols-3 gap-2">
            <div className="col-span-2 space-y-1.5"><Label htmlFor="ev-venue">Venue</Label><Input id="ev-venue" value={f.venue} onChange={set("venue")} /></div>
            <div className="space-y-1.5"><Label htmlFor="ev-capacity">Capacity</Label><Input id="ev-capacity" type="number" min={1} step={1} value={f.capacity} onChange={set("capacity")} placeholder="No limit" /></div>
          </div>
          <div className="space-y-1.5">
            <Label>Category</Label>
            <Select value={f.category} onValueChange={(v) => setF({ ...f, category: v })}>
              <SelectTrigger aria-label="Category"><SelectValue /></SelectTrigger>
              <SelectContent>{eventCategories.map((c) => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          {err && <p className="text-sm text-destructive">{err}</p>}
          <DialogFooter><Button type="button" variant="ghost" onClick={onClose}>{event ? "Keep as is" : "Cancel"}</Button><Button type="submit">{event ? "Save changes" : "Publish event"}</Button></DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
