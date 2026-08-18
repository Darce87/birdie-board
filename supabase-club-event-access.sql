-- Birdie Board: let social-club members open their club's events read-only.
-- Run once in the Supabase SQL Editor.

create or replace function public.can_view_club_course(target_course uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tournaments t
    where t.course_id = target_course
      and public.is_club_member(t.club_id)
  );
$$;

-- A member can view an event belonging to their club, but this does not grant
-- organiser permissions to alter it.
drop policy if exists "Club members can view their club tournaments" on public.tournaments;
create policy "Club members can view their club tournaments"
on public.tournaments
for select
to authenticated
using (public.is_club_member(club_id));

drop policy if exists "Club members can view event courses" on public.courses;
create policy "Club members can view event courses"
on public.courses
for select
to authenticated
using (public.can_view_club_course(id));

drop policy if exists "Club members can view event scorecards" on public.course_holes;
create policy "Club members can view event scorecards"
on public.course_holes
for select
to authenticated
using (public.can_view_club_course(course_id));

revoke all on function public.can_view_club_course(uuid) from public;
grant execute on function public.can_view_club_course(uuid) to authenticated;
