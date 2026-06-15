import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-tabs-css')) return;
  const s = document.createElement('style'); s.id = 'al-tabs-css';
  s.textContent = `
  .al-tabs{font-family:var(--font-sans)}
  /* segmented */
  .al-tabs--segmented{display:inline-flex;gap:2px;padding:3px;background:var(--bg-subtle);
    border:1px solid var(--border-subtle);border-radius:var(--radius-md)}
  .al-tabs--segmented .al-tab{height:24px;padding:0 12px;border-radius:var(--radius-sm);border:none;background:transparent;
    color:var(--text-muted);font-size:var(--text-label);font-weight:500;cursor:pointer;transition:var(--transition-control);
    display:inline-flex;align-items:center;gap:6px}
  .al-tabs--segmented .al-tab:hover{color:var(--text-primary)}
  .al-tabs--segmented .al-tab[data-active="true"]{background:var(--bg-active);color:var(--text-primary);box-shadow:var(--shadow-xs)}
  /* underline */
  .al-tabs--underline{display:flex;gap:18px;border-bottom:1px solid var(--border-subtle)}
  .al-tabs--underline .al-tab{height:34px;padding:0 1px;border:none;background:transparent;color:var(--text-muted);
    font-size:var(--text-body);font-weight:500;cursor:pointer;position:relative;transition:color var(--duration-fast) var(--ease-out);
    display:inline-flex;align-items:center;gap:6px}
  .al-tabs--underline .al-tab:hover{color:var(--text-primary)}
  .al-tabs--underline .al-tab[data-active="true"]{color:var(--text-primary)}
  .al-tabs--underline .al-tab[data-active="true"]::after{content:"";position:absolute;left:0;right:0;bottom:-1px;height:2px;
    background:var(--accent);border-radius:2px}
  .al-tab__count{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .al-tab{white-space:nowrap}
  .al-tab:focus-visible{outline:none;box-shadow:var(--focus-ring)}`;
  document.head.appendChild(s);
};

export function Tabs({ variant = 'segmented', items = [], value, defaultValue, onChange, className, ...rest }) {
  inject();
  const [internal, setInternal] = React.useState(defaultValue ?? (items[0] && items[0].value));
  const active = value !== undefined ? value : internal;
  const pick = (v) => { setInternal(v); onChange && onChange(v); };
  return (
    <div className={['al-tabs', 'al-tabs--' + variant, className].filter(Boolean).join(' ')} role="tablist" {...rest}>
      {items.map((it) => (
        <button key={it.value} role="tab" className="al-tab" data-active={active === it.value}
          aria-selected={active === it.value} onClick={() => pick(it.value)}>
          {it.label}
          {it.count != null && <span className="al-tab__count">{it.count}</span>}
        </button>
      ))}
    </div>
  );
}
