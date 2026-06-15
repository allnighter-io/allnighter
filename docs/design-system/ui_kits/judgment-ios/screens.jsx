// @ds-adherence-ignore -- iOS review: Inbox, Compose+CallPlan, Review board.
const { Button, Icon, Badge, StatusPill, BrandIcon } = window;

(function () {
  if (document.getElementById('jio-css')) return;
  const s = document.createElement('style'); s.id = 'jio-css';
  s.textContent = `
  .jio-app{height:100%;display:flex;flex-direction:column;background:var(--bg-base);color:var(--text-primary);font-family:var(--font-sans)}
  .jio-scroll{flex:1;overflow:auto;padding:50px 18px 22px}
  .jio-hdr{display:flex;align-items:center;gap:9px;margin-bottom:16px}
  .jio-hdr .wm{font-family:var(--font-display);font-weight:800;font-size:18px;letter-spacing:-.02em;flex:1}
  .jio-back{display:flex;align-items:center;gap:6px;background:none;border:none;color:var(--text-muted);font-size:14px;font-weight:600;cursor:pointer;padding:0;margin-bottom:14px}
  .jio-h1{font-family:var(--font-display);font-size:26px;font-weight:800;letter-spacing:-.02em}
  .jio-sub{color:var(--text-muted);font-size:14px;margin-top:5px}
  .jio-sect{font-size:12px;font-weight:700;letter-spacing:.06em;text-transform:uppercase;color:var(--text-faint);margin:22px 0 11px}
  .jio-card{display:block;width:100%;text-align:left;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:15px;padding:15px;margin-bottom:10px;cursor:pointer;font-family:inherit}
  .jio-card.accent{border-color:var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.06),transparent 60%),var(--bg-raised)}
  .jio-row{display:flex;align-items:center;gap:12px}
  .jio-ic{width:36px;height:36px;border-radius:10px;display:flex;align-items:center;justify-content:center;flex:none}
  .jio-ic svg{width:19px;height:19px}
  .jio-main{flex:1;min-width:0;display:flex;flex-direction:column}
  .jio-t{font-size:15px;font-weight:600;line-height:1.25}
  .jio-m{font-family:var(--font-mono);font-size:11px;color:var(--text-faint);margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .jio-prog{height:4px;border-radius:3px;background:var(--bg-active);margin-top:12px;overflow:hidden}
  .jio-prog>i{display:block;height:100%;background:var(--accent);border-radius:3px}
  .jio-cta{display:flex;align-items:center;justify-content:center;gap:8px;width:100%;height:50px;border:none;border-radius:13px;background:var(--accent);color:var(--text-on-amber);font-family:inherit;font-size:16px;font-weight:600;cursor:pointer}
  .jio-cta:active{transform:scale(.98)}
  .jio-cta svg{width:18px;height:18px}
  .jio-preset{display:flex;align-items:center;gap:12px;width:100%;text-align:left;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:13px;padding:13px;margin-bottom:9px;cursor:pointer;font-family:inherit}
  .jio-preset.on{border-color:var(--accent);background:linear-gradient(180deg,rgba(255,166,48,.06),transparent),var(--bg-raised)}
  .jio-radio{width:20px;height:20px;border-radius:50%;border:2px solid var(--border-strong);flex:none;display:flex;align-items:center;justify-content:center}
  .jio-preset.on .jio-radio{border-color:var(--accent);background:var(--accent)}
  .jio-radio svg{width:11px;height:11px;color:var(--text-on-amber);opacity:0}
  .jio-preset.on .jio-radio svg{opacity:1}
  .jio-presn{font-size:15px;font-weight:600}.jio-presd{font-size:12px;color:var(--text-muted);margin-top:2px}
  .jio-plan{background:var(--bg-surface);border:1px solid var(--border-subtle);border-radius:13px;padding:14px;margin-top:6px}
  .jio-planr{display:flex;justify-content:space-between;align-items:center;gap:10px;font-family:var(--font-mono);font-size:13px;color:var(--text-secondary);padding:5px 0}
  .jio-planr span{white-space:nowrap}
  .jio-ta{width:100%;box-sizing:border-box;background:var(--bg-input);border:1px solid var(--border-default);border-radius:13px;color:var(--text-primary);font-family:inherit;font-size:17px;line-height:1.45;padding:14px;resize:none;outline:none}
  .jio-ta:focus{border-color:var(--accent-border)}
  .jio-strip{display:flex;align-items:center;gap:6px;margin-bottom:16px;flex-wrap:wrap}
  .jio-pip{display:flex;align-items:center;gap:5px;font-family:var(--font-mono);font-size:10px;color:var(--text-faint)}
  .jio-pip .d{width:7px;height:7px;border-radius:50%}
  .jio-lens__hd{display:flex;align-items:center;gap:11px;margin-bottom:11px}
  .jio-lens__t{flex:1;min-width:0}
  .jio-lens__n{font-size:15px;font-weight:600}
  .jio-lens__w{font-family:var(--font-mono);font-size:11px;color:var(--text-faint);margin-top:1px}
  .jio-conc{display:flex;gap:9px;font-size:13px;color:var(--text-secondary);line-height:1.45;padding:5px 0}
  .jio-conc .dot{flex:none;width:6px;height:6px;border-radius:50%;margin-top:6px}
  .jio-tabbar{flex:none;display:flex;background:var(--bg-surface);border-top:1px solid var(--border-subtle);padding:9px 0 26px}
  .jio-tab{flex:1;display:flex;flex-direction:column;align-items:center;gap:4px;border:none;background:transparent;color:var(--text-faint);font-size:10px;font-weight:600;cursor:pointer;font-family:inherit}
  .jio-tab svg{width:23px;height:23px}.jio-tab.on{color:var(--accent-text)}
  .jio-actionbar{flex:none;padding:12px 18px 30px;background:var(--bg-surface);border-top:1px solid var(--border-subtle)}`;
  document.head.appendChild(s);
})();

const JLM = ({ size = 22, run }) => React.createElement('svg', { width: size, height: size, viewBox: '0 0 100 100',
  dangerouslySetInnerHTML: { __html: `<defs><linearGradient id="jiolm" x1="20" y1="24" x2="66" y2="80" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFD79E"/><stop offset=".5" stop-color="#FFA630"/><stop offset="1" stop-color="#F0901C"/></linearGradient><mask id="jiocm"><rect width="100" height="100" fill="black"/><circle cx="47" cy="50" r="32" fill="white"/><circle cx="62" cy="41" r="28" fill="black"/></mask></defs><rect width="100" height="100" fill="url(#jiolm)" mask="url(#jiocm)"/>` + (run ? '<rect x="60" y="43" width="10.5" height="17" rx="2.6" fill="#FFE9C6"><animate attributeName="opacity" values="1;1;0;0" dur="1.05s" repeatCount="indefinite"/></rect>' : '') } });

/* ===== Inbox ===== */
const INBOX = [
  { id: 'r1', t: 'Rate limiting API', m: 'light_review · final spec ready', icon: 'circle-check', bg: 'var(--accent-surface)', fg: 'var(--accent-text)', tag: ['accent', 'implement'], accent: true, go: 'review' },
  { id: 'r2', t: 'Onboarding redesign', m: 'review board · 1 blocker · 2 concerns', icon: 'shield', bg: 'var(--danger-surface)', fg: 'var(--red-400)', tag: ['danger', '1 blocker'], go: 'review' },
  { id: 'r3', t: 'Email parser refactor', m: 'Opus returned · score 0.86', icon: 'rotate-cw', bg: 'var(--info-surface)', fg: 'var(--blue-400)', tag: ['info', 'review it'], go: 'review' },
];
function InboxScreen({ open }) {
  return (
    <div>
      <div className="jio-hdr"><JLM size={24} /><span className="wm">allnighter</span><Icon name="settings-2" size={21} style={{ color: 'var(--text-muted)' }} /></div>
      <div className="jio-h1">Needs you</div>
      <div className="jio-sub">3 runs waiting on a decision</div>
      <div className="jio-sect">Decide</div>
      {INBOX.map((r) => (
        <button className={'jio-card' + (r.accent ? ' accent' : '')} key={r.id} onClick={() => open(r.go)}>
          <div className="jio-row">
            <span className="jio-ic" style={{ background: r.bg, color: r.fg }}><Icon name={r.icon} size={19} /></span>
            <span className="jio-main"><span className="jio-t">{r.t}</span><span className="jio-m">{r.m}</span></span>
            <Badge tone={r.tag[0]} dot>{r.tag[1]}</Badge>
          </div>
        </button>
      ))}
      <div className="jio-sect">Running</div>
      <button className="jio-card" onClick={() => open('liverun')}>
        <div className="jio-row">
          <span className="jio-ic" style={{ background: 'var(--info-surface)', color: 'var(--blue-400)' }}><Icon name="users" size={19} /></span>
          <span className="jio-main"><span className="jio-t">Cache invalidation plan</span><span className="jio-m">full_review · review board · 6 of 9 lenses</span></span>
          <StatusPill status="running" />
        </div>
        <div className="jio-prog"><i style={{ width: '67%' }}></i></div>
      </button>
    </div>
  );
}

/* ===== Compose ===== */
function ComposeScreen() {
  const [preset, setPreset] = React.useState('light');
  const calls = preset === 'syn' ? 2 : preset === 'light' ? 6 : 12;
  return (
    <div>
      <div className="jio-h1" style={{ marginBottom: 16 }}>New run</div>
      <textarea className="jio-ta" rows={3} defaultValue="Add per-user rate limiting to the public API." />
      <div className="jio-sect">Workflow</div>
      {[['syn', 'Synthesis only', 'Daily driver · fast'], ['light', 'Light review', '3 lenses + final spec'], ['full', 'Full review', 'All lenses · big bets']].map((p) => (
        <button className={'jio-preset' + (preset === p[0] ? ' on' : '')} key={p[0]} onClick={() => setPreset(p[0])}>
          <span className="jio-radio"><Icon name="check" size={11} stroke={3.5} /></span>
          <span className="jio-main"><span className="jio-presn">{p[1]}</span><span className="jio-presd">{p[2]}</span></span>
        </button>
      ))}
      <div className="jio-sect">Call plan</div>
      <div className="jio-plan">
        <div className="jio-planr"><span style={{ color: 'var(--text-faint)' }}>team · 5 workers</span><span><Badge tone="positive" mono>reused</Badge></span></div>
        <div className="jio-planr"><span style={{ color: 'var(--text-faint)' }}>fresh model calls</span><span style={{ color: 'var(--accent-text)', fontWeight: 600 }}>~{calls}</span></div>
        <div className="jio-planr" style={{ color: 'var(--text-faint)', fontSize: 11 }}><span>est. 3–5 min · $0 marginal · local</span><span>estimate</span></div>
      </div>
    </div>
  );
}

/* ===== Review board ===== */
const LENSES = [
  { n: 'Security & privacy', w: 'Gemini Flash · fast', v: 'blocker', vt: 'danger', bg: 'var(--danger-surface)', fg: 'var(--red-400)', c: ['Counter store is written to a world-readable path — token leak.', 'Reset endpoint has no auth.'] },
  { n: 'Code maintainer', w: 'Sonnet 4.6', v: 'concerns', vt: 'warning', bg: 'var(--warning-surface)', fg: 'var(--yellow-400)', c: ['Two sources of truth for the window — collapse to one.'] },
  { n: 'Proof / QA', w: 'ChatGPT 5.5 · fast', v: 'concerns', vt: 'warning', bg: 'var(--warning-surface)', fg: 'var(--yellow-400)', c: ['No Works Test for the 429 path or reset boundary.'] },
];
const PIPS = [['Team', 'done'], ['Analysis', 'done'], ['Plan', 'done'], ['Review', 'run'], ['Final', 'idle']];
const PIPC = { done: 'var(--green-500)', run: 'var(--blue-500)', idle: 'var(--ink-500)' };
function ReviewScreen({ back, onAnalysis }) {
  return (
    <div>
      <button className="jio-back" onClick={back}><Icon name="chevron-right" size={16} style={{ transform: 'rotate(180deg)' }} /> Inbox</button>
      <div className="jio-h1" style={{ fontSize: 22 }}>Rate limiting API</div>
      <div className="jio-strip" style={{ marginTop: 12 }}>
        {PIPS.map((p, i) => (<React.Fragment key={i}><span className="jio-pip"><span className="d" style={{ background: PIPC[p[1]] }}></span>{p[0]}</span>{i < PIPS.length - 1 && <span style={{ color: 'var(--text-faint)' }}>›</span>}</React.Fragment>))}
      </div>
      {onAnalysis && <button className="jio-back" style={{ marginTop: 4, color: 'var(--accent-text)' }} onClick={onAnalysis}><Icon name="scale" size={15} /> View plan writer analysis</button>}
      <div className="jio-row" style={{ marginBottom: 14 }}>
        <span style={{ flex: 1, fontSize: 13, fontWeight: 700, letterSpacing: '.06em', textTransform: 'uppercase', color: 'var(--text-faint)' }}>Review board</span>
        <Badge tone="danger" dot>1 blocker</Badge><Badge tone="warning" dot>2 concerns</Badge>
      </div>
      {LENSES.map((l, i) => (
        <div className="jio-card" key={i} style={{ cursor: 'default' }}>
          <div className="jio-lens__hd">
            <span className="jio-ic" style={{ background: l.bg, color: l.fg, width: 32, height: 32 }}><Icon name="shield" size={16} /></span>
            <span className="jio-lens__t"><span className="jio-lens__n">{l.n}</span><span className="jio-lens__w">{l.w}</span></span>
            <Badge tone={l.vt} dot>{l.v}</Badge>
          </div>
          {l.c.map((c, j) => (<div className="jio-conc" key={j}><span className="dot" style={{ background: l.fg }}></span>{c}</div>))}
        </div>
      ))}
      <div style={{ color: 'var(--text-muted)', fontSize: 12, padding: '4px 2px' }}>Advisory only — the draft plan is never overwritten.</div>
    </div>
  );
}

window.JIOSApp = function JIOSApp() {
  const [tab, setTab] = React.useState('inbox');
  const [detail, setDetail] = React.useState(null);
  const screen = detail === 'review' ? <ReviewScreen back={() => setDetail(null)} />
    : tab === 'inbox' ? <InboxScreen open={setDetail} />
    : <ComposeScreen />;
  const showAction = detail === 'review';
  return (
    <div className="jio-app">
      <div className="jio-scroll">{screen}</div>
      {showAction && (
        <div className="jio-actionbar"><button className="jio-cta"><Icon name="arrow-right" size={18} /> View final spec</button></div>
      )}
      {!detail && (
        <div className="jio-tabbar">
          {[['inbox', 'Inbox', 'moon'], ['compose', 'Compose', 'plus']].map(([id, label, icon]) => (
            <button key={id} className={'jio-tab' + (tab === id ? ' on' : '')} onClick={() => setTab(id)}><Icon name={icon} size={23} /><span>{label}</span></button>
          ))}
        </div>
      )}
    </div>
  );
};
Object.assign(window, { JIOS_Inbox: InboxScreen, JIOS_Compose: ComposeScreen, JIOS_Review: ReviewScreen, JIOS_Live: JLM });
