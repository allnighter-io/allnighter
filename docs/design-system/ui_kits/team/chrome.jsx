// @ds-adherence-ignore -- Team command-center chrome. Window globals.
const R = window.React;

(function () {
  if (document.getElementById('team-cc-css')) return;
  const s = document.createElement('style'); s.id = 'team-cc-css';
  s.textContent = `
  .tcc-win{display:flex;flex-direction:column;width:100%;height:100%;background:var(--bg-base);border:1px solid var(--border-default);
    border-radius:var(--radius-window);overflow:hidden;box-shadow:var(--shadow-xl);font-family:var(--font-sans)}
  .tcc-title{height:44px;flex:none;display:flex;align-items:center;gap:12px;padding:0 14px;background:var(--bg-surface);border-bottom:1px solid var(--border-subtle)}
  .tcc-lights{display:flex;gap:8px;flex:none}.tcc-lights i{width:12px;height:12px;border-radius:50%;display:block}
  .tcc-center{flex:1;display:flex;align-items:center;justify-content:center;gap:8px}
  .tcc-center .nm{font-size:var(--text-label);font-weight:600;color:var(--text-secondary)}
  .tcc-center .sub{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .tcc-right{display:flex;align-items:center;gap:6px;flex:none}
  .tcc-ready{border:none;background:transparent;padding:0;cursor:pointer;border-radius:var(--radius-xs)}
  .tcc-ready:focus-visible{outline:none;box-shadow:var(--focus-ring)}
  .tcc-body{flex:1;min-height:0;display:flex}
  .tcc-nav{width:228px;flex:none;background:var(--bg-subtle);border-right:1px solid var(--border-subtle);display:flex;flex-direction:column;overflow:auto}
  .tcc-nav__top{padding:14px 12px 10px;border-bottom:1px solid var(--border-subtle)}
  .tcc-nav__k{font-size:10px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--accent-text);margin-bottom:8px}
  .tcc-nav__t{font-size:14px;font-weight:650;color:var(--text-primary);line-height:1.35}
  .tcc-nav__m{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-top:5px}
  .tcc-nav__list{display:flex;flex-direction:column;gap:4px;padding:10px}
  .tcc-navitem{display:flex;align-items:center;gap:9px;width:100%;height:34px;padding:0 9px;border:none;border-radius:var(--radius-sm);
    background:transparent;color:var(--text-secondary);font-family:var(--font-sans);font-size:13px;font-weight:600;text-align:left;cursor:pointer;transition:var(--transition-control)}
  .tcc-navitem:hover{background:var(--bg-hover);color:var(--text-primary)}
  .tcc-navitem.is-on{background:var(--bg-active);color:var(--text-primary)}
  .tcc-navitem .ic{width:20px;height:20px;display:flex;align-items:center;justify-content:center;color:var(--text-faint);flex:none}
  .tcc-navitem.is-on .ic{color:var(--accent-text)}
  .tcc-navitem .ct{margin-left:auto;font-family:var(--font-mono);font-size:10px;color:var(--text-faint)}
  .tcc-main{flex:1;min-width:0;background:var(--bg-base);overflow:auto}
  .tcc-foot{margin-top:auto;padding:12px 14px;border-top:1px solid var(--border-subtle);font-size:11px;line-height:1.5;color:var(--text-muted)}
  .al-livemark .cur{fill:#FFE9C6}.al-livemark.run .cur{animation:tcc-blink 1.05s steps(1,end) infinite}
  @keyframes tcc-blink{0%,52%{opacity:1}53%,100%{opacity:0}}`;
  document.head.appendChild(s);
})();

window.TeamLive = function TeamLive({ size = 18, run }) {
  return R.createElement('svg', { className: 'al-livemark' + (run ? ' run' : ''), width: size, height: size, viewBox: '0 0 100 100',
    dangerouslySetInnerHTML: { __html:
      `<defs><linearGradient id="tlm" x1="20" y1="24" x2="66" y2="80" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFD79E"/><stop offset=".5" stop-color="#FFA630"/><stop offset="1" stop-color="#F0901C"/></linearGradient><mask id="tcm"><rect width="100" height="100" fill="black"/><circle cx="47" cy="50" r="32" fill="white"/><circle cx="62" cy="41" r="28" fill="black"/></mask></defs><rect width="100" height="100" fill="url(#tlm)" mask="url(#tcm)"/>` +
      (run ? '<rect class="cur" x="60" y="43" width="10.5" height="17" rx="2.6" fill="#FFE9C6"/>' : '') } });
};

window.TeamChrome = function TeamChrome({ active, onNav, healthy = 5, total = 5, children }) {
  const { IconButton, Icon, Badge } = window;
  const nav = [
    ['ready', 'Ready', 'activity', `${healthy}/${total}`],
    ['build', 'Build bench', 'terminal', '5'],
    ['design', 'Design bench', 'sparkles', '4'],
    ['copy', 'Copy bench', 'file-text', '4'],
    ['skills', 'Skills', 'list', '12'],
  ];
  return R.createElement('div', { className: 'tcc-win' },
    R.createElement('div', { className: 'tcc-title' },
      R.createElement('div', { className: 'tcc-lights' },
        R.createElement('i', { style: { background: '#FF5F57' } }),
        R.createElement('i', { style: { background: '#FEBC2E' } }),
        R.createElement('i', { style: { background: '#28C840' } })),
      R.createElement('div', { className: 'tcc-center' },
        R.createElement(window.TeamLive, { size: 16 }),
        R.createElement('span', { className: 'nm' }, 'allnighter'),
        R.createElement('span', { className: 'sub' }, '· team')),
      R.createElement('div', { className: 'tcc-right' },
        R.createElement('button', { className: 'tcc-ready', onClick: () => onNav('ready'), 'aria-label': 'Open Team readiness' },
          R.createElement(Badge, { tone: 'positive', dot: true, mono: true }, healthy + '/' + total + ' healthy')),
        R.createElement(IconButton, { variant: 'ghost', size: 'sm', label: 'History' }, R.createElement(Icon, { name: 'history' })),
        R.createElement(IconButton, { variant: 'ghost', size: 'sm', label: 'Settings' }, R.createElement(Icon, { name: 'settings-2' })))),
    R.createElement('div', { className: 'tcc-body' },
      R.createElement('aside', { className: 'tcc-nav' },
        R.createElement('div', { className: 'tcc-nav__top' },
          R.createElement('div', { className: 'tcc-nav__k' }, 'Team'),
          R.createElement('div', { className: 'tcc-nav__t' }, 'Ready bench'),
          R.createElement('div', { className: 'tcc-nav__m' }, '5 sources · 8 models')),
        R.createElement('div', { className: 'tcc-nav__list' },
          nav.map(([id, label, ic, count]) => R.createElement('button', { key: id, className: 'tcc-navitem' + (active === id ? ' is-on' : ''), onClick: () => onNav(id) },
            R.createElement('span', { className: 'ic' }, R.createElement(Icon, { name: ic, size: 15 })),
            label,
            R.createElement('span', { className: 'ct' }, count)))),
        R.createElement('div', { className: 'tcc-foot' }, 'Last sweep 2m ago · all local')),
      R.createElement('main', { className: 'tcc-main' }, children)));
};

window.TeamHeader = function TeamHeader({ eyebrow, title, sub, actions }) {
  return R.createElement('div', { className: 'tmc-hd' },
    R.createElement('div', { className: 'tmc-hd__l' },
      eyebrow && R.createElement('div', { className: 'tmc-eyebrow' }, eyebrow),
      R.createElement('div', { className: 'tmc-title' }, title),
      sub && R.createElement('div', { className: 'tmc-sub' }, sub)),
    actions && R.createElement('div', { className: 'tmc-actions' }, actions));
};
