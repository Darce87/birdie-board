-- Birdie Board: organiser corrections and round lock audit.
-- Run once in Supabase SQL Editor.

create table if not exists public.live_round_score_audit (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.tournament_rounds(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  hole_number smallint not null check (hole_number between 1 and 18),
  previous_gross_score smallint,
  new_gross_score smallint not null check (new_gross_score between 1 and 20),
  reason text not null check (char_length(trim(reason)) between 3 and 250),
  corrected_by uuid not null references auth.users(id),
  corrected_at timestamptz not null default now()
);

alter table public.live_round_score_audit enable row level security;

drop policy if exists "Tournament managers can view live score audit" on public.live_round_score_audit;
create policy "Tournament managers can view live score audit"
on public.live_round_score_audit for select to authenticated
using (
  exists (
    select 1
    from public.tournament_rounds r
    where r.id = round_id
      and public.can_manage_tournament(r.tournament_id)
  )
);

create or replace function public.correct_live_round_score(
  target_round uuid,
  target_player uuid,
  target_hole integer,
  replacement_gross integer,
  correction_reason text
)
returns void language plpgsql security definer set search_path = public
as $$
declare
  event_id uuid;
  previous_score smallint;
begin
  select tournament_id into event_id
  from public.tournament_rounds
  where id = target_round;

  if event_id is null or not public.can_manage_tournament(event_id) then
    raise exception 'Not authorised to correct this round';
  end if;
  if (select status from public.tournament_rounds where id = target_round) <> 'live' then
    raise exception 'Only a live round can be corrected';
  end if;
  if target_hole not between 1 and 18 or replacement_gross not between 1 and 20 then
    raise exception 'Invalid score';
  end if;
  if char_length(trim(correction_reason)) not between 3 and 250 then
    raise exception 'Enter a correction reason of 3 to 250 characters';
  end if;
  if not exists (
    select 1 from public.tournament_members
    where tournament_id = event_id and user_id = target_player
  ) then
    raise exception 'That player is not in this tournament';
  end if;

  select gross_score into previous_score
  from public.live_round_hole_scores
  where round_id = target_round and player_id = target_player and hole_number = target_hole;

  if previous_score is not null and previous_score = replacement_gross then
    raise exception 'The replacement score is unchanged';
  end if;

  insert into public.live_round_hole_scores
    (round_id, player_id, hole_number, gross_score, updated_by)
  values
    (target_round, target_player, target_hole, replacement_gross, auth.uid())
  on conflict on constraint live_round_hole_scores_pkey do update
    set gross_score = excluded.gross_score,
        updated_by = excluded.updated_by,
        updated_at = now();

  insert into public.live_round_score_audit
    (round_id, player_id, hole_number, previous_gross_score, new_gross_score, reason, corrected_by)
  values
    (target_round, target_player, target_hole, previous_score, replacement_gross, trim(correction_reason), auth.uid());
end;
$$;

revoke all on function public.correct_live_round_score(uuid,uuid,integer,integer,text) from public;
grant execute on function public.correct_live_round_score(uuid,uuid,integer,integer,text) to authenticated;

notify pgrst, 'reload schema';
