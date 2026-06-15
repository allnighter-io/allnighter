import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-dialog-css')) return;
  const s = document.createElement('style'); s.id = 'al-dialog-css';
  s.textContent = `
  .al-dialog__scrim{position:fixed;inset:0;z-index:100;background:var(--bg-overlay);backdrop-filter:blur(3px);
    display:flex;align-items:center;justify-content:center;padding:24px}
  .al-dialog{width:100%;background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-2xl);
    box-shadow:var(--shadow-xl)}
  .al-dialog--sm{max-width:380px}.al-dialog--md{max-width:480px}.al-dialog--lg{max-width:640px}
  .al-dialog__head{display:flex;align-items:flex-start;gap:12px;padding:20px 20px 0}
  .al-dialog__headic{width:34px;height:34px;border-radius:var(--radius-md);flex:none;display:flex;align-items:center;justify-content:center}
  .al-dialog__htext{flex:1;min-width:0}
  .al-dialog__title{font-family:var(--font-display);font-size:var(--text-h3);font-weight:700;color:var(--text-primary);letter-spacing:-.01em}
  .al-dialog__desc{font-size:var(--text-body);color:var(--text-muted);margin-top:5px;line-height:1.5}
  .al-dialog__close{margin-left:auto;flex:none}
  .al-dialog__body{padding:16px 20px 0}
  .al-dialog__foot{display:flex;justify-content:flex-end;gap:8px;padding:20px}`;
  document.head.appendChild(s);
};

const X = () => (<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M18 6 6 18" /><path d="m6 6 12 12" /></svg>);

export function Dialog({ open, onClose, title, description, icon, iconTone, size = 'md', footer, showClose = true, children }) {
  inject();
  React.useEffect(() => {
    if (!open) return;
    const h = (e) => { if (e.key === 'Escape') onClose && onClose(); };
    document.addEventListener('keydown', h);
    return () => document.removeEventListener('keydown', h);
  }, [open, onClose]);
  if (!open) return null;
  const toneBg = iconTone === 'danger' ? 'var(--danger-surface)' : iconTone === 'accent' ? 'var(--accent-surface)' : 'var(--bg-active)';
  const toneFg = iconTone === 'danger' ? 'var(--red-400)' : iconTone === 'accent' ? 'var(--accent-text)' : 'var(--text-secondary)';
  return (
    <div className="al-dialog__scrim" onMouseDown={(e) => { if (e.target === e.currentTarget) onClose && onClose(); }}>
      <div className={'al-dialog al-dialog--' + size} role="dialog" aria-modal="true">
        {(title || icon || showClose) && (
          <div className="al-dialog__head">
            {icon && <span className="al-dialog__headic" style={{ background: toneBg, color: toneFg }}>{icon}</span>}
            <div className="al-dialog__htext">
              {title && <div className="al-dialog__title">{title}</div>}
              {description && <div className="al-dialog__desc">{description}</div>}
            </div>
            {showClose && (
              <button className="al-dialog__close al-iconbtn al-iconbtn--ghost al-iconbtn--sm" aria-label="Close" onClick={onClose}><X /></button>
            )}
          </div>
        )}
        {children && <div className="al-dialog__body">{children}</div>}
        {footer && <div className="al-dialog__foot">{footer}</div>}
      </div>
    </div>
  );
}
