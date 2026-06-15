import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-input-css')) return;
  const s = document.createElement('style'); s.id = 'al-input-css';
  s.textContent = `
  .al-field{display:flex;flex-direction:column;gap:6px;font-family:var(--font-sans)}
  .al-field__label{font-size:var(--text-label);font-weight:500;color:var(--text-secondary)}
  .al-field__req{color:var(--accent-text);margin-left:2px}
  .al-input{display:flex;align-items:center;gap:7px;height:30px;padding:0 10px;background:var(--bg-input);
    border:1px solid var(--border-default);border-radius:var(--radius-sm);transition:var(--transition-control)}
  .al-input:focus-within{border-color:var(--accent-border);box-shadow:var(--focus-ring)}
  .al-input--error{border-color:var(--danger)}
  .al-input--lg{height:36px}
  .al-input__prefix,.al-input__suffix{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint);flex:none}
  .al-input input{flex:1;min-width:0;background:transparent;border:none;outline:none;color:var(--text-primary);
    font-size:var(--text-body);font-family:inherit}
  .al-input input::placeholder{color:var(--text-faint)}
  .al-input--mono input{font-family:var(--font-mono);font-size:var(--text-mono)}
  .al-field__hint{font-size:var(--text-caption);color:var(--text-muted)}
  .al-field__hint--error{color:var(--red-400)}`;
  document.head.appendChild(s);
};

export function Input({ label, hint, error, required, prefixText, suffix, size = 'md', mono, id, className, ...rest }) {
  inject();
  const fid = id || ('al-' + Math.random().toString(36).slice(2, 8));
  const boxCls = ['al-input', size === 'lg' && 'al-input--lg', mono && 'al-input--mono', error && 'al-input--error']
    .filter(Boolean).join(' ');
  return (
    <div className={['al-field', className].filter(Boolean).join(' ')}>
      {label && <label className="al-field__label" htmlFor={fid}>{label}{required && <span className="al-field__req">*</span>}</label>}
      <div className={boxCls}>
        {prefixText && <span className="al-input__prefix">{prefixText}</span>}
        <input id={fid} {...rest} />
        {suffix && <span className="al-input__suffix">{suffix}</span>}
      </div>
      {(error || hint) && <span className={'al-field__hint' + (error ? ' al-field__hint--error' : '')}>{error || hint}</span>}
    </div>
  );
}
