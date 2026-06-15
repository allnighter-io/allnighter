// @ds-adherence-ignore -- Council window chrome + sidebar. Window globals.
const R = window.React;

(function () {
  if (document.getElementById('al-kit-css')) return;
  const s = document.createElement('style'); s.id = 'al-kit-css';
  s.textContent = `
  .alk-win{display:flex;flex-direction:column;width:100%;height:100%;background:var(--bg-base);
    border:1px solid var(--border-default);border-radius:var(--radius-window);overflow:hidden;
    box-shadow:var(--shadow-xl);font-family:var(--font-sans)}
  .alk-title{height:44px;flex:none;display:flex;align-items:center;gap:12px;padding:0 14px;
    background:var(--bg-surface);border-bottom:1px solid var(--border-subtle)}
  .alk-lights{display:flex;gap:8px;flex:none}
  .alk-lights i{width:12px;height:12px;border-radius:50%;display:block}
  .alk-titlecenter{flex:1;display:flex;flex-wrap:nowrap;align-items:center;justify-content:center;gap:8px}
  .alk-titlecenter .nm,.alk-titlecenter .sub{white-space:nowrap}
  .alk-titlecenter .nm{font-size:var(--text-label);font-weight:600;color:var(--text-secondary)}
  .alk-titlecenter .sub{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .alk-titleright{display:flex;align-items:center;gap:6px;flex:none}
  .alk-body{flex:1;display:flex;min-height:0}
  .alk-side{width:264px;flex:none;background:var(--bg-subtle);border-right:1px solid var(--border-subtle);
    display:flex;flex-direction:column;overflow:auto}
  .alk-side__sec{padding:16px 14px 8px}
  .alk-side__h{display:flex;align-items:center;justify-content:space-between;margin-bottom:10px}
  .alk-side__t{font-size:var(--text-caption);font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--text-faint)}
  .alk-side__list{display:flex;flex-direction:column;gap:6px}
  .alk-divider{height:1px;background:var(--border-subtle);margin:8px 0}
  .alk-synth{display:flex;align-items:center;gap:10px;padding:9px 10px;border-radius:var(--radius-md);
    background:var(--bg-raised);border:1px solid var(--border-subtle);cursor:pointer}
  .alk-synth .lbl{flex:1;font-size:var(--text-body);font-weight:600;color:var(--text-primary)}
  .alk-synth .tag{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--accent-text)}
  .alk-hist{display:flex;align-items:center;gap:9px;padding:7px 8px;border-radius:var(--radius-sm);cursor:pointer}
  .alk-hist:hover{background:var(--bg-hover)}
  .alk-hist .dot{width:6px;height:6px;border-radius:50%;flex:none}
  .alk-hist .h-main{flex:1;min-width:0}
  .alk-hist .h-t{font-size:var(--text-label);color:var(--text-secondary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .alk-hist .h-m{font-family:var(--font-mono);font-size:9px;color:var(--text-faint)}
  .alk-main{flex:1;min-width:0;display:flex;flex-direction:column;background:var(--bg-base);overflow:auto}
  /* live mark */
  .al-livemark .cur{fill:#FFE9C6}
  .al-livemark.run .cur{animation:al-curblink 1.05s steps(1,end) infinite}
  @keyframes al-curblink{0%,52%{opacity:1}53%,100%{opacity:0}}`;
  document.head.appendChild(s);
})();

const LIVE_SVG = `
  <defs>
    <linearGradient id="lmcg" x1="20" y1="24" x2="66" y2="80" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFD79E"/><stop offset=".5" stop-color="#FFA630"/><stop offset="1" stop-color="#F0901C"/></linearGradient>
    <mask id="lmcm"><rect width="100" height="100" fill="black"/>
      <circle cx="47" cy="50" r="32" fill="white"/><circle cx="62" cy="41" r="28" fill="black"/></mask>
  </defs>
  <rect width="100" height="100" fill="url(#lmcg)" mask="url(#lmcm)"/>
  <rect class="cur" x="60" y="43" width="10.5" height="17" rx="2.6"/>`;

window.LiveMark = function LiveMark({ size = 20, run = false }) {
  return R.createElement('svg', {
    className: 'al-livemark' + (run ? ' run' : ''), width: size, height: size, viewBox: '0 0 100 100',
    dangerouslySetInnerHTML: { __html: LIVE_SVG },
  });
};

window.WindowChrome = function WindowChrome({ healthy = 6, total = 6, children }) {
  const { IconButton, Icon, Badge, LiveMark } = window;
  return R.createElement('div', { className: 'alk-win' },
    R.createElement('div', { className: 'alk-title' },
      R.createElement('div', { className: 'alk-lights' },
        R.createElement('i', { style: { background: '#FF5F57' } }),
        R.createElement('i', { style: { background: '#FEBC2E' } }),
        R.createElement('i', { style: { background: '#28C840' } })),
      R.createElement('div', { className: 'alk-titlecenter' },
        R.createElement(LiveMark, { size: 16 }),
        R.createElement('span', { className: 'nm' }, 'allnighter'),
        R.createElement('span', { className: 'sub' }, '· council')),
      R.createElement('div', { className: 'alk-titleright' },
        R.createElement(Badge, { tone: 'positive', dot: true }, healthy + '/' + total + ' healthy'),
        R.createElement(IconButton, { variant: 'ghost', size: 'sm', label: 'History' }, R.createElement(Icon, { name: 'history' })),
        R.createElement(IconButton, { variant: 'ghost', size: 'sm', label: 'Settings' }, R.createElement(Icon, { name: 'settings-2' })))),
    R.createElement('div', { className: 'alk-body' }, children));
};

window.Sidebar = function Sidebar({ selected, onToggle, disabled }) {
  const { WorkerChip, Icon, Glyph } = window;
  const workers = window.AL_WORKERS;
  return R.createElement('aside', { className: 'alk-side' },
    R.createElement('div', { className: 'alk-side__sec' },
      R.createElement('div', { className: 'alk-side__h' },
        R.createElement('span', { className: 'alk-side__t' }, 'Panel'),
        R.createElement('span', { style: { fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--text-faint)', whiteSpace: 'nowrap' } }, selected.size + ' of ' + workers.length)),
      R.createElement('div', { className: 'alk-side__list' },
        workers.map((w) => R.createElement(WorkerChip, {
          key: w.id, name: w.name, model: w.model, selectable: !disabled, selected: selected.has(w.id),
          onToggle: () => onToggle(w.id), glyph: R.createElement(Glyph, { worker: w }),
        })))),
    R.createElement('div', { className: 'alk-side__sec' },
      R.createElement('div', { className: 'alk-side__t', style: { marginBottom: 10 } }, 'Synthesizer'),
      R.createElement('div', { className: 'alk-synth' },
        R.createElement(Glyph, { worker: workers[0] }),
        R.createElement('span', { className: 'lbl' }, 'Opus 4.8'),
        R.createElement('span', { className: 'tag' }, 'master'),
        R.createElement(Icon, { name: 'chevron-down', size: 15, style: { color: 'var(--text-faint)' } }))),
    R.createElement('div', { className: 'alk-side__sec', style: { marginTop: 'auto' } },
      R.createElement('div', { className: 'alk-side__t', style: { marginBottom: 8 } }, 'Recent'),
      [['premium dashboard directions', '03:12 · 6 done', 'var(--green-500)'],
       ['rename the onboarding steps', '01:40 · 5 done', 'var(--green-500)'],
       ['api error copy rewrite', 'yesterday · 4 done', 'var(--yellow-500)']].map((h, i) =>
        R.createElement('div', { className: 'alk-hist', key: i },
          R.createElement('span', { className: 'dot', style: { background: h[2] } }),
          R.createElement('span', { className: 'h-main' },
            R.createElement('div', { className: 'h-t' }, h[0]),
            R.createElement('div', { className: 'h-m' }, h[1]))))));
};
