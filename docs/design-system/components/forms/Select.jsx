import React from 'react';

const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-select-css')) return;
  const s = document.createElement('style'); s.id = 'al-select-css';
  s.textContent = `
  .al-select{position:relative}
  .al-select__trigger{display:flex;align-items:center;gap:8px;width:100%;height:30px;padding:0 10px;background:var(--bg-input);
    border:1px solid var(--border-default);border-radius:var(--radius-sm);color:var(--text-primary);font-family:var(--font-sans);
    font-size:var(--text-body);cursor:pointer;transition:var(--transition-control);text-align:left}
  .al-select__trigger:hover{border-color:var(--border-strong)}
  .al-select__trigger.is-open,.al-select__trigger:focus-visible{outline:none;border-color:var(--accent-border);box-shadow:var(--focus-ring)}
  .al-select__trigger:disabled{opacity:.45;cursor:not-allowed}
  .al-select__trigger--lg{height:36px}
  .al-select__trigger--mono{font-family:var(--font-mono);font-size:var(--text-mono)}
  .al-select__val{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .al-select__ph{color:var(--text-faint)}
  .al-select__chev{flex:none;color:var(--text-faint);transition:transform var(--duration-fast) var(--ease-out)}
  .al-select__trigger.is-open .al-select__chev{transform:rotate(180deg)}
  .al-select__menu{position:absolute;z-index:50;top:calc(100% + 5px);left:0;right:0;padding:5px;background:var(--bg-raised);
    border:1px solid var(--border-default);border-radius:var(--radius-md);box-shadow:var(--shadow-md);max-height:240px;overflow:auto;
    animation:none}
  @keyframes al-pop{from{opacity:0;transform:translateY(-4px)}to{opacity:1;transform:none}}
  .al-select__opt{display:flex;align-items:center;gap:8px;width:100%;height:28px;padding:0 8px;border:none;background:transparent;
    border-radius:var(--radius-sm);color:var(--text-secondary);font-family:inherit;font-size:var(--text-body);cursor:pointer;text-align:left;transition:var(--transition-control)}
  .al-select__opt:hover{background:var(--bg-hover);color:var(--text-primary)}
  .al-select__opt.is-sel{color:var(--text-primary)}
  .al-select__opt .al-select__lbl{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .al-select__opt svg{flex:none;color:var(--accent-text)}`;
  document.head.appendChild(s);
};

const Chevron = () => (<svg className="al-select__chev" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="m6 9 6 6 6-6" /></svg>);
const Check = () => (<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"><path d="M20 6 9 17l-5-5" /></svg>);

export function Select({ label, options = [], value, defaultValue, onChange, placeholder = 'Select…', size = 'md', mono, disabled, leading, className, ...rest }) {
  inject();
  const [open, setOpen] = React.useState(false);
  const [internal, setInternal] = React.useState(defaultValue);
  const ref = React.useRef(null);
  const val = value !== undefined ? value : internal;
  React.useEffect(() => {
    if (!open) return;
    const h = (e) => { if (ref.current && !ref.current.contains(e.target)) setOpen(false); };
    document.addEventListener('mousedown', h);
    return () => document.removeEventListener('mousedown', h);
  }, [open]);
  const sel = options.find((o) => o.value === val);
  const pick = (v) => { setInternal(v); onChange && onChange(v); setOpen(false); };
  return (
    <div className={['al-field', className].filter(Boolean).join(' ')}>
      {label && <label className="al-field__label">{label}</label>}
      <div className="al-select" ref={ref}>
        <button type="button" disabled={disabled} onClick={() => setOpen((o) => !o)}
          className={['al-select__trigger', size === 'lg' && 'al-select__trigger--lg', mono && 'al-select__trigger--mono', open && 'is-open'].filter(Boolean).join(' ')} {...rest}>
          {leading}
          <span className={'al-select__val' + (sel ? '' : ' al-select__ph')}>{sel ? sel.label : placeholder}</span>
          <Chevron />
        </button>
        {open && (
          <div className="al-select__menu" role="listbox">
            {options.map((o) => (
              <button key={o.value} type="button" role="option" aria-selected={o.value === val}
                className={'al-select__opt' + (o.value === val ? ' is-sel' : '')} onClick={() => pick(o.value)}>
                <span className="al-select__lbl">{o.label}</span>
                {o.value === val && <Check />}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
