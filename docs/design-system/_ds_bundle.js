/* @ds-bundle: {"format":3,"namespace":"AllnighterDesignSystem_efa784","components":[{"name":"Badge","sourcePath":"components/core/Badge.jsx"},{"name":"Button","sourcePath":"components/core/Button.jsx"},{"name":"Card","sourcePath":"components/core/Card.jsx"},{"name":"IconButton","sourcePath":"components/core/IconButton.jsx"},{"name":"Input","sourcePath":"components/forms/Input.jsx"},{"name":"Switch","sourcePath":"components/forms/Switch.jsx"},{"name":"Textarea","sourcePath":"components/forms/Textarea.jsx"},{"name":"Tabs","sourcePath":"components/navigation/Tabs.jsx"},{"name":"StatusPill","sourcePath":"components/product/StatusPill.jsx"},{"name":"WorkerChip","sourcePath":"components/product/WorkerChip.jsx"}],"sourceHashes":{"components/core/Badge.jsx":"7b4d44d6b518","components/core/Button.jsx":"7d962aa47106","components/core/Card.jsx":"4c976703162f","components/core/IconButton.jsx":"48d1bfa043aa","components/forms/Input.jsx":"310f87107715","components/forms/Switch.jsx":"2224132f9458","components/forms/Textarea.jsx":"c7529a7aaeb5","components/navigation/Tabs.jsx":"d116c3c9b60c","components/product/StatusPill.jsx":"f52eba46364c","components/product/WorkerChip.jsx":"fdce5325325d","guidelines/explorations/design-canvas.jsx":"bd8746af6e58","ui_kits/council/chrome.jsx":"f58bc627b508","ui_kits/council/data.jsx":"71f8fc3bb152","ui_kits/council/screens.jsx":"396aa50f1f3d"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.AllnighterDesignSystem_efa784 = window.AllnighterDesignSystem_efa784 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/core/Badge.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-badge-css')) return;
  const s = document.createElement('style');
  s.id = 'al-badge-css';
  s.textContent = `
  .al-badge{display:inline-flex;align-items:center;gap:5px;height:20px;padding:0 8px;border-radius:var(--radius-xs);
    font-family:var(--font-sans);font-size:var(--text-caption);font-weight:600;line-height:1;letter-spacing:.01em;
    border:1px solid transparent;white-space:nowrap}
  .al-badge--mono{font-family:var(--font-mono);font-weight:500}
  .al-badge__dot{width:6px;height:6px;border-radius:50%;flex:none}
  .al-badge--neutral{background:var(--bg-active);color:var(--text-secondary);border-color:var(--border-subtle)}
  .al-badge--accent{background:var(--accent-surface);color:var(--accent-text);border-color:var(--accent-border)}
  .al-badge--positive{background:var(--success-surface);color:var(--green-400)}
  .al-badge--danger{background:var(--danger-surface);color:var(--red-400)}
  .al-badge--info{background:var(--info-surface);color:var(--blue-400)}
  .al-badge--warning{background:var(--warning-surface);color:var(--yellow-400)}`;
  document.head.appendChild(s);
};
const DOT = {
  neutral: 'var(--ink-400)',
  accent: 'var(--accent)',
  positive: 'var(--green-500)',
  danger: 'var(--red-500)',
  info: 'var(--blue-500)',
  warning: 'var(--yellow-500)'
};
function Badge({
  tone = 'neutral',
  dot = false,
  mono = false,
  children,
  className,
  ...rest
}) {
  inject();
  const cls = ['al-badge', 'al-badge--' + tone, mono && 'al-badge--mono', className].filter(Boolean).join(' ');
  return /*#__PURE__*/React.createElement("span", _extends({
    className: cls
  }, rest), dot && /*#__PURE__*/React.createElement("span", {
    className: "al-badge__dot",
    style: {
      background: DOT[tone]
    }
  }), children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Badge.jsx", error: String((e && e.message) || e) }); }

// components/core/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
// Self-injecting scoped CSS (uses design tokens from styles.css)
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-btn-css')) return;
  const s = document.createElement('style');
  s.id = 'al-btn-css';
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
function Button({
  variant = 'primary',
  size = 'md',
  iconLeft,
  iconRight,
  block,
  disabled,
  children,
  className,
  ...rest
}) {
  inject();
  const cls = ['al-btn', 'al-btn--' + variant, size !== 'md' && 'al-btn--' + size, block && 'al-btn--block', className].filter(Boolean).join(' ');
  return /*#__PURE__*/React.createElement("button", _extends({
    className: cls,
    disabled: disabled
  }, rest), iconLeft && /*#__PURE__*/React.createElement("span", {
    className: "al-btn__i"
  }, iconLeft), children && /*#__PURE__*/React.createElement("span", null, children), iconRight && /*#__PURE__*/React.createElement("span", {
    className: "al-btn__i"
  }, iconRight));
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }

// components/core/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-card-css')) return;
  const s = document.createElement('style');
  s.id = 'al-card-css';
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
function Card({
  variant = 'default',
  pad = true,
  interactive = false,
  as = 'div',
  children,
  className,
  ...rest
}) {
  inject();
  const Tag = as;
  const cls = ['al-card', pad && 'al-card--pad', variant !== 'default' && 'al-card--' + variant, interactive && 'al-card--interactive', className].filter(Boolean).join(' ');
  return /*#__PURE__*/React.createElement(Tag, _extends({
    className: cls
  }, rest), children);
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Card.jsx", error: String((e && e.message) || e) }); }

// components/core/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-iconbtn-css')) return;
  const s = document.createElement('style');
  s.id = 'al-iconbtn-css';
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
function IconButton({
  variant = 'ghost',
  size = 'md',
  label,
  disabled,
  children,
  className,
  ...rest
}) {
  inject();
  const cls = ['al-iconbtn', 'al-iconbtn--' + variant, size !== 'md' && 'al-iconbtn--' + size, className].filter(Boolean).join(' ');
  return /*#__PURE__*/React.createElement("button", _extends({
    className: cls,
    "aria-label": label,
    title: label,
    disabled: disabled
  }, rest), children);
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/forms/Input.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
// Self-injecting scoped CSS (uses design tokens from styles.css)
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-input-css')) return;
  const s = document.createElement('style');
  s.id = 'al-input-css';
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
function Input({
  label,
  hint,
  error,
  required,
  prefixText,
  suffix,
  size = 'md',
  mono,
  id,
  className,
  ...rest
}) {
  inject();
  const fid = id || 'al-' + Math.random().toString(36).slice(2, 8);
  const boxCls = ['al-input', size === 'lg' && 'al-input--lg', mono && 'al-input--mono', error && 'al-input--error'].filter(Boolean).join(' ');
  return /*#__PURE__*/React.createElement("div", {
    className: ['al-field', className].filter(Boolean).join(' ')
  }, label && /*#__PURE__*/React.createElement("label", {
    className: "al-field__label",
    htmlFor: fid
  }, label, required && /*#__PURE__*/React.createElement("span", {
    className: "al-field__req"
  }, "*")), /*#__PURE__*/React.createElement("div", {
    className: boxCls
  }, prefixText && /*#__PURE__*/React.createElement("span", {
    className: "al-input__prefix"
  }, prefixText), /*#__PURE__*/React.createElement("input", _extends({
    id: fid
  }, rest)), suffix && /*#__PURE__*/React.createElement("span", {
    className: "al-input__suffix"
  }, suffix)), (error || hint) && /*#__PURE__*/React.createElement("span", {
    className: 'al-field__hint' + (error ? ' al-field__hint--error' : '')
  }, error || hint));
}
Object.assign(__ds_scope, { Input });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Input.jsx", error: String((e && e.message) || e) }); }

// components/forms/Switch.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-switch-css')) return;
  const s = document.createElement('style');
  s.id = 'al-switch-css';
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
function Switch({
  label,
  description,
  checked,
  defaultChecked,
  disabled,
  onChange,
  className,
  ...rest
}) {
  inject();
  const cls = ['al-switch', disabled && 'al-switch--disabled', className].filter(Boolean).join(' ');
  return /*#__PURE__*/React.createElement("label", {
    className: cls
  }, /*#__PURE__*/React.createElement("input", _extends({
    type: "checkbox",
    checked: checked,
    defaultChecked: defaultChecked,
    disabled: disabled,
    onChange: onChange
  }, rest)), /*#__PURE__*/React.createElement("span", {
    className: "al-switch__track"
  }, /*#__PURE__*/React.createElement("span", {
    className: "al-switch__thumb"
  })), (label || description) && /*#__PURE__*/React.createElement("span", {
    className: "al-switch__text"
  }, label && /*#__PURE__*/React.createElement("span", {
    className: "al-switch__label"
  }, label), description && /*#__PURE__*/React.createElement("span", {
    className: "al-switch__desc"
  }, description)));
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Switch.jsx", error: String((e && e.message) || e) }); }

// components/forms/Textarea.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-textarea-css')) return;
  const s = document.createElement('style');
  s.id = 'al-textarea-css';
  s.textContent = `
  .al-field{display:flex;flex-direction:column;gap:6px;font-family:var(--font-sans)}
  .al-field__label{font-size:var(--text-label);font-weight:500;color:var(--text-secondary)}
  .al-field__hint{font-size:var(--text-caption);color:var(--text-muted)}
  .al-ta__box{position:relative;background:var(--bg-input);border:1px solid var(--border-default);
    border-radius:var(--radius-md);transition:var(--transition-control)}
  .al-ta__box:focus-within{border-color:var(--accent-border);box-shadow:var(--focus-ring)}
  .al-ta__box textarea{display:block;width:100%;box-sizing:border-box;background:transparent;border:none;outline:none;
    resize:vertical;color:var(--text-primary);font-family:var(--font-sans);font-size:var(--text-body);
    line-height:var(--leading-normal);padding:10px 12px}
  .al-ta--mono textarea{font-family:var(--font-mono);font-size:var(--text-mono)}
  .al-ta__box textarea::placeholder{color:var(--text-faint)}
  .al-ta__count{position:absolute;right:10px;bottom:8px;font-family:var(--font-mono);font-size:var(--text-mono-sm);
    color:var(--text-faint);pointer-events:none}`;
  document.head.appendChild(s);
};
function Textarea({
  label,
  hint,
  rows = 4,
  maxLength,
  showCount,
  mono,
  value,
  defaultValue,
  onChange,
  id,
  className,
  ...rest
}) {
  inject();
  const fid = id || 'al-' + Math.random().toString(36).slice(2, 8);
  const [val, setVal] = React.useState(defaultValue || '');
  const count = (value !== undefined ? value : val).length;
  return /*#__PURE__*/React.createElement("div", {
    className: ['al-field', className].filter(Boolean).join(' ')
  }, label && /*#__PURE__*/React.createElement("label", {
    className: "al-field__label",
    htmlFor: fid
  }, label), /*#__PURE__*/React.createElement("div", {
    className: ['al-ta__box', mono && 'al-ta--mono'].filter(Boolean).join(' ')
  }, /*#__PURE__*/React.createElement("textarea", _extends({
    id: fid,
    rows: rows,
    maxLength: maxLength,
    value: value,
    defaultValue: defaultValue,
    onChange: e => {
      setVal(e.target.value);
      onChange && onChange(e);
    }
  }, rest)), showCount && maxLength && /*#__PURE__*/React.createElement("span", {
    className: "al-ta__count"
  }, count + '/' + maxLength)), hint && /*#__PURE__*/React.createElement("span", {
    className: "al-field__hint"
  }, hint));
}
Object.assign(__ds_scope, { Textarea });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Textarea.jsx", error: String((e && e.message) || e) }); }

// components/navigation/Tabs.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-tabs-css')) return;
  const s = document.createElement('style');
  s.id = 'al-tabs-css';
  s.textContent = `
  .al-tabs--segmented{display:inline-flex;gap:2px;padding:3px;background:var(--bg-subtle);
    border:1px solid var(--border-subtle);border-radius:var(--radius-md)}
  .al-tabs--segmented .al-tab{height:24px;padding:0 12px;border-radius:var(--radius-sm);border:none;background:transparent;
    color:var(--text-muted);font-size:var(--text-label);font-weight:500;cursor:pointer;transition:var(--transition-control);
    display:inline-flex;align-items:center;gap:6px;font-family:var(--font-sans)}
  .al-tabs--segmented .al-tab:hover{color:var(--text-primary)}
  .al-tabs--segmented .al-tab[data-active="true"]{background:var(--bg-active);color:var(--text-primary);box-shadow:var(--shadow-xs)}
  .al-tabs--underline{display:flex;gap:18px;border-bottom:1px solid var(--border-subtle)}
  .al-tabs--underline .al-tab{height:34px;padding:0 1px;border:none;background:transparent;color:var(--text-muted);
    font-size:var(--text-body);font-weight:500;cursor:pointer;position:relative;
    transition:color var(--duration-fast) var(--ease-out);display:inline-flex;align-items:center;gap:6px;font-family:var(--font-sans)}
  .al-tabs--underline .al-tab:hover{color:var(--text-primary)}
  .al-tabs--underline .al-tab[data-active="true"]{color:var(--text-primary)}
  .al-tabs--underline .al-tab[data-active="true"]::after{content:"";position:absolute;left:0;right:0;bottom:-1px;height:2px;
    background:var(--accent);border-radius:2px}
  .al-tab__count{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .al-tab:focus-visible{outline:none;box-shadow:var(--focus-ring)}
  .al-tab{white-space:nowrap}`;
  document.head.appendChild(s);
};
function Tabs({
  variant = 'segmented',
  items = [],
  value,
  defaultValue,
  onChange,
  className,
  ...rest
}) {
  inject();
  const [internal, setInternal] = React.useState(defaultValue != null ? defaultValue : items[0] && items[0].value);
  const active = value !== undefined ? value : internal;
  const cls = ['al-tabs', 'al-tabs--' + variant, className].filter(Boolean).join(' ');
  return /*#__PURE__*/React.createElement("div", _extends({
    className: cls,
    role: "tablist"
  }, rest), items.map(it => /*#__PURE__*/React.createElement("button", {
    key: it.value,
    role: "tab",
    className: "al-tab",
    "data-active": active === it.value,
    "aria-selected": active === it.value,
    onClick: () => {
      setInternal(it.value);
      onChange && onChange(it.value);
    }
  }, it.label, it.count != null && /*#__PURE__*/React.createElement("span", {
    className: "al-tab__count"
  }, it.count))));
}
Object.assign(__ds_scope, { Tabs });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/Tabs.jsx", error: String((e && e.message) || e) }); }

// components/product/StatusPill.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-status-css')) return;
  const s = document.createElement('style');
  s.id = 'al-status-css';
  s.textContent = `
  .al-status{display:inline-flex;align-items:center;gap:6px;height:20px;padding:0 8px 0 7px;border-radius:var(--radius-pill);
    font-family:var(--font-sans);font-size:var(--text-caption);font-weight:600;line-height:1;white-space:nowrap;border:1px solid transparent}
  .al-status__dot{width:7px;height:7px;border-radius:50%;flex:none}
  .al-status--running .al-status__dot{animation:al-statusblink 1.1s var(--ease-in-out) infinite}
  @keyframes al-statusblink{0%,100%{opacity:1}50%{opacity:.3}}
  .al-status--queued{background:var(--bg-active);color:var(--text-muted)}
  .al-status--running{background:var(--info-surface);color:var(--blue-400)}
  .al-status--done{background:var(--success-surface);color:var(--green-400)}
  .al-status--failed{background:var(--danger-surface);color:var(--red-400)}
  .al-status--timedout{background:var(--warning-surface);color:var(--yellow-400)}`;
  document.head.appendChild(s);
};
const META = {
  queued: {
    label: 'Queued',
    dot: 'var(--ink-400)'
  },
  running: {
    label: 'Running',
    dot: 'var(--blue-500)'
  },
  done: {
    label: 'Done',
    dot: 'var(--green-500)'
  },
  failed: {
    label: 'Failed',
    dot: 'var(--red-500)'
  },
  timedout: {
    label: 'Timed out',
    dot: 'var(--yellow-500)'
  }
};
function StatusPill({
  status = 'queued',
  children,
  className,
  ...rest
}) {
  inject();
  const m = META[status] || META.queued;
  return /*#__PURE__*/React.createElement("span", _extends({
    className: ['al-status', 'al-status--' + status, className].filter(Boolean).join(' ')
  }, rest), /*#__PURE__*/React.createElement("span", {
    className: "al-status__dot",
    style: {
      background: m.dot
    }
  }), children || m.label);
}
Object.assign(__ds_scope, { StatusPill });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/product/StatusPill.jsx", error: String((e && e.message) || e) }); }

// components/product/WorkerChip.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const inject = () => {
  if (typeof document === 'undefined' || document.getElementById('al-worker-css')) return;
  const s = document.createElement('style');
  s.id = 'al-worker-css';
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
const Check = () => /*#__PURE__*/React.createElement("svg", {
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: "3.5",
  strokeLinecap: "round",
  strokeLinejoin: "round"
}, /*#__PURE__*/React.createElement("path", {
  d: "M20 6 9 17l-5-5"
}));
function WorkerChip({
  name,
  model,
  glyph,
  status,
  selectable = false,
  selected = false,
  meta,
  onToggle,
  className,
  ...rest
}) {
  inject();
  const Tag = selectable ? 'button' : 'div';
  const cls = ['al-worker', selectable && 'al-worker--selectable', selected && 'al-worker--selected', status === 'running' && 'al-worker--running', className].filter(Boolean).join(' ');
  return /*#__PURE__*/React.createElement(Tag, _extends({
    className: cls,
    onClick: selectable ? onToggle : undefined,
    type: selectable ? 'button' : undefined
  }, rest), /*#__PURE__*/React.createElement("span", {
    className: "al-worker__glyph"
  }, glyph), /*#__PURE__*/React.createElement("span", {
    className: "al-worker__main"
  }, /*#__PURE__*/React.createElement("span", {
    className: "al-worker__name"
  }, name), model && /*#__PURE__*/React.createElement("span", {
    className: "al-worker__model"
  }, model)), /*#__PURE__*/React.createElement("span", {
    className: "al-worker__trail"
  }, meta && /*#__PURE__*/React.createElement("span", {
    className: "al-worker__meta"
  }, meta), status && /*#__PURE__*/React.createElement(__ds_scope.StatusPill, {
    status: status
  }), selectable && /*#__PURE__*/React.createElement("span", {
    className: "al-worker__check"
  }, /*#__PURE__*/React.createElement(Check, null))));
}
Object.assign(__ds_scope, { WorkerChip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/product/WorkerChip.jsx", error: String((e && e.message) || e) }); }

// guidelines/explorations/design-canvas.jsx
try { (() => {
// @ds-adherence-ignore -- omelette starter scaffold (raw elements/hex/px by design)

/* BEGIN USAGE */
// DesignCanvas.jsx — Figma-ish design canvas wrapper
// Warm gray grid bg + Sections + Artboards + PostIt notes.
// Exports (to window): DesignCanvas, DCSection, DCArtboard, DCPostIt.
// Artboards are reorderable (grip-drag), deletable, labels/titles are
// inline-editable, and any artboard can be opened in a fullscreen focus
// overlay (←/→/Esc). State persists to a .design-canvas.state.json sidecar
// via the host bridge. No assets, no deps.
//
// Usage:
//   <DesignCanvas>
//     <DCSection id="onboarding" title="Onboarding" subtitle="First-run variants">
//       <DCArtboard id="a" label="A · Dusk" width={260} height={480}>…</DCArtboard>
//       <DCArtboard id="b" label="B · Minimal" width={260} height={480}>…</DCArtboard>
//     </DCSection>
//   </DesignCanvas>
//
// Artboards are static design frames, not scroll regions — never use
// height: 100% + overflow: auto/scroll on inner elements; size each artboard
// to fit its content (explicit pixel height, or let it grow).
/* END USAGE */

const DC = {
  bg: '#f0eee9',
  grid: 'rgba(0,0,0,0.06)',
  label: 'rgba(60,50,40,0.7)',
  title: 'rgba(40,30,20,0.85)',
  subtitle: 'rgba(60,50,40,0.6)',
  postitBg: '#fef4a8',
  postitText: '#5a4a2a',
  font: '-apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif'
};

// One-time CSS injection (classes are dc-prefixed so they don't collide with
// the hosted design's own styles).
if (typeof document !== 'undefined' && !document.getElementById('dc-styles')) {
  const s = document.createElement('style');
  s.id = 'dc-styles';
  s.textContent = ['.dc-editable{cursor:text;outline:none;white-space:nowrap;border-radius:3px;padding:0 2px;margin:0 -2px}', '.dc-editable:focus{background:#fff;box-shadow:0 0 0 1.5px #c96442}', '[data-dc-slot]{transition:transform .18s cubic-bezier(.2,.7,.3,1)}', '[data-dc-slot].dc-dragging{transition:none;z-index:10;pointer-events:none}', '[data-dc-slot].dc-dragging .dc-card{box-shadow:0 12px 40px rgba(0,0,0,.25),0 0 0 2px #c96442;transform:scale(1.02)}',
  // isolation:isolate contains artboard content's z-indexes so a
  // z-indexed child (sticky navbar etc.) can't paint over .dc-header or
  // the .dc-menu popover that drops into the top of the card.
  '.dc-card{isolation:isolate;transition:box-shadow .15s,transform .15s}', '.dc-card *{scrollbar-width:none}', '.dc-card *::-webkit-scrollbar{display:none}',
  // Per-artboard header: grip + label on the left, delete/expand on the
  // right. Single flex row; when the artboard's on-screen width is too
  // narrow for both the label yields (ellipsis, then hidden entirely below
  // ~4ch via the container query) and the buttons stay on the row.
  '.dc-header{position:absolute;bottom:100%;left:-4px;margin-bottom:calc(4px * var(--dc-inv-zoom,1));z-index:2;', '  display:flex;align-items:center;container-type:inline-size}', '.dc-labelrow{display:flex;align-items:center;gap:4px;height:24px;flex:1 1 auto;min-width:0}', '.dc-grip{flex:0 0 auto;cursor:grab;display:flex;align-items:center;padding:5px 4px;border-radius:4px;transition:background .12s,opacity .12s}', '.dc-grip:hover{background:rgba(0,0,0,.08)}', '.dc-grip:active{cursor:grabbing}', '.dc-labeltext{flex:1 1 auto;min-width:0;cursor:pointer;border-radius:4px;padding:3px 6px;', '  display:flex;align-items:center;transition:background .12s;overflow:hidden}',
  // Below ~4ch of label room: hide the label entirely, and drop the grip to
  // hover-only (same reveal rule as .dc-btns) so a narrow header is clean
  // until the card is moused.
  '@container (max-width: 110px){', '  .dc-labeltext{display:none}', '  .dc-grip{opacity:0}', '  [data-dc-slot]:hover .dc-grip{opacity:1}', '}', '.dc-labeltext:hover{background:rgba(0,0,0,.05)}', '.dc-labeltext .dc-editable{overflow:hidden;text-overflow:ellipsis;max-width:100%}', '.dc-labeltext .dc-editable:focus{overflow:visible;text-overflow:clip}', '.dc-btns{flex:0 0 auto;margin-left:auto;display:flex;gap:2px;opacity:0;transition:opacity .12s}', '[data-dc-slot]:hover .dc-btns,.dc-btns:has(.dc-menu){opacity:1}', '.dc-expand,.dc-kebab{width:22px;height:22px;border-radius:5px;border:none;cursor:pointer;padding:0;', '  background:transparent;color:rgba(60,50,40,.7);display:flex;align-items:center;justify-content:center;', '  font:inherit;transition:background .12s,color .12s}', '.dc-expand:hover,.dc-kebab:hover{background:rgba(0,0,0,.06);color:#2a251f}',
  // Slot hosting an open menu floats above later siblings (which otherwise
  // paint on top — same z-index:auto, later DOM order) so the popup isn't
  // clipped by the next card.
  '[data-dc-slot]:has(.dc-menu){z-index:10}', '.dc-menu{position:absolute;top:100%;right:0;margin-top:4px;background:#fff;border-radius:8px;', '  box-shadow:0 8px 28px rgba(0,0,0,.18),0 0 0 1px rgba(0,0,0,.05);padding:4px;min-width:160px;z-index:10}', '.dc-menu button{display:block;width:100%;padding:7px 10px;border:0;background:transparent;', '  border-radius:5px;font-family:inherit;font-size:13px;font-weight:500;line-height:1.2;', '  color:#29261b;cursor:pointer;text-align:left;transition:background .12s;white-space:nowrap}', '.dc-menu button:hover{background:rgba(0,0,0,.05)}', '.dc-menu hr{border:0;border-top:1px solid rgba(0,0,0,.08);margin:4px 2px}', '.dc-menu .dc-danger{color:#c96442}', '.dc-menu .dc-danger:hover{background:rgba(201,100,66,.1)}',
  // Chrome (titles / labels / buttons) counter-scales against the viewport
  // zoom so it stays a constant on-screen size. --dc-inv-zoom is set by
  // DCViewport on every transform update and inherits to all descendants —
  // any overlay inside the world (e.g. a TweaksPanel on an artboard) can use
  // it the same way.
  //
  // The header uses transform:scale (out-of-flow, so layout impact doesn't
  // matter) with its world-space width set to card-width / inv-zoom so that
  // after counter-scaling its on-screen width exactly matches the card's —
  // that's what lets the container query + text-overflow behave against the
  // card's visible edge at every zoom level.
  //
  // The section head uses CSS zoom instead of transform so its layout box
  // grows with the counter-scale, pushing the card row down — otherwise the
  // constant-screen-size title would overflow into the (shrinking) world-
  // space gap and overlap the artboard headers at low zoom.
  '.dc-header{width:calc((100% + 4px) / var(--dc-inv-zoom,1));', '  transform:scale(var(--dc-inv-zoom,1));transform-origin:bottom left}', '.dc-sectionhead{zoom:var(--dc-inv-zoom,1)}'].join('\n');
  document.head.appendChild(s);
}
const DCCtx = React.createContext(null);

// Recursively unwrap React.Fragment so <>…</> grouping doesn't hide
// DCSection/DCArtboard children from the type-based walks below.
function dcFlatten(children) {
  const out = [];
  React.Children.forEach(children, c => {
    if (c && c.type === React.Fragment) out.push(...dcFlatten(c.props.children));else out.push(c);
  });
  return out;
}

// ─────────────────────────────────────────────────────────────
// DesignCanvas — stateful wrapper around the pan/zoom viewport.
// Owns runtime state (per-section order, renamed titles/labels, hidden
// artboards, focused artboard). Order/titles/labels/hidden persist to a
// .design-canvas.state.json
// sidecar next to the HTML. Reads go via plain fetch() so the saved
// arrangement is visible anywhere the HTML + sidecar are served together
// (omelette preview, direct link, downloaded zip). Writes go through the
// host's window.omelette bridge — editing requires the omelette runtime.
// Focus is ephemeral.
// ─────────────────────────────────────────────────────────────
const DC_STATE_FILE = '.design-canvas.state.json';
function DesignCanvas({
  children,
  minScale,
  maxScale,
  style
}) {
  const [state, setState] = React.useState({
    sections: {},
    focus: null
  });
  // Hold rendering until the sidecar read settles so the saved order/titles
  // appear on first paint (no source-order flash). didRead gates writes until
  // the read settles so the empty initial state can't clobber a slow read;
  // skipNextWrite suppresses the one echo-write that would otherwise follow
  // hydration.
  const [ready, setReady] = React.useState(false);
  const didRead = React.useRef(false);
  const skipNextWrite = React.useRef(false);
  React.useEffect(() => {
    let off = false;
    fetch('./' + DC_STATE_FILE).then(r => r.ok ? r.json() : null).then(saved => {
      if (off || !saved || !saved.sections) return;
      skipNextWrite.current = true;
      setState(s => ({
        ...s,
        sections: saved.sections
      }));
    }).catch(() => {}).finally(() => {
      didRead.current = true;
      if (!off) setReady(true);
    });
    const t = setTimeout(() => {
      if (!off) setReady(true);
    }, 150);
    return () => {
      off = true;
      clearTimeout(t);
    };
  }, []);
  React.useEffect(() => {
    if (!didRead.current) return;
    if (skipNextWrite.current) {
      skipNextWrite.current = false;
      return;
    }
    const t = setTimeout(() => {
      window.omelette?.writeFile(DC_STATE_FILE, JSON.stringify({
        sections: state.sections
      })).catch(() => {});
    }, 250);
    return () => clearTimeout(t);
  }, [state.sections]);

  // Build registries synchronously from children so FocusOverlay can read
  // them in the same render. Fragments are flattened; wrapping in other
  // elements still opts out of focus/reorder.
  const registry = {}; // slotId -> { sectionId, artboard }
  const sectionMeta = {}; // sectionId -> { title, subtitle, slotIds[] }
  const sectionOrder = [];
  dcFlatten(children).forEach(sec => {
    if (!sec || sec.type !== DCSection) return;
    const sid = sec.props.id ?? sec.props.title;
    if (!sid) return;
    sectionOrder.push(sid);
    const persisted = state.sections[sid] || {};
    const abs = [];
    dcFlatten(sec.props.children).forEach(ab => {
      if (!ab || ab.type !== DCArtboard) return;
      const aid = ab.props.id ?? ab.props.label;
      if (aid) abs.push([aid, ab]);
    });
    // hidden is scoped to one source revision — when the agent regenerates
    // (artboard-ID set changes), prior deletes don't apply to new content.
    const srcKey = abs.map(([k]) => k).join('\x1f');
    const hidden = persisted.srcKey === srcKey ? persisted.hidden || [] : [];
    const srcIds = [];
    abs.forEach(([aid, ab]) => {
      if (hidden.includes(aid)) return;
      registry[`${sid}/${aid}`] = {
        sectionId: sid,
        artboard: ab
      };
      srcIds.push(aid);
    });
    const kept = (persisted.order || []).filter(k => srcIds.includes(k));
    sectionMeta[sid] = {
      title: persisted.title ?? sec.props.title,
      subtitle: sec.props.subtitle,
      slotIds: [...kept, ...srcIds.filter(k => !kept.includes(k))]
    };
  });
  const api = React.useMemo(() => ({
    state,
    section: id => state.sections[id] || {},
    patchSection: (id, p) => setState(s => ({
      ...s,
      sections: {
        ...s.sections,
        [id]: {
          ...s.sections[id],
          ...(typeof p === 'function' ? p(s.sections[id] || {}) : p)
        }
      }
    })),
    setFocus: slotId => setState(s => ({
      ...s,
      focus: slotId
    }))
  }), [state]);

  // Esc exits focus; any outside pointerdown commits an in-progress rename.
  React.useEffect(() => {
    const onKey = e => {
      if (e.key === 'Escape') api.setFocus(null);
    };
    const onPd = e => {
      const ae = document.activeElement;
      if (ae && ae.isContentEditable && !ae.contains(e.target)) ae.blur();
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onPd, true);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('pointerdown', onPd, true);
    };
  }, [api]);
  return /*#__PURE__*/React.createElement(DCCtx.Provider, {
    value: api
  }, /*#__PURE__*/React.createElement(DCViewport, {
    minScale: minScale,
    maxScale: maxScale,
    style: style
  }, ready && children), state.focus && registry[state.focus] && /*#__PURE__*/React.createElement(DCFocusOverlay, {
    entry: registry[state.focus],
    sectionMeta: sectionMeta,
    sectionOrder: sectionOrder
  }));
}

// ─────────────────────────────────────────────────────────────
// DCViewport — transform-based pan/zoom (internal)
//
// Input mapping (Figma-style):
//   • trackpad pinch  → zoom   (ctrlKey wheel; Safari gesture* events)
//   • trackpad scroll → pan    (two-finger)
//   • mouse wheel     → zoom   (notched; distinguished from trackpad scroll)
//   • middle-drag / primary-drag-on-bg → pan
//
// Transform state lives in a ref and is written straight to the DOM
// (translate3d + will-change) so wheel ticks don't go through React —
// keeps pans at 60fps on dense canvases.
// ─────────────────────────────────────────────────────────────
function DCViewport({
  children,
  minScale = 0.1,
  maxScale = 8,
  style = {}
}) {
  const vpRef = React.useRef(null);
  const worldRef = React.useRef(null);
  const tf = React.useRef({
    x: 0,
    y: 0,
    scale: 1
  });
  // Persist viewport across reloads so the user lands back where they were
  // after an agent edit or browser refresh. The sandbox origin is already
  // per-project; pathname keeps multiple canvas files in one project apart.
  const tfKey = 'dc-viewport:' + location.pathname;
  const saveT = React.useRef(0);
  const lastPostedScale = React.useRef();
  const apply = React.useCallback(() => {
    const {
      x,
      y,
      scale
    } = tf.current;
    const el = worldRef.current;
    if (!el) return;
    el.style.transform = `translate3d(${x}px, ${y}px, 0) scale(${scale})`;
    // Exposed for zoom-invariant chrome (labels, buttons, TweaksPanel).
    el.style.setProperty('--dc-inv-zoom', String(1 / scale));
    // Keep the host toolbar's % readout in sync with the canvas scale. Pan
    // ticks leave scale unchanged — skip the cross-frame post for those.
    if (lastPostedScale.current !== scale) {
      lastPostedScale.current = scale;
      window.parent.postMessage({
        type: '__dc_zoom',
        scale
      }, '*');
    }
    clearTimeout(saveT.current);
    saveT.current = setTimeout(() => {
      try {
        localStorage.setItem(tfKey, JSON.stringify(tf.current));
      } catch {}
    }, 200);
  }, [tfKey]);
  React.useLayoutEffect(() => {
    const flush = () => {
      clearTimeout(saveT.current);
      try {
        localStorage.setItem(tfKey, JSON.stringify(tf.current));
      } catch {}
    };
    try {
      const s = JSON.parse(localStorage.getItem(tfKey) || 'null');
      if (s && Number.isFinite(s.x) && Number.isFinite(s.y) && Number.isFinite(s.scale)) {
        tf.current = {
          x: s.x,
          y: s.y,
          scale: Math.min(maxScale, Math.max(minScale, s.scale))
        };
        apply();
      }
    } catch {}
    // Flush on pagehide and unmount so a reload within the 200ms debounce
    // window doesn't drop the last pan/zoom.
    window.addEventListener('pagehide', flush);
    return () => {
      window.removeEventListener('pagehide', flush);
      flush();
    };
  }, []);
  React.useEffect(() => {
    const vp = vpRef.current;
    if (!vp) return;
    const zoomAt = (cx, cy, factor) => {
      const r = vp.getBoundingClientRect();
      const px = cx - r.left,
        py = cy - r.top;
      const t = tf.current;
      const next = Math.min(maxScale, Math.max(minScale, t.scale * factor));
      const k = next / t.scale;
      // --dc-inv-zoom consumers (.dc-sectionhead's CSS zoom, each section's
      // marginBottom) reflow on every scale change, vertically shifting the
      // world layout — so a world point mathematically pinned under the cursor
      // drifts as you zoom (content creeps up on zoom-in, down on zoom-out).
      // Anchor the DOM element under the cursor instead: record its screen Y,
      // apply the transform + --dc-inv-zoom, then cancel whatever vertical
      // drift the reflow introduced so it stays put on screen.
      let marker = null,
        markerY0 = 0;
      if (k !== 1) {
        const hit = document.elementFromPoint(cx, cy);
        marker = hit && hit.closest ? hit.closest('[data-dc-slot],[data-dc-section]') : null;
        if (marker) markerY0 = marker.getBoundingClientRect().top;
      }
      // keep the world point under the cursor fixed
      t.x = px - (px - t.x) * k;
      t.y = py - (py - t.y) * k;
      t.scale = next;
      apply();
      if (marker) {
        // A pure zoom around (cx, cy) maps screen Y → cy + (Y - cy) * k. Any
        // departure after the --dc-inv-zoom reflow is the layout drift.
        const drift = marker.getBoundingClientRect().top - (cy + (markerY0 - cy) * k);
        if (Math.abs(drift) > 0.1) {
          t.y -= drift;
          apply();
        }
      }
    };

    // Mouse-wheel vs trackpad-scroll heuristic. A physical wheel sends
    // line-mode deltas (Firefox) or large integer pixel deltas with no X
    // component (Chrome/Safari, typically multiples of 100/120). Trackpad
    // two-finger scroll sends small/fractional pixel deltas, often with
    // non-zero deltaX. ctrlKey is set by the browser for trackpad pinch.
    const isMouseWheel = e => e.deltaMode !== 0 || e.deltaX === 0 && Number.isInteger(e.deltaY) && Math.abs(e.deltaY) >= 40;
    const onWheel = e => {
      e.preventDefault();
      if (isGesturing) return; // Safari: gesture* owns the pinch — discard concurrent wheels
      if ((e.ctrlKey || e.metaKey) && !isMouseWheel(e)) {
        // trackpad pinch, or ctrl/cmd + smooth-scroll mouse. Notched
        // wheels fall through to the fixed-step branch below.
        zoomAt(e.clientX, e.clientY, Math.exp(-e.deltaY * 0.01));
      } else if (isMouseWheel(e)) {
        // notched mouse wheel — fixed-ratio step per click
        zoomAt(e.clientX, e.clientY, Math.exp(-Math.sign(e.deltaY) * 0.18));
      } else {
        // trackpad two-finger scroll — pan
        tf.current.x -= e.deltaX;
        tf.current.y -= e.deltaY;
        apply();
      }
    };

    // Safari sends native gesture* events for trackpad pinch with a smooth
    // e.scale; preferring these over the ctrl+wheel fallback gives a much
    // better feel there. No-ops on other browsers. Safari also fires
    // ctrlKey wheel events during the same pinch — isGesturing makes
    // onWheel drop those entirely so they neither zoom nor pan.
    let gsBase = 1;
    let isGesturing = false;
    const onGestureStart = e => {
      e.preventDefault();
      isGesturing = true;
      gsBase = tf.current.scale;
    };
    const onGestureChange = e => {
      e.preventDefault();
      zoomAt(e.clientX, e.clientY, gsBase * e.scale / tf.current.scale);
    };
    const onGestureEnd = e => {
      e.preventDefault();
      isGesturing = false;
    };

    // Drag-pan: middle button anywhere, or primary button on canvas
    // background (anything that isn't an artboard or an inline editor).
    let drag = null;
    const onPointerDown = e => {
      const onBg = !e.target.closest('[data-dc-slot], .dc-editable');
      if (!(e.button === 1 || e.button === 0 && onBg)) return;
      e.preventDefault();
      vp.setPointerCapture(e.pointerId);
      drag = {
        id: e.pointerId,
        lx: e.clientX,
        ly: e.clientY
      };
      vp.style.cursor = 'grabbing';
    };
    const onPointerMove = e => {
      if (!drag || e.pointerId !== drag.id) return;
      tf.current.x += e.clientX - drag.lx;
      tf.current.y += e.clientY - drag.ly;
      drag.lx = e.clientX;
      drag.ly = e.clientY;
      apply();
    };
    const onPointerUp = e => {
      if (!drag || e.pointerId !== drag.id) return;
      vp.releasePointerCapture(e.pointerId);
      drag = null;
      vp.style.cursor = '';
    };

    // Host-driven zoom (toolbar % menu). Zooms around viewport centre so the
    // visible midpoint stays fixed — matching the host's iframe-zoom feel.
    const onHostMsg = e => {
      const d = e.data;
      if (d && d.type === '__dc_set_zoom' && typeof d.scale === 'number') {
        const r = vp.getBoundingClientRect();
        zoomAt(r.left + r.width / 2, r.top + r.height / 2, d.scale / tf.current.scale);
      } else if (d && d.type === '__dc_probe') {
        // Host's [readyGen] reset asks whether a canvas is present; it
        // fires on the iframe's native 'load', which for canvases with
        // images/fonts is after our mount-time announce, so re-announce.
        // Clear the pan-tick guard so apply() re-posts the current scale
        // even if it's unchanged — the host just reset dcScale to 1.
        window.parent.postMessage({
          type: '__dc_present'
        }, '*');
        lastPostedScale.current = undefined;
        apply();
      }
    };
    window.addEventListener('message', onHostMsg);
    // Announce canvas mode so the host toolbar proxies its % control here
    // instead of scaling the iframe element (which would just shrink the
    // viewport window of an infinite canvas). The apply() that follows emits
    // the initial __dc_zoom so the toolbar % is correct before first pinch.
    // lastPostedScale reset mirrors the __dc_probe handler: the layout
    // effect's restore-path apply() may already have posted the restored
    // scale (before __dc_present), so clear the guard to re-post it in order.
    window.parent.postMessage({
      type: '__dc_present'
    }, '*');
    lastPostedScale.current = undefined;
    apply();
    vp.addEventListener('wheel', onWheel, {
      passive: false
    });
    vp.addEventListener('gesturestart', onGestureStart, {
      passive: false
    });
    vp.addEventListener('gesturechange', onGestureChange, {
      passive: false
    });
    vp.addEventListener('gestureend', onGestureEnd, {
      passive: false
    });
    vp.addEventListener('pointerdown', onPointerDown);
    vp.addEventListener('pointermove', onPointerMove);
    vp.addEventListener('pointerup', onPointerUp);
    vp.addEventListener('pointercancel', onPointerUp);
    return () => {
      window.removeEventListener('message', onHostMsg);
      vp.removeEventListener('wheel', onWheel);
      vp.removeEventListener('gesturestart', onGestureStart);
      vp.removeEventListener('gesturechange', onGestureChange);
      vp.removeEventListener('gestureend', onGestureEnd);
      vp.removeEventListener('pointerdown', onPointerDown);
      vp.removeEventListener('pointermove', onPointerMove);
      vp.removeEventListener('pointerup', onPointerUp);
      vp.removeEventListener('pointercancel', onPointerUp);
    };
  }, [apply, minScale, maxScale]);
  const gridSvg = `url("data:image/svg+xml,%3Csvg width='120' height='120' xmlns='http://www.w3.org/2000/svg'%3E%3Cpath d='M120 0H0v120' fill='none' stroke='${encodeURIComponent(DC.grid)}' stroke-width='1'/%3E%3C/svg%3E")`;
  return /*#__PURE__*/React.createElement("div", {
    ref: vpRef,
    className: "design-canvas",
    style: {
      height: '100vh',
      width: '100vw',
      background: DC.bg,
      overflow: 'hidden',
      overscrollBehavior: 'none',
      touchAction: 'none',
      position: 'relative',
      fontFamily: DC.font,
      boxSizing: 'border-box',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    ref: worldRef,
    style: {
      position: 'absolute',
      top: 0,
      left: 0,
      transformOrigin: '0 0',
      willChange: 'transform',
      width: 'max-content',
      minWidth: '100%',
      minHeight: '100%',
      padding: '60px 0 80px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      inset: -6000,
      backgroundImage: gridSvg,
      backgroundSize: '120px 120px',
      pointerEvents: 'none',
      zIndex: -1
    }
  }), children));
}

// ─────────────────────────────────────────────────────────────
// DCSection — editable title + h-row of artboards in persisted order
// ─────────────────────────────────────────────────────────────
function DCSection({
  id,
  title,
  subtitle,
  children,
  gap = 48
}) {
  const ctx = React.useContext(DCCtx);
  const sid = id ?? title;
  const all = React.Children.toArray(dcFlatten(children));
  const artboards = all.filter(c => c && c.type === DCArtboard);
  const rest = all.filter(c => !(c && c.type === DCArtboard));
  const sec = ctx && sid && ctx.section(sid) || {};
  // Must match DesignCanvas's srcKey computation exactly (it filters falsy
  // IDs), or onDelete persists a srcKey that DesignCanvas never recognizes.
  const allIds = artboards.map(a => a.props.id ?? a.props.label).filter(Boolean);
  const srcKey = allIds.join('\x1f');
  const hidden = sec.srcKey === srcKey ? sec.hidden || [] : [];
  const srcOrder = allIds.filter(k => !hidden.includes(k));
  const order = React.useMemo(() => {
    const kept = (sec.order || []).filter(k => srcOrder.includes(k));
    return [...kept, ...srcOrder.filter(k => !kept.includes(k))];
  }, [sec.order, srcOrder.join('|')]);
  const byId = Object.fromEntries(artboards.map(a => [a.props.id ?? a.props.label, a]));

  // marginBottom counter-scales so the on-screen gap between sections stays
  // constant — otherwise at low zoom the (world-space) gap collapses while
  // the screen-constant sectionhead below it doesn't, and the title reads as
  // belonging to the section above. paddingBottom below is just enough for
  // the 24px artboard-header (abs-positioned above each card) plus ~8px, so
  // the title sits tight against its own row at every zoom.
  return /*#__PURE__*/React.createElement("div", {
    "data-dc-section": sid,
    style: {
      marginBottom: 'calc(80px * var(--dc-inv-zoom, 1))',
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 60px'
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "dc-sectionhead",
    style: {
      paddingBottom: 36
    }
  }, /*#__PURE__*/React.createElement(DCEditable, {
    tag: "div",
    value: sec.title ?? title,
    onChange: v => ctx && sid && ctx.patchSection(sid, {
      title: v
    }),
    style: {
      fontSize: 28,
      fontWeight: 600,
      color: DC.title,
      letterSpacing: -0.4,
      marginBottom: 6,
      display: 'inline-block'
    }
  }), subtitle && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 16,
      color: DC.subtitle
    }
  }, subtitle))), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap,
      padding: '0 60px',
      alignItems: 'flex-start',
      width: 'max-content'
    }
  }, order.map(k => /*#__PURE__*/React.createElement(DCArtboardFrame, {
    key: k,
    sectionId: sid,
    artboard: byId[k],
    order: order,
    label: (sec.labels || {})[k] ?? byId[k].props.label,
    onRename: v => ctx && ctx.patchSection(sid, x => ({
      labels: {
        ...x.labels,
        [k]: v
      }
    })),
    onReorder: next => ctx && ctx.patchSection(sid, {
      order: next
    }),
    onDelete: () => ctx && ctx.patchSection(sid, x => ({
      hidden: [...(x.srcKey === srcKey ? x.hidden || [] : []), k],
      srcKey
    })),
    onFocus: () => ctx && ctx.setFocus(`${sid}/${k}`)
  }))), rest);
}

// DCArtboard — marker; rendered by DCArtboardFrame via DCSection.
function DCArtboard() {
  return null;
}

// Per-artboard export (kind: 'png' | 'html'). Both paths share the same
// self-contained clone: computed styles baked in, @font-face / <img> /
// inline-style background-image urls inlined as data URIs. PNG wraps the
// clone in foreignObject→canvas at 3× the artboard's natural width×height
// (same pipeline the host uses for page captures); HTML wraps it in a
// minimal standalone document. Both are independent of viewport zoom.
async function dcExport(node, w, h, name, kind) {
  try {
    await document.fonts.ready;
  } catch {}
  const toDataURL = url => fetch(url).then(r => r.blob()).then(b => new Promise(res => {
    const fr = new FileReader();
    fr.onload = () => res(fr.result);
    fr.onerror = () => res(url);
    fr.readAsDataURL(b);
  })).catch(() => url);

  // Collect @font-face rules. ss.cssRules throws SecurityError on
  // cross-origin sheets (e.g. fonts.googleapis.com) — in that case fetch
  // the CSS text directly (those endpoints send ACAO:*) and regex-extract
  // the blocks. @import and @media/@supports are walked so nested
  // @font-face rules aren't missed.
  const fontRules = [],
    pending = [],
    seen = new Set();
  const scrapeCss = href => {
    if (seen.has(href)) return;
    seen.add(href);
    pending.push(fetch(href).then(r => r.text()).then(css => {
      for (const m of css.match(/@font-face\s*{[^}]*}/g) || []) fontRules.push({
        css: m,
        base: href
      });
      for (const m of css.matchAll(/@import\s+(?:url\()?['"]?([^'")\s;]+)/g)) scrapeCss(new URL(m[1], href).href);
    }).catch(() => {}));
  };
  const walk = (rules, base) => {
    for (const r of rules) {
      if (r.type === CSSRule.FONT_FACE_RULE) fontRules.push({
        css: r.cssText,
        base
      });else if (r.type === CSSRule.IMPORT_RULE && r.styleSheet) {
        const ibase = r.styleSheet.href || base;
        try {
          walk(r.styleSheet.cssRules, ibase);
        } catch {
          scrapeCss(ibase);
        }
      } else if (r.cssRules) walk(r.cssRules, base);
    }
  };
  for (const ss of document.styleSheets) {
    const base = ss.href || location.href;
    try {
      walk(ss.cssRules, base);
    } catch {
      if (ss.href) scrapeCss(ss.href);
    }
  }
  while (pending.length) await pending.shift();
  const fontCss = (await Promise.all(fontRules.map(async rule => {
    let out = rule.css,
      m;
    const re = /url\((['"]?)([^'")]+)\1\)/g;
    while (m = re.exec(rule.css)) {
      if (m[2].indexOf('data:') === 0) continue;
      let abs;
      try {
        abs = new URL(m[2], rule.base).href;
      } catch {
        continue;
      }
      out = out.split(m[0]).join('url("' + (await toDataURL(abs)) + '")');
    }
    return out;
  }))).join('\n');
  const cloneStyled = src => {
    if (src.nodeType === 8 || src.nodeType === 1 && src.tagName === 'SCRIPT') return document.createTextNode('');
    const dst = src.cloneNode(false);
    if (src.nodeType === 1) {
      const cs = getComputedStyle(src);
      let txt = '';
      for (let i = 0; i < cs.length; i++) txt += cs[i] + ':' + cs.getPropertyValue(cs[i]) + ';';
      dst.setAttribute('style', txt + 'animation:none;transition:none;');
      if (src.tagName === 'CANVAS') try {
        const im = document.createElement('img');
        im.src = src.toDataURL();
        im.setAttribute('style', txt);
        return im;
      } catch {}
    }
    for (let c = src.firstChild; c; c = c.nextSibling) dst.appendChild(cloneStyled(c));
    return dst;
  };
  const clone = cloneStyled(node);
  clone.setAttribute('xmlns', 'http://www.w3.org/1999/xhtml');
  // Drop the card's own shadow/radius so the export is a flush w×h rect;
  // the artboard's own background (if any) is already in the computed style.
  clone.style.boxShadow = 'none';
  clone.style.borderRadius = '0';
  const jobs = [];
  clone.querySelectorAll('img').forEach(el => {
    const s = el.getAttribute('src');
    if (s && s.indexOf('data:') !== 0) jobs.push(toDataURL(el.src).then(d => el.setAttribute('src', d)));
  });
  [clone, ...clone.querySelectorAll('*')].forEach(el => {
    const bg = el.style.backgroundImage;
    if (!bg) return;
    let m;
    const re = /url\(["']?([^"')]+)["']?\)/g;
    while (m = re.exec(bg)) {
      const tok = m[0],
        url = m[1];
      if (url.indexOf('data:') === 0) continue;
      jobs.push(toDataURL(url).then(d => {
        el.style.backgroundImage = el.style.backgroundImage.split(tok).join('url("' + d + '")');
      }));
    }
  });
  await Promise.all(jobs);
  const xml = new XMLSerializer().serializeToString(clone);
  const save = (blob, ext) => {
    if (!blob) return;
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name + '.' + ext;
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  };
  if (kind === 'html') {
    const html = '<!doctype html><html><head><meta charset="utf-8"><title>' + name + '</title>' + (fontCss ? '<style>' + fontCss + '</style>' : '') + '</head><body style="margin:0">' + xml + '</body></html>';
    return save(new Blob([html], {
      type: 'text/html'
    }), 'html');
  }

  // PNG: the SVG's own width/height must be the output resolution — an
  // <img>-loaded SVG rasterizes at its intrinsic size, so sizing it at 1×
  // and ctx.scale()-ing up would just upscale a 1× bitmap. viewBox maps the
  // w×h foreignObject onto the px·w × px·h SVG canvas so the browser renders
  // the HTML at full resolution.
  const px = 3;
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w * px + '" height="' + h * px + '" viewBox="0 0 ' + w + ' ' + h + '"><foreignObject width="' + w + '" height="' + h + '">' + (fontCss ? '<style><![CDATA[' + fontCss + ']]></style>' : '') + xml + '</foreignObject></svg>';
  const img = new Image();
  await new Promise((res, rej) => {
    img.onload = res;
    img.onerror = () => rej(new Error('svg load failed'));
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg);
  });
  const cv = document.createElement('canvas');
  cv.width = w * px;
  cv.height = h * px;
  cv.getContext('2d').drawImage(img, 0, 0);
  cv.toBlob(blob => save(blob, 'png'), 'image/png');
}
function DCArtboardFrame({
  sectionId,
  artboard,
  label,
  order,
  onRename,
  onReorder,
  onFocus,
  onDelete
}) {
  const {
    id: rawId,
    label: rawLabel,
    width = 260,
    height = 480,
    children,
    style = {}
  } = artboard.props;
  const id = rawId ?? rawLabel;
  const ref = React.useRef(null);
  const cardRef = React.useRef(null);
  const menuRef = React.useRef(null);
  const [menuOpen, setMenuOpen] = React.useState(false);
  const [confirming, setConfirming] = React.useState(false);

  // ⋯ menu: close on any outside pointerdown. Two-click delete lives inside
  // the menu — first click arms the row, second commits; closing disarms.
  React.useEffect(() => {
    if (!menuOpen) {
      setConfirming(false);
      return;
    }
    const off = e => {
      if (!menuRef.current || !menuRef.current.contains(e.target)) setMenuOpen(false);
    };
    document.addEventListener('pointerdown', off, true);
    return () => document.removeEventListener('pointerdown', off, true);
  }, [menuOpen]);
  const doExport = kind => {
    setMenuOpen(false);
    if (!cardRef.current) return;
    const name = String(label || id || 'artboard').replace(/[^\w\s.-]+/g, '_');
    dcExport(cardRef.current, width, height, name, kind).catch(e => console.error('[design-canvas] export failed:', e));
  };

  // Live drag-reorder: dragged card sticks to cursor; siblings slide into
  // their would-be slots in real time via transforms. DOM order only
  // changes on drop.
  const onGripDown = e => {
    e.preventDefault();
    e.stopPropagation();
    const me = ref.current;
    // translateX is applied in local (pre-scale) space but pointer deltas and
    // getBoundingClientRect().left are screen-space — divide by the viewport's
    // current scale so the dragged card tracks the cursor at any zoom level.
    const scale = me.getBoundingClientRect().width / me.offsetWidth || 1;
    const peers = Array.from(document.querySelectorAll(`[data-dc-section="${sectionId}"] [data-dc-slot]`));
    const homes = peers.map(el => ({
      el,
      id: el.dataset.dcSlot,
      x: el.getBoundingClientRect().left
    }));
    const slotXs = homes.map(h => h.x);
    const startIdx = order.indexOf(id);
    const startX = e.clientX;
    let liveOrder = order.slice();
    me.classList.add('dc-dragging');
    const layout = () => {
      for (const h of homes) {
        if (h.id === id) continue;
        const slot = liveOrder.indexOf(h.id);
        h.el.style.transform = `translateX(${(slotXs[slot] - h.x) / scale}px)`;
      }
    };
    const move = ev => {
      const dx = ev.clientX - startX;
      me.style.transform = `translateX(${dx / scale}px)`;
      const cur = homes[startIdx].x + dx;
      let nearest = 0,
        best = Infinity;
      for (let i = 0; i < slotXs.length; i++) {
        const d = Math.abs(slotXs[i] - cur);
        if (d < best) {
          best = d;
          nearest = i;
        }
      }
      if (liveOrder.indexOf(id) !== nearest) {
        liveOrder = order.filter(k => k !== id);
        liveOrder.splice(nearest, 0, id);
        layout();
      }
    };
    const up = () => {
      document.removeEventListener('pointermove', move);
      document.removeEventListener('pointerup', up);
      const finalSlot = liveOrder.indexOf(id);
      me.classList.remove('dc-dragging');
      me.style.transform = `translateX(${(slotXs[finalSlot] - homes[startIdx].x) / scale}px)`;
      // After the settle transition, kill transitions + clear transforms +
      // commit the reorder in the same frame so there's no visual snap-back.
      setTimeout(() => {
        for (const h of homes) {
          h.el.style.transition = 'none';
          h.el.style.transform = '';
        }
        if (liveOrder.join('|') !== order.join('|')) onReorder(liveOrder);
        requestAnimationFrame(() => requestAnimationFrame(() => {
          for (const h of homes) h.el.style.transition = '';
        }));
      }, 180);
    };
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', up);
  };
  return /*#__PURE__*/React.createElement("div", {
    ref: ref,
    "data-dc-slot": id,
    style: {
      position: 'relative',
      flexShrink: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "dc-header",
    "data-omelette-chrome": "",
    style: {
      color: DC.label
    },
    onPointerDown: e => e.stopPropagation()
  }, /*#__PURE__*/React.createElement("div", {
    className: "dc-labelrow"
  }, /*#__PURE__*/React.createElement("div", {
    className: "dc-grip",
    onPointerDown: onGripDown,
    title: "Drag to reorder"
  }, /*#__PURE__*/React.createElement("svg", {
    width: "9",
    height: "13",
    viewBox: "0 0 9 13",
    fill: "currentColor"
  }, /*#__PURE__*/React.createElement("circle", {
    cx: "2",
    cy: "2",
    r: "1.1"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "7",
    cy: "2",
    r: "1.1"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "2",
    cy: "6.5",
    r: "1.1"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "7",
    cy: "6.5",
    r: "1.1"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "2",
    cy: "11",
    r: "1.1"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "7",
    cy: "11",
    r: "1.1"
  }))), /*#__PURE__*/React.createElement("div", {
    className: "dc-labeltext",
    onClick: onFocus,
    title: "Click to focus"
  }, /*#__PURE__*/React.createElement(DCEditable, {
    value: label,
    onChange: onRename,
    onClick: e => e.stopPropagation(),
    style: {
      fontSize: 15,
      fontWeight: 500,
      color: DC.label,
      lineHeight: 1
    }
  }))), /*#__PURE__*/React.createElement("div", {
    className: "dc-btns"
  }, /*#__PURE__*/React.createElement("div", {
    ref: menuRef,
    style: {
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("button", {
    className: "dc-kebab",
    title: "More",
    onClick: () => setMenuOpen(o => !o)
  }, /*#__PURE__*/React.createElement("svg", {
    width: "12",
    height: "12",
    viewBox: "0 0 12 12",
    fill: "currentColor"
  }, /*#__PURE__*/React.createElement("circle", {
    cx: "2.5",
    cy: "6",
    r: "1.1"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "6",
    cy: "6",
    r: "1.1"
  }), /*#__PURE__*/React.createElement("circle", {
    cx: "9.5",
    cy: "6",
    r: "1.1"
  }))), menuOpen && /*#__PURE__*/React.createElement("div", {
    className: "dc-menu",
    onPointerDown: e => e.stopPropagation()
  }, /*#__PURE__*/React.createElement("button", {
    onClick: () => doExport('png')
  }, "Download PNG"), /*#__PURE__*/React.createElement("button", {
    onClick: () => doExport('html')
  }, "Download HTML"), /*#__PURE__*/React.createElement("hr", null), /*#__PURE__*/React.createElement("button", {
    className: "dc-danger",
    onClick: () => {
      if (confirming) {
        setMenuOpen(false);
        onDelete();
      } else setConfirming(true);
    }
  }, confirming ? 'Click again to delete' : 'Delete'))), /*#__PURE__*/React.createElement("button", {
    className: "dc-expand",
    onClick: onFocus,
    title: "Focus"
  }, /*#__PURE__*/React.createElement("svg", {
    width: "12",
    height: "12",
    viewBox: "0 0 12 12",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "1.6",
    strokeLinecap: "round"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M7 1h4v4M5 11H1V7M11 1L7.5 4.5M1 11l3.5-3.5"
  }))))), /*#__PURE__*/React.createElement("div", {
    ref: cardRef,
    className: "dc-card",
    style: {
      borderRadius: 2,
      boxShadow: '0 1px 3px rgba(0,0,0,.08),0 4px 16px rgba(0,0,0,.06)',
      overflow: 'hidden',
      width,
      height,
      background: '#fff',
      ...style
    }
  }, children || /*#__PURE__*/React.createElement("div", {
    style: {
      height: '100%',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: '#bbb',
      fontSize: 13,
      fontFamily: DC.font
    }
  }, id)));
}

// Inline rename — commits on blur or Enter.
function DCEditable({
  value,
  onChange,
  style,
  tag = 'span',
  onClick
}) {
  const T = tag;
  return /*#__PURE__*/React.createElement(T, {
    className: "dc-editable",
    contentEditable: true,
    suppressContentEditableWarning: true,
    onClick: onClick,
    onPointerDown: e => e.stopPropagation(),
    onBlur: e => onChange && onChange(e.currentTarget.textContent),
    onKeyDown: e => {
      if (e.key === 'Enter') {
        e.preventDefault();
        e.currentTarget.blur();
      }
    },
    style: style
  }, value);
}

// ─────────────────────────────────────────────────────────────
// Focus mode — overlay one artboard; ←/→ within section, ↑/↓ across
// sections, Esc or backdrop click to exit.
// ─────────────────────────────────────────────────────────────
function DCFocusOverlay({
  entry,
  sectionMeta,
  sectionOrder
}) {
  const ctx = React.useContext(DCCtx);
  const {
    sectionId,
    artboard
  } = entry;
  const sec = ctx.section(sectionId);
  const meta = sectionMeta[sectionId];
  const peers = meta.slotIds;
  const aid = artboard.props.id ?? artboard.props.label;
  const idx = peers.indexOf(aid);
  const secIdx = sectionOrder.indexOf(sectionId);
  const go = d => {
    const n = peers[(idx + d + peers.length) % peers.length];
    if (n) ctx.setFocus(`${sectionId}/${n}`);
  };
  const goSection = d => {
    // Sections whose artboards are all deleted have slotIds:[] — step past
    // them to the next non-empty section so ↑/↓ doesn't dead-end.
    const n = sectionOrder.length;
    for (let i = 1; i < n; i++) {
      const ns = sectionOrder[((secIdx + d * i) % n + n) % n];
      const first = sectionMeta[ns] && sectionMeta[ns].slotIds[0];
      if (first) {
        ctx.setFocus(`${ns}/${first}`);
        return;
      }
    }
  };
  React.useEffect(() => {
    const k = e => {
      if (e.key === 'ArrowLeft') {
        e.preventDefault();
        go(-1);
      }
      if (e.key === 'ArrowRight') {
        e.preventDefault();
        go(1);
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault();
        goSection(-1);
      }
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        goSection(1);
      }
    };
    document.addEventListener('keydown', k);
    return () => document.removeEventListener('keydown', k);
  });
  const {
    width = 260,
    height = 480,
    children
  } = artboard.props;
  const [vp, setVp] = React.useState({
    w: window.innerWidth,
    h: window.innerHeight
  });
  React.useEffect(() => {
    const r = () => setVp({
      w: window.innerWidth,
      h: window.innerHeight
    });
    window.addEventListener('resize', r);
    return () => window.removeEventListener('resize', r);
  }, []);
  const scale = Math.max(0.1, Math.min((vp.w - 200) / width, (vp.h - 260) / height, 2));
  const [ddOpen, setDd] = React.useState(false);
  const Arrow = ({
    dir,
    onClick
  }) => /*#__PURE__*/React.createElement("button", {
    onClick: e => {
      e.stopPropagation();
      onClick();
    },
    style: {
      position: 'absolute',
      top: '50%',
      [dir]: 28,
      transform: 'translateY(-50%)',
      border: 'none',
      background: 'rgba(255,255,255,.08)',
      color: 'rgba(255,255,255,.9)',
      width: 44,
      height: 44,
      borderRadius: 22,
      fontSize: 18,
      cursor: 'pointer',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      transition: 'background .15s'
    },
    onMouseEnter: e => e.currentTarget.style.background = 'rgba(255,255,255,.18)',
    onMouseLeave: e => e.currentTarget.style.background = 'rgba(255,255,255,.08)'
  }, /*#__PURE__*/React.createElement("svg", {
    width: "18",
    height: "18",
    viewBox: "0 0 18 18",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "2",
    strokeLinecap: "round"
  }, /*#__PURE__*/React.createElement("path", {
    d: dir === 'left' ? 'M11 3L5 9l6 6' : 'M7 3l6 6-6 6'
  })));

  // Portal to body so position:fixed is the real viewport regardless of any
  // transform on DesignCanvas's ancestors (including the canvas zoom itself).
  return ReactDOM.createPortal(/*#__PURE__*/React.createElement("div", {
    onClick: () => ctx.setFocus(null),
    onWheel: e => e.preventDefault(),
    style: {
      position: 'fixed',
      inset: 0,
      zIndex: 100,
      background: 'rgba(24,20,16,.6)',
      backdropFilter: 'blur(14px)',
      fontFamily: DC.font,
      color: '#fff'
    }
  }, /*#__PURE__*/React.createElement("div", {
    onClick: e => e.stopPropagation(),
    style: {
      position: 'absolute',
      top: 0,
      left: 0,
      right: 0,
      height: 72,
      display: 'flex',
      alignItems: 'flex-start',
      padding: '16px 20px 0',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("button", {
    onClick: () => setDd(o => !o),
    style: {
      border: 'none',
      background: 'transparent',
      color: '#fff',
      cursor: 'pointer',
      padding: '6px 8px',
      borderRadius: 6,
      textAlign: 'left',
      fontFamily: 'inherit'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 8
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 18,
      fontWeight: 600,
      letterSpacing: -0.3
    }
  }, meta.title), /*#__PURE__*/React.createElement("svg", {
    width: "11",
    height: "11",
    viewBox: "0 0 11 11",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "1.8",
    strokeLinecap: "round",
    style: {
      opacity: .7
    }
  }, /*#__PURE__*/React.createElement("path", {
    d: "M2 4l3.5 3.5L9 4"
  }))), meta.subtitle && /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'block',
      fontSize: 13,
      opacity: .6,
      fontWeight: 400,
      marginTop: 2
    }
  }, meta.subtitle)), ddOpen && /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: '100%',
      left: 0,
      marginTop: 4,
      background: '#2a251f',
      borderRadius: 8,
      boxShadow: '0 8px 32px rgba(0,0,0,.4)',
      padding: 4,
      minWidth: 200,
      zIndex: 10
    }
  }, sectionOrder.filter(sid => sectionMeta[sid].slotIds.length).map(sid => /*#__PURE__*/React.createElement("button", {
    key: sid,
    onClick: () => {
      setDd(false);
      const f = sectionMeta[sid].slotIds[0];
      if (f) ctx.setFocus(`${sid}/${f}`);
    },
    style: {
      display: 'block',
      width: '100%',
      textAlign: 'left',
      border: 'none',
      cursor: 'pointer',
      background: sid === sectionId ? 'rgba(255,255,255,.1)' : 'transparent',
      color: '#fff',
      padding: '8px 12px',
      borderRadius: 5,
      fontSize: 14,
      fontWeight: sid === sectionId ? 600 : 400,
      fontFamily: 'inherit'
    }
  }, sectionMeta[sid].title)))), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1
    }
  }), /*#__PURE__*/React.createElement("button", {
    onClick: () => ctx.setFocus(null),
    onMouseEnter: e => e.currentTarget.style.background = 'rgba(255,255,255,.12)',
    onMouseLeave: e => e.currentTarget.style.background = 'transparent',
    style: {
      border: 'none',
      background: 'transparent',
      color: 'rgba(255,255,255,.7)',
      width: 32,
      height: 32,
      borderRadius: 16,
      fontSize: 20,
      cursor: 'pointer',
      lineHeight: 1,
      transition: 'background .12s'
    }
  }, "\xD7")), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top: 64,
      bottom: 56,
      left: 100,
      right: 100,
      display: 'flex',
      flexDirection: 'column',
      alignItems: 'center',
      justifyContent: 'center',
      gap: 16
    }
  }, /*#__PURE__*/React.createElement("div", {
    onClick: e => e.stopPropagation(),
    style: {
      width: width * scale,
      height: height * scale,
      position: 'relative'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width,
      height,
      transform: `scale(${scale})`,
      transformOrigin: 'top left',
      background: '#fff',
      borderRadius: 2,
      overflow: 'hidden',
      boxShadow: '0 20px 80px rgba(0,0,0,.4)'
    }
  }, children || /*#__PURE__*/React.createElement("div", {
    style: {
      height: '100%',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: '#bbb'
    }
  }, aid))), /*#__PURE__*/React.createElement("div", {
    onClick: e => e.stopPropagation(),
    style: {
      fontSize: 14,
      fontWeight: 500,
      opacity: .85,
      textAlign: 'center'
    }
  }, (sec.labels || {})[aid] ?? artboard.props.label, /*#__PURE__*/React.createElement("span", {
    style: {
      opacity: .5,
      marginLeft: 10,
      fontVariantNumeric: 'tabular-nums'
    }
  }, idx + 1, " / ", peers.length))), /*#__PURE__*/React.createElement(Arrow, {
    dir: "left",
    onClick: () => go(-1)
  }), /*#__PURE__*/React.createElement(Arrow, {
    dir: "right",
    onClick: () => go(1)
  }), /*#__PURE__*/React.createElement("div", {
    onClick: e => e.stopPropagation(),
    style: {
      position: 'absolute',
      bottom: 20,
      left: '50%',
      transform: 'translateX(-50%)',
      display: 'flex',
      gap: 8
    }
  }, peers.map((p, i) => /*#__PURE__*/React.createElement("button", {
    key: p,
    onClick: () => ctx.setFocus(`${sectionId}/${p}`),
    style: {
      border: 'none',
      padding: 0,
      cursor: 'pointer',
      width: 6,
      height: 6,
      borderRadius: 3,
      background: i === idx ? '#fff' : 'rgba(255,255,255,.3)'
    }
  })))), document.body);
}

// ─────────────────────────────────────────────────────────────
// Post-it — absolute-positioned sticky note
// ─────────────────────────────────────────────────────────────
function DCPostIt({
  children,
  top,
  left,
  right,
  bottom,
  rotate = -2,
  width = 180
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'absolute',
      top,
      left,
      right,
      bottom,
      width,
      background: DC.postitBg,
      padding: '14px 16px',
      fontFamily: '"Comic Sans MS", "Marker Felt", "Segoe Print", cursive',
      fontSize: 14,
      lineHeight: 1.4,
      color: DC.postitText,
      boxShadow: '0 2px 8px rgba(0,0,0,0.12), 0 1px 2px rgba(0,0,0,0.08)',
      transform: `rotate(${rotate}deg)`,
      zIndex: 5
    }
  }, children);
}
Object.assign(window, {
  DesignCanvas,
  DCSection,
  DCArtboard,
  DCPostIt
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "guidelines/explorations/design-canvas.jsx", error: String((e && e.message) || e) }); }

// ui_kits/council/chrome.jsx
try { (() => {
// @ds-adherence-ignore -- Council window chrome + sidebar. Window globals.
const R = window.React;
(function () {
  if (document.getElementById('al-kit-css')) return;
  const s = document.createElement('style');
  s.id = 'al-kit-css';
  s.textContent = `
  .alk-win{display:flex;flex-direction:column;width:100%;height:100%;background:var(--bg-base);
    border:1px solid var(--border-default);border-radius:var(--radius-window);overflow:hidden;
    box-shadow:var(--shadow-xl);font-family:var(--font-sans)}
  .alk-title{height:44px;flex:none;display:flex;align-items:center;gap:12px;padding:0 14px;
    background:var(--bg-surface);border-bottom:1px solid var(--border-subtle)}
  .alk-lights{display:flex;gap:8px;flex:none}
  .alk-lights i{width:12px;height:12px;border-radius:50%;display:block}
  .alk-titlecenter{flex:1;display:flex;flex-wrap:nowrap;align-items:center;justify-content:center;gap:8px}
  .alk-titlecenter .nm,.alk-titlecenter .sub{white-space:nowrap}
  .alk-titlecenter .nm{font-size:var(--text-label);font-weight:600;color:var(--text-secondary)}
  .alk-titlecenter .sub{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .alk-titleright{display:flex;align-items:center;gap:6px;flex:none}
  .alk-body{flex:1;display:flex;min-height:0}
  .alk-side{width:264px;flex:none;background:var(--bg-subtle);border-right:1px solid var(--border-subtle);
    display:flex;flex-direction:column;overflow:auto}
  .alk-side__sec{padding:16px 14px 8px}
  .alk-side__h{display:flex;align-items:center;justify-content:space-between;margin-bottom:10px}
  .alk-side__t{font-size:var(--text-caption);font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--text-faint)}
  .alk-side__list{display:flex;flex-direction:column;gap:6px}
  .alk-divider{height:1px;background:var(--border-subtle);margin:8px 0}
  .alk-synth{display:flex;align-items:center;gap:10px;padding:9px 10px;border-radius:var(--radius-md);
    background:var(--bg-raised);border:1px solid var(--border-subtle);cursor:pointer}
  .alk-synth .lbl{flex:1;font-size:var(--text-body);font-weight:600;color:var(--text-primary)}
  .alk-synth .tag{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--accent-text)}
  .alk-hist{display:flex;align-items:center;gap:9px;padding:7px 8px;border-radius:var(--radius-sm);cursor:pointer}
  .alk-hist:hover{background:var(--bg-hover)}
  .alk-hist .dot{width:6px;height:6px;border-radius:50%;flex:none}
  .alk-hist .h-main{flex:1;min-width:0}
  .alk-hist .h-t{font-size:var(--text-label);color:var(--text-secondary);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .alk-hist .h-m{font-family:var(--font-mono);font-size:9px;color:var(--text-faint)}
  .alk-main{flex:1;min-width:0;display:flex;flex-direction:column;background:var(--bg-base);overflow:auto}
  /* live mark */
  .al-livemark .cur{fill:#FFE9C6}
  .al-livemark.run .cur{animation:al-curblink 1.05s steps(1,end) infinite}
  @keyframes al-curblink{0%,52%{opacity:1}53%,100%{opacity:0}}`;
  document.head.appendChild(s);
})();
const LIVE_SVG = `
  <defs>
    <linearGradient id="lmcg" x1="20" y1="24" x2="66" y2="80" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFD79E"/><stop offset=".5" stop-color="#FFA630"/><stop offset="1" stop-color="#F0901C"/></linearGradient>
    <mask id="lmcm"><rect width="100" height="100" fill="black"/>
      <circle cx="47" cy="50" r="32" fill="white"/><circle cx="62" cy="41" r="28" fill="black"/></mask>
  </defs>
  <rect width="100" height="100" fill="url(#lmcg)" mask="url(#lmcm)"/>
  <rect class="cur" x="60" y="43" width="10.5" height="17" rx="2.6"/>`;
window.LiveMark = function LiveMark({
  size = 20,
  run = false
}) {
  return R.createElement('svg', {
    className: 'al-livemark' + (run ? ' run' : ''),
    width: size,
    height: size,
    viewBox: '0 0 100 100',
    dangerouslySetInnerHTML: {
      __html: LIVE_SVG
    }
  });
};
window.WindowChrome = function WindowChrome({
  healthy = 6,
  total = 6,
  children
}) {
  const {
    IconButton,
    Icon,
    Badge,
    LiveMark
  } = window;
  return R.createElement('div', {
    className: 'alk-win'
  }, R.createElement('div', {
    className: 'alk-title'
  }, R.createElement('div', {
    className: 'alk-lights'
  }, R.createElement('i', {
    style: {
      background: '#FF5F57'
    }
  }), R.createElement('i', {
    style: {
      background: '#FEBC2E'
    }
  }), R.createElement('i', {
    style: {
      background: '#28C840'
    }
  })), R.createElement('div', {
    className: 'alk-titlecenter'
  }, R.createElement(LiveMark, {
    size: 16
  }), R.createElement('span', {
    className: 'nm'
  }, 'allnighter'), R.createElement('span', {
    className: 'sub'
  }, '· council')), R.createElement('div', {
    className: 'alk-titleright'
  }, R.createElement(Badge, {
    tone: 'positive',
    dot: true
  }, healthy + '/' + total + ' healthy'), R.createElement(IconButton, {
    variant: 'ghost',
    size: 'sm',
    label: 'History'
  }, R.createElement(Icon, {
    name: 'history'
  })), R.createElement(IconButton, {
    variant: 'ghost',
    size: 'sm',
    label: 'Settings'
  }, R.createElement(Icon, {
    name: 'settings-2'
  })))), R.createElement('div', {
    className: 'alk-body'
  }, children));
};
window.Sidebar = function Sidebar({
  selected,
  onToggle,
  disabled
}) {
  const {
    WorkerChip,
    Icon,
    Glyph
  } = window;
  const workers = window.AL_WORKERS;
  return R.createElement('aside', {
    className: 'alk-side'
  }, R.createElement('div', {
    className: 'alk-side__sec'
  }, R.createElement('div', {
    className: 'alk-side__h'
  }, R.createElement('span', {
    className: 'alk-side__t'
  }, 'Panel'), R.createElement('span', {
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: 10,
      color: 'var(--text-faint)',
      whiteSpace: 'nowrap'
    }
  }, selected.size + ' of ' + workers.length)), R.createElement('div', {
    className: 'alk-side__list'
  }, workers.map(w => R.createElement(WorkerChip, {
    key: w.id,
    name: w.name,
    model: w.model,
    selectable: !disabled,
    selected: selected.has(w.id),
    onToggle: () => onToggle(w.id),
    glyph: R.createElement(Glyph, {
      worker: w
    })
  })))), R.createElement('div', {
    className: 'alk-side__sec'
  }, R.createElement('div', {
    className: 'alk-side__t',
    style: {
      marginBottom: 10
    }
  }, 'PlanWriter'), R.createElement('div', {
    className: 'alk-synth'
  }, R.createElement(Glyph, {
    worker: workers[0]
  }), R.createElement('span', {
    className: 'lbl'
  }, 'Opus 4.8'), R.createElement('span', {
    className: 'tag'
  }, 'master'), R.createElement(Icon, {
    name: 'chevron-down',
    size: 15,
    style: {
      color: 'var(--text-faint)'
    }
  }))), R.createElement('div', {
    className: 'alk-side__sec',
    style: {
      marginTop: 'auto'
    }
  }, R.createElement('div', {
    className: 'alk-side__t',
    style: {
      marginBottom: 8
    }
  }, 'Recent'), [['premium dashboard directions', '03:12 · 6 done', 'var(--green-500)'], ['rename the onboarding steps', '01:40 · 5 done', 'var(--green-500)'], ['api error copy rewrite', 'yesterday · 4 done', 'var(--yellow-500)']].map((h, i) => R.createElement('div', {
    className: 'alk-hist',
    key: i
  }, R.createElement('span', {
    className: 'dot',
    style: {
      background: h[2]
    }
  }), R.createElement('span', {
    className: 'h-main'
  }, R.createElement('div', {
    className: 'h-t'
  }, h[0]), R.createElement('div', {
    className: 'h-m'
  }, h[1]))))));
};
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/council/chrome.jsx", error: String((e && e.message) || e) }); }

// ui_kits/council/data.jsx
try { (() => {
// @ds-adherence-ignore -- UI-kit data + a Glyph helper. Window globals.
const R = window.React;

// The founder's real six-worker panel (MVP README §0).
window.AL_WORKERS = [{
  id: 'opus',
  name: 'Opus 4.8',
  model: 'via claude-code',
  brand: 'anthropic',
  color: 'FFA630',
  synth: true
}, {
  id: 'gpt',
  name: 'ChatGPT 5.5',
  model: 'via codex-cli',
  icon: 'terminal'
}, {
  id: 'sonnet',
  name: 'Sonnet 4.6',
  model: 'via claude-code',
  brand: 'anthropic',
  color: 'AEB5C9'
}, {
  id: 'composer',
  name: 'Composer 2.5',
  model: 'via cursor',
  icon: 'square'
}, {
  id: 'gemini',
  name: 'Gemini Flash',
  model: 'via gemini-cli',
  brand: 'googlegemini',
  color: 'E1E5F0'
}, {
  id: 'grok',
  name: 'Grok Build',
  model: 'via grok-cli',
  brand: 'x',
  color: 'E1E5F0'
}];
window.AL_PROMPT = 'Give me three different directions for making this dashboard feel premium.';

// Per-worker simulated run timing + token counts (ms to done).
window.AL_RUN = {
  opus: {
    ms: 4200,
    tok: '2,140'
  },
  gpt: {
    ms: 2600,
    tok: '1,512'
  },
  sonnet: {
    ms: 3100,
    tok: '1,884'
  },
  composer: {
    ms: 2200,
    tok: '1,043'
  },
  gemini: {
    ms: 1500,
    tok: '842',
    fail: false
  },
  grok: {
    ms: 2900,
    tok: '—',
    fail: true
  }
};
window.AL_PLAN = {
  consensus: ['Lead with typography and spacing, not color — premium reads as restraint.', 'Replace flat fills with one accent + a calm neutral scale; kill gradient noise.', 'Add depth through hairline borders and soft shadow, not heavy cards.'],
  conflicts: ['Opus & Sonnet want a denser data grid; Gemini argues for more whitespace and fewer KPIs.', 'ChatGPT proposes a dark theme by default; Composer keeps light primary with a dark mode toggle.'],
  gaps: ['No one addressed empty/loading states — premium products feel polished there first.', 'Motion was mentioned but unspecified; needs an easing + duration system.'],
  plan: ['Set a type scale (display 800 / body 400) and an 8px spacing grid; apply to the header + KPI row first.', 'Collapse the palette to one accent + a 7-step neutral ramp; remove all gradients from tiles.', 'Rebuild cards as hairline-border + soft-shadow surfaces; unify radius at 10px.', 'Design the empty, loading, and error states for the main chart before adding features.', 'Adopt a 160–240ms ease-out motion system for hovers, opens, and value changes.'],
  minority: {
    who: 'Gemini Flash',
    text: 'Cut the dashboard to 3 KPIs and one chart. Most “premium” wins come from removing, not styling.'
  }
};
window.AL_ANSWERS = {
  opus: 'Three directions: (1) Editorial — big type, generous whitespace, one accent. (2) Control-room — dense, mono numerics, dark. (3) Calm-OS — soft surfaces, muted color, motion. I’d ship (1): premium is restraint. Start with the type scale and spacing grid, then strip gradients.',
  gpt: 'Default to a dark theme; it instantly reads as pro. Use a single saturated accent for primary actions and keep every surface near-black with hairline borders. Tighten the KPI row to four metrics and set them in a mono face.',
  sonnet: 'Premium = hierarchy + consistency. Define a 6-step type scale and an 8px grid, then audit every component against it. Add a denser data table with sticky headers; power users equate density with capability.',
  composer: 'Keep light as primary with a polished dark mode. Standardize radius (10px), border (1px hairline), and shadow (one soft step). Replace icon noise with a tighter set. Ship a motion spec: 200ms ease-out.',
  gemini: 'Less is the upgrade. Cut to three KPIs and one chart, double the whitespace, and remove decorative color entirely. A premium dashboard answers one question beautifully, not ten adequately.',
  grok: ''
};

// Glyph renderer: brand logo when available, else a Lucide icon.
window.Glyph = function Glyph({
  worker,
  size = 18
}) {
  const {
    BrandIcon,
    Icon
  } = window;
  if (worker.brand) return R.createElement(BrandIcon, {
    slug: worker.brand,
    color: worker.color,
    size
  });
  return R.createElement(Icon, {
    name: worker.icon || 'terminal',
    size: size - 2,
    style: {
      color: 'var(--text-secondary)'
    }
  });
};
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/council/data.jsx", error: String((e && e.message) || e) }); }

// ui_kits/council/screens.jsx
try { (() => {
// @ds-adherence-ignore -- Council screens: Composer, RunView, PlanView.
const R = window.React;
(function () {
  if (document.getElementById('al-screens-css')) return;
  const s = document.createElement('style');
  s.id = 'al-screens-css';
  s.textContent = `
  .alc-pad{padding:28px 32px}
  .alc-eyebrow{font-size:var(--text-caption);font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--accent-text);margin-bottom:14px}
  .alc-compose{max-width:680px;margin:0 auto;width:100%}
  .alc-prompt{background:var(--bg-raised);border:1px solid var(--border-default);border-radius:var(--radius-xl);overflow:hidden;box-shadow:var(--shadow-sm)}
  .alc-prompt:focus-within{border-color:var(--accent-border)}
  .alc-prompt textarea{display:block;width:100%;box-sizing:border-box;background:transparent;border:none;outline:none;resize:none;
    color:var(--text-primary);font-family:var(--font-sans);font-size:18px;line-height:1.5;padding:22px 22px 12px}
  .alc-prompt textarea::placeholder{color:var(--text-faint)}
  .alc-promptbar{display:flex;align-items:center;justify-content:space-between;padding:12px 14px;border-top:1px solid var(--border-subtle)}
  .alc-meta{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-faint)}
  .alc-examples{display:flex;gap:8px;flex-wrap:wrap;margin-top:16px}
  .alc-ex{font-size:var(--text-label);color:var(--text-muted);background:var(--bg-surface);border:1px solid var(--border-subtle);
    border-radius:var(--radius-pill);padding:5px 12px;cursor:pointer;transition:var(--transition-control);white-space:nowrap}
  .alc-ex:hover{color:var(--text-primary);border-color:var(--border-default)}
  .alc-runhead{display:flex;align-items:flex-start;justify-content:space-between;gap:16px;margin-bottom:18px}
  .alc-runtitle{font-size:var(--text-h2);font-weight:700;letter-spacing:-.01em}
  .alc-runprompt{color:var(--text-muted);font-size:var(--text-body);margin-top:4px;max-width:560px}
  .alc-grid{display:grid;grid-template-columns:1fr 1fr;gap:10px}
  .alc-synthbar{margin-top:18px;display:flex;align-items:center;gap:12px;padding:14px 16px;border-radius:var(--radius-lg);
    background:linear-gradient(180deg,rgba(255,166,48,.07),transparent),var(--bg-raised);border:1px solid var(--accent-border)}
  .alc-synthbar .st{flex:1}
  .alc-synthbar .t{font-size:var(--text-body);font-weight:600;color:var(--text-primary)}
  .alc-synthbar .m{font-family:var(--font-mono);font-size:var(--text-mono-sm);color:var(--text-muted);margin-top:2px}
  .alc-planhead{display:flex;align-items:center;justify-content:space-between;gap:16px;margin-bottom:18px}
  .alc-sec{margin-bottom:14px}
  .alc-sec__h{display:flex;align-items:center;gap:8px;margin-bottom:10px}
  .alc-sec__ic{width:24px;height:24px;border-radius:var(--radius-sm);display:flex;align-items:center;justify-content:center;flex:none}
  .alc-sec__t{font-size:var(--text-title);font-weight:600}
  .alc-li{display:flex;gap:10px;padding:7px 0;font-size:var(--text-body);color:var(--text-secondary);line-height:1.5;border-bottom:1px solid var(--border-subtle)}
  .alc-li:last-child{border-bottom:none}
  .alc-num{flex:none;width:20px;height:20px;border-radius:50%;background:var(--accent-surface);color:var(--accent-text);
    font-family:var(--font-mono);font-size:11px;font-weight:600;display:flex;align-items:center;justify-content:center;margin-top:1px}
  .alc-dot{flex:none;width:6px;height:6px;border-radius:50%;background:var(--text-faint);margin-top:7px}
  .alc-quote{font-size:var(--text-body-lg);line-height:1.55;color:var(--text-primary);font-style:italic}
  .alc-answer{font-size:var(--text-body);color:var(--text-secondary);line-height:1.6;margin-top:8px}
  .alc-prompthdr{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:16px}
  .alc-prompthdr .p{font-size:var(--text-body);color:var(--text-secondary)}`;
  document.head.appendChild(s);
})();

/* ---------- Composer ---------- */
window.Composer = function Composer({
  value,
  onChange,
  onRun,
  count,
  onExample
}) {
  const {
    Button,
    Icon
  } = window;
  return R.createElement('div', {
    className: 'alc-pad',
    style: {
      display: 'flex',
      flexDirection: 'column',
      justifyContent: 'center',
      flex: 1
    }
  }, R.createElement('div', {
    className: 'alc-compose'
  }, R.createElement('div', {
    className: 'alc-eyebrow'
  }, 'New council run'), R.createElement('div', {
    className: 'alc-prompt'
  }, R.createElement('textarea', {
    rows: 3,
    placeholder: 'Ask the panel one thing…',
    value,
    onChange: e => onChange(e.target.value)
  }), R.createElement('div', {
    className: 'alc-promptbar'
  }, R.createElement('span', {
    className: 'alc-meta'
  }, count + ' workers · local · $0 marginal'), R.createElement(Button, {
    variant: 'primary',
    iconLeft: R.createElement(Icon, {
      name: 'play',
      size: 15
    }),
    onClick: onRun,
    disabled: !value.trim() || count === 0
  }, 'Run council'))), R.createElement('div', {
    className: 'alc-examples'
  }, ['3 directions for a premium dashboard', 'rewrite our API error copy', 'plan a migration to Swift 6'].map((ex, i) => R.createElement('button', {
    className: 'alc-ex',
    key: i,
    onClick: () => onExample(ex)
  }, ex)))));
};

/* ---------- RunView ---------- */
window.RunView = function RunView({
  workers,
  states,
  elapsed,
  prompt,
  synth,
  onStop,
  onView
}) {
  const {
    WorkerChip,
    Button,
    Icon,
    Glyph,
    LiveMark
  } = window;
  return R.createElement('div', {
    className: 'alc-pad'
  }, R.createElement('div', {
    className: 'alc-runhead'
  }, R.createElement('div', null, R.createElement('div', {
    className: 'alc-runtitle'
  }, 'Council run'), R.createElement('div', {
    className: 'alc-runprompt'
  }, prompt)), R.createElement('div', {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 12,
      flex: 'none'
    }
  }, R.createElement('span', {
    className: 'alc-meta',
    style: {
      fontSize: 13
    }
  }, elapsed), R.createElement(Button, {
    variant: 'secondary',
    size: 'sm',
    iconLeft: R.createElement(Icon, {
      name: 'square',
      size: 13
    }),
    onClick: onStop
  }, 'Stop'))), R.createElement('div', {
    className: 'alc-grid'
  }, workers.map(w => {
    const st = states[w.id] || {};
    return R.createElement(WorkerChip, {
      key: w.id,
      name: w.name,
      model: w.model,
      status: st.status || 'queued',
      meta: st.meta,
      glyph: R.createElement(Glyph, {
        worker: w
      })
    });
  })), synth !== 'waiting' && R.createElement('div', {
    className: 'alc-synthbar'
  }, R.createElement(LiveMark, {
    size: 26,
    run: synth === 'planning'
  }), R.createElement('div', {
    className: 'st'
  }, R.createElement('div', {
    className: 't'
  }, synth === 'planning' ? 'Opus is planning the plan…' : 'Plan ready'), R.createElement('div', {
    className: 'm'
  }, synth === 'planning' ? 'reading 5 answers · 1 failed' : '5 answers · 00:42 · $0.00 marginal')), synth === 'ready' && R.createElement(Button, {
    variant: 'primary',
    iconLeft: R.createElement(Icon, {
      name: 'arrow-right',
      size: 15
    }),
    onClick: onView
  }, 'View plan')));
};

/* ---------- PlanView ---------- */
function Section({
  icon,
  color,
  title,
  children
}) {
  const {
    Icon,
    Card
  } = window;
  return R.createElement('div', {
    className: 'alc-sec'
  }, R.createElement('div', {
    className: 'alc-sec__h'
  }, R.createElement('span', {
    className: 'alc-sec__ic',
    style: {
      background: color.bg,
      color: color.fg
    }
  }, R.createElement(Icon, {
    name: icon,
    size: 14
  })), R.createElement('span', {
    className: 'alc-sec__t'
  }, title)), R.createElement(Card, {
    variant: 'flush'
  }, children));
}
window.PlanView = function PlanView({
  onNew
}) {
  const {
    Button,
    IconButton,
    Icon,
    Tabs,
    Card,
    StatusPill,
    WorkerChip,
    Glyph,
    Badge
  } = window;
  const [tab, setTab] = R.useState('plan');
  const P = window.AL_PLAN;
  const workers = window.AL_WORKERS,
    answers = window.AL_ANSWERS;
  return R.createElement('div', {
    className: 'alc-pad'
  }, R.createElement('div', {
    className: 'alc-planhead'
  }, R.createElement(Tabs, {
    variant: 'segmented',
    value: tab,
    onChange: setTab,
    items: [{
      value: 'plan',
      label: 'Plan'
    }, {
      value: 'answers',
      label: 'Member answers',
      count: 6
    }]
  }), R.createElement('div', {
    style: {
      display: 'flex',
      gap: 8
    }
  }, R.createElement(Button, {
    variant: 'ghost',
    size: 'sm',
    iconLeft: R.createElement(Icon, {
      name: 'copy',
      size: 14
    })
  }, 'Copy'), R.createElement(Button, {
    variant: 'secondary',
    size: 'sm',
    iconLeft: R.createElement(Icon, {
      name: 'download',
      size: 14
    })
  }, 'Export Markdown'), R.createElement(Button, {
    variant: 'primary',
    size: 'sm',
    iconLeft: R.createElement(Icon, {
      name: 'plus',
      size: 14
    }),
    onClick: onNew
  }, 'New run'))), tab === 'plan' ? R.createElement('div', null, R.createElement(Card, {
    variant: 'accent',
    style: {
      marginBottom: 18
    }
  }, R.createElement('div', {
    className: 'alc-prompthdr'
  }, R.createElement('div', {
    className: 'p'
  }, '“' + window.AL_PROMPT + '”'), R.createElement(Badge, {
    tone: 'accent',
    mono: true
  }, 'Opus 4.8')), R.createElement('div', {
    className: 'alc-meta'
  }, 'synthesized from 5 answers · 00:42 · $0.00 marginal · local')), R.createElement(Section, {
    icon: 'check-check',
    color: {
      bg: 'var(--success-surface)',
      fg: 'var(--green-400)'
    },
    title: 'Consensus'
  }, P.consensus.map((t, i) => R.createElement('div', {
    className: 'alc-li',
    key: i
  }, R.createElement('span', {
    className: 'alc-dot'
  }), t))), R.createElement(Section, {
    icon: 'zap',
    color: {
      bg: 'var(--warning-surface)',
      fg: 'var(--yellow-400)'
    },
    title: 'Conflicts'
  }, P.conflicts.map((t, i) => R.createElement('div', {
    className: 'alc-li',
    key: i
  }, R.createElement('span', {
    className: 'alc-dot'
  }), t))), R.createElement(Section, {
    icon: 'search',
    color: {
      bg: 'var(--info-surface)',
      fg: 'var(--blue-400)'
    },
    title: 'Gaps'
  }, P.gaps.map((t, i) => R.createElement('div', {
    className: 'alc-li',
    key: i
  }, R.createElement('span', {
    className: 'alc-dot'
  }), t))), R.createElement(Section, {
    icon: 'arrow-right',
    color: {
      bg: 'var(--accent-surface)',
      fg: 'var(--accent-text)'
    },
    title: 'The plan'
  }, P.plan.map((t, i) => R.createElement('div', {
    className: 'alc-li',
    key: i
  }, R.createElement('span', {
    className: 'alc-num'
  }, i + 1), t))), R.createElement(Section, {
    icon: 'users',
    color: {
      bg: 'var(--bg-active)',
      fg: 'var(--text-muted)'
    },
    title: 'Minority report'
  }, R.createElement('div', {
    className: 'alc-quote'
  }, '“' + P.minority.text + '”'), R.createElement('div', {
    className: 'alc-meta',
    style: {
      marginTop: 8
    }
  }, '— ' + P.minority.who))) : R.createElement('div', {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, workers.map(w => R.createElement(Card, {
    key: w.id,
    variant: 'flush'
  }, R.createElement('div', {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      marginBottom: 2
    }
  }, R.createElement('span', {
    style: {
      width: 26,
      height: 26,
      borderRadius: 6,
      background: 'var(--bg-active)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, R.createElement(Glyph, {
    worker: w
  })), R.createElement('span', {
    style: {
      fontWeight: 600,
      flex: 1
    }
  }, w.name), R.createElement('span', {
    style: {
      fontFamily: 'var(--font-mono)',
      fontSize: 11,
      color: 'var(--text-faint)'
    }
  }, w.model), R.createElement(StatusPill, {
    status: answers[w.id] ? 'done' : 'failed'
  })), answers[w.id] ? R.createElement('div', {
    className: 'alc-answer'
  }, answers[w.id]) : R.createElement('div', {
    className: 'alc-answer',
    style: {
      color: 'var(--text-faint)'
    }
  }, 'No answer — CLI auth expired. Surfaced in Doctor, never faked.')))));
};
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/council/screens.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.Switch = __ds_scope.Switch;

__ds_ns.Textarea = __ds_scope.Textarea;

__ds_ns.Tabs = __ds_scope.Tabs;

__ds_ns.StatusPill = __ds_scope.StatusPill;

__ds_ns.WorkerChip = __ds_scope.WorkerChip;

})();
