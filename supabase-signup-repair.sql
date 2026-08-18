-- Birdie Board: repair missing player profiles and make club joining resilient.
-- Run once in the Supabase SQL Editor.

-- Create a basic player profile for any existing Auth user who does not have one.
insert into public.profiles (id, display_name, first_name, last_name, handicap)
select
  u.id,
  coalesce(nullif(trim(u.raw_user_meta_data ->> 'first_name'), ''), 'Player'),
  nullif(trim(u.raw_user_meta_data ->> 'first_name'), ''),
  nullif(trim(u.raw_user_meta_data ->> 'last_name'), ''),
  coalesce(nullif(u.raw_user_meta_data ->> 'handicap', '')::numeric, 0)
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id);

-- A safety net for future users whose profile trigger has not completed.
create or replace function public.join_social_club(code text)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  target_club public.clubs;
begin
  if auth.uid() is null then
    raise exception 'Please sign in';
  end if;

  select * into target_club
  from public.clubs
  where invite_code = upper(trim(code));

  if target_club.id is null then
    raise exception 'That club code was not found';
  end if;

  insert into public.profiles (id, display_name, first_name, last_name, handicap)
  select
    u.id,
    coalesce(nullif(trim(u.raw_user_meta_data ->> 'first_name'), ''), 'Player'),
    nullif(trim(u.raw_user_meta_data ->> 'first_name'), ''),
    nullif(trim(u.raw_user_meta_data ->> 'last_name'), ''),
    coalesce(nullif(u.raw_user_meta_data ->> 'handicap', '')::numeric, 0)
  from auth.users u
  where u.id = auth.uid()
  on conflict (id) do nothing;

  insert into public.club_members (club_id, user_id, role)
  values (target_club.id, auth.uid(), 'member')
  on conflict do nothing;

  return jsonb_build_object('id', target_club.id, 'name', target_club.name);
end;
$$;

revoke all on function public.join_social_club(text) from public;
grant execute on function public.join_social_club(text) to authenticated;
