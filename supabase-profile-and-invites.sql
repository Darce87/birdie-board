-- Birdie Board: profile completion and existing-account invitations
-- Run this once in Supabase SQL Editor after the initial schema.

alter table public.profiles
  add column if not exists first_name text,
  add column if not exists last_name text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_first_name_length'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_first_name_length
      check (first_name is null or char_length(trim(first_name)) between 1 and 60);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'profiles_last_name_length'
      and conrelid = 'public.profiles'::regclass
  ) then
    alter table public.profiles
      add constraint profiles_last_name_length
      check (last_name is null or char_length(trim(last_name)) between 1 and 80);
  end if;
end;
$$;

-- New accounts begin with a blank profile and must complete it in the app.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, first_name, last_name, handicap)
  values (
    new.id,
    'Player',
    nullif(trim(new.raw_user_meta_data ->> 'first_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'last_name'), ''),
    nullif(new.raw_user_meta_data ->> 'handicap', '')::numeric
  );
  return new;
end;
$$;

-- An organiser/scorer may add an existing Birdie Board account by email.
-- This runs server-side; browser users never receive access to auth.users.
create or replace function public.add_existing_player(
  target_tournament uuid,
  target_email text,
  target_handicap numeric default null
)
returns jsonb
language plpgsql
security definer set search_path = public, auth
as $$
declare
  target_user uuid;
  target_name text;
begin
  if auth.uid() is null or not public.can_manage_tournament(target_tournament) then
    raise exception 'Not authorised to add players to this tournament';
  end if;

  select u.id into target_user
  from auth.users u
  where lower(u.email) = lower(trim(target_email))
  limit 1;

  if target_user is null then
    raise exception 'No Birdie Board account exists for that email address';
  end if;

  insert into public.tournament_members (tournament_id, user_id, role, playing_handicap)
  values (target_tournament, target_user, 'player', target_handicap)
  on conflict (tournament_id, user_id) do update
    set playing_handicap = excluded.playing_handicap;

  select coalesce(nullif(trim(concat_ws(' ', p.first_name, p.last_name)), ''), p.display_name)
    into target_name
  from public.profiles p
  where p.id = target_user;

  return jsonb_build_object('user_id', target_user, 'display_name', target_name);
end;
$$;

revoke all on function public.add_existing_player(uuid, text, numeric) from public;
grant execute on function public.add_existing_player(uuid, text, numeric) to authenticated;
