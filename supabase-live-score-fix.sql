-- Run this once in Supabase SQL Editor to replace the live-score save function.
-- It fixes the "column reference player_id is ambiguous" error.

create or replace function public.save_live_round_scores(target_round uuid, entries jsonb)
returns void language plpgsql security definer set search_path = public
as $$
declare
  event_id uuid;
  entry jsonb;
  v_player_id uuid;
  v_hole integer;
  v_gross integer;
begin
  select tournament_id into event_id
  from public.tournament_rounds
  where id = target_round;

  if event_id is null
     or (select status from public.tournament_rounds where id = target_round) <> 'live' then
    raise exception 'This round is not open for scoring';
  end if;

  for entry in select value from jsonb_array_elements(entries) loop
    v_player_id := (entry->>'player_id')::uuid;
    v_hole := (entry->>'hole_number')::integer;
    v_gross := (entry->>'gross_score')::integer;

    if v_hole not between 1 and 18 or v_gross not between 1 and 20 then
      raise exception 'Invalid score';
    end if;

    if not public.can_manage_tournament(event_id) and not exists (
      select 1
      from public.live_round_groups g
      join public.live_round_group_members gm on gm.group_id = g.id
      where g.round_id = target_round
        and g.scorer_id = auth.uid()
        and gm.user_id = v_player_id
    ) then
      raise exception 'You can only score your own group';
    end if;

    insert into public.live_round_hole_scores
      (round_id, player_id, hole_number, gross_score, updated_by)
    values
      (target_round, v_player_id, v_hole, v_gross, auth.uid())
    on conflict on constraint live_round_hole_scores_pkey do update
      set gross_score = excluded.gross_score,
          updated_by = excluded.updated_by,
          updated_at = now();
  end loop;
end;
$$;
