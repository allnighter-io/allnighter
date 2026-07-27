// @ds-adherence-ignore -- iOS floor-manager screens. Window globals.
const R = window.React;

(function () {
  if (document.getElementById('al-ios-css')) return;
  const s = document.createElement('style'); s.id = 'al-ios-css';
  s.textContent = `
  .ios-app{height:100%;display:flex;flex-direction:column;background:var(--bg-base);color:var(--text-primary);font-family:var(--font-sans)}
  .ios-scroll{flex:1;overflow:auto;padding:50px 18px 22px}
  .ios-hdr{display:flex;align-items:center;gap:9px;margin-bottom:18px}
  .ios-hdr .wm{font-family:var(--font-display);font-weight:800;font-size:18px;letter-spacing:-.02em;flex:1}
  .ios-hi{font-family:var(--font-display);font-size:28px;font-weight:800;letter-spacing:-.02em;line-height:1.1}
  .ios-sub{color:var(--text-muted);font-size:14px;margin-top:5px}
  .ios-eyebrow{font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--accent-text);margin-bottom:12px}
  .ios-sectit{font-size:13px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--text-faint);margin:24px 0 11px}
  .ios-pull{background:linear-gradient(180deg,rgba(255,166,48,.10),transparent 70%),var(--bg-raised);border:1px solid var(--accent-border);
    border-radius:18px;padding:18px}
  .ios-stats{display:flex;gap:10px;margin-top:14px}
  .ios-stat{flex:1;background:var(--bg-surface);border:1px solid var(--border-subtle);border-radius:12px;padding:12px 11px}
  .ios-stat .v{font-family:var(--font-display);font-size:21px;font-weight:800;letter-spacing:-.02em}
  .ios-stat .l{font-size:11px;color:var(--text-muted);margin-top:3px;line-height:1.3}
  .ios-card{background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:14px;padding:14px;margin-bottom:10px}
  .ios-row{display:flex;align-items:center;gap:12px}
  .ios-glyph{width:34px;height:34px;border-radius:9px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none;overflow:hidden}
  .ios-glyph img{width:20px;height:20px}
  .ios-main{flex:1;min-width:0;display:flex;flex-direction:column}
  .ios-t{font-size:15px;font-weight:600;line-height:1.25}
  .ios-m{font-family:var(--font-mono);font-size:11px;color:var(--text-faint);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .ios-prog{height:4px;border-radius:3px;background:var(--bg-active);margin-top:11px;overflow:hidden}
  .ios-prog>i{display:block;height:100%;background:var(--accent);border-radius:3px}
  .ios-cta{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;height:50px;border:none;border-radius:13px;
    background:var(--accent);color:var(--text-on-amber);font-family:var(--font-sans);font-size:16px;font-weight:600;cursor:pointer}
  .ios-cta:active{transform:scale(.98)}
  .ios-cta--ghost{background:var(--bg-surface);color:var(--text-primary);border:1px solid var(--border-default)}
  .ios-cta--danger{background:transparent;color:var(--red-400);border:1px solid rgba(247,107,107,.32)}
  .ios-cta svg{width:18px;height:18px}
  .ios-preview{height:118px;border-radius:12px;position:relative;overflow:hidden;border:1px solid var(--border-subtle);margin-bottom:12px}
  .ios-preview .lab{position:absolute;left:11px;bottom:9px;font-size:12px;font-weight:600;color:#fff;z-index:2}
  .ios-preview .tag{position:absolute;right:9px;top:9px;z-index:2}
  .ios-tabbar{flex:none;display:flex;background:var(--bg-surface);border-top:1px solid var(--border-subtle);padding:9px 0 26px}
  .ios-tab{flex:1;display:flex;flex-direction:column;align-items:center;gap:4px;border:none;background:transparent;color:var(--text-faint);
    font-size:10px;font-weight:600;cursor:pointer;padding:4px 0}
  .ios-tab svg{width:23px;height:23px}
  .ios-tab.is-active{color:var(--accent-text)}
  .ios-sheet{position:absolute;inset:0;z-index:80;display:flex;flex-direction:column;justify-content:flex-end}
  .ios-sheet__scrim{position:absolute;inset:0;background:var(--bg-overlay)}
  .ios-sheet__card{position:relative;background:var(--bg-raised);border-top-left-radius:24px;border-top-right-radius:24px;
    border-top:1px solid var(--border-default);padding:20px 18px 40px;box-shadow:var(--shadow-xl)}
  .ios-sheet__grab{width:38px;height:4px;border-radius:3px;background:var(--ink-500);margin:0 auto 16px}
  .ios-ta{width:100%;box-sizing:border-box;background:var(--bg-input);border:1px solid var(--border-default);border-radius:12px;
    color:var(--text-primary);font-family:var(--font-sans);font-size:15px;line-height:1.45;padding:13px;resize:none;outline:none}
  .ios-ta:focus{border-color:var(--accent-border)}
  .ios-killrow{display:flex;align-items:center;gap:12px;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:14px;padding:14px}`;
  document.head.appendChild(s);
})();

const LiveMarkMini = ({ size = 22, run }) => R.createElement('svg', {
  width: size, height: size, viewBox: '0 0 100 100',
  dangerouslySetInnerHTML: { __html:
    `<defs><linearGradient id="iolm" x1="20" y1="24" x2="66" y2="80" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFD79E"/><stop offset=".5" stop-color="#FFA630"/><stop offset="1" stop-color="#F0901C"/></linearGradient><mask id="iocm"><rect width="100" height="100" fill="black"/><circle cx="47" cy="50" r="32" fill="white"/><circle cx="62" cy="41" r="28" fill="black"/></mask></defs><rect width="100" height="100" fill="url(#iolm)" mask="url(#iocm)"/>` +
    (run ? '<rect x="60" y="43" width="10.5" height="17" rx="2.6" fill="#FFE9C6"><animate attributeName="opacity" values="1;1;0;0" dur="1.05s" repeatCount="indefinite"/></rect>' : '') },
});

const DRAFTS = [
  { id: 'a', label: 'Editorial', worker: 'Opus 4.8', brand: 'anthropic', color: 'FFA630', sum: 'Big type, generous whitespace, one accent.', grad: 'linear-gradient(135deg,#1B2138,#0B0E1A)' },
  { id: 'b', label: 'Control-room', worker: 'ChatGPT 5.5', icon: 'terminal', sum: 'Dense mono numerics on near-black.', grad: 'linear-gradient(135deg,#0F1B16,#0B0E1A)' },
  { id: 'c', label: 'Calm-OS', worker: 'Gemini Flash', brand: 'googlegemini', color: 'E1E5F0', sum: 'Soft surfaces, muted color, motion.', grad: 'linear-gradient(135deg,#231A2E,#0B0E1A)' },
];
const LANES = [
  { id: 1, name: 'premium dashboard · A', worker: 'Opus 4.8', brand: 'anthropic', color: 'FFA630', status: 'running', prog: 64, meta: 'lane a3f · 04:12 elapsed' },
  { id: 2, name: 'sticky header fix', worker: 'Sonnet 4.6', brand: 'anthropic', color: 'AEB5C9', status: 'running', prog: 38, meta: 'lane b1c · 02:40 elapsed' },
  { id: 3, name: 'api error copy', worker: 'ChatGPT 5.5', icon: 'terminal', status: 'done', prog: 100, meta: 'lane c90 · green tier · 5 tests pass' },
];

function GlyphEl({ d, size = 20 }) {
  const { BrandIcon, Icon } = window;
  return d.brand ? R.createElement(BrandIcon, { slug: d.brand, color: d.color, size }) : R.createElement(Icon, { name: d.icon || 'terminal', size: size - 2, style: { color: 'var(--text-secondary)' } });
}

/* ---------- Home ---------- */
function HomeScreen({ go }) {
  const { Icon, StatusPill } = window;
  return R.createElement('div', null,
    R.createElement('div', { className: 'ios-hdr' },
      R.createElement(LiveMarkMini, { size: 24 }),
      R.createElement('span', { className: 'wm' }, 'allnighter'),
      R.createElement(Icon, { name: 'settings-2', size: 21, style: { color: 'var(--text-muted)' } })),
    R.createElement('div', { className: 'ios-hi' }, 'Good morning, Mara'),
    R.createElement('div', { className: 'ios-sub' }, 'Thursday · 3 lanes active on the bench'),
    R.createElement('div', { className: 'ios-pull', style: { marginTop: 18 } },
      R.createElement('div', { className: 'ios-eyebrow' }, 'Session digest'),
      R.createElement('div', { style: { fontSize: 15, color: 'var(--text-secondary)', lineHeight: 1.5 } }, 'Your prepaid bench turned quota into reviewable progress.'),
      R.createElement('div', { className: 'ios-stats' },
        [['4.2h', 'agent-hours'], ['7', 'drafts'], ['3', 'landed']].map((s, i) =>
          R.createElement('div', { className: 'ios-stat', key: i },
            R.createElement('div', { className: 'v' }, s[0]),
            R.createElement('div', { className: 'l' }, s[1]))))),
    R.createElement('div', { className: 'ios-sectit' }, 'Needs you'),
    R.createElement('button', { className: 'ios-card', style: { width: '100%', textAlign: 'left', cursor: 'pointer', border: '1px solid var(--accent-border)' }, onClick: () => go('race') },
      R.createElement('div', { className: 'ios-row' },
        R.createElement('span', { className: 'ios-glyph', style: { background: 'var(--accent-surface)' } }, R.createElement(Icon, { name: 'users', size: 18, style: { color: 'var(--accent-text)' } })),
        R.createElement('span', { className: 'ios-main' },
          R.createElement('span', { className: 'ios-t' }, 'A race is ready to plan writer'),
          R.createElement('span', { className: 'ios-m' }, '3 directions · premium dashboard')),
        R.createElement(Icon, { name: 'chevron-right', size: 18, style: { color: 'var(--text-faint)' } }))),
    R.createElement('div', { className: 'ios-sectit' }, 'Landed'),
    [['Onboarding copy rewrite', 'green tier · reverted 0'], ['Empty-state illustrations', 'green tier · 6 tests pass']].map((x, i) =>
      R.createElement('div', { className: 'ios-card', key: i },
        R.createElement('div', { className: 'ios-row' },
          R.createElement('span', { className: 'ios-glyph', style: { background: 'var(--success-surface)' } }, R.createElement(Icon, { name: 'check-check', size: 18, style: { color: 'var(--green-400)' } })),
          R.createElement('span', { className: 'ios-main' },
            R.createElement('span', { className: 'ios-t' }, x[0]),
            R.createElement('span', { className: 'ios-m' }, x[1]))))),
    R.createElement('div', { className: 'ios-sectit' }, 'Safety'),
    R.createElement('div', { className: 'ios-killrow' },
      R.createElement('span', { className: 'ios-main' },
        R.createElement('span', { className: 'ios-t' }, 'Stop all workers'),
        R.createElement('span', { style: { fontSize: 12, color: 'var(--text-muted)', marginTop: 2, display: 'block' } }, 'Global kill switch · halts every lane')),
      R.createElement('span', { style: { color: 'var(--red-400)' } }, R.createElement(Icon, { name: 'square', size: 22 }))));
}

/* ---------- Lanes ---------- */
function LanesScreen() {
  const { StatusPill, Badge } = window;
  return R.createElement('div', null,
    R.createElement('div', { className: 'ios-hi', style: { fontSize: 24 } }, 'Active lanes'),
    R.createElement('div', { className: 'ios-sub', style: { marginBottom: 18 } }, '2 running · 1 ready to land'),
    LANES.map((l) =>
      R.createElement('div', { className: 'ios-card', key: l.id },
        R.createElement('div', { className: 'ios-row' },
          R.createElement('span', { className: 'ios-glyph' }, R.createElement(GlyphEl, { d: l })),
          R.createElement('span', { className: 'ios-main' },
            R.createElement('span', { className: 'ios-t' }, l.name),
            R.createElement('span', { className: 'ios-m' }, l.meta)),
          R.createElement(StatusPill, { status: l.status })),
        l.status === 'running'
          ? R.createElement('div', { className: 'ios-prog' }, R.createElement('i', { style: { width: l.prog + '%' } }))
          : R.createElement('button', { className: 'ios-cta', style: { marginTop: 12, height: 44, fontSize: 15 } },
              R.createElement(window.Icon, { name: 'check', size: 17 }), 'Land · green tier'))));
}

/* ---------- Race (the wedge) ---------- */
function RaceScreen() {
  const { Badge, Icon } = window;
  const [picked, setPicked] = R.useState(null);
  const [done, setDone] = R.useState(false);
  const d = DRAFTS.find((x) => x.id === picked);
  return R.createElement('div', null,
    R.createElement('div', { className: 'ios-hi', style: { fontSize: 24 } }, 'Draft race'),
    R.createElement('div', { className: 'ios-sub', style: { marginBottom: 18 } }, '“make the dashboard feel premium” · 3 directions'),
    DRAFTS.map((dr) =>
      R.createElement('div', { className: 'ios-card', key: dr.id, style: { padding: 12 } },
        R.createElement('div', { className: 'ios-preview', style: { background: dr.grad } },
          R.createElement('span', { className: 'lab' }, dr.label),
          R.createElement('span', { className: 'tag' }, R.createElement(Badge, { tone: 'neutral', mono: true }, dr.id.toUpperCase())),
          R.createElement('div', { style: { position: 'absolute', left: 11, top: 11, right: 11, display: 'flex', gap: 5 } },
            [0, 1, 2].map((k) => R.createElement('div', { key: k, style: { flex: 1, height: 26, borderRadius: 6, background: 'rgba(255,255,255,.06)', border: '1px solid rgba(255,255,255,.08)' } }))),
          R.createElement('div', { style: { position: 'absolute', left: 11, right: 11, top: 44, height: 40, borderRadius: 6, background: 'rgba(255,166,48,.10)', border: '1px solid rgba(255,166,48,.22)' } })),
        R.createElement('div', { className: 'ios-row', style: { marginBottom: 11 } },
          R.createElement('span', { className: 'ios-glyph', style: { width: 26, height: 26 } }, R.createElement(GlyphEl, { d: dr, size: 16 })),
          R.createElement('span', { className: 'ios-main' },
            R.createElement('span', { style: { fontSize: 13, fontWeight: 600 } }, dr.worker),
            R.createElement('span', { style: { fontSize: 13, color: 'var(--text-muted)', display: 'block', marginTop: 1 } }, dr.sum))),
        R.createElement('button', { className: 'ios-cta ios-cta--ghost', style: { height: 44, fontSize: 15 }, onClick: () => { setPicked(dr.id); setDone(false); } },
          R.createElement(Icon, { name: 'sparkles', size: 16 }), 'Pick this'))),
    picked && R.createElement(PickSheet, { d, done, onImplement: () => setDone(true), onClose: () => setPicked(null) }));
}

function PickSheet({ d, done, onImplement, onClose }) {
  const { Icon } = window;
  return R.createElement('div', { className: 'ios-sheet' },
    R.createElement('div', { className: 'ios-sheet__scrim', onClick: onClose }),
    R.createElement('div', { className: 'ios-sheet__card' },
      R.createElement('div', { className: 'ios-sheet__grab' }),
      done
        ? R.createElement('div', { style: { textAlign: 'center', padding: '8px 0 4px' } },
            R.createElement('div', { style: { display: 'flex', justifyContent: 'center', marginBottom: 12 } }, R.createElement(LiveMarkMini, { size: 44, run: true })),
            R.createElement('div', { style: { fontSize: 19, fontWeight: 700 } }, 'Lane started'),
            R.createElement('div', { style: { color: 'var(--text-muted)', fontSize: 14, marginTop: 6, lineHeight: 1.5 } }, 'Implementing direction ' + d.id.toUpperCase() + ' with your note. You\u2019ll get a landing card when it\u2019s ready.'),
            R.createElement('button', { className: 'ios-cta ios-cta--ghost', style: { marginTop: 18 }, onClick: onClose }, 'Done'))
        : R.createElement(R.Fragment, null,
            R.createElement('div', { className: 'ios-eyebrow' }, 'Implement this'),
            R.createElement('div', { style: { fontSize: 19, fontWeight: 700, marginBottom: 4 } }, d.label + ' — by ' + d.worker),
            R.createElement('div', { style: { color: 'var(--text-muted)', fontSize: 14, marginBottom: 14, lineHeight: 1.45 } }, 'Your pick becomes the work order. Add a note to steer it — no copy-paste, no re-explaining.'),
            R.createElement('textarea', { className: 'ios-ta', rows: 3, defaultValue: 'but make the header sticky' }),
            R.createElement('button', { className: 'ios-cta', style: { marginTop: 14 }, onClick: onImplement },
              R.createElement(Icon, { name: 'arrow-right', size: 18 }), 'Implement this'))));
}

/* ---------- App shell + tabs ---------- */
window.FloorApp = function FloorApp() {
  const { Icon } = window;
  const [tab, setTab] = R.useState('home');
  const screen = tab === 'home' ? R.createElement(HomeScreen, { go: setTab })
    : tab === 'lanes' ? R.createElement(LanesScreen)
    : R.createElement(RaceScreen);
  const TABS = [['home', 'Home', 'moon'], ['lanes', 'Lanes', 'activity'], ['race', 'Race', 'users']];
  return R.createElement('div', { className: 'ios-app' },
    R.createElement('div', { className: 'ios-scroll' }, screen),
    R.createElement('div', { className: 'ios-tabbar' },
      TABS.map(([id, label, icon]) =>
        R.createElement('button', { key: id, className: 'ios-tab' + (tab === id ? ' is-active' : ''), onClick: () => setTab(id) },
          R.createElement(Icon, { name: icon, size: 23 }),
          R.createElement('span', null, label)))));
};
