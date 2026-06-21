-- Enable Supabase Realtime for cloud relay control-plane tables.
-- Idempotent: safe to re-run if publication membership already exists.

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'command_inbox'
  ) then
    alter publication supabase_realtime add table public.command_inbox;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'command_acks'
  ) then
    alter publication supabase_realtime add table public.command_acks;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'event_envelopes'
  ) then
    alter publication supabase_realtime add table public.event_envelopes;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pair_requests'
  ) then
    alter publication supabase_realtime add table public.pair_requests;
  end if;
end $$;