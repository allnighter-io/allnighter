// @ds-adherence-ignore -- Review screens: Composer, Review board, Final spec.
const { Button, IconButton, Icon, Badge, Card, Tabs, Switch, Select, Menu, StatusPill, BrandIcon, JHeader, JLive } = window;

(function () {
  if (document.getElementById('jud-screens-css')) return;
  const s = document.createElement('style'); s.id = 'jud-screens-css';
  s.textContent = `
  .jc-grid{display:grid;grid-template-columns:1.55fr 1fr;gap:22px;align-items:start}
  .jc-label{font-size:11px;font-weight:700;letter-spacing:.07em;text-transform:uppercase;color:var(--text-faint);margin:22px 0 10px}
  .jc-label:first-child{margin-top:0}
  .jc-prompt{background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-lg);overflow:hidden}
  .jc-prompt textarea{display:block;width:100%;box-sizing:border-box;background:transparent;border:none;outline:none;resize:none;
    color:var(--text-primary);font-family:var(--font-sans);font-size:16px;line-height:1.5;padding:16px}
  .jc-worker{display:flex;align-items:center;gap:11px;padding:9px 11px;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-md);margin-bottom:7px}
  .jc-glyph{width:28px;height:28px;border-radius:7px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none;overflow:hidden}
  .jc-glyph img{width:17px;height:17px}
  .jc-worker__main{flex:1;min-width:0}
  .jc-worker__n{font-size:13px;font-weight:600}
  .jc-worker__m{font-family:var(--font-mono);font-size:10px;color:var(--text-faint)}
  .jc-plan{position:sticky;top:0}
  .jc-planrow{display:flex;align-items:center;gap:8px;padding:8px 0;border-bottom:1px solid var(--border-subtle);font-size:13px}
  .jc-planrow:last-child{border-bottom:none}
  .jc-planrow .nm{flex:1;color:var(--text-secondary)}
  .jc-planrow .ct{font-family:var(--font-mono);font-size:11px;color:var(--text-muted)}
  .jc-bignum{font-family:var(--font-display);font-size:34px;font-weight:800;letter-spacing:-.02em}
  /* review board */
  .jr-lens{margin-bottom:13px}
  .jr-lens__hd{display:flex;align-items:center;gap:11px;margin-bottom:12px}
  .jr-ic{width:32px;height:32px;border-radius:9px;display:flex;align-items:center;justify-content:center;flex:none}
  .jr-ic svg{width:17px;height:17px}
  .jr-lens__t{flex:1;min-width:0}
  .jr-lens__n{font-size:15px;font-weight:600}
  .jr-lens__w{font-family:var(--font-mono);font-size:11px;color:var(--text-faint);margin-top:1px}
  .jr-concerns{display:flex;flex-direction:column;gap:8px;margin-top:4px}
  .jr-c{display:flex;gap:9px;font-size:13px;color:var(--text-secondary);line-height:1.45}
  .jr-c .dot{flex:none;width:6px;height:6px;border-radius:50%;margin-top:6px}
  .jr-foot{display:flex;align-items:center;gap:8px;margin-top:14px;padding-top:12px;border-top:1px solid var(--border-subtle)}
  /* final spec */
  .js-banner{display:flex;align-items:center;gap:10px;padding:11px 14px;border-radius:var(--radius-md);margin-bottom:20px;
    background:var(--success-surface);border:1px solid rgba(63,209,139,.3);color:var(--green-400);font-size:13px;font-weight:600}
  .js-sec{margin-bottom:22px}
  .js-sec__h{font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--accent-text);margin-bottom:10px;display:flex;align-items:center;gap:8px}
  .js-sec p{font-size:14px;color:var(--text-secondary);line-height:1.6;margin:0 0 8px}
  .js-li{display:flex;gap:10px;font-size:14px;color:var(--text-secondary);line-height:1.55;padding:5px 0}
  .js-li .n{flex:none;width:19px;height:19px;border-radius:50%;background:var(--accent-surface);color:var(--accent-text);font-family:var(--font-mono);font-size:10px;font-weight:600;display:flex;align-items:center;justify-content:center;margin-top:1px}
  .js-li .dot{flex:none;width:6px;height:6px;border-radius:50%;background:var(--text-faint);margin-top:7px}
  .js-code{font-family:var(--font-mono);font-size:12.5px;line-height:1.7;color:var(--text-secondary);background:var(--bg-void);border:1px solid var(--border-subtle);border-radius:var(--radius-md);padding:13px 15px;white-space:pre;overflow:auto}
  .js-code .c{color:var(--text-faint)}
  .js-dec{display:inline-flex;align-items:center;font-family:var(--font-sans);font-size:10px;font-weight:700;letter-spacing:.03em;padding:2px 7px;border-radius:var(--radius-xs);flex:none}
  .js-decrow{display:flex;align-items:flex-start;gap:10px;padding:9px 0;border-bottom:1px solid var(--border-subtle);font-size:13px;color:var(--text-secondary);line-height:1.5}
  .js-decrow:last-child{border-bottom:none}
  .js-decrow .who{font-weight:600;color:var(--text-primary);flex:none;width:124px}`;
  document.head.appendChild(s);
})();

const WK = {
  opus: { name: 'Opus 4.8', model: 'via claude-code', brand: 'anthropic', color: 'FFA630' },
  gpt: { name: 'ChatGPT 5.5', model: 'via codex-cli', icon: 'terminal' },
  sonnet: { name: 'Sonnet 4.6', model: 'via claude-code', brand: 'anthropic', color: 'AEB5C9' },
  composer: { name: 'Composer 2.5', model: 'via cursor', icon: 'square' },
  gemini: { name: 'Gemini Flash', model: 'via gemini-cli', brand: 'googlegemini', color: 'E1E5F0' },
};
function Gly({ w, size = 17 }) {
  return w.brand ? <BrandIcon slug={w.brand} color={w.color} size={size} /> : <Icon name={w.icon || 'terminal'} size={size - 2} style={{ color: 'var(--text-secondary)' }} />;
}
const STANCES = [
  { value: 'neutral', label: 'Neutral' }, { value: 'skeptic', label: 'Skeptic' },
  { value: 'first_principles', label: 'First principles' }, { value: 'minimalist', label: 'Minimalist' }, { value: 'user_advocate', label: 'User advocate' },
];

/* ============ Composer ============ */
const PLAN = {
  synthesis_only: { calls: 2, rows: [['Team · 5 workers', 'reused · 0', true], ['Plan writer analysis', '1'], ['Draft plan', '1']] },
  light_review: { calls: 6, rows: [['Team · 5 workers', 'reused · 0', true], ['Plan writer analysis', '1'], ['Draft plan', '1'], ['Review · 3 lenses', '3'], ['Final spec', '1']] },
  full_review: { calls: 12, rows: [['Team · 5 workers', 'reused · 0', true], ['Plan writer analysis', '1'], ['Draft plan', '1'], ['Review · 9 lenses', '9'], ['Final spec', '1']] },
};
window.ComposerView = function ComposerView({ onRun }) {
  const [preset, setPreset] = React.useState('light_review');
  const p = PLAN[preset];
  return (
    <div>
      <JHeader eyebrow="Review run" title="Compose" sub="One prompt → a team, a board of review lenses, and a pressure-tested spec." />
      <div className="jud-content">
        <div className="jc-grid">
          <div>
            <div className="jc-label">Prompt</div>
            <div className="jc-prompt">
              <textarea rows={3} defaultValue="Add per-user rate limiting to the public API." />
            </div>

            <div className="jc-label">Workflow preset</div>
            <Tabs variant="segmented" value={preset} onChange={setPreset} items={[
              { value: 'synthesis_only', label: 'Synthesis only' },
              { value: 'light_review', label: 'Light review' },
              { value: 'full_review', label: 'Full review' }]} />

            <div className="jc-label">Team · workers <span style={{ color: 'var(--text-muted)', fontWeight: 500, textTransform: 'none', letterSpacing: 0 }}>· one worker can fill several (self-fusion)</span></div>
            {[WK.opus, WK.gpt, WK.sonnet, WK.composer, WK.gemini].map((w, i) => (
              <div className="jc-worker" key={i}>
                <span className="jc-glyph"><Gly w={w} /></span>
                <span className="jc-worker__main">
                  <span className="jc-worker__n">{w.name}</span>
                  <span className="jc-worker__m">{w.model}</span>
                </span>
                <div style={{ width: 150 }}>
                  <Select mono defaultValue={i === 0 ? 'first_principles' : i === 1 ? 'skeptic' : 'neutral'} options={STANCES} />
                </div>
              </div>
            ))}

            <div className="jc-label">PlanWriter</div>
            <div style={{ maxWidth: 280 }}>
              <Select mono leading={<span style={{ display: 'inline-flex', marginRight: 2 }}><BrandIcon slug="anthropic" color="FFA630" size={15} /></span>}
                defaultValue="opus" options={[{ value: 'opus', label: 'Opus 4.8' }, { value: 'sonnet', label: 'Sonnet 4.6' }]} />
            </div>
          </div>

          <Card variant="accent" className="jc-plan">
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: '.1em', textTransform: 'uppercase', color: 'var(--accent-text)', marginBottom: 10 }}>Call plan</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
              <span className="jc-bignum">~{p.calls}</span>
              <span style={{ color: 'var(--text-muted)', fontSize: 13 }}>fresh calls</span>
            </div>
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-faint)', margin: '4px 0 14px' }}>est. 3–5 min · $0 marginal · local · estimate</div>
            {p.rows.map((r, i) => (
              <div className="jc-planrow" key={i}>
                <span className="nm">{r[0]}</span>
                {r[2] && <Badge tone="positive" mono>reuse</Badge>}
                <span className="ct">{r[1]}</span>
              </div>
            ))}
            <button className="ios-cta" style={{ marginTop: 16, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, width: '100%', height: 40, border: 'none', borderRadius: 'var(--radius-sm)', background: 'var(--accent)', color: 'var(--text-on-amber)', fontFamily: 'var(--font-sans)', fontSize: 14, fontWeight: 600, cursor: 'pointer' }} onClick={onRun}>
              <Icon name="play" size={15} /> Run {preset === 'synthesis_only' ? 'synthesis' : preset.replace('_', ' ')}
            </button>
            <div style={{ fontSize: 11, color: 'var(--text-muted)', textAlign: 'center', marginTop: 9, lineHeight: 1.5 }}>Nothing runs until you press go. Cost is never silent.</div>
          </Card>
        </div>
      </div>
    </div>
  );
};

/* ============ Review board ============ */
const LENSES = [
  { id: 'security_privacy', name: 'Security & privacy', icon: 'shield', worker: 'Gemini Flash · fast', verdict: 'blocker',
    concerns: ['Counter store is written to a world-readable path in the run folder — token/identifier leak.', 'The limit-reset endpoint has no auth; any caller can clear another user’s window.'] },
  { id: 'code_maintainer', name: 'Code maintainer', icon: 'compare', worker: 'Sonnet 4.6', verdict: 'concerns',
    concerns: ['Two sources of truth for the window (env config + DB row) — collapse to one.', 'Middleware ordering vs. auth is ambiguous; specify where the limiter sits.'] },
  { id: 'proof_qa', name: 'Proof / QA', icon: 'flask', worker: 'ChatGPT 5.5 · fast', verdict: 'concerns',
    concerns: ['No Works Test for the 429 path or the reset boundary.', 'Clock-skew across instances isn’t covered — limits could diverge.'] },
];
const VTONE = { ok: 'positive', concerns: 'warning', blocker: 'danger' };
const VIC = { ok: 'var(--success-surface)', concerns: 'var(--warning-surface)', blocker: 'var(--danger-surface)' };
const VFG = { ok: 'var(--green-400)', concerns: 'var(--yellow-400)', blocker: 'var(--red-400)' };
window.ReviewBoardView = function ReviewBoardView() {
  return (
    <div>
      <JHeader eyebrow="Review board · advisory" title="Review board"
        sub="3 lenses attacked the draft in parallel. Advisory only — master_plan.md is never overwritten."
        actions={<>
          <Badge tone="danger" dot>1 blocker</Badge>
          <Badge tone="warning" dot>2 concerns</Badge>
          <Button variant="secondary" size="sm" iconLeft={<Icon name="rotate-cw" size={14} />}>Re-run all</Button>
        </>} />
      <div className="jud-content">
        {LENSES.map((l) => (
          <Card key={l.id} className="jr-lens">
            <div className="jr-lens__hd">
              <span className="jr-ic" style={{ background: VIC[l.verdict], color: VFG[l.verdict] }}><Icon name={l.icon} size={17} /></span>
              <span className="jr-lens__t">
                <span className="jr-lens__n">{l.name}</span>
                <span className="jr-lens__w">{l.worker}</span>
              </span>
              <Badge tone={VTONE[l.verdict]} dot>{l.verdict}</Badge>
              <Menu align="end" trigger={<IconButton variant="ghost" size="sm" label="Lens actions"><Icon name="settings-2" /></IconButton>}
                items={[{ label: 'Re-run lens', icon: <Icon name="rotate-cw" /> }, { label: 'Open review_' + l.id + '.md', icon: <Icon name="file-text" /> }, { divider: true }, { label: 'Disable lens', icon: <Icon name="x" />, danger: true }]} />
            </div>
            <div className="jr-concerns">
              {l.concerns.map((c, i) => (
                <div className="jr-c" key={i}><span className="dot" style={{ background: VFG[l.verdict] }}></span>{c}</div>
              ))}
            </div>
            <div className="jr-foot">
              <Button variant="ghost" size="sm" iconLeft={<Icon name="file-text" size={14} />}>Read full review</Button>
              <Button variant="ghost" size="sm" iconLeft={<Icon name="copy" size={14} />}>Copy</Button>
              <span style={{ flex: 1 }}></span>
              <Switch label="Enabled" defaultChecked />
            </div>
          </Card>
        ))}
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, color: 'var(--text-muted)', fontSize: 13, padding: '6px 2px' }}>
          <Icon name="plus" size={16} /> full_review adds 6 more lenses (cost, dissent, coverage, UX, customer, writer) — routed to fast workers.
        </div>
      </div>
    </div>
  );
};

/* ============ Final spec ============ */
function Dec({ k }) {
  const m = { adopted: ['ADOPTED', 'var(--green-400)', 'var(--success-surface)'], partial: ['PARTIAL', 'var(--yellow-400)', 'var(--warning-surface)'], rejected: ['REJECTED', 'var(--red-400)', 'var(--danger-surface)'], deferred: ['DEFERRED', 'var(--text-muted)', 'var(--bg-active)'] }[k];
  return <span className="js-dec" style={{ color: m[1], background: m[2] }}>{m[0]}</span>;
}
window.FinalSpecView = function FinalSpecView({ onImplement }) {
  return (
    <div>
      <JHeader eyebrow="Final spec · decision-grade" title="final_spec.md"
        sub="Finalized from first principles. master_plan.md left unchanged."
        actions={<>
          <Button variant="ghost" size="sm" iconLeft={<Icon name="copy" size={14} />}>Copy</Button>
          <Button variant="secondary" size="sm" iconLeft={<Icon name="download" size={14} />}>Export</Button>
          <Button variant="primary" size="sm" iconLeft={<Icon name="arrow-right" size={14} />} onClick={onImplement}>Implement this</Button>
        </>} />
      <div className="jud-content" style={{ maxWidth: 760 }}>
        <div className="js-banner"><Icon name="circle-check" size={17} /> Executable — carries a Works Test + proof commands. Ready for dispatch.</div>

        <div className="js-sec">
          <div className="js-sec__h"><Icon name="list" size={13} /> Scope</div>
          <p>Add token-bucket rate limiting keyed by authenticated user ID to all <code>/api/*</code> routes. Default 100 req/min, configurable per plan tier. Return <code>429</code> with a <code>Retry-After</code> header on limit.</p>
        </div>
        <div className="js-sec">
          <div className="js-sec__h"><Icon name="x" size={13} /> Non-goals</div>
          <div className="js-li"><span className="dot"></span>No global/IP-based limiting (separate concern).</div>
          <div className="js-li"><span className="dot"></span>No distributed rate-limit coordination beyond a single Redis.</div>
        </div>
        <div className="js-sec">
          <div className="js-sec__h"><Icon name="compare" size={13} /> Architecture &amp; state ownership</div>
          <p>Single source of truth: a Redis token bucket per <code>userId</code>. Limiter middleware sits <em>after</em> auth, before handlers. The reset endpoint is admin-only and authenticated. No counter is written to disk.</p>
        </div>
        <div className="js-sec">
          <div className="js-sec__h"><Icon name="circle-check" size={13} /> Acceptance criteria</div>
          <div className="js-li"><span className="n">1</span>101st request within 60s for a user returns <code>429</code> + <code>Retry-After</code>.</div>
          <div className="js-li"><span className="n">2</span>Limits are isolated per user; one user’s burst never affects another.</div>
          <div className="js-li"><span className="n">3</span>Reset endpoint rejects unauthenticated callers with <code>401</code>.</div>
        </div>
        <div className="js-sec">
          <div className="js-sec__h"><Icon name="flask" size={13} /> Works Test &amp; proof wall</div>
          <div className="js-code"><span className="c"># proof commands the executor / CI runs</span>{'\n'}swift test --filter RateLimitTests{'\n'}./scripts/load-test.sh --user u1 --rps 5 --expect 429{'\n'}curl -s -o /dev/null -w "%{'{'}http_code{'}'}" localhost:8080/api/ping  <span className="c"># 200 then 429</span></div>
        </div>
        <div className="js-sec">
          <div className="js-sec__h"><Icon name="scale" size={13} /> Decisions on review feedback</div>
          <div className="js-decrow"><span className="who">Security &amp; privacy</span><Dec k="adopted" /><span>Counter moved to Redis (never disk); reset endpoint now admin-auth. The blocker is resolved.</span></div>
          <div className="js-decrow"><span className="who">Code maintainer</span><Dec k="adopted" /><span>Collapsed to a single source of truth in Redis; middleware order pinned after auth.</span></div>
          <div className="js-decrow"><span className="who">Proof / QA</span><Dec k="adopted" /><span>Added the 429 + reset-boundary tests above. Clock-skew deferred (single Redis clock).</span></div>
        </div>
        <div className="js-sec">
          <div className="js-sec__h"><Icon name="scale" size={13} /> Decisions on team contradictions</div>
          <div className="js-decrow"><span className="who">Storage</span><Dec k="rejected" /><span>In-memory map (Composer) rejected — loses limits on restart. Redis chosen.</span></div>
          <div className="js-decrow"><span className="who">Window algorithm</span><Dec k="partial" /><span>Sliding-window (Opus) vs fixed (GPT): token bucket adopted as the simpler middle.</span></div>
        </div>
        <div className="js-sec">
          <div className="js-sec__h"><Icon name="zap" size={13} /> Risks &amp; open questions</div>
          <div className="js-li"><span className="dot"></span>Redis is now a hard dependency on the request path — needs a fail-open vs fail-closed decision.</div>
        </div>
      </div>
    </div>
  );
};

window.StubView = function StubView({ stage }) {
  return (
    <div>
      <JHeader eyebrow="Up next" title={stage} sub="This macOS view is in the next mockup batch." />
      <div className="jud-content" style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', minHeight: 320, color: 'var(--text-faint)', gap: 14 }}>
        <JLive size={40} />
        <div style={{ fontFamily: 'var(--font-mono)', fontSize: 13 }}>{stage} — mocked next</div>
      </div>
    </div>
  );
};
