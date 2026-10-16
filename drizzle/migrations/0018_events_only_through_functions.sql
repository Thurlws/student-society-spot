-- Events change only through update_event and cancel_event, which tell registered people.
-- The delete policy from 0001 still let a committee remove an event through the API: its
-- registrations went with it and nobody was told. The app never deletes events; cancel them.
drop policy "Committee delete events" on public.events;
revoke delete on public.events from anon, authenticated;
