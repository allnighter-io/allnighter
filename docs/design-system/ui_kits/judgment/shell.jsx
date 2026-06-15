// @ds-adherence-ignore -- Judgment workflow shell (window + pipeline rail). Window globals.
const R = window.React;

(function () {
  if (document.getElementById('jud-css')) return;
  const s = document.createElement('style'); s.id = 'jud-css';
  s.textContent = `
  .jud-win{display:flex;flex-direction:column;width:100%;height:100%;background:var(--bg-base);border:1px solid var(--border-default);
    border-radius:var(--radius-window);overflow:hidden;box-shadow:var(--shadow-xl);font-family:var(--font-sans)}
  .jud-title{height:44px;flex:none;display:flex;align-items:center;gap:12px;padding:0 14px;background:var(--bg-surface);border-bottom:1px solid var(--border-subtle)}
  .jud-lights{display:flex;gap:8px}.jud-lights i{width:12px;height:12px;border-radius:50%;display:block}
  .jud-tc{flex:1;display:flex;align-items:center;justify-content:center;gap:8px}
  .jud-tc .nm{font-size:var(--text-label);font-weight:600;color:var(--text-secondary)}
  .jud-tc .sub{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .jud-tr{display:flex;align-items:center;gap:6px}
  .jud-body{flex:1;display:flex;min-height:0}
  .jud-rail{width:248px;flex:none;background:var(--bg-subtle);border-right:1px solid var(--border-subtle);display:flex;flex-direction:column;overflow:auto}
  .jud-rail__hd{padding:15px 16px 10px}
  .jud-rail__prompt{font-size:13px;color:var(--text-secondary);line-height:1.4;font-weight:500}
  .jud-rail__meta{display:flex;align-items:center;gap:6px;margin-top:9px}
  .jud-steps{position:relative;padding:6px 10px 16px}
  .jud-steps::before{content:"";position:absolute;left:31px;top:22px;bottom:30px;width:1.5px;background:var(--border-subtle)}
  .jud-step{display:flex;align-items:center;gap:11px;width:100%;padding:7px 8px;border:none;background:transparent;border-radius:var(--radius-md);
    cursor:pointer;text-align:left;position:relative;transition:var(--transition-control)}
  .jud-step:hover{background:var(--bg-hover)}
  .jud-step.is-active{background:var(--bg-active)}
  .jud-step.is-active::before{content:"";position:absolute;left:0;top:8px;bottom:8px;width:2.5px;border-radius:3px;background:var(--accent)}
  .jud-node{width:26px;height:26px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;z-index:1;border:2px solid var(--bg-subtle)}
  .jud-node svg{width:14px;height:14px}
  .jud-step__txt{flex:1;min-width:0;display:flex;flex-direction:column;gap:1px}
  .jud-step__lab{font-size:13px;font-weight:600;color:var(--text-primary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .jud-step.is-idle .jud-step__lab{color:var(--text-faint)}
  .jud-step__sub{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .jud-main{flex:1;min-width:0;display:flex;flex-direction:column;background:var(--bg-base);overflow:auto}
  .jud-hd{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;padding:24px 28px 16px;border-bottom:1px solid var(--border-subtle)}
  .jud-hd__l{min-width:0}
  .jud-hd__eyebrow{font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--accent-text);margin-bottom:7px}
  .jud-hd__t{font-size:var(--text-h2);font-weight:700;letter-spacing:-.01em}
  .jud-hd__sub{color:var(--text-muted);font-size:13px;margin-top:5px}
  .jud-hd__r{display:flex;gap:8px;flex:none;align-items:center}
  .jud-content{padding:22px 28px 40px}
  .al-livemark .cur{fill:#FFE9C6}.al-livemark.run .cur{animation:jud-blink 1.05s steps(1,end) infinite}
  @keyframes jud-blink{0%,52%{opacity:1}53%,100%{opacity:0}}`;
  document.head.appendChild(s);
})();

window.JLive = function JLive({ size = 18, run }) {
  return R.createElement('svg', { className: 'al-livemark' + (run ? ' run' : ''), width: size, height: size, viewBox: '0 0 100 100',
    dangerouslySetInnerHTML: { __html:
      `<defs><linearGradient id="jlm" x1="20" y1="24" x2="66" y2="80" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFD79E"/><stop offset=".5" stop-color="#FFA630"/><stop offset="1" stop-color="#F0901C"/></linearGradient><mask id="jcm"><rect width="100" height="100" fill="black"/><circle cx="47" cy="50" r="32" fill="white"/><circle cx="62" cy="41" r="28" fill="black"/></mask></defs><rect width="100" height="100" fill="url(#jlm)" mask="url(#jcm)"/>` +
      (run ? '<rect class="cur" x="60" y="43" width="10.5" height="17" rx="2.6" fill="#FFE9C6"/>' : '') } });
};

const STATUS = {
  done: { bg: 'var(--success-surface)', fg: 'var(--green-400)' },
  running: { bg: 'var(--info-surface)', fg: 'var(--blue-400)' },
  idle: { bg: 'var(--bg-active)', fg: 'var(--text-faint)' },
  failed: { bg: 'var(--danger-surface)', fg: 'var(--red-400)' },
};

window.JUD_STAGES = [
  { id: 'prompt', label: 'Prompt', icon: 'terminal', sub: 'light_review', status: 'done' },
  { id: 'panel', label: 'Panel', icon: 'users', sub: '5 seats · reused', status: 'done', reuse: true },
  { id: 'analysis', label: 'Judge analysis', icon: 'scale', sub: '2 contradictions', status: 'done' },
  { id: 'plan', label: 'Draft plan', icon: 'file-text', sub: 'master_plan.md', status: 'done' },
  { id: 'review', label: 'Review board', icon: 'shield', sub: '3 lenses · 1 blocker', status: 'done' },
  { id: 'final', label: 'Final spec', icon: 'circle-check', sub: 'executable ✓', status: 'done' },
  { id: 'dispatch', label: 'Dispatch', icon: 'arrow-right', sub: 'Opus 4.8 · exit 0', status: 'done' },
  { id: 'return', label: 'Return review', icon: 'rotate-cw', sub: 'met 3/3 · 0.86', status: 'done' },
  { id: 'routing', label: 'Next action', icon: 'compare', sub: 'recommend: pick', status: 'done' },
];

window.JShell = function JShell({ active, onNav, children }) {
  const { IconButton, Icon, Badge } = window;
  return R.createElement('div', { className: 'jud-win' },
    R.createElement('div', { className: 'jud-title' },
      R.createElement('div', { className: 'jud-lights' },
        R.createElement('i', { style: { background: '#FF5F57' } }), R.createElement('i', { style: { background: '#FEBC2E' } }), R.createElement('i', { style: { background: '#28C840' } })),
      R.createElement('div', { className: 'jud-tc' },
        R.createElement(window.JLive, { size: 16 }), R.createElement('span', { className: 'nm' }, 'allnighter'), R.createElement('span', { className: 'sub' }, '· judgment')),
      R.createElement('div', { className: 'jud-tr' },
        R.createElement(Badge, { tone: 'positive', dot: true }, '5/5 healthy'),
        R.createElement(IconButton, { variant: 'ghost', size: 'sm', label: 'History' }, R.createElement(Icon, { name: 'history' })),
        R.createElement(IconButton, { variant: 'ghost', size: 'sm', label: 'Settings', onClick: () => onNav('cfg_scorecards') }, R.createElement(Icon, { name: 'settings-2' })))),
    R.createElement('div', { className: 'jud-body' },
      R.createElement('aside', { className: 'jud-rail' },
        R.createElement('button', { className: 'jud-rail__hd', onClick: () => onNav('overview'), style: { background: active === 'overview' ? 'var(--bg-active)' : 'transparent', border: 'none', textAlign: 'left', cursor: 'pointer', borderBottom: '1px solid var(--border-subtle)' } },
          R.createElement('div', { className: 'jud-rail__prompt' }, '“Add per-user rate limiting to the public API.”'),
          R.createElement('div', { className: 'jud-rail__meta' },
            R.createElement(Badge, { tone: 'accent' }, 'light_review'),
            R.createElement(Badge, { tone: 'neutral', mono: true }, 'run 7f3'))),
        R.createElement('div', { className: 'jud-steps' },
          window.JUD_STAGES.map((st) => {
            const sc = STATUS[st.status] || STATUS.idle;
            return R.createElement('button', { key: st.id, className: 'jud-step' + (active === st.id ? ' is-active' : '') + (st.status === 'idle' ? ' is-idle' : ''), onClick: () => onNav(st.id) },
              R.createElement('span', { className: 'jud-node', style: { background: sc.bg, color: sc.fg } }, R.createElement(Icon, { name: st.icon, size: 14 })),
              R.createElement('span', { className: 'jud-step__txt' },
                R.createElement('span', { className: 'jud-step__lab' }, st.label),
                R.createElement('span', { className: 'jud-step__sub' }, st.sub)));
          }))),
      R.createElement('main', { className: 'jud-main' }, children)));
};

window.JHeader = function JHeader({ eyebrow, title, sub, actions }) {
  return R.createElement('div', { className: 'jud-hd' },
    R.createElement('div', { className: 'jud-hd__l' },
      eyebrow && R.createElement('div', { className: 'jud-hd__eyebrow' }, eyebrow),
      R.createElement('div', { className: 'jud-hd__t' }, title),
      sub && R.createElement('div', { className: 'jud-hd__sub' }, sub)),
    actions && R.createElement('div', { className: 'jud-hd__r' }, actions));
};
