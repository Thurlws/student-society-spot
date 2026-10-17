import { createFileRoute, Link } from "@tanstack/react-router";
import { pageHead } from "@/lib/seo";
import {
  DEVICE_STORAGE,
  NOTICE_UPDATED,
  OPERATOR,
  PRIVACY_CONTACT_EMAIL,
  PROVIDERS,
  RETENTION,
} from "@/lib/privacy";
import { TURNSTILE_SITE_KEY } from "@/lib/turnstile";
import { ContactLine, LegalPage, Section, Table } from "@/components/legal-page";

export const Route = createFileRoute("/privacy")({
  head: () =>
    pageHead(
      "Privacy",
      "What SocConnect collects about you, who can see it, how long it's kept and your rights.",
    ),
  component: Privacy,
});

/** The privacy notice. Public, so people can read it before they sign up. */
function Privacy() {
  return (
    <LegalPage title="Privacy and cookies" updated={NOTICE_UPDATED}>
      <div className="space-y-3">
        <p>
          SocConnect is an app for university societies. It started as a student project at TU
          Dublin and is run by {OPERATOR || "the SocConnect team"}. This page says what we collect
          about you, who can see it, how long we keep it, what we store on your device and what you
          can do about it. Using SocConnect also means agreeing to its{" "}
          <Link to="/terms" className="text-primary underline">
            terms of use
          </Link>
          .
        </p>
        <p>
          When a university runs SocConnect as a pilot, the university decides how your data is used
          and the SocConnect team acts on its instructions under a written agreement. The
          university's own privacy notice then applies too.
        </p>
      </div>

      <Section title="What we collect">
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong>Your account:</strong> your university email address, which tells us your
            university; the name you want people to call you, which we need so members know who
            they're talking to; and, if you give them, your course, year and interests. Also your
            notification settings and when you last signed in. If you sign in with Microsoft, your
            university's Microsoft account gives us your name and email address.
          </li>
          <li>
            <strong>What you do in societies:</strong> which societies you join or ask to join,
            committee positions, events you register for, messages you post, requests you send to
            committees, and messages you report. If a society charges a membership fee, whether
            you've paid it and how. SocConnect takes no real payments yet: its demo checkout takes
            no money and asks for no card or bank details.
          </li>
          <li>
            <strong>Calendar link:</strong> if you make one, when you made it. The link itself isn't
            stored, only a scrambled form of it that can't be turned back into the link.
          </li>
          <li>
            <strong>Calls:</strong> when you join a call. Your captions start off. If you turn them
            on, short recordings of your speech are sent to an AI service to be written down. The
            transcript is shared with everyone in the call and used to write an AI summary of the
            call.
          </li>
          <li>
            <strong>AI features:</strong> the questions you ask, and when you use AI features, so we
            can limit how often each person uses them.
          </li>
          <li>
            <strong>On your device:</strong> only what keeps you signed in. See{" "}
            <a href="#cookies" className="text-primary underline">
              cookies and storage
            </a>{" "}
            below.
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
            Members of the same society see each other's name, course and year, and the messages in
            its channels. Asking to join doesn't show you the members.
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
            To run the service you signed up for: your account, your societies, events, messages and
            calls. Our legal basis is our legitimate interest in running SocConnect for students and
            their societies, or, in a pilot, the basis your university sets out.
          </li>
          <li>To check you're a student, by sending sign-in links only to university addresses.</li>
          <li>
            To keep SocConnect safe: moderation, suspensions, usage limits and a log of admin
            actions.
          </li>
          <li>
            Captions and AI recaps only from people who turn captions on. That is your consent, and
            you can take it back at any time with the captions button. If you're under 16, please
            leave captions off.
          </li>
          <li>
            To suggest societies, by matching your interests with the ones societies list. Nothing
            about you is decided automatically: suggestions only change what you see first, and
            AI-written text is labelled as such.
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
              "Its members and join requests, whether you've paid its membership fee, requests you send it, reports about its messages",
            ],
            ["People in a call", "Your name, video, voice and captions while you're in it"],
            [
              "Anyone with your calendar link, and the calendar app you add it to (Google Calendar, for example)",
              "The events you've registered for: titles, times, places and societies. Only if you make a link; you can turn it off in Settings",
            ],
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
        <p>
          "Add to Google Calendar" on an event opens Google Calendar with that event filled in, so
          Google sees it, and only when you choose to. Adding your calendar link to Google Calendar
          lets Google fetch the events you've registered for; Google's own privacy policy then
          applies to them.
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

      <Section id="cookies" title="Cookies and storage on your device">
        <p>
          SocConnect sets no cookies. It has no analytics, no advertising and no tracking, and loads
          nothing from other companies except societies' logos and banners
          {TURNSTILE_SITE_KEY &&
            " and, on the sign-in page, Cloudflare's check that you're not a bot (which looks at your browser but sets no cookies)"}
          . It keeps only these on your device, because they're strictly necessary for what you
          asked for, so you aren't asked to accept cookies:
        </p>
        <Table
          head={["Name", "Where", "Why", "Kept"]}
          rows={DEVICE_STORAGE.map((d) => [
            <code key="n" className="text-xs">
              {d.name}
            </code>,
            d.kind,
            d.why,
            d.kept,
          ])}
        />
        <p>
          You can clear them in your browser's settings at any time; you'll then need a new sign-in
          link. If SocConnect ever adds anything that isn't strictly necessary, it will ask you
          first.
        </p>
      </Section>

      <Section title="How long we keep it">
        <Table head={["Data", "Kept for"]} rows={RETENTION.map((r) => [r.what, r.kept])} />
        <p>
          Deleting your account deletes your profile, memberships, registrations, messages and
          requests straight away. Posts you made as a committee member stay with the society without
          your name. Backups held by our hosting provider are overwritten on their own schedule.
        </p>
      </Section>

      <Section title="Your rights">
        <ul className="list-disc space-y-2 pl-5">
          <li>
            <strong>See and download your data:</strong> Settings, Your data and account, Download
            my data. You get a JSON file you can take to another service.
          </li>
          <li>
            <strong>Correct it:</strong> edit your profile in Settings.
          </li>
          <li>
            <strong>Delete it:</strong> Settings, Your data and account, Delete my account.
          </li>
          <li>
            <strong>Object or ask us to restrict</strong> how we use your data, or ask anything else
            about it, by contacting us.
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
        <ContactLine email={PRIVACY_CONTACT_EMAIL}>
          about anything on this page. In a pilot, you can also contact your university's data
          protection officer.
        </ContactLine>
      </Section>
    </LegalPage>
  );
}
