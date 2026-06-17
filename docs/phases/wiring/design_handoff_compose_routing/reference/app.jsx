// @ds-adherence-ignore -- Allnighter home: data + panes + app.
const RA = window.React;
const { Button: HB, IconButton: HIB, Badge: HBadge } = window;
const Ico = window.DCIcon;
const Sela = window.DCSelect;
const Mena = window.DCMenu;
const { WK: W, WGly: G, LANE: LN, Stt } = window;

/* ===================== threads (work orders = conversations) ===================== */
const SHOT = (v) => RA.createElement('div', { className: 'hm-shot' }, RA.createElement(window.FauxScreen, { variant: v }));

const THREADS = [
  {
    id: 'profile', title: 'Redesign the profile screen', lane: 'design', state: 'returned',
    workers: ['grok', 'claude'], time: 'now', pinned: true,
    turns: [
      { kind: 'user', time: '2:02', text: 'Make this profile feel premium and clean.', shot: 'before' },
      { kind: 'fanout', lane: 'design', who: 'The bench', sub: 'fan-out · 4 mockups',
        workers: ['grok', 'gpt', 'gemini'], pick: 1,
        tiles: ['bold', 'minimal', 'editorial', 'onbrand'], picked: 'minimal' },
      { kind: 'user', time: '2:09', text: 'Love the minimal one. Build it into the real screen.' },
      { kind: 'exec', who: 'Claude Code', worker: 'claude', sub: 'execution · ~/code/halo-app', state: 'returned',
        file: 'src/screens/Profile.tsx', add: '+84', del: '−63',
        term: ['read option_o1.png + Profile.tsx', 'restyled — reused <Card> / <Avatar>', '✓ build passed · exit 0'] },
      { kind: 'user', time: '2:21', text: 'Quick gut check — is the empty state worth keeping, or cut it?' },
      { kind: 'chat', who: 'Grok', worker: 'grok', sub: 'chat', state: 'replied',
        text: 'Keep it. It’s the only screen state a brand-new user with zero posts actually sees — cutting it leaves them staring at a blank wall. It’s cheap to keep and it’s the difference between “empty” and “welcoming.”' },
    ],
  },
  {
    id: 'ratelimit', title: 'Rate-limit the public API', lane: 'build', state: 'running',
    workers: ['opus', 'gpt', 'sonnet'], time: '1m', pinned: true,
    turns: [
      { kind: 'user', time: '4:40', text: 'Add per-user rate limiting to the public API.' },
      { kind: 'fanout', lane: 'build', who: 'The bench', sub: 'fan-out · 5 workers · running',
        workers: ['opus', 'gpt', 'sonnet', 'composer', 'gemini'], running: true },
    ],
  },
  {
    id: 'limiter', title: 'Token bucket vs sliding window', lane: 'chat', state: 'replied',
    workers: ['grok', 'claude'], time: '5m',
    turns: [
      { kind: 'user', time: '3:31', text: 'For per-user API rate limiting — token bucket or sliding window? Short answer + why.' },
      { kind: 'chat', who: 'Grok', worker: 'grok', sub: 'chat', state: 'replied',
        md: [
          "**Token bucket** — for most APIs it's the right default.",
          "",
          "### Why",
          "- It tolerates short **bursts** (banked tokens) while still capping the sustained rate — friendlier to real clients.",
          "- Cheap to store: one `count` + one `lastRefill` timestamp per user in Redis.",
          "- Sliding window is smoother but needs a sorted set of timestamps per user — more memory, more ops.",
          "",
          "Refill with `tokens = min(cap, tokens + rate * elapsed)` and reject when `tokens < 1`.",
        ],
        reroute: { worker: 'claude', who: 'Claude',
          md: ["Agree — **token bucket**, with one caveat: if you must guarantee exactly N per window for billing, a fixed window is simpler to reason about. For fairness + burst tolerance, token bucket wins."] } },
      { kind: 'user', time: '3:34', text: 'Give me a minimal Express middleware for it.' },
      { kind: 'chat', who: 'Claude', worker: 'claude', sub: 'chat', streaming: true,
        md: [
          "Here's a minimal Redis-backed token bucket:",
          "",
          "```js",
          "export const limit = (cap, rate) => async (req, res, next) => {",
          "  const key = `rl:${req.userId}`;",
          "  const now = Date.now() / 1000;",
          "  let [t, ts] = (await redis.hmget(key, 't', 'ts')).map(Number);",
          "  let tokens = Math.min(cap, (t ?? cap) + (now - (ts ?? now)) * rate);",
          "  if (tokens < 1) return res.status(429).set('Retry-After', '1').end();",
        ] },
    ],
  },
  {
    id: 'onboard', title: 'Onboarding empty states', lane: 'design', state: 'board',
    workers: ['gemini', 'grok'], time: '12m',
    turns: [
      { kind: 'user', time: '4:28', text: 'Three empty states for onboarding — make them feel encouraging, not broken.', shot: 'editorial' },
      { kind: 'fanout', lane: 'design', who: 'The bench', sub: 'fan-out · 4 mockups',
        workers: ['grok', 'gemini'], tiles: ['minimal', 'bold', 'editorial', 'onbrand'] },
    ],
  },
  {
    id: 'darkmode', title: 'Dark-mode token audit', lane: 'chat', state: 'replied',
    workers: ['grok'], time: '2h',
    turns: [
      { kind: 'user', time: '1:14', text: 'Which of my gray tokens fail AA on the midnight background?' },
      { kind: 'chat', who: 'Grok', worker: 'grok', sub: 'chat', state: 'replied',
        text: 'Three are borderline: --ink-500 on --bg-base lands at 3.9:1 (fails AA for body), --ink-400 is fine for large text only, and your caption gray --ink-500 at 11px is the riskiest. Bump captions to --ink-300 and you clear AA everywhere.' },
    ],
  },
  { id: 'auth', title: 'Migrate auth to server sessions', lane: 'build', state: 'spec', workers: ['opus'], time: '40m' },
  { id: 'checkout', title: 'Fix the flaky checkout test', lane: 'build', state: 'failed', workers: ['claude'], time: '1h' },
  { id: 'pricing', title: 'Pricing page — make it not look like a template', lane: 'design', state: 'board', workers: ['gpt', 'gemini'], time: '3h' },
  { id: 'webhook', title: 'Webhook retry + backoff', lane: 'build', state: 'returned', workers: ['composer'], time: 'Tue' },
];

/* ===================== sidebar ===================== */
function Stack({ ws }) {
  return RA.createElement('span', { className: 'hm-stack' },
    ws.slice(0, 3).map((k, i) => W[k] && W[k].brand
      ? RA.createElement('img', { key: i, src: `https://cdn.simpleicons.org/${W[k].brand}/${W[k].color}`, alt: '' })
      : RA.createElement('span', { key: i, className: 'hm-stack__t' }, RA.createElement(Ico, { name: (W[k] && W[k].icon) || 'terminal', size: 10, style: { color: 'var(--text-secondary)' } }))));
}
function ConvoRow({ t, active, onClick }) {
  const lane = LN[t.lane];
  return RA.createElement('button', { className: 'hm-row' + (active ? ' is-active' : '') + (t.state === 'replied' ? ' is-idle' : ''), onClick },
    RA.createElement('span', { className: 'hm-row__glyph' },
      RA.createElement(G, { w: W[t.workers[0]], size: 17 }),
      RA.createElement('span', { className: 'hm-row__lane', style: { background: lane.bg, color: lane.fg } }, RA.createElement(Ico, { name: lane.icon, size: 9 }))),
    RA.createElement('span', { className: 'hm-row__main' },
      RA.createElement('span', { className: 'hm-row__t' }, t.title),
      RA.createElement('span', { className: 'hm-row__meta' },
        RA.createElement(Stt, { k: t.state }),
        t.workers.length > 1 && RA.createElement(Stack, { ws: t.workers }),
        RA.createElement('span', { className: 'hm-row__time' }, t.time))));
}
function Sidebar({ sel, onSel, onNew }) {
  const [filter, setFilter] = RA.useState('all');
  const pinned = THREADS.filter((t) => t.pinned);
  let rows = THREADS.filter((t) => !t.pinned);
  if (filter !== 'all') rows = rows.filter((t) => filter === 'running' ? t.state === 'running' : t.lane === filter);
  return RA.createElement('aside', { className: 'hm-side' },
    RA.createElement('div', { className: 'hm-side__top' },
      RA.createElement('button', { className: 'hm-new', onClick: onNew }, RA.createElement(Ico, { name: 'plus', size: 16 }), 'New work order'),
      RA.createElement('div', { className: 'hm-search' }, RA.createElement(Ico, { name: 'search', size: 14 }), RA.createElement('input', { placeholder: 'Search conversations' })),
      RA.createElement('div', { className: 'hm-filters' },
        [['all', 'All'], ['design', 'Design'], ['build', 'Build'], ['running', 'Running']].map(([k, l]) =>
          RA.createElement('button', { key: k, className: 'hm-fchip' + (filter === k ? ' is-on' : ''), onClick: () => setFilter(k) }, l)))),
    RA.createElement('div', { className: 'hm-list' },
      pinned.length > 0 && filter === 'all' && RA.createElement('div', { className: 'hm-grouplbl' }, RA.createElement(Ico, { name: 'corner-down-right', size: 11 }), 'Pinned'),
      filter === 'all' && pinned.map((t) => RA.createElement(ConvoRow, { key: t.id, t, active: sel === t.id, onClick: () => onSel(t.id) })),
      RA.createElement('div', { className: 'hm-grouplbl' }, 'Recent'),
      rows.map((t) => RA.createElement(ConvoRow, { key: t.id, t, active: sel === t.id, onClick: () => onSel(t.id) }))));
}

/* ===================== turns ===================== */
function TurnUser({ t }) {
  return RA.createElement('div', { className: 'hm-turn hm-turn--you' },
    RA.createElement('span', { className: 'hm-turn__g hm-turn__g--you' }, 'YOU'),
    RA.createElement('div', { className: 'hm-turn__b' },
      RA.createElement('div', { className: 'hm-turn__hd' },
        RA.createElement('span', { className: 'hm-turn__who' }, 'You'),
        t.time && RA.createElement('span', { className: 'hm-turn__time' }, t.time)),
      RA.createElement('div', { className: 'hm-turn__txt' }, t.text),
      t.shot && SHOT(t.shot)));
}
function TurnHead({ w, who, sub, state }) {
  const lane = w ? null : null;
  return RA.createElement('div', { className: 'hm-turn__hd' },
    RA.createElement('span', { className: 'hm-turn__who' }, who),
    RA.createElement('span', { className: 'hm-turn__kind' }, '· ' + sub),
    state && RA.createElement('span', { style: { marginLeft: 'auto' } }, RA.createElement(Stt, { k: state })));
}
(function () {
  if (document.getElementById('home-chat-css')) return;
  const s = document.createElement('style'); s.id = 'home-chat-css';
  s.textContent = `
  .md{margin-top:2px}
  .md p{font-size:13.5px;color:var(--text-secondary);line-height:1.62;margin:0 0 9px}
  .md p:last-child{margin-bottom:0}
  .md h3{font-size:12px;font-weight:700;color:var(--text-primary);letter-spacing:.04em;text-transform:uppercase;margin:13px 0 7px}
  .md ul{margin:0 0 9px;padding:0;list-style:none}
  .md li{display:flex;gap:9px;font-size:13.5px;color:var(--text-secondary);line-height:1.55;padding:3px 0}
  .md li::before{content:"";width:5px;height:5px;border-radius:50%;background:var(--accent);margin-top:8px;flex:none}
  .md code{font-family:var(--font-mono);font-size:12px;background:var(--bg-active);border:1px solid var(--border-subtle);border-radius:5px;padding:1px 5px;color:var(--text-primary)}
  .md pre{background:var(--bg-void);border:1px solid var(--border-subtle);border-radius:var(--radius-md);padding:11px 13px;overflow:auto;margin:2px 0 10px}
  .md pre code{font-family:var(--font-mono);font-size:12px;line-height:1.7;color:var(--text-secondary);background:none;border:none;padding:0;white-space:pre;display:block}
  .md strong{color:var(--text-primary);font-weight:600}
  .hm-cc{display:flex;gap:2px;margin-top:10px;margin-left:-6px}
  .hm-cur{display:inline-block;width:7px;height:14px;background:var(--accent);border-radius:2px;vertical-align:-2px;animation:hm-cur 1s steps(1,end) infinite}
  @keyframes hm-cur{0%,52%{opacity:1}53%,100%{opacity:0}}
  .hm-stream{display:flex;align-items:center;gap:8px;margin-top:9px;font-family:var(--font-mono);font-size:11px;color:var(--accent-text);white-space:nowrap}
  .hm-rr{margin-top:13px;border-left:2px solid var(--accent-border);padding-left:14px}
  .hm-rr__h{display:flex;align-items:center;gap:6px;font-family:var(--font-mono);font-size:10.5px;color:var(--text-faint);margin-bottom:8px;white-space:nowrap}
  .hm-rr__h img{width:13px;height:13px;border-radius:3px}
  .hm-rr__h b{color:var(--text-secondary);font-weight:600}
  .fr-wrap{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;padding:26px;overflow:auto}
  .fr-h{font-size:25px;font-weight:800;letter-spacing:-.02em;margin-top:16px;text-align:center}
  .fr-s{font-size:13.5px;color:var(--text-muted);max-width:486px;line-height:1.6;text-align:center;margin-top:9px}
  .fr-bench{display:flex;gap:7px;flex-wrap:wrap;justify-content:center;margin:18px 0 2px;max-width:580px}
  .fr-w{display:flex;align-items:center;gap:7px;padding:7px 11px;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-md)}
  .fr-w__n{font-size:12px;font-weight:600}
  .fr-w__c{font-family:var(--font-mono);font-size:10px;color:var(--text-faint)}
  .fr-w__d{width:6px;height:6px;border-radius:50%;background:var(--green-500)}
  .fr-ex{display:flex;gap:10px;margin:18px 0 6px;max-width:640px;width:100%}
  .fr-card{flex:1;text-align:left;padding:13px 14px;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-md);cursor:pointer;transition:var(--transition-control)}
  .fr-card:hover{border-color:var(--border-default);background:var(--bg-hover);transform:translateY(-2px)}
  .fr-card__h{display:flex;align-items:center;gap:8px;font-size:12.5px;font-weight:700;margin-bottom:7px}
  .fr-card__t{font-size:11.5px;color:var(--text-muted);line-height:1.5}
  .fr-emptyhint{display:flex;flex-direction:column;align-items:center;gap:9px;color:var(--text-muted);text-align:center;padding:46px 18px;font-size:12.5px}`;
  document.head.appendChild(s);
})();

/* ---- compact markdown (no regex, no escapes) ---- */
function mdInline(s) {
  const out = []; let buf = ''; let key = 0; let i = 0;
  const flush = () => { if (buf) { out.push(buf); buf = ''; } };
  while (i < s.length) {
    if (s[i] === '`') { const e = s.indexOf('`', i + 1); if (e > i) { flush(); out.push(<code key={key++}>{s.slice(i + 1, e)}</code>); i = e + 1; continue; } }
    if (s[i] === '*' && s[i + 1] === '*') { const e = s.indexOf('**', i + 2); if (e > i) { flush(); out.push(<strong key={key++}>{s.slice(i + 2, e)}</strong>); i = e + 2; continue; } }
    buf += s[i]; i++;
  }
  flush(); return out;
}
function MD({ text }) {
  const lines = Array.isArray(text) ? text : String(text).split(String.fromCharCode(10));
  const blocks = []; let i = 0;
  while (i < lines.length) {
    const ln = lines[i];
    if (ln.startsWith('```')) {
      const code = []; i++;
      while (i < lines.length && !lines[i].startsWith('```')) { code.push(lines[i]); i++; }
      i++; blocks.push(['code', code.join(String.fromCharCode(10))]); continue;
    }
    if (ln.startsWith('### ') || ln.startsWith('## ')) { blocks.push(['h', ln.startsWith('### ') ? ln.slice(4) : ln.slice(3)]); i++; continue; }
    if (ln.trimStart().startsWith('- ')) { const items = []; while (i < lines.length && lines[i].trimStart().startsWith('- ')) { items.push(lines[i].trimStart().slice(2)); i++; } blocks.push(['ul', items]); continue; }
    if (ln.trim() === '') { i++; continue; }
    blocks.push(['p', ln]); i++;
  }
  return <div className="md">{blocks.map((b, k) =>
    b[0] === 'code' ? <pre key={k}><code>{b[1]}</code></pre>
      : b[0] === 'h' ? <h3 key={k}>{mdInline(b[1])}</h3>
        : b[0] === 'ul' ? <ul key={k}>{b[1].map((li, j) => <li key={j}>{mdInline(li)}</li>)}</ul>
          : <p key={k}>{mdInline(b[1])}</p>)}</div>;
}
function ChatControls({ worker }) {
  return <div className="hm-cc">
    <HB variant="ghost" size="sm" iconLeft={<Ico name="copy" size={12} />}>Copy</HB>
    <HB variant="ghost" size="sm" iconLeft={<Ico name="rotate-cw" size={12} />}>Retry</HB>
    <Mena align="start" trigger={<HB variant="ghost" size="sm" iconLeft={<Ico name="corner-down-right" size={12} />} iconRight={<Ico name="chevron-down" size={11} />}>Route to</HB>}
      items={Object.keys(W).filter((k) => k !== worker).map((k) => ({ label: W[k].name, icon: <G w={W[k]} size={14} /> }))} />
  </div>;
}
function Reroute({ r }) {
  return <div className="hm-rr">
    <div className="hm-rr__h"><Ico name="corner-down-right" size={12} /> you re-asked <G w={W[r.worker]} size={13} /> <b>{r.who}</b> · second opinion</div>
    <MD text={r.md} />
  </div>;
}
function TurnChat({ t }) {
  return <div className="hm-turn">
    <span className="hm-turn__g" style={{ background: 'var(--bg-active)' }}><G w={W[t.worker]} /></span>
    <div className="hm-turn__b">
      <TurnHead who={t.who} sub={t.sub} state={t.streaming ? null : t.state} />
      {t.md ? <MD text={t.md} /> : <div className="hm-turn__txt">{t.text}</div>}
      {t.streaming
        ? <div className="hm-stream"><span className="hm-cur" /> {W[t.worker].name} is writing…</div>
        : <ChatControls worker={t.worker} />}
      {t.reroute && <Reroute r={t.reroute} />}
    </div>
  </div>;
}
function TurnFanout({ t, onOpen }) {
  return RA.createElement('div', { className: 'hm-turn' },
    RA.createElement('span', { className: 'hm-turn__g', style: { background: LN[t.lane].bg, color: LN[t.lane].fg } }, RA.createElement(Ico, { name: 'layers', size: 15 })),
    RA.createElement('div', { className: 'hm-turn__b' },
      RA.createElement('div', { className: 'hm-turn__hd' },
        RA.createElement('span', { className: 'hm-turn__who' }, t.who),
        RA.createElement('span', { className: 'hm-turn__kind' }, '· ' + t.sub),
        RA.createElement('span', { style: { marginLeft: 'auto', display: 'flex', alignItems: 'center', gap: 8 } },
          RA.createElement(Stack, { ws: t.workers }),
          t.running && RA.createElement(Stt, { k: 'running' }))),
      t.tiles && RA.createElement('div', { className: 'hm-fan' },
        RA.createElement('div', { className: 'hm-fan__row' },
          t.tiles.map((v, i) => RA.createElement('div', { key: i, className: 'hm-fan__tile' + (t.picked === v ? ' is-pick' : ''), onClick: onOpen },
            RA.createElement(window.FauxScreen, { variant: v }),
            t.picked === v && RA.createElement('span', { className: 'hm-fan__pk' }, RA.createElement(HBadge, { tone: 'accent', dot: true }, 'pick'))))),
        RA.createElement('div', { style: { display: 'flex', alignItems: 'center', gap: 10 } },
          t.picked
            ? RA.createElement('span', { style: { fontSize: 12.5, color: 'var(--text-secondary)' } }, 'You picked ', RA.createElement('b', { style: { color: 'var(--text-primary)' } }, t.picked))
            : RA.createElement('span', { style: { fontSize: 12.5, color: 'var(--text-muted)' } }, 'Open the board to compare and pick.'),
          RA.createElement(HB, { variant: 'ghost', size: 'sm', iconLeft: RA.createElement(Ico, { name: 'layout-grid', size: 13 }), onClick: onOpen }, 'Open board'))),
      t.running && RA.createElement('div', { style: { display: 'flex', gap: 9, marginTop: 4 } },
        t.workers.map((k, i) => RA.createElement('div', { key: i, style: { width: 78, height: 120, borderRadius: 8, border: '1px dashed var(--border-strong)', background: 'var(--bg-active)', display: 'flex', alignItems: 'center', justifyContent: 'center' } },
          RA.createElement('span', { className: 'hm-stt hm-stt--run', style: { color: 'var(--blue-400)' } }, RA.createElement('span', { className: 'hm-stt__d', style: { background: 'var(--blue-400)' } })))))));
}
function TurnExec({ t }) {
  return RA.createElement('div', { className: 'hm-turn' },
    RA.createElement('span', { className: 'hm-turn__g', style: { background: 'var(--bg-active)' } }, RA.createElement(G, { w: W[t.worker] })),
    RA.createElement('div', { className: 'hm-turn__b' },
      RA.createElement(TurnHead, { who: t.who, sub: t.sub, state: t.state }),
      RA.createElement('div', { className: 'hm-res' },
        RA.createElement('div', { className: 'hm-res__top' },
          RA.createElement(Ico, { name: 'file-text', size: 15, style: { color: 'var(--text-faint)' } }),
          RA.createElement('span', { className: 'hm-res__file' }, t.file),
          RA.createElement('span', { className: 'hm-res__diff', style: { marginLeft: 'auto' } },
            RA.createElement('span', { className: 'add' }, t.add), ' ', RA.createElement('span', { className: 'del' }, t.del))),
        RA.createElement('div', { className: 'hm-res__term' }, t.term.map((l, i) =>
          RA.createElement('div', { key: i }, l.startsWith('✓') ? RA.createElement('span', { className: 'ok' }, l) : l))),
        RA.createElement('div', { className: 'hm-res__acts' },
          RA.createElement(HB, { variant: 'secondary', size: 'sm', iconLeft: RA.createElement(Ico, { name: 'file-text', size: 13 }) }, 'View diff'),
          RA.createElement(HB, { variant: 'ghost', size: 'sm', iconLeft: RA.createElement(Ico, { name: 'terminal', size: 13 }) }, 'Transcript')))));
}

/* ===================== composer ===================== */
(function () {
  if (document.getElementById('home-comp-css')) return;
  const s = document.createElement('style'); s.id = 'home-comp-css';
  s.textContent = `
  .hm-popwrap{position:relative;display:inline-flex}
  .hm-popbd{position:fixed;inset:0;z-index:60}
  .hm-pop{position:absolute;bottom:calc(100% + 9px);left:0;z-index:61;background:var(--bg-surface);border:1px solid var(--border-default);border-radius:var(--radius-lg);box-shadow:var(--shadow-xl);overflow:hidden}
  .hm-pop--down{bottom:auto;top:calc(100% + 9px)}
  .hm-pop--right{left:auto;right:0}
  .hm-pop__hd{padding:12px 14px 9px;border-bottom:1px solid var(--border-subtle)}
  .hm-pop__t{font-size:12.5px;font-weight:700;color:var(--text-primary)}
  .hm-pop__s{font-family:var(--font-mono);font-size:10.5px;color:var(--text-faint);margin-top:3px}
  .hm-pop__list{padding:6px;max-height:248px;overflow:auto}
  .hm-opt{display:flex;align-items:center;gap:10px;width:100%;padding:8px 9px;border:none;background:transparent;border-radius:var(--radius-sm);cursor:pointer;text-align:left;transition:var(--transition-control);font-family:var(--font-sans)}
  .hm-opt:hover{background:var(--bg-hover)}
  .hm-opt:disabled{cursor:default}
  .hm-opt:disabled .hm-opt__n{color:var(--text-muted)}
  .hm-opt:disabled:hover{background:transparent}
  .hm-opt__g{width:27px;height:27px;border-radius:7px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none}
  .hm-opt__m{flex:1;min-width:0}
  .hm-opt__n{font-size:13px;font-weight:600;color:var(--text-primary);display:flex;align-items:center;gap:7px}
  .hm-opt__s{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-top:1px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .hm-opt__def{font-family:var(--font-mono);font-size:9px;letter-spacing:.04em;color:var(--text-faint);border:1px solid var(--border-subtle);border-radius:4px;padding:0 4px;height:15px;display:inline-flex;align-items:center;flex:none}
  .hm-opt__chk{color:var(--accent-text);flex:none}
  .hm-pop__ft{padding:10px 12px;border-top:1px solid var(--border-subtle);display:flex;align-items:center;gap:9px}
  .hm-pop__ftnote{font-size:10.5px;color:var(--text-faint);line-height:1.4}
  .hm-lanetabs{display:flex;gap:4px;padding:10px 11px 5px}
  .hm-lanetab{flex:1;height:31px;border:1px solid var(--border-subtle);background:transparent;border-radius:var(--radius-sm);color:var(--text-muted);font-size:12px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:6px;font-family:var(--font-sans);transition:var(--transition-control)}
  .hm-lanetab:hover{background:var(--bg-hover);color:var(--text-secondary)}
  .hm-lanetab.is-on{background:var(--bg-active);color:var(--text-primary);border-color:var(--border-default)}
  .hm-lanetab.is-on>.ic{color:var(--accent-text)}
  .hm-eff{display:flex;align-items:center;gap:10px;padding:11px 14px;border-top:1px solid var(--border-subtle);flex-wrap:wrap}
  .hm-eff__l{font-size:10.5px;font-weight:700;letter-spacing:.07em;text-transform:uppercase;color:var(--text-faint)}
  .hm-eff__note{flex-basis:100%;font-size:10.5px;color:var(--text-faint);line-height:1.4}
  .hm-seg{display:inline-flex;gap:2px;padding:3px;background:var(--bg-subtle);border:1px solid var(--border-subtle);border-radius:var(--radius-md);margin-left:auto}
  .hm-seg button{height:24px;padding:0 13px;border:none;background:transparent;color:var(--text-muted);font-size:11.5px;font-weight:600;cursor:pointer;border-radius:var(--radius-sm);font-family:var(--font-sans);transition:var(--transition-control)}
  .hm-seg button:hover{color:var(--text-primary)}
  .hm-seg button.is-on{background:var(--bg-active);color:var(--text-primary);box-shadow:var(--shadow-xs)}
  .hm-mrow{display:flex;align-items:flex-start;gap:11px;width:100%;padding:9px 11px;border:none;background:transparent;border-radius:var(--radius-sm);cursor:pointer;text-align:left;transition:var(--transition-control);font-family:var(--font-sans)}
  .hm-mrow:hover{background:var(--bg-hover)}
  .hm-mrow.is-on{background:var(--bg-active)}
  .hm-mrow>.ic{margin-top:1px;color:var(--accent-text);flex:none}
  .hm-mrow__m{flex:1;min-width:0}
  .hm-mrow__n{font-size:13px;font-weight:600;color:var(--text-primary);display:flex;align-items:center;gap:8px}
  .hm-mrow__s{font-size:11px;color:var(--text-muted);margin-top:3px;line-height:1.45}
  .hm-kbd{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);border:1px solid var(--border-subtle);border-radius:5px;padding:1px 5px;background:var(--bg-subtle);margin-left:auto;flex:none}
  .hm-modepill{display:inline-flex;align-items:center;gap:7px;height:31px;padding:0 11px;border-radius:var(--radius-md);border:1px solid var(--border-default);background:var(--bg-subtle);color:var(--text-primary);font-size:12.5px;font-weight:600;cursor:pointer;font-family:var(--font-sans);white-space:nowrap;transition:var(--transition-control)}
  .hm-modepill:hover{background:var(--bg-hover);border-color:var(--border-strong)}
  .hm-modepill>.ic{color:var(--accent-text)}
  .hm-chip{display:inline-flex;align-items:center;gap:7px;height:31px;padding:0 10px;border-radius:var(--radius-md);border:1px solid var(--border-default);background:var(--bg-raised);color:var(--text-primary);font-size:12.5px;font-weight:600;cursor:pointer;font-family:var(--font-mono);white-space:nowrap;transition:var(--transition-control)}
  .hm-chip:hover{background:var(--bg-hover);border-color:var(--border-strong)}
  .hm-chip__eff{color:var(--text-muted);font-weight:500}
  .hm-to{font-family:var(--font-mono);font-size:11px;color:var(--text-faint)}
  .hm-team{display:inline-flex;align-items:center;gap:8px;height:28px;padding:0 9px 0 7px;border-radius:var(--radius-pill);border:1px solid var(--border-default);background:var(--bg-raised);cursor:pointer;transition:var(--transition-control);font-family:var(--font-sans)}
  .hm-team:hover{border-color:var(--border-strong);background:var(--bg-hover)}
  .hm-team__stack{display:flex}
  .hm-team__stack img,.hm-team__stack .t{width:18px;height:18px;border-radius:5px;margin-left:-6px;border:1.5px solid var(--bg-surface);background:var(--bg-active);display:flex;align-items:center;justify-content:center}
  .hm-team__stack>:first-child{margin-left:0}
  .hm-team__lbl{font-size:12px;font-weight:600;color:var(--text-secondary)}
  .hm-team__dot{width:7px;height:7px;border-radius:50%;background:var(--green-500)}`;
  document.head.appendChild(s);
})();

const BENCH_ROWS = [
  ['claude', 'Anthropic · Opus 4.8', true],
  ['sonnet', 'Anthropic · claude-cli', true],
  ['grok', 'xAI · grok-4', true],
  ['gemini', 'Google · gemini-3-pro', true],
  ['gpt', 'OpenAI · Codex CLI', false, 'Not signed in'],
  ['composer', 'Cursor · composer-1', false, 'Not detected'],
];
const EXEC_IDS = ['claude', 'gpt', 'grok', 'composer'];
const FAN_LANES = [['build', 'Build', 'hammer'], ['design', 'Design', 'image'], ['copy', 'Copy', 'file-text']];
const FAN_TEAMS = {
  build: [['bd-light', 'Light review', '3 workers', true], ['bd-full', 'Full review', '6 workers'], ['bd-sec', 'Security pass', '3 workers · custom']],
  design: [['ds-std', 'Standard board', '4 mockups', true], ['ds-brand', 'Brand pass', '2 mockups · custom']],
  copy: [['cp-land', 'Landing page', '4 versions', true], ['cp-launch', 'Aggressive launch', '6 versions · custom']],
};
const EFFORT_OPTS = [['low', 'Low'], ['med', 'Med'], ['high', 'High']];
const MODE_INFO = {
  chat: ['Chat', 'message-square', '\u23181', 'One model answers — route the turn to anyone.'],
  fanout: ['Fan out', 'layers', '\u23182', 'A team answers in parallel \u2192 a board to compare and pick.'],
  exec: ['Execute', 'hammer', '\u23183', 'An agent runs it in your repo and the result returns here.'],
};
const defTeamFor = (lane) => (FAN_TEAMS[lane].find((t) => t[3]) || FAN_TEAMS[lane][0])[0];

function EffortRow({ effort, setEffort, note }) {
  return <div className="hm-eff">
    <span className="hm-eff__l">Effort</span>
    <span className="hm-seg">{EFFORT_OPTS.map(([v, l]) =>
      <button key={v} className={effort === v ? 'is-on' : ''} onClick={() => setEffort(v)}>{l}</button>)}</span>
    {note && <span className="hm-eff__note">{note}</span>}
  </div>;
}

function TeamControl() {
  const [open, setOpen] = RA.useState(false);
  const top = ['claude', 'sonnet', 'grok', 'gemini'];
  return <span className="hm-popwrap">
    <button className="hm-team" onClick={() => setOpen((o) => !o)} aria-label="Your team">
      <span className="hm-team__stack">{top.map((k, i) => W[k].brand
        ? <img key={i} src={`https://cdn.simpleicons.org/${W[k].brand}/${W[k].color}`} alt="" />
        : <span key={i} className="t"><Ico name={W[k].icon || 'terminal'} size={11} style={{ color: 'var(--text-secondary)' }} /></span>)}</span>
      <span className="hm-team__lbl">Team</span>
      <span className="hm-team__dot" />
      <Ico name="chevron-down" size={13} style={{ color: 'var(--text-faint)' }} />
    </button>
    {open && <>
      <div className="hm-popbd" onClick={() => setOpen(false)} />
      <div className="hm-pop hm-pop--down hm-pop--right" style={{ width: 306 }}>
        <div className="hm-pop__hd">
          <div className="hm-pop__t">Your bench</div>
          <div className="hm-pop__s">4 of 6 models ready</div>
        </div>
        <div className="hm-pop__list">{BENCH_ROWS.map(([k, sub, ready, note]) =>
          <div key={k} className="hm-opt" style={{ cursor: 'default' }}>
            <span className="hm-opt__g"><G w={W[k]} size={15} /></span>
            <span className="hm-opt__m">
              <span className="hm-opt__n">{W[k].name}</span>
              <span className="hm-opt__s">{sub}</span>
            </span>
            {ready
              ? <span className="hm-team__dot" />
              : <HBadge tone="warning">{note}</HBadge>}
          </div>)}</div>
        <div className="hm-pop__ft">
          <HB variant="secondary" size="sm" iconLeft={<Ico name="settings-2" size={13} />}>Manage team</HB>
          <span className="hm-pop__ftnote">Add models &amp; build teams in&nbsp;settings.</span>
        </div>
      </div>
    </>}
  </span>;
}

function Composer({ big, lane: threadLane, defaultMode }) {
  const startLane = ['build', 'design', 'copy'].includes(threadLane) ? threadLane : 'design';
  const [mode, setMode] = RA.useState(defaultMode || 'chat');
  const [to, setTo] = RA.useState('claude');
  const [effort, setEffort] = RA.useState('med');
  const [lane, setLane] = RA.useState(startLane);
  const [team, setTeam] = RA.useState(defTeamFor(startLane));
  const [pop, setPop] = RA.useState(null);
  // re-seed the armed verb when the active thread (and thus its default) changes
  RA.useEffect(() => { setMode(defaultMode || 'chat'); }, [defaultMode]);

  const modeInfo = MODE_INFO[mode];
  const effLabel = EFFORT_OPTS.find((e) => e[0] === effort)[1];
  const laneRow = FAN_LANES.find((l) => l[0] === lane);

  const pickMode = (k) => {
    setMode(k);
    if (k === 'exec' && !EXEC_IDS.includes(to)) setTo('claude');
    setPop(k === 'fanout' ? 'target' : null);
  };
  const pickLane = (l) => { setLane(l); setTeam(defTeamFor(l)); };

  const chipGlyph = mode === 'fanout'
    ? <Ico name={laneRow[2]} size={14} style={{ color: 'var(--accent-text)' }} />
    : <G w={W[to]} size={15} />;
  const chipName = mode === 'fanout' ? laneRow[1] + ' team' : W[to].name;

  const ModelList = (ids, title, sub, note) => <>
    <div className="hm-pop__hd"><div className="hm-pop__t">{title}</div><div className="hm-pop__s">{sub}</div></div>
    <div className="hm-pop__list">{ids.map((k) => {
      const row = BENCH_ROWS.find((r) => r[0] === k);
      const ready = row[2];
      return <button key={k} className="hm-opt" disabled={!ready} onClick={() => { setTo(k); }}>
        <span className="hm-opt__g"><G w={W[k]} size={15} /></span>
        <span className="hm-opt__m"><span className="hm-opt__n">{W[k].name}</span><span className="hm-opt__s">{row[1]}</span></span>
        {ready && to === k && <Ico name="check" size={14} className="hm-opt__chk" />}
        {!ready && <HBadge tone="warning">{row[3]}</HBadge>}
      </button>;
    })}</div>
    <EffortRow effort={effort} setEffort={setEffort} note={note} />
  </>;

  let popBody = null;
  if (pop === 'target' && mode === 'chat') popBody = ModelList(BENCH_ROWS.map((r) => r[0]), 'Route to model', 'One model answers this turn', 'Higher effort = more reasoning time.');
  else if (pop === 'target' && mode === 'exec') popBody = ModelList(EXEC_IDS, 'Hand to executor', 'An agent runs it in your repo', 'Higher effort = more reasoning time.');
  else if (pop === 'target' && mode === 'fanout') popBody = <>
    <div className="hm-pop__hd"><div className="hm-pop__t">Send to team</div><div className="hm-pop__s">Pick the lane, then the lineup</div></div>
    <div className="hm-lanetabs">{FAN_LANES.map(([l, nm, ic]) =>
      <button key={l} className={'hm-lanetab' + (lane === l ? ' is-on' : '')} onClick={() => pickLane(l)}><Ico name={ic} size={13} className="ic" />{nm}</button>)}</div>
    <div className="hm-pop__list">{FAN_TEAMS[lane].map(([id, nm, sub, def]) =>
      <button key={id} className="hm-opt" onClick={() => setTeam(id)}>
        <span className="hm-opt__g"><Ico name={laneRow[2]} size={14} style={{ color: 'var(--accent-text)' }} /></span>
        <span className="hm-opt__m"><span className="hm-opt__n">{nm}{def && <span className="hm-opt__def">default</span>}</span><span className="hm-opt__s">{sub}</span></span>
        {team === id && <Ico name="check" size={14} className="hm-opt__chk" />}
      </button>)}</div>
    <div className="hm-pop__ft"><HB variant="ghost" size="sm" iconLeft={<Ico name="settings-2" size={13} />}>Customize…</HB><span className="hm-pop__ftnote">Build &amp; edit teams in settings.</span></div>
    <EffortRow effort={effort} setEffort={setEffort} note="Higher effort = more workers + a deeper pass." />
  </>;

  return <div className="hm-comp" style={big ? { borderTop: 'none', padding: 0, width: '100%', maxWidth: 640 } : null}>
    <div className="hm-comp__box">
      <textarea rows={big ? 3 : 2} placeholder={big ? 'Describe the work — a question, a screen to redesign, a change to ship…' : 'Reply, or start the next turn…'} />
      <div className="hm-comp__bar">
        <span className="hm-popwrap">
          <button className="hm-modepill" onClick={() => setPop(pop === 'mode' ? null : 'mode')}>
            <Ico name={modeInfo[1]} size={14} className="ic" />{modeInfo[0]}<Ico name="chevron-down" size={12} style={{ color: 'var(--text-faint)' }} />
          </button>
          {pop === 'mode' && <>
            <div className="hm-popbd" onClick={() => setPop(null)} />
            <div className="hm-pop" style={{ width: 300 }}>
              {Object.keys(MODE_INFO).map((k) => {
                const m = MODE_INFO[k];
                return <button key={k} className={'hm-mrow' + (mode === k ? ' is-on' : '')} onClick={() => pickMode(k)}>
                  <Ico name={m[1]} size={16} className="ic" />
                  <span className="hm-mrow__m">
                    <span className="hm-mrow__n">{m[0]}{mode === k && <Ico name="check" size={13} style={{ color: 'var(--accent-text)' }} />}<span className="hm-kbd">{m[2]}</span></span>
                    <span className="hm-mrow__s">{m[3]}</span>
                  </span>
                </button>;
              })}
            </div>
          </>}
        </span>
        {mode !== 'fanout' && <span className="hm-to">to</span>}
        <span className="hm-popwrap">
          <button className="hm-chip" onClick={() => setPop(pop === 'target' ? null : 'target')}>
            {chipGlyph}<span>{chipName}</span><span className="hm-chip__eff">· {effLabel}</span><Ico name="chevron-down" size={12} style={{ color: 'var(--text-faint)' }} />
          </button>
          {pop === 'target' && <>
            <div className="hm-popbd" onClick={() => setPop(null)} />
            <div className="hm-pop" style={{ width: mode === 'fanout' ? 320 : 296 }}>{popBody}</div>
          </>}
        </span>
        <span style={{ flex: 1 }} />
        <HIB variant="ghost" size="sm" label="Attach image"><Ico name="image-plus" size={16} /></HIB>
        <button className="hm-send" aria-label={'Send — ' + modeInfo[0]}><Ico name="arrow-right" size={16} /></button>
      </div>
    </div>
    <div className="hm-comp__hint">
      <Ico name="corner-down-right" size={12} />
      {modeInfo[3]}
    </div>
  </div>;
}

/* ===================== thread pane ===================== */
function ThreadPane({ t, onOpenBoard }) {
  return RA.createElement('div', { className: 'hm-thread' },
    RA.createElement('div', { className: 'hm-th__hd' },
      RA.createElement('span', { className: 'hm-th__t' }, t.title),
      RA.createElement('span', { className: 'hm-th__tags' },
        RA.createElement(HBadge, { tone: t.lane === 'design' ? 'accent' : t.lane === 'build' ? 'info' : 'neutral' },
          RA.createElement(Ico, { name: LN[t.lane].icon, size: 11, style: { marginRight: 4 } }), t.lane)),
      RA.createElement('span', { style: { flex: 1 } }),
      RA.createElement('span', { className: 'hm-th__route' }, 'routed across', RA.createElement(Stack, { ws: t.workers })),
      RA.createElement(Mena, { align: 'end', trigger: RA.createElement(HIB, { variant: 'ghost', size: 'sm', label: 'More' }, RA.createElement(Ico, { name: 'more-horizontal' })),
        items: [{ label: 'Rename', icon: RA.createElement(Ico, { name: 'file-text' }) }, { label: t.pinned ? 'Unpin' : 'Pin', icon: RA.createElement(Ico, { name: 'corner-down-right' }) }, { divider: true }, { label: 'Archive', icon: RA.createElement(Ico, { name: 'x' }), danger: true }] })),
    RA.createElement('div', { className: 'hm-turns' },
      (t.turns || []).map((tn, i) => {
        if (tn.kind === 'user') return RA.createElement(TurnUser, { key: i, t: tn });
        if (tn.kind === 'chat') return RA.createElement(TurnChat, { key: i, t: tn });
        if (tn.kind === 'fanout') return RA.createElement(TurnFanout, { key: i, t: tn, onOpen: onOpenBoard });
        if (tn.kind === 'exec') return RA.createElement(TurnExec, { key: i, t: tn });
        return null;
      })),
    RA.createElement(Composer, { lane: t.lane, defaultMode: t.state === 'spec' ? 'exec' : 'chat' }));
}

function NewPane() {
  return RA.createElement('div', { className: 'hm-thread' },
    RA.createElement('div', { className: 'hm-empty' },
      RA.createElement(window.DCLive, { size: 38 }),
      RA.createElement('div', { className: 'hm-empty__t' }, 'Start a work order'),
      RA.createElement('div', { className: 'hm-empty__s' }, 'One message in. Chat with a single model, fan it out to the whole bench for options, or hand it to an agent to build — and route any turn to anyone.'),
      RA.createElement('div', { className: 'hm-bench' }, RA.createElement('span', { className: 'hm-stt__d', style: { background: 'var(--green-500)', width: 6, height: 6, borderRadius: '50%' } }), '6 models on the bench · ready'),
      RA.createElement('div', { style: { width: '100%', display: 'flex', justifyContent: 'center', marginTop: 18 } }, RA.createElement(Composer, { big: true }))));
}

/* ===================== app ===================== */
function HomeApp() {
  const [sel, setSel] = RA.useState('profile');
  const t = THREADS.find((x) => x.id === sel);
  const I = window.DCIcon;
  return RA.createElement('div', { className: 'hm-win' },
    RA.createElement('div', { className: 'hm-title' },
      RA.createElement('div', { className: 'hm-lights' },
        RA.createElement('i', { style: { background: '#FF5F57' } }), RA.createElement('i', { style: { background: '#FEBC2E' } }), RA.createElement('i', { style: { background: '#28C840' } })),
      RA.createElement('div', { className: 'hm-tc' }, RA.createElement(window.DCLive, { size: 16, run: true }), RA.createElement('span', { className: 'nm' }, 'allnighter')),
      RA.createElement('div', { className: 'hm-tr' },
        RA.createElement(TeamControl, null),
        RA.createElement(HIB, { variant: 'ghost', size: 'sm', label: 'History' }, RA.createElement(I, { name: 'history' })),
        RA.createElement(HIB, { variant: 'ghost', size: 'sm', label: 'Settings' }, RA.createElement(I, { name: 'settings-2' })))),
    RA.createElement('div', { className: 'hm-body' },
      RA.createElement(Sidebar, { sel, onSel: setSel, onNew: () => setSel(null) }),
      sel && t ? RA.createElement(ThreadPane, { t, onOpenBoard: () => { window.location.href = '../design-council/index.html'; } }) : RA.createElement(NewPane, null)));
}
function FirstRun() {
  const I = window.DCIcon;
  const bench = ['claude', 'gpt', 'grok', 'gemini', 'composer', 'sonnet'];
  const cli = { claude: 'claude-code', gpt: 'codex', grok: 'grok', gemini: 'antigravity', composer: 'cursor', sonnet: 'claude-code' };
  const ex = [
    ['message-square', 'Chat', 'Ask the bench a question — “token bucket or sliding window for rate limiting?”'],
    ['layers', 'Fan out', 'Drop a screenshot — “make this profile feel premium and clean” → a board of options.'],
    ['hammer', 'Execute', 'Point an agent at your repo — “add the 429 + Retry-After path to the limiter.”'],
  ];
  return <div className="hm-win">
    <div className="hm-title">
      <div className="hm-lights"><i style={{ background: '#FF5F57' }} /><i style={{ background: '#FEBC2E' }} /><i style={{ background: '#28C840' }} /></div>
      <div className="hm-tc">{React.createElement(window.DCLive, { size: 16, run: true })}<span className="nm">allnighter</span></div>
      <div className="hm-tr"><TeamControl /><HIB variant="ghost" size="sm" label="Settings"><I name="settings-2" /></HIB></div>
    </div>
    <div className="hm-body">
      <aside className="hm-side">
        <div className="hm-side__top">
          <button className="hm-new"><Ico name="plus" size={16} />New work order</button>
          <div className="hm-search"><Ico name="search" size={14} /><input placeholder="Search conversations" /></div>
          <div className="hm-filters">{[['all', 'All'], ['design', 'Design'], ['build', 'Build'], ['running', 'Running']].map(([k, l]) => <button key={k} className={'hm-fchip' + (k === 'all' ? ' is-on' : '')}>{l}</button>)}</div>
        </div>
        <div className="hm-list"><div className="fr-emptyhint">{React.createElement(window.DCLive, { size: 28 })}<div style={{ fontWeight: 600, color: 'var(--text-secondary)' }}>No conversations yet</div><div style={{ color: 'var(--text-faint)', maxWidth: 210, lineHeight: 1.5 }}>Your work orders will live here — newest on top.</div></div></div>
      </aside>
      <div className="hm-thread">
        <div className="fr-wrap">
          {React.createElement(window.DCLive, { size: 42, run: true })}
          <div className="fr-h">You already pay for the team.</div>
          <div className="fr-s">Allnighter puts the AI tools you already subscribe to on one bench. Ask one, ask them all, or hand the work to an agent — and route any turn to anyone.</div>
          <div className="fr-bench">{bench.map((k, i) => <div className="fr-w" key={i}><G w={W[k]} size={16} /><span className="fr-w__n">{W[k].name}</span><span className="fr-w__c">{cli[k]}</span><span className="fr-w__d" /></div>)}</div>
          <div className="fr-ex">{ex.map((e, i) => <div className="fr-card" key={i}><div className="fr-card__h"><Ico name={e[0]} size={15} style={{ color: 'var(--accent-text)' }} />{e[1]}</div><div className="fr-card__t">{e[2]}</div></div>)}</div>
          <div style={{ width: '100%', display: 'flex', justifyContent: 'center', marginTop: 8 }}><Composer big /></div>
        </div>
      </div>
    </div>
  </div>;
}
window.HomeApp = HomeApp;
window.HomeFirstRun = FirstRun;
