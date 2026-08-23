(() => {
  const applyLiveScoreLabels = () => {
    const inputs = [...document.querySelectorAll('input[data-live-score]')];
    if (!inputs.length) return;

    inputs.forEach(input => input.removeAttribute('placeholder'));
    const firstRow = inputs[0].closest('.score');
    if (firstRow && !firstRow.previousElementSibling?.classList.contains('score-column-heading')) {
      const heading = document.createElement('p');
      heading.className = 'score-column-heading';
      heading.textContent = 'Gross strokes';
      firstRow.before(heading);
    }
  };

  new MutationObserver(applyLiveScoreLabels).observe(document.body, { childList: true, subtree: true });
  const style = document.createElement('style');
  style.textContent = '.score-column-heading{margin:18px 0 7px;text-align:right;color:#FCE300;font:700 .78rem/1.2 "DM Mono",monospace;letter-spacing:.09em;text-transform:uppercase}';
  document.head.appendChild(style);
  applyLiveScoreLabels();
})();
