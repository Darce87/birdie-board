(() => {
  const URL = 'https://otqkceoknzzqnpfgvldh.supabase.co';
  const KEY = 'sb_publishable_jmzzq_RyGyqBqOua7wFe2g_bCKVm2dc';
  let client, busy = false;
  const esc = value => String(value ?? '').replace(/[&<>'"]/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[char]));
  const route = () => history.state?.view === 'liveRound' ? history.state.data : null;

  async function getClient() {
    if (client) return client;
    const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2');
    client = createClient(URL, KEY);
    return client;
  }

  async function mountReview() {
    const active = route();
    if (!active || !document.querySelector('#bb .live-board') || document.getElementById('roundreview') || busy) return;
    busy = true;
    try {
      const supabase = await getClient();
      const [{ data: sessionData }, { data: event }] = await Promise.all([
        supabase.auth.getUser(),
        supabase.from('tournaments').select('created_by,club_id').eq('id', active.tournamentId).maybeSingle()
      ]);
      if (!event) return;
      const { data: roster } = await supabase.rpc('get_social_club_members', { target_club: event.club_id });
      const myRole = (roster || []).find(person => person.user_id === sessionData.user?.id)?.role;
      if (sessionData.user?.id !== event.created_by && !['owner', 'admin'].includes(myRole)) return;

      const [{ data: round }, { data: members }, { data: scores }, { data: audit }] = await Promise.all([
        supabase.from('tournament_rounds').select('status').eq('id', active.roundId).maybeSingle(),
        supabase.from('tournament_members').select('user_id').eq('tournament_id', active.tournamentId),
        supabase.from('live_round_hole_scores').select('player_id,hole_number,gross_score').eq('round_id', active.roundId),
        supabase.from('live_round_score_audit').select('player_id,hole_number,previous_gross_score,new_gross_score,reason,corrected_at').eq('round_id', active.roundId).order('corrected_at', { ascending: false }).limit(8)
      ]);
      if (round?.status !== 'live') return;
      const people = new Map((roster || []).map(person => [person.user_id, [person.first_name, person.last_name].filter(Boolean).join(' ') || person.display_name || 'Player']));
      const players = (members || []).map(member => ({ id: member.user_id, name: people.get(member.user_id) || 'Player' }));
      const scoreMap = new Map((scores || []).map(score => [`${score.player_id}-${score.hole_number}`, score.gross_score]));
      const playerOptions = players.map(player => `<option value="${player.id}">${esc(player.name)}</option>`).join('');
      const holeOptions = Array.from({ length: 18 }, (_, index) => `<option value="${index + 1}">Hole ${index + 1}</option>`).join('');
      const auditRows = (audit || []).map(item => `<p class="review-audit"><b>${esc(people.get(item.player_id) || 'Player')} · Hole ${item.hole_number}</b><br>${item.previous_gross_score ?? '—'} → ${item.new_gross_score} · ${esc(item.reason)}</p>`).join('') || '<p class="muted">No organiser corrections recorded.</p>';
      const panel = document.createElement('section');
      panel.id = 'roundreview';
      panel.className = 'card';
      panel.innerHTML = `<p class="kick">ORGANISER REVIEW</p><h2>Review & lock round</h2><p class="muted">Corrections are recorded with a reason. Locking prevents further score changes.</p><p id="reviewmsg" class="error"></p><form id="reviewform"><label class="field">Player<select id="reviewplayer">${playerOptions}</select></label><label class="field">Hole<select id="reviewhole">${holeOptions}</select></label><p id="recordedscore" class="note">Recorded gross: —</p><label class="field">Correct gross<input id="reviewgross" type="number" min="1" max="20" inputmode="numeric" required></label><label class="field">Reason<input id="reviewreason" minlength="3" maxlength="250" placeholder="e.g. Scorecard correction" required></label><button class="secondary" type="submit">Save correction</button></form><hr class="review-rule"><p class="kick">RECENT CORRECTIONS</p>${auditRows}<button id="lockround" class="primary auth-button">Lock round</button>`;
      document.querySelector('#bb .live-board')?.closest('.card')?.after(panel);
      const updateRecorded = () => {
        const player = document.getElementById('reviewplayer').value, hole = document.getElementById('reviewhole').value;
        const score = scoreMap.get(`${player}-${hole}`);
        document.getElementById('recordedscore').textContent = `Recorded gross: ${score ?? '—'}`;
        document.getElementById('reviewgross').value = score ?? '';
      };
      document.getElementById('reviewplayer').onchange = updateRecorded;
      document.getElementById('reviewhole').onchange = updateRecorded;
      updateRecorded();
      document.getElementById('reviewform').onsubmit = async event => {
        event.preventDefault();
        const message = document.getElementById('reviewmsg');
        message.textContent = 'Saving correction…';
        const { error } = await supabase.rpc('correct_live_round_score', {
          target_round: active.roundId,
          target_player: document.getElementById('reviewplayer').value,
          target_hole: Number(document.getElementById('reviewhole').value),
          replacement_gross: Number(document.getElementById('reviewgross').value),
          correction_reason: document.getElementById('reviewreason').value.trim()
        });
        if (error) { message.textContent = error.message; return; }
        panel.remove();
        mountReview();
      };
      document.getElementById('lockround').onclick = async () => {
        if (!confirm('Lock this round? Scorers will no longer be able to change scores.')) return;
        const { error } = await supabase.rpc('lock_live_round', { target_round: active.roundId });
        if (error) { document.getElementById('reviewmsg').textContent = error.message; return; }
        location.reload();
      };
    } finally {
      busy = false;
    }
  }

  const style = document.createElement('style');
  style.textContent = '#bb #roundreview .secondary{width:100%;margin-top:8px}#bb .review-rule{border:0;border-top:1px solid #3b9378;margin:20px 0}#bb .review-audit{padding:8px 0;border-bottom:1px solid #3b9378;color:#cde3db;font-size:11px;line-height:1.45}';
  document.head.appendChild(style);
  new MutationObserver(mountReview).observe(document.body, { childList: true, subtree: true });
  mountReview();
})();
