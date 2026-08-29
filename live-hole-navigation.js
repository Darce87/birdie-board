(() => {
  const keyFor = roundId => `birdieBoardCompletedHoles-${roundId}`;
  const pendingKeyFor = roundId => `birdieBoardPendingHole-${roundId}`;
  const liveRoute = () => history.state?.view === 'liveRound' ? history.state.data : null;

  const renderHoleProgress = () => {
    const picker = document.getElementById('livehole');
    const route = liveRoute();
    if (!picker || !route || document.getElementById('holeprogress')) return;

    const pending = Number(sessionStorage.getItem(pendingKeyFor(route.roundId)));
    const completed = new Set(JSON.parse(sessionStorage.getItem(keyFor(route.roundId)) || '[]'));
    // The score-entry page only re-renders after a successful save.
    if (Number.isInteger(pending) && pending >= 1 && pending <= 18) {
      completed.add(pending);
      sessionStorage.setItem(keyFor(route.roundId), JSON.stringify([...completed]));
      sessionStorage.removeItem(pendingKeyFor(route.roundId));
    }

    const navigation = document.createElement('section');
    navigation.id = 'holeprogress';
    navigation.innerHTML = `<p class="hole-progress-label">Hole progress</p><div class="hole-progress">${[...picker.options].map(option => {
      const hole = Number(option.value), done = completed.has(hole), current = hole === Number(picker.value);
      return `<button type="button" class="${done ? 'done' : ''} ${current ? 'current' : ''}" data-live-hole="${hole}" aria-label="${done ? 'Recorded' : 'Select'} hole ${hole}">${hole}</button>`;
    }).join('')}</div>`;
    picker.closest('.field')?.before(navigation);
    picker.closest('.field').style.display = 'none';

    navigation.querySelectorAll('[data-live-hole]').forEach(button => {
      button.addEventListener('click', () => {
        picker.value = button.dataset.liveHole;
        picker.dispatchEvent(new Event('change', { bubbles: true }));
        navigation.remove();
        renderHoleProgress();
      });
    });
  };

  document.addEventListener('click', event => {
    if (!event.target.closest('#savelivescores')) return;
    const route = liveRoute(), picker = document.getElementById('livehole');
    if (route && picker) sessionStorage.setItem(pendingKeyFor(route.roundId), picker.value);
  }, true);

  document.addEventListener('change', event => {
    if (event.target.id !== 'livehole') return;
    document.getElementById('holeprogress')?.remove();
    renderHoleProgress();
  });

  new MutationObserver(renderHoleProgress).observe(document.body, { childList: true, subtree: true });
  const style = document.createElement('style');
  style.textContent = `#bb .hole-progress-label{margin:15px 0 8px;color:#cde3db;font:500 10px DM Mono;letter-spacing:1px;text-transform:uppercase}#bb .hole-progress{display:grid;grid-template-columns:repeat(9,1fr);gap:6px}#bb .hole-progress button{height:34px;border:1px solid #3b9378;border-radius:7px;background:#006747;color:#fff;font:600 12px DM Mono;cursor:pointer}#bb .hole-progress button.current{background:#FCE300;border-color:#FCE300;color:#006747}#bb .hole-progress button.done{background:#005238;color:#8ab9aa;text-decoration:line-through}#bb .hole-progress button.done.current{background:#FCE300;color:#006747;text-decoration:none}@media(max-width:390px){#bb .hole-progress{grid-template-columns:repeat(6,1fr)}}`;
  document.head.appendChild(style);
  renderHoleProgress();
})();
