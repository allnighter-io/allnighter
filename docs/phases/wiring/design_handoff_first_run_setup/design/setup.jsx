// @ds-adherence-ignore -- Allnighter first-run Setup: "Assemble your council".
// The roster in its PARTIAL state (some ready, some need a step) with inline
// fix-its, plus a per-state spec sheet so engineering can implement every
// WorkerSetupStatus. Tool-level roster (one card per CLI); seats expand under a
// ready tool. Window globals, no exports. Built from 00_/01_ specs.
const RS = window.React;
const { Button: SB, IconButton: SIB, Badge: SBadge, BrandIcon: SBrand } = window;
const SLive = window.DCLive;

/* ---------- extra icons not in shell's DCIcon set ---------- */
const SU_EXTRA = {
  'external-link': '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
  'alert-triangle': '<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>',
  loader: '<path d="M12 2v4"/><path d="m16.2 7.8 2.9-2.9"/><path d="M18 12h4"/><path d="m16.2 16.2 2.9 2.9"/><path d="M12 18v4"/><path d="m4.9 19.1 2.9-2.9"/><path d="M2 12h4"/><path d="m4.9 4.9 2.9 2.9"/>',
  info: '<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>',
  shield: '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/>',
};
function SI({ name, size = 18, stroke = 2, style, ...rest }) {
  if (SU_EXTRA[name]) return RS.createElement('svg', { width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: stroke, strokeLinecap: 'round', strokeLinejoin: 'round', style, dangerouslySetInnerHTML: { __html: SU_EXTRA[name] }, ...rest });
  return RS.createElement(window.DCIcon, { name, size, stroke, style, ...rest });
}

/* ---------- styles ---------- */
(function () {
  if (document.getElementById('su-css')) return;
  const s = document.createElement('style'); s.id = 'su-css';
  s.textContent = `
  .su-page{min-height:100%;background:var(--bg-void);display:flex;flex-direction:column;align-items:center;gap:42px;padding:36px 24px 80px;box-sizing:border-box;font-family:var(--font-sans)}
  /* window chrome */
  .su-win{width:1120px;max-width:100%;display:flex;flex-direction:column;background:var(--bg-base);border:1px solid var(--border-default);border-radius:var(--radius-window);overflow:hidden;box-shadow:var(--shadow-xl);min-height:704px}
  .su-title{height:44px;flex:none;display:flex;align-items:center;gap:12px;padding:0 14px;background:var(--bg-surface);border-bottom:1px solid var(--border-subtle)}
  .su-lights{display:flex;gap:8px}.su-lights i{width:12px;height:12px;border-radius:50%;display:block}
  .su-tc{flex:1;display:flex;align-items:center;justify-content:center;gap:8px}
  .su-tc .nm{font-size:var(--text-label);font-weight:600;color:var(--text-secondary)}
  .su-tc .sub{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .su-tr{display:flex;align-items:center;gap:8px}
  /* stage */
  .su-stage{flex:1;display:flex;flex-direction:column;align-items:center;padding:44px 28px 12px}
  .su-hero{width:100%;max-width:720px;display:flex;flex-direction:column;align-items:center;text-align:center}
  .su-hero__mark{margin-bottom:20px;filter:drop-shadow(0 0 22px rgba(255,166,48,.20))}
  .su-hero__h{font-family:var(--font-display,var(--font-sans));font-size:30px;font-weight:800;letter-spacing:-.022em;color:var(--text-primary);line-height:1.08}
  .su-tally{display:flex;align-items:center;gap:9px;margin-top:15px;font-size:14px;color:var(--text-secondary);white-space:nowrap}
  .su-tally b{color:var(--text-primary);font-weight:700}
  .su-tally .c{font-family:var(--font-mono)}
  .su-tally .seats{font-family:var(--font-mono);font-size:12px;color:var(--text-faint)}
  .su-seg{display:flex;gap:5px;margin-top:17px}
  .su-seg i{width:52px;height:5px;border-radius:3px;background:var(--bg-active);display:block}
  .su-seg i.ready{background:var(--green-500)}
  .su-seg i.step{background:var(--yellow-400)}
  .su-hero__s{font-size:13.5px;color:var(--text-muted);max-width:540px;line-height:1.58;margin-top:17px;text-wrap:pretty}
  /* roster */
  .su-roster{width:100%;max-width:720px;display:flex;flex-direction:column;gap:9px;margin:32px 0 10px}
  .su-grouplbl{display:flex;align-items:center;gap:10px;font-size:10.5px;font-weight:700;letter-spacing:.11em;text-transform:uppercase;color:var(--text-faint);padding:15px 2px 3px}
  .su-grouplbl .ct{font-family:var(--font-mono);letter-spacing:0}
  .su-grouplbl .ln{flex:1;height:1px;background:var(--border-subtle)}
  /* card */
  .su-card{background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-lg);overflow:hidden;box-shadow:var(--shadow-sm)}
  .su-card--ready{border-color:rgba(63,185,109,.26);background:linear-gradient(180deg,rgba(63,185,109,.045),transparent 46%),var(--bg-raised)}
  .su-card--step{border-color:var(--border-default)}
  .su-card--muted{background:var(--bg-surface);border-style:dashed;border-color:var(--border-default);box-shadow:none}
  .su-card--fail{border-color:rgba(240,90,90,.28)}
  .su-head{display:flex;align-items:center;gap:13px;padding:13px 15px}
  .su-glyph{width:40px;height:40px;border-radius:10px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none;overflow:hidden}
  .su-glyph img{width:23px;height:23px}
  .su-card--muted .su-glyph{opacity:.5}
  .su-id{flex:1;min-width:0;display:flex;flex-direction:column;gap:4px}
  .su-name{font-size:14.5px;font-weight:700;color:var(--text-primary);letter-spacing:-.01em}
  .su-card--muted .su-name{color:var(--text-muted)}
  .su-meta{display:flex;align-items:center;gap:7px;font-family:var(--font-mono);font-size:11px;color:var(--text-faint);flex-wrap:wrap;line-height:1.3}
  .su-meta>span{white-space:nowrap}
  .su-meta .v{color:var(--text-muted)}
  .su-meta .ok{color:var(--green-400)}
  .su-meta .sep{opacity:.45}
  .su-trail{flex:none;display:flex;align-items:center}
  /* body / fix-it */
  .su-body{padding:14px 15px 15px;border-top:1px solid var(--border-subtle)}
  .su-fix{font-size:13px;color:var(--text-secondary);line-height:1.5;margin-bottom:11px}
  .su-fix code,.su-ic{font-family:var(--font-mono);font-size:12px;background:var(--bg-active);border:1px solid var(--border-subtle);border-radius:5px;padding:1px 6px;color:var(--text-primary)}
  .su-cmd{display:flex;align-items:center;gap:9px;background:var(--bg-void);border:1px solid var(--border-subtle);border-radius:var(--radius-md);padding:8px 8px 8px 12px;margin-bottom:12px}
  .su-cmd__p{font-family:var(--font-mono);font-size:12.5px;color:var(--text-faint);flex:none}
  .su-cmd__t{font-family:var(--font-mono);font-size:12.5px;color:var(--text-primary);flex:1;min-width:0;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .su-cmd--err .su-cmd__p{color:var(--red-400)}.su-cmd--err .su-cmd__t{color:var(--red-400)}
  .su-acts{display:flex;align-items:center;gap:8px;flex-wrap:wrap}
  .su-note{display:flex;align-items:center;gap:7px;font-size:11.5px;color:var(--text-faint);margin-top:12px;line-height:1.45}
  .su-note svg{flex:none}
  .su-poll{display:flex;align-items:center;gap:10px}
  /* seats */
  .su-seats{display:flex;flex-direction:column;gap:1px}
  .su-seat{display:flex;align-items:center;gap:10px;padding:8px 9px;border-radius:var(--radius-sm)}
  .su-seat__d{width:7px;height:7px;border-radius:50%;background:var(--green-500);flex:none}
  .su-seat__n{font-size:13px;font-weight:600;color:var(--text-primary)}
  .su-seat__m{font-family:var(--font-mono);font-size:11px;color:var(--text-faint)}
  .su-synth{display:inline-flex;align-items:center;gap:5px;height:20px;padding:0 8px;border-radius:var(--radius-pill);background:var(--accent-surface);color:var(--accent-text);border:1px solid var(--accent-border);font-size:10.5px;font-weight:600;margin-left:auto}
  /* pill */
  .su-pill{display:inline-flex;align-items:center;gap:6px;height:23px;padding:0 10px 0 8px;border-radius:var(--radius-pill);font-size:11.5px;font-weight:600;white-space:nowrap;border:1px solid transparent}
  .su-pill__d{width:7px;height:7px;border-radius:50%;flex:none}
  .su-pill--ready{background:var(--success-surface);color:var(--green-400)}
  .su-pill--step{background:var(--warning-surface);color:var(--yellow-400)}
  .su-pill--muted{background:var(--bg-active);color:var(--text-faint)}
  .su-pill--fail{background:var(--danger-surface);color:var(--red-400)}
  .su-pill--check{background:var(--info-surface);color:var(--blue-400)}
  .su-pill--check .su-pill__d{animation:su-blink 1.1s ease-in-out infinite}
  @keyframes su-blink{0%,100%{opacity:1}50%{opacity:.3}}
  /* footer */
  .su-footer{flex:none;display:flex;align-items:center;gap:18px;padding:14px 22px;border-top:1px solid var(--border-subtle);background:var(--bg-surface)}
  .su-footer__l{flex:1;min-width:0;display:flex;flex-direction:column;gap:5px}
  .su-scan{display:inline-flex;align-items:center;gap:7px;font-size:12.5px;font-weight:500;color:var(--text-secondary);background:none;border:none;cursor:pointer;font-family:inherit;padding:0}
  .su-scan:hover{color:var(--text-primary)}
  .su-reassure{font-family:var(--font-mono);font-size:10.5px;color:var(--text-faint)}
  .su-footer__r{display:flex;align-items:center;gap:14px;flex:none}
  .su-footer__hint{font-size:12px;color:var(--text-muted);text-align:right;max-width:208px;line-height:1.42}
  /* spec sheet */
  .su-gal{width:1120px;max-width:100%}
  .su-gal__hd{display:flex;align-items:baseline;gap:13px;flex-wrap:wrap;padding-bottom:10px;border-bottom:1px solid var(--border-subtle);margin-bottom:24px}
  .su-gal__t{font-size:18px;font-weight:700;letter-spacing:-.01em;color:var(--text-primary)}
  .su-gal__s{font-size:12.5px;color:var(--text-muted);max-width:560px;line-height:1.5}
  .su-gal__grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:22px 22px}
  .su-spec{display:flex;flex-direction:column;gap:10px}
  .su-spec__cap{display:flex;align-items:center;gap:9px;flex-wrap:wrap}
  .su-enum{font-family:var(--font-mono);font-size:11px;color:var(--accent-text);background:var(--accent-surface);border:1px solid var(--accent-border);border-radius:5px;padding:2px 7px}
  .su-spec__lbl{font-size:12px;color:var(--text-muted)}`;
  document.head.appendChild(s);
})();

/* ---------- glyph + pill ---------- */
function Glyph({ tool, muted }) {
  if (tool.brand) return RS.createElement(SBrand, { slug: tool.brand, color: muted ? '6B7180' : tool.color, size: 23 });
  return RS.createElement(SI, { name: tool.icon || 'terminal', size: 21, style: { color: muted ? 'var(--text-faint)' : 'var(--text-secondary)' } });
}
const PILL = {
  ready: ['ready', 'Ready', 'var(--green-500)'],
  needsLogin: ['step', 'Needs sign-in', 'var(--yellow-400)'],
  needsPath: ['step', 'Needs a path', 'var(--yellow-400)'],
  notInstalled: ['muted', 'Not installed', 'var(--text-faint)'],
  probeFailed: ['fail', 'Probe failed', 'var(--red-400)'],
  queued: ['muted', 'Queued', 'var(--text-faint)'],
  detecting: ['check', 'Detecting…', 'var(--blue-400)'],
  reprobing: ['check', 'Re-checking…', 'var(--blue-400)'],
  waiting: ['check', 'Waiting for sign-in…', 'var(--blue-400)'],
};
function Pill({ state }) {
  const p = PILL[state];
  return RS.createElement('span', { className: 'su-pill su-pill--' + p[0] },
    RS.createElement('span', { className: 'su-pill__d', style: { background: p[2] } }), p[1]);
}
function Cmd({ prompt = '$', text, err }) {
  return <div className={'su-cmd' + (err ? ' su-cmd--err' : '')}>
    <span className="su-cmd__p">{prompt}</span>
    <span className="su-cmd__t">{text}</span>
    <SIB variant="ghost" size="sm" label="Copy"><SI name="copy" size={14} /></SIB>
  </div>;
}

/* ---------- card head meta per state ---------- */
function Meta({ tool }) {
  const s = tool.state; const items = [];
  if (s === 'ready') items.push(<span key="r" className="v">{tool.route}</span>, <span key="v" className="v">{tool.version}</span>, <span key="se">{tool.seats.length} seats</span>, <span key="ok" className="ok">signed in</span>);
  else if (s === 'needsLogin' || s === 'waiting') items.push(<span key="r" className="v">{tool.route}</span>, <span key="v" className="v">{tool.version}</span>, <span key="f">found, not signed in</span>);
  else if (s === 'needsPath') items.push(<span key="r" className="v">{tool.route}</span>, <span key="v" className="v">{tool.version}</span>, <span key="f">shell function</span>);
  else if (s === 'notInstalled') items.push(<span key="f">no binary on PATH or known paths</span>);
  else if (s === 'probeFailed') items.push(<span key="r" className="v">{tool.route}</span>, <span key="v" className="v">{tool.version}</span>, <span key="f">smoke failed</span>);
  else if (s === 'reprobing') items.push(<span key="r" className="v">{tool.route}</span>, <span key="v" className="v">{tool.version}</span>, <span key="f">cheap re-check…</span>);
  else if (s === 'detecting') items.push(<span key="r" className="v">{tool.route}</span>, <span key="f">resolving → version → smoke</span>);
  else items.push(<span key="q">queued</span>);
  const out = [];
  items.forEach((it, i) => { if (i) out.push(<span key={'s' + i} className="sep">·</span>); out.push(it); });
  return <span className="su-meta">{out}</span>;
}

/* ---------- fix-it bodies ---------- */
function Body({ tool, compact }) {
  const s = tool.state;
  if (s === 'ready') { if (compact) return null; return <div className="su-body"><div className="su-seats">{tool.seats.map((seat, i) =>
    <div className="su-seat" key={i}>
      <span className="su-seat__d" /><span className="su-seat__n">{seat.n}</span><span className="su-seat__m">{seat.m}</span>
      {seat.synth && <span className="su-synth"><SI name="sparkles" size={11} />synthesizer</span>}
    </div>)}</div></div>; }

  if (s === 'needsLogin' || s === 'waiting') return <div className="su-body">
    <div className="su-fix">{tool.name} is installed but not signed in. It prompts for sign-in on first run.</div>
    <Cmd text="codex" />
    {s === 'waiting'
      ? <div className="su-poll"><Pill state="waiting" /><span className="su-reassure">re-checking every few seconds</span></div>
      : <div className="su-acts"><SB variant="primary" size="sm" iconLeft={<SI name="terminal" size={14} />}>Open Terminal & sign in</SB><SB variant="ghost" size="sm" iconLeft={<SI name="copy" size={13} />}>Copy steps</SB></div>}
    <div className="su-note"><SI name={s === 'waiting' ? 'loader' : 'info'} size={13} />{s === 'waiting' ? 'Flips to ready the moment the probe passes — no restart, no app focus needed.' : 'Sign in in Terminal — we’ll detect when you’re done.'}</div>
  </div>;

  if (s === 'needsPath') return <div className="su-body">
    <div className="su-fix">We found <code>agy</code> as a shell function, not a plain command.</div>
    <Cmd prompt="ƒ" text="agy () { /Applications/Antigravity.app/Contents/MacOS/agy $@ }" />
    <div className="su-acts"><SB variant="secondary" size="sm">Use it anyway</SB><SB variant="ghost" size="sm" iconLeft={<SI name="folder" size={14} />}>Locate the binary…</SB></div>
    <div className="su-note"><SI name="info" size={13} />Use-anyway runs it through your login shell — exactly as your terminal does.</div>
  </div>;

  if (s === 'notInstalled') return <div className="su-body">
    <div className="su-fix">You don’t have Grok yet. Install it, then re-scan.</div>
    <Cmd text="brew install grok" />
    <div className="su-acts"><SB variant="secondary" size="sm" iconLeft={<SI name="external-link" size={13} />}>Open install page</SB><SB variant="ghost" size="sm" iconLeft={<SI name="rotate-cw" size={13} />}>Re-scan</SB></div>
  </div>;

  if (s === 'probeFailed') return <div className="su-body">
    <div className="su-fix">Detected <code>codex 0.9.1</code>, but the smoke run failed.</div>
    <Cmd prompt="!" text="error: unknown flag --model (exit 2)" err />
    <div className="su-acts"><SB variant="secondary" size="sm" iconLeft={<SI name="rotate-cw" size={13} />}>Re-try probe</SB><SB variant="ghost" size="sm" iconLeft={<SI name="file-text" size={13} />}>View log</SB></div>
    <div className="su-note"><SI name="alert-triangle" size={13} style={{ color: 'var(--red-400)' }} />Detect passed, smoke didn’t — this is not a sign-in problem.</div>
  </div>;

  return null;
}

/* ---------- the card ---------- */
function SetupCard({ tool, compact }) {
  const s = tool.state;
  const variant = s === 'ready' ? 'ready' : s === 'notInstalled' ? 'muted' : s === 'probeFailed' ? 'fail' : s === 'queued' || s === 'detecting' ? 'muted' : 'step';
  const muted = s === 'notInstalled' || s === 'queued' || s === 'detecting';
  return <div className={'su-card su-card--' + variant}>
    <div className="su-head">
      <span className="su-glyph"><Glyph tool={tool} muted={muted} /></span>
      <span className="su-id"><span className="su-name">{tool.name}</span><Meta tool={tool} /></span>
      <span className="su-trail"><Pill state={s} /></span>
    </div>
    <Body tool={tool} compact={compact} />
  </div>;
}

/* ---------- roster data (the partial state) ---------- */
const ROSTER = {
  ready: [
    { id: 'claude', name: 'Claude Code', brand: 'anthropic', color: 'FFA630', route: 'via claude-code', version: 'claude 1.2.4', state: 'ready', seats: [{ n: 'Opus 4.8', m: 'opus-4.8', synth: true }, { n: 'Sonnet 4.6', m: 'sonnet-4.6' }] },
  ],
  step: [
    { id: 'codex', name: 'Codex', icon: 'terminal', route: 'via codex', version: 'codex 0.9.1', state: 'needsLogin' },
    { id: 'agy', name: 'Antigravity', brand: 'googlegemini', color: 'E1E5F0', route: 'via antigravity', version: 'agy', state: 'needsPath' },
  ],
  add: [
    { id: 'grok', name: 'Grok', brand: 'x', color: 'E1E5F0', route: 'via grok', state: 'notInstalled' },
  ],
};

function GroupLabel({ children, count }) {
  return <div className="su-grouplbl">{children}<span className="ct">{count}</span><span className="ln" /></div>;
}

/* ---------- the Setup window ---------- */
function SetupWindow() {
  return <div className="su-win">
    <div className="su-title">
      <div className="su-lights"><i style={{ background: '#FF5F57' }} /><i style={{ background: '#FEBC2E' }} /><i style={{ background: '#28C840' }} /></div>
      <div className="su-tc">{RS.createElement(SLive, { size: 16 })}<span className="nm">allnighter</span><span className="sub">· setup</span></div>
      <div className="su-tr"><SBadge tone="warning" dot mono>1/4 ready</SBadge><SIB variant="ghost" size="sm" label="Settings"><SI name="settings-2" /></SIB></div>
    </div>

    <div className="su-stage">
      <div className="su-hero">
        <div className="su-hero__mark">{RS.createElement(SLive, { size: 46 })}</div>
        <div className="su-hero__h">Your council is taking shape</div>
        <div className="su-tally"><b><span className="c">1</span> of <span className="c">4</span> tools ready</b><span className="seats">· 2 seats</span></div>
        <div className="su-seg"><i className="ready" /><i className="step" /><i className="step" /><i /></div>
        <div className="su-hero__s">Claude Code is ready. Two tools need a quick step and one isn’t installed yet — fix them here and they go green in place. No restart, no typing.</div>
      </div>

      <div className="su-roster">
        <GroupLabel count="1">Ready</GroupLabel>
        {ROSTER.ready.map((t) => <SetupCard key={t.id} tool={t} />)}
        <GroupLabel count="2">Needs a step</GroupLabel>
        {ROSTER.step.map((t) => <SetupCard key={t.id} tool={t} />)}
        <GroupLabel count="1">Available to add</GroupLabel>
        {ROSTER.add.map((t) => <SetupCard key={t.id} tool={t} />)}
      </div>
    </div>

    <div className="su-footer">
      <div className="su-footer__l">
        <button className="su-scan"><SI name="shield" size={14} />What gets scanned?</button>
        <span className="su-reassure">scanned locally · read-only · only known CLI tools</span>
      </div>
      <div className="su-footer__r">
        <span className="su-footer__hint">Continue with 1 ready, or fix the rest first.</span>
        <SB variant="primary" iconRight={<SI name="arrow-right" size={16} />}>Continue</SB>
      </div>
    </div>
  </div>;
}

/* ---------- per-state spec sheet (for engineering) ---------- */
const SPECS = [
  { enum: 'ready', lbl: 'Smoke passed — seats expand under the tool', tool: ROSTER.ready[0] },
  { enum: 'installedNotSignedIn', lbl: 'Found, not signed in — guided sign-in', tool: ROSTER.step[0] },
  { enum: 'installedNotSignedIn · polling', lbl: 'After “Open Terminal” — re-probes in place', tool: { id: 'codex-w', name: 'Codex', icon: 'terminal', route: 'via codex', version: 'codex 0.9.1', state: 'waiting' } },
  { enum: 'notInstalled', lbl: 'No binary resolved — install hint + re-scan', tool: ROSTER.add[0] },
  { enum: 'shimmedNeedsConfirm', lbl: 'Alias / shim / non-PATH binary', tool: ROSTER.step[1] },
  { enum: 'probeFailed', lbl: 'Detect ok, smoke failed (not auth)', tool: { id: 'codex-f', name: 'Codex', icon: 'terminal', route: 'via codex', version: 'codex 0.9.1', state: 'probeFailed' } },
  { enum: 'queued / ghost', lbl: 'Before detection — a dim slot in roll-call', tool: { id: 'grok-q', name: 'Grok', brand: 'x', color: 'E1E5F0', route: 'via grok', state: 'queued' } },
  { enum: 'detecting', lbl: 'Resolve → version → smoke (quiet pulse)', tool: { id: 'claude-d', name: 'Claude Code', brand: 'anthropic', color: 'FFA630', route: 'via claude-code', state: 'detecting' } },
  { enum: 're-probing', lbl: 'Cheap re-check on launch / wake', tool: { id: 'agy-r', name: 'Antigravity', brand: 'googlegemini', color: 'E1E5F0', route: 'via antigravity', version: 'agy', state: 'reprobing' } },
];
function SpecSheet() {
  return <div className="su-gal">
    <div className="su-gal__hd">
      <span className="su-gal__t">Every card state</span>
      <span className="su-gal__s">One card per tool. State is the single canonical <span className="su-ic">WorkerSetupStatus</span> — Doctor, Setup, and the health badge all read it. A card only flips to <b style={{ color: 'var(--green-400)' }}>Ready</b> when its smoke probe actually passed; failures show the real reason and the fix.</span>
    </div>
    <div className="su-gal__grid">
      {SPECS.map((sp, i) => <div className="su-spec" key={i}>
        <div className="su-spec__cap"><span className="su-enum">{sp.enum}</span><span className="su-spec__lbl">{sp.lbl}</span></div>
        <SetupCard tool={sp.tool} />
      </div>)}
    </div>
  </div>;
}

function SetupScreen() {
  return <div className="su-page"><SetupWindow /><SpecSheet /></div>;
}
window.SetupScreen = SetupScreen;
// reused by the compact Doctor / Council-health surface (doctor.jsx)
Object.assign(window, { SetupCard, GroupLabel, SU_ROSTER: ROSTER, SI, Pill });
