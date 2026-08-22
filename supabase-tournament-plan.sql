-- Birdie Board: organiser-controlled tournament plan changes.
-- Run once in the Supabase SQL Editor.

create table if not exists public.tournament_courses (
  tournament_id uuid not null references public.tournaments(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  primary key (tournament_id, course_id)
);

-- This is a planning map, not a PostgREST relationship.  Keeping these two
-- foreign keys would make Supabase see two routes from tournaments to courses.
alter table public.tournament_courses
  drop constraint if exists tournament_courses_tournament_id_fkey,
  drop constraint if exists tournament_courses_course_id_fkey;

insert into public.tournament_courses (tournament_id, course_id)
select distinct tournament_id, course_id
from public.tournament_rounds
on conflict do nothing;

alter table public.tournament_courses enable row level security;
drop policy if exists "Tournament managers can view tournament courses" on public.tournament_courses;
create policy "Tournament managers can view tournament courses"
on public.tournament_courses for select to authenticated
using (public.can_manage_tournament(tournament_id));

create or replace function public.sync_tournament_course()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.tournament_courses (tournament_id, course_id)
  values (new.tournament_id, new.course_id)
  on conflict do nothing;
  return new;
end;
$$;

drop trigger if exists tournament_round_course_sync on public.tournament_rounds;
create trigger tournament_round_course_sync
after insert or update of course_id on public.tournament_rounds
for each row execute function public.sync_tournament_course();

create or replace function public.update_tournament_plan(
  target_tournament uuid,
  new_name text,
  new_round_count integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count integer;
  first_course uuid;
  first_date timestamptz;
  round_no integer;
begin
  if auth.uid() is null or not public.can_manage_tournament(target_tournament) then
    raise exception 'Not authorised to edit this tournament';
  end if;
  if char_length(trim(new_name)) not between 2 and 120 then
    raise exception 'Tournament name must be between 2 and 120 characters';
  end if;
  if new_round_count not between 1 and 20 then
    raise exception 'Choose between 1 and 20 rounds';
  end if;
  select count(*) into current_count
  from public.tournament_rounds where tournament_id = target_tournament;
  select course_id, starts_at into first_course, first_date
  from public.tournament_rounds
  where tournament_id = target_tournament
  order by round_number
  limit 1;
  if first_course is null then raise exception 'Tournament has no course to use for new rounds'; end if;
  update public.tournaments set name = trim(new_name) where id = target_tournament;
  if new_round_count < current_count then
    delete from public.tournament_rounds where tournament_id = target_tournament and round_number > new_round_count;
  elsif new_round_count > current_count then
    for round_no in current_count + 1..new_round_count loop
      insert into public.tournament_rounds (tournament_id, round_number, course_id, starts_at)
      values (target_tournament, round_no, first_course, first_date);
    end loop;
  end if;
end;
$$;

revoke all on function public.update_tournament_plan(uuid,text,integer) from public;
grant execute on function public.update_tournament_plan(uuid,text,integer) to authenticated;

-- Add a reusable course to an existing tournament.  Its scorecard starts as a
-- copy of the first course, so the organiser only needs to correct differences.
create or replace function public.add_tournament_course(
  target_tournament uuid,
  course_name text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  source_course uuid;
  new_course uuid;
begin
  if auth.uid() is null or not public.can_manage_tournament(target_tournament) then
    raise exception 'Not authorised to edit this tournament';
  end if;
  if char_length(trim(course_name)) not between 2 and 120 then
    raise exception 'Course name must be between 2 and 120 characters';
  end if;

  select course_id into source_course
  from public.tournament_rounds
  where tournament_id = target_tournament
  order by round_number
  limit 1;

  insert into public.courses (name, created_by)
  values (trim(course_name), auth.uid())
  returning id into new_course;

  insert into public.course_holes (course_id, hole_number, par, stroke_index)
  select new_course, hole_number, par, stroke_index
  from public.course_holes
  where course_id = source_course
  order by hole_number;

  insert into public.tournament_courses (tournament_id, course_id)
  values (target_tournament, new_course);

  return new_course;
end;
$$;

create or replace function public.update_tournament_course_scorecard(
  target_tournament uuid,
  target_course uuid,
  scorecard jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  entry jsonb;
  seen_indices integer[] := '{}';
begin
  if auth.uid() is null or not public.can_manage_tournament(target_tournament) then
    raise exception 'Not authorised to edit this tournament';
  end if;
  if not exists (
    select 1 from public.tournament_courses
    where tournament_id = target_tournament and course_id = target_course
  ) then
    raise exception 'This course is not part of the tournament';
  end if;
  if jsonb_array_length(scorecard) <> 18 then
    raise exception 'A scorecard needs all 18 holes';
  end if;

  for entry in select value from jsonb_array_elements(scorecard) loop
    if (entry->>'hole_number')::integer not between 1 and 18
       or (entry->>'par')::integer not between 3 and 6
       or (entry->>'stroke_index')::integer not between 1 and 18 then
      raise exception 'Check the par and stroke-index values';
    end if;
    seen_indices := array_append(seen_indices, (entry->>'stroke_index')::integer);
  end loop;
  if (select count(distinct value) from unnest(seen_indices) value) <> 18 then
    raise exception 'Use every stroke index from 1 to 18 once';
  end if;

  delete from public.course_holes where course_id = target_course;
  insert into public.course_holes (course_id, hole_number, par, stroke_index)
  select target_course,
         (value->>'hole_number')::integer,
         (value->>'par')::integer,
         (value->>'stroke_index')::integer
  from jsonb_array_elements(scorecard)
  order by (value->>'hole_number')::integer;
end;
$$;

revoke all on function public.add_tournament_course(uuid,text) from public;
revoke all on function public.update_tournament_course_scorecard(uuid,uuid,jsonb) from public;
grant execute on function public.add_tournament_course(uuid,text) to authenticated;
grant execute on function public.update_tournament_course_scorecard(uuid,uuid,jsonb) to authenticated;

create or replace function public.get_tournament_courses(target_tournament uuid)
returns table (id uuid, name text)
language sql
security definer
set search_path = public
as $$
  select c.id, c.name
  from public.tournament_courses tc
  join public.courses c on c.id = tc.course_id
  where tc.tournament_id = target_tournament
    and public.can_manage_tournament(target_tournament)
  order by c.name;
$$;

revoke all on function public.get_tournament_courses(uuid) from public;
grant execute on function public.get_tournament_courses(uuid) to authenticated;

create or replace function public.use_one_tournament_course(target_tournament uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_course uuid;
begin
  if auth.uid() is null or not public.can_manage_tournament(target_tournament) then
    raise exception 'Not authorised to edit this tournament';
  end if;
  select course_id into selected_course
  from public.tournament_rounds
  where tournament_id = target_tournament
  order by round_number
  limit 1;
  if selected_course is null then
    raise exception 'Tournament has no course';
  end if;
  update public.tournament_rounds
  set course_id = selected_course
  where tournament_id = target_tournament;
end;
$$;

revoke all on function public.use_one_tournament_course(uuid) from public;
grant execute on function public.use_one_tournament_course(uuid) to authenticated;

notify pgrst, 'reload schema';
