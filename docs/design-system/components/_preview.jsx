// @ds-adherence-ignore -- runtime mirror of the bundled components for live
// rendering in specimen cards + the Council UI kit (the generated _ds_bundle.js
// is the source of truth for real consumers). Window globals, no exports.

(function () {
  if (typeof document === 'undefined' || document.getElementById('al-preview-css')) return;
  const s = document.createElement('style'); s.id = 'al-preview-css';
  s.textContent = `
  .al-btn{--h:30px;display:inline-flex;align-items:center;justify-content:center;gap:7px;height:var(--h);padding:0 14px;border-radius:var(--radius-sm);border:1px solid transparent;font-family:var(--font-sans);font-size:var(--text-body);font-weight:600;line-height:1;cursor:pointer;white-space:nowrap;transition:var(--transition-control);user-select:none}
  .al-btn:focus-visible{outline:none;box-shadow:var(--focus-ring)}
  .al-btn:disabled{opacity:.45;cursor:not-allowed}
  .al-btn--sm{--h:24px;padding:0 10px;font-size:var(--text-label)}
  .al-btn--lg{--h:36px;padding:0 18px;font-size:var(--text-body-lg)}
  .al-btn--block{width:100%}
  .al-btn__i{display:inline-flex;flex:none}.al-btn__i svg{width:1em;height:1em;display:block}
  .al-btn--primary{background:var(--accent);color:var(--text-on-amber)}
  .al-btn--primary:hover:not(:disabled){background:var(--accent-hover);box-shadow:var(--glow-amber-sm)}
  .al-btn--primary:active:not(:disabled){background:var(--accent-press);transform:scale(.97)}
  .al-btn--secondary{background:var(--bg-surface);color:var(--text-primary);border-color:var(--border-default)}
  .al-btn--secondary:hover:not(:disabled){background:var(--bg-hover);border-color:var(--border-strong)}
  .al-btn--secondary:active:not(:disabled){transform:scale(.97)}
  .al-btn--ghost{background:transparent;color:var(--text-secondary)}
  .al-btn--ghost:hover:not(:disabled){background:var(--bg-hover);color:var(--text-primary)}
  .al-btn--ghost:active:not(:disabled){transform:scale(.97)}
  .al-btn--danger{background:var(--danger);color:#220707}
  .al-btn--danger:hover:not(:disabled){background:var(--red-400);box-shadow:var(--glow-red)}
  .al-iconbtn{--sz:30px;display:inline-flex;align-items:center;justify-content:center;width:var(--sz);height:var(--sz);border-radius:var(--radius-sm);border:1px solid transparent;background:transparent;color:var(--text-secondary);cursor:pointer;transition:var(--transition-control);flex:none}
  .al-iconbtn:focus-visible{outline:none;box-shadow:var(--focus-ring)}
  .al-iconbtn:disabled{opacity:.4;cursor:not-allowed}
  .al-iconbtn svg{width:18px;height:18px;display:block}
  .al-iconbtn--sm{--sz:24px}.al-iconbtn--sm svg{width:15px;height:15px}
  .al-iconbtn--lg{--sz:36px}.al-iconbtn--lg svg{width:20px;height:20px}
  .al-iconbtn--ghost:hover:not(:disabled){background:var(--bg-hover);color:var(--text-primary)}
  .al-iconbtn--outline{border-color:var(--border-default);background:var(--bg-surface)}
  .al-iconbtn--outline:hover:not(:disabled){background:var(--bg-hover);border-color:var(--border-strong);color:var(--text-primary)}
  .al-iconbtn--solid{background:var(--bg-active);color:var(--text-primary)}
  .al-iconbtn--solid:hover:not(:disabled){background:var(--bg-hover)}
  .al-iconbtn--accent{background:var(--accent-surface);color:var(--accent-text);border-color:var(--accent-border)}
  .al-iconbtn:active:not(:disabled){transform:scale(.93)}
  .al-badge{display:inline-flex;align-items:center;gap:5px;height:20px;padding:0 8px;border-radius:var(--radius-xs);font-family:var(--font-sans);font-size:var(--text-caption);font-weight:600;line-height:1;border:1px solid transparent;white-space:nowrap}
  .al-badge--mono{font-family:var(--font-mono);font-weight:500}
  .al-badge__dot{width:6px;height:6px;border-radius:50%;flex:none}
  .al-badge--neutral{background:var(--bg-active);color:var(--text-secondary);border-color:var(--border-subtle)}
  .al-badge--accent{background:var(--accent-surface);color:var(--accent-text);border-color:var(--accent-border)}
  .al-badge--positive{background:var(--success-surface);color:var(--green-400)}
  .al-badge--danger{background:var(--danger-surface);color:var(--red-400)}
  .al-badge--info{background:var(--info-surface);color:var(--blue-400)}
  .al-badge--warning{background:var(--warning-surface);color:var(--yellow-400)}
  .al-card{background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-lg);box-shadow:var(--shadow-sm);color:var(--text-primary)}
  .al-card--pad{padding:16px}
  .al-card--flush{background:var(--bg-surface)}
  .al-card--accent{border-color:var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.06),transparent 60%),var(--bg-raised)}
  .al-card--interactive{cursor:pointer;transition:transform var(--duration-fast) var(--ease-out),box-shadow var(--duration-fast) var(--ease-out),border-color var(--duration-fast) var(--ease-out)}
  .al-card--interactive:hover{transform:translateY(-2px);box-shadow:var(--shadow-md);border-color:var(--border-default)}
  .al-field{display:flex;flex-direction:column;gap:6px;font-family:var(--font-sans)}
  .al-field__label{font-size:var(--text-label);font-weight:500;color:var(--text-secondary)}
  .al-field__req{color:var(--accent-text);margin-left:2px}
  .al-input{display:flex;align-items:center;gap:7px;height:30px;padding:0 10px;background:var(--bg-input);border:1px solid var(--border-default);border-radius:var(--radius-sm);transition:var(--transition-control)}
  .al-input:focus-within{border-color:var(--accent-border);box-shadow:var(--focus-ring)}
  .al-input--error{border-color:var(--danger)}.al-input--lg{height:36px}
  .al-input__prefix,.al-input__suffix{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint);flex:none}
  .al-input input{flex:1;min-width:0;background:transparent;border:none;outline:none;color:var(--text-primary);font-size:var(--text-body);font-family:inherit}
  .al-input input::placeholder{color:var(--text-faint)}
  .al-input--mono input{font-family:var(--font-mono);font-size:var(--text-mono)}
  .al-field__hint{font-size:var(--text-caption);color:var(--text-muted)}.al-field__hint--error{color:var(--red-400)}
  .al-ta__box{position:relative;background:var(--bg-input);border:1px solid var(--border-default);border-radius:var(--radius-md);transition:var(--transition-control)}
  .al-ta__box:focus-within{border-color:var(--accent-border);box-shadow:var(--focus-ring)}
  .al-ta__box textarea{display:block;width:100%;box-sizing:border-box;background:transparent;border:none;outline:none;resize:vertical;color:var(--text-primary);font-family:var(--font-sans);font-size:var(--text-body);line-height:var(--leading-normal);padding:10px 12px}
  .al-ta--mono textarea{font-family:var(--font-mono);font-size:var(--text-mono)}
  .al-ta__box textarea::placeholder{color:var(--text-faint)}
  .al-ta__count{position:absolute;right:10px;bottom:8px;font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint);pointer-events:none}
  .al-switch{display:flex;align-items:flex-start;gap:10px;font-family:var(--font-sans);cursor:pointer;user-select:none}
  .al-switch--disabled{opacity:.45;cursor:not-allowed}
  .al-switch__track{position:relative;flex:none;width:34px;height:20px;border-radius:var(--radius-pill);background:var(--ink-600);transition:background var(--duration-fast) var(--ease-out);margin-top:1px}
  .al-switch__thumb{position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:50%;background:#fff;box-shadow:var(--shadow-xs);transition:transform var(--duration-normal) var(--ease-spring)}
  .al-switch input{position:absolute;opacity:0;width:0;height:0}
  .al-switch input:checked + .al-switch__track{background:var(--accent)}
  .al-switch input:checked + .al-switch__track .al-switch__thumb{transform:translateX(14px)}
  .al-switch input:focus-visible + .al-switch__track{box-shadow:var(--focus-ring)}
  .al-switch__text{display:flex;flex-direction:column;gap:2px}
  .al-switch__label{font-size:var(--text-body);font-weight:500;color:var(--text-primary);line-height:1.3}
  .al-switch__desc{font-size:var(--text-caption);color:var(--text-muted)}
  .al-tabs--segmented{display:inline-flex;gap:2px;padding:3px;background:var(--bg-subtle);border:1px solid var(--border-subtle);border-radius:var(--radius-md)}
  .al-tabs--segmented .al-tab{height:24px;padding:0 12px;border-radius:var(--radius-sm);border:none;background:transparent;color:var(--text-muted);font-size:var(--text-label);font-weight:500;cursor:pointer;transition:var(--transition-control);display:inline-flex;align-items:center;gap:6px;font-family:var(--font-sans)}
  .al-tabs--segmented .al-tab:hover{color:var(--text-primary)}
  .al-tabs--segmented .al-tab[data-active="true"]{background:var(--bg-active);color:var(--text-primary);box-shadow:var(--shadow-xs)}
  .al-tabs--underline{display:flex;gap:18px;border-bottom:1px solid var(--border-subtle)}
  .al-tabs--underline .al-tab{height:34px;padding:0 1px;border:none;background:transparent;color:var(--text-muted);font-size:var(--text-body);font-weight:500;cursor:pointer;position:relative;transition:color var(--duration-fast) var(--ease-out);display:inline-flex;align-items:center;gap:6px;font-family:var(--font-sans)}
  .al-tabs--underline .al-tab:hover{color:var(--text-primary)}
  .al-tabs--underline .al-tab[data-active="true"]{color:var(--text-primary)}
  .al-tabs--underline .al-tab[data-active="true"]::after{content:"";position:absolute;left:0;right:0;bottom:-1px;height:2px;background:var(--accent);border-radius:2px}
  .al-tab__count{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .al-tab:focus-visible{outline:none;box-shadow:var(--focus-ring)}
  .al-tab{white-space:nowrap}
  .al-status{display:inline-flex;align-items:center;gap:6px;height:20px;padding:0 8px 0 7px;border-radius:var(--radius-pill);font-family:var(--font-sans);font-size:var(--text-caption);font-weight:600;line-height:1;white-space:nowrap;border:1px solid transparent}
  .al-status__dot{width:7px;height:7px;border-radius:50%;flex:none}
  .al-status--running .al-status__dot{animation:al-statusblink 1.1s var(--ease-in-out) infinite}
  @keyframes al-statusblink{0%,100%{opacity:1}50%{opacity:.3}}
  .al-status--queued{background:var(--bg-active);color:var(--text-muted)}
  .al-status--running{background:var(--info-surface);color:var(--blue-400)}
  .al-status--done{background:var(--success-surface);color:var(--green-400)}
  .al-status--failed{background:var(--danger-surface);color:var(--red-400)}
  .al-status--timedout{background:var(--warning-surface);color:var(--yellow-400)}
  .al-worker{display:flex;align-items:center;gap:11px;padding:11px 12px;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-md);transition:var(--transition-control);font-family:var(--font-sans);text-align:left;width:100%;box-sizing:border-box}
  .al-worker--selectable{cursor:pointer}
  .al-worker--selectable:hover{border-color:var(--border-default);background:var(--bg-hover)}
  .al-worker--selected{border-color:var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.05),transparent),var(--bg-raised)}
  .al-worker--running{border-color:rgba(91,157,255,.30)}
  .al-worker__glyph{width:30px;height:30px;border-radius:var(--radius-sm);background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none;overflow:hidden}
  .al-worker__glyph img{width:18px;height:18px}
  .al-worker__main{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
  .al-worker__name{font-size:var(--text-body);font-weight:600;color:var(--text-primary);line-height:1.25;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .al-worker__model{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .al-worker__trail{display:flex;align-items:center;gap:10px;flex:none}
  .al-worker__meta{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-muted)}
  .al-worker__check{width:18px;height:18px;border-radius:var(--radius-xs);border:1.5px solid var(--border-strong);display:flex;align-items:center;justify-content:center;flex:none;transition:var(--transition-control)}
  .al-worker--selected .al-worker__check{background:var(--accent);border-color:var(--accent)}
  .al-worker__check svg{width:12px;height:12px;color:var(--text-on-amber);opacity:0}
  .al-worker--selected .al-worker__check svg{opacity:1}
  .al-select{position:relative}
  .al-select__trigger{display:flex;align-items:center;gap:8px;width:100%;height:30px;padding:0 10px;background:var(--bg-input);border:1px solid var(--border-default);border-radius:var(--radius-sm);color:var(--text-primary);font-family:var(--font-sans);font-size:var(--text-body);cursor:pointer;transition:var(--transition-control);text-align:left}
  .al-select__trigger:hover{border-color:var(--border-strong)}
  .al-select__trigger.is-open,.al-select__trigger:focus-visible{outline:none;border-color:var(--accent-border);box-shadow:var(--focus-ring)}
  .al-select__trigger--mono{font-family:var(--font-mono);font-size:var(--text-mono)}
  .al-select__val{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .al-select__ph{color:var(--text-faint)}
  .al-select__chev{flex:none;color:var(--text-faint);transition:transform var(--duration-fast) var(--ease-out)}
  .al-select__trigger.is-open .al-select__chev{transform:rotate(180deg)}
  .al-select__menu{position:absolute;z-index:50;top:calc(100% + 5px);left:0;right:0;padding:5px;background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-md);box-shadow:var(--shadow-md);max-height:240px;overflow:auto}
  .al-select__opt{display:flex;align-items:center;gap:8px;width:100%;height:28px;padding:0 8px;border:none;background:transparent;border-radius:var(--radius-sm);color:var(--text-secondary);font-family:inherit;font-size:var(--text-body);cursor:pointer;text-align:left;transition:var(--transition-control)}
  .al-select__opt:hover{background:var(--bg-hover);color:var(--text-primary)}
  .al-select__opt.is-sel{color:var(--text-primary)}
  .al-select__opt .al-select__lbl{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .al-select__opt svg{flex:none;color:var(--accent-text)}
  .al-menu{position:relative;display:inline-flex}.al-menu__trigger{display:inline-flex}
  .al-menu__pop{position:absolute;z-index:60;top:calc(100% + 6px);min-width:184px;padding:5px;background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-md);box-shadow:var(--shadow-md)}
  .al-menu__pop--start{left:0}.al-menu__pop--end{right:0}
  .al-menu__item{display:flex;align-items:center;gap:9px;width:100%;height:30px;padding:0 9px;border:none;background:transparent;border-radius:var(--radius-sm);color:var(--text-secondary);font-family:var(--font-sans);font-size:var(--text-body);cursor:pointer;text-align:left;transition:var(--transition-control)}
  .al-menu__item:hover{background:var(--bg-hover);color:var(--text-primary)}
  .al-menu__item.is-danger{color:var(--red-400)}.al-menu__item.is-danger:hover{background:var(--danger-surface)}
  .al-menu__ic{display:inline-flex;flex:none;color:var(--text-faint)}.al-menu__item:hover .al-menu__ic{color:inherit}.al-menu__ic svg{width:15px;height:15px;display:block}
  .al-menu__lbl{flex:1}.al-menu__kbd{font-family:var(--font-mono);font-size:10px;color:var(--text-faint)}
  .al-menu__div{height:1px;background:var(--border-subtle);margin:5px 4px}
  .al-dialog__scrim{position:fixed;inset:0;z-index:100;background:var(--bg-overlay);backdrop-filter:blur(3px);display:flex;align-items:center;justify-content:center;padding:24px}
  .al-dialog{width:100%;background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-2xl);box-shadow:var(--shadow-xl)}
  .al-dialog--sm{max-width:380px}.al-dialog--md{max-width:480px}.al-dialog--lg{max-width:640px}
  .al-dialog__head{display:flex;align-items:flex-start;gap:12px;padding:20px 20px 0}
  .al-dialog__headic{width:34px;height:34px;border-radius:var(--radius-md);flex:none;display:flex;align-items:center;justify-content:center}
  .al-dialog__htext{flex:1;min-width:0}
  .al-dialog__title{font-family:var(--font-display);font-size:var(--text-h3);font-weight:700;color:var(--text-primary);letter-spacing:-.01em}
  .al-dialog__desc{font-size:var(--text-body);color:var(--text-muted);margin-top:5px;line-height:1.5}
  .al-dialog__close{margin-left:auto;flex:none}
  .al-dialog__body{padding:16px 20px 0}
  .al-dialog__foot{display:flex;justify-content:flex-end;gap:8px;padding:20px}
  .al-toast{display:flex;align-items:flex-start;gap:11px;width:340px;max-width:100%;padding:13px 13px 13px 14px;background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-lg);box-shadow:var(--shadow-lg);font-family:var(--font-sans)}
  .al-toast--accent{border-color:var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.07),transparent 60%),var(--bg-raised)}
  .al-toast--positive{border-color:rgba(63,209,139,.32)}.al-toast--danger{border-color:rgba(247,107,107,.32)}
  .al-toast__ic{flex:none;width:24px;height:24px;display:flex;align-items:center;justify-content:center;margin-top:1px}.al-toast__ic svg{width:18px;height:18px}
  .al-toast__body{flex:1;min-width:0}
  .al-toast__title{font-size:var(--text-body);font-weight:600;color:var(--text-primary);line-height:1.35}
  .al-toast__desc{font-size:var(--text-caption);color:var(--text-muted);margin-top:2px;line-height:1.45}
  .al-toast__action{flex:none;align-self:center}.al-toast__close{flex:none;margin:-2px -2px 0 0}`;
  document.head.appendChild(s);
})();

const R = window.React;

/* ---------- Icon (curated Lucide path data, dependency-free) ---------- */
const ICONS = {
  play: '<polygon points="6 3 20 12 6 21 6 3"/>',
  square: '<rect width="14" height="14" x="5" y="5" rx="2"/>',
  copy: '<rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
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
  clock: '<circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/>',
  activity: '<path d="M22 12h-4l-3 9L9 3l-3 9H2"/>',
  zap: '<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/>',
  'file-text': '<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/><path d="M16 13H8"/><path d="M16 17H8"/><path d="M10 9H8"/>',
  users: '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
  search: '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
  moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
  history: '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/><path d="M12 7v5l4 2"/>',
  shield: '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>',
  gauge: '<path d="m12 14 4-4"/><path d="M3.34 19a10 10 0 1 1 17.32 0"/>',
  compare: '<circle cx="18" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><path d="M13 6h3a2 2 0 0 1 2 2v7"/><path d="M11 18H8a2 2 0 0 1-2-2V9"/>',
  folder: '<path d="M20 20a2 2 0 0 0 2-2V8a2 2 0 0 0-2-2h-7.9a2 2 0 0 1-1.69-.9L9.6 3.9A2 2 0 0 0 7.93 3H4a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2Z"/>',
  'circle-check': '<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>',
  scale: '<path d="m16 16 3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1Z"/><path d="m2 16 3-8 3 8c-.87.65-1.92 1-3 1s-2.13-.35-3-1Z"/><path d="M7 21h10"/><path d="M12 3v18"/><path d="M3 7h2c2 0 5-1 7-2 2 1 5 2 7 2h2"/>',
  flask: '<path d="M10 2v7.31"/><path d="M14 9.3V1.99"/><path d="M8.5 2h7"/><path d="M14 9.3a6.5 6.5 0 1 1-4 0"/><path d="M5.58 16.5h12.85"/>',
  list: '<path d="M8 6h13"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M3 6h.01"/><path d="M3 12h.01"/><path d="M3 18h.01"/>',
};
function Icon({ name, size = 20, stroke = 2, style, ...rest }) {
  return R.createElement('svg', {
    width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor',
    strokeWidth: stroke, strokeLinecap: 'round', strokeLinejoin: 'round',
    style, dangerouslySetInnerHTML: { __html: ICONS[name] || '' }, ...rest,
  });
}
function BrandIcon({ slug, color = 'E1E5F0', size = 18, ...rest }) {
  return R.createElement('img', { src: `https://cdn.simpleicons.org/${slug}/${color}`, width: size, height: size, alt: '', ...rest });
}

/* ---------- primitives ---------- */
function cx() { return Array.prototype.filter.call(arguments, Boolean).join(' '); }

function Button({ variant = 'primary', size = 'md', iconLeft, iconRight, block, disabled, children, className, ...rest }) {
  return R.createElement('button', { className: cx('al-btn', 'al-btn--' + variant, size !== 'md' && 'al-btn--' + size, block && 'al-btn--block', className), disabled, ...rest },
    iconLeft && R.createElement('span', { className: 'al-btn__i' }, iconLeft),
    children != null && R.createElement('span', null, children),
    iconRight && R.createElement('span', { className: 'al-btn__i' }, iconRight));
}
function IconButton({ variant = 'ghost', size = 'md', label, disabled, children, className, ...rest }) {
  return R.createElement('button', { className: cx('al-iconbtn', 'al-iconbtn--' + variant, size !== 'md' && 'al-iconbtn--' + size, className), 'aria-label': label, title: label, disabled, ...rest }, children);
}
const DOT = { neutral: 'var(--ink-400)', accent: 'var(--accent)', positive: 'var(--green-500)', danger: 'var(--red-500)', info: 'var(--blue-500)', warning: 'var(--yellow-500)' };
function Badge({ tone = 'neutral', dot = false, mono = false, children, className, ...rest }) {
  return R.createElement('span', { className: cx('al-badge', 'al-badge--' + tone, mono && 'al-badge--mono', className), ...rest },
    dot && R.createElement('span', { className: 'al-badge__dot', style: { background: DOT[tone] } }), children);
}
function Card({ variant = 'default', pad = true, interactive = false, as = 'div', children, className, ...rest }) {
  return R.createElement(as, { className: cx('al-card', pad && 'al-card--pad', variant !== 'default' && 'al-card--' + variant, interactive && 'al-card--interactive', className), ...rest }, children);
}
function Input({ label, hint, error, required, prefixText, suffix, size = 'md', mono, id, className, ...rest }) {
  const fid = id || ('al-' + Math.random().toString(36).slice(2, 8));
  return R.createElement('div', { className: cx('al-field', className) },
    label && R.createElement('label', { className: 'al-field__label', htmlFor: fid }, label, required && R.createElement('span', { className: 'al-field__req' }, '*')),
    R.createElement('div', { className: cx('al-input', size === 'lg' && 'al-input--lg', mono && 'al-input--mono', error && 'al-input--error') },
      prefixText && R.createElement('span', { className: 'al-input__prefix' }, prefixText),
      R.createElement('input', { id: fid, ...rest }),
      suffix && R.createElement('span', { className: 'al-input__suffix' }, suffix)),
    (error || hint) && R.createElement('span', { className: 'al-field__hint' + (error ? ' al-field__hint--error' : '') }, error || hint));
}
function Textarea({ label, hint, rows = 4, maxLength, showCount, mono, value, defaultValue, onChange, id, className, ...rest }) {
  const fid = id || ('al-' + Math.random().toString(36).slice(2, 8));
  const [val, setVal] = R.useState(defaultValue || '');
  const count = (value !== undefined ? value : val).length;
  return R.createElement('div', { className: cx('al-field', className) },
    label && R.createElement('label', { className: 'al-field__label', htmlFor: fid }, label),
    R.createElement('div', { className: cx('al-ta__box', mono && 'al-ta--mono') },
      R.createElement('textarea', { id: fid, rows, maxLength, value, defaultValue, onChange: (e) => { setVal(e.target.value); onChange && onChange(e); }, ...rest }),
      showCount && maxLength && R.createElement('span', { className: 'al-ta__count' }, count + '/' + maxLength)),
    hint && R.createElement('span', { className: 'al-field__hint' }, hint));
}
function Switch({ label, description, checked, defaultChecked, disabled, onChange, className, ...rest }) {
  return R.createElement('label', { className: cx('al-switch', disabled && 'al-switch--disabled', className) },
    R.createElement('input', { type: 'checkbox', checked, defaultChecked, disabled, onChange, ...rest }),
    R.createElement('span', { className: 'al-switch__track' }, R.createElement('span', { className: 'al-switch__thumb' })),
    (label || description) && R.createElement('span', { className: 'al-switch__text' },
      label && R.createElement('span', { className: 'al-switch__label' }, label),
      description && R.createElement('span', { className: 'al-switch__desc' }, description)));
}
function Tabs({ variant = 'segmented', items = [], value, defaultValue, onChange, className, ...rest }) {
  const [internal, setInternal] = R.useState(defaultValue != null ? defaultValue : (items[0] && items[0].value));
  const active = value !== undefined ? value : internal;
  return R.createElement('div', { className: cx('al-tabs', 'al-tabs--' + variant, className), role: 'tablist', ...rest },
    items.map((it) => R.createElement('button', { key: it.value, role: 'tab', className: 'al-tab', 'data-active': active === it.value, 'aria-selected': active === it.value, onClick: () => { setInternal(it.value); onChange && onChange(it.value); } },
      it.label, it.count != null && R.createElement('span', { className: 'al-tab__count' }, it.count))));
}
const SMETA = { queued: { label: 'Queued', dot: 'var(--ink-400)' }, running: { label: 'Running', dot: 'var(--blue-500)' }, done: { label: 'Done', dot: 'var(--green-500)' }, failed: { label: 'Failed', dot: 'var(--red-500)' }, timedout: { label: 'Timed out', dot: 'var(--yellow-500)' } };
function StatusPill({ status = 'queued', children, className, ...rest }) {
  const m = SMETA[status] || SMETA.queued;
  return R.createElement('span', { className: cx('al-status', 'al-status--' + status, className), ...rest },
    R.createElement('span', { className: 'al-status__dot', style: { background: m.dot } }), children || m.label);
}
function WorkerChip({ name, model, glyph, status, selectable = false, selected = false, meta, onToggle, className, ...rest }) {
  const Tag = selectable ? 'button' : 'div';
  return R.createElement(Tag, { className: cx('al-worker', selectable && 'al-worker--selectable', selected && 'al-worker--selected', status === 'running' && 'al-worker--running', className), onClick: selectable ? onToggle : undefined, type: selectable ? 'button' : undefined, ...rest },
    R.createElement('span', { className: 'al-worker__glyph' }, glyph),
    R.createElement('span', { className: 'al-worker__main' },
      R.createElement('span', { className: 'al-worker__name' }, name),
      model && R.createElement('span', { className: 'al-worker__model' }, model)),
    R.createElement('span', { className: 'al-worker__trail' },
      meta && R.createElement('span', { className: 'al-worker__meta' }, meta),
      status && R.createElement(StatusPill, { status }),
      selectable && R.createElement('span', { className: 'al-worker__check' }, R.createElement(Icon, { name: 'check', size: 12, stroke: 3.5 }))));
}

Object.assign(window, { Icon, BrandIcon, Button, IconButton, Badge, Card, Input, Textarea, Switch, Tabs, StatusPill, WorkerChip });

/* ---------- Select ---------- */
function Select({ label, options = [], value, defaultValue, onChange, placeholder = 'Select…', size = 'md', mono, leading, disabled, className, ...rest }) {
  const [open, setOpen] = R.useState(false);
  const [internal, setInternal] = R.useState(defaultValue);
  const ref = R.useRef(null);
  const val = value !== undefined ? value : internal;
  R.useEffect(() => {
    if (!open) return;
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    document.addEventListener('mousedown', h); return () => document.removeEventListener('mousedown', h);
  }, [open]);
  const sel = options.find((o) => o.value === val);
  const pick = (v) => { setInternal(v); onChange && onChange(v); setOpen(false); };
  const chev = R.createElement('svg', { className: 'al-select__chev', width: 15, height: 15, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 2, strokeLinecap: 'round', strokeLinejoin: 'round', dangerouslySetInnerHTML: { __html: '<path d="m6 9 6 6 6-6"/>' } });
  return R.createElement('div', { className: cx('al-field', className) },
    label && R.createElement('label', { className: 'al-field__label' }, label),
    R.createElement('div', { className: 'al-select', ref },
      R.createElement('button', { type: 'button', disabled, onClick: () => setOpen((o) => !o), className: cx('al-select__trigger', mono && 'al-select__trigger--mono', open && 'is-open'), ...rest },
        leading, R.createElement('span', { className: 'al-select__val' + (sel ? '' : ' al-select__ph') }, sel ? sel.label : placeholder), chev),
      open && R.createElement('div', { className: 'al-select__menu', role: 'listbox' },
        options.map((o) => R.createElement('button', { key: o.value, type: 'button', role: 'option', 'aria-selected': o.value === val, className: 'al-select__opt' + (o.value === val ? ' is-sel' : ''), onClick: () => pick(o.value) },
          R.createElement('span', { className: 'al-select__lbl' }, o.label),
          o.value === val && R.createElement(Icon, { name: 'check', size: 14, stroke: 2.5 }))))));
}

/* ---------- Menu ---------- */
function Menu({ trigger, items = [], align = 'start', className, ...rest }) {
  const [open, setOpen] = R.useState(false);
  const ref = R.useRef(null);
  R.useEffect(() => {
    if (!open) return;
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    const k = (e) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('mousedown', h); document.addEventListener('keydown', k);
    return () => { document.removeEventListener('mousedown', h); document.removeEventListener('keydown', k); };
  }, [open]);
  return R.createElement('div', { className: cx('al-menu', className), ref, ...rest },
    R.createElement('span', { className: 'al-menu__trigger', onClick: () => setOpen((o) => !o) }, trigger),
    open && R.createElement('div', { className: 'al-menu__pop al-menu__pop--' + align, role: 'menu' },
      items.map((it, i) => it.divider
        ? R.createElement('div', { className: 'al-menu__div', key: i })
        : R.createElement('button', { key: i, role: 'menuitem', className: 'al-menu__item' + (it.danger ? ' is-danger' : ''), onClick: () => { it.onClick && it.onClick(); setOpen(false); } },
          it.icon && R.createElement('span', { className: 'al-menu__ic' }, it.icon),
          R.createElement('span', { className: 'al-menu__lbl' }, it.label),
          it.kbd && R.createElement('span', { className: 'al-menu__kbd' }, it.kbd)))));
}

/* ---------- Dialog ---------- */
function Dialog({ open, onClose, title, description, icon, iconTone, size = 'md', footer, showClose = true, children }) {
  R.useEffect(() => {
    if (!open) return;
    const h = (e) => { if (e.key === 'Escape') onClose && onClose(); };
    document.addEventListener('keydown', h); return () => document.removeEventListener('keydown', h);
  }, [open, onClose]);
  if (!open) return null;
  const bg = iconTone === 'danger' ? 'var(--danger-surface)' : iconTone === 'accent' ? 'var(--accent-surface)' : 'var(--bg-active)';
  const fg = iconTone === 'danger' ? 'var(--red-400)' : iconTone === 'accent' ? 'var(--accent-text)' : 'var(--text-secondary)';
  return R.createElement('div', { className: 'al-dialog__scrim', onMouseDown: (e) => { if (e.target === e.currentTarget) onClose && onClose(); } },
    R.createElement('div', { className: 'al-dialog al-dialog--' + size, role: 'dialog', 'aria-modal': 'true' },
      (title || icon || showClose) && R.createElement('div', { className: 'al-dialog__head' },
        icon && R.createElement('span', { className: 'al-dialog__headic', style: { background: bg, color: fg } }, icon),
        R.createElement('div', { className: 'al-dialog__htext' },
          title && R.createElement('div', { className: 'al-dialog__title' }, title),
          description && R.createElement('div', { className: 'al-dialog__desc' }, description)),
        showClose && R.createElement(IconButton, { variant: 'ghost', size: 'sm', label: 'Close', className: 'al-dialog__close', onClick: onClose }, R.createElement(Icon, { name: 'x', size: 16 }))),
      children && R.createElement('div', { className: 'al-dialog__body' }, children),
      footer && R.createElement('div', { className: 'al-dialog__foot' }, footer)));
}

/* ---------- Toast ---------- */
function Toast({ tone = 'default', title, description, icon, action, onClose, className, ...rest }) {
  return R.createElement('div', { className: cx('al-toast', tone !== 'default' && 'al-toast--' + tone, className), role: 'status', ...rest },
    icon && R.createElement('span', { className: 'al-toast__ic' }, icon),
    R.createElement('div', { className: 'al-toast__body' },
      title && R.createElement('div', { className: 'al-toast__title' }, title),
      description && R.createElement('div', { className: 'al-toast__desc' }, description)),
    action && R.createElement('div', { className: 'al-toast__action' }, action),
    onClose && R.createElement(IconButton, { variant: 'ghost', size: 'sm', label: 'Dismiss', className: 'al-toast__close', onClick: onClose }, R.createElement(Icon, { name: 'x', size: 14 })));
}

Object.assign(window, { Select, Menu, Dialog, Toast });
