import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-iconbtn-css')) return;
  const s = document.createElement('style'); s.id = 'al-iconbtn-css';
  s.textContent = `
  .al-iconbtn{--sz:30px;display:inline-flex;align-items:center;justify-content:center;width:var(--sz);height:var(--sz);
    border-radius:var(--radius-sm);border:1px solid transparent;background:transparent;color:var(--text-secondary);
    cursor:pointer;transition:var(--transition-control);flex:none}
  .al-iconbtn:focus-visible{outline:none;box-shadow:var(--focus-ring)}
  .al-iconbtn:disabled{opacity:.4;cursor:not-allowed}
  .al-iconbtn svg{width:18px;height:18px;display:block}
  .al-iconbtn--sm{--sz:24px}.al-iconbtn--sm svg{width:15px;height:15px}
  .al-iconbtn--lg{--sz:36px}.al-iconbtn--lg svg{width:20px;height:20px}
  .al-iconbtn--ghost:hover:not(:disabled){background:var(--bg-hover);color:var(--text-primary)}
  .al-iconbtn--outline{border-color:var(--border-default);background:var(--bg-surface)}
  .al-iconbtn--outline:hover:not(:disabled){background:var(--bg-hover);border-color:var(--border-strong);color:var(--text-primary)}
  .al-iconbtn--solid{background:var(--bg-active);color:var(--text-primary)}
  .al-iconbtn--solid:hover:not(:disabled){background:var(--bg-hover)}
  .al-iconbtn--accent{background:var(--accent-surface);color:var(--accent-text);border-color:var(--accent-border)}
  .al-iconbtn--accent:hover:not(:disabled){background:rgba(255,166,48,.18)}
  .al-iconbtn:active:not(:disabled){transform:scale(.93)}`;
  document.head.appendChild(s);
};

export function IconButton({ variant = 'ghost', size = 'md', label, disabled, children, className, ...rest }) {
  inject();
  const cls = ['al-iconbtn', 'al-iconbtn--' + variant, size !== 'md' && 'al-iconbtn--' + size, className]
    .filter(Boolean).join(' ');
  return (
    <button className={cls} aria-label={label} title={label} disabled={disabled} {...rest}>
      {children}
    </button>
  );
}
