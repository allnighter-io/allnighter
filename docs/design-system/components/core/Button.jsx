import React from 'react';

// Self-injecting scoped CSS (uses design tokens from styles.css)
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-btn-css')) return;
  const s = document.createElement('style'); s.id = 'al-btn-css';
  s.textContent = `
  .al-btn{--h:30px;display:inline-flex;align-items:center;justify-content:center;gap:7px;height:var(--h);
    padding:0 14px;border-radius:var(--radius-sm);border:1px solid transparent;font-family:var(--font-sans);
    font-size:var(--text-body);font-weight:600;line-height:1;letter-spacing:var(--tracking-normal);
    cursor:pointer;white-space:nowrap;transition:var(--transition-control);user-select:none}
  .al-btn:focus-visible{outline:none;box-shadow:var(--focus-ring)}
  .al-btn:disabled{opacity:.45;cursor:not-allowed}
  .al-btn--sm{--h:24px;padding:0 10px;font-size:var(--text-label)}
  .al-btn--lg{--h:36px;padding:0 18px;font-size:var(--text-body-lg)}
  .al-btn--block{width:100%}
  .al-btn__i{display:inline-flex;flex:none}
  .al-btn__i svg{width:1em;height:1em;display:block}
  .al-btn--primary{background:var(--accent);color:var(--text-on-amber)}
  .al-btn--primary:hover:not(:disabled){background:var(--accent-hover);box-shadow:var(--glow-amber-sm)}
  .al-btn--primary:active:not(:disabled){background:var(--accent-press);transform:scale(.97)}
  .al-btn--secondary{background:var(--bg-surface);color:var(--text-primary);border-color:var(--border-default)}
  .al-btn--secondary:hover:not(:disabled){background:var(--bg-hover);border-color:var(--border-strong)}
  .al-btn--secondary:active:not(:disabled){transform:scale(.97)}
  .al-btn--ghost{background:transparent;color:var(--text-secondary)}
  .al-btn--ghost:hover:not(:disabled){background:var(--bg-hover);color:var(--text-primary)}
  .al-btn--ghost:active:not(:disabled){transform:scale(.97)}
  .al-btn--danger{background:var(--danger);color:#220707}
  .al-btn--danger:hover:not(:disabled){background:var(--red-400);box-shadow:var(--glow-red)}
  .al-btn--danger:active:not(:disabled){transform:scale(.97)}`;
  document.head.appendChild(s);
};

export function Button({ variant = 'primary', size = 'md', iconLeft, iconRight, block, disabled, children, className, ...rest }) {
  inject();
  const cls = ['al-btn', 'al-btn--' + variant, size !== 'md' && 'al-btn--' + size, block && 'al-btn--block', className]
    .filter(Boolean).join(' ');
  return (
    <button className={cls} disabled={disabled} {...rest}>
      {iconLeft && <span className="al-btn__i">{iconLeft}</span>}
      {children && <span>{children}</span>}
      {iconRight && <span className="al-btn__i">{iconRight}</span>}
    </button>
  );
}
