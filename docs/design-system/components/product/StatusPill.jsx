import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-status-css')) return;
  const s = document.createElement('style'); s.id = 'al-status-css';
  s.textContent = `
  .al-status{display:inline-flex;align-items:center;gap:6px;height:20px;padding:0 8px 0 7px;border-radius:var(--radius-pill);
    font-family:var(--font-sans);font-size:var(--text-caption);font-weight:600;line-height:1;white-space:nowrap;border:1px solid transparent}
  .al-status__dot{width:7px;height:7px;border-radius:50%;flex:none}
  .al-status--running .al-status__dot{animation:al-statusblink 1.1s var(--ease-in-out) infinite}
  @keyframes al-statusblink{0%,100%{opacity:1}50%{opacity:.3}}
  .al-status--queued{background:var(--bg-active);color:var(--text-muted)}
  .al-status--running{background:var(--info-surface);color:var(--blue-400)}
  .al-status--done{background:var(--success-surface);color:var(--green-400)}
  .al-status--failed{background:var(--danger-surface);color:var(--red-400)}
  .al-status--timedout{background:var(--warning-surface);color:var(--yellow-400)}`;
  document.head.appendChild(s);
};

const META = {
  queued:   { label: 'Queued',    dot: 'var(--ink-400)' },
  running:  { label: 'Running',   dot: 'var(--blue-500)' },
  done:     { label: 'Done',      dot: 'var(--green-500)' },
  failed:   { label: 'Failed',    dot: 'var(--red-500)' },
  timedout: { label: 'Timed out', dot: 'var(--yellow-500)' },
};

export function StatusPill({ status = 'queued', children, className, ...rest }) {
  inject();
  const m = META[status] || META.queued;
  return (
    <span className={['al-status', 'al-status--' + status, className].filter(Boolean).join(' ')} {...rest}>
      <span className="al-status__dot" style={{ background: m.dot }} />
      {children || m.label}
    </span>
  );
}
