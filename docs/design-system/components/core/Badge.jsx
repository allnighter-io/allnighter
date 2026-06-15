import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-badge-css')) return;
  const s = document.createElement('style'); s.id = 'al-badge-css';
  s.textContent = `
  .al-badge{display:inline-flex;align-items:center;gap:5px;height:20px;padding:0 8px;border-radius:var(--radius-xs);
    font-family:var(--font-sans);font-size:var(--text-caption);font-weight:600;line-height:1;letter-spacing:.01em;
    border:1px solid transparent;white-space:nowrap}
  .al-badge--mono{font-family:var(--font-mono);font-weight:500}
  .al-badge__dot{width:6px;height:6px;border-radius:50%;flex:none}
  .al-badge--neutral{background:var(--bg-active);color:var(--text-secondary);border-color:var(--border-subtle)}
  .al-badge--accent{background:var(--accent-surface);color:var(--accent-text);border-color:var(--accent-border)}
  .al-badge--positive{background:var(--success-surface);color:var(--green-400)}
  .al-badge--danger{background:var(--danger-surface);color:var(--red-400)}
  .al-badge--info{background:var(--info-surface);color:var(--blue-400)}
  .al-badge--warning{background:var(--warning-surface);color:var(--yellow-400)}`;
  document.head.appendChild(s);
};

const DOT = {
  neutral: 'var(--ink-400)', accent: 'var(--accent)', positive: 'var(--green-500)',
  danger: 'var(--red-500)', info: 'var(--blue-500)', warning: 'var(--yellow-500)',
};

export function Badge({ tone = 'neutral', dot = false, mono = false, children, className, ...rest }) {
  inject();
  const cls = ['al-badge', 'al-badge--' + tone, mono && 'al-badge--mono', className].filter(Boolean).join(' ');
  return (
    <span className={cls} {...rest}>
      {dot && <span className="al-badge__dot" style={{ background: DOT[tone] }} />}
      {children}
    </span>
  );
}
