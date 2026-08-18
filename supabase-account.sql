-- Birdie Board: self-service account settings
-- Run this once in the Supabase SQL Editor.

create or replace function public.get_my_profile()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  profile_row public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Please sign in';
  end if;

  select * into profile_row
  from public.profiles
  where id = auth.uid();

  return jsonb_build_object(
    'first_name', profile_row.first_name,
    'last_name', profile_row.last_name,
    'handicap', profile_row.handicap
  );
end;
$$;

create or replace function public.update_my_profile(
  profile_first_name text,
  profile_last_name text,
  profile_handicap numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  clean_first_name text := nullif(trim(profile_first_name), '');
  clean_last_name text := nullif(trim(profile_last_name), '');
  saved_profile public.profiles;
begin
  if auth.uid() is null then
    raise exception 'Please sign in';
  end if;

  if clean_first_name is null or clean_last_name is null then
    raise exception 'Please enter your first and last name';
  end if;

  if profile_handicap is null or profile_handicap < 0 or profile_handicap > 54 then
    raise exception 'Exact handicap must be between 0 and 54';
  end if;

  insert into public.profiles (id, display_name, first_name, last_name, handicap)
  values (auth.uid(), clean_first_name, clean_first_name, clean_last_name, profile_handicap)
  on conflict (id) do update set
    display_name = excluded.display_name,
    first_name = excluded.first_name,
    last_name = excluded.last_name,
    handicap = excluded.handicap
  returning * into saved_profile;

  return jsonb_build_object(
    'first_name', saved_profile.first_name,
    'last_name', saved_profile.last_name,
    'handicap', saved_profile.handicap
  );
end;
$$;

revoke all on function public.get_my_profile() from public;
revoke all on function public.update_my_profile(text, text, numeric) from public;
grant execute on function public.get_my_profile() to authenticated;
grant execute on function public.update_my_profile(text, text, numeric) to authenticated;
