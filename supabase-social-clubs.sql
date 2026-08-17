-- Birdie Board: social clubs, playing groups, scoring control and finalisation.
-- Run once in the Supabase SQL Editor after the existing Birdie Board SQL.

alter table public.clubs add column if not exists invite_code text;
create unique index if not exists clubs_invite_code_unique on public.clubs (invite_code) where invite_code is not null;
alter table public.tournaments add column if not exists club_id uuid references public.clubs(id) on delete set null;
alter table public.tournaments add column if not exists is_finalised boolean not null default false;
alter table public.tournaments add column if not exists finalised_at timestamptz;
alter table public.tournaments add column if not exists finalised_by uuid references auth.users(id);

create table if not exists public.tournament_groups (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80),
  scorer_id uuid references auth.users(id) on delete set null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists public.tournament_group_members (
  group_id uuid not null references public.tournament_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  primary key (group_id, user_id)
);

create table if not exists public.score_overrides (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  hole_number smallint not null check (hole_number between 1 and 18),
  stableford_points smallint not null check (stableford_points between 0 and 20),
  reason text not null check (char_length(trim(reason)) between 2 and 240),
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (tournament_id, player_id, hole_number)
);

create or replace function public.is_club_member(target_club uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.club_members where club_id = target_club and user_id = auth.uid()) $$;

create or replace function public.is_club_organiser(target_club uuid)
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.club_members where club_id = target_club and user_id = auth.uid() and role::text in ('owner','admin')) $$;

create or replace function public.create_social_club(club_name text)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare new_club public.clubs; new_code text;
begin
  if auth.uid() is null then raise exception 'Please sign in'; end if;
  if char_length(trim(club_name)) not between 2 and 80 then raise exception 'Club name must be between 2 and 80 characters'; end if;
  loop
    new_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
    exit when not exists (select 1 from public.clubs where invite_code = new_code);
  end loop;
  insert into public.clubs (name, owner_id, invite_code) values (trim(club_name), auth.uid(), new_code) returning * into new_club;
  insert into public.club_members (club_id, user_id, role) values (new_club.id, auth.uid(), 'owner') on conflict do nothing;
  return jsonb_build_object('id', new_club.id, 'name', new_club.name, 'invite_code', new_code);
end;
$$;

create or replace function public.join_social_club(code text)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare target_club public.clubs;
begin
  if auth.uid() is null then raise exception 'Please sign in'; end if;
  select * into target_club from public.clubs where invite_code = upper(trim(code));
  if target_club.id is null then raise exception 'That club code was not found'; end if;
  insert into public.club_members (club_id, user_id, role) values (target_club.id, auth.uid(), 'member') on conflict do nothing;
  return jsonb_build_object('id', target_club.id, 'name', target_club.name);
end;
$$;

create or replace function public.add_club_player_to_tournament(target_tournament uuid, target_player uuid, target_handicap numeric default null)
returns void language plpgsql security definer set search_path = public
as $$
declare club_for_tournament uuid;
begin
  if not public.can_manage_tournament(target_tournament) then raise exception 'Not authorised to manage this tournament'; end if;
  select club_id into club_for_tournament from public.tournaments where id = target_tournament;
  if club_for_tournament is null or not exists (select 1 from public.club_members where club_id = club_for_tournament and user_id = target_player) then
    raise exception 'Player is not a member of this social club';
  end if;
  insert into public.tournament_members (tournament_id, user_id, role, playing_handicap)
  values (target_tournament, target_player, 'player', target_handicap)
  on conflict (tournament_id, user_id) do update set playing_handicap = excluded.playing_handicap;
end;
$$;

create or replace function public.create_playing_group(target_tournament uuid, group_name text, group_scorer uuid, group_players uuid[])
returns uuid language plpgsql security definer set search_path = public
as $$
declare new_group uuid;
begin
  if not public.can_manage_tournament(target_tournament) then raise exception 'Not authorised to manage this tournament'; end if;
  if (select is_finalised from public.tournaments where id = target_tournament) then raise exception 'This tournament is finalised'; end if;
  if cardinality(group_players) not between 1 and 4 then raise exception 'A playing group must have between 1 and 4 players'; end if;
  if group_scorer is not null and not group_scorer = any(group_players) then raise exception 'The scorer must be in this group'; end if;
  if exists (select 1 from unnest(group_players) p where not exists (select 1 from public.tournament_members tm where tm.tournament_id = target_tournament and tm.user_id = p)) then
    raise exception 'Every group member must be a tournament player';
  end if;
  insert into public.tournament_groups (tournament_id, name, scorer_id, created_by) values (target_tournament, trim(group_name), group_scorer, auth.uid()) returning id into new_group;
  insert into public.tournament_group_members (group_id, user_id) select new_group, unnest(group_players);
  return new_group;
end;
$$;

create or replace function public.save_group_scores(target_tournament uuid, entries jsonb)
returns void language plpgsql security definer set search_path = public
as $$
declare entry jsonb; target_player uuid; target_hole int; target_score int; allowed boolean;
begin
  if (select is_finalised from public.tournaments where id = target_tournament) then raise exception 'This tournament is finalised'; end if;
  for entry in select * from jsonb_array_elements(entries) loop
    target_player := (entry->>'player_id')::uuid; target_hole := (entry->>'hole_number')::int; target_score := (entry->>'gross_score')::int;
    if target_hole not between 1 and 18 or target_score not between 1 and 20 then raise exception 'Invalid score'; end if;
    allowed := public.can_manage_tournament(target_tournament)
      or target_player = auth.uid()
      or exists (
        select 1 from public.tournament_groups g join public.tournament_group_members gm on gm.group_id = g.id
        where g.tournament_id = target_tournament and g.scorer_id = auth.uid() and gm.user_id = target_player
      );
    if not allowed then raise exception 'You can only enter scores for your playing group'; end if;
    insert into public.hole_scores (tournament_id, player_id, hole_number, gross_score, updated_by)
    values (target_tournament, target_player, target_hole, target_score, auth.uid())
    on conflict (tournament_id, player_id, hole_number) do update set gross_score = excluded.gross_score, updated_by = excluded.updated_by;
  end loop;
end;
$$;

create or replace function public.set_score_override(target_tournament uuid, target_player uuid, target_hole int, target_points int, override_reason text)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_manage_tournament(target_tournament) then raise exception 'Not authorised to override scores'; end if;
  if (select is_finalised from public.tournaments where id = target_tournament) then raise exception 'Reopen the tournament before making changes'; end if;
  insert into public.score_overrides (tournament_id, player_id, hole_number, stableford_points, reason, updated_by)
  values (target_tournament, target_player, target_hole, target_points, trim(override_reason), auth.uid())
  on conflict (tournament_id, player_id, hole_number) do update set stableford_points = excluded.stableford_points, reason = excluded.reason, updated_by = excluded.updated_by, updated_at = now();
end;
$$;

create or replace function public.set_tournament_finalised(target_tournament uuid, should_finalise boolean)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_manage_tournament(target_tournament) then raise exception 'Not authorised to finalise this tournament'; end if;
  update public.tournaments set is_finalised = should_finalise, finalised_at = case when should_finalise then now() else null end, finalised_by = case when should_finalise then auth.uid() else null end where id = target_tournament;
end;
$$;

create or replace function public.delete_tournament(target_tournament uuid)
returns void language plpgsql security definer set search_path = public
as $$
begin
  if not public.can_manage_tournament(target_tournament) then
    raise exception 'Not authorised to delete this tournament';
  end if;
  delete from public.tournaments where id = target_tournament;
end;
$$;

alter table public.tournament_groups enable row level security;
alter table public.tournament_group_members enable row level security;
alter table public.score_overrides enable row level security;

-- Club members can see their own club roster, but only server-side functions change membership.
drop policy if exists "Club members can view clubs" on public.clubs;
create policy "Club members can view clubs" on public.clubs for select to authenticated using (public.is_club_member(id));
drop policy if exists "Club members can view roster" on public.club_members;
create policy "Club members can view roster" on public.club_members for select to authenticated using (public.is_club_member(club_id));

drop policy if exists "Club members can view club tournaments" on public.tournaments;
create policy "Club members can view club tournaments" on public.tournaments for select to authenticated using (club_id is not null and public.is_club_member(club_id));

drop policy if exists "Club members can view each other's profiles" on public.profiles;
create policy "Club members can view each other's profiles" on public.profiles for select to authenticated using (
  id = (select auth.uid()) or exists (
    select 1 from public.club_members mine
    join public.club_members teammate on teammate.club_id = mine.club_id
    where mine.user_id = (select auth.uid()) and teammate.user_id = profiles.id
  )
);

drop policy if exists "Tournament members can view groups" on public.tournament_groups;
create policy "Tournament members can view groups" on public.tournament_groups for select to authenticated using (public.can_view_tournament(tournament_id));
drop policy if exists "Tournament members can view group members" on public.tournament_group_members;
create policy "Tournament members can view group members" on public.tournament_group_members for select to authenticated using (exists (select 1 from public.tournament_groups g where g.id = group_id and public.can_view_tournament(g.tournament_id)));
drop policy if exists "Tournament members can view score overrides" on public.score_overrides;
create policy "Tournament members can view score overrides" on public.score_overrides for select to authenticated using (public.can_view_tournament(tournament_id));

revoke all on function public.create_social_club(text) from public;
revoke all on function public.join_social_club(text) from public;
revoke all on function public.add_club_player_to_tournament(uuid,uuid,numeric) from public;
revoke all on function public.create_playing_group(uuid,text,uuid,uuid[]) from public;
revoke all on function public.save_group_scores(uuid,jsonb) from public;
revoke all on function public.set_score_override(uuid,uuid,int,int,text) from public;
revoke all on function public.set_tournament_finalised(uuid,boolean) from public;
revoke all on function public.delete_tournament(uuid) from public;
grant execute on function public.create_social_club(text), public.join_social_club(text), public.add_club_player_to_tournament(uuid,uuid,numeric), public.create_playing_group(uuid,text,uuid,uuid[]), public.save_group_scores(uuid,jsonb), public.set_score_override(uuid,uuid,int,int,text), public.set_tournament_finalised(uuid,boolean) to authenticated;
grant execute on function public.delete_tournament(uuid) to authenticated;
