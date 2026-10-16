# Data processing agreement (template)

Draft template, 2026-10-16, for a pilot where a university uses SocConnect. It follows GDPR Article 28(3). Square brackets are for the parties to fill in. The university's legal office will usually prefer its own template; this one lists what SocConnect can commit to, so it can be compared clause by clause. It is not legal advice.

---

**Between**

[University name], [address] ("the Controller"), and

[SocConnect team's legal name], [address] ("the Processor").

**Start date:** [date]. **End:** the end of the pilot on [date], or earlier as set out in clause 10.

## 1. Subject and duration

The Processor runs SocConnect, an app for the Controller's student societies, for the Controller during the pilot. This agreement covers the personal data the Processor processes to do that, for as long as it does.

## 2. Nature and purpose

Annex A describes the processing: what is done, why, to which data and about whom. The Processor processes personal data only for those purposes.

## 3. Instructions

The Processor processes personal data only on the Controller's documented instructions. This agreement, the configuration the Controller sets in SocConnect's admin page, and written requests from the Controller's named contact are instructions. The Processor tells the Controller straight away if it thinks an instruction breaks data protection law. If law requires the Processor to process data otherwise, it tells the Controller first, unless the law forbids that.

## 4. Confidentiality

Only people who need access to run SocConnect get it, and they are bound to confidentiality. Platform admin rights are granted by named invitation only, and every grant is recorded in SocConnect's audit log.

## 5. Security

The Processor applies the measures in Annex B and keeps them under review.

## 6. Sub-processors

The Controller gives general authorisation for the sub-processors in Annex C. The Processor gives the Controller [30] days' written notice before adding or replacing one, and the Controller may object. Each sub-processor is bound by data protection terms at least as protective as these. The Processor stays responsible for them.

## 7. International transfers

Personal data leaves the European Economic Area only where Annex C says so, and only under a transfer mechanism in Chapter V of the GDPR (an adequacy decision, including the EU-US Data Privacy Framework, or standard contractual clauses). [The parties to confirm the mechanism for each transfer in Annex C before the pilot starts.]

## 8. Helping the Controller

The Processor helps the Controller to:

- answer requests from people exercising their rights. People can download and delete their own data in the app; the Processor handles anything else within [10] working days of the Controller's request;
- keep personal data secure, and notify and communicate breaches;
- carry out data protection impact assessments and consult the Data Protection Commission where needed.

## 9. Personal data breaches

The Processor tells the Controller's contact without undue delay, and within [24] hours of becoming aware of a breach affecting the Controller's data, with what is known: what happened, what data and how many people, likely consequences, and what has been done. It updates the Controller as it learns more.

## 10. End of the agreement

At the end, the Processor, at the Controller's choice, returns the personal data (as a database export) or deletes it, within [30] days, and confirms in writing. Copies in providers' backups are deleted on their backup cycle, stated in Annex C. The Processor may keep data only where law requires it.

## 11. Records and audits

The Processor keeps a record of the processing it does for the Controller (Annex A is that record) and makes available everything needed to show it meets this agreement. The Controller, or an auditor it appoints, may audit on [30] days' notice, no more than once a year unless there has been a breach.

## 12. Contacts

| | Controller | Processor |
|---|---|---|
| Data protection contact | [DPO name, email] | [name, email] |
| Day-to-day contact | [Students' Union or societies officer] | [name, email] |

Signed for the Controller: ____________ Date: ______

Signed for the Processor: ____________ Date: ______

---

## Annex A: The processing

| | |
|---|---|
| People | The Controller's students and staff with an address at its listed email domains who sign up; committee members; university admins the Controller appoints; call guests invited by committees (name only) |
| Data | Email address, name, course, year, interests, notification settings, university, sign-in times; memberships, committee positions, event registrations, messages, member requests, reports; call participation and, for people who turn captions on, speech clips, transcripts, AI summaries and answers; AI feature use; the admin activity log; suspensions |
| Special category data | Membership of societies about religion, ethnicity, sexuality, health or disability can reveal it (Article 9). See the DPIA |
| Processing | Collection, storage, organisation, retrieval, use, disclosure to the people the app's permissions allow, transfer to sub-processors, deletion |
| Purposes | Running SocConnect for the Controller's societies; checking that users are current students; moderation, suspension, usage limits and the activity log; captions and AI recaps for people who turn them on |
| Retention | As in the retention schedule (docs/privacy/retention.md), enforced by nightly jobs |

## Annex B: Security measures

As built on 2026-10-16:

- **Access control in the database.** Row-level security on every table; permission helpers the API can't call; every table and callable function tested for nine kinds of user in CI. A new table without row-level security, or a new callable function without tests, fails CI.
- **Separation between universities.** Every rule checks the university; tested in CI.
- **Least privilege for admins.** Rights only by named invitation; university admins limited to their university; nobody becomes an admin from their email domain.
- **Audit log.** Privileged actions recorded with who and when; entries can't be edited or deleted through the API, even by the server's service role.
- **Authentication.** Email links to university addresses only, valid for 10 minutes; one university per account; email changes stay at the same university; sessions end after a year without a university sign-in.
- **Secrets.** Only public keys in the app; service keys and API keys held in the hosting provider's secret store and used only by server code.
- **Suspension.** Admins can block an account at once.
- **Minimisation and retention.** No tracking; captions off by default; nightly deletion of short-lived data.
- **Change control.** Every change goes through a pull request with type checks, unit tests, database permission tests and browser journeys. [Staging environment: planned.]
- **Monitoring.** [Health checks and error alerts: being set up.]

## Annex C: Sub-processors

The current list, with locations and transfer mechanisms, is docs/privacy/sub-processors.md, attached as at the date of signing.
