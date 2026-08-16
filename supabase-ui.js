(async () => {
  const SUPABASE_URL = 'https://otqkceoknzzqnpfgvldh.supabase.co';
  const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_jmzzq_RyGyqBqOua7wFe2g_bCKVm2dc';
  const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2');
  const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY);
  let currentUser = null;
  let currentTournamentId = null;
  let liveChannel = null;
  let pendingSignUp = false;
  const signUpCompleteMessage = 'Account created. Check your email to confirm it, then sign in.';

  document.title = 'Birdie Board';
  document.head.insertAdjacentHTML('beforeend', `<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@1,600;1,700&family=DM+Mono:wght@400;500&family=DM+Sans:wght@400;500;600;700&display=swap" rel="stylesheet"><style>
  #bb-root{min-height:100vh;background:#006747;color:#fff;font-family:'DM Sans',sans-serif;padding:24px 18px 90px;box-sizing:border-box}#bb-root *{box-sizing:border-box}#bb-root button,#bb-root input,#bb-root select{font:inherit}.bb-shell{max-width:650px;margin:auto}.bb-top{display:flex;justify-content:space-between;align-items:flex-start;margin-bottom:26px}.bb-logo{font:700 italic 44px/.78 'Cormorant Garamond',serif;letter-spacing:-2px}.bb-logo i{color:#FCE300}.bb-kicker{margin:0 0 7px;color:#cde3db;font:500 10px 'DM Mono';letter-spacing:1px}.bb-user{border:1px solid #78b8a5;border-radius:20px;padding:8px 11px;color:#fff;background:transparent;font-size:12px}.bb-card{background:#087957;border:1px solid #3b9378;border-radius:18px;padding:18px;margin:14px 0}.bb-card h2{font:600 24px/1 'Cormorant Garamond',serif;margin:0 0 7px;letter-spacing:-.4px}.bb-muted{color:#cde3db;font-size:12px;line-height:1.45}.bb-field{display:block;margin:13px 0;color:#fff;font-size:12px;font-weight:600}.bb-field input,.bb-field select{width:100%;margin-top:6px;height:46px;border:1px solid #3b9378;border-radius:10px;padding:0 12px;background:#006747;color:#fff}.bb-primary,.bb-secondary{border:0;border-radius:11px;min-height:48px;padding:0 15px;font-weight:700;cursor:pointer}.bb-primary{background:#FCE300;color:#006747}.bb-secondary{background:transparent;border:1px solid #78b8a5;color:#fff}.bb-primary:disabled{opacity:.55;cursor:wait}.bb-row{display:flex;gap:10px;align-items:center}.bb-row>*{flex:1}.bb-link{border:0;background:none;color:#FCE300;padding:0;font-size:12px}.bb-error{min-height:18px;color:#ffe2a9;font-size:12px;margin:10px 0}.bb-tournament{display:flex;align-items:center;justify-content:space-between;gap:13px;width:100%;padding:15px 0;border:0;border-bottom:1px solid #3b9378;background:transparent;color:#fff;text-align:left}.bb-tournament b{font-size:14px}.bb-tournament small{display:block;margin-top:4px;color:#cde3db;font-size:11px}.bb-status{color:#FCE300;font:500 10px 'DM Mono';letter-spacing:.6px;text-transform:uppercase}.bb-back{border:0;background:transparent;color:#FCE300;padding:0 0 14px;font-size:13px}.bb-scorehead{display:grid;grid-template-columns:1fr auto auto;gap:8px;padding:8px 0;color:#cde3db;font:500 10px 'DM Mono';letter-spacing:.5px}.bb-leader{display:grid;grid-template-columns:1fr 42px 42px;gap:8px;align-items:center;padding:12px 0;border-top:1px solid #3b9378;font-size:13px}.bb-leader b{font-size:16px}.bb-scorecard{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin-top:12px}.bb-hole{border:1px solid #3b9378;border-radius:10px;padding:8px;text-align:center}.bb-hole span{display:block;font:10px 'DM Mono';color:#cde3db}.bb-hole b{display:block;font:700 18px 'Cormorant Garamond',serif;margin:4px}.bb-hole input{width:37px;border:0;border-bottom:1px solid #78b8a5;background:transparent;color:#fff;text-align:center;font-weight:700}.bb-note{padding:10px 12px;background:#005238;border-radius:10px;color:#d8eee6;font-size:11px;line-height:1.45}@media(min-width:680px){#bb-root{padding-top:38px}.bb-scorecard{grid-template-columns:repeat(6,1fr)}}
  </style>`);

  const root = document.createElement('div');
  root.id = 'bb-root';
  document.body.replaceChildren(root);

  function layout(content, signedIn = false) {
    root.innerHTML = `<div class="bb-shell"><header class="bb-top"><div><button id="bb-home" class="bb-logo" type="button" aria-label="Birdie Board home" style="border:0;padding:0;background:transparent;color:#fff;cursor:pointer;text-align:left">Birdie <i>Board</i></button></div>${signedIn ? '<button id="bb-logout" class="bb-user">Sign out</button>' : ''}</header>${content}</div>`;
    document.getElementById('bb-home').addEventListener('click', () => currentUser ? loadDashboard() : showAuth());
    document.getElementById('bb-logout')?.addEventListener('click', async () => { await supabase.auth.signOut(); });
  }

  function showAuth(message = '', mode = 'signin') {
    const signUp = mode === 'signup';
    const profileFields = signUp ? `<label class="bb-field">First name<input id="bb-first-name" type="text" autocomplete="given-name" maxlength="60" required></label><label class="bb-field">Last name<input id="bb-last-name" type="text" autocomplete="family-name" maxlength="80" required></label><label class="bb-field">Exact handicap<input id="bb-handicap" type="number" min="0" max="54" step="0.1" inputmode="decimal" required></label>` : '';
    const passwordConfirmation = signUp ? `<label class="bb-field">Confirm password<input id="bb-password-confirm" type="password" autocomplete="new-password" minlength="8" required></label>` : '';
    const passwordAutocomplete = signUp ? 'new-password' : 'current-password';
    const title = signUp ? 'Create your player profile.' : 'Live golf scoring.';
    const description = signUp ? 'Register once to create tournaments, enter scores, and follow live leaderboards.' : 'Sign in to organise rounds, enter scores, and follow the leaderboard in real time.';
    const actions = signUp ? `<div class="bb-row"><button class="bb-primary" type="submit">Sign Up</button><button id="bb-back-to-signin" class="bb-secondary" type="button">Back to sign in</button></div>` : `<div class="bb-row"><button class="bb-primary" type="submit">Sign in</button><button id="bb-show-signup" class="bb-secondary" type="button">Sign Up</button></div>`;
    layout(`<section class="bb-card"><p class="bb-kicker">WELCOME TO THE CLUBHOUSE</p><h2>${title}</h2><p class="bb-muted">${description}</p><div id="bb-auth-error" class="bb-error">${escapeHtml(message)}</div><form id="bb-auth-form">${profileFields}<label class="bb-field">Email address<input id="bb-email" type="email" autocomplete="email" required></label><label class="bb-field">Password<input id="bb-password" type="password" autocomplete="${passwordAutocomplete}" minlength="8" required></label>${passwordConfirmation}${actions}</form></section>`);
    const form = document.getElementById('bb-auth-form');
    const error = document.getElementById('bb-auth-error');
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const email = document.getElementById('bb-email').value.trim();
      const password = document.getElementById('bb-password').value;
      if (!signUp) {
        error.textContent = 'Signing in…';
        const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
        error.textContent = signInError ? signInError.message : '';
        return;
      }
      const firstName = document.getElementById('bb-first-name').value.trim();
      const lastName = document.getElementById('bb-last-name').value.trim();
      const handicap = Number(document.getElementById('bb-handicap').value);
      const passwordConfirmationValue = document.getElementById('bb-password-confirm').value;
      if (!Number.isFinite(handicap) || handicap < 0 || handicap > 54) { error.textContent = 'Enter an exact handicap between 0 and 54.'; return; }
      if (password !== passwordConfirmationValue) { error.textContent = 'Your passwords do not match.'; return; }
      pendingSignUp = true;
      error.textContent = 'Creating your account…';
      const { error: signUpError } = await supabase.auth.signUp({ email, password, options: { data: { first_name: firstName, last_name: lastName, handicap: String(handicap), display_name: `${firstName} ${lastName}` }, emailRedirectTo: 'https://darce87.github.io/birdie-board/' } });
      if (signUpError) { pendingSignUp = false; error.textContent = signUpError.message; return; }
      await supabase.auth.signOut();
      if (pendingSignUp) { pendingSignUp = false; currentUser = null; showAuth(signUpCompleteMessage); }
    });
    if (signUp) document.getElementById('bb-back-to-signin').addEventListener('click', () => showAuth());
    else document.getElementById('bb-show-signup').addEventListener('click', () => showAuth('', 'signup'));
  }

  function showProfileSetup(profile = {}) {
    profile = profile || {};
    layout(`<section class="bb-card"><p class="bb-kicker">YOUR PLAYER PROFILE</p><h2>Let’s get your details right.</h2><p class="bb-muted">Your name and exact handicap are used when you enter and score tournaments.</p><div id="bb-profile-error" class="bb-error"></div><form id="bb-profile-form"><label class="bb-field">First name<input id="bb-profile-first" type="text" required maxlength="60" value="${escapeHtml(profile.first_name || '')}"></label><label class="bb-field">Last name<input id="bb-profile-last" type="text" required maxlength="80" value="${escapeHtml(profile.last_name || '')}"></label><label class="bb-field">Exact handicap<input id="bb-profile-handicap" type="number" min="0" max="54" step="0.1" required value="${profile.handicap ?? ''}"></label><button class="bb-primary" type="submit">Save profile</button></form></section>`, true);
    document.getElementById('bb-profile-form').addEventListener('submit', async event => { event.preventDefault(); const error = document.getElementById('bb-profile-error'); const firstName = document.getElementById('bb-profile-first').value.trim(); const lastName = document.getElementById('bb-profile-last').value.trim(); const handicap = Number(document.getElementById('bb-profile-handicap').value); if (!firstName || !lastName || !Number.isFinite(handicap) || handicap < 0 || handicap > 54) { error.textContent = 'Enter a valid name and handicap.'; return; } const { error: updateError } = await supabase.from('profiles').upsert({ id: currentUser.id, first_name: firstName, last_name: lastName, display_name: `${firstName} ${lastName}`, handicap }, { onConflict: 'id' }); error.textContent = updateError ? updateError.message : ''; if (!updateError) loadDashboard(); });
  }

  async function loadDashboard() {
    const { data: profile } = await supabase.from('profiles').select('display_name,first_name,last_name,handicap').eq('id', currentUser.id).maybeSingle();
    if (!profile?.first_name || !profile?.last_name || profile.handicap === null) { showProfileSetup(profile); return; }
    const { data: memberships, error } = await supabase.from('tournament_members').select('role, tournament_id, tournaments(id,name,status,starts_at,courses(name))').eq('user_id', currentUser.id).order('joined_at', { ascending: false });
    if (error) { layout(`<p class="bb-error">${error.message}</p>`, true); return; }
    const cards = (memberships || []).map(({ role, tournaments }) => tournaments ? `<button class="bb-tournament" data-open-tournament="${tournaments.id}"><span><b>${escapeHtml(tournaments.name)}</b><small>${escapeHtml(tournaments.courses?.name || 'Course pending')} · ${tournaments.starts_at ? new Date(tournaments.starts_at).toLocaleDateString() : 'Date pending'}</small></span><span class="bb-status">${escapeHtml(tournaments.status)}</span></button>` : '').join('') || '<p class="bb-muted">No tournaments yet. Create your first live round.</p>';
    layout(`<section class="bb-card"><p class="bb-kicker">WELCOME BACK</p><h2>${escapeHtml(profile.first_name)}</h2><p class="bb-muted">Your private tournaments and live scoreboards.</p><button id="bb-create" class="bb-primary">Create tournament</button></section><section class="bb-card"><p class="bb-kicker">MY TOURNAMENTS</p>${cards}</section>`, true);
    document.getElementById('bb-create').addEventListener('click', showCreateTournament);
    document.querySelectorAll('[data-open-tournament]').forEach(button => button.addEventListener('click', () => openTournament(button.dataset.openTournament)));
  }

  function showCreateTournament() {
    layout(`<button id="bb-back" class="bb-back">← Back to tournaments</button><section class="bb-card"><p class="bb-kicker">NEW TOURNAMENT</p><h2>Start a live round</h2><p class="bb-muted">A standard 18-hole scorecard is created. You can replace its par and stroke-index details during course setup next.</p><div id="bb-create-error" class="bb-error"></div><form id="bb-create-form"><label class="bb-field">Tournament name<input id="bb-tournament-name" required maxlength="120" placeholder="Saturday Stableford"></label><label class="bb-field">Course name<input id="bb-course-name" required maxlength="120" placeholder="Riverside Country Club"></label><label class="bb-field">Start date<input id="bb-start-date" type="datetime-local"></label><button class="bb-primary" type="submit">Create tournament</button></form></section>`, true);
    document.getElementById('bb-back').onclick = loadDashboard;
    document.getElementById('bb-create-form').addEventListener('submit', createTournament);
  }

  async function createTournament(event) {
    event.preventDefault();
    const error = document.getElementById('bb-create-error');
    error.textContent = 'Creating your secure tournament…';
    const courseName = document.getElementById('bb-course-name').value.trim();
    const tournamentName = document.getElementById('bb-tournament-name').value.trim();
    const startDate = document.getElementById('bb-start-date').value || null;
    const { data: course, error: courseError } = await supabase.from('courses').insert({ name: courseName, created_by: currentUser.id }).select().single();
    if (courseError) { error.textContent = courseError.message; return; }
    const holes = Array.from({ length: 18 }, (_, index) => ({ course_id: course.id, hole_number: index + 1, par: 4, stroke_index: index + 1 }));
    const { error: holesError } = await supabase.from('course_holes').insert(holes);
    if (holesError) { error.textContent = holesError.message; return; }
    const { data: tournament, error: tournamentError } = await supabase.from('tournaments').insert({ name: tournamentName, course_id: course.id, created_by: currentUser.id, starts_at: startDate, status: 'live' }).select().single();
    if (tournamentError) { error.textContent = tournamentError.message; return; }
    currentTournamentId = tournament.id;
    openTournament(tournament.id);
  }

  async function openTournament(tournamentId) {
    currentTournamentId = tournamentId;
    if (liveChannel) await supabase.removeChannel(liveChannel);
    const { data: tournament, error: tournamentError } = await supabase.from('tournaments').select('id,name,status,starts_at,courses(id,name)').eq('id', tournamentId).single();
    const { data: members, error: membersError } = await supabase.from('tournament_members').select('user_id,role,playing_handicap,profiles(display_name)').eq('tournament_id', tournamentId);
    const { data: scores, error: scoresError } = await supabase.from('hole_scores').select('player_id,hole_number,gross_score').eq('tournament_id', tournamentId);
    const { data: holes } = await supabase.from('course_holes').select('hole_number,par,stroke_index').eq('course_id', tournament?.courses?.id).order('hole_number');
    if (tournamentError || membersError || scoresError) { layout(`<p class="bb-error">${tournamentError?.message || membersError?.message || scoresError?.message}</p>`, true); return; }
    const scoreMap = new Map((scores || []).map(score => [`${score.player_id}-${score.hole_number}`, score.gross_score]));
    const leaderboard = (members || []).map(member => {
      const handicap = Number(member.playing_handicap || 0); let points = 0; let through = 0;
      (holes || []).forEach(hole => { const gross = scoreMap.get(`${member.user_id}-${hole.hole_number}`); if (gross) { through++; const strokes = Math.floor(handicap / 18) + (hole.stroke_index <= handicap % 18 ? 1 : 0); points += Math.max(0, hole.par - (gross - strokes) + 2); } });
      return { ...member, points, through };
    }).sort((a, b) => b.points - a.points);
    const myMember = (members || []).find(member => member.user_id === currentUser.id);
    const canScore = myMember?.role === 'player' || myMember?.role === 'organizer' || myMember?.role === 'scorer';
    const scorecard = canScore ? `<section class="bb-card"><p class="bb-kicker">SCORE ENTRY</p><h2>Your scorecard</h2><p class="bb-muted">Enter gross strokes. Stableford points update live for everyone in the tournament.</p><div class="bb-scorecard">${(holes || []).map(hole => `<label class="bb-hole"><span>H${hole.hole_number} · P${hole.par} · SI${hole.stroke_index}</span><b>${scoreMap.get(`${currentUser.id}-${hole.hole_number}`) || '—'}</b><input data-hole="${hole.hole_number}" type="number" min="1" max="20" value="${scoreMap.get(`${currentUser.id}-${hole.hole_number}`) || ''}" aria-label="Hole ${hole.hole_number} gross score"></label>`).join('')}</div><button id="bb-save-scores" class="bb-primary" style="margin-top:16px">Save scores</button></section>` : '';
    layout(`<button id="bb-back" class="bb-back">← All tournaments</button><section class="bb-card"><p class="bb-kicker">${escapeHtml(tournament.status)} TOURNAMENT</p><h2>${escapeHtml(tournament.name)}</h2><p class="bb-muted">${escapeHtml(tournament.courses?.name || '')} · Stableford</p><div class="bb-note">Only people added to this tournament can access its live scores. Score changes are recorded in the audit log.</div></section><section class="bb-card"><p class="bb-kicker">LIVE LEADERBOARD</p><div class="bb-scorehead"><span>PLAYER</span><span>PTS</span><span>THRU</span></div>${leaderboard.map((member, index) => `<div class="bb-leader"><span>${index + 1}. <b>${escapeHtml(member.profiles?.display_name || 'Player')}</b></span><b>${member.points}</b><span>${member.through}/18</span></div>`).join('') || '<p class="bb-muted">No competitors yet.</p>'}</section>${scorecard}`, true);
    document.getElementById('bb-back').onclick = loadDashboard;
    document.getElementById('bb-save-scores')?.addEventListener('click', async () => {
      const button = document.getElementById('bb-save-scores'); button.disabled = true; button.textContent = 'Saving…';
      const payload = [...document.querySelectorAll('[data-hole]')].filter(input => input.value).map(input => ({ tournament_id: tournamentId, player_id: currentUser.id, hole_number: Number(input.dataset.hole), gross_score: Number(input.value), updated_by: currentUser.id }));
      const { error } = await supabase.from('hole_scores').upsert(payload, { onConflict: 'tournament_id,player_id,hole_number' });
      if (error) { button.textContent = error.message; button.disabled = false; return; }
      openTournament(tournamentId);
    });
    liveChannel = supabase.channel(`tournament-${tournamentId}`).on('postgres_changes', { event: '*', schema: 'public', table: 'hole_scores', filter: `tournament_id=eq.${tournamentId}` }, () => openTournament(tournamentId)).subscribe();
  }

  function escapeHtml(value) { return String(value ?? '').replace(/[&<>'"]/g, char => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', "'":'&#39;', '"':'&quot;' }[char])); }
  showAuth();
  try {
    const { data: { session } } = await supabase.auth.getSession();
    currentUser = session?.user || null;
    if (currentUser) await loadDashboard();
  } catch (error) {
    console.error('Birdie Board session recovery error:', error);
    showAuth('Your saved session could not be restored. Please sign in again.');
  }
  supabase.auth.onAuthStateChange((_event, sessionChange) => {
    if (pendingSignUp) {
      if (sessionChange?.user) { void supabase.auth.signOut(); return; }
      pendingSignUp = false;
      currentUser = null;
      showAuth(signUpCompleteMessage);
      return;
    }
    currentUser = sessionChange?.user || null;
    if (liveChannel && !currentUser) { supabase.removeChannel(liveChannel); liveChannel = null; }
    if (currentUser) { loadDashboard().catch(error => showAuth(error.message)); } else { showAuth(); }
  });
})().catch(error => {
  console.error('Birdie Board startup error:', error);
  document.body.innerHTML = `<main style="min-height:100vh;background:#006747;color:#fff;padding:32px 22px;font-family:Arial,sans-serif"><h1 style="font-size:28px">Birdie Board</h1><p>We could not start the app. Please refresh and try again.</p><p style="color:#d8eee6;font-size:13px">${String(error.message || error)}</p></main>`;
});
