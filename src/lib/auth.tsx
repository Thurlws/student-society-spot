import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";
import { supabase } from "@/integrations/supabase/client";

/** What to tell someone whose sign-in email request failed, from Supabase's error code. */
export function signInError(e: { code?: string | undefined; message: string }) {
  if (e.code === "over_email_send_rate_limit") {
    const seconds = e.message.match(/(\d+) seconds/)?.[1];
    return seconds
      ? `You just asked for a link. Wait ${seconds} seconds, then try again.`
      : "Too many sign-in emails have gone out in the last hour. Try again later.";
  }
  if (e.code === "over_request_rate_limit")
    return "Too many attempts from this network. Try again in a few minutes.";
  if (e.code === "captcha_failed")
    return "The check that you're not a bot didn't pass. Reload the page and try again.";
  if (/university email|same university/.test(e.message)) return e.message;
  return "We couldn't send the sign-in link. Try again in a minute.";
}

/** Whether a failed sign-in email is SocConnect's problem, worth an alert, rather than the person's. */
export function signInFailureIsOurs(e: { code?: string | undefined; message: string }) {
  if (e.code === "over_email_send_rate_limit") return !/\d+ seconds/.test(e.message);
  if (e.code === "over_request_rate_limit") return false;
  return !/university email|same university/.test(e.message);
}

export type Profile = {
  id: string;
  display_name: string;
  course: string;
  year: string;
  onboarded_at: string | null;
};
export type CommitteeSeat = {
  society_id: string;
  slug: string;
  short_name: string;
  position: string;
};
export type University = { id: string; slug: string; name: string; short_name: string };
export type Access = {
  is_admin: boolean;
  university: University | null;
  university_admin: boolean;
  committee: CommitteeSeat[];
  /** Set while an admin has suspended the account (migration 0025). */
  suspended?: { at: string; reason: string } | null;
};

type AuthValue = {
  ready: boolean;
  session: Session | null;
  email: string;
  profile: Profile | null;
  access: Access;
  interests: string[];
  refresh: () => Promise<void>;
  signOut: () => Promise<void>;
};

const NO_ACCESS: Access = {
  is_admin: false,
  university: null,
  university_admin: false,
  committee: [],
};
const Ctx = createContext<AuthValue | null>(null);
const SIGNED_OUT: AuthValue = {
  ready: false,
  session: null,
  email: "",
  profile: null,
  access: NO_ACCESS,
  interests: [],
  refresh: async () => {},
  signOut: async () => {},
};

export function AuthProvider({ children }: { children: ReactNode }) {
  const [ready, setReady] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [access, setAccess] = useState<Access>(NO_ACCESS);
  const [interests, setInterests] = useState<string[]>([]);

  const load = useCallback(async (s: Session | null) => {
    setSession(s);
    if (!s) {
      setProfile(null);
      setAccess(NO_ACCESS);
      setInterests([]);
      setReady(true);
      return;
    }
    const [p, a, i] = await Promise.all([
      supabase
        .from("profiles")
        .select("id, display_name, course, year, onboarded_at")
        .eq("id", s.user.id)
        .maybeSingle(),
      supabase.rpc("my_access"),
      supabase.from("profile_interests").select("interests(name)").eq("profile_id", s.user.id),
    ]);
    setProfile((p.data as Profile | null) ?? null);
    setAccess((a.data as unknown as Access | null) ?? NO_ACCESS);
    setInterests(
      ((i.data ?? []) as { interests: { name: string } | null }[])
        .map((r) => r.interests?.name)
        .filter((n): n is string => !!n),
    );
    setReady(true);
  }, []);

  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((event, s) => {
      if (event === "SIGNED_IN" || event === "SIGNED_OUT" || event === "USER_UPDATED")
        setTimeout(() => void load(s), 0);
    });
    void supabase.auth.getSession().then(({ data }) => load(data.session));
    return () => sub.subscription.unsubscribe();
  }, [load]);

  const value: AuthValue = {
    ready,
    session,
    email: session?.user.email ?? "",
    profile,
    access,
    interests,
    refresh: async () => load((await supabase.auth.getSession()).data.session),
    signOut: async () => {
      await supabase.auth.signOut();
    },
  };
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useAuth() {
  // Outside the provider (e.g. mid hot-reload or in isolated tests) behave as signed out instead of crashing.
  return useContext(Ctx) ?? SIGNED_OUT;
}

/**
 * Whether someone still has to say what people should call them: no name yet, or only the
 * start of their email address (usually a student number), which sign-up used to fill in.
 */
export const needsName = (name: string | null | undefined, email: string) => {
  const n = (name ?? "").trim().toLowerCase();
  return n.length < 2 || n === email.split("@")[0]!.toLowerCase();
};

export const initialsOf = (name: string) =>
  name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((w) => w[0]!.toUpperCase())
    .join("") || "?";
