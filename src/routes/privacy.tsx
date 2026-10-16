import { createFileRoute, Link } from "@tanstack/react-router";
import { Waypoints } from "lucide-react";
import type { ReactNode } from "react";
import { pageHead } from "@/lib/seo";
import { NOTICE_UPDATED, PRIVACY_CONTACT_EMAIL, PROVIDERS, RETENTION } from "@/lib/privacy";

export const Route = createFileRoute("/privacy")({
  head: () =>
    pageHead(
      "Privacy",
      "What SocConnect collects about you, who can see it, how long it's kept and your rights.",
    ),
  component: Privacy,
});

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="space-y-3">
      <h2 className="text-xl font-semibold">{title}</h2>
      {children}
    </section>
  );
}

function Table({ head, rows }: { head: string[]; rows: string[][] }) {
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
          {rows.map((r) => (
            <tr key={r[0]}>
              {r.map((c, i) => (
                <td key={i} className="px-3 py-2 align-top">
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

/** The privacy notice. Public, so people can read it before they sign up. */
function Privacy() {
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
      <main className="mx-auto max-w-3xl space-y-10 px-6 pb-16 pt-4 text-[15px] leading-relaxed">
        <div className="space-y-3">
          <h1 className="text-4xl font-semibold tracking-tight">Privacy</h1>
          <p className="text-muted-foreground">Last updated {NOTICE_UPDATED}.</p>
          <p>
            SocConnect is an app for university societies. It started as a student project at TU
            Dublin and is run by the SocConnect team. This page says what we collect about you, who
            can see it, how long we keep it and what you can do about it.
          </p>
          <p>
            When a university runs SocConnect as a pilot, the university decides how your data is
            used and the SocConnect team acts on its instructions under a written agreement. The
            university's own privacy notice then applies too.
          </p>
        </div>

        <Section title="What we collect">
          <ul className="list-disc space-y-2 pl-5">
            <li>
              <strong>Your account:</strong> your university email address, which tells us your
              university, and the name, course, year and interests you give us. Also your
              notification settings and when you last signed in. If you sign in with Microsoft, your
              university's Microsoft account gives us your name and email address.
            </li>
            <li>
              <strong>What you do in societies:</strong> which societies you join or ask to join,
              committee positions, events you register for, messages you post, requests you send to
              committees, and messages you report.
            </li>
            <li>
              <strong>Calls:</strong> when you join a call. Your captions start off. If you turn
              them on, short recordings of your speech are sent to an AI service to be written down.
              The transcript is shared with everyone in the call and used to write an AI summary of
              the call.
            </li>
            <li>
              <strong>AI features:</strong> the questions you ask, and when you use AI features, so
              we can limit how often each person uses them.
            </li>
            <li>
              <strong>Your browser</strong> keeps you signed in with a token in its local storage.
              We don't use advertising or tracking cookies, and we don't sell or share data for
              advertising.
            </li>
          </ul>
        </Section>

        <Section title="Societies that reveal sensitive information">
          <p>
            Some societies are about religion, ethnicity, sexuality, health or disability. Being a
            member can say something sensitive about you. So memberships are kept tight:
          </p>
          <ul className="list-disc space-y-2 pl-5">
            <li>A society's committee sees its members and requests to join.</li>
            <li>
              Members of the same society see each other's name, course and year, and the messages
              in its channels. Asking to join doesn't show you the members.
            </li>
            <li>
              University and platform admins can't see who belongs to a society. The admin activity
              log doesn't record who was approved into a society.
            </li>
          </ul>
        </Section>

        <Section title="Why we use it">
          <ul className="list-disc space-y-2 pl-5">
            <li>
              To run the service you signed up for: your account, your societies, events, messages
              and calls. Our legal basis is our legitimate interest in running SocConnect for
              students and their societies, or, in a pilot, the basis your university sets out.
            </li>
            <li>
              To check you're a student, by sending sign-in links only to university addresses.
            </li>
            <li>
              To keep SocConnect safe: moderation, suspensions, usage limits and a log of admin
              actions.
            </li>
            <li>
              Captions and AI recaps only from people who turn captions on. That is your consent,
              and you can take it back at any time with the captions button. If you're under 16,
              please leave captions off.
            </li>
          </ul>
        </Section>

        <Section title="Who sees what">
          <Table
            head={["Who", "What they see"]}
            rows={[
              [
                "Everyone at your university on SocConnect",
                "Societies, their events and announcements, and committee members' names",
              ],
              [
                "Members of a society you're in",
                "Your name, course and year, and your messages in its channels",
              ],
              [
                "The society's committee",
                "Its members and join requests, requests you send it, reports about its messages",
              ],
              ["People in a call", "Your name, video, voice and captions while you're in it"],
              [
                "Your university's admins",
                "Profiles of people at the university, reported message excerpts, the admin activity log. Not society memberships or channels.",
              ],
              [
                "SocConnect's platform admins",
                "The same as university admins, for every university, to run and fix the service",
              ],
            ]}
          />
          <p>
            People at other universities see nothing of yours. Society logos and banners load from
            your university's own societies website, which sees your IP address when they load.
          </p>
        </Section>

        <Section title="Service providers">
          <p>These companies process data for us. They may only use it to provide their service.</p>
          <ul className="divide-y rounded-xl border bg-card text-sm">
            {PROVIDERS.map((p) => (
              <li key={p.name} className="space-y-1 px-4 py-3">
                <p className="font-semibold">{p.name}</p>
                <p>{p.does}.</p>
                <p className="text-muted-foreground">
                  Data: {p.data}. Where: {p.where}.
                </p>
              </li>
            ))}
          </ul>
        </Section>

        <Section title="How long we keep it">
          <Table head={["Data", "Kept for"]} rows={RETENTION.map((r) => [r.what, r.kept])} />
          <p>
            Deleting your account deletes your profile, memberships, registrations, messages and
            requests straight away. Posts you made as a committee member stay with the society
            without your name. Backups held by our hosting provider are overwritten on their own
            schedule.
          </p>
        </Section>

        <Section title="Your rights">
          <ul className="list-disc space-y-2 pl-5">
            <li>
              <strong>See and download your data:</strong> Settings, Your data, Download my data.
            </li>
            <li>
              <strong>Correct it:</strong> edit your profile in Settings.
            </li>
            <li>
              <strong>Delete it:</strong> Settings, Your data, Delete my account.
            </li>
            <li>
              <strong>Object or ask us to restrict</strong> how we use your data, or ask anything
              else about it, by contacting us.
            </li>
            <li>
              <strong>Complain</strong> to the Data Protection Commission at{" "}
              <a className="text-primary underline" href="https://www.dataprotection.ie">
                dataprotection.ie
              </a>
              .
            </li>
          </ul>
        </Section>

        <Section title="Contact">
          {PRIVACY_CONTACT_EMAIL ? (
            <p>
              Email{" "}
              <a className="text-primary underline" href={`mailto:${PRIVACY_CONTACT_EMAIL}`}>
                {PRIVACY_CONTACT_EMAIL}
              </a>{" "}
              about anything on this page. In a pilot, you can also contact your university's data
              protection officer.
            </p>
          ) : (
            <p>
              The SocConnect team will add a contact address here before any university pilot. Until
              then, you can download and delete your data yourself in Settings.
            </p>
          )}
        </Section>
      </main>
    </div>
  );
}
