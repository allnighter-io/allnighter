// @ds-adherence-ignore -- Review batch 4: config shell + Scorecards, Preset editor, Lens library, Workers/Doctor.
const { Button, IconButton, Icon, Badge, Card, Select, Switch, StatusPill, BrandIcon, Textarea, JHeader, JLive } = window;

(function () {
  if (document.getElementById('jud-screens4-css')) return;
  const s = document.createElement('style'); s.id = 'jud-screens4-css';
  s.textContent = `
  .jcf-nav{width:230px;flex:none;background:var(--bg-subtle);border-right:1px solid var(--border-subtle);display:flex;flex-direction:column;padding:12px 10px;gap:2px}
  .jcf-back{display:flex;align-items:center;gap:8px;padding:8px 10px;border:none;background:transparent;color:var(--text-muted);font-family:var(--font-sans);font-size:12px;font-weight:600;cursor:pointer;border-radius:var(--radius-sm);margin-bottom:8px}
  .jcf-back:hover{background:var(--bg-hover);color:var(--text-primary)}
  .jcf-item{display:flex;align-items:center;gap:10px;padding:9px 10px;border:none;background:transparent;border-radius:var(--radius-md);cursor:pointer;text-align:left;color:var(--text-secondary);font-family:var(--font-sans);font-size:13px;font-weight:500;transition:var(--transition-control)}
  .jcf-item:hover{background:var(--bg-hover)}
  .jcf-item.on{background:var(--bg-active);color:var(--text-primary)}
  .jcf-item svg{width:17px;height:17px;flex:none;color:var(--text-faint)}
  .jcf-item.on svg{color:var(--accent-text)}
  /* scorecards */
  .jsc-row{display:flex;align-items:center;gap:13px;padding:13px 0;border-bottom:1px solid var(--border-subtle)}
  .jsc-row:last-child{border-bottom:none}
  .jsc-g{width:32px;height:32px;border-radius:8px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none;overflow:hidden}
  .jsc-g img{width:19px;height:19px}
  .jsc-nm{width:128px;flex:none}
  .jsc-nm .n{font-size:13px;font-weight:600}
  .jsc-nm .r{font-family:var(--font-mono);font-size:10px;color:var(--text-faint)}
  .jsc-m{flex:1;min-width:0}
  .jsc-m .v{font-family:var(--font-mono);font-size:12px;color:var(--text-secondary);display:flex;justify-content:space-between;margin-bottom:4px}
  .jsc-bar{height:5px;border-radius:3px;background:var(--bg-active);overflow:hidden}
  .jsc-bar>i{display:block;height:100%;border-radius:3px}
  .jsc-lat{width:60px;flex:none;text-align:right;font-family:var(--font-mono);font-size:12px;color:var(--text-muted)}
  /* preset editor + lens */
  .jpe-grid{display:grid;grid-template-columns:208px 1fr;gap:20px;align-items:start}
  .jpe-list{display:flex;flex-direction:column;gap:6px}
  .jpe-p{padding:11px 12px;border:1px solid var(--border-subtle);border-radius:var(--radius-md);background:var(--bg-raised);cursor:pointer;text-align:left;width:100%;font-family:var(--font-sans);transition:var(--transition-control)}
  .jpe-p.on{border-color:var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.05),transparent),var(--bg-raised)}
  .jpe-p .n{font-size:13px;font-weight:600;display:flex;align-items:center;gap:7px}
  .jpe-p .d{font-size:11px;color:var(--text-muted);margin-top:3px;line-height:1.4}
  .jpe-stage{display:flex;align-items:center;gap:11px;padding:10px 12px;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-md);margin-bottom:7px}
  .jpe-stage__i{width:26px;height:26px;border-radius:7px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none;color:var(--text-secondary)}
  .jpe-stage__i svg{width:14px;height:14px}
  .jpe-stage__m{flex:1}.jpe-stage__t{font-size:13px;font-weight:600}.jpe-stage__s{font-family:var(--font-mono);font-size:10px;color:var(--text-faint)}
  .jpe-label{font-size:11px;font-weight:700;letter-spacing:.07em;text-transform:uppercase;color:var(--text-faint);margin:20px 0 10px}
  .jpe-lens{display:flex;align-items:center;gap:11px;padding:9px 11px;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-md);margin-bottom:7px}
  .jpe-lens__n{flex:1;font-size:13px;font-weight:500}
  /* workers */
  .jw-row{display:flex;align-items:center;gap:13px;padding:13px;background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-md);margin-bottom:8px}
  .jw-g{width:34px;height:34px;border-radius:9px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;flex:none;overflow:hidden}
  .jw-g img{width:20px;height:20px}
  .jw-m{flex:1;min-width:0}
  .jw-n{font-size:14px;font-weight:600}
  .jw-d{font-family:var(--font-mono);font-size:11px;color:var(--text-faint);margin-top:2px}
  .jw-hint{font-size:12px;color:var(--yellow-400);margin-top:4px;display:flex;align-items:center;gap:6px}
  .jw-hint code{color:var(--text-secondary)}`;
  document.head.appendChild(s);
})();

const CFG_NAV = [
  { id: 'cfg_scorecards', label: 'Worker scorecards', icon: 'gauge' },
  { id: 'cfg_presets', label: 'Workflow presets', icon: 'list' },
  { id: 'cfg_lenses', label: 'Prompt profiles', icon: 'file-text' },
  { id: 'cfg_workers', label: 'Workers & Doctor', icon: 'shield' },
];
window.JConfigShell = function JConfigShell({ active, onNav, children }) {
  return (
    <div className="jud-win">
      <div className="jud-title">
        <div className="jud-lights"><i style={{ background: '#FF5F57' }}></i><i style={{ background: '#FEBC2E' }}></i><i style={{ background: '#28C840' }}></i></div>
        <div className="jud-tc"><JLive size={16} /><span className="nm">allnighter</span><span className="sub">· settings</span></div>
        <div className="jud-tr"><Badge tone="positive" dot>5/6 healthy</Badge></div>
      </div>
      <div className="jud-body">
        <aside className="jcf-nav">
          <button className="jcf-back" onClick={() => onNav('overview')}><Icon name="chevron-right" size={14} style={{ transform: 'rotate(180deg)' }} /> Back to run</button>
          {CFG_NAV.map((n) => (
            <button key={n.id} className={'jcf-item' + (active === n.id ? ' on' : '')} onClick={() => onNav(n.id)}>
              <Icon name={n.icon} size={17} />{n.label}
            </button>
          ))}
        </aside>
        <main className="jud-main">{children}</main>
      </div>
    </div>
  );
};

/* ============ ⑩ Model scorecards ============ */
const SCORES = [
  { w: { brand: 'anthropic', color: 'FFA630' }, n: 'Opus 4.8', runs: 42, team: 92, synth: 88, exec: 88, lat: '1.9s' },
  { w: { brand: 'anthropic', color: 'AEB5C9' }, n: 'Sonnet 4.6', runs: 38, team: 95, synth: 71, exec: 81, lat: '1.4s' },
  { w: { icon: 'terminal' }, n: 'ChatGPT 5.5', runs: 40, team: 90, synth: 64, exec: 79, lat: '2.2s' },
  { w: { icon: 'square' }, n: 'Composer 2.5', runs: 18, team: 72, synth: null, exec: 83, lat: 'manual' },
  { w: { brand: 'googlegemini', color: 'E1E5F0' }, n: 'Gemini Flash', runs: 31, team: 78, synth: 55, exec: 62, lat: '0.9s' },
];
const barColor = (v) => v >= 85 ? 'var(--green-500)' : v >= 70 ? 'var(--accent)' : 'var(--yellow-500)';
function SG({ w }) { return w.brand ? <BrandIcon slug={w.brand} color={w.color} size={19} /> : <Icon name={w.icon} size={17} style={{ color: 'var(--text-secondary)' }} />; }
window.ScorecardsView = function ScorecardsView() {
  return (
    <div>
      <JHeader eyebrow="Learning" title="Worker scorecards"
        sub="Aggregated from your local run history, on demand. Estimates — no telemetry, nothing uploaded."
        actions={<Badge tone="neutral" mono>local · estimate</Badge>} />
      <div className="jud-content" style={{ maxWidth: 820 }}>
        <div style={{ display: 'flex', gap: 18, padding: '0 0 10px', fontFamily: 'var(--font-mono)', fontSize: 10, color: 'var(--text-faint)' }}>
          <span style={{ width: 173 }}></span><span style={{ flex: 1 }}>worker answer · synthesis selected · execution success</span><span>median</span>
        </div>
        {SCORES.map((s, i) => (
          <div className="jsc-row" key={i}>
            <span className="jsc-g"><SG w={s.w} /></span>
            <span className="jsc-nm"><span className="n">{s.n}</span><span className="r">{s.runs} runs</span></span>
            <span className="jsc-m">
              {[['team', s.team], ['synth', s.synth], ['exec', s.exec]].map((m, j) => (
                <div key={j} style={{ marginBottom: 4 }}>
                  <div className="v"><span style={{ color: 'var(--text-faint)' }}>{m[0]}</span><span>{m[1] == null ? '—' : m[1] + '%'}</span></div>
                  <div className="jsc-bar"><i style={{ width: (m[1] || 0) + '%', background: barColor(m[1] || 0) }}></i></div>
                </div>
              ))}
            </span>
            <span className="jsc-lat">{s.lat}</span>
          </div>
        ))}
      </div>
    </div>
  );
};

/* ============ ⑪ Workflow preset editor ============ */
const PRESETS = [
  { id: 'synthesis_only', n: 'Synthesis only', d: 'Daily driver · 2 calls' },
  { id: 'light_review', n: 'Light review', d: '3 lenses + final · default', def: true },
  { id: 'full_review', n: 'Full review', d: 'All lenses · architecture bets' },
];
window.PresetEditorView = function PresetEditorView() {
  const [sel, setSel] = React.useState('light_review');
  return (
    <div>
      <JHeader eyebrow="Configuration" title="Workflow presets"
        sub="Bind the fixed fanout/reduce chain — workers, lenses, profiles. The UI edits presets; it never invents workflow."
        actions={<Button variant="secondary" size="sm" iconLeft={<Icon name="plus" size={14} />}>New preset</Button>} />
      <div className="jud-content">
        <div className="jpe-grid">
          <div className="jpe-list">
            {PRESETS.map((p) => (
              <button key={p.id} className={'jpe-p' + (sel === p.id ? ' on' : '')} onClick={() => setSel(p.id)}>
                <span className="n">{p.n}{p.def && <Badge tone="accent">default</Badge>}</span>
                <span className="d">{p.d}</span>
              </button>
            ))}
          </div>
          <div>
            <div className="jpe-label" style={{ marginTop: 0 }}>Stage chain</div>
            {[['users', 'Team · fanout', '5 workers · stances on'], ['scale', 'Plan writer analysis · reduce', 'Opus 4.8'], ['file-text', 'Draft plan · reduce', 'Opus 4.8'], ['shield', 'Review board · fanout', '3 lenses'], ['circle-check', 'Final spec · reduce', 'first-principles · advisory']].map((s, i) => (
              <div className="jpe-stage" key={i}>
                <span className="jpe-stage__i"><Icon name={s[0]} size={14} /></span>
                <span className="jpe-stage__m"><span className="jpe-stage__t">{s[1]}</span><span className="jpe-stage__s">{s[2]}</span></span>
                {i >= 3 ? <Switch defaultChecked /> : <Badge tone="neutral" mono>required</Badge>}
              </div>
            ))}

            <div className="jpe-label">Review lenses · binding + budget routing</div>
            {[['Security & privacy', 'gemini', true], ['Code maintainer', 'sonnet', false], ['Proof / QA', 'gpt', true]].map((l, i) => (
              <div className="jpe-lens" key={i}>
                <span className="jpe-lens__n">{l[0]}</span>
                <div style={{ width: 160 }}><Select mono defaultValue={l[1]} options={[{ value: 'gemini', label: 'Gemini Flash' }, { value: 'sonnet', label: 'Sonnet 4.6' }, { value: 'gpt', label: 'ChatGPT 5.5' }]} /></div>
                <Switch label="fast" defaultChecked={l[2]} />
              </div>
            ))}

            <div className="jpe-label">Default execution worker</div>
            <div style={{ maxWidth: 280 }}><Select mono leading={<span style={{ display: 'inline-flex', marginRight: 2 }}><BrandIcon slug="anthropic" color="FFA630" size={15} /></span>} defaultValue="opus" options={[{ value: 'opus', label: 'Opus 4.8 · claude-code' }]} /></div>
          </div>
        </div>
      </div>
    </div>
  );
};

/* ============ ⑫ Prompt profile / lens library ============ */
const PROFILES = [
  { g: 'Draft synthesis', items: [['Plan writer default', 'v4', true]] },
  { g: 'Review lenses', items: [['Security & privacy', 'v3', true], ['Code maintainer', 'v3', true], ['Proof / QA', 'v3', true], ['Cost · latency · quota', 'v2', true], ['Dissent preserver', 'v2', true], ['Coverage audit', 'v1', true], ['UI / UX', 'v2', true]] },
  { g: 'Final spec', items: [['Finalizer · first principles', 'v4', true]] },
];
window.LensLibraryView = function LensLibraryView() {
  const [sel, setSel] = React.useState('Security & privacy');
  return (
    <div>
      <JHeader eyebrow="Library" title="Prompt profiles"
        sub="Versioned, editable templates. A review lens is a prompt profile — not a second kind of worker."
        actions={<Button variant="secondary" size="sm" iconLeft={<Icon name="copy" size={14} />}>Duplicate to edit</Button>} />
      <div className="jud-content">
        <div className="jpe-grid">
          <div className="jpe-list">
            {PROFILES.map((grp) => (
              <div key={grp.g}>
                <div style={{ fontSize: 10, fontWeight: 700, letterSpacing: '.06em', textTransform: 'uppercase', color: 'var(--text-faint)', margin: '12px 4px 6px' }}>{grp.g}</div>
                {grp.items.map((it) => (
                  <button key={it[0]} className={'jpe-p' + (sel === it[0] ? ' on' : '')} style={{ marginBottom: 5 }} onClick={() => setSel(it[0])}>
                    <span className="n" style={{ fontSize: 12 }}>{it[0]}</span>
                    <span className="d" style={{ fontFamily: 'var(--font-mono)' }}>{it[1]}{it[2] ? ' · built-in' : ''}</span>
                  </button>
                ))}
              </div>
            ))}
          </div>
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 14 }}>
              <span style={{ fontSize: 16, fontWeight: 700 }}>{sel}</span>
              <Badge tone="accent">review_lens</Badge><Badge tone="neutral" mono>v3</Badge><Badge tone="neutral">built-in · read-only</Badge>
            </div>
            <div className="jpe-label" style={{ marginTop: 0 }}>Template</div>
            <Textarea mono rows={11} defaultValue={"You are a security & privacy reviewer on an advisory board.\n\nInput: the founder prompt, the PlanAnalysis (consensus / contradictions /\nblind spots), and the draft plan.\n\nDo NOT restate or endorse the draft. Surface what is wrong, missing, or\nrisky from a security, privacy, permission, and data-leak lens. Challenge a\nspecific contradiction or an unsupported consensus point directly.\n\nIf you find nothing, say so briefly. Emit a verdict header:\n  verdict: ok | concerns | blocker\n  top_concerns: [ ... ]\nthen the full advisory review in Markdown."} />
          </div>
        </div>
      </div>
    </div>
  );
};

/* ============ ⑬ Workers & Doctor ============ */
const WORKERS = [
  { w: { brand: 'anthropic', color: 'FFA630' }, n: 'Opus 4.8', cli: 'claude-code · headless_cli', role: 'both', health: 'healthy' },
  { w: { icon: 'terminal' }, n: 'ChatGPT 5.5', cli: 'codex-cli · headless_cli', role: 'member', health: 'healthy' },
  { w: { brand: 'anthropic', color: 'AEB5C9' }, n: 'Sonnet 4.6', cli: 'claude-code · headless_cli', role: 'both', health: 'healthy' },
  { w: { icon: 'square' }, n: 'Composer 2.5', cli: 'cursor · manual_paste', role: 'member', health: 'manual', hint: 'IDE-bound — uses the paste fallback, not auto-invoked.' },
  { w: { brand: 'googlegemini', color: 'E1E5F0' }, n: 'Gemini Flash', cli: 'gemini-cli · headless_cli', role: 'member', health: 'unhealthy', hint: 'gemini-cli not on PATH — run: brew install gemini-cli' },
];
const HEALTH = { healthy: ['positive', 'Healthy'], manual: ['neutral', 'Manual paste'], unhealthy: ['danger', 'Unhealthy'] };
window.WorkersView = function WorkersView() {
  return (
    <div>
      <JHeader eyebrow="Workers · Doctor" title="Workers & Doctor"
        sub="Each worker is a CLI + model + driver manifest. Doctor gates dispatch — a churned CLI fails loudly, never silently."
        actions={<Button variant="secondary" size="sm" iconLeft={<Icon name="rotate-cw" size={14} />}>Run Doctor</Button>} />
      <div className="jud-content" style={{ maxWidth: 760 }}>
        {WORKERS.map((w, i) => (
          <div className="jw-row" key={i}>
            <span className="jw-g">{w.w.brand ? <BrandIcon slug={w.w.brand} color={w.w.color} size={20} /> : <Icon name={w.w.icon} size={18} style={{ color: 'var(--text-secondary)' }} />}</span>
            <span className="jw-m">
              <span className="jw-n">{w.n}</span>
              <span className="jw-d">{w.cli} · role: {w.role}</span>
              {w.hint && <span className="jw-hint" style={w.health === 'manual' ? { color: 'var(--text-muted)' } : null}><Icon name="zap" size={13} /><code>{w.hint}</code></span>}
            </span>
            <Badge tone={HEALTH[w.health][0]} dot>{HEALTH[w.health][1]}</Badge>
            <IconButton variant="ghost" size="sm" label="Configure"><Icon name="settings-2" /></IconButton>
          </div>
        ))}
      </div>
    </div>
  );
};
