// @ds-adherence-ignore -- Team command-center screens. Window globals.
const R = window.React;
const { Button, IconButton, Icon, Badge, Card, Tabs, Select, Switch, TeamHeader, TeamGlyph } = window;

(function () {
  if (document.getElementById('team-screens-css')) return;
  const s = document.createElement('style'); s.id = 'team-screens-css';
  s.textContent = `
  .tmc-hd{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;padding:24px 28px 16px;border-bottom:1px solid var(--border-subtle)}
  .tmc-hd__l{min-width:0}.tmc-eyebrow{font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--accent-text);margin-bottom:7px}
  .tmc-title{font-size:var(--text-h2);font-weight:700;letter-spacing:-.01em}.tmc-sub{font-size:13px;color:var(--text-muted);margin-top:5px;max-width:780px}
  .tmc-actions{display:flex;align-items:center;gap:8px;flex:none}.tmc-content{padding:22px 28px 36px}
  .tmc-grid{display:grid;grid-template-columns:1.28fr .78fr;gap:18px;align-items:start}
  .tmc-kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-bottom:18px}
  .tmc-kpi{padding:12px 13px;border:1px solid var(--border-subtle);background:var(--bg-surface);border-radius:var(--radius-md)}
  .tmc-kpi .n{font-family:var(--font-display);font-size:25px;font-weight:800;letter-spacing:-.02em}.tmc-kpi .m{font-size:11px;color:var(--text-muted);margin-top:2px}
  .tmc-src{display:grid;grid-template-columns:32px minmax(0,1fr) auto;gap:11px;align-items:center;padding:11px 12px;border:1px solid var(--border-subtle);
    background:var(--bg-raised);border-radius:var(--radius-md);margin-bottom:8px}
  .tmc-src:hover{border-color:var(--border-default);background:var(--bg-hover)}
  .tmc-glyph{width:32px;height:32px;border-radius:8px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;overflow:hidden}
  .tmc-glyph img{width:18px;height:18px}.tmc-src__name{font-size:13px;font-weight:650;color:var(--text-primary)}
  .tmc-src__meta{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .tmc-src__badges{display:flex;gap:5px;flex-wrap:wrap;margin-top:6px}.tmc-src__act{display:flex;align-items:center;gap:7px;flex:none}
  .tmc-paneltitle{font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--text-faint);margin-bottom:10px}
  .tmc-repairrow{display:flex;align-items:center;gap:9px;padding:9px 0;border-bottom:1px solid var(--border-subtle)}
  .tmc-repairrow:last-child{border-bottom:none}.tmc-repairrow .ic{width:28px;height:28px;border-radius:7px;background:var(--bg-active);display:flex;align-items:center;justify-content:center;color:var(--accent-text);flex:none}
  .tmc-repairrow .tx{flex:1;min-width:0}.tmc-repairrow .t{font-size:13px;font-weight:600}.tmc-repairrow .m{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-top:2px}
  .tmc-lanebar{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:18px}
  .tmc-lanegrid{display:grid;grid-template-columns:.95fr 1.05fr;gap:18px;align-items:start}
  .tmc-listhead{display:flex;align-items:center;justify-content:space-between;margin-bottom:10px}
  .tmc-listhead .h{font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--text-faint)}
  .tmc-model{display:grid;grid-template-columns:30px minmax(0,1fr) auto;gap:10px;align-items:center;padding:10px 11px;border:1px solid var(--border-subtle);
    background:var(--bg-raised);border-radius:var(--radius-md);margin-bottom:8px}
  .tmc-model .name{font-size:13px;font-weight:650}.tmc-model .meta{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-top:1px}
  .tmc-caps{display:flex;gap:5px;flex-wrap:wrap;margin-top:6px}
  .tmc-team{border:1px solid var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.06),transparent 56%),var(--bg-raised);border-radius:var(--radius-lg);box-shadow:var(--shadow-sm);overflow:hidden}
  .tmc-team__hd{display:flex;align-items:center;justify-content:space-between;gap:12px;padding:13px 14px;border-bottom:1px solid var(--border-subtle)}
  .tmc-team__hd .t{font-size:14px;font-weight:700}.tmc-team__hd .s{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-top:2px}
  .tmc-worker{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr) 20px;gap:10px;align-items:center;padding:10px 14px;border-bottom:1px solid var(--border-subtle)}
  .tmc-worker:last-child{border-bottom:none}.tmc-worker .skill{font-size:13px;font-weight:600}.tmc-worker .kind{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-top:1px}
  .tmc-worker .model{display:flex;align-items:center;justify-content:flex-end;gap:7px;font-size:12px;color:var(--text-secondary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .tmc-team__ft{display:flex;align-items:center;gap:8px;padding:12px 14px;border-top:1px solid var(--border-subtle);background:rgba(5,6,12,.18)}
  .tmc-copy{font-size:12px;color:var(--text-muted);line-height:1.5}.tmc-copy b{color:var(--accent-text)}
  .tmc-skillgrid{display:grid;grid-template-columns:260px 1fr;gap:18px;align-items:start}.tmc-skillnav{max-height:520px;overflow:auto;border-right:1px solid var(--border-subtle);padding-right:14px}
  .tmc-skillitem{padding:9px 10px;border-radius:var(--radius-sm);font-size:13px;color:var(--text-secondary);margin-bottom:4px}
  .tmc-skillitem.is-on{background:var(--bg-active);color:var(--text-primary)}.tmc-skillitem .m{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-top:2px}
  .tmc-scrim{position:fixed;inset:0;background:rgba(5,6,12,.68);backdrop-filter:blur(3px);z-index:70}
  .tmc-drawer{position:fixed;right:0;top:0;bottom:0;width:430px;z-index:80;background:var(--bg-raised);border-left:1px solid var(--border-default);box-shadow:var(--shadow-xl);display:flex;flex-direction:column}
  .tmc-drawer__hd{display:flex;align-items:flex-start;gap:11px;padding:16px;border-bottom:1px solid var(--border-subtle)}
  .tmc-drawer__ic{width:32px;height:32px;border-radius:8px;background:var(--accent-surface);color:var(--accent-text);display:flex;align-items:center;justify-content:center;flex:none}
  .tmc-drawer__t{font-size:15px;font-weight:700}.tmc-drawer__s{font-family:var(--font-mono);font-size:10px;color:var(--text-faint);margin-top:3px}
  .tmc-drawer__body{padding:14px 16px;overflow:auto;flex:1}.tmc-drawerrow{display:grid;grid-template-columns:1fr 1fr 24px;gap:8px;align-items:end;margin-bottom:9px}
  .tmc-drawer__foot{display:flex;align-items:center;gap:8px;padding:14px 16px;border-top:1px solid var(--border-subtle)}
  @media(max-width:900px){.tmc-grid,.tmc-lanegrid,.tmc-skillgrid{grid-template-columns:1fr}.tmc-kpis{grid-template-columns:repeat(2,1fr)}.tcc-nav{width:202px}.tmc-drawer{width:min(430px,92vw)}}`;
  document.head.appendChild(s);
})();

const sources = window.TEAM_SOURCES;
const models = window.TEAM_MODELS;
const skills = window.TEAM_SKILLS;
const presets = window.TEAM_PRESETS;
const modelOptions = window.TEAM_MODEL_OPTIONS;
const sourceFor = window.TeamSource;
const modelFor = window.TeamModel;

function statusTone(status) {
  return status === 'ready' ? 'positive' : status === 'installedNotSignedIn' ? 'warning' : 'danger';
}

function SourceCard({ src }) {
  return (
    <div className="tmc-src">
      <span className="tmc-glyph"><TeamGlyph source={src} /></span>
      <div>
        <div className="tmc-src__name">{src.name}</div>
        <div className="tmc-src__meta">{src.command} · {src.version} · {src.invocation} · {src.path}</div>
        <div className="tmc-src__badges">
          {src.models.map((m) => <Badge key={m} tone="neutral" mono>{m}</Badge>)}
          {src.lanes.map((l) => <Badge key={l} tone="accent">{l}</Badge>)}
        </div>
      </div>
      <div className="tmc-src__act">
        <Badge tone={statusTone(src.status)} dot>{src.status === 'ready' ? 'Ready' : 'Repair'}</Badge>
        <Button variant="ghost" size="sm" iconLeft={<Icon name="rotate-cw" size={13} />}>Check</Button>
      </div>
    </div>
  );
}

window.ReadyView = function ReadyView() {
  const ready = sources.filter((s) => s.status === 'ready').length;
  const modelCount = models.length;
  return (
    <div>
      <TeamHeader eyebrow="Ready" title="Team readiness" sub="5 sources ready · 8 bench models · last smoke 2m ago" actions={<>
        <Button variant="secondary" size="sm" iconLeft={<Icon name="rotate-cw" size={14} />}>Re-check all</Button>
        <Button variant="primary" size="sm" iconLeft={<Icon name="plus" size={14} />}>Add source</Button>
      </>} />
      <div className="tmc-content">
        <div className="tmc-kpis">
          <div className="tmc-kpi"><div className="n">{ready}/{sources.length}</div><div className="m">sources ready</div></div>
          <div className="tmc-kpi"><div className="n">{modelCount}</div><div className="m">models on bench</div></div>
          <div className="tmc-kpi"><div className="n">3</div><div className="m">lanes covered</div></div>
          <div className="tmc-kpi"><div className="n">$0</div><div className="m">marginal cost</div></div>
        </div>
        <div className="tmc-grid">
          <div>
            <div className="tmc-paneltitle">Sources · one probe per CLI</div>
            {sources.map((src) => <SourceCard key={src.id} src={src} />)}
          </div>
          <Card variant="accent">
            <div className="tmc-paneltitle">Repair panel</div>
            <div className="tmc-repairrow">
              <span className="ic"><Icon name="activity" size={15} /></span>
              <span className="tx"><div className="t">Invocation cache</div><div className="m">direct · shim · login shell</div></span>
            </div>
            <div className="tmc-repairrow">
              <span className="ic"><Icon name="terminal" size={15} /></span>
              <span className="tx"><div className="t">Login flow</div><div className="m">owned by the source CLI</div></span>
              <Button variant="secondary" size="sm">Open</Button>
            </div>
            <div className="tmc-repairrow">
              <span className="ic"><Icon name="folder" size={15} /></span>
              <span className="tx"><div className="t">Binary path</div><div className="m">aliases · shims · app bundles</div></span>
              <Button variant="ghost" size="sm">Locate</Button>
            </div>
            <div className="tmc-repairrow">
              <span className="ic"><Icon name="shield" size={15} /></span>
              <span className="tx"><div className="t">Last proof</div><div className="m">5 smokes passed · 0 failed</div></span>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
};

function ModelRow({ model }) {
  const src = sourceFor(model.source);
  return (
    <div className="tmc-model">
      <span className="tmc-glyph"><TeamGlyph model={model} /></span>
      <div>
        <div className="name">{model.name}</div>
        <div className="meta">{src.name} · {model.week}</div>
        <div className="tmc-caps">{model.caps.map((c) => <Badge key={c} tone="neutral" mono>{c}</Badge>)}</div>
      </div>
      <Badge tone="positive" dot>Ready</Badge>
    </div>
  );
}

function WorkerRow({ row }) {
  const model = modelFor(row.model);
  return (
    <div className="tmc-worker">
      <div><div className="skill">{row.name}</div><div className="kind">{row.kind}</div></div>
      <div className="model"><TeamGlyph model={model} size={15} />{model.name}</div>
      <Icon name="check" size={15} style={{ color: 'var(--green-400)' }} />
    </div>
  );
}

window.BenchView = function BenchView({ lane, onCustomize }) {
  const preset = presets[lane];
  const [type, setType] = R.useState(preset.type);
  const [effort, setEffort] = R.useState(preset.effort);
  const laneModels = models.filter((m) => m.caps.includes(lane));
  const laneSkills = skills[lane];
  const typeItems = lane === 'build'
    ? [{ value: 'Feature', label: 'Feature' }, { value: 'Bug fix', label: 'Bug fix' }, { value: 'Refactor', label: 'Refactor' }]
    : [{ value: 'Redesign', label: 'Redesign' }, { value: 'Greenfield', label: 'Greenfield' }, { value: 'App icon', label: 'App icon' }];
  return (
    <div>
      <TeamHeader eyebrow={`${preset.lane} bench`} title={`${preset.lane} team`}
        sub={`${preset.type} · ${preset.effort} default · ${preset.outputs}`}
        actions={<>
          <Badge tone="accent" mono>{preset.outputs}</Badge>
          <Button variant="primary" size="sm" iconLeft={<Icon name="settings-2" size={14} />} onClick={() => onCustomize(lane)}>Customize team</Button>
        </>} />
      <div className="tmc-content">
        <div className="tmc-lanebar">
          <div style={{ display: 'flex', gap: 10, alignItems: 'center', flexWrap: 'wrap' }}>
            <Tabs variant="segmented" value={type} onChange={setType} items={typeItems} />
            <Tabs variant="segmented" value={effort} onChange={setEffort} items={[
              { value: 'Quick', label: 'Quick' }, { value: 'Standard', label: 'Standard' }, { value: 'Deep', label: 'Deep' }]} />
          </div>
          <div className="tmc-copy"><b>{laneSkills.length} workers</b> · default {type.toLowerCase()} team · {effort.toLowerCase()}</div>
        </div>
        <div className="tmc-lanegrid">
          <div>
            <div className="tmc-listhead"><span className="h">Bench · ready models</span><Badge tone="positive" mono>{laneModels.length} ready</Badge></div>
            {laneModels.map((m) => <ModelRow key={m.id} model={m} />)}
          </div>
          <div className="tmc-team">
            <div className="tmc-team__hd">
              <div><div className="t">Default team</div><div className="s">each row is Skill | Model</div></div>
              <Button variant="secondary" size="sm" iconLeft={<Icon name="copy" size={13} />}>Save preset</Button>
            </div>
            {laneSkills.map((row) => <WorkerRow key={row.id} row={row} />)}
            <div className="tmc-team__ft">
              <Button variant="primary" size="sm" iconLeft={<Icon name="play" size={13} />}>{preset.runLabel}</Button>
              <Button variant="secondary" size="sm" iconLeft={<Icon name="settings-2" size={13} />} onClick={() => onCustomize(lane)}>Customize</Button>
              <span className="tmc-copy">{laneModels.length} ready models · {laneSkills.length} workers</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

window.CopyBenchView = function CopyBenchView({ onCustomize }) {
  return (
    <div>
      <TeamHeader eyebrow="Copy bench" title="Copy team" sub="Landing page · Standard default · 3 workers" actions={<Button variant="secondary" size="sm" iconLeft={<Icon name="settings-2" size={14} />} onClick={() => onCustomize('build')}>Customize similar team</Button>} />
      <div className="tmc-content">
        <Card>
          <div className="tmc-paneltitle">Landing page default</div>
          <div className="tmc-worker"><div><div className="skill">Offer strategist</div><div className="kind">copy</div></div><div className="model"><TeamGlyph model={modelFor('opus')} size={15} />Opus 4.8</div><Icon name="check" size={15} style={{ color: 'var(--green-400)' }} /></div>
          <div className="tmc-worker"><div><div className="skill">Objection hunter</div><div className="kind">copy</div></div><div className="model"><TeamGlyph model={modelFor('grokBuild')} size={15} />Grok Build</div><Icon name="check" size={15} style={{ color: 'var(--green-400)' }} /></div>
          <div className="tmc-worker"><div><div className="skill">Proof skeptic</div><div className="kind">copy</div></div><div className="model"><TeamGlyph model={modelFor('sonnet')} size={15} />Sonnet 4.6</div><Icon name="check" size={15} style={{ color: 'var(--green-400)' }} /></div>
        </Card>
      </div>
    </div>
  );
};

window.SkillsView = function SkillsView() {
  const all = [
    ...skills.build.map((s) => ({ ...s, lane: 'Build' })),
    ...skills.design.map((s) => ({ ...s, lane: 'Design' })),
    { id: 'offer', name: 'Offer strategist', kind: 'copy', lane: 'Copy', model: 'opus' },
    { id: 'clarity', name: 'Clarity editor', kind: 'shared', lane: 'Shared', model: 'sonnet' },
    { id: 'contrarian', name: 'Contrarian', kind: 'shared', lane: 'Shared', model: 'gpt' },
  ];
  const cur = all[0];
  return (
    <div>
      <TeamHeader eyebrow="Skills" title="Skill library" sub="12 built-ins · 3 shared · 0 custom" actions={<Button variant="primary" size="sm" iconLeft={<Icon name="plus" size={14} />}>New skill</Button>} />
      <div className="tmc-content">
        <div className="tmc-skillgrid">
          <div className="tmc-skillnav">
            {all.map((s, i) => <div key={s.id} className={'tmc-skillitem' + (i === 0 ? ' is-on' : '')}>{s.name}<div className="m">{s.kind} · {s.lane}</div></div>)}
          </div>
          <Card>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
              <div style={{ fontSize: 18, fontWeight: 700 }}>{cur.name}</div>
              <Badge tone="neutral">built-in</Badge>
              <Badge tone="accent">{cur.lane}</Badge>
            </div>
            <div className="tmc-paneltitle">Prompt template</div>
            <div style={{ fontFamily: 'var(--font-mono)', fontSize: 12, lineHeight: 1.7, color: 'var(--text-secondary)', background: 'var(--bg-void)', border: '1px solid var(--border-subtle)', borderRadius: 'var(--radius-md)', padding: 13, whiteSpace: 'pre-wrap' }}>
{`You are the ${cur.name.toLowerCase()} on an Allnighter team.

Input: the founder prompt, repo context, and any attached references.

Do not pad. Name the sharpest tradeoff, the missing proof, and the smallest next move.`}
            </div>
            <div style={{ display: 'flex', gap: 8, marginTop: 14 }}>
              <Button variant="secondary" size="sm" iconLeft={<Icon name="copy" size={14} />}>Duplicate to edit</Button>
              <Button variant="ghost" size="sm">Use in preset</Button>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
};

window.CustomizeDrawer = function CustomizeDrawer({ lane, onClose }) {
  const preset = presets[lane] || presets.build;
  const rows = skills[lane] || skills.build;
  return (
    <>
      <div className="tmc-scrim" onClick={onClose}></div>
      <div className="tmc-drawer">
        <div className="tmc-drawer__hd">
          <span className="tmc-drawer__ic"><Icon name="settings-2" size={16} /></span>
          <div style={{ flex: 1 }}>
            <div className="tmc-drawer__t">Customize team</div>
            <div className="tmc-drawer__s">{preset.lane} · {preset.type} · {preset.effort} · skill | model</div>
          </div>
          <IconButton variant="ghost" size="sm" label="Close" onClick={onClose}><Icon name="x" /></IconButton>
        </div>
        <div className="tmc-drawer__body">
          <div style={{ marginBottom: 12 }}>
            <Select label="Start from" defaultValue="default" options={[{ value: 'default', label: `${preset.type} · default` }, { value: 'fast', label: 'Fast team' }, { value: 'deep', label: 'Deep review' }]} />
          </div>
          <div className="tmc-paneltitle">Workers</div>
          {rows.map((row) => (
            <div className="tmc-drawerrow" key={row.id}>
              <Select defaultValue={row.id} options={rows.map((r) => ({ value: r.id, label: r.name }))} />
              <Select defaultValue={row.model} options={modelOptions} />
              <IconButton variant="ghost" size="sm" label="Remove worker"><Icon name="x" /></IconButton>
            </div>
          ))}
          <Button variant="secondary" size="sm" iconLeft={<Icon name="plus" size={14} />}>Add worker</Button>
          <div style={{ marginTop: 18 }}>
            <Switch defaultChecked label="Allow healthy substitutions" description="If a model is down, use another ready model with the same lane capability." />
          </div>
          <div style={{ marginTop: 18 }} className="tmc-copy"><b>{rows.length} workers</b> · {preset.outputs}. This saves the default for new {preset.lane.toLowerCase()} work orders.</div>
        </div>
        <div className="tmc-drawer__foot">
          <Button variant="secondary" size="sm" iconLeft={<Icon name="copy" size={14} />}>Save as preset</Button>
          <span style={{ flex: 1 }}></span>
          <Button variant="ghost" size="sm" onClick={onClose}>Cancel</Button>
          <Button variant="primary" size="sm" onClick={onClose}>Done</Button>
        </div>
      </div>
    </>
  );
};
