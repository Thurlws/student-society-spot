import { createFileRoute, Link } from "@tanstack/react-router";
import { pageHead } from "@/lib/seo";
import { OPERATOR, PRIVACY_CONTACT_EMAIL, TERMS_UPDATED } from "@/lib/privacy";
import { ContactLine, LegalPage, Section } from "@/components/legal-page";

export const Route = createFileRoute("/terms")({
  head: () =>
    pageHead(
      "Terms of use",
      "The rules for using SocConnect, how moderation works and how to report illegal content.",
    ),
  component: Terms,
});

/**
 * The terms of use. Written to cover what the EU Digital Services Act asks of a service that
 * hosts what people post (articles 14, 16 and 17: rules and moderation in the terms, a way to
 * report illegal content, reasons for removals), and the AI Act's labelling of AI-written text.
 * A lawyer should review them before a university pilot (context/go-live.md).
 */
function Terms() {
  const runBy = OPERATOR || "the SocConnect team";
  return (
    <LegalPage title="Terms of use" updated={TERMS_UPDATED}>
      <div className="space-y-3">
        <p>
          SocConnect is an app for university societies, run by {runBy}. These terms are the
          agreement between you and us when you use it. How we handle your personal data is in the{" "}
          <Link to="/privacy" className="text-primary underline">
            privacy notice
          </Link>
          . When your university runs SocConnect as a pilot, its own rules for students and staff
          apply too.
        </p>
      </div>

      <Section title="Who can use SocConnect">
        <ul className="list-disc space-y-2 pl-5">
          <li>
            Students and staff of a university that takes part, signing in with an email address at
            one of its domains. You need to be at least 16.
          </li>
          <li>
            One account each, in your own name. Keep your university mailbox to yourself: anyone who
            can read it can sign in as you.
          </li>
          <li>
            Accounts that haven't signed in for a year are signed out, and need the university
            mailbox to come back. That's how SocConnect checks you're still at the university.
          </li>
        </ul>
      </Section>

      <Section title="Your name and what you post">
        <ul className="list-disc space-y-2 pl-5">
          <li>
            Use the name people know you by. Don't pretend to be someone else, a society or the
            university.
          </li>
          <li>
            What you post stays yours. You let SocConnect show it to the people who can see where
            you posted it (for example a society's members), for as long as it's there. You can
            delete your messages, and your whole account, at any time.
          </li>
          <li>You're responsible for what you post, and for the events your society runs.</li>
        </ul>
      </Section>

      <Section title="The rules">
        <p>Don't use SocConnect to:</p>
        <ul className="list-disc space-y-2 pl-5">
          <li>post anything illegal, or link to it;</li>
          <li>harass, threaten, bully or demean anyone, or post hate speech;</li>
          <li>
            share someone else's personal details, photos or private messages without their
            agreement;
          </li>
          <li>spam, advertise or sell, unless it's your society's own event or activity;</li>
          <li>record a call without everyone in it agreeing;</li>
          <li>
            get around a suspension, a usage limit or a society's privacy, or collect data with
            scripts or bots;
          </li>
          <li>break, overload or probe SocConnect or anyone's account.</li>
        </ul>
        <p>Societies can set their own rules for their channels on top of these.</p>
      </Section>

      <Section title="Reporting a message or illegal content">
        <ul className="list-disc space-y-2 pl-5">
          <li>
            If you're in the society, open the message's menu and choose{" "}
            <strong>Report to the committee</strong>. The committee and the admins see your report;
            the author isn't told who reported it.
          </li>
          <li>
            Anyone, with or without an account, can report content they believe is illegal by
            contacting us (below). Say where it is, why you think it's illegal, and your name and
            email address. We confirm we've received it, decide promptly and tell you what we
            decided.
          </li>
        </ul>
      </Section>

      <Section title="How moderation works">
        <ul className="list-disc space-y-2 pl-5">
          <li>
            A society's committee looks after its channels. Your university's admins, and the
            SocConnect team's admins, look after the whole service. People make every moderation
            decision; nothing is removed automatically.
          </li>
          <li>
            They can remove messages that break these terms or the society's rules, archive a
            society, and suspend an account. A society's committee can also remove a member from the
            society; you're told when that happens, and why if they give a reason. A suspended
            account can't see or do anything until the suspension is lifted.
          </li>
          <li>
            If your message is removed, you get a notification saying so, with the reason when one
            is given. If your account is suspended, you see the reason when you sign in.
          </li>
          <li>
            If you think a decision was wrong, send the committee a request from the society's page,
            or contact us. You can also take it to the courts.
          </li>
        </ul>
      </Section>

      <Section title="AI features">
        <p>
          Some features use AI: captions in calls, call recaps and answers, and the explanations of
          why a society might suit you. AI-written text is labelled, and it can be wrong, so check
          anything that matters. Captions stay off until you turn yours on.
        </p>
      </Section>

      <Section title="The service">
        <ul className="list-disc space-y-2 pl-5">
          <li>
            SocConnect is free. We work to keep it running and secure, but it's a new service and it
            may change, pause or stop.
          </li>
          <li>
            Societies run their own events and decide who joins them. We're not responsible for what
            societies or other people do or post, but we act on reports.
          </li>
          <li>
            Nothing in these terms limits what we owe you where the law doesn't allow it to be
            limited, or takes away your rights as a consumer.
          </li>
          <li>
            We'll tell you in SocConnect before we change these terms in a way that matters. If you
            don't agree, you can delete your account.
          </li>
          <li>
            Irish law applies, and the Irish courts can hear disputes. If you live elsewhere in the
            EU, you keep the protection of your own country's consumer law.
          </li>
        </ul>
      </Section>

      <Section title="Contact">
        <ContactLine email={PRIVACY_CONTACT_EMAIL}>
          to report illegal content, question a decision, or ask anything about these terms. This is
          also our point of contact for authorities under the Digital Services Act.
        </ContactLine>
      </Section>
    </LegalPage>
  );
}
