import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-toast-css')) return;
  const s = document.createElement('style'); s.id = 'al-toast-css';
  s.textContent = `
  .al-toast{display:flex;align-items:flex-start;gap:11px;width:340px;max-width:100%;padding:13px 13px 13px 14px;
    background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-lg);box-shadow:var(--shadow-lg);
    font-family:var(--font-sans)}
  .al-toast--accent{border-color:var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.07),transparent 60%),var(--bg-raised)}
  .al-toast--positive{border-color:rgba(63,209,139,.32)}
  .al-toast--danger{border-color:rgba(247,107,107,.32)}
  .al-toast__ic{flex:none;width:24px;height:24px;display:flex;align-items:center;justify-content:center;margin-top:1px}
  .al-toast__ic svg{width:18px;height:18px}
  .al-toast__body{flex:1;min-width:0}
  .al-toast__title{font-size:var(--text-body);font-weight:600;color:var(--text-primary);line-height:1.35}
  .al-toast__desc{font-size:var(--text-caption);color:var(--text-muted);margin-top:2px;line-height:1.45}
  .al-toast__desc .mono,.al-toast__desc code{font-family:var(--font-mono);color:var(--text-secondary)}
  .al-toast__action{flex:none;align-self:center}
  .al-toast__close{flex:none;margin:-2px -2px 0 0}`;
  document.head.appendChild(s);
};

const X = () => (<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M18 6 6 18" /><path d="m6 6 12 12" /></svg>);

export function Toast({ tone = 'default', title, description, icon, action, onClose, className, ...rest }) {
  inject();
  return (
    <div className={['al-toast', tone !== 'default' && 'al-toast--' + tone, className].filter(Boolean).join(' ')} role="status" {...rest}>
      {icon && <span className="al-toast__ic">{icon}</span>}
      <div className="al-toast__body">
        {title && <div className="al-toast__title">{title}</div>}
        {description && <div className="al-toast__desc">{description}</div>}
      </div>
      {action && <div className="al-toast__action">{action}</div>}
      {onClose && <button className="al-toast__close al-iconbtn al-iconbtn--ghost al-iconbtn--sm" aria-label="Dismiss" onClick={onClose}><X /></button>}
    </div>
  );
}
