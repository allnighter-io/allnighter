// @ds-adherence-ignore -- Allnighter home: the conversation workspace.
// Two panes — a list of work-order threads (review) + the active conversation
// with per-turn worker routing (chat / fan-out / execute). Observed state only;
// no "needs you", no overnight framing, no estimates.
const RH = window.React;
const { Button, IconButton, Badge, Card, BrandIcon } = window;
const Ic = window.DCIcon;
const HSel = window.DCSelect;
const HMenu = window.DCMenu;

(function () {
  if (document.getElementById('home-css')) return;
  const s = document.createElement('style'); s.id = 'home-css';
  s.textContent = `
  .hm-win{display:flex;flex-direction:column;width:100%;height:100%;background:var(--bg-base);border:1px solid var(--border-default);
    border-radius:var(--radius-window);overflow:hidden;box-shadow:var(--shadow-xl);font-family:var(--font-sans)}
  .hm-title{height:44px;flex:none;display:flex;align-items:center;gap:12px;padding:0 14px;background:var(--bg-surface);border-bottom:1px solid var(--border-subtle)}
  .hm-lights{display:flex;gap:8px}.hm-lights i{width:12px;height:12px;border-radius:50%;display:block}
  .hm-tc{flex:1;display:flex;align-items:center;justify-content:center;gap:8px}
  .hm-tc .nm{font-size:var(--text-label);font-weight:600;color:var(--text-secondary)}
  .hm-tc .sub{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .hm-tr{display:flex;align-items:center;gap:6px}
  .hm-body{flex:1;display:flex;min-height:0}
  /* ---- conversations sidebar ---- */
  .hm-side{width:328px;flex:none;background:var(--bg-subtle);border-right:1px solid var(--border-subtle);display:flex;flex-direction:column;min-height:0}
  .hm-side__top{padding:13px 13px 10px;display:flex;flex-direction:column;gap:10px}
  .hm-new{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;height:38px;border:none;border-radius:var(--radius-sm);
    background:var(--accent);color:var(--text-on-amber);font-family:var(--font-sans);font-size:14px;font-weight:600;cursor:pointer;transition:var(--transition-control)}
  .hm-new:hover{background:var(--accent-hover);box-shadow:var(--glow-amber-sm)}
  .hm-search{display:flex;align-items:center;gap:8px;height:32px;padding:0 10px;background:var(--bg-input);border:1px solid var(--border-default);border-radius:var(--radius-sm);color:var(--text-faint)}
  .hm-search input{flex:1;min-width:0;background:transparent;border:none;outline:none;color:var(--text-primary);font-size:13px;font-family:inherit}
  .hm-search input::placeholder{color:var(--text-faint)}
  .hm-filters{display:flex;gap:5px;flex-wrap:wrap}
  .hm-fchip{height:24px;padding:0 10px;border-radius:var(--radius-pill);border:1px solid var(--border-subtle);background:transparent;color:var(--text-muted);
    font-size:11.5px;font-weight:600;cursor:pointer;transition:var(--transition-control);font-family:var(--font-sans)}
  .hm-fchip:hover{background:var(--bg-hover);color:var(--text-secondary)}
  .hm-fchip.is-on{background:var(--bg-active);color:var(--text-primary);border-color:var(--border-default)}
  .hm-list{flex:1;overflow:auto;padding:4px 8px 16px}
  .hm-grouplbl{font-size:10px;font-weight:700;letter-spacing:.09em;text-transform:uppercase;color:var(--text-faint);padding:12px 8px 6px;display:flex;align-items:center;gap:6px}
  .hm-row{display:flex;gap:10px;width:100%;padding:9px 9px;border:none;background:transparent;border-radius:var(--radius-md);cursor:pointer;text-align:left;transition:var(--transition-control);position:relative}
  .hm-row:hover{background:var(--bg-hover)}
  .hm-row.is-active{background:var(--bg-active)}
  .hm-row.is-active::before{content:"";position:absolute;left:0;top:9px;bottom:9px;width:2.5px;border-radius:3px;background:var(--accent)}
  .hm-row__glyph{width:30px;height:30px;border-radius:var(--radius-sm);background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none;overflow:hidden;position:relative}
  .hm-row__glyph img{width:17px;height:17px}
  .hm-row__lane{position:absolute;bottom:-3px;right:-3px;width:14px;height:14px;border-radius:5px;display:flex;align-items:center;justify-content:center;border:2px solid var(--bg-subtle)}
  .hm-row__main{flex:1;min-width:0}
  .hm-row__t{font-size:13px;font-weight:600;color:var(--text-primary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .hm-row.is-idle .hm-row__t{color:var(--text-secondary);font-weight:500}
  .hm-row__meta{display:flex;align-items:center;gap:7px;margin-top:4px;min-width:0;flex-wrap:nowrap}
  .hm-row__time{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);flex:none;margin-left:auto}
  .hm-stack{display:flex;align-items:center}
  .hm-stack img,.hm-stack .hm-stack__t{width:15px;height:15px;border-radius:4px;margin-left:-4px;border:1px solid var(--bg-subtle);background:var(--bg-active);display:flex;align-items:center;justify-content:center}
  .hm-stack img:first-child,.hm-stack .hm-stack__t:first-child{margin-left:0}
  .hm-stt{display:inline-flex;align-items:center;gap:5px;font-size:11px;font-weight:600;font-family:var(--font-mono);white-space:nowrap;flex:none}
  .hm-stt__d{width:6px;height:6px;border-radius:50%;flex:none}
  .hm-stt--run .hm-stt__d{animation:hm-blink 1.1s ease-in-out infinite}
  @keyframes hm-blink{0%,100%{opacity:1}50%{opacity:.3}}
  /* ---- thread pane ---- */
  .hm-thread{flex:1;min-width:0;display:flex;flex-direction:column;background:var(--bg-base)}
  .hm-th__hd{display:flex;align-items:center;gap:12px;padding:15px 22px;border-bottom:1px solid var(--border-subtle);flex:none}
  .hm-th__t{font-size:16px;font-weight:700;letter-spacing:-.01em}
  .hm-th__tags{display:flex;align-items:center;gap:6px}
  .hm-th__route{font-family:var(--font-mono);font-size:11px;color:var(--text-faint);display:flex;align-items:center;gap:6px;white-space:nowrap;flex:none}
  .hm-turns{flex:1;overflow:auto;padding:8px 0 18px}
  .hm-turn{display:flex;gap:13px;padding:14px 22px}
  .hm-turn__g{width:28px;height:28px;border-radius:7px;flex:none;display:flex;align-items:center;justify-content:center;overflow:hidden;margin-top:1px}
  .hm-turn__g img{width:16px;height:16px}
  .hm-turn__g--you{background:var(--bg-active);color:var(--text-secondary);font-size:11px;font-weight:700;font-family:var(--font-mono)}
  .hm-turn__b{flex:1;min-width:0}
  .hm-turn__hd{display:flex;align-items:center;gap:8px;margin-bottom:6px}
  .hm-turn__who{font-size:12.5px;font-weight:600;color:var(--text-primary)}
  .hm-turn__kind{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);white-space:nowrap}
  .hm-turn__time{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-left:auto}
  .hm-turn__txt{font-size:13.5px;color:var(--text-secondary);line-height:1.55}
  .hm-turn--you .hm-turn__txt{color:var(--text-primary)}
  .hm-shot{width:46px;height:66px;border-radius:6px;border:1px solid var(--border-default);overflow:hidden;position:relative;background:var(--bg-void);margin-top:9px}
  /* fan-out turn */
  .hm-fan{margin-top:4px}
  .hm-fan__row{display:flex;gap:9px;margin-bottom:9px}
  .hm-fan__tile{position:relative;width:78px;aspect-ratio:78/120;border-radius:8px;overflow:hidden;border:1px solid var(--border-default);background:var(--bg-void);cursor:pointer;transition:var(--transition-control)}
  .hm-fan__tile:hover{transform:translateY(-2px);box-shadow:var(--shadow-sm)}
  .hm-fan__tile.is-pick{border-color:var(--accent);box-shadow:0 0 0 1px var(--accent)}
  .hm-fan__pk{position:absolute;top:4px;left:4px}
  /* result card (execution) */
  .hm-res{background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-md);padding:12px 14px;margin-top:4px}
  .hm-res__top{display:flex;align-items:center;gap:9px}
  .hm-res__file{font-family:var(--font-mono);font-size:12px;color:var(--text-primary)}
  .hm-res__diff{font-family:var(--font-mono);font-size:11px}
  .hm-res__diff .add{color:var(--green-400)}.hm-res__diff .del{color:var(--red-400)}
  .hm-res__term{font-family:var(--font-mono);font-size:11.5px;line-height:1.7;color:var(--text-muted);margin-top:9px;padding-top:9px;border-top:1px solid var(--border-subtle)}
  .hm-res__term .ok{color:var(--green-400)}
  .hm-res__acts{display:flex;gap:7px;margin-top:11px}
  /* composer */
  .hm-comp{flex:none;border-top:1px solid var(--border-subtle);padding:13px 22px 16px;background:var(--bg-base)}
  .hm-comp__box{background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-lg);transition:var(--transition-control)}
  .hm-comp__box:focus-within{border-color:var(--accent-border);box-shadow:var(--focus-ring)}
  .hm-comp__box textarea{display:block;width:100%;box-sizing:border-box;background:transparent;border:none;outline:none;resize:none;color:var(--text-primary);font-family:var(--font-sans);font-size:14px;line-height:1.5;padding:13px 14px 6px}
  .hm-comp__box textarea::placeholder{color:var(--text-faint)}
  .hm-comp__bar{display:flex;align-items:center;gap:8px;padding:8px 9px 9px}
  .hm-modes{display:inline-flex;gap:2px;padding:3px;background:var(--bg-subtle);border:1px solid var(--border-subtle);border-radius:var(--radius-md)}
  .hm-mode{height:25px;padding:0 11px;border:none;background:transparent;color:var(--text-muted);font-size:12px;font-weight:600;cursor:pointer;border-radius:var(--radius-sm);display:inline-flex;align-items:center;gap:6px;font-family:var(--font-sans);transition:var(--transition-control);white-space:nowrap}
  .hm-mode:hover{color:var(--text-primary)}
  .hm-mode.is-on{background:var(--bg-active);color:var(--text-primary);box-shadow:var(--shadow-xs)}
  .hm-send{width:34px;height:34px;border-radius:var(--radius-sm);border:none;background:var(--accent);color:var(--text-on-amber);display:flex;align-items:center;justify-content:center;cursor:pointer;flex:none;transition:var(--transition-control)}
  .hm-send:hover{background:var(--accent-hover);box-shadow:var(--glow-amber-sm)}
  .hm-comp__hint{font-size:11px;color:var(--text-faint);margin-top:8px;display:flex;align-items:center;gap:6px}
  /* empty / new */
  .hm-empty{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:22px;text-align:center;gap:6px}
  .hm-empty__t{font-size:20px;font-weight:700;letter-spacing:-.01em;margin-top:14px}
  .hm-empty__s{font-size:13.5px;color:var(--text-muted);max-width:420px;line-height:1.55}
  .hm-bench{display:flex;align-items:center;gap:7px;margin-top:6px;font-family:var(--font-mono);font-size:11px;color:var(--text-faint)}`;
  document.head.appendChild(s);
})();

/* ---------- workers ---------- */
const WK = {
  claude: { name: 'Claude Code', brand: 'anthropic', color: 'FFA630' },
  opus: { name: 'Opus 4.8', brand: 'anthropic', color: 'FFA630' },
  sonnet: { name: 'Sonnet 4.6', brand: 'anthropic', color: 'AEB5C9' },
  grok: { name: 'Grok', brand: 'x', color: 'E1E5F0' },
  gpt: { name: 'ChatGPT', icon: 'terminal' },
  gemini: { name: 'Gemini', brand: 'googlegemini', color: 'E1E5F0' },
  composer: { name: 'Composer', icon: 'square' },
};
function WGly({ w, size = 16 }) {
  if (!w) return null;
  return w.brand ? RH.createElement(BrandIcon, { slug: w.brand, color: w.color, size }) : RH.createElement(Ic, { name: w.icon || 'terminal', size: size - 1, style: { color: 'var(--text-secondary)' } });
}
const LANE = {
  design: { icon: 'image', bg: 'var(--accent-surface)', fg: 'var(--accent-text)' },
  build: { icon: 'hammer', bg: 'var(--info-surface)', fg: 'var(--blue-400)' },
  chat: { icon: 'message-square', bg: 'var(--bg-active)', fg: 'var(--text-muted)' },
};
// observed states only — facts, never "urgent" / "needs you"
const STT = {
  running: ['running', 'var(--blue-400)', 'run'],
  board: ['board ready', 'var(--accent-text)', ''],
  spec: ['spec ready', 'var(--accent-text)', ''],
  returned: ['exit 0', 'var(--green-400)', ''],
  failed: ['exit 1', 'var(--red-400)', ''],
  replied: ['replied', 'var(--text-muted)', ''],
};
function Stt({ k }) {
  const m = STT[k]; if (!m) return null;
  return RH.createElement('span', { className: 'hm-stt' + (m[2] === 'run' ? ' hm-stt--run' : ''), style: { color: m[1] } },
    RH.createElement('span', { className: 'hm-stt__d', style: { background: m[1] } }), m[0]);
}

Object.assign(window, { WK, WGly, LANE, STT, Stt });
