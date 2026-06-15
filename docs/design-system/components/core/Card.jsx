import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-card-css')) return;
  const s = document.createElement('style'); s.id = 'al-card-css';
  s.textContent = `
  .al-card{background:var(--bg-raised);border:1px solid var(--border-subtle);border-radius:var(--radius-lg);
    box-shadow:var(--shadow-sm);color:var(--text-primary)}
  .al-card--pad{padding:16px}
  .al-card--flush{background:var(--bg-surface)}
  .al-card--accent{border-color:var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.06),transparent 60%),var(--bg-raised)}
  .al-card--interactive{cursor:pointer;transition:transform var(--duration-fast) var(--ease-out),box-shadow var(--duration-fast) var(--ease-out),border-color var(--duration-fast) var(--ease-out)}
  .al-card--interactive:hover{transform:translateY(-2px);box-shadow:var(--shadow-md);border-color:var(--border-default)}`;
  document.head.appendChild(s);
};

export function Card({ variant = 'default', pad = true, interactive = false, as = 'div', children, className, ...rest }) {
  inject();
  const Tag = as;
  const cls = ['al-card', pad && 'al-card--pad', variant !== 'default' && 'al-card--' + variant,
    interactive && 'al-card--interactive', className].filter(Boolean).join(' ');
  return <Tag className={cls} {...rest}>{children}</Tag>;
}
