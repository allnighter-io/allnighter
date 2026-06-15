// @ds-adherence-ignore -- Judgment batch 3: Return review, Routing, Compare.
const { Button, IconButton, Icon, Badge, Card, StatusPill, BrandIcon, JHeader } = window;

(function () {
  if (document.getElementById('jud-screens3-css')) return;
  const s = document.createElement('style'); s.id = 'jud-screens3-css';
  s.textContent = `
  .jt-strip{display:flex;gap:10px;margin-bottom:22px}
  .jt-stat{flex:1;background:var(--bg-surface);border:1px solid var(--border-subtle);border-radius:var(--radius-md);padding:11px 13px}
  .jt-stat .v{font-family:var(--font-mono);font-size:15px;font-weight:600;color:var(--text-primary)}
  .jt-stat .l{font-size:11px;color:var(--text-muted);margin-top:3px}
  .jt-label{font-size:11px;font-weight:700;letter-spacing:.07em;text-transform:uppercase;color:var(--text-faint);margin:0 0 11px}
  .jt-crit{display:flex;align-items:flex-start;gap:11px;padding:12px 0;border-bottom:1px solid var(--border-subtle)}
  .jt-crit:last-child{border-bottom:none}
  .jt-mark{width:20px;height:20px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;margin-top:1px}
  .jt-mark svg{width:13px;height:13px}
  .jt-crit__m{flex:1;min-width:0}
  .jt-crit__t{font-size:14px;color:var(--text-primary);line-height:1.45}
  .jt-crit__n{font-size:12px;color:var(--text-muted);margin-top:3px;line-height:1.45}
  .jt-proof{font-family:var(--font-mono);font-size:12.5px;line-height:1.9;color:var(--text-secondary);background:var(--bg-void);border:1px solid var(--border-subtle);border-radius:var(--radius-md);padding:13px 15px}
  .jt-proof .ok{color:var(--green-400)}.jt-proof .c{color:var(--text-faint)}
  .jt-score{display:flex;align-items:center;gap:14px;padding:16px;background:linear-gradient(180deg,rgba(255,166,48,.07),transparent),var(--bg-raised);border:1px solid var(--accent-border);border-radius:var(--radius-lg)}
  .jt-score__big{font-family:var(--font-display);font-size:40px;font-weight:800;letter-spacing:-.02em;color:var(--accent-text)}
  .jt-bar{height:6px;border-radius:4px;background:var(--bg-active);overflow:hidden;margin-top:7px}
  .jt-bar>i{display:block;height:100%;background:var(--accent);border-radius:4px}
  /* routing */
  .jg-opt{display:flex;gap:14px;padding:17px;border-radius:var(--radius-lg);border:1px solid var(--border-subtle);background:var(--bg-raised);margin-bottom:12px;align-items:flex-start}
  .jg-opt.rec{border-color:var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.06),transparent 60%),var(--bg-raised)}
  .jg-opt__ic{width:40px;height:40px;border-radius:11px;flex:none;display:flex;align-items:center;justify-content:center;background:var(--bg-active);color:var(--text-secondary)}
  .jg-opt.rec .jg-opt__ic{background:var(--accent-surface);color:var(--accent-text)}
  .jg-opt__ic svg{width:20px;height:20px}
  .jg-opt__m{flex:1;min-width:0}
  .jg-opt__h{display:flex;align-items:center;gap:9px}
  .jg-opt__t{font-size:16px;font-weight:700;letter-spacing:-.01em}
  .jg-opt__d{font-size:13px;color:var(--text-secondary);margin-top:5px;line-height:1.5}
  .jg-opt__r{font-size:12px;color:var(--text-muted);margin-top:8px;line-height:1.5;display:flex;gap:7px}
  .jg-opt__r svg{flex:none;margin-top:2px;color:var(--accent-text)}
  /* compare */
  .jp-grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px}
  .jp-col{display:flex;flex-direction:column;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-lg);overflow:hidden}
  .jp-col.win{border-color:var(--accent-border)}
  .jp-col__hd{padding:13px;border-bottom:1px solid var(--border-subtle)}
  .jp-col__wk{display:flex;align-items:center;gap:9px}
  .jp-col__g{width:26px;height:26px;border-radius:7px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;overflow:hidden;flex:none}
  .jp-col__g img{width:16px;height:16px}
  .jp-col__n{font-size:13px;font-weight:600;flex:1}
  .jp-col__sc{font-family:var(--font-display);font-size:24px;font-weight:800;letter-spacing:-.02em;margin-top:9px}
  .jp-col__meta{font-family:var(--font-mono);font-size:11px;color:var(--text-faint);margin-top:2px}
  .jp-col__body{padding:12px 13px;flex:1;display:flex;flex-direction:column;gap:9px}
  .jp-crit{display:flex;align-items:center;gap:8px;font-size:12px;color:var(--text-secondary)}
  .jp-crit svg{flex:none;width:14px;height:14px}
  .jp-col__ft{padding:11px 13px;border-top:1px solid var(--border-subtle)}`;
  document.head.appendChild(s);
})();

const MARK = {
  pass: ['var(--success-surface)', 'var(--green-400)', 'circle-check'],
  partial: ['var(--warning-surface)', 'var(--yellow-400)', 'gauge'],
  fail: ['var(--danger-surface)', 'var(--red-400)', 'x'],
};
function Mark({ k }) { const m = MARK[k]; return <span className="jt-mark" style={{ background: m[0], color: m[1] }}><Icon name={m[2]} size={13} /></span>; }
function MiniMark({ k }) { const m = MARK[k]; return <Icon name={m[2]} size={14} style={{ color: m[1] }} />; }

/* ============ Return review + outcome score ============ */
window.ReturnReviewView = function ReturnReviewView({ onNav }) {
  return (
    <div>
      <JHeader eyebrow="Return review · RB5 · advisory" title="return_review.md"
        sub="The council that judged the plan now judges the result. Advisory — it never edits the agent’s output."
        actions={<><Badge tone="positive" dot>exit 0</Badge><Button variant="ghost" size="sm" iconLeft={<Icon name="copy" size={14} />}>Copy</Button></>} />
      <div className="jud-content" style={{ maxWidth: 780 }}>
        <div className="jt-strip">
          {[['Opus 4.8', 'worker'], ['exit 0', 'status'], ['3 files · +148 −12', 'diff (observed)'], ['2m 41s', 'duration']].map((x, i) => (
            <div className="jt-stat" key={i}><div className="v">{x[0]}</div><div className="l">{x[1]}</div></div>
          ))}
        </div>

        <div className="jt-score" style={{ marginBottom: 22 }}>
          <div className="jt-score__big">0.86</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 14, fontWeight: 600 }}>Outcome score · met 3 of 3 criteria</div>
            <div className="jt-bar"><i style={{ width: '86%' }}></i></div>
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-faint)', marginTop: 6 }}>scored against final_spec.md acceptance criteria · estimate</div>
          </div>
        </div>

        <div className="jt-label">Acceptance criteria</div>
        <Card variant="flush" style={{ marginBottom: 18 }}>
          <div className="jt-crit"><Mark k="pass" /><div className="jt-crit__m"><div className="jt-crit__t">101st request within 60s returns 429 + Retry-After</div><div className="jt-crit__n">load-test hit 429 at request 101; header present.</div></div></div>
          <div className="jt-crit"><Mark k="pass" /><div className="jt-crit__m"><div className="jt-crit__t">Limits isolated per user</div><div className="jt-crit__n">two-user concurrent test stayed independent.</div></div></div>
          <div className="jt-crit"><Mark k="partial" /><div className="jt-crit__m"><div className="jt-crit__t">Reset endpoint rejects unauthenticated callers</div><div className="jt-crit__n">returns 403, spec said 401 — behavior correct, status code differs.</div></div></div>
        </Card>

        <div className="jt-label">Proof commands <span style={{ textTransform: 'none', letterSpacing: 0, fontWeight: 500, color: 'var(--text-muted)' }}>· ran with your consent</span></div>
        <div className="jt-proof" style={{ marginBottom: 18 }}>
          <div><span className="ok">✓</span> swift test --filter RateLimitTests <span className="c">— 6 passed</span></div>
          <div><span className="ok">✓</span> ./scripts/load-test.sh --user u1 --rps 5 <span className="c">— 429 observed</span></div>
          <div><span className="ok">✓</span> curl …/api/ping <span className="c">— 200 then 429</span></div>
        </div>

        <div className="jt-label">Missing / risky</div>
        <Card variant="flush" style={{ marginBottom: 20 }}>
          <div className="jt-crit" style={{ borderBottom: 'none' }}><span className="jt-mark" style={{ background: 'var(--bg-active)', color: 'var(--text-muted)' }}><Icon name="zap" size={13} /></span><div className="jt-crit__m"><div className="jt-crit__t">Fail-open implemented but undocumented</div><div className="jt-crit__n">the blind spot the panel flagged is now code — add it to the spec.</div></div></div>
        </Card>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: 14, background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-md)' }}>
          <div style={{ flex: 1 }}><div style={{ fontSize: 13, fontWeight: 600 }}>Recommended next action: Pick</div><div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 2 }}>highest score on this task; criteria met.</div></div>
          <Button variant="primary" size="sm" iconLeft={<Icon name="compare" size={14} />} onClick={() => onNav('routing')}>See routing</Button>
        </div>
      </div>
    </div>
  );
};

/* ============ Routing ============ */
window.RoutingView = function RoutingView({ onNav }) {
  return (
    <div>
      <JHeader eyebrow="Routing · next action" title="What to do next"
        sub="From the return review, outcome score, and worker scorecards. A recommendation — you decide and act."
        actions={<Badge tone="neutral" mono>estimate</Badge>} />
      <div className="jud-content" style={{ maxWidth: 760 }}>
        <div className="jg-opt rec">
          <span className="jg-opt__ic"><Icon name="circle-check" size={20} /></span>
          <div className="jg-opt__m">
            <div className="jg-opt__h"><span className="jg-opt__t">Pick</span><Badge tone="accent">recommended</Badge></div>
            <div className="jg-opt__d">Accept Opus 4.8’s return and stop here.</div>
            <div className="jg-opt__r"><Icon name="zap" size={13} />Met 3/3 criteria at score 0.86 — the highest of any worker on this task, and the proof wall is green.</div>
          </div>
          <Button variant="primary" size="sm">Pick this return</Button>
        </div>

        <div className="jg-opt">
          <span className="jg-opt__ic"><Icon name="rotate-cw" size={20} /></span>
          <div className="jg-opt__m">
            <div className="jg-opt__h"><span className="jg-opt__t">Rerun</span></div>
            <div className="jg-opt__d">Re-dispatch the same brief to a different worker, or re-run the council at higher depth if the spec itself was weak.</div>
            <div className="jg-opt__r"><Icon name="zap" size={13} />Composer 2.5 scores +0.07 on refactor-style tasks historically; reuse keeps the panel + spec free.</div>
          </div>
          <Button variant="secondary" size="sm">Set up rerun</Button>
        </div>

        <div className="jg-opt">
          <span className="jg-opt__ic"><Icon name="compare" size={20} /></span>
          <div className="jg-opt__m">
            <div className="jg-opt__h"><span className="jg-opt__t">Remix</span></div>
            <div className="jg-opt__d">Combine the best parts of several returns into one final pass.</div>
            <div className="jg-opt__r"><Icon name="zap" size={13} />Needs ≥2 returns — dispatch the brief to multiple workers and compare first.</div>
          </div>
          <Button variant="secondary" size="sm" iconLeft={<Icon name="compare" size={14} />} onClick={() => onNav('compare')}>Compare workers</Button>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginTop: 16, padding: '11px 13px', background: 'var(--bg-surface)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-md)', fontSize: 12, color: 'var(--text-muted)' }}>
          <Icon name="gauge" size={15} style={{ color: 'var(--accent-text)' }} />
          Reasoning uses the Opus 4.8 scorecard — 92% panel answer · 88% exec success · 1.9s median latency.
          <span style={{ flex: 1 }}></span>
          <Button variant="ghost" size="sm">View scorecards</Button>
        </div>
      </div>
    </div>
  );
};

/* ============ Multi-executor compare ============ */
const CMP = [
  { w: { brand: 'anthropic', color: 'FFA630' }, n: 'Opus 4.8', score: '0.86', diff: '3 files · +148 −12', crit: ['pass', 'pass', 'partial'], win: true },
  { w: { brand: 'anthropic', color: 'AEB5C9' }, n: 'Sonnet 4.6', score: '0.81', diff: '3 files · +132 −9', crit: ['pass', 'pass', 'fail'] },
  { w: { icon: 'square' }, n: 'Composer 2.5', score: '0.79', diff: '5 files · +201 −30', crit: ['pass', 'partial', 'pass'] },
];
window.CompareView = function CompareView() {
  return (
    <div>
      <JHeader eyebrow="Multi-executor compare · RB5" title="Compare returns"
        sub="The same brief dispatched to 3 workers in parallel — text returns, no worktrees. Scored side by side."
        actions={<><Button variant="secondary" size="sm" iconLeft={<Icon name="compare" size={14} />}>Remix top 2</Button><Button variant="primary" size="sm">Pick winner</Button></>} />
      <div className="jud-content">
        <div className="jp-grid">
          {CMP.map((c, i) => (
            <div className={'jp-col' + (c.win ? ' win' : '')} key={i}>
              <div className="jp-col__hd">
                <div className="jp-col__wk">
                  <span className="jp-col__g">{c.w.brand ? <BrandIcon slug={c.w.brand} color={c.w.color} size={16} /> : <Icon name={c.w.icon} size={14} style={{ color: 'var(--text-secondary)' }} />}</span>
                  <span className="jp-col__n">{c.n}</span>
                  {c.win && <Badge tone="accent">winner</Badge>}
                </div>
                <div className="jp-col__sc" style={{ color: c.win ? 'var(--accent-text)' : 'var(--text-primary)' }}>{c.score}</div>
                <div className="jp-col__meta">exit 0 · {c.diff}</div>
              </div>
              <div className="jp-col__body">
                {['101st req → 429', 'per-user isolation', 'reset auth'].map((t, j) => (
                  <div className="jp-crit" key={j}><MiniMark k={c.crit[j]} />{t}</div>
                ))}
              </div>
              <div className="jp-col__ft">
                <Button variant={c.win ? 'primary' : 'secondary'} size="sm" block>Pick this</Button>
              </div>
            </div>
          ))}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 9, color: 'var(--text-muted)', fontSize: 12, marginTop: 14 }}>
          <Icon name="shield" size={15} /> Still no worktrees, branches, or commits — this is a text-level compare. Managed races are deferred roadmap.
        </div>
      </div>
    </div>
  );
};
