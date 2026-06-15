// @ds-adherence-ignore -- iOS judgment batch 2: Final spec, Dispatch, Return.
const { Button, Icon, Badge, StatusPill, BrandIcon } = window;

(function () {
  if (document.getElementById('jio2-css')) return;
  const s = document.createElement('style'); s.id = 'jio2-css';
  s.textContent = `
  .ji2-banner{display:flex;align-items:center;gap:9px;padding:11px 13px;border-radius:12px;margin-bottom:18px;background:var(--success-surface);border:1px solid rgba(63,209,139,.3);color:var(--green-400);font-size:13px;font-weight:600}
  .ji2-sec{margin-bottom:18px}
  .ji2-sec__h{font-size:11px;font-weight:700;letter-spacing:.07em;text-transform:uppercase;color:var(--accent-text);margin-bottom:8px;display:flex;align-items:center;gap:7px}
  .ji2-p{font-size:14px;color:var(--text-secondary);line-height:1.55;margin:0}
  .ji2-li{display:flex;gap:10px;font-size:14px;color:var(--text-secondary);line-height:1.5;padding:5px 0}
  .ji2-li .n{flex:none;width:19px;height:19px;border-radius:50%;background:var(--accent-surface);color:var(--accent-text);font-family:var(--font-mono);font-size:10px;font-weight:600;display:flex;align-items:center;justify-content:center;margin-top:1px}
  .ji2-code{font-family:var(--font-mono);font-size:12px;line-height:1.7;color:var(--text-secondary);background:var(--bg-void);border:1px solid var(--border-subtle);border-radius:11px;padding:12px 13px;white-space:pre-wrap;word-break:break-word}
  .ji2-code .ok{color:var(--green-400)}.ji2-code .c{color:var(--text-faint)}
  .ji2-decrow{display:flex;align-items:center;gap:9px;padding:8px 0;border-bottom:1px solid var(--border-subtle);font-size:13px;color:var(--text-secondary)}
  .ji2-decrow:last-child{border-bottom:none}
  .ji2-decrow .who{flex:1;color:var(--text-primary);font-weight:600}
  .ji2-dec{font-family:var(--font-sans);font-size:10px;font-weight:700;padding:2px 7px;border-radius:5px}
  .ji2-bound{display:flex;gap:10px;padding:13px;background:var(--warning-surface);border:1px solid rgba(245,200,75,.3);border-radius:12px;margin-bottom:18px}
  .ji2-bound svg{color:var(--yellow-400);flex:none;margin-top:1px}.ji2-bound .t{font-size:13px;color:var(--text-secondary);line-height:1.5}.ji2-bound b{color:var(--text-primary)}
  .ji2-row{display:flex;align-items:center;gap:11px;padding:12px 0;border-bottom:1px solid var(--border-subtle)}
  .ji2-row .l{width:120px;flex:none;font-size:13px;font-weight:500;color:var(--text-secondary)}
  .ji2-g{width:26px;height:26px;border-radius:7px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;overflow:hidden;flex:none}
  .ji2-g img{width:16px;height:16px}
  .ji2-term{font-family:var(--font-mono);font-size:12px;line-height:1.85;color:var(--text-secondary);background:var(--bg-void);border:1px solid var(--border-subtle);border-radius:11px;padding:12px 13px;margin-top:14px}
  .ji2-term .ok{color:var(--green-400)}.ji2-term .a{color:var(--accent-text)}.ji2-term .c{color:var(--text-faint)}
  .ji2-score{display:flex;align-items:center;gap:14px;padding:16px;background:linear-gradient(180deg,rgba(255,166,48,.08),transparent),var(--bg-raised);border:1px solid var(--accent-border);border-radius:15px;margin-bottom:18px}
  .ji2-score .big{font-family:var(--font-display);font-size:40px;font-weight:800;letter-spacing:-.02em;color:var(--accent-text)}
  .ji2-bar{height:6px;border-radius:4px;background:var(--bg-active);overflow:hidden;margin-top:7px}.ji2-bar>i{display:block;height:100%;background:var(--accent);border-radius:4px}
  .ji2-crit{display:flex;align-items:flex-start;gap:10px;padding:10px 0;border-bottom:1px solid var(--border-subtle)}
  .ji2-crit:last-child{border-bottom:none}
  .ji2-crit svg{flex:none;margin-top:1px}
  .ji2-crit .t{font-size:13px;color:var(--text-primary);line-height:1.4}.ji2-crit .n{font-size:12px;color:var(--text-muted);margin-top:2px}`;
  document.head.appendChild(s);
})();

const Back = ({ onClick, label }) => <button className="jio-back" onClick={onClick}><Icon name="chevron-right" size={16} style={{ transform: 'rotate(180deg)' }} /> {label}</button>;
const DEC = { adopted: ['ADOPTED', 'var(--green-400)', 'var(--success-surface)'], partial: ['PARTIAL', 'var(--yellow-400)', 'var(--warning-surface)'], rejected: ['REJECTED', 'var(--red-400)', 'var(--danger-surface)'] };
const MK = { pass: ['var(--green-400)', 'circle-check'], partial: ['var(--yellow-400)', 'gauge'], fail: ['var(--red-400)', 'x'] };

/* ===== Final spec ===== */
window.JIOS_Final = function FinalSpecScreen({ back }) {
  return (
    <div>
      <Back onClick={back} label="Review board" />
      <div className="jio-h1" style={{ fontSize: 22 }}>final_spec.md</div>
      <div className="jio-sub" style={{ marginBottom: 16 }}>Decision-grade · master plan unchanged</div>
      <div className="ji2-banner"><Icon name="circle-check" size={16} /> Executable — Works Test + proof commands</div>
      <div className="ji2-sec"><div className="ji2-sec__h"><Icon name="list" size={13} /> Scope</div><p className="ji2-p">Token-bucket rate limiting keyed by user ID on all <code>/api/*</code> routes. 100 req/min, per-tier. Return <code>429</code> + <code>Retry-After</code>.</p></div>
      <div className="ji2-sec"><div className="ji2-sec__h"><Icon name="circle-check" size={13} /> Acceptance criteria</div>
        <div className="ji2-li"><span className="n">1</span>101st request in 60s returns 429 + Retry-After.</div>
        <div className="ji2-li"><span className="n">2</span>Limits isolated per user.</div>
        <div className="ji2-li"><span className="n">3</span>Reset endpoint rejects unauthenticated callers.</div>
      </div>
      <div className="ji2-sec"><div className="ji2-sec__h"><Icon name="flask" size={13} /> Works Test</div>
        <div className="ji2-code"><span className="c"># proof commands</span>{'\n'}swift test --filter RateLimitTests{'\n'}./scripts/load-test.sh --user u1 --rps 5</div>
      </div>
      <div className="ji2-sec"><div className="ji2-sec__h"><Icon name="scale" size={13} /> Decisions on review</div>
        {[['Security & privacy', 'adopted'], ['Code maintainer', 'adopted'], ['Proof / QA', 'adopted']].map((d, i) => (
          <div className="ji2-decrow" key={i}><span className="who">{d[0]}</span><span className="ji2-dec" style={{ color: DEC[d[1]][1], background: DEC[d[1]][2] }}>{DEC[d[1]][0]}</span></div>
        ))}
      </div>
    </div>
  );
};

/* ===== Dispatch ===== */
window.JIOS_Dispatch = function DispatchScreen({ back, onReturn }) {
  const [st, setSt] = React.useState('ready'); // ready | running | done
  return (
    <div>
      <Back onClick={back} label="Final spec" />
      <div className="jio-h1" style={{ fontSize: 22 }}>Implement this</div>
      <div className="jio-sub" style={{ marginBottom: 16 }}>Hand the spec straight to the agent</div>
      <div className="ji2-bound"><Icon name="shield" size={17} /><div className="t"><b>Honest boundary.</b> Runs <b>Opus 4.8</b> in <b>~/code/api-gateway</b>. No worktree, no commit rules — the CLI and prompt control file edits.</div></div>
      <div className="ji2-row"><span className="l">Worker</span><span className="ji2-g"><BrandIcon slug="anthropic" color="FFA630" size={16} /></span><span style={{ fontSize: 14, fontWeight: 600 }}>Opus 4.8</span><span style={{ flex: 1 }}></span><Badge tone="positive" dot>healthy</Badge></div>
      <div className="ji2-row"><span className="l">Working dir</span><span style={{ fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--text-secondary)' }}>~/code/api-gateway</span></div>
      <div className="ji2-row" style={{ borderBottom: 'none' }}><span className="l">Reveal only</span><span style={{ flex: 1, fontSize: 12, color: 'var(--text-muted)' }}>write artifacts, don’t invoke</span><Icon name="square" size={18} style={{ color: 'var(--text-faint)' }} /></div>

      {st === 'ready' && <button className="jio-cta" style={{ marginTop: 18 }} onClick={() => { setSt('running'); setTimeout(() => setSt('done'), 1800); }}><Icon name="play" size={17} /> Dispatch to Opus 4.8</button>}
      {st !== 'ready' && (
        <div className="ji2-term">
          <div className="c">$ claude-code --prompt execution_prompt_opus.md</div>
          <div><span className="a">•</span> read brief — 3 acceptance criteria</div>
          <div><span className="a">•</span> editing src/middleware/rateLimit.ts</div>
          {st === 'done' && <div><span className="ok">✓</span> swift test — 6 passed</div>}
          {st === 'done' && <div className="c">transcript → Runs/run_7f3/dispatch.log</div>}
        </div>
      )}
      {st === 'done' && <button className="jio-cta" style={{ marginTop: 14 }} onClick={onReturn}><Icon name="arrow-right" size={17} /> See return review</button>}
    </div>
  );
};

/* ===== Return review ===== */
window.JIOS_Return = function ReturnScreen({ back }) {
  return (
    <div>
      <Back onClick={back} label="Dispatch" />
      <div className="jio-h1" style={{ fontSize: 22 }}>Return review</div>
      <div className="jio-sub" style={{ marginBottom: 16 }}>Advisory — judged against the spec</div>
      <div className="ji2-score"><span className="big">0.86</span><div style={{ flex: 1 }}><div style={{ fontSize: 14, fontWeight: 600 }}>Met 3 of 3 criteria</div><div className="ji2-bar"><i style={{ width: '86%' }}></i></div><div style={{ fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--text-faint)', marginTop: 6 }}>outcome score · estimate</div></div></div>
      <div className="ji2-sec__h" style={{ marginBottom: 4 }}><Icon name="circle-check" size={13} /> Acceptance criteria</div>
      {[['pass', '101st request → 429', 'hit 429 at request 101'], ['pass', 'per-user isolation', 'two-user test independent'], ['partial', 'reset rejects unauth', 'returns 403, spec said 401']].map((c, i) => (
        <div className="ji2-crit" key={i}><Icon name={MK[c[0]][1]} size={15} style={{ color: MK[c[0]][0] }} /><div><div className="t">{c[1]}</div><div className="n">{c[2]}</div></div></div>
      ))}
      <div className="ji2-sec__h" style={{ margin: '18px 0 6px' }}><Icon name="flask" size={13} /> Proofs ran</div>
      <div className="ji2-code"><span className="ok">✓</span> swift test — 6 passed{'\n'}<span className="ok">✓</span> load-test — 429 observed</div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 16, padding: 13, background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 12 }}>
        <Icon name="circle-check" size={18} style={{ color: 'var(--accent-text)' }} />
        <div style={{ flex: 1 }}><div style={{ fontSize: 13, fontWeight: 600 }}>Recommended: Pick</div><div style={{ fontSize: 12, color: 'var(--text-muted)' }}>highest score; criteria met</div></div>
      </div>
    </div>
  );
};

/* ===== App (extended) ===== */
window.JIOSApp = function JIOSApp() {
  const { JIOS_Inbox, JIOS_Compose, JIOS_Review, JIOS_Final, JIOS_Dispatch, JIOS_Return } = window;
  const [tab, setTab] = React.useState('inbox');
  const [detail, setDetail] = React.useState(null);
  let screen, action = null;
  if (detail === 'review') { screen = <JIOS_Review back={() => setDetail(null)} />; action = { label: 'View final spec', icon: 'arrow-right', go: 'final' }; }
  else if (detail === 'final') { screen = <JIOS_Final back={() => setDetail('review')} />; action = { label: 'Implement this', icon: 'arrow-right', go: 'dispatch' }; }
  else if (detail === 'dispatch') { screen = <JIOS_Dispatch back={() => setDetail('final')} onReturn={() => setDetail('return')} />; }
  else if (detail === 'return') { screen = <JIOS_Return back={() => setDetail('dispatch')} />; }
  else screen = tab === 'inbox' ? <JIOS_Inbox open={setDetail} /> : <JIOS_Compose />;
  return (
    <div className="jio-app">
      <div className="jio-scroll">{screen}</div>
      {action && <div className="jio-actionbar"><button className="jio-cta" onClick={() => setDetail(action.go)}><Icon name={action.icon} size={18} /> {action.label}</button></div>}
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
