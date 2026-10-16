import { Link } from "@tanstack/react-router";
import { Waypoints } from "lucide-react";
import type { ReactNode } from "react";

/** The privacy notice and the terms of use: public pages, readable before anyone signs up. */
export function LegalPage({
  title,
  updated,
  children,
}: {
  title: string;
  updated: string;
  children: ReactNode;
}) {
  return (
    <div className="min-h-screen">
      <header className="mx-auto flex max-w-3xl items-center px-6 py-5">
        <Link to="/welcome" className="flex items-center gap-2.5">
          <span className="flex size-8 items-center justify-center rounded-lg bg-brand text-primary-foreground">
            <Waypoints className="size-4" />
          </span>
          <span className="font-display text-lg font-semibold">SocConnect</span>
        </Link>
      </header>
      <main className="mx-auto max-w-3xl space-y-10 px-6 pb-12 pt-4 text-[15px] leading-relaxed">
        <div className="space-y-3">
          <h1 className="text-4xl font-semibold tracking-tight">{title}</h1>
          <p className="text-muted-foreground">Last updated {updated}.</p>
        </div>
        {children}
      </main>
      <LegalFooter />
    </div>
  );
}

/** Links to the privacy notice and terms, for the public pages' footers. */
export function LegalFooter({ className }: { className?: string }) {
  return (
    <footer
      className={
        className ??
        "mx-auto flex max-w-3xl flex-wrap gap-x-4 gap-y-1 border-t px-6 py-8 text-xs text-muted-foreground"
      }
    >
      <span>SocConnect, for university societies.</span>
      <Link to="/privacy" className="underline hover:text-foreground">
        Privacy and cookies
      </Link>
      <Link to="/terms" className="underline hover:text-foreground">
        Terms of use
      </Link>
    </footer>
  );
}

export function Section({
  id,
  title,
  children,
}: {
  id?: string;
  title: string;
  children: ReactNode;
}) {
  return (
    <section id={id} className="scroll-mt-6 space-y-3">
      <h2 className="text-xl font-semibold">{title}</h2>
      {children}
    </section>
  );
}

export function Table({ head, rows }: { head: string[]; rows: ReactNode[][] }) {
  return (
    <div className="overflow-x-auto rounded-xl border bg-card">
      <table className="w-full text-left text-sm">
        <thead className="border-b bg-muted/50">
          <tr>
            {head.map((h) => (
              <th key={h} className="px-3 py-2 font-semibold">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y">
          {rows.map((r, i) => (
            <tr key={i}>
              {r.map((c, j) => (
                <td key={j} className="px-3 py-2 align-top">
                  {c}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/** The team's contact address, or what happens until there is one. */
export function ContactLine({ email, children }: { email: string; children: ReactNode }) {
  return email ? (
    <p>
      Email{" "}
      <a className="text-primary underline" href={`mailto:${email}`}>
        {email}
      </a>{" "}
      {children}
    </p>
  ) : (
    <p>
      The SocConnect team will add a contact address here before any university pilot. Until then,
      you can download and delete your data yourself in Settings, and report messages from the
      message's menu.
    </p>
  );
}
