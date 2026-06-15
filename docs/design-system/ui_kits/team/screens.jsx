// @ds-adherence-ignore -- Team screens: Composer, RunView, PlanView.
const R = window.React;

(function () {
  if (document.getElementById('al-screens-css')) return;
  const s = document.createElement('style'); s.id = 'al-screens-css';
  s.textContent = `
  .alc-pad{padding:28px 32px}
  .alc-eyebrow{font-size:var(--text-caption);font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--accent-text);margin-bottom:14px}
  .alc-compose{max-width:680px;margin:0 auto;width:100%}
  .alc-prompt{background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-xl);overflow:hidden;box-shadow:var(--shadow-sm)}
  .alc-prompt:focus-within{border-color:var(--accent-border)}
  .alc-prompt textarea{display:block;width:100%;box-sizing:border-box;background:transparent;border:none;outline:none;resize:none;
    color:var(--text-primary);font-family:var(--font-sans);font-size:18px;line-height:1.5;padding:22px 22px 12px}
  .alc-prompt textarea::placeholder{color:var(--text-faint)}
  .alc-promptbar{display:flex;align-items:center;justify-content:space-between;padding:12px 14px;border-top:1px solid var(--border-subtle)}
  .alc-meta{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .alc-examples{display:flex;gap:8px;flex-wrap:wrap;margin-top:16px}
  .alc-ex{font-size:var(--text-label);color:var(--text-muted);background:var(--bg-surface);border:1px solid var(--border-subtle);
    border-radius:var(--radius-pill);padding:5px 12px;cursor:pointer;transition:var(--transition-control);white-space:nowrap}
  .alc-ex:hover{color:var(--text-primary);border-color:var(--border-default)}
  .alc-runhead{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-bottom:18px}
  .alc-runtitle{font-size:var(--text-h2);font-weight:700;letter-spacing:-.01em}
  .alc-runprompt{color:var(--text-muted);font-size:var(--text-body);margin-top:4px;max-width:560px}
  .alc-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
  .alc-synthbar{margin-top:18px;display:flex;align-items:center;gap:12px;padding:14px 16px;border-radius:var(--radius-lg);
    background:linear-gradient(180deg,rgba(255,166,48,.07),transparent),var(--bg-raised);border:1px solid var(--accent-border)}
  .alc-synthbar .st{flex:1}
  .alc-synthbar .t{font-size:var(--text-body);font-weight:600;color:var(--text-primary)}
  .alc-synthbar .m{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-muted);margin-top:2px}
  .alc-planhead{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:18px}
  .alc-sec{margin-bottom:14px}
  .alc-sec__h{display:flex;align-items:center;gap:8px;margin-bottom:10px}
  .alc-sec__ic{width:24px;height:24px;border-radius:var(--radius-sm);display:flex;align-items:center;justify-content:center;flex:none}
  .alc-sec__t{font-size:var(--text-title);font-weight:600}
  .alc-li{display:flex;gap:10px;padding:7px 0;font-size:var(--text-body);color:var(--text-secondary);line-height:1.5;border-bottom:1px solid var(--border-subtle)}
  .alc-li:last-child{border-bottom:none}
  .alc-num{flex:none;width:20px;height:20px;border-radius:50%;background:var(--accent-surface);color:var(--accent-text);
    font-family:var(--font-mono);font-size:11px;font-weight:600;display:flex;align-items:center;justify-content:center;margin-top:1px}
  .alc-dot{flex:none;width:6px;height:6px;border-radius:50%;background:var(--text-faint);margin-top:7px}
  .alc-quote{font-size:var(--text-body-lg);line-height:1.55;color:var(--text-primary);font-style:italic}
  .alc-answer{font-size:var(--text-body);color:var(--text-secondary);line-height:1.6;margin-top:8px}
  .alc-prompthdr{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:16px}
  .alc-prompthdr .p{font-size:var(--text-body);color:var(--text-secondary)}`;
  document.head.appendChild(s);
})();

/* ---------- Composer ---------- */
window.Composer = function Composer({ value, onChange, onRun, count, onExample }) {
  const { Button, Icon } = window;
  return R.createElement('div', { className: 'alc-pad', style: { display: 'flex', flexDirection: 'column', justifyContent: 'center', flex: 1 } },
    R.createElement('div', { className: 'alc-compose' },
      R.createElement('div', { className: 'alc-eyebrow' }, 'New team run'),
      R.createElement('div', { className: 'alc-prompt' },
        R.createElement('textarea', { rows: 3, placeholder: 'Ask the team one thing…', value, onChange: (e) => onChange(e.target.value) }),
        R.createElement('div', { className: 'alc-promptbar' },
          R.createElement('span', { className: 'alc-meta' }, count + ' workers · local · $0 marginal'),
          R.createElement(Button, { variant: 'primary', iconLeft: R.createElement(Icon, { name: 'play', size: 15 }), onClick: onRun, disabled: !value.trim() || count === 0 }, 'Run team'))),
      R.createElement('div', { className: 'alc-examples' },
        ['3 directions for a premium dashboard', 'rewrite our API error copy', 'plan a migration to Swift 6'].map((ex, i) =>
          R.createElement('button', { className: 'alc-ex', key: i, onClick: () => onExample(ex) }, ex)))));
};

/* ---------- RunView ---------- */
window.RunView = function RunView({ workers, states, elapsed, prompt, synth, onStop, onView }) {
  const { WorkerChip, Button, Icon, Glyph, LiveMark } = window;
  return R.createElement('div', { className: 'alc-pad' },
    R.createElement('div', { className: 'alc-runhead' },
      R.createElement('div', null,
        R.createElement('div', { className: 'alc-runtitle' }, 'Team run'),
        R.createElement('div', { className: 'alc-runprompt' }, prompt)),
      R.createElement('div', { style: { display: 'flex', alignItems: 'center', gap: 12, flex: 'none' } },
        R.createElement('span', { className: 'alc-meta', style: { fontSize: 13 } }, elapsed),
        R.createElement(Button, { variant: 'secondary', size: 'sm', iconLeft: R.createElement(Icon, { name: 'square', size: 13 }), onClick: onStop }, 'Stop'))),
    R.createElement('div', { className: 'alc-grid' },
      workers.map((w) => {
        const st = states[w.id] || {};
        return R.createElement(WorkerChip, {
          key: w.id, name: w.name, model: w.model, status: st.status || 'queued',
          meta: st.meta, glyph: R.createElement(Glyph, { worker: w }),
        });
      })),
    synth !== 'waiting' && R.createElement('div', { className: 'alc-synthbar' },
      R.createElement(LiveMark, { size: 26, run: synth === 'planning' }),
      R.createElement('div', { className: 'st' },
        R.createElement('div', { className: 't' }, synth === 'planning' ? 'Opus is planning the plan…' : 'Plan ready'),
        R.createElement('div', { className: 'm' }, synth === 'planning' ? 'reading 5 answers · 1 failed' : '5 answers · 00:42 · $0.00 marginal')),
      synth === 'ready' && R.createElement(Button, { variant: 'primary', iconLeft: R.createElement(Icon, { name: 'arrow-right', size: 15 }), onClick: onView }, 'View plan')));
};

/* ---------- PlanView ---------- */
function Section({ icon, color, title, children }) {
  const { Icon, Card } = window;
  return R.createElement('div', { className: 'alc-sec' },
    R.createElement('div', { className: 'alc-sec__h' },
      R.createElement('span', { className: 'alc-sec__ic', style: { background: color.bg, color: color.fg } }, R.createElement(Icon, { name: icon, size: 14 })),
      R.createElement('span', { className: 'alc-sec__t' }, title)),
    R.createElement(Card, { variant: 'flush' }, children));
}

window.PlanView = function PlanView({ onNew }) {
  const { Button, IconButton, Icon, Tabs, Card, StatusPill, WorkerChip, Glyph, Badge } = window;
  const [tab, setTab] = R.useState('plan');
  const P = window.AL_PLAN;
  const workers = window.AL_WORKERS, answers = window.AL_ANSWERS;
  return R.createElement('div', { className: 'alc-pad' },
    R.createElement('div', { className: 'alc-planhead' },
      R.createElement(Tabs, { variant: 'segmented', value: tab, onChange: setTab, items: [
        { value: 'plan', label: 'Plan' }, { value: 'answers', label: 'Worker answers', count: 6 }] }),
      R.createElement('div', { style: { display: 'flex', gap: 8 } },
        R.createElement(Button, { variant: 'ghost', size: 'sm', iconLeft: R.createElement(Icon, { name: 'copy', size: 14 }) }, 'Copy'),
        R.createElement(Button, { variant: 'secondary', size: 'sm', iconLeft: R.createElement(Icon, { name: 'download', size: 14 }) }, 'Export Markdown'),
        R.createElement(Button, { variant: 'primary', size: 'sm', iconLeft: R.createElement(Icon, { name: 'plus', size: 14 }), onClick: onNew }, 'New run'))),

    tab === 'plan' ? R.createElement('div', null,
      R.createElement(Card, { variant: 'accent', style: { marginBottom: 18 } },
        R.createElement('div', { className: 'alc-prompthdr' },
          R.createElement('div', { className: 'p' }, '“' + window.AL_PROMPT + '”'),
          R.createElement(Badge, { tone: 'accent', mono: true }, 'Opus 4.8')),
        R.createElement('div', { className: 'alc-meta' }, 'synthesized from 5 answers · 00:42 · $0.00 marginal · local')),
      R.createElement(Section, { icon: 'check-check', color: { bg: 'var(--success-surface)', fg: 'var(--green-400)' }, title: 'Consensus' },
        P.consensus.map((t, i) => R.createElement('div', { className: 'alc-li', key: i }, R.createElement('span', { className: 'alc-dot' }), t))),
      R.createElement(Section, { icon: 'zap', color: { bg: 'var(--warning-surface)', fg: 'var(--yellow-400)' }, title: 'Conflicts' },
        P.conflicts.map((t, i) => R.createElement('div', { className: 'alc-li', key: i }, R.createElement('span', { className: 'alc-dot' }), t))),
      R.createElement(Section, { icon: 'search', color: { bg: 'var(--info-surface)', fg: 'var(--blue-400)' }, title: 'Gaps' },
        P.gaps.map((t, i) => R.createElement('div', { className: 'alc-li', key: i }, R.createElement('span', { className: 'alc-dot' }), t))),
      R.createElement(Section, { icon: 'arrow-right', color: { bg: 'var(--accent-surface)', fg: 'var(--accent-text)' }, title: 'The plan' },
        P.plan.map((t, i) => R.createElement('div', { className: 'alc-li', key: i }, R.createElement('span', { className: 'alc-num' }, i + 1), t))),
      R.createElement(Section, { icon: 'users', color: { bg: 'var(--bg-active)', fg: 'var(--text-muted)' }, title: 'Minority report' },
        R.createElement('div', { className: 'alc-quote' }, '“' + P.minority.text + '”'),
        R.createElement('div', { className: 'alc-meta', style: { marginTop: 8 } }, '— ' + P.minority.who))
    ) : R.createElement('div', { style: { display: 'flex', flexDirection: 'column', gap: 12 } },
      workers.map((w) => R.createElement(Card, { key: w.id, variant: 'flush' },
        R.createElement('div', { style: { display: 'flex', alignItems: 'center', gap: 10, marginBottom: 2 } },
          R.createElement('span', { style: { width: 26, height: 26, borderRadius: 6, background: 'var(--bg-active)', display: 'flex', alignItems: 'center', justifyContent: 'center' } }, R.createElement(Glyph, { worker: w })),
          R.createElement('span', { style: { fontWeight: 600, flex: 1 } }, w.name),
          R.createElement('span', { style: { fontFamily: 'var(--font-mono)', fontSize: 11, color: 'var(--text-faint)' } }, w.model),
          R.createElement(StatusPill, { status: answers[w.id] ? 'done' : 'failed' })),
        answers[w.id]
          ? R.createElement('div', { className: 'alc-answer' }, answers[w.id])
          : R.createElement('div', { className: 'alc-answer', style: { color: 'var(--text-faint)' } }, 'No answer — CLI auth expired. Surfaced in Doctor, never faked.')))));
};
