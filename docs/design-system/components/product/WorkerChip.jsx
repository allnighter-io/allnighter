import React from 'react';
import { StatusPill } from './StatusPill.jsx';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-worker-css')) return;
  const s = document.createElement('style'); s.id = 'al-worker-css';
  s.textContent = `
  .al-worker{display:flex;align-items:center;gap:11px;padding:11px 12px;background:var(--bg-raised);
    border:1px solid var(--border-subtle);border-radius:var(--radius-md);transition:var(--transition-control);
    font-family:var(--font-sans);text-align:left;width:100%;box-sizing:border-box}
  .al-worker--selectable{cursor:pointer}
  .al-worker--selectable:hover{border-color:var(--border-default);background:var(--bg-hover)}
  .al-worker--selected{border-color:var(--accent-border);background:linear-gradient(180deg,rgba(255,166,48,.05),transparent),var(--bg-raised)}
  .al-worker--running{border-color:rgba(91,157,255,.30)}
  .al-worker__glyph{width:30px;height:30px;border-radius:var(--radius-sm);background:var(--bg-active);
    display:flex;align-items:center;justify-content:center;flex:none;overflow:hidden}
  .al-worker__glyph img{width:18px;height:18px}
  .al-worker__main{flex:1;min-width:0;display:flex;flex-direction:column;gap:2px}
  .al-worker__name{font-size:var(--text-body);font-weight:600;color:var(--text-primary);line-height:1.25;
    white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .al-worker__model{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint);
    white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .al-worker__trail{display:flex;align-items:center;gap:10px;flex:none}
  .al-worker__meta{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-muted)}
  .al-worker__check{width:18px;height:18px;border-radius:var(--radius-xs);border:1.5px solid var(--border-strong);
    display:flex;align-items:center;justify-content:center;flex:none;transition:var(--transition-control)}
  .al-worker--selected .al-worker__check{background:var(--accent);border-color:var(--accent)}
  .al-worker__check svg{width:12px;height:12px;color:var(--text-on-amber);opacity:0}
  .al-worker--selected .al-worker__check svg{opacity:1}`;
  document.head.appendChild(s);
};

const Check = () => (
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M20 6 9 17l-5-5" />
  </svg>
);

export function WorkerChip({
  name, model, glyph, status, selectable = false, selected = false, meta, onToggle, className, ...rest
}) {
  inject();
  const Tag = selectable ? 'button' : 'div';
  const cls = ['al-worker', selectable && 'al-worker--selectable', selected && 'al-worker--selected',
    status === 'running' && 'al-worker--running', className].filter(Boolean).join(' ');
  return (
    <Tag className={cls} onClick={selectable ? onToggle : undefined} type={selectable ? 'button' : undefined} {...rest}>
      <span className="al-worker__glyph">{glyph}</span>
      <span className="al-worker__main">
        <span className="al-worker__name">{name}</span>
        {model && <span className="al-worker__model">{model}</span>}
      </span>
      <span className="al-worker__trail">
        {meta && <span className="al-worker__meta">{meta}</span>}
        {status && <StatusPill status={status} />}
        {selectable && <span className="al-worker__check"><Check /></span>}
      </span>
    </Tag>
  );
}
