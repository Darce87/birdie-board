-- Birdie Board: live rounds, mobile groups and shared scoring.
-- Run once in the Supabase SQL Editor after the earlier Birdie Board SQL files.

alter table public.tournament_rounds
  add column if not exists status text not null default 'preparation',
  add column if not exists started_at timestamptz,
  add column if not exists locked_at timestamptz;

alter table public.tournament_rounds
  drop constraint if exists tournament_rounds_live_status;
alter table public.tournament_rounds
  add constraint tournament_rounds_live_status check (status in ('preparation','live','locked'));

create table if not exists public.live_round_groups (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.tournament_rounds(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  tee_time time,
  scorer_id uuid references auth.users(id) on delete set null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.live_round_group_members (
  group_id uuid not null references public.live_round_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (group_id, user_id)
);

create table if not exists public.live_round_handicaps (
  round_id uuid not null references public.tournament_rounds(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  exact_handicap numeric(4,1) not null,
  course_handicap integer not null,
  playing_handicap integer not null,
  primary key (round_id, user_id)
);

create table if not exists public.live_round_hole_scores (
  round_id uuid not null references public.tournament_rounds(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  hole_number smallint not null check (hole_number between 1 and 18),
  gross_score smallint not null check (gross_score between 1 and 20),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (round_id, player_id, hole_number)
);

create or replace function public.can_view_live_round(target_round uuid)
returns boolean language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.tournament_rounds r
    join public.tournaments t on t.id = r.tournament_id
    where r.id = target_round
      and (public.can_manage_tournament(t.id)
        or exists (select 1 from public.tournament_members tm where tm.tournament_id = t.id and tm.user_id = auth.uid()))
  );
$$;

alter table public.live_round_groups enable row level security;
alter table public.live_round_group_members enable row level security;
alter table public.live_round_handicaps enable row level security;
alter table public.live_round_hole_scores enable row level security;

drop policy if exists "Participants can view live groups" on public.live_round_groups;
create policy "Participants can view live groups" on public.live_round_groups for select to authenticated using (public.can_view_live_round(round_id));
drop policy if exists "Participants can view live group members" on public.live_round_group_members;
create policy "Participants can view live group members" on public.live_round_group_members for select to authenticated using (exists (select 1 from public.live_round_groups g where g.id = group_id and public.can_view_live_round(g.round_id)));
drop policy if exists "Participants can view live handicaps" on public.live_round_handicaps;
create policy "Participants can view live handicaps" on public.live_round_handicaps for select to authenticated using (public.can_view_live_round(round_id));
drop policy if exists "Participants can view live scores" on public.live_round_hole_scores;
create policy "Participants can view live scores" on public.live_round_hole_scores for select to authenticated using (public.can_view_live_round(round_id));

create or replace function public.save_live_round_groups(target_round uuid, groups jsonb)
returns void language plpgsql security definer set search_path = public
as $$
declare
  event_id uuid; group_entry jsonb; player_id uuid; new_group uuid; assigned uuid[] := '{}'; players uuid[];
begin
  select tournament_id into event_id from public.tournament_rounds where id = target_round;
  if event_id is null or not public.can_manage_tournament(event_id) then raise exception 'Not authorised to manage this round'; end if;
  if (select status from public.tournament_rounds where id = target_round) <> 'preparation' then raise exception 'Groups cannot be changed after the round starts'; end if;
  if jsonb_typeof(groups) <> 'array' or jsonb_array_length(groups) = 0 then raise exception 'Create at least one group'; end if;
  select array_agg(tm.user_id) into players from public.tournament_members tm where tm.tournament_id = event_id;
  delete from public.live_round_groups where round_id = target_round;
  for group_entry in select value from jsonb_array_elements(groups) loop
    if jsonb_array_length(group_entry->'player_ids') not between 1 and 4 then raise exception 'Each group must have one to four players'; end if;
    insert into public.live_round_groups (round_id,name,tee_time,scorer_id,created_by)
    values (target_round,trim(group_entry->>'name'),nullif(group_entry->>'tee_time','')::time,(group_entry->>'scorer_id')::uuid,auth.uid())
    returning id into new_group;
    for player_id in select value::text::uuid from jsonb_array_elements_text(group_entry->'player_ids') loop
      if not player_id = any(players) or player_id = any(assigned) then raise exception 'Every player must be assigned once only'; end if;
      insert into public.live_round_group_members (group_id,user_id) values (new_group,player_id);
      assigned := array_append(assigned,player_id);
    end loop;
    if not exists (select 1 from public.live_round_group_members where group_id=new_group and user_id=(group_entry->>'scorer_id')::uuid) then raise exception 'The scorer must be in their group'; end if;
  end loop;
  if cardinality(assigned) <> cardinality(players) then raise exception 'Assign every tournament player to a group'; end if;
end;
$$;

create or replace function public.start_live_round(target_round uuid)
returns void language plpgsql security definer set search_path = public
as $$
declare
  event_id uuid; event_course_id uuid; slope integer; rating numeric; total_par integer; member_count integer; grouped_count integer;
begin
  select r.tournament_id,r.course_id,c.slope_rating,c.course_rating into event_id,event_course_id,slope,rating
  from public.tournament_rounds r join public.courses c on c.id=r.course_id where r.id=target_round;
  if event_id is null or not public.can_manage_tournament(event_id) then raise exception 'Not authorised to start this round'; end if;
  if (select status from public.tournament_rounds where id=target_round) <> 'preparation' then raise exception 'This round has already started'; end if;
  select count(*) into member_count from public.tournament_members tm where tm.tournament_id=event_id;
  select count(distinct gm.user_id) into grouped_count from public.live_round_groups g join public.live_round_group_members gm on gm.group_id=g.id where g.round_id=target_round;
  if member_count=0 or grouped_count <> member_count then raise exception 'Assign every player to a group before starting'; end if;
  if slope is null or rating is null then raise exception 'Add the tee, slope and course rating before starting'; end if;
  select sum(ch.par) into total_par from public.course_holes ch where ch.course_id=event_course_id;
  if total_par is null then raise exception 'Complete the course scorecard before starting'; end if;
  insert into public.live_round_handicaps (round_id,user_id,exact_handicap,course_handicap,playing_handicap)
  select target_round,tm.user_id,p.handicap,
    round(p.handicap*slope/113+(rating-total_par))::integer,
    round(round(p.handicap*slope/113+(rating-total_par))*0.95)::integer
  from public.tournament_members tm join public.profiles p on p.id=tm.user_id where tm.tournament_id=event_id
  on conflict (round_id,user_id) do nothing;
  update public.tournament_rounds set status='live',started_at=now() where id=target_round;
end;
$$;

create or replace function public.save_live_round_scores(target_round uuid, entries jsonb)
returns void language plpgsql security definer set search_path = public
as $$
declare
  event_id uuid; entry jsonb; player_id uuid; hole integer; gross integer;
begin
  select tournament_id into event_id from public.tournament_rounds where id=target_round;
  if event_id is null or (select status from public.tournament_rounds where id=target_round) <> 'live' then raise exception 'This round is not open for scoring'; end if;
  for entry in select value from jsonb_array_elements(entries) loop
    player_id := (entry->>'player_id')::uuid; hole := (entry->>'hole_number')::integer; gross := (entry->>'gross_score')::integer;
    if hole not between 1 and 18 or gross not between 1 and 20 then raise exception 'Invalid score'; end if;
    if not public.can_manage_tournament(event_id) and not exists (
      select 1 from public.live_round_groups g join public.live_round_group_members gm on gm.group_id=g.id
      where g.round_id=target_round and g.scorer_id=auth.uid() and gm.user_id=player_id
    ) then raise exception 'You can only score your own group'; end if;
    insert into public.live_round_hole_scores(round_id,player_id,hole_number,gross_score,updated_by)
    values(target_round,player_id,hole,gross,auth.uid())
    on conflict(round_id,player_id,hole_number) do update set gross_score=excluded.gross_score,updated_by=excluded.updated_by,updated_at=now();
  end loop;
end;
$$;

create or replace function public.lock_live_round(target_round uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not exists (select 1 from public.tournament_rounds r where r.id=target_round and public.can_manage_tournament(r.tournament_id)) then raise exception 'Not authorised to lock this round'; end if;
  update public.tournament_rounds set status='locked',locked_at=now() where id=target_round and status='live';
end;
$$;

revoke all on function public.can_view_live_round(uuid),public.save_live_round_groups(uuid,jsonb),public.start_live_round(uuid),public.save_live_round_scores(uuid,jsonb),public.lock_live_round(uuid) from public;
grant execute on function public.can_view_live_round(uuid),public.save_live_round_groups(uuid,jsonb),public.start_live_round(uuid),public.save_live_round_scores(uuid,jsonb),public.lock_live_round(uuid) to authenticated;

alter table public.live_round_hole_scores replica identity full;
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'live_round_hole_scores'
  ) then
    alter publication supabase_realtime add table public.live_round_hole_scores;
  end if;
end;
$$;
notify pgrst, 'reload schema';
