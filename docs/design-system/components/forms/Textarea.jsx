import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-textarea-css')) return;
  const s = document.createElement('style'); s.id = 'al-textarea-css';
  s.textContent = `
  .al-ta__box{position:relative;background:var(--bg-input);border:1px solid var(--border-default);
    border-radius:var(--radius-md);transition:var(--transition-control)}
  .al-ta__box:focus-within{border-color:var(--accent-border);box-shadow:var(--focus-ring)}
  .al-ta__box textarea{display:block;width:100%;box-sizing:border-box;background:transparent;border:none;outline:none;resize:vertical;
    color:var(--text-primary);font-family:var(--font-sans);font-size:var(--text-body);line-height:var(--leading-normal);
    padding:10px 12px}
  .al-ta--mono textarea{font-family:var(--font-mono);font-size:var(--text-mono)}
  .al-ta__box textarea::placeholder{color:var(--text-faint)}
  .al-ta__count{position:absolute;right:10px;bottom:8px;font-family:var(--font-mono);font-size:var(--text-mono-sm);
    color:var(--text-faint);pointer-events:none}`;
  document.head.appendChild(s);
};

export function Textarea({ label, hint, rows = 4, maxLength, showCount, mono, value, defaultValue, onChange, id, className, ...rest }) {
  inject();
  const fid = id || ('al-' + Math.random().toString(36).slice(2, 8));
  const [val, setVal] = React.useState(defaultValue || '');
  const count = (value !== undefined ? value : val).length;
  return (
    <div className={['al-field', className].filter(Boolean).join(' ')}>
      {label && <label className="al-field__label" htmlFor={fid}>{label}</label>}
      <div className={['al-ta__box', mono && 'al-ta--mono'].filter(Boolean).join(' ')}>
        <textarea id={fid} rows={rows} maxLength={maxLength} value={value} defaultValue={defaultValue}
          onChange={(e) => { setVal(e.target.value); onChange && onChange(e); }} {...rest} />
        {showCount && maxLength && <span className="al-ta__count">{count}/{maxLength}</span>}
      </div>
      {hint && <span className="al-field__hint">{hint}</span>}
    </div>
  );
}
