// @ds-adherence-ignore -- Allnighter "Council health" — the compact, in-app
// re-check surface. A popover anchored to the title-bar health badge, opened
// after first-run setup is complete. Reuses the SetupCard / states / tokens /
// copy from setup.jsx (Phase 3 Doctor → compact roster, per spec 00_ §6, 01_ §10).
// Window globals, no exports. Built from 00_/01_ specs.
const RD = window.React;
const { Button: DB, IconButton: DIB, Badge: DBadge } = window;
const DLiveMark = window.DCLive;
const DSetupCard = window.SetupCard;
const DGroupLabel = window.GroupLabel;
const DI = window.SI; // shared icon helper from setup.jsx (Lucide + extras)

/* ---------- styles ---------- */
(function () {
  if (document.getElementById('dr-css')) return;
  const s = document.createElement('style'); s.id = 'dr-css';
  s.textContent = `
  .dr-page{min-height:100%;background:var(--bg-void);display:flex;justify-content:center;align-items:flex-start;padding:30px 24px 64px;box-sizing:border-box;font-family:var(--font-sans)}
  .dr-frame{width:1120px;max-width:100%;display:flex;flex-direction:column}
  /* window-top peeking behind the popover (the running app, dimmed) */
  .dr-bar{box-sizing:border-box;height:44px;flex:none;display:flex;align-items:center;gap:12px;padding:0 14px;background:var(--bg-surface);border:1px solid var(--border-default);border-radius:var(--radius-window) var(--radius-window) 0 0}
  .dr-lights{display:flex;gap:8px}.dr-lights i{width:12px;height:12px;border-radius:50%;display:block}
  .dr-tc{flex:1;display:flex;align-items:center;justify-content:center;gap:8px}
  .dr-tc .nm{font-size:var(--text-label);font-weight:600;color:var(--text-secondary)}
  .dr-tr{display:flex;align-items:center;gap:8px}
  .dr-badge{border-radius:var(--radius-pill);box-shadow:var(--focus-ring)}  /* the open anchor, highlighted */
  .dr-barbody{position:relative;box-sizing:border-box;height:108px;display:flex;overflow:hidden;
    border-left:1px solid var(--border-default);border-right:1px solid var(--border-default);border-bottom:1px solid var(--border-default);border-radius:0 0 var(--radius-window) var(--radius-window)}
  .dr-ghost-side{width:328px;flex:none;background:var(--bg-subtle);border-right:1px solid var(--border-subtle)}
  .dr-ghost-main{flex:1;background:var(--bg-base)}
  .dr-scrim{position:absolute;inset:0;background:var(--bg-overlay);backdrop-filter:blur(2px)}
  /* the popover */
  .dr-pop{position:relative;z-index:4;align-self:flex-end;width:404px;margin:-96px 13px 0;display:flex;flex-direction:column;
    background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-xl);
    box-shadow:0 24px 60px rgba(0,0,0,.66)}
  .dr-caret{position:absolute;z-index:5;top:-7px;right:58px;width:13px;height:13px;background:var(--bg-raised);
    border-left:1px solid var(--border-default);border-top:1px solid var(--border-default);transform:rotate(45deg)}
  .dr-hd{flex:none;padding:13px 13px 12px;border-bottom:1px solid var(--border-subtle)}
  .dr-hd__top{display:flex;align-items:center;gap:9px}
  .dr-hd__icon{width:26px;height:26px;border-radius:8px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none;color:var(--accent-text)}
  .dr-hd__t{font-size:14px;font-weight:700;letter-spacing:-.01em;color:var(--text-primary);flex:1}
  .dr-hd__sub{display:flex;align-items:center;gap:8px;margin-top:11px;white-space:nowrap}
  .dr-hd__tally{font-size:12.5px;color:var(--text-secondary)}
  .dr-hd__tally b{color:var(--text-primary);font-weight:700}
  .dr-hd__tally .c{font-family:var(--font-mono)}
  .dr-hd__tally .seats{font-family:var(--font-mono);font-size:11px;color:var(--text-faint)}
  .dr-hd__checked{margin-left:auto;display:inline-flex;align-items:center;gap:5px;font-family:var(--font-mono);font-size:10.5px;color:var(--text-faint)}
  .dr-hd__checked svg{flex:none}
  .dr-body{flex:1;min-height:0;padding:4px 13px 12px;display:flex;flex-direction:column;gap:8px}
  .dr-foot{flex:none;border-top:1px solid var(--border-subtle);padding:9px 13px;display:flex;align-items:center;justify-content:center;background:var(--bg-surface);border-radius:0 0 var(--radius-xl) var(--radius-xl)}
  .dr-openfull{display:inline-flex;align-items:center;gap:7px;font-size:12px;font-weight:500;color:var(--text-muted);background:none;border:none;cursor:pointer;font-family:inherit;padding:4px 8px;border-radius:var(--radius-sm)}
  .dr-openfull:hover{color:var(--text-primary);background:var(--bg-hover)}
  .dr-note{width:1120px;max-width:100%;margin-top:20px;font-size:12px;color:var(--text-faint);font-family:var(--font-mono);text-align:center}`;
  document.head.appendChild(s);
})();

/* ---------- doctor roster (live re-check state) ----------
   Same shapes/states as setup.jsx; here Codex is mid-poll after a sign-in,
   demonstrating the waiting → green-flip loop inside the running app. */
const DR_ROSTER = {
  ready: [window.SU_ROSTER.ready[0]],
  step: [
    { id: 'codex', name: 'Codex', icon: 'terminal', route: 'via codex', version: 'codex 0.9.1', state: 'waiting' },
    window.SU_ROSTER.step[1], // Antigravity — needs a path
  ],
  add: [window.SU_ROSTER.add[0]], // Grok — not installed
};

function CouncilHealthPopover() {
  return RD.createElement('div', { className: 'dr-pop' },
    RD.createElement('div', { className: 'dr-caret' }),
    RD.createElement('div', { className: 'dr-hd' },
      RD.createElement('div', { className: 'dr-hd__top' },
        RD.createElement('span', { className: 'dr-hd__icon' }, RD.createElement(DI, { name: 'shield', size: 15 })),
        RD.createElement('span', { className: 'dr-hd__t' }, 'Council health'),
        RD.createElement(DB, { variant: 'ghost', size: 'sm', iconLeft: RD.createElement(DI, { name: 'rotate-cw', size: 13 }) }, 'Re-check'),
        RD.createElement(DIB, { variant: 'ghost', size: 'sm', label: 'Close' }, RD.createElement(DI, { name: 'x', size: 16 }))),
      RD.createElement('div', { className: 'dr-hd__sub' },
        RD.createElement('span', { className: 'dr-hd__tally' },
          RD.createElement('b', null, RD.createElement('span', { className: 'c' }, '1'), ' of ', RD.createElement('span', { className: 'c' }, '4'), ' tools ready'),
          RD.createElement('span', { className: 'seats' }, ' · 2 seats')),
        RD.createElement('span', { className: 'dr-hd__checked' }, RD.createElement(DI, { name: 'clock', size: 12 }), 'checked 2s ago'))),
    RD.createElement('div', { className: 'dr-body' },
      RD.createElement(DGroupLabel, { count: '1' }, 'Ready'),
      DR_ROSTER.ready.map((t) => RD.createElement(DSetupCard, { key: t.id, tool: t, compact: true })),
      RD.createElement(DGroupLabel, { count: '2' }, 'Needs a step'),
      DR_ROSTER.step.map((t) => RD.createElement(DSetupCard, { key: t.id, tool: t })),
      RD.createElement(DGroupLabel, { count: '1' }, 'Available to add'),
      DR_ROSTER.add.map((t) => RD.createElement(DSetupCard, { key: t.id, tool: t }))),
    RD.createElement('div', { className: 'dr-foot' },
      RD.createElement('button', { className: 'dr-openfull' }, RD.createElement(DI, { name: 'maximize', size: 13 }), 'Open full setup')));
}

function DoctorScreen() {
  return RD.createElement('div', { className: 'dr-page' },
    RD.createElement('div', { className: 'dr-frame' },
      RD.createElement('div', { className: 'dr-bar' },
        RD.createElement('div', { className: 'dr-lights' },
          RD.createElement('i', { style: { background: '#FF5F57' } }), RD.createElement('i', { style: { background: '#FEBC2E' } }), RD.createElement('i', { style: { background: '#28C840' } })),
        RD.createElement('div', { className: 'dr-tc' }, RD.createElement(DLiveMark, { size: 16 }), RD.createElement('span', { className: 'nm' }, 'allnighter')),
        RD.createElement('div', { className: 'dr-tr' },
          RD.createElement('span', { className: 'dr-badge' }, RD.createElement(DBadge, { tone: 'warning', dot: true, mono: true }, '1/4 ready')),
          RD.createElement(DIB, { variant: 'ghost', size: 'sm', label: 'Settings' }, RD.createElement(DI, { name: 'settings-2' })))),
      RD.createElement('div', { className: 'dr-barbody' },
        RD.createElement('div', { className: 'dr-ghost-side' }),
        RD.createElement('div', { className: 'dr-ghost-main' }),
        RD.createElement('div', { className: 'dr-scrim' })),
      RD.createElement(CouncilHealthPopover, null),
      RD.createElement('div', { className: 'dr-note' }, 'Council health — opened from the title-bar health badge · compact in-app re-check surface (scrolls in the real window)')));
}
window.DoctorScreen = DoctorScreen;
