-- Audit finding 27: anyone signed in could save any proposal id, and the error for an
-- unknown id (a foreign key violation, unlike the policy error for a known one) told them
-- whether it existed. Only proposals the person can read can be saved now; the check runs
-- before the foreign key, so unknown and hidden ids get the same refusal.
drop policy "Save own" on public.saved_proposals;
create policy "Save own" on public.saved_proposals for insert to authenticated
  with check (
    user_id = auth.uid()
    and exists (select 1 from public.collaboration_proposals p where p.id = proposal_id)
  );
