(() => {
  const applyLiveScoreLabels = () => {
    const inputs = [...document.querySelectorAll('input[data-live-score]')];
    if (!inputs.length) return;

    inputs.forEach(input => input.removeAttribute('placeholder'));
    const firstRow = inputs[0].closest('.score');
    if (firstRow && !firstRow.previousElementSibling?.classList.contains('score-column-heading')) {
      const heading = document.createElement('p');
      heading.className = 'score-column-heading';
      heading.textContent = 'Gross';
      firstRow.before(heading);
    }
  };

  new MutationObserver(applyLiveScoreLabels).observe(document.body, { childList: true, subtree: true });
  const style = document.createElement('style');
  style.textContent = '#bb .score{grid-template-columns:1fr 48px}.score-column-heading{width:48px;margin:14px 0 4px auto;text-align:center;color:#cde3db;font:500 .64rem/1.2 "DM Mono",monospace;letter-spacing:.06em;text-transform:uppercase}';
  document.head.appendChild(style);
  applyLiveScoreLabels();
})();
