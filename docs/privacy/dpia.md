# Data protection impact assessment (draft)

| | |
|---|---|
| Status | Draft for the DPO, 2026-10-16. Describes the code on `main` plus Phase 4 |
| System | SocConnect, an app for university societies |
| Controller in a pilot | The university (to be named) |
| Processor | The SocConnect team (legal identity to be confirmed) |
| Review | Before a pilot starts, then yearly and whenever processing changes |

A data protection impact assessment (DPIA) is needed because SocConnect processes data that can reveal religion, ethnicity, sexuality, health or disability (membership of some societies, GDPR Article 9), sends some people's speech to an AI service outside the EU, and is aimed at a whole student population. The DPO decides; this draft gives them what they need.

## 1. What SocConnect does

Students sign in with their university email address, find their university's societies, join them, register for events, read announcements, talk in society channels, contact committees and hold video calls. Committees run their society's membership, events, posts, requests and calls. University admins manage their university's societies and committees, handle reports and can suspend accounts. Platform admins (the SocConnect team) do the same across universities and add universities.

Each university's people see only that university's societies. People at different universities can't see each other.

## 2. The processing

### People

Students and staff with an address at a listed university domain. Committee members. University admins (for example Students' Union staff). Guests a committee invites to a call with a link (name only).

Expected scale for one pilot: 500 to 3,000 active students, 70 to 200 societies.

### Data

| Category | Items | Source |
|---|---|---|
| Identity | University email address, display name (required; never the start of the email address, which is often a student number: until 2026-10-16 sign-up used it as the name, and migration 0031 cleared those) | The person, or their university's Microsoft account |
| Study | Course and year (free text, or the university's course list) | The person |
| Preferences | Interests, notification settings | The person |
| University | Which university the account belongs to (from the email domain), when they last signed in, suspension and reason | Automatic, admins |
| Society activity | Memberships and join requests (with whether the membership fee was paid, and whether through the demo checkout or marked by the committee; no card or bank details), committee positions, event registrations, messages, member requests to committees, reports about messages, saved proposals; a calendar link's hash and when it was made. Whoever has the link, and the calendar app it's added to (Google Calendar, for example), sees the events the person registered for | The person, committees |
| **Special category, by inference** | Membership of societies about religion, ethnicity, sexuality, health or disability | The person's choice to join |
| Calls | Who joined, display name in the call; only for people who turn captions on: 7-second audio clips, the transcript, an AI summary and answers | The person |
| AI use | Questions asked, when AI features are used | The person |
| Admin records | The activity log of privileged actions (section 6) | Automatic |
| Technical | Sign-in session in the browser's local storage; the newest message seen in each channel, in local storage until sign-out; a guest's name for a call in session storage; request logs at the hosting provider | Automatic |

Not collected: student numbers, phone numbers, dates of birth, addresses, photos (avatars aren't uploaded), location, advertising identifiers. Society data imported from the university's public societies site leaves out student-number email addresses, phone numbers and committee names.

### Purposes and proposed legal bases

The legal bases are proposals for the DPO. In a pilot, the university chooses them.

| Purpose | Proposed basis | Notes |
|---|---|---|
| Running accounts, societies, events, messages and calls | Article 6(1)(e) public task or 6(1)(f) legitimate interests, depending on the university | Student societies are part of student life the university supports |
| Checking that people are current students | Same as above | Email domain, yearly re-verification |
| Safety: moderation, suspension, usage limits, admin log | Article 6(1)(f) legitimate interests | |
| Captions and AI recaps | Article 6(1)(a) consent | Off by default; each person turns their own on and can turn them off |
| AI suggestions and "Ask SocConnect" | Article 6(1)(f) legitimate interests | Uses only records the person can already see |
| Membership of societies that reveal special-category data | **Open: see decision D1** | |

### Data flows

1. The browser talks to the database directly with the person's own token. Row-level security in the database decides what each person can read or change; the browser is never trusted.
2. Server functions add secrets for calls (LiveKit tokens) and AI (the Lovable AI gateway, which forwards to OpenAI in the United States).
3. Sign-in emails are sent by Lovable's email service.
4. Video and audio go between browsers through LiveKit.
5. Society images load from the university's societies site.

Providers, regions and what is still to confirm: [sub-processors.md](sub-processors.md). Retention: [retention.md](retention.md).

## 3. Necessity and proportionality

- **Minimal profile.** Name, course, year and interests are all the profile holds. Course and year help societies (some are course-based); interests drive recommendations. All three can be left vague.
- **Purpose-bound access.** Each table has row-level security, and each permission is tested for nine kinds of user (`dev/supabase/tests/permission_matrix.test.sql`, about 1,750 checks in CI).
- **No tracking.** No analytics, advertising or tracking cookies. Fonts are bundled, not loaded from Google.
- **AI on request only.** Captions are off until a person turns them on. AI suggestions use the person's own interests and visible society data. Requests ask the provider not to store responses.
- **Retention.** Every short-term category has a period and a nightly job ([retention.md](retention.md)).
- **Rights in the app.** Download (Settings → Your data), correct (profile), delete (Settings → Delete my account, immediate). Objection, restriction and questions go to the privacy contact (to be set up).
- **Accuracy.** People edit their own profile. AI summaries are labelled as AI-written and participants can read them.

## 4. Risks and measures

Likelihood and severity: low, medium, high. "Residual" is the risk after the measures listed.

| # | Risk to people | Before | Measures in place | Residual |
|---|---|---|---|---|
| R1 | Someone learns who belongs to a society about religion, ethnicity, sexuality, health or disability | High | Permission helpers can't be called through the API (migration 0008); member lists only for the society's committee; a pending request doesn't show members; admins can't see memberships; the audit log leaves out membership decisions and the authors of removed messages; tested in the permission matrix | Medium: members of a society see each other, and committees see their members. See D1 and D2 |
| R2 | An admin or committee member misuses their access | Medium | Admin and committee rights only by invite (no admin by email domain, 0007); university admins limited to their university; every grant, invite, rename, archive, removal and suspension is in an audit log nobody can edit (0024) | Low |
| R3 | Someone who isn't (or is no longer) a student gets in | Medium | Sign-up only from listed university domains, also on email change (0011, 0022); sign-in links expire after 10 minutes; sessions end after a year without a university sign-in (0023) | Medium until CAPTCHA (finding 7) and a decision on staff addresses that share the student domain |
| R4 | Speech is processed by an AI service in the United States | High | Captions off by default and per person; explained before joining a call; transcripts deleted after 7 days, recaps after a year; no audio is stored by SocConnect | Medium until the transfer terms are confirmed (sub-processors) |
| R5 | One university's people or data reach another's | Medium | Every society-scoped rule checks the university; `university_isolation.test.sql` | Low |
| R6 | Harassment or abuse between students | Medium | Authors delete their messages; committees and admins remove any; reports to committees and admins; suspension blocks everything at once (0025) | Low |
| R7 | Data kept longer than needed | Medium | Nightly purge for every short-term category (0026) | Low; dormant accounts open (retention.md) |
| R8 | A breach at a provider | Medium | Only public keys in the app; secrets server-side; providers listed | Medium until the providers' agreements and regions are confirmed |
| R9 | An AI summary or suggestion misrepresents someone | Low | Labelled as AI; participants and the committee can read the recap; deleted after a year | Low |
| R10 | Under-16s agree to captions without a parent | Low | The notice asks under-16s to leave captions off | Low |
| R11 | A problem goes unnoticed (errors, sign-in emails not arriving) | Medium | Health endpoint and sign-in delivery check for an uptime monitor; server error reporting once an EU error tracker is set up (T4.4) | Low once the monitor is set up |
| R12 | A change breaks a privacy rule in production | Medium | Database tests and browser journeys run on every pull request; a staging project is planned (T4.5) | Medium until staging exists |
| R13 | Visiting the app tells the university's societies site who visits | Low | Only society images load from it; the notice says so | Low |
| R14 | A suspended person deletes their account and signs up again to escape | Low | A suspended account can't delete itself | Low |

## 5. Open decisions for the DPO

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | Legal basis for memberships that reveal special-category data | (a) Explicit consent when joining a society the university marks as sensitive; (b) another Article 9(2) condition the university can rely on | (a): a "sensitive" flag on societies and a consent step when joining them. About two developer-days |
| D2 | Should members of sensitive societies see each other? | Keep as now; or hide member names from other members for societies marked sensitive (they'd still see message authors) | Ask the societies concerned |
| D3 | Staff and students on one domain | Treat everyone on the domain the same; or only student domains | Per university; TU Dublin separates them already |
| D4 | Dormant accounts | Keep; or delete after two years without a sign-in, with a warning email | Delete after two years, once the custom sending domain exists |
| D5 | Retention periods | The defaults in retention.md | Agree or change each |
| D6 | Who answers rights requests and breaches | The university, the SocConnect team, or both | Set in the processing agreement |

## 6. What the admin activity log records

Platform admin and university admin grants and removals; committee seats added, changed and removed; invites sent and cancelled; societies created, archived, restored, renamed, moved and their official links changed; universities and their email domains; messages removed by someone other than the author (channel and society, not the author); reports dismissed; events cancelled; accounts deleted; suspensions and reinstatements with the reason. University admins see their university's entries; platform admins see all. Kept two years.

## 7. Sign-off

| Role | Name | Date | Outcome |
|---|---|---|---|
| University DPO | | | |
| SocConnect team | | | |
| Students' Union (consulted) | | | |
