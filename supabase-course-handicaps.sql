-- Birdie Board: tee data and playing-handicap support.
-- Run once in the Supabase SQL Editor.

alter table public.courses
  add column if not exists tee_name text,
  add column if not exists slope_rating integer,
  add column if not exists course_rating numeric(4,1);

alter table public.courses
  drop constraint if exists courses_slope_rating_range,
  drop constraint if exists courses_course_rating_range;

alter table public.courses
  add constraint courses_slope_rating_range
    check (slope_rating is null or slope_rating between 55 and 155),
  add constraint courses_course_rating_range
    check (course_rating is null or course_rating between 45 and 90);

create or replace function public.update_tournament_course_setup(
  target_tournament uuid,
  target_course uuid,
  new_tee_name text,
  new_slope_rating integer,
  new_course_rating numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
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
  if nullif(trim(new_tee_name), '') is null then
    raise exception 'Enter the tee being played';
  end if;
  if new_slope_rating not between 55 and 155 then
    raise exception 'Slope rating must be between 55 and 155';
  end if;
  if new_course_rating not between 45 and 90 then
    raise exception 'Course rating must be between 45.0 and 90.0';
  end if;

  update public.courses
  set tee_name = trim(new_tee_name),
      slope_rating = new_slope_rating,
      course_rating = new_course_rating
  where id = target_course;
end;
$$;

revoke all on function public.update_tournament_course_setup(uuid,uuid,text,integer,numeric) from public;
grant execute on function public.update_tournament_course_setup(uuid,uuid,text,integer,numeric) to authenticated;

notify pgrst, 'reload schema';
