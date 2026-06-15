// @ds-adherence-ignore -- iOS judgment batch 3+4: Routing, Live run, Judge analysis, Scorecards.
const { Button, Icon, Badge, StatusPill, BrandIcon } = window;

(function () {
  if (document.getElementById('jio3-css')) return;
  const s = document.createElement('style'); s.id = 'jio3-css';
  s.textContent = `
  .ji3-opt{display:flex;gap:12px;padding:15px;border-radius:15px;border:1px solid var(--border-subtle);background:var(--bg-raised);margin-bottom:11px;align-items:flex-start}
  .ji3-opt.rec{border-color:var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.06),transparent 60%),var(--bg-raised)}
  .ji3-opt__ic{width:38px;height:38px;border-radius:11px;flex:none;display:flex;align-items:center;justify-content:center;background:var(--bg-active);color:var(--text-secondary)}
  .ji3-opt.rec .ji3-opt__ic{background:var(--accent-surface);color:var(--accent-text)}
  .ji3-opt__ic svg{width:19px;height:19px}
  .ji3-opt__m{flex:1;min-width:0}
  .ji3-opt__h{display:flex;align-items:center;gap:8px}
  .ji3-opt__t{font-size:15px;font-weight:700}
  .ji3-opt__d{font-size:13px;color:var(--text-secondary);margin-top:4px;line-height:1.45}
  .ji3-opt__r{font-size:12px;color:var(--text-muted);margin-top:7px;line-height:1.45;display:flex;gap:6px}
  .ji3-opt__r svg{flex:none;margin-top:2px;color:var(--accent-text)}
  /* live run */
  .ji3-lr{display:flex;align-items:center;gap:12px;padding:13px;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:13px;margin-bottom:8px}
  .ji3-lr__n{width:30px;height:30px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;border:2px solid var(--bg-base)}
  .ji3-lr__n svg{width:15px;height:15px}
  .ji3-lr__m{flex:1;min-width:0}
  .ji3-lr__t{font-size:14px;font-weight:600}
  .ji3-lr__s{font-family:var(--font-mono);font-size:11px;color:var(--text-faint);margin-top:2px}
  /* analysis */
  .ji3-seats{display:flex;gap:6px;flex-wrap:wrap;margin-bottom:18px}
  .ji3-seat{display:flex;align-items:center;gap:6px;padding:5px 9px 5px 6px;background:var(--bg-surface);border:1px solid var(--border-subtle);border-radius:999px}
  .ji3-seat__g{width:18px;height:18px;border-radius:5px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;overflow:hidden}
  .ji3-seat__g img{width:12px;height:12px}
  .ji3-seat__n{font-size:11px;font-weight:600}
  .ji3-asec{margin-bottom:13px}
  .ji3-asec__h{display:flex;align-items:center;gap:8px;margin-bottom:9px}
  .ji3-aic{width:24px;height:24px;border-radius:7px;display:flex;align-items:center;justify-content:center;flex:none}
  .ji3-aic svg{width:14px;height:14px}
  .ji3-asec__t{font-size:14px;font-weight:600}
  .ji3-ali{display:flex;gap:9px;font-size:13px;color:var(--text-secondary);line-height:1.45;padding:5px 0}
  .ji3-ali .dot{flex:none;width:6px;height:6px;border-radius:50%;margin-top:6px}
  .ji3-ali .attr{margin-left:auto;font-family:var(--font-mono);font-size:10px;color:var(--accent-text);flex:none;padding-left:8px}
  .ji3-con{display:flex;border:1px solid var(--border-subtle);border-radius:11px;overflow:hidden;margin-bottom:8px}
  .ji3-con__s{flex:1;padding:10px 11px}
  .ji3-con__s+.ji3-con__s{border-left:1px solid var(--border-subtle)}
  .ji3-con__w{font-family:var(--font-mono);font-size:9px;color:var(--text-faint);margin-bottom:3px}
  .ji3-con__t{font-size:12px;color:var(--text-secondary);line-height:1.35}
  /* scorecards */
  .ji3-sc{display:flex;align-items:center;gap:11px;padding:12px 0;border-bottom:1px solid var(--border-subtle)}
  .ji3-sc:last-child{border-bottom:none}
  .ji3-sc__g{width:30px;height:30px;border-radius:8px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none;overflow:hidden}
  .ji3-sc__g img{width:18px;height:18px}
  .ji3-sc__m{flex:1;min-width:0}
  .ji3-sc__n{font-size:13px;font-weight:600;display:flex;justify-content:space-between}
  .ji3-sc__n .lat{font-family:var(--font-mono);font-size:11px;color:var(--text-muted);font-weight:400}
  .ji3-sc__bars{display:flex;gap:5px;margin-top:7px}
  .ji3-sc__bar{flex:1;height:5px;border-radius:3px;background:var(--bg-active);overflow:hidden}
  .ji3-sc__bar>i{display:block;height:100%;border-radius:3px}
  .ji3-sclegend{display:flex;gap:14px;font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-bottom:8px}
  .ji3-link{display:flex;align-items:center;justify-content:center;gap:7px;width:100%;height:44px;border:1px solid var(--border-default);border-radius:12px;background:var(--bg-surface);color:var(--text-secondary);font-family:inherit;font-size:14px;font-weight:600;cursor:pointer;margin-top:6px}`;
  document.head.appendChild(s);
})();

const Back3 = ({ onClick, label }) => <button className="jio-back" onClick={onClick}><Icon name="chevron-right" size={16} style={{ transform: 'rotate(180deg)' }} /> {label}</button>;

/* ===== Routing ===== */
window.JIOS_Routing = function RoutingScreen({ back, onCompare, onScores }) {
  return (
    <div>
      <Back3 onClick={back} label="Return review" />
      <div className="jio-h1" style={{ fontSize: 22 }}>What to do next</div>
      <div className="jio-sub" style={{ marginBottom: 18 }}>From the outcome score &amp; scorecards · estimate</div>
      <div className="ji3-opt rec">
        <span className="ji3-opt__ic"><Icon name="circle-check" size={19} /></span>
        <div className="ji3-opt__m">
          <div className="ji3-opt__h"><span className="ji3-opt__t">Pick</span><Badge tone="accent">recommended</Badge></div>
          <div className="ji3-opt__d">Accept Opus 4.8’s return and stop here.</div>
          <div className="ji3-opt__r"><Icon name="zap" size={13} />Met 3/3 at 0.86 — highest on this task; proof wall green.</div>
          <div style={{ marginTop: 11 }}><button className="jio-cta" style={{ height: 44, fontSize: 15 }}>Pick this return</button></div>
        </div>
      </div>
      <div className="ji3-opt">
        <span className="ji3-opt__ic"><Icon name="rotate-cw" size={19} /></span>
        <div className="ji3-opt__m">
          <div className="ji3-opt__h"><span className="ji3-opt__t">Rerun</span></div>
          <div className="ji3-opt__d">Re-dispatch the brief to a different worker.</div>
          <div className="ji3-opt__r"><Icon name="zap" size={13} />Composer 2.5 is +0.07 on refactors; reuse keeps panel + spec free.</div>
        </div>
      </div>
      <div className="ji3-opt">
        <span className="ji3-opt__ic"><Icon name="compare" size={19} /></span>
        <div className="ji3-opt__m">
          <div className="ji3-opt__h"><span className="ji3-opt__t">Remix</span></div>
          <div className="ji3-opt__d">Combine the best parts of several returns.</div>
          <div className="ji3-opt__r"><Icon name="zap" size={13} />Needs ≥2 returns — compare workers first.</div>
        </div>
      </div>
      <button className="ji3-link" onClick={onScores}><Icon name="gauge" size={15} /> View worker scorecards</button>
    </div>
  );
};

/* ===== Live run ===== */
const LR_STAGES = [
  { t: 'Panel · 5 seats', s: 'reused · 0 fresh', st: 'done' },
  { t: 'Judge analysis', s: 'analysis.md · 2 contradictions', st: 'done' },
  { t: 'Draft plan', s: 'master_plan.md', st: 'done' },
  { t: 'Review board · 9 lenses', s: '6 of 9 returned', st: 'run' },
  { t: 'Final spec', s: 'waiting', st: 'idle' },
];
const LRC = { done: ['var(--success-surface)', 'var(--green-400)', 'check'], run: ['var(--info-surface)', 'var(--blue-400)', 'users'], idle: ['var(--bg-active)', 'var(--text-faint)', 'clock'] };
window.JIOS_LiveRun = function LiveRunScreen({ back }) {
  return (
    <div>
      <Back3 onClick={back} label="Inbox" />
      <div className="jio-row" style={{ marginBottom: 4 }}>
        <span className="jio-h1" style={{ fontSize: 22, flex: 1 }}>Cache invalidation</span>
        <StatusPill status="running" />
      </div>
      <div className="jio-sub" style={{ marginBottom: 18 }}>full_review · running · 1m 48s elapsed</div>
      {LR_STAGES.map((st, i) => {
        const c = LRC[st.st];
        return (
          <div className="ji3-lr" key={i}>
            <span className="ji3-lr__n" style={{ background: c[0], color: c[1] }}><Icon name={c[2]} size={15} /></span>
            <span className="ji3-lr__m"><span className="ji3-lr__t" style={st.st === 'idle' ? { color: 'var(--text-faint)' } : null}>{st.t}</span><span className="ji3-lr__s">{st.s}</span></span>
            {st.st === 'run' && <span style={{ width: 8, height: 8, borderRadius: '50%', background: 'var(--blue-500)', animation: 'allnighter-pulse 1.4s var(--ease-in-out) infinite' }}></span>}
          </div>
        );
      })}
      <div style={{ marginTop: 14 }}><button className="ji3-link" style={{ color: 'var(--red-400)', borderColor: 'rgba(247,107,107,.3)' }}><Icon name="square" size={15} /> Stop run</button></div>
    </div>
  );
};

/* ===== Judge analysis ===== */
const A_SEATS = [
  { b: 'anthropic', col: 'FFA630', n: 'Opus', st: 'first principles' },
  { ic: 'terminal', n: 'ChatGPT', st: 'skeptic' },
  { b: 'anthropic', col: 'AEB5C9', n: 'Sonnet', st: 'neutral' },
  { ic: 'square', n: 'Composer', st: 'neutral' },
];
function ASeatG({ s }) { return s.b ? <BrandIcon slug={s.b} color={s.col} size={12} /> : <Icon name={s.ic} size={11} style={{ color: 'var(--text-secondary)' }} />; }
window.JIOS_Analysis = function AnalysisScreen({ back }) {
  return (
    <div>
      <Back3 onClick={back} label="Review board" />
      <div className="jio-h1" style={{ fontSize: 22 }}>analysis.md</div>
      <div className="jio-sub" style={{ marginBottom: 16 }}>Structured panel truth · 4 of 5 answered</div>
      <div className="ji3-seats">
        {A_SEATS.map((s, i) => (<span className="ji3-seat" key={i}><span className="ji3-seat__g"><ASeatG s={s} /></span><span className="ji3-seat__n">{s.n}</span><Badge tone="accent" mono>{s.st}</Badge></span>))}
        <span className="ji3-seat" style={{ opacity: .6 }}><span className="ji3-seat__g"><BrandIcon slug="googlegemini" color="E1E5F0" size={12} /></span><span className="ji3-seat__n">Gemini</span><Badge tone="danger" dot>failed</Badge></span>
      </div>

      <div className="ji3-asec">
        <div className="ji3-asec__h"><span className="ji3-aic" style={{ background: 'var(--success-surface)', color: 'var(--green-400)' }}><Icon name="check-check" size={14} /></span><span className="ji3-asec__t">Consensus</span></div>
        {['Key on user ID, never IP.', 'Return 429 + Retry-After.', 'Keep counters off the disk path.'].map((t, i) => (<div className="ji3-ali" key={i}><span className="dot" style={{ background: 'var(--green-500)' }}></span>{t}</div>))}
      </div>
      <div className="ji3-asec">
        <div className="ji3-asec__h"><span className="ji3-aic" style={{ background: 'var(--warning-surface)', color: 'var(--yellow-400)' }}><Icon name="scale" size={14} /></span><span className="ji3-asec__t">Contradictions · 2</span></div>
        <div className="ji3-con"><div className="ji3-con__s"><div className="ji3-con__w">Opus · first principles</div><div className="ji3-con__t">Redis token bucket — survives restart.</div></div><div className="ji3-con__s"><div className="ji3-con__w">Composer · neutral</div><div className="ji3-con__t">In-memory map — simplest.</div></div></div>
        <div className="ji3-con"><div className="ji3-con__s"><div className="ji3-con__w">Opus</div><div className="ji3-con__t">Sliding window.</div></div><div className="ji3-con__s"><div className="ji3-con__w">ChatGPT · skeptic</div><div className="ji3-con__t">Fixed window — cheaper.</div></div></div>
      </div>
      <div className="ji3-asec">
        <div className="ji3-asec__h"><span className="ji3-aic" style={{ background: 'var(--accent-surface)', color: 'var(--accent-text)' }}><Icon name="zap" size={14} /></span><span className="ji3-asec__t">Unique insights · 3</span></div>
        <div className="ji3-ali"><span className="dot" style={{ background: 'var(--accent)' }}></span>Per-tier limits belong in config.<span className="attr">Sonnet</span></div>
        <div className="ji3-ali"><span className="dot" style={{ background: 'var(--accent)' }}></span>Expose remaining-quota headers.<span className="attr">Opus</span></div>
      </div>
      <div className="ji3-asec">
        <div className="ji3-asec__h"><span className="ji3-aic" style={{ background: 'var(--info-surface)', color: 'var(--blue-400)' }}><Icon name="search" size={14} /></span><span className="ji3-asec__t">Blind spots</span></div>
        <div className="ji3-ali"><span className="dot" style={{ background: 'var(--blue-500)' }}></span>Fail-open vs fail-closed when the backend is down.</div>
      </div>
    </div>
  );
};

/* ===== Scorecards ===== */
const SC = [
  { b: 'anthropic', col: 'FFA630', n: 'Opus 4.8', p: 92, s: 88, e: 88, lat: '1.9s' },
  { b: 'anthropic', col: 'AEB5C9', n: 'Sonnet 4.6', p: 95, s: 71, e: 81, lat: '1.4s' },
  { ic: 'terminal', n: 'ChatGPT 5.5', p: 90, s: 64, e: 79, lat: '2.2s' },
  { ic: 'square', n: 'Composer 2.5', p: 72, s: 0, e: 83, lat: 'manual' },
  { b: 'googlegemini', col: 'E1E5F0', n: 'Gemini Flash', p: 78, s: 55, e: 62, lat: '0.9s' },
];
const scColor = (v) => v >= 85 ? 'var(--green-500)' : v >= 70 ? 'var(--accent)' : 'var(--yellow-500)';
window.JIOS_Scorecards = function ScorecardsScreen({ back }) {
  return (
    <div>
      <Back3 onClick={back} label="Next action" />
      <div className="jio-h1" style={{ fontSize: 22 }}>Worker scorecards</div>
      <div className="jio-sub" style={{ marginBottom: 18 }}>From local history · estimate · nothing uploaded</div>
      <div className="ji3-sclegend"><span style={{ color: 'var(--green-400)' }}>● panel</span><span style={{ color: 'var(--accent-text)' }}>● synthesis</span><span style={{ color: 'var(--blue-400)' }}>● exec</span></div>
      {SC.map((w, i) => (
        <div className="ji3-sc" key={i}>
          <span className="ji3-sc__g">{w.b ? <BrandIcon slug={w.b} color={w.col} size={18} /> : <Icon name={w.ic} size={16} style={{ color: 'var(--text-secondary)' }} />}</span>
          <span className="ji3-sc__m">
            <span className="ji3-sc__n">{w.n}<span className="lat">{w.lat}</span></span>
            <span className="ji3-sc__bars">
              {[w.p, w.s, w.e].map((v, j) => (<span className="ji3-sc__bar" key={j}><i style={{ width: v + '%', background: v === 0 ? 'transparent' : scColor(v) }}></i></span>))}
            </span>
          </span>
        </div>
      ))}
    </div>
  );
};

/* ===== App (final) ===== */
window.JIOSApp = function JIOSApp() {
  const W = window;
  const [tab, setTab] = React.useState('inbox');
  const [detail, setDetail] = React.useState(null);
  let screen, action = null;
  if (detail === 'review') { screen = <W.JIOS_Review back={() => setDetail(null)} onAnalysis={() => setDetail('analysis')} />; action = { label: 'View final spec', go: 'final' }; }
  else if (detail === 'analysis') { screen = <W.JIOS_Analysis back={() => setDetail('review')} />; }
  else if (detail === 'final') { screen = <W.JIOS_Final back={() => setDetail('review')} />; action = { label: 'Implement this', go: 'dispatch' }; }
  else if (detail === 'dispatch') { screen = <W.JIOS_Dispatch back={() => setDetail('final')} onReturn={() => setDetail('return')} />; }
  else if (detail === 'return') { screen = <W.JIOS_Return back={() => setDetail('dispatch')} />; action = { label: 'See routing', go: 'routing' }; }
  else if (detail === 'routing') { screen = <W.JIOS_Routing back={() => setDetail('return')} onScores={() => setDetail('scorecards')} />; }
  else if (detail === 'scorecards') { screen = <W.JIOS_Scorecards back={() => setDetail('routing')} />; }
  else if (detail === 'liverun') { screen = <W.JIOS_LiveRun back={() => setDetail(null)} />; }
  else screen = tab === 'inbox' ? <W.JIOS_Inbox open={setDetail} /> : <W.JIOS_Compose />;
  return (
    <div className="jio-app">
      <div className="jio-scroll">{screen}</div>
      {action && <div className="jio-actionbar"><button className="jio-cta" onClick={() => setDetail(action.go)}><Icon name="arrow-right" size={18} /> {action.label}</button></div>}
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
