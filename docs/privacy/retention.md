# Retention schedule

Draft, 2026-10-16. The periods are defaults for the DPO to agree. Deletion is automatic: a nightly database job, `purge_expired_data` (migration 0026, 03:30 UTC), deletes what is past its period, and `purge_old_transcripts` (migration 0003, 03:15 UTC) clears call transcripts. Both are tested in `dev/supabase/tests/retention.test.sql`.

To change a period, change the migration's function (in a new migration), `RETENTION` in `src/lib/privacy.ts` (what the notice shows) and this table together.

| Data | Kept for | Why that long | How it goes |
|---|---|---|---|
| Account: email, name, course, year, interests, settings, university | Until the person deletes it | It is the account | Settings → Delete my account deletes it at once, with everything that belongs to it (migration 0012) |
| Sessions of accounts not used for a year | Ended after a year without a sign-in | The next sign-in needs the university mailbox, which proves the person is still a student | Nightly `end_lapsed_sessions` (migration 0023). The account itself stays; see "Open" below |
| Memberships (with whether the membership fee was paid, and how), committee seats | While the account and the society exist | Needed to run the society | Leaving, being removed, or account deletion |
| Messages | While the account and the society exist | A society's discussion history | The author or the committee deletes them; account deletion deletes the author's messages |
| Announcements, events, resources | While the society exists | Society history | Committees delete announcements; events are cancelled, not deleted. An author's deleted account leaves them without a name |
| Event registrations | A year after the event | Attendance can reveal sensitive information; a year covers questions about an event | Nightly purge |
| Calendar link (a SHA-256 hash of it, and when it was made) | Until the person turns it off or makes a new one | Calendar apps fetch it without signing in | Turning it off, a new link, or account deletion |
| Call transcripts | 7 days | Long enough to write and correct the recap | Nightly `purge_old_transcripts` |
| Call recaps (summary, answers, participant names) | A year | Covers a committee's year | Nightly purge |
| Who joined a call | 90 days | Only used to decide who may write a recap | Nightly purge |
| Expired guest links | 30 days after they expire | Questions about who was let in | Nightly purge |
| Notifications | 90 days once read, a year at most | Only useful while new | Nightly purge |
| Message reports | Until handled, then a year | Shows a pattern if someone is reported again | Nightly purge; deleting the message deletes its reports |
| Member requests to committees | Two years after they're resolved | Committees hand over yearly and may need the history | Nightly purge; open requests stay |
| AI usage records | 30 days | Limits look back one hour; a month helps review cost and abuse | Nightly purge |
| AI society suggestions cache | 30 days | A daily cache | Nightly purge |
| Admin activity log | Two years | Accountability for admin and committee actions across two committee years | Nightly purge. Entries can't be edited or deleted any other way |
| Suspension reason | While the suspension lasts | The person must be able to see why | Lifting the suspension clears it; the audit log keeps it for two years |

## Not controlled by SocConnect

To confirm with the providers ([sub-processors.md](sub-processors.md)):

- **Backups** of the Lovable Cloud database: how often, how long they're kept, and whether deleted data can be restored from them.
- **Request logs** at the hosting provider and at Supabase Auth (`auth.audit_log_entries`).
- **Error reports and server logs** in Sentry: kept for its plan's retention period.
- **AI requests** at the Lovable gateway and OpenAI.
- **Sign-in emails** in the email provider's logs and in people's mailboxes.

## Open

- **Dormant accounts.** An account that hasn't signed in for a year is signed out, but its profile and memberships stay. The recommended next step is to delete accounts after two years without a sign-in, with an email a month before. Not built: it deletes data and needs the DPO's and the owner's agreement, and the warning email needs the custom sending domain.
- **Messages.** Kept while the society exists. A university may prefer a limit (for example, messages older than three years).
