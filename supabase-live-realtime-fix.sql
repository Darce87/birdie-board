-- Run once in Supabase SQL Editor.
-- Ensures score changes are broadcast to participant devices immediately.

alter table public.live_round_hole_scores replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'live_round_hole_scores'
  ) then
    alter publication supabase_realtime
      add table public.live_round_hole_scores;
  end if;
end;
$$;
