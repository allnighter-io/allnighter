// @ds-adherence-ignore -- Design council shell: window chrome + pipeline rail,
// plus the primitives the base preview lacks (DCSelect, DCMenu, a fuller DCIcon).
// Window globals, no exports.
const R = window.React;

/* ---------- fuller Lucide icon set (the base _preview.jsx ships a small subset) ---------- */
const DC_ICONS = {
  // reuse-equivalents
  play: '<polygon points="6 3 20 12 6 21 6 3"/>',
  square: '<rect width="14" height="14" x="5" y="5" rx="2"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  'check-check': '<path d="M18 6 7 17l-5-5"/><path d="m22 10-7.5 7.5L13 16"/>',
  plus: '<path d="M5 12h14"/><path d="M12 5v14"/>',
  x: '<path d="M18 6 6 18"/><path d="m6 6 12 12"/>',
  'settings-2': '<path d="M20 7h-9"/><path d="M14 17H5"/><circle cx="17" cy="17" r="3"/><circle cx="7" cy="7" r="3"/>',
  terminal: '<path d="m4 17 6-6-6-6"/><path d="M12 19h8"/>',
  sparkles: '<path d="M9.937 15.5A2 2 0 0 0 8.5 14.063l-6.135-1.582a.5.5 0 0 1 0-.962L8.5 9.936A2 2 0 0 0 9.937 8.5l1.582-6.135a.5.5 0 0 1 .963 0L14.063 8.5A2 2 0 0 0 15.5 9.937l6.135 1.581a.5.5 0 0 1 0 .964L15.5 14.063a2 2 0 0 0-1.437 1.437l-1.582 6.135a.5.5 0 0 1-.963 0z"/><path d="M20 3v4"/><path d="M22 5h-4"/>',
  'rotate-cw': '<path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8"/><path d="M21 3v5h-5"/>',
  download: '<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="M7 10l5 5 5-5"/><path d="M12 15V3"/>',
  'chevron-down': '<path d="m6 9 6 6 6-6"/>',
  'chevron-right': '<path d="m9 18 6-6-6-6"/>',
  'arrow-right': '<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>',
  'arrow-left': '<path d="M19 12H5"/><path d="m12 19-7-7 7-7"/>',
  clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
  zap: '<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/>',
  'file-text': '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M16 13H8"/><path d="M16 17H8"/><path d="M10 9H8"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
  moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
  history: '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/>',
  copy: '<rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
  // new for the design council
  image: '<rect width="18" height="18" x="3" y="3" rx="2" ry="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/>',
  'image-plus': '<path d="M16 5h6"/><path d="M19 2v6"/><path d="M21 11.5V19a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h7.5"/><path d="m21 15-3.086-3.086a2 2 0 0 0-2.828 0L6 21"/><circle cx="9" cy="9" r="2"/>',
  'layout-grid': '<rect width="7" height="7" x="3" y="3" rx="1"/><rect width="7" height="7" x="14" y="3" rx="1"/><rect width="7" height="7" x="14" y="14" rx="1"/><rect width="7" height="7" x="3" y="14" rx="1"/>',
  layers: '<path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83z"/><path d="M2 12a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 12"/><path d="M2 17a1 1 0 0 0 .58.91l8.6 3.91a2 2 0 0 0 1.65 0l8.58-3.9A1 1 0 0 0 22 17"/>',
  maximize: '<path d="M8 3H5a2 2 0 0 0-2 2v3"/><path d="M21 8V5a2 2 0 0 0-2-2h-3"/><path d="M3 16v3a2 2 0 0 0 2 2h3"/><path d="M16 21h3a2 2 0 0 0 2-2v-3"/>',
  columns: '<rect width="18" height="18" x="3" y="3" rx="2"/><path d="M12 3v18"/>',
  eye: '<path d="M2.062 12.348a1 1 0 0 1 0-.696 10.75 10.75 0 0 1 19.876 0 1 1 0 0 1 0 .696 10.75 10.75 0 0 1-19.876 0"/><circle cx="12" cy="12" r="3"/>',
  smartphone: '<rect width="14" height="20" x="5" y="2" rx="2" ry="2"/><path d="M12 18h.01"/>',
  monitor: '<rect width="20" height="14" x="2" y="3" rx="2"/><line x1="8" x2="16" y1="21" y2="21"/><line x1="12" x2="12" y1="17" y2="21"/>',
  palette: '<circle cx="13.5" cy="6.5" r=".5" fill="currentColor"/><circle cx="17.5" cy="10.5" r=".5" fill="currentColor"/><circle cx="8.5" cy="7.5" r=".5" fill="currentColor"/><circle cx="6.5" cy="12.5" r=".5" fill="currentColor"/><path d="M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2"/>',
  folder: '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
  shield: '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>',
  'circle-check': '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
  'message-square': '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  wand: '<path d="m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72"/><path d="m14 7 3 3"/><path d="M5 6v4"/><path d="M19 14v4"/><path d="M10 2v2"/><path d="M7 8H3"/><path d="M21 16h-4"/><path d="M11 3H9"/>',
  heart: '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>',
  'more-horizontal': '<circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/><circle cx="5" cy="12" r="1"/>',
  hammer: '<path d="m15 12-8.5 8.5a2.12 2.12 0 1 1-3-3L12 9"/><path d="M17.64 15 22 10.64"/><path d="m20.91 11.7-1.25-1.25c-.6-.6-.93-1.4-.93-2.25v-.86L16.01 4.6a5.56 5.56 0 0 0-3.94-1.64H9l.92.82A6.18 6.18 0 0 1 12 8.4v1.56l2 2h.86c.85 0 1.65.34 2.25.93l1.25 1.25"/>',
  list: '<path d="M3 12h.01"/><path d="M3 18h.01"/><path d="M3 6h.01"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M8 6h13"/>',
  'corner-down-right': '<polyline points="15 10 20 15 15 20"/><path d="M4 4v7a4 4 0 0 0 4 4h12"/>',
};
window.DCIcon = function DCIcon({ name, size = 20, stroke = 2, style, ...rest }) {
  return R.createElement('svg', {
    width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
    strokeWidth: stroke, strokeLinecap: 'round', strokeLinejoin: 'round',
    style, dangerouslySetInnerHTML: { __html: DC_ICONS[name] || '' }, ...rest,
  });
};

/* ---------- chrome + primitives css ---------- */
(function () {
  if (document.getElementById('dc-css')) return;
  const s = document.createElement('style'); s.id = 'dc-css';
  s.textContent = `
  .dc-win{display:flex;flex-direction:column;width:100%;height:100%;background:var(--bg-base);border:1px solid var(--border-default);
    border-radius:var(--radius-window);overflow:hidden;box-shadow:var(--shadow-xl);font-family:var(--font-sans)}
  .dc-title{height:44px;flex:none;display:flex;align-items:center;gap:12px;padding:0 14px;background:var(--bg-surface);border-bottom:1px solid var(--border-subtle)}
  .dc-lights{display:flex;gap:8px}.dc-lights i{width:12px;height:12px;border-radius:50%;display:block}
  .dc-tc{flex:1;display:flex;align-items:center;justify-content:center;gap:8px}
  .dc-tc .nm{font-size:var(--text-label);font-weight:600;color:var(--text-secondary)}
  .dc-tc .sub{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .dc-tr{display:flex;align-items:center;gap:6px}
  .dc-body{flex:1;display:flex;min-height:0}
  .dc-rail{width:248px;flex:none;background:var(--bg-subtle);border-right:1px solid var(--border-subtle);display:flex;flex-direction:column;overflow:auto}
  .dc-rail__hd{padding:14px 16px 12px;border-bottom:1px solid var(--border-subtle);background:transparent;border-left:none;border-right:none;border-top:none;text-align:left;cursor:pointer;width:100%}
  .dc-rail__hd:hover{background:var(--bg-hover)}
  .dc-rail__thumb{display:flex;gap:10px;align-items:center}
  .dc-rail__shot{width:38px;height:54px;flex:none;border-radius:6px;border:1px solid var(--border-default);overflow:hidden;position:relative;background:var(--bg-void)}
  .dc-rail__prompt{font-size:13px;color:var(--text-secondary);line-height:1.4;font-weight:500}
  .dc-rail__meta{display:flex;align-items:center;gap:6px;margin-top:9px}
  .dc-steps{position:relative;padding:6px 10px 16px}
  .dc-steps::before{content:"";position:absolute;left:31px;top:22px;bottom:30px;width:1.5px;background:var(--border-subtle)}
  .dc-step{display:flex;align-items:center;gap:11px;width:100%;padding:7px 8px;border:none;background:transparent;border-radius:var(--radius-md);
    cursor:pointer;text-align:left;position:relative;transition:var(--transition-control)}
  .dc-step:hover{background:var(--bg-hover)}
  .dc-step.is-active{background:var(--bg-active)}
  .dc-step.is-active::before{content:"";position:absolute;left:0;top:8px;bottom:8px;width:2.5px;border-radius:3px;background:var(--accent)}
  .dc-node{width:26px;height:26px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;z-index:1;border:2px solid var(--bg-subtle)}
  .dc-node svg{width:14px;height:14px}
  .dc-step__txt{flex:1;min-width:0;display:flex;flex-direction:column;gap:1px}
  .dc-step__lab{font-size:13px;font-weight:600;color:var(--text-primary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .dc-step.is-idle .dc-step__lab{color:var(--text-faint)}
  .dc-step__sub{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .dc-main{flex:1;min-width:0;display:flex;flex-direction:column;background:var(--bg-base);overflow:auto;position:relative}
  .dc-hd{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;padding:24px 28px 16px;border-bottom:1px solid var(--border-subtle)}
  .dc-hd__l{min-width:0}
  .dc-hd__eyebrow{font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--accent-text);margin-bottom:7px}
  .dc-hd__t{font-size:var(--text-h2);font-weight:700;letter-spacing:-.01em}
  .dc-hd__sub{color:var(--text-muted);font-size:13px;margin-top:5px;max-width:560px;line-height:1.5}
  .dc-hd__r{display:flex;gap:8px;flex:none;align-items:center}
  .dc-content{padding:22px 28px 44px}
  /* DCSelect */
  .dc-sel{position:relative;font-family:var(--font-sans)}
  .dc-sel__btn{display:flex;align-items:center;gap:8px;width:100%;height:30px;padding:0 9px 0 11px;box-sizing:border-box;background:var(--bg-input);
    border:1px solid var(--border-default);border-radius:var(--radius-sm);color:var(--text-primary);font-size:13px;cursor:pointer;transition:var(--transition-control)}
  .dc-sel__btn:hover{border-color:var(--border-strong)}
  .dc-sel__btn.is-open{border-color:var(--accent-border);box-shadow:var(--focus-ring)}
  .dc-sel--mono .dc-sel__btn{font-family:var(--font-mono);font-size:12px}
  .dc-sel__val{flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;text-align:left}
  .dc-sel__chev{flex:none;color:var(--text-faint);transition:transform var(--duration-fast) var(--ease-out)}
  .dc-sel__btn.is-open .dc-sel__chev{transform:rotate(180deg)}
  .dc-pop{position:absolute;z-index:40;top:calc(100% + 5px);left:0;min-width:100%;background:var(--bg-raised);border:1px solid var(--border-default);
    border-radius:var(--radius-md);box-shadow:var(--shadow-lg,0 12px 36px rgba(0,0,0,.5));padding:5px;backdrop-filter:blur(8px)}
  .dc-pop--end{left:auto;right:0}
  .dc-opt{display:flex;align-items:center;gap:8px;width:100%;padding:7px 9px;border:none;background:transparent;border-radius:var(--radius-sm);
    color:var(--text-secondary);font-size:13px;font-family:inherit;cursor:pointer;text-align:left;white-space:nowrap;transition:var(--transition-control)}
  .dc-sel--mono .dc-opt{font-family:var(--font-mono);font-size:12px}
  .dc-opt:hover{background:var(--bg-hover);color:var(--text-primary)}
  .dc-opt.is-sel{color:var(--accent-text)}
  .dc-opt__chk{margin-left:auto;flex:none;opacity:0}.dc-opt.is-sel .dc-opt__chk{opacity:1}
  .dc-opt--danger{color:var(--red-400)}.dc-opt--danger:hover{background:var(--danger-surface)}
  .dc-pop__div{height:1px;background:var(--border-subtle);margin:4px 2px}
  .dc-livemark .cur{fill:#FFE9C6}.dc-livemark.run .cur{animation:dc-blink 1.05s steps(1,end) infinite}
  @keyframes dc-blink{0%,52%{opacity:1}53%,100%{opacity:0}}`;
  document.head.appendChild(s);
})();

/* ---------- DCSelect ---------- */
window.DCSelect = function DCSelect({ value, defaultValue, options = [], onChange, mono = false, leading, align = 'start', width }) {
  const [open, setOpen] = R.useState(false);
  const [internal, setInternal] = R.useState(defaultValue != null ? defaultValue : (options[0] && options[0].value));
  const val = value !== undefined ? value : internal;
  const ref = R.useRef(null);
  R.useEffect(() => {
    function onDoc(e) { if (ref.current && !ref.current.contains(e.target)) setOpen(false); }
    document.addEventListener('mousedown', onDoc); return () => document.removeEventListener('mousedown', onDoc);
  }, []);
  const cur = options.find((o) => o.value === val) || options[0] || { label: '' };
  return R.createElement('div', { className: 'dc-sel' + (mono ? ' dc-sel--mono' : ''), ref, style: width ? { width } : null },
    R.createElement('button', { type: 'button', className: 'dc-sel__btn' + (open ? ' is-open' : ''), onClick: () => setOpen((o) => !o) },
      leading && R.createElement('span', { style: { display: 'inline-flex', flex: 'none' } }, leading),
      R.createElement('span', { className: 'dc-sel__val' }, cur.label),
      R.createElement('span', { className: 'dc-sel__chev' }, R.createElement(window.DCIcon, { name: 'chevron-down', size: 14 }))),
    open && R.createElement('div', { className: 'dc-pop' + (align === 'end' ? ' dc-pop--end' : '') },
      options.map((o) => R.createElement('button', { key: o.value, type: 'button', className: 'dc-opt' + (o.value === val ? ' is-sel' : ''),
        onClick: () => { setInternal(o.value); onChange && onChange(o.value); setOpen(false); } },
        o.label,
        R.createElement('span', { className: 'dc-opt__chk' }, R.createElement(window.DCIcon, { name: 'check', size: 13, stroke: 3 }))))));
};

/* ---------- DCMenu (kebab actions) ---------- */
window.DCMenu = function DCMenu({ trigger, items = [], align = 'end' }) {
  const [open, setOpen] = R.useState(false);
  const ref = R.useRef(null);
  R.useEffect(() => {
    function onDoc(e) { if (ref.current && !ref.current.contains(e.target)) setOpen(false); }
    document.addEventListener('mousedown', onDoc); return () => document.removeEventListener('mousedown', onDoc);
  }, []);
  return R.createElement('div', { className: 'dc-sel', ref, style: { display: 'inline-block' } },
    R.createElement('span', { onClick: () => setOpen((o) => !o) }, trigger),
    open && R.createElement('div', { className: 'dc-pop' + (align === 'end' ? ' dc-pop--end' : ''), style: { minWidth: 180 } },
      items.map((it, i) => it.divider
        ? R.createElement('div', { key: i, className: 'dc-pop__div' })
        : R.createElement('button', { key: i, type: 'button', className: 'dc-opt' + (it.danger ? ' dc-opt--danger' : ''),
            onClick: () => { setOpen(false); it.onClick && it.onClick(); } },
            it.icon && R.createElement('span', { style: { display: 'inline-flex', flex: 'none' } }, it.icon), it.label))));
};

/* ---------- live mark ---------- */
window.DCLive = function DCLive({ size = 18, run }) {
  return R.createElement('svg', { className: 'dc-livemark' + (run ? ' run' : ''), width: size, height: size, viewBox: '0 0 100 100',
    dangerouslySetInnerHTML: { __html:
      `<defs><linearGradient id="dclm" x1="20" y1="24" x2="66" y2="80" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFD79E"/><stop offset=".5" stop-color="#FFA630"/><stop offset="1" stop-color="#F0901C"/></linearGradient><mask id="dccm"><rect width="100" height="100" fill="black"/><circle cx="47" cy="50" r="32" fill="white"/><circle cx="62" cy="41" r="28" fill="black"/></mask></defs><rect width="100" height="100" fill="url(#dclm)" mask="url(#dccm)"/>` +
      (run ? '<rect class="cur" x="60" y="43" width="10.5" height="17" rx="2.6" fill="#FFE9C6"/>' : '') } });
};

/* ---------- stages ---------- */
const DC_STATUS = {
  done: { bg: 'var(--success-surface)', fg: 'var(--green-400)' },
  running: { bg: 'var(--info-surface)', fg: 'var(--blue-400)' },
  idle: { bg: 'var(--bg-active)', fg: 'var(--text-faint)' },
  failed: { bg: 'var(--danger-surface)', fg: 'var(--red-400)' },
  advisory: { bg: 'var(--accent-surface)', fg: 'var(--accent-text)' },
};
window.DC_STAGES = [
  { id: 'prompt', label: 'Prompt', icon: 'image', sub: 'design_board', status: 'done' },
  { id: 'panel', label: 'Panel', icon: 'layers', sub: '4 mockups · 3 engines', status: 'done' },
  { id: 'board', label: 'The board', icon: 'layout-grid', sub: '4 options · ready', status: 'done' },
  { id: 'lead', label: 'Lead designer', icon: 'message-square', sub: 'advisory · ran on request', status: 'advisory' },
  { id: 'build', label: 'Build this', icon: 'hammer', sub: 'Claude Code · exit 0', status: 'done' },
];

window.DCShell = function DCShell({ active, onNav, children }) {
  const { IconButton, Badge } = window;
  const I = window.DCIcon;
  return R.createElement('div', { className: 'dc-win' },
    R.createElement('div', { className: 'dc-title' },
      R.createElement('div', { className: 'dc-lights' },
        R.createElement('i', { style: { background: '#FF5F57' } }), R.createElement('i', { style: { background: '#FEBC2E' } }), R.createElement('i', { style: { background: '#28C840' } })),
      R.createElement('div', { className: 'dc-tc' },
        R.createElement(window.DCLive, { size: 16 }), R.createElement('span', { className: 'nm' }, 'allnighter'), R.createElement('span', { className: 'sub' }, '· design')),
      R.createElement('div', { className: 'dc-tr' },
        R.createElement(Badge, { tone: 'positive', dot: true }, '3/3 engines'),
        R.createElement(IconButton, { variant: 'ghost', size: 'sm', label: 'History' }, R.createElement(I, { name: 'history' })),
        R.createElement(IconButton, { variant: 'ghost', size: 'sm', label: 'Settings' }, R.createElement(I, { name: 'settings-2' })))),
    R.createElement('div', { className: 'dc-body' },
      R.createElement('aside', { className: 'dc-rail' },
        R.createElement('button', { className: 'dc-rail__hd', onClick: () => onNav('board') },
          R.createElement('div', { className: 'dc-rail__thumb' },
            R.createElement('div', { className: 'dc-rail__shot' }, R.createElement(window.FauxScreen, { variant: 'before', mini: true })),
            R.createElement('div', { style: { minWidth: 0 } },
              R.createElement('div', { className: 'dc-rail__prompt' }, '“Make this profile feel premium and clean.”'),
              R.createElement('div', { className: 'dc-rail__meta' },
                R.createElement(Badge, { tone: 'accent' }, 'design_board'),
                R.createElement(Badge, { tone: 'neutral', mono: true }, 'run a4e'))))),
        R.createElement('div', { className: 'dc-steps' },
          window.DC_STAGES.map((st) => {
            const sc = DC_STATUS[st.status] || DC_STATUS.idle;
            return R.createElement('button', { key: st.id, className: 'dc-step' + (active === st.id ? ' is-active' : '') + (st.status === 'idle' ? ' is-idle' : ''), onClick: () => onNav(st.id) },
              R.createElement('span', { className: 'dc-node', style: { background: sc.bg, color: sc.fg } }, R.createElement(I, { name: st.icon, size: 14 })),
              R.createElement('span', { className: 'dc-step__txt' },
                R.createElement('span', { className: 'dc-step__lab' }, st.label),
                R.createElement('span', { className: 'dc-step__sub' }, st.sub)));
          }))),
      R.createElement('main', { className: 'dc-main' }, children)));
};

window.DCHeader = function DCHeader({ eyebrow, title, sub, actions }) {
  return R.createElement('div', { className: 'dc-hd' },
    R.createElement('div', { className: 'dc-hd__l' },
      eyebrow && R.createElement('div', { className: 'dc-hd__eyebrow' }, eyebrow),
      R.createElement('div', { className: 'dc-hd__t' }, title),
      sub && R.createElement('div', { className: 'dc-hd__sub' }, sub)),
    actions && R.createElement('div', { className: 'dc-hd__r' }, actions));
};
