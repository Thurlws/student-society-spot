import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Loader2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { needsName, useAuth } from "@/lib/auth";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import tudCourses from "@/data/tud-courses.json";

// Course lists by university slug; students elsewhere type their course.
const catalogues: Record<string, typeof tudCourses> = { tudublin: tudCourses };
const years = ["Year 1", "Year 2", "Year 3", "Year 4", "Year 5", "Postgraduate", "Staff"];

/** Display name, course and year — saved to the signed-in person's own profile. */
export function ProfileForm({
  submitLabel = "Save profile",
  onSaved,
  finishOnboarding,
}: {
  submitLabel?: string;
  onSaved?: () => void;
  finishOnboarding?: boolean;
}) {
  const { profile, session, refresh, access, email } = useAuth();
  const courses = catalogues[access.university?.slug ?? ""];
  const [name, setName] = useState("");
  const [course, setCourse] = useState("");
  const [year, setYear] = useState("");
  const [busy, setBusy] = useState(false);
  const [filled, setFilled] = useState(false);

  // Fill in the saved details once. The profile refreshes when interests change on the same
  // page, and refilling then would wipe whatever the person had typed meanwhile.
  useEffect(() => {
    if (!profile || filled) return;
    // A name that is only the start of the email address isn't one; ask for a real one.
    setName(needsName(profile.display_name, email) ? "" : profile.display_name);
    setCourse(profile.course);
    setYear(profile.year);
    setFilled(true);
  }, [profile, filled, email]);

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!session) return;
    if (needsName(name, email))
      return void toast.error(
        "Tell us what people should call you: your name, not your student number or email.",
      );
    setBusy(true);
    const { error } = await supabase
      .from("profiles")
      .update({
        display_name: name.trim().slice(0, 80),
        course: course.trim().slice(0, 120),
        year: year.trim().slice(0, 40),
        ...(finishOnboarding ? { onboarded_at: new Date().toISOString() } : {}),
      })
      .eq("id", session.user.id);
    setBusy(false);
    // The database's own refusals (P0001) say what to change; anything else is ours.
    if (error)
      return void toast.error(
        error.code === "P0001" ? error.message : "Couldn't save your profile. Try again.",
      );
    await refresh();
    toast.success("Profile saved");
    onSaved?.();
  };

  return (
    <form onSubmit={save} className="grid gap-4 sm:grid-cols-3">
      <div className="space-y-1.5 sm:col-span-3">
        <Label htmlFor="pf-name">What should people call you?</Label>
        <Input
          id="pf-name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="e.g. Aoife Byrne"
          aria-describedby="pf-name-hint"
          autoComplete="name"
          maxLength={80}
          required
        />
        <p id="pf-name-hint" className="text-xs text-muted-foreground">
          Your name, or the name people know you by. Members of your societies see it next to your
          messages.
        </p>
      </div>
      <div className="space-y-1.5 sm:col-span-2">
        <Label htmlFor="pf-course">Course</Label>
        <Input
          id="pf-course"
          list={courses ? "courses" : undefined}
          placeholder={courses ? "Search course code or name" : undefined}
          value={course}
          onChange={(e) => setCourse(e.target.value)}
          maxLength={120}
          autoComplete="off"
        />
        {courses && (
          <datalist id="courses">
            {courses.map((c) => (
              <option key={c.code} value={`${c.code} — ${c.name}`} />
            ))}
          </datalist>
        )}
      </div>
      <div className="space-y-1.5">
        <Label htmlFor="pf-year">Year</Label>
        <select
          id="pf-year"
          value={year}
          onChange={(e) => setYear(e.target.value)}
          className="h-9 w-full rounded-md border border-input bg-background px-3 text-sm shadow-xs focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <option value="">Select year</option>
          {year && !years.includes(year) && <option value={year}>{year}</option>}
          {years.map((y) => (
            <option key={y} value={y}>
              {y}
            </option>
          ))}
        </select>
      </div>
      <div className="sm:col-span-3">
        <Button type="submit" disabled={busy}>
          {busy && <Loader2 className="animate-spin" />}
          {submitLabel}
        </Button>
      </div>
    </form>
  );
}
