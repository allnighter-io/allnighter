import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-switch-css')) return;
  const s = document.createElement('style'); s.id = 'al-switch-css';
  s.textContent = `
  .al-switch{display:flex;align-items:flex-start;gap:10px;font-family:var(--font-sans);cursor:pointer;user-select:none}
  .al-switch--disabled{opacity:.45;cursor:not-allowed}
  .al-switch__track{position:relative;flex:none;width:34px;height:20px;border-radius:var(--radius-pill);
    background:var(--ink-600);transition:background var(--duration-fast) var(--ease-out);margin-top:1px}
  .al-switch__thumb{position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:50%;background:#fff;
    box-shadow:var(--shadow-xs);transition:transform var(--duration-normal) var(--ease-spring)}
  .al-switch input{position:absolute;opacity:0;width:0;height:0}
  .al-switch input:checked + .al-switch__track{background:var(--accent)}
  .al-switch input:checked + .al-switch__track .al-switch__thumb{transform:translateX(14px)}
  .al-switch input:focus-visible + .al-switch__track{box-shadow:var(--focus-ring)}
  .al-switch__text{display:flex;flex-direction:column;gap:2px}
  .al-switch__label{font-size:var(--text-body);font-weight:500;color:var(--text-primary);line-height:1.3}
  .al-switch__desc{font-size:var(--text-caption);color:var(--text-muted)}`;
  document.head.appendChild(s);
};

export function Switch({ label, description, checked, defaultChecked, disabled, onChange, className, ...rest }) {
  inject();
  const cls = ['al-switch', disabled && 'al-switch--disabled', className].filter(Boolean).join(' ');
  return (
    <label className={cls}>
      <input type="checkbox" checked={checked} defaultChecked={defaultChecked} disabled={disabled} onChange={onChange} {...rest} />
      <span className="al-switch__track"><span className="al-switch__thumb" /></span>
      {(label || description) && (
        <span className="al-switch__text">
          {label && <span className="al-switch__label">{label}</span>}
          {description && <span className="al-switch__desc">{description}</span>}
        </span>
      )}
    </label>
  );
}
