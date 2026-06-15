// @ds-adherence-ignore -- Judgment batch 2: Run overview, Judge analysis, Dispatch.
const { Button, IconButton, Icon, Badge, Card, Select, Switch, StatusPill, BrandIcon, JHeader, JLive } = window;

(function () {
  if (document.getElementById('jud-screens2-css')) return;
  const s = document.createElement('style'); s.id = 'jud-screens2-css';
  s.textContent = `
  .jo-strip{display:flex;gap:10px;margin-bottom:20px}
  .jo-stat{flex:1;background:var(--bg-surface);border:1px solid var(--border-subtle);border-radius:var(--radius-md);padding:12px 13px}
  .jo-stat .v{font-family:var(--font-display);font-size:20px;font-weight:800;letter-spacing:-.02em}
  .jo-stat .l{font-size:11px;color:var(--text-muted);margin-top:3px}
  .jo-tl{position:relative;padding-left:6px}
  .jo-tl::before{content:"";position:absolute;left:20px;top:18px;bottom:18px;width:1.5px;background:var(--border-subtle)}
  .jo-step{display:flex;align-items:center;gap:13px;padding:11px 12px;background:var(--bg-raised);border:1px solid var(--border-subtle);
    border-radius:var(--radius-md);margin-bottom:8px;position:relative}
  .jo-node{width:30px;height:30px;border-radius:50%;flex:none;display:flex;align-items:center;justify-content:center;z-index:1;border:3px solid var(--bg-base)}
  .jo-node svg{width:15px;height:15px}
  .jo-step__m{flex:1;min-width:0}
  .jo-step__t{font-size:14px;font-weight:600}
  .jo-step__s{font-family:var(--font-mono);font-size:11px;color:var(--text-faint);margin-top:2px}
  .jo-step__r{display:flex;align-items:center;gap:10px;flex:none}
  .jo-dur{font-family:var(--font-mono);font-size:11px;color:var(--text-muted)}
  /* analysis */
  .ja-seats{display:flex;gap:7px;flex-wrap:wrap;margin-bottom:20px}
  .ja-seat{display:flex;align-items:center;gap:7px;padding:6px 10px 6px 7px;background:var(--bg-surface);border:1px solid var(--border-subtle);border-radius:var(--radius-pill)}
  .ja-seat__g{width:20px;height:20px;border-radius:5px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;overflow:hidden}
  .ja-seat__g img{width:13px;height:13px}
  .ja-seat__n{font-size:12px;font-weight:600}
  .ja-sec{margin-bottom:14px}
  .ja-sec__h{display:flex;align-items:center;gap:8px;margin-bottom:11px}
  .ja-ic{width:26px;height:26px;border-radius:7px;display:flex;align-items:center;justify-content:center;flex:none}
  .ja-ic svg{width:15px;height:15px}
  .ja-sec__t{font-size:15px;font-weight:600}
  .ja-li{display:flex;gap:10px;font-size:13px;color:var(--text-secondary);line-height:1.5;padding:6px 0;border-bottom:1px solid var(--border-subtle)}
  .ja-li:last-child{border-bottom:none}
  .ja-li .dot{flex:none;width:6px;height:6px;border-radius:50%;margin-top:6px}
  .ja-attr{font-family:var(--font-mono);font-size:10px;color:var(--accent-text);flex:none}
  .ja-con{display:flex;align-items:stretch;gap:0;border:1px solid var(--border-subtle);border-radius:var(--radius-md);overflow:hidden;margin-bottom:9px}
  .ja-con__side{flex:1;padding:11px 13px}
  .ja-con__side+.ja-con__side{border-left:1px solid var(--border-subtle)}
  .ja-con__who{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-bottom:4px}
  .ja-con__txt{font-size:13px;color:var(--text-secondary);line-height:1.4}
  /* dispatch */
  .jd-boundary{display:flex;gap:11px;padding:14px 16px;background:var(--warning-surface);border:1px solid rgba(245,200,75,.3);border-radius:var(--radius-md);margin-bottom:20px}
  .jd-boundary svg{color:var(--yellow-400);flex:none;margin-top:1px}
  .jd-boundary .t{font-size:13px;color:var(--text-secondary);line-height:1.55}
  .jd-boundary .t b{color:var(--text-primary);font-weight:600}
  .jd-row{display:flex;align-items:center;gap:12px;padding:13px 0;border-bottom:1px solid var(--border-subtle)}
  .jd-row__l{width:150px;flex:none;font-size:13px;font-weight:500;color:var(--text-secondary)}
  .jd-file{display:flex;align-items:center;gap:9px;padding:10px 12px;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-md);margin-bottom:8px}
  .jd-file__n{flex:1;font-family:var(--font-mono);font-size:12px;color:var(--text-secondary)}
  .jd-term{font-family:var(--font-mono);font-size:12px;line-height:1.8;color:var(--text-secondary);background:var(--bg-void);border:1px solid var(--border-subtle);border-radius:var(--radius-md);padding:13px 15px;margin-top:8px}
  .jd-term .c{color:var(--text-faint)}.jd-term .ok{color:var(--green-400)}.jd-term .a{color:var(--accent-text)}`;
  document.head.appendChild(s);
})();

const J2STATUS = { done: ['var(--success-surface)', 'var(--green-400)'], running: ['var(--info-surface)', 'var(--blue-400)'], idle: ['var(--bg-active)', 'var(--text-faint)'], failed: ['var(--danger-surface)', 'var(--red-400)'] };

/* ============ Run pipeline overview ============ */
const OV_STAGES = [
  { icon: 'users', t: 'Panel · 5 seats', s: 'member_<seat>.md · reused from run 7f2', dur: '0s', status: 'done', reuse: true },
  { icon: 'scale', t: 'Judge analysis', s: 'analysis.md · 2 contradictions, 3 insights', dur: '11s', status: 'done', nav: 'analysis' },
  { icon: 'file-text', t: 'Draft plan', s: 'master_plan.md', dur: '14s', status: 'done' },
  { icon: 'shield', t: 'Review board · 3 lenses', s: 'review_*.md · 1 blocker · 2 concerns', dur: '9s', status: 'done', nav: 'review' },
  { icon: 'circle-check', t: 'Final spec', s: 'final_spec.md · executable ✓', dur: '18s', status: 'done', nav: 'final' },
  { icon: 'arrow-right', t: 'Direct dispatch', s: 'Opus 4.8 · exit 0 · transcript captured', dur: '2m41s', status: 'done', nav: 'dispatch' },
  { icon: 'rotate-cw', t: 'Return review', s: 'return_review.md · met 3/3 · score 0.86', dur: '12s', status: 'done', nav: 'return' },
  { icon: 'compare', t: 'Next action', s: 'recommend: pick', dur: '—', status: 'done', nav: 'routing' },
];
window.RunPipelineView = function RunPipelineView({ onNav }) {
  return (
    <div>
      <JHeader eyebrow="Run 7f3 · light_review" title="Run overview"
        sub="The whole chain at a glance. Stages are content-addressed — unchanged inputs reuse, never re-run."
        actions={<>
          <Button variant="ghost" size="sm" iconLeft={<Icon name="file-text" size={14} />}>bundle.md</Button>
          <Button variant="secondary" size="sm" iconLeft={<Icon name="rotate-cw" size={14} />}>Re-run</Button>
        </>} />
      <div className="jud-content">
        <div className="jo-strip">
          {[['complete', 'status'], ['6', 'fresh calls'], ['5', 'reused'], ['52s', 'wall time'], ['$0.00', 'marginal']].map((x, i) => (
            <div className="jo-stat" key={i}><div className="v">{x[0]}</div><div className="l">{x[1]}</div></div>
          ))}
        </div>
        <div className="jo-tl">
          {OV_STAGES.map((st, i) => {
            const c = J2STATUS[st.status];
            return (
              <div className="jo-step" key={i}>
                <span className="jo-node" style={{ background: c[0], color: c[1] }}><Icon name={st.icon} size={15} /></span>
                <span className="jo-step__m">
                  <span className="jo-step__t">{st.t}</span>
                  <span className="jo-step__s">{st.s}</span>
                </span>
                <span className="jo-step__r">
                  {st.reuse && <Badge tone="positive" mono>reused</Badge>}
                  <span className="jo-dur">{st.dur}</span>
                  {st.nav ? <Button variant="ghost" size="sm" onClick={() => onNav(st.nav)}>View</Button>
                    : <span style={{ width: 52 }}></span>}
                </span>
              </div>
            );
          })}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 9, color: 'var(--text-muted)', fontSize: 12, marginTop: 6 }}>
          <Icon name="circle-check" size={15} style={{ color: 'var(--green-400)' }} /> Resumable: a stopped run keeps completed stage outputs and continues from the first incomplete stage.
        </div>
      </div>
    </div>
  );
};

/* ============ Judge analysis ============ */
const JA_SEATS = [
  { w: { brand: 'anthropic', color: 'FFA630' }, n: 'Opus 4.8', stance: 'first principles', status: 'done' },
  { w: { icon: 'terminal' }, n: 'ChatGPT 5.5', stance: 'skeptic', status: 'done' },
  { w: { brand: 'anthropic', color: 'AEB5C9' }, n: 'Sonnet 4.6', stance: 'neutral', status: 'done' },
  { w: { icon: 'square' }, n: 'Composer 2.5', stance: 'neutral', status: 'done' },
  { w: { brand: 'googlegemini', color: 'E1E5F0' }, n: 'Gemini Flash', stance: 'neutral', status: 'failed' },
];
function SeatGly({ w }) { return w.brand ? <BrandIcon slug={w.brand} color={w.color} size={13} /> : <Icon name={w.icon} size={12} style={{ color: 'var(--text-secondary)' }} />; }
window.JudgeAnalysisView = function JudgeAnalysisView() {
  return (
    <div>
      <JHeader eyebrow="Judge analysis · structured" title="analysis.md"
        sub="The structured panel truth the reviewers and finalizer consume directly — not re-parsed prose."
        actions={<><Badge tone="neutral" mono>4 of 5 answered</Badge><Button variant="ghost" size="sm" iconLeft={<Icon name="copy" size={14} />}>Copy</Button></>} />
      <div className="jud-content" style={{ maxWidth: 780 }}>
        <div className="ja-seats">
          {JA_SEATS.map((s, i) => (
            <div className="ja-seat" key={i} style={s.status === 'failed' ? { opacity: .6 } : null}>
              <span className="ja-seat__g"><SeatGly w={s.w} /></span>
              <span className="ja-seat__n">{s.n}</span>
              <Badge tone="accent" mono>{s.stance}</Badge>
              {s.status === 'failed' && <Badge tone="danger" dot>failed</Badge>}
            </div>
          ))}
        </div>

        <Card className="ja-sec">
          <div className="ja-sec__h"><span className="ja-ic" style={{ background: 'var(--success-surface)', color: 'var(--green-400)' }}><Icon name="check-check" size={15} /></span><span className="ja-sec__t">Consensus</span></div>
          {['Limit must key on authenticated user ID, never IP.', 'Return 429 with a Retry-After header on limit.', 'Keep counters off the request-critical disk path.'].map((t, i) => (
            <div className="ja-li" key={i}><span className="dot" style={{ background: 'var(--green-500)' }}></span>{t}</div>
          ))}
        </Card>

        <Card className="ja-sec">
          <div className="ja-sec__h"><span className="ja-ic" style={{ background: 'var(--warning-surface)', color: 'var(--yellow-400)' }}><Icon name="scale" size={15} /></span><span className="ja-sec__t">Contradictions · 2</span></div>
          <div className="ja-con">
            <div className="ja-con__side"><div className="ja-con__who">Opus · first principles</div><div className="ja-con__txt">Redis token bucket — survives restart, scales out.</div></div>
            <div className="ja-con__side"><div className="ja-con__who">Composer · neutral</div><div className="ja-con__txt">In-memory map — simplest, no new dependency.</div></div>
          </div>
          <div className="ja-con">
            <div className="ja-con__side"><div className="ja-con__who">Opus</div><div className="ja-con__txt">Sliding window for smooth limits.</div></div>
            <div className="ja-con__side"><div className="ja-con__who">ChatGPT · skeptic</div><div className="ja-con__txt">Fixed window — cheaper, good enough.</div></div>
          </div>
        </Card>

        <Card className="ja-sec">
          <div className="ja-sec__h"><span className="ja-ic" style={{ background: 'var(--accent-surface)', color: 'var(--accent-text)' }}><Icon name="zap" size={15} /></span><span className="ja-sec__t">Unique insights · 3</span></div>
          <div className="ja-li"><span className="dot" style={{ background: 'var(--accent)' }}></span>Per-plan-tier limits belong in config, not code.<span style={{ flex: 1 }}></span><span className="ja-attr">Sonnet 4.6</span></div>
          <div className="ja-li"><span className="dot" style={{ background: 'var(--accent)' }}></span>Expose remaining-quota headers so clients self-throttle.<span style={{ flex: 1 }}></span><span className="ja-attr">Opus 4.8</span></div>
          <div className="ja-li"><span className="dot" style={{ background: 'var(--accent)' }}></span>Treat the limiter as fail-open by default.<span style={{ flex: 1 }}></span><span className="ja-attr">ChatGPT 5.5</span></div>
        </Card>

        <Card className="ja-sec">
          <div className="ja-sec__h"><span className="ja-ic" style={{ background: 'var(--info-surface)', color: 'var(--blue-400)' }}><Icon name="search" size={15} /></span><span className="ja-sec__t">Blind spots · no seat covered</span></div>
          <div className="ja-li"><span className="dot" style={{ background: 'var(--blue-500)' }}></span>Fail-open vs fail-closed when the limiter backend is down.</div>
          <div className="ja-li"><span className="dot" style={{ background: 'var(--blue-500)' }}></span>Multi-instance clock skew could let limits diverge.</div>
        </Card>

        <Card className="ja-sec" style={{ borderColor: 'rgba(247,107,107,.3)' }}>
          <div className="ja-sec__h"><span className="ja-ic" style={{ background: 'var(--danger-surface)', color: 'var(--red-400)' }}><Icon name="x" size={15} /></span><span className="ja-sec__t">Failed seat · 1</span></div>
          <div className="ja-li" style={{ color: 'var(--text-muted)' }}><span className="dot" style={{ background: 'var(--red-500)' }}></span>Gemini Flash timed out at 60s — surfaced, never faked. Analysis proceeded on 4 seats.</div>
        </Card>
      </div>
    </div>
  );
};

/* ============ Direct dispatch ============ */
window.DispatchView = function DispatchView() {
  const [running, setRunning] = React.useState(false);
  const [reveal, setReveal] = React.useState(false);
  return (
    <div>
      <JHeader eyebrow="Direct dispatch · RB4" title="Implement this"
        sub="Hand the final spec straight to a coding agent. No clipboard, no re-explaining."
        actions={<Badge tone="positive" dot>Doctor: healthy</Badge>} />
      <div className="jud-content" style={{ maxWidth: 760 }}>
        <div className="jd-boundary">
          <Icon name="shield" size={18} />
          <div className="t"><b>Honest boundary.</b> Dispatch runs <b>Opus 4.8 (claude-code)</b> in <b>~/code/api-gateway</b>. Allnighter is not creating a worktree or managing commits — file edits and git behavior are controlled by the selected CLI and prompt.</div>
        </div>

        <div className="jd-row">
          <span className="jd-row__l">Execution worker</span>
          <div style={{ flex: 1, maxWidth: 320 }}>
            <Select mono leading={<span style={{ display: 'inline-flex', marginRight: 2 }}><BrandIcon slug="anthropic" color="FFA630" size={15} /></span>}
              defaultValue="opus" options={[{ value: 'opus', label: 'Opus 4.8 · claude-code' }, { value: 'composer', label: 'Composer 2.5 · cursor' }]} />
          </div>
        </div>
        <div className="jd-row">
          <span className="jd-row__l">Working directory</span>
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8, fontFamily: 'var(--font-mono)', fontSize: 12, color: 'var(--text-secondary)' }}>
            <Icon name="folder" size={15} style={{ color: 'var(--text-faint)' }} /> ~/code/api-gateway
            <Button variant="ghost" size="sm">Change</Button>
          </div>
        </div>
        <div className="jd-row" style={{ borderBottom: 'none' }}>
          <span className="jd-row__l">Reveal only</span>
          <div style={{ flex: 1 }}><Switch description="Write the brief + prompt and open them, without invoking the CLI." checked={reveal} onChange={(e) => setReveal(e.target.checked)} /></div>
        </div>

        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '.07em', textTransform: 'uppercase', color: 'var(--text-faint)', margin: '18px 0 10px' }}>Handoff artifacts</div>
        <div className="jd-file"><Icon name="file-text" size={15} style={{ color: 'var(--text-faint)' }} /><span className="jd-file__n">implementation_brief.md</span><Button variant="ghost" size="sm">Open</Button></div>
        <div className="jd-file"><Icon name="file-text" size={15} style={{ color: 'var(--text-faint)' }} /><span className="jd-file__n">execution_prompt_opus.md</span><Button variant="ghost" size="sm">Open</Button></div>

        <div style={{ display: 'flex', gap: 10, marginTop: 18, alignItems: 'center' }}>
          <Button variant="primary" iconLeft={<Icon name={reveal ? 'file-text' : 'play'} size={15} />} onClick={() => !reveal && setRunning(true)}>
            {reveal ? 'Reveal artifacts' : 'Dispatch to Opus 4.8'}
          </Button>
          {running && <StatusPill status="running">Running</StatusPill>}
        </div>

        {running && (
          <div className="jd-term">
            <div className="c">$ claude-code --prompt execution_prompt_opus.md --cwd ~/code/api-gateway</div>
            <div><span className="a">•</span> read implementation_brief.md — 3 acceptance criteria, proof commands</div>
            <div><span className="a">•</span> editing src/middleware/rateLimit.ts</div>
            <div><span className="a">•</span> added test/RateLimitTests.swift</div>
            <div><span className="ok">✓</span> swift test --filter RateLimitTests — 6 passed</div>
            <div className="c">transcript → Runs/run_7f3/dispatch_opus.log</div>
          </div>
        )}
      </div>
    </div>
  );
};
