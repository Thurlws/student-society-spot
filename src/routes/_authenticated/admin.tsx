import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { toast } from "sonner";
import {
  Archive,
  ArchiveRestore,
  ChevronDown,
  FileUp,
  Loader2,
  Pencil,
  Plus,
  Search,
  ShieldCheck,
  Trash2,
  UserPlus,
  Users,
} from "lucide-react";
import { useServerFn } from "@tanstack/react-start";
import { supabase } from "@/integrations/supabase/client";
import { setMicrosoftSignIn } from "@/lib/system.functions";
import { useAuth, type University } from "@/lib/auth";
import { useData } from "@/lib/api/store";
import { committeePositions } from "@/lib/validation";
import type { Society } from "@/lib/types";
import { cn } from "@/lib/utils";
import { pageHead } from "@/lib/seo";
import { PageHeader, EmptyState } from "@/components/cards";
import { ReportedMessages } from "@/components/moderation";
import { ActivityLog } from "@/components/activity-log";
import { PeopleAdmin } from "@/components/people-admin";
import { SystemPanel } from "@/components/system-status";
import { SocietyImportDialog } from "@/components/society-import-dialog";
import { SocietyAvatar } from "@/components/society-avatar";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button, buttonVariants } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
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

const TABS = ["societies", "reports", "people", "activity", "university", "system"] as const;
type Tab = (typeof TABS)[number];

export const Route = createFileRoute("/_authenticated/admin")({
  validateSearch: (s: Record<string, unknown>): { tab?: Tab } =>
    TABS.includes(s["tab"] as Tab) ? { tab: s["tab"] as Tab } : {},
  head: () => pageHead("Admin", "Create and manage societies and their committees."),
  component: AdminPage,
});

const ACCENTS = ["indigo", "teal", "coral", "amber", "rose", "sky", "emerald", "plum"] as const;
type Accent = (typeof ACCENTS)[number];

type SocietyRow = {
  id: string;
  slug: string;
  name: string;
  short_name: string;
  category: string;
  tagline: string;
  description: string;
  accent: string;
  requires_approval: boolean;
  meets: string;
  status: string;
  icon: string;
  logo_url: string | null;
};
type RoleRow = {
  id: string;
  society_id: string;
  position: string;
  user_id: string;
  profiles: { display_name: string } | null;
};
type InviteRow = {
  id: string;
  email: string;
  society_id: string | null;
  university_id: string | null;
  position: string;
};
type AdminRow = { user_id: string; profiles: { display_name: string } | null };

const slugify = (v: string) =>
  v
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "")
    .slice(0, 40);

function useAdminData(universityId: string) {
  return useQuery({
    queryKey: ["admin", universityId],
    enabled: !!universityId,
    queryFn: async () => {
      const [s, r, i, d, a] = await Promise.all([
        supabase
          .from("societies")
          .select(
            "id, slug, name, short_name, category, tagline, description, accent, requires_approval, meets, status, icon, logo_url",
          )
          .eq("university_id", universityId)
          .order("name"),
        supabase
          .from("society_roles")
          .select("id, society_id, position, user_id, profiles(display_name)"),
        supabase
          .from("role_invites")
          .select("id, email, society_id, university_id, position")
          .is("claimed_at", null),
        // "*" so the Microsoft tenant comes along once 0040 is in, and nothing breaks before.
        supabase
          .from("university_domains")
          .select("*")
          .eq("university_id", universityId)
          .order("domain"),
        supabase
          .from("university_admins")
          .select("user_id, profiles(display_name)")
          .eq("university_id", universityId),
      ]);
      if (s.error) throw s.error;
      return {
        societies: (s.data ?? []) as SocietyRow[],
        roles: (r.data ?? []) as unknown as RoleRow[],
        invites: (i.data ?? []) as InviteRow[],
        domains: (d.data ?? []).map((x) => x.domain),
        // Domain → whether Microsoft sign-in is on; empty until migration 0040.
        microsoft: Object.fromEntries(
          (d.data ?? [])
            .filter((x) => "microsoft_tenant_id" in x)
            .map((x) => [x.domain, x.microsoft_tenant_id !== null]),
        ) as Record<string, boolean>,
        admins: (a.data ?? []) as unknown as AdminRow[],
      };
    },
  });
}

function AdminPage() {
  const { access } = useAuth();
  const { messageReports, canManage } = useData();
  const navigate = useNavigate();
  const search = Route.useSearch();
  // Platform admins pick a university; university admins manage their own.
  const { data: universities } = useQuery({
    queryKey: ["admin", "universities"],
    enabled: access.is_admin,
    queryFn: async () =>
      (await supabase.from("universities").select("id, slug, name, short_name").order("name"))
        .data ?? [],
  });
  const [picked, setPicked] = useState<string>();
  const universityId = picked ?? access.university?.id ?? universities?.[0]?.id ?? "";
  const university = universities?.find((u) => u.id === universityId) ?? access.university;
  const { data, isLoading } = useAdminData(universityId);
  const [editing, setEditing] = useState<SocietyRow | "new" | null>(null);
  const [importing, setImporting] = useState(false);
  const qc = useQueryClient();

  if (!access.is_admin && !access.university_admin)
    return (
      <EmptyState
        icon={ShieldCheck}
        title="Admins only"
        body="This page is for platform and university admins."
      />
    );

  // The University and System tabs are for platform admins; anyone else lands on Societies.
  const tab: Tab =
    (search.tab === "university" || search.tab === "system") && !access.is_admin
      ? "societies"
      : (search.tab ?? "societies");
  const openReports = new Set(
    messageReports
      .filter((r) => !r.dismissed && (access.is_admin || canManage(r.societyId)))
      .map((r) => r.messageId),
  ).size;

  const setStatus = async (s: SocietyRow, status: "active" | "archived") => {
    const { error } = await supabase.from("societies").update({ status }).eq("id", s.id);
    if (error) return void toast.error(error.message);
    toast.success(status === "archived" ? `${s.short_name} archived` : `${s.short_name} restored`);
    void qc.invalidateQueries({ queryKey: ["admin"] });
  };

  return (
    <div>
      <PageHeader
        title="Admin"
        subtitle={`Run ${university?.short_name ?? "your university"}'s societies and committees, and look after its members.`}
        actions={
          access.is_admin &&
          universities && (
            <Select value={universityId} onValueChange={setPicked}>
              <SelectTrigger className="w-56 bg-card" aria-label="University">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {universities.map((u) => (
                  <SelectItem key={u.id} value={u.id}>
                    {u.short_name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          )
        }
      />
      <Tabs
        value={tab}
        onValueChange={(t) =>
          navigate({
            to: "/admin",
            search: t === "societies" ? {} : { tab: t as Tab },
            replace: true,
          })
        }
      >
        <TabsList className="h-auto flex-wrap justify-start gap-1 bg-transparent p-0">
          <AdminTab value="societies" label="Societies" count={data?.societies.length} />
          <AdminTab value="reports" label="Reports" count={openReports || undefined} alert />
          <AdminTab value="people" label="People" />
          <AdminTab value="activity" label="Activity" />
          {access.is_admin && <AdminTab value="university" label="University" />}
          {access.is_admin && <AdminTab value="system" label="System" />}
        </TabsList>

        <TabsContent value="societies" className="mt-6">
          <SocietiesPanel
            data={data}
            loading={isLoading}
            universityId={universityId}
            onNew={() => setEditing("new")}
            onImport={() => setImporting(true)}
            onEdit={setEditing}
            onStatus={setStatus}
          />
        </TabsContent>
        <TabsContent value="reports" className="mt-6">
          {openReports ? (
            <ReportedMessages />
          ) : (
            <EmptyState
              icon={ShieldCheck}
              title="No open reports"
              body="When a member reports a message, it shows up here and on the society's committee dashboard."
            />
          )}
        </TabsContent>
        <TabsContent value="people" className="mt-6">
          {universityId && <PeopleAdmin universityId={universityId} />}
        </TabsContent>
        <TabsContent value="activity" className="mt-6">
          {universityId && <ActivityLog universityId={universityId} />}
        </TabsContent>
        {access.is_admin && (
          <TabsContent value="university" className="mt-6">
            {university && data && (
              <Universities
                university={university}
                domains={data.domains}
                microsoft={data.microsoft}
                admins={data.admins}
                invites={data.invites.filter((i) => i.university_id === university.id)}
                onCreated={setPicked}
              />
            )}
          </TabsContent>
        )}
        {access.is_admin && (
          <TabsContent value="system" className="mt-6">
            <SystemPanel />
          </TabsContent>
        )}
      </Tabs>
      {importing && (
        <SocietyImportDialog
          universityId={universityId}
          universityName={university?.short_name ?? "the university's"}
          onClose={() => setImporting(false)}
        />
      )}
      {editing && (
        <SocietyDialog
          society={editing === "new" ? null : editing}
          universityId={universityId}
          onClose={() => setEditing(null)}
        />
      )}
    </div>
  );
}

function AdminTab({
  value,
  label,
  count,
  alert,
}: {
  value: Tab;
  label: string;
  count?: number | undefined;
  alert?: boolean;
}) {
  return (
    <TabsTrigger
      value={value}
      className="gap-1.5 rounded-full data-[state=active]:bg-primary-soft data-[state=active]:text-primary data-[state=active]:shadow-none"
    >
      {label}
      {count !== undefined && (
        <span
          className={cn(
            "rounded-full px-1.5 text-[11px] tabular-nums",
            alert ? "bg-destructive text-destructive-foreground" : "bg-muted text-muted-foreground",
          )}
        >
          {count}
        </span>
      )}
    </TabsTrigger>
  );
}

type AdminData = NonNullable<ReturnType<typeof useAdminData>["data"]>;

/** The university's societies as a searchable list; each row opens its committee. */
function SocietiesPanel({
  data,
  loading,
  universityId,
  onNew,
  onImport,
  onEdit,
  onStatus,
}: {
  data: AdminData | undefined;
  loading: boolean;
  universityId: string;
  onNew: () => void;
  onImport: () => void;
  onEdit: (s: SocietyRow) => void;
  onStatus: (s: SocietyRow, status: "active" | "archived") => void;
}) {
  const [query, setQuery] = useState("");
  const [show, setShow] = useState<"active" | "archived" | "all">("active");
  const [open, setOpen] = useState<string | null>(null);
  const societies = data?.societies ?? [];
  const counts = {
    active: societies.filter((s) => s.status === "active").length,
    archived: societies.filter((s) => s.status === "archived").length,
  };
  const q = query.trim().toLowerCase();
  const list = societies.filter(
    (s) =>
      (show === "all" || s.status === show) &&
      (!q || `${s.name} ${s.short_name} ${s.category}`.toLowerCase().includes(q)),
  );

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
        <div className="relative flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            aria-label="Search societies"
            placeholder="Search by name or category"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            className="bg-card pl-9"
          />
        </div>
        <Select value={show} onValueChange={(v) => setShow(v as typeof show)}>
          <SelectTrigger className="bg-card sm:w-44" aria-label="Show">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="active">Active ({counts.active})</SelectItem>
            <SelectItem value="archived">Archived ({counts.archived})</SelectItem>
            <SelectItem value="all">All ({societies.length})</SelectItem>
          </SelectContent>
        </Select>
        <div className="flex gap-2">
          <Button variant="outline" onClick={onImport} disabled={!universityId}>
            <FileUp />
            Import societies
          </Button>
          <Button onClick={onNew} disabled={!universityId}>
            <Plus />
            New society
          </Button>
        </div>
      </div>

      {loading && <div className="h-32 animate-pulse rounded-xl bg-muted" />}
      {data && societies.length === 0 && (
        <EmptyState
          title="No societies yet"
          body="Create the first society, or import a list from the Students' Union."
        />
      )}
      {data && societies.length > 0 && list.length === 0 && (
        <p className="py-8 text-center text-sm text-muted-foreground">
          No societies match. Try another search, or show archived societies too.
        </p>
      )}
      {list.length > 0 && (
        <ul className="divide-y overflow-hidden rounded-xl border bg-card shadow-soft">
          {list.map((s) => {
            const roles = data!.roles.filter((r) => r.society_id === s.id);
            const invites = data!.invites.filter((i) => i.society_id === s.id);
            const expanded = open === s.id;
            const committee = [
              roles.length ? `${roles.length} on the committee` : "No committee yet",
              invites.length ? `${invites.length} invited` : "",
            ]
              .filter(Boolean)
              .join(", ");
            return (
              <li key={s.id}>
                <section aria-labelledby={`soc-${s.id}`}>
                  <div className="flex flex-wrap items-center gap-3 px-4 py-3">
                    <SocietyAvatar
                      size="sm"
                      society={{
                        name: s.name,
                        icon: s.icon,
                        accent: s.accent as Society["accent"],
                        logoUrl: s.logo_url ?? undefined,
                      }}
                    />
                    <div className="min-w-0 flex-1">
                      <h3
                        id={`soc-${s.id}`}
                        className="flex items-center gap-2 text-sm font-semibold"
                      >
                        <span className="truncate">{s.name}</span>
                        {s.status === "archived" && <Badge variant="outline">Archived</Badge>}
                      </h3>
                      <p className="truncate text-xs text-muted-foreground">
                        {s.category}, {committee}
                      </p>
                    </div>
                    <div className="flex flex-wrap gap-1">
                      <Button
                        variant="ghost"
                        size="sm"
                        aria-expanded={expanded}
                        onClick={() => setOpen(expanded ? null : s.id)}
                      >
                        <Users />
                        Committee
                        <ChevronDown
                          className={cn("transition-transform", expanded && "rotate-180")}
                        />
                      </Button>
                      <Button variant="ghost" size="sm" onClick={() => onEdit(s)}>
                        <Pencil />
                        Edit
                      </Button>
                      {s.status === "active" ? (
                        <Button variant="ghost" size="sm" onClick={() => onStatus(s, "archived")}>
                          <Archive />
                          Archive
                        </Button>
                      ) : (
                        <Button variant="ghost" size="sm" onClick={() => onStatus(s, "active")}>
                          <ArchiveRestore />
                          Restore
                        </Button>
                      )}
                    </div>
                  </div>
                  {expanded && (
                    <div className="border-t bg-surface px-4 py-4">
                      <Committee
                        society={s}
                        domain={data!.domains[0]}
                        roles={roles}
                        invites={invites}
                      />
                    </div>
                  )}
                </section>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

function Committee({
  society,
  domain,
  roles,
  invites,
}: {
  society: SocietyRow;
  domain: string | undefined;
  roles: RoleRow[];
  invites: InviteRow[];
}) {
  const { session } = useAuth();
  const qc = useQueryClient();
  const [email, setEmail] = useState("");
  const [position, setPosition] = useState<string>("Committee member");
  const [busy, setBusy] = useState(false);
  const refresh = () => qc.invalidateQueries({ queryKey: ["admin"] });

  const invite = async (e: React.FormEvent) => {
    e.preventDefault();
    const addr = email.trim().toLowerCase();
    setBusy(true);
    const { error } = await supabase.from("role_invites").insert({
      email: addr,
      society_id: society.id,
      role: "committee",
      position,
      invited_by: session?.user.id ?? null,
    });
    setBusy(false);
    if (error)
      return void toast.error(
        error.code === "23505" ? "That person is already invited." : error.message,
      );
    toast.success(`${addr} added to ${society.short_name}'s committee`);
    setEmail("");
    setPosition("Committee member");
    void refresh();
  };

  const remove = async (table: "society_roles" | "role_invites", id: string) => {
    const { error } = await supabase.from(table).delete().eq("id", id);
    if (error) return void toast.error(error.message);
    void refresh();
  };

  return (
    <div>
      <h4 className="text-sm font-semibold">Committee</h4>
      <ul className="mt-2 space-y-1 text-sm">
        {roles.map((r) => (
          <li key={r.id} className="flex items-center justify-between gap-2">
            <span>
              {r.profiles?.display_name || "Member"},{" "}
              <span className="text-muted-foreground">{r.position}</span>
            </span>
            <Button
              variant="ghost"
              size="sm"
              aria-label="Remove"
              onClick={() => remove("society_roles", r.id)}
            >
              <Trash2 />
            </Button>
          </li>
        ))}
        {invites.map((i) => (
          <li key={i.id} className="flex items-center justify-between gap-2 text-muted-foreground">
            <span>
              {i.email}, {i.position}, waiting for first sign-in
            </span>
            <Button
              variant="ghost"
              size="sm"
              aria-label="Cancel invite"
              onClick={() => remove("role_invites", i.id)}
            >
              <Trash2 />
            </Button>
          </li>
        ))}
        {roles.length + invites.length === 0 && (
          <li className="text-muted-foreground">No committee yet.</li>
        )}
      </ul>
      <form onSubmit={invite} className="mt-3 flex flex-col gap-2 sm:flex-row">
        <Input
          type="email"
          aria-label="Committee member email"
          placeholder={`name@${domain ?? "university.ie"}`}
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
        />
        <Select value={position} onValueChange={setPosition}>
          <SelectTrigger aria-label="Position" className="sm:w-56">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {committeePositions.map((p) => (
              <SelectItem key={p} value={p}>
                {p}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Button type="submit" variant="outline" disabled={busy}>
          {busy ? <Loader2 className="animate-spin" /> : <UserPlus />}Add
        </Button>
      </form>
    </div>
  );
}

const domainError = (e: { code: string; message: string }) =>
  e.code === "23505"
    ? "That domain already belongs to a university."
    : e.code === "23514"
      ? "Enter a domain like university.ie."
      : e.message;

/** Platform admins only: the managed university's sign-in domains and admins, and new universities. */
function Universities({
  university,
  domains,
  microsoft,
  admins,
  invites,
  onCreated,
}: {
  university: University;
  domains: string[];
  microsoft: Record<string, boolean>;
  admins: AdminRow[];
  invites: InviteRow[];
  onCreated: (id: string) => void;
}) {
  const { session } = useAuth();
  const qc = useQueryClient();
  const [domain, setDomain] = useState("");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [adding, setAdding] = useState(false);
  const refresh = () => qc.invalidateQueries({ queryKey: ["admin"] });
  const setMicrosoft = useServerFn(setMicrosoftSignIn);

  const addDomain = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    const { error } = await supabase.from("university_domains").insert({
      domain: domain.trim().toLowerCase().replace(/^@/, ""),
      university_id: university.id,
    });
    setBusy(false);
    if (error) return void toast.error(domainError(error));
    setDomain("");
    void refresh();
  };

  const toggleMicrosoft = async (d: string, on: boolean) => {
    setBusy(true);
    try {
      await setMicrosoft({ data: { domain: d, on } });
      toast.success(`Microsoft sign-in is ${on ? "on" : "off"} for @${d}`);
      void refresh();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "Couldn't change Microsoft sign-in.");
    } finally {
      setBusy(false);
    }
  };

  const removeDomain = async (d: string) => {
    const { error } = await supabase.from("university_domains").delete().eq("domain", d);
    if (error) return void toast.error(error.message);
    void refresh();
  };

  const invite = async (e: React.FormEvent) => {
    e.preventDefault();
    const addr = email.trim().toLowerCase();
    setBusy(true);
    const { error } = await supabase.from("role_invites").insert({
      email: addr,
      role: "university_admin",
      university_id: university.id,
      invited_by: session?.user.id ?? null,
    });
    setBusy(false);
    if (error)
      return void toast.error(
        error.code === "23505" ? "That person is already invited." : error.message,
      );
    toast.success(`${addr} added as a ${university.short_name} admin`);
    setEmail("");
    void refresh();
  };

  const removeAdmin = async (userId: string) => {
    const { error } = await supabase
      .from("university_admins")
      .delete()
      .eq("university_id", university.id)
      .eq("user_id", userId);
    if (error) return void toast.error(error.message);
    void refresh();
  };

  const cancelInvite = async (id: string) => {
    const { error } = await supabase.from("role_invites").delete().eq("id", id);
    if (error) return void toast.error(error.message);
    void refresh();
  };

  return (
    <section className="rounded-xl border bg-card p-6 shadow-soft">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-semibold">Universities</h2>
          <p className="text-sm text-muted-foreground">{university.name}</p>
        </div>
        <Button variant="outline" size="sm" onClick={() => setAdding(true)}>
          <Plus />
          New university
        </Button>
      </div>
      <div className="mt-5 border-t pt-4">
        <h3 className="text-sm font-semibold">Email domains</h3>
        <ul className="mt-2 space-y-1 text-sm">
          {domains.map((d) => (
            <li key={d} className="flex items-center justify-between gap-2">
              <span className="mr-auto">@{d}</span>
              {d in microsoft && (
                <Label className="flex items-center gap-2 text-xs font-normal text-muted-foreground">
                  Microsoft sign-in
                  <Switch
                    checked={microsoft[d]}
                    disabled={busy}
                    onCheckedChange={(on) => toggleMicrosoft(d, on)}
                  />
                </Label>
              )}
              <AlertDialog>
                <AlertDialogTrigger asChild>
                  <Button variant="ghost" size="sm" aria-label={`Remove @${d}`}>
                    <Trash2 />
                  </Button>
                </AlertDialogTrigger>
                <AlertDialogContent>
                  <AlertDialogHeader>
                    <AlertDialogTitle>Remove @{d}?</AlertDialogTitle>
                    <AlertDialogDescription>
                      People with @{d} addresses won't be able to sign up or get a sign-in link.
                    </AlertDialogDescription>
                  </AlertDialogHeader>
                  <AlertDialogFooter>
                    <AlertDialogCancel>Cancel</AlertDialogCancel>
                    <AlertDialogAction
                      className={buttonVariants({ variant: "destructive" })}
                      onClick={() => removeDomain(d)}
                    >
                      Remove
                    </AlertDialogAction>
                  </AlertDialogFooter>
                </AlertDialogContent>
              </AlertDialog>
            </li>
          ))}
          {domains.length === 0 && (
            <li className="text-muted-foreground">No domains yet, so nobody can sign up.</li>
          )}
        </ul>
        <form onSubmit={addDomain} className="mt-3 flex flex-col gap-2 sm:flex-row">
          <Input
            aria-label="Email domain"
            placeholder="university.ie"
            value={domain}
            onChange={(e) => setDomain(e.target.value)}
            required
          />
          <Button type="submit" variant="outline" disabled={busy}>
            <Plus />
            Add
          </Button>
        </form>
      </div>
      <div className="mt-5 border-t pt-4">
        <h3 className="text-sm font-semibold">University admins</h3>
        <ul className="mt-2 space-y-1 text-sm">
          {admins.map((a) => (
            <li key={a.user_id} className="flex items-center justify-between gap-2">
              <span>{a.profiles?.display_name || "Admin"}</span>
              <Button
                variant="ghost"
                size="sm"
                aria-label="Remove"
                onClick={() => removeAdmin(a.user_id)}
              >
                <Trash2 />
              </Button>
            </li>
          ))}
          {invites.map((i) => (
            <li
              key={i.id}
              className="flex items-center justify-between gap-2 text-muted-foreground"
            >
              <span>{i.email}, waiting for first sign-in</span>
              <Button
                variant="ghost"
                size="sm"
                aria-label="Cancel invite"
                onClick={() => cancelInvite(i.id)}
              >
                <Trash2 />
              </Button>
            </li>
          ))}
          {admins.length + invites.length === 0 && (
            <li className="text-muted-foreground">No university admins yet.</li>
          )}
        </ul>
        <form onSubmit={invite} className="mt-3 flex flex-col gap-2 sm:flex-row">
          <Input
            type="email"
            aria-label="Admin email"
            placeholder={`name@${domains[0] ?? "university.ie"}`}
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
          />
          <Button type="submit" variant="outline" disabled={busy}>
            {busy ? <Loader2 className="animate-spin" /> : <UserPlus />}Add
          </Button>
        </form>
      </div>
      {adding && <UniversityDialog onClose={() => setAdding(false)} onCreated={onCreated} />}
    </section>
  );
}

function UniversityDialog({
  onClose,
  onCreated,
}: {
  onClose: () => void;
  onCreated: (id: string) => void;
}) {
  const qc = useQueryClient();
  const [f, setF] = useState({ name: "", short_name: "", slug: "", domains: "" });
  const [busy, setBusy] = useState(false);
  const set = (k: keyof typeof f, v: string) => setF((x) => ({ ...x, [k]: v }));

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    const slug = f.slug || slugify(f.short_name || f.name);
    const domains = f.domains
      .toLowerCase()
      .split(/[\s,]+/)
      .map((d) => d.replace(/^@/, ""))
      .filter(Boolean);
    if (f.name.trim().length < 2 || !f.short_name.trim() || slug.length < 2 || !domains.length)
      return void toast.error("Name, short name, address and a domain are required.");
    setBusy(true);
    const { data, error } = await supabase
      .from("universities")
      .insert({ name: f.name.trim(), short_name: f.short_name.trim(), slug })
      .select("id")
      .single();
    if (error) {
      setBusy(false);
      return void toast.error(
        error.code === "23505" ? "That address is already taken." : error.message,
      );
    }
    const d = await supabase
      .from("university_domains")
      .insert(domains.map((domain) => ({ domain, university_id: data.id })));
    setBusy(false);
    void qc.invalidateQueries({ queryKey: ["admin"] });
    onCreated(data.id);
    onClose();
    // The university exists either way; its domains can be fixed in the list.
    if (d.error) return void toast.error(domainError(d.error));
    toast.success(`${f.short_name.trim()} added`);
  };

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>New university</DialogTitle>
        </DialogHeader>
        <form onSubmit={save} className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="uni-name">Name</Label>
            <Input
              id="uni-name"
              placeholder="e.g. University College Dublin"
              value={f.name}
              onChange={(e) => set("name", e.target.value)}
              maxLength={100}
              required
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="uni-short">Short name</Label>
              <Input
                id="uni-short"
                placeholder="e.g. UCD"
                value={f.short_name}
                onChange={(e) => set("short_name", e.target.value)}
                maxLength={30}
                required
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="uni-slug">Address</Label>
              <Input
                id="uni-slug"
                placeholder={slugify(f.short_name || f.name) || "ucd"}
                value={f.slug}
                onChange={(e) => set("slug", slugify(e.target.value))}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="uni-domains">Email domains</Label>
            <Input
              id="uni-domains"
              placeholder="e.g. ucd.ie, ucdconnect.ie"
              value={f.domains}
              onChange={(e) => set("domains", e.target.value)}
              required
            />
          </div>
          <DialogFooter>
            <Button type="submit" disabled={busy}>
              {busy && <Loader2 className="animate-spin" />}
              Add university
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

function SocietyDialog({
  society,
  universityId,
  onClose,
}: {
  society: SocietyRow | null;
  universityId: string;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const [f, setF] = useState({
    name: society?.name ?? "",
    short_name: society?.short_name ?? "",
    slug: society?.slug ?? "",
    category: society?.category ?? "",
    tagline: society?.tagline ?? "",
    description: society?.description ?? "",
    meets: society?.meets ?? "",
    accent: (society?.accent ?? "indigo") as Accent,
    requires_approval: society?.requires_approval ?? false,
  });
  const [busy, setBusy] = useState(false);
  const set = <K extends keyof typeof f>(k: K, v: (typeof f)[K]) => setF((x) => ({ ...x, [k]: v }));

  const save = async (e: React.FormEvent) => {
    e.preventDefault();
    const slug = f.slug || slugify(f.short_name || f.name);
    if (f.name.trim().length < 2 || !f.short_name.trim() || slug.length < 2)
      return void toast.error("Name, short name and address are required.");
    setBusy(true);
    const row = {
      ...f,
      slug,
      name: f.name.trim(),
      short_name: f.short_name.trim(),
      category: f.category.trim() || "Community",
    };
    const { error } = society
      ? await supabase.from("societies").update(row).eq("id", society.id)
      : await supabase.from("societies").insert({ ...row, university_id: universityId });
    setBusy(false);
    if (error)
      return void toast.error(
        error.code === "23505" ? "That address is already taken." : error.message,
      );
    toast.success(society ? "Society updated" : "Society created");
    void qc.invalidateQueries({ queryKey: ["admin"] });
    onClose();
  };

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>{society ? `Edit ${society.short_name}` : "New society"}</DialogTitle>
        </DialogHeader>
        <form onSubmit={save} className="space-y-3">
          <div className="space-y-1.5">
            <Label htmlFor="soc-name">Name</Label>
            <Input
              id="soc-name"
              value={f.name}
              onChange={(e) => set("name", e.target.value)}
              maxLength={100}
              required
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="soc-short">Short name</Label>
              <Input
                id="soc-short"
                value={f.short_name}
                onChange={(e) => set("short_name", e.target.value)}
                maxLength={30}
                required
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="soc-slug">Address</Label>
              <Input
                id="soc-slug"
                placeholder={slugify(f.short_name || f.name) || "compsoc"}
                value={f.slug}
                onChange={(e) => set("slug", slugify(e.target.value))}
              />
            </div>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label htmlFor="soc-category">Category</Label>
              <Input
                id="soc-category"
                placeholder="e.g. Academic"
                value={f.category}
                onChange={(e) => set("category", e.target.value)}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="soc-accent">Colour</Label>
              <Select value={f.accent} onValueChange={(v) => set("accent", v as Accent)}>
                <SelectTrigger id="soc-accent">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {ACCENTS.map((a) => (
                    <SelectItem key={a} value={a} className="capitalize">
                      {a}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="soc-tagline">Tagline</Label>
            <Input
              id="soc-tagline"
              value={f.tagline}
              onChange={(e) => set("tagline", e.target.value)}
              maxLength={140}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="soc-description">Description</Label>
            <Textarea
              id="soc-description"
              rows={4}
              value={f.description}
              onChange={(e) => set("description", e.target.value)}
              maxLength={2000}
            />
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="soc-meets">When it meets</Label>
            <Input
              id="soc-meets"
              placeholder="e.g. Wednesdays 6pm, Room A12"
              value={f.meets}
              onChange={(e) => set("meets", e.target.value)}
              maxLength={140}
            />
          </div>
          <div className="flex items-center justify-between">
            <Label htmlFor="ra">New members need approval</Label>
            <Switch
              id="ra"
              checked={f.requires_approval}
              onCheckedChange={(v) => set("requires_approval", v)}
            />
          </div>
          <DialogFooter>
            <Button type="submit" disabled={busy}>
              {busy && <Loader2 className="animate-spin" />}
              {society ? "Save" : "Create society"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
