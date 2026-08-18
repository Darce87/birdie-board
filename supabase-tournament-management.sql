-- Birdie Board: tournament scorecard editing
-- Run this once in the Supabase SQL Editor.

create or replace function public.update_tournament_scorecard(
  target_tournament uuid,
  scorecard jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_course uuid;
  scorecard_entry jsonb;
  entry_hole integer;
  entry_par integer;
  entry_si integer;
begin
  if auth.uid() is null or not public.can_manage_tournament(target_tournament) then
    raise exception 'Not authorised to edit this tournament scorecard';
  end if;

  if (select is_finalised from public.tournaments where id = target_tournament) then
    raise exception 'Reopen the tournament before editing its scorecard';
  end if;

  if jsonb_typeof(scorecard) <> 'array' or jsonb_array_length(scorecard) <> 18 then
    raise exception 'A scorecard must contain all 18 holes';
  end if;

  if (select count(distinct (entry ->> 'hole_number')::integer) from jsonb_array_elements(scorecard) entry) <> 18
    or (select min((entry ->> 'hole_number')::integer) from jsonb_array_elements(scorecard) entry) <> 1
    or (select max((entry ->> 'hole_number')::integer) from jsonb_array_elements(scorecard) entry) <> 18
    or (select count(distinct (entry ->> 'stroke_index')::integer) from jsonb_array_elements(scorecard) entry) <> 18
    or (select min((entry ->> 'stroke_index')::integer) from jsonb_array_elements(scorecard) entry) <> 1
    or (select max((entry ->> 'stroke_index')::integer) from jsonb_array_elements(scorecard) entry) <> 18 then
    raise exception 'Use every hole number and stroke index from 1 to 18 once';
  end if;

  select course_id into target_course
  from public.tournaments
  where id = target_tournament;

  if target_course is null then
    raise exception 'Tournament course not found';
  end if;

  for scorecard_entry in select * from jsonb_array_elements(scorecard) loop
    entry_hole := (scorecard_entry ->> 'hole_number')::integer;
    entry_par := (scorecard_entry ->> 'par')::integer;
    entry_si := (scorecard_entry ->> 'stroke_index')::integer;
    if entry_par not between 3 and 6 then
      raise exception 'Each hole par must be between 3 and 6';
    end if;
    update public.course_holes
    set par = entry_par, stroke_index = entry_si
    where course_id = target_course and hole_number = entry_hole;
  end loop;
end;
$$;

revoke all on function public.update_tournament_scorecard(uuid, jsonb) from public;
grant execute on function public.update_tournament_scorecard(uuid, jsonb) to authenticated;

-- Safe, organiser-only deletion for cancelled or mistaken tournaments.
create or replace function public.delete_tournament(target_tournament uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not public.can_manage_tournament(target_tournament) then
    raise exception 'Not authorised to delete this tournament';
  end if;

  if exists (select 1 from public.hole_scores where tournament_id = target_tournament) then
    raise exception 'This event has scores recorded and cannot be deleted';
  end if;

  delete from public.tournaments where id = target_tournament;
end;
$$;

revoke all on function public.delete_tournament(uuid) from public;
grant execute on function public.delete_tournament(uuid) to authenticated;
