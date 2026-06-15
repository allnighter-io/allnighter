import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-menu-css')) return;
  const s = document.createElement('style'); s.id = 'al-menu-css';
  s.textContent = `
  .al-menu{position:relative;display:inline-flex}
  .al-menu__trigger{display:inline-flex}
  .al-menu__pop{position:absolute;z-index:60;top:calc(100% + 6px);min-width:184px;padding:5px;background:var(--bg-raised);
    border:1px solid var(--border-default);border-radius:var(--radius-md);box-shadow:var(--shadow-md)}
  .al-menu__pop--start{left:0}.al-menu__pop--end{right:0}
  @keyframes al-menupop{from{opacity:0;transform:translateY(-4px)}to{opacity:1;transform:none}}
  .al-menu__item{display:flex;align-items:center;gap:9px;width:100%;height:30px;padding:0 9px;border:none;background:transparent;
    border-radius:var(--radius-sm);color:var(--text-secondary);font-family:var(--font-sans);font-size:var(--text-body);
    cursor:pointer;text-align:left;transition:var(--transition-control)}
  .al-menu__item:hover{background:var(--bg-hover);color:var(--text-primary)}
  .al-menu__item.is-danger{color:var(--red-400)}
  .al-menu__item.is-danger:hover{background:var(--danger-surface)}
  .al-menu__ic{display:inline-flex;flex:none;color:var(--text-faint)}
  .al-menu__item:hover .al-menu__ic{color:inherit}
  .al-menu__ic svg{width:15px;height:15px;display:block}
  .al-menu__lbl{flex:1}
  .al-menu__kbd{font-family:var(--font-mono);font-size:10px;color:var(--text-faint)}
  .al-menu__div{height:1px;background:var(--border-subtle);margin:5px 4px}
  .al-menu__label{font-size:var(--text-caption);font-weight:600;color:var(--text-faint);padding:6px 9px 4px;letter-spacing:.03em}`;
  document.head.appendChild(s);
};

export function Menu({ trigger, items = [], align = 'start', className, ...rest }) {
  inject();
  const [open, setOpen] = React.useState(false);
  const ref = React.useRef(null);
  React.useEffect(() => {
    if (!open) return;
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    document.addEventListener('mousedown', h);
    const k = (e) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('keydown', k);
    return () => { document.removeEventListener('mousedown', h); document.removeEventListener('keydown', k); };
  }, [open]);
  return (
    <div className={['al-menu', className].filter(Boolean).join(' ')} ref={ref} {...rest}>
      <span className="al-menu__trigger" onClick={() => setOpen((o) => !o)}>{trigger}</span>
      {open && (
        <div className={'al-menu__pop al-menu__pop--' + align} role="menu">
          {items.map((it, i) => {
            if (it.divider) return <div className="al-menu__div" key={i} />;
            if (it.label && it.heading) return <div className="al-menu__label" key={i}>{it.label}</div>;
            return (
              <button key={i} role="menuitem" className={'al-menu__item' + (it.danger ? ' is-danger' : '')}
                onClick={() => { it.onClick && it.onClick(); setOpen(false); }}>
                {it.icon && <span className="al-menu__ic">{it.icon}</span>}
                <span className="al-menu__lbl">{it.label}</span>
                {it.kbd && <span className="al-menu__kbd">{it.kbd}</span>}
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
