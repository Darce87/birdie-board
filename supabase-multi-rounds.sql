-- Birdie Board: multi-round tournament foundation.
-- Run once in the Supabase SQL Editor before enabling the multi-round setup UI.

create table if not exists public.tournament_rounds (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  round_number smallint not null check (round_number between 1 and 20),
  course_id uuid not null references public.courses(id),
  starts_at timestamptz,
  created_at timestamptz not null default now(),
  unique (tournament_id, round_number)
);

create index if not exists tournament_rounds_tournament_index
on public.tournament_rounds (tournament_id, round_number);

-- Preserve existing tournaments as a single first round.
insert into public.tournament_rounds (tournament_id, round_number, course_id, starts_at)
select t.id, 1, t.course_id, t.starts_at
from public.tournaments t
where t.course_id is not null
  and not exists (
    select 1 from public.tournament_rounds r where r.tournament_id = t.id
  );

alter table public.tournament_rounds enable row level security;

create policy "Club members can view tournament rounds"
on public.tournament_rounds
for select to authenticated
using (public.is_club_member((select t.club_id from public.tournaments t where t.id = tournament_id)));

create policy "Tournament organisers can manage rounds"
on public.tournament_rounds
for all to authenticated
using (public.can_manage_tournament(tournament_id))
with check (public.can_manage_tournament(tournament_id));
