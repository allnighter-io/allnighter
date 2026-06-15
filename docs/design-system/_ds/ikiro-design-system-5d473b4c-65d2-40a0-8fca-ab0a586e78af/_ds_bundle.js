/* @ds-bundle: {"format":3,"namespace":"IkiroDesignSystem_5d473b","components":[{"name":"Avatar","sourcePath":"components/core/Avatar.jsx"},{"name":"Badge","sourcePath":"components/core/Badge.jsx"},{"name":"Button","sourcePath":"components/core/Button.jsx"},{"name":"Card","sourcePath":"components/core/Card.jsx"},{"name":"IconButton","sourcePath":"components/core/IconButton.jsx"},{"name":"Tag","sourcePath":"components/core/Tag.jsx"},{"name":"Input","sourcePath":"components/forms/Input.jsx"},{"name":"Switch","sourcePath":"components/forms/Switch.jsx"},{"name":"Textarea","sourcePath":"components/forms/Textarea.jsx"},{"name":"Tabs","sourcePath":"components/navigation/Tabs.jsx"},{"name":"LinkRow","sourcePath":"components/product/LinkRow.jsx"},{"name":"Stat","sourcePath":"components/product/Stat.jsx"}],"sourceHashes":{"components/core/Avatar.jsx":"cd974c1c1dae","components/core/Badge.jsx":"88c3b712d454","components/core/Button.jsx":"6488e5ab4890","components/core/Card.jsx":"dc0ee5be6a60","components/core/IconButton.jsx":"66aef7942477","components/core/Tag.jsx":"990bc507f7aa","components/forms/Input.jsx":"2fbbbda3976f","components/forms/Switch.jsx":"a62f1e31a0c0","components/forms/Textarea.jsx":"10ce09c885b1","components/navigation/Tabs.jsx":"e90d834996e4","components/product/LinkRow.jsx":"f4801e840863","components/product/Stat.jsx":"e1abda0e4e08","ui_kits/studio/AddComposer.jsx":"fc8e61448786","ui_kits/studio/BlockComposer.jsx":"aa7fe7bcb7b0","ui_kits/studio/ContentPanel.jsx":"fcd6159950ba","ui_kits/studio/Copilot.jsx":"f6d533b107fb","ui_kits/studio/Import.jsx":"6e11a62d9580","ui_kits/studio/Inspector.jsx":"b52bbf2271e6","ui_kits/studio/LinkHubPage.jsx":"8d75350d5cee","ui_kits/studio/PublicMount.jsx":"3c96a70aea5d","ui_kits/studio/StudioApp.jsx":"0335b0c5b4bb","ui_kits/studio/design-canvas.jsx":"bd8746af6e58","ui_kits/studio/footerBadges.jsx":"3fa2a751119c","ui_kits/studio/hubData.jsx":"3dcadbda77b8","ui_kits/studio/icons.jsx":"72536e90407f","ui_kits/studio/importData.jsx":"d52b5564e95e","ui_kits/studio/registry.jsx":"419121b71d19"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.IkiroDesignSystem_5d473b = window.IkiroDesignSystem_5d473b || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/core/Avatar.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useAvatarStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-avatar {
    --_s: 2.5rem;
    position: relative; display: inline-flex; align-items: center; justify-content: center;
    width: var(--_s); height: var(--_s); flex: 0 0 auto;
    border-radius: var(--radius-pill); overflow: visible;
    font-family: var(--font-sans); font-weight: var(--weight-semibold);
    color: var(--accent-text); background: var(--accent-soft);
    user-select: none;
  }
  .ik-avatar[data-shape="rounded"] { border-radius: var(--radius-md); }
  .ik-avatar[data-size="xs"] { --_s: 1.5rem; font-size: 0.625rem; }
  .ik-avatar[data-size="sm"] { --_s: 2rem; font-size: 0.75rem; }
  .ik-avatar[data-size="md"] { --_s: 2.5rem; font-size: 0.875rem; }
  .ik-avatar[data-size="lg"] { --_s: 3.25rem; font-size: 1.125rem; }
  .ik-avatar[data-size="xl"] { --_s: 4.5rem; font-size: 1.5rem; }
  .ik-avatar__img { width: 100%; height: 100%; object-fit: cover; border-radius: inherit; display: block; }
  .ik-avatar__ring { box-shadow: 0 0 0 2px var(--surface-card), 0 0 0 3px var(--border-default); }
  .ik-avatar__status {
    position: absolute; right: -1px; bottom: -1px;
    width: 30%; height: 30%; min-width: 8px; min-height: 8px;
    border-radius: 50%; border: 2px solid var(--surface-card);
  }
  .ik-avatar__status[data-status="online"] { background: var(--positive); }
  .ik-avatar__status[data-status="busy"]   { background: var(--danger); }
  .ik-avatar__status[data-status="away"]   { background: var(--warning); }
  .ik-avatar__status[data-status="offline"]{ background: var(--ink-300); }
  `;
  const el = document.createElement("style");
  el.id = "ik-avatar-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function initials(name = "") {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}
function Avatar({
  src,
  name = "",
  size = "md",
  shape = "circle",
  status,
  ring = false,
  ...rest
}) {
  useAvatarStyles();
  return /*#__PURE__*/React.createElement("span", _extends({
    className: "ik-avatar" + (ring ? " ik-avatar__ring" : ""),
    "data-size": size,
    "data-shape": shape,
    title: name || undefined
  }, rest), src ? /*#__PURE__*/React.createElement("img", {
    className: "ik-avatar__img",
    src: src,
    alt: name
  }) : /*#__PURE__*/React.createElement("span", {
    "aria-hidden": "true"
  }, initials(name)), status && /*#__PURE__*/React.createElement("span", {
    className: "ik-avatar__status",
    "data-status": status
  }));
}
Object.assign(__ds_scope, { Avatar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Avatar.jsx", error: String((e && e.message) || e) }); }

// components/core/Badge.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useBadgeStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-badge {
    display: inline-flex; align-items: center; gap: 0.3125rem;
    height: 1.5rem; padding: 0 0.5rem;
    font-family: var(--font-sans); font-size: var(--text-overline);
    font-weight: var(--weight-semibold); letter-spacing: var(--tracking-snug);
    line-height: 1; white-space: nowrap; border-radius: var(--radius-sm);
    border: 1px solid transparent;
  }
  .ik-badge[data-size="sm"] { height: 1.25rem; padding: 0 0.375rem; font-size: 0.6875rem; }
  .ik-badge__dot { width: 0.4375rem; height: 0.4375rem; border-radius: 50%; background: currentColor; flex: 0 0 auto; }
  .ik-badge__ico { display: inline-flex; margin-left: -0.0625rem; }

  /* soft (default) */
  .ik-badge[data-tone="neutral"]  { background: var(--ink-100); color: var(--ink-700); }
  .ik-badge[data-tone="accent"]   { background: var(--accent-soft); color: var(--accent-text); }
  .ik-badge[data-tone="positive"] { background: var(--positive-soft); color: var(--positive-text); }
  .ik-badge[data-tone="warning"]  { background: var(--warning-soft); color: var(--warning-text); }
  .ik-badge[data-tone="danger"]   { background: var(--danger-soft); color: var(--danger-text); }
  .ik-badge[data-tone="info"]     { background: var(--info-soft); color: var(--info-text); }

  /* solid */
  .ik-badge[data-variant="solid"][data-tone="neutral"]  { background: var(--ink-800); color: #fff; }
  .ik-badge[data-variant="solid"][data-tone="accent"]   { background: var(--accent); color: var(--accent-contrast); }
  .ik-badge[data-variant="solid"][data-tone="positive"] { background: var(--positive); color: #fff; }
  .ik-badge[data-variant="solid"][data-tone="warning"]  { background: var(--warning); color: #4a3206; }
  .ik-badge[data-variant="solid"][data-tone="danger"]   { background: var(--danger); color: #fff; }
  .ik-badge[data-variant="solid"][data-tone="info"]     { background: var(--info); color: #fff; }

  /* outline */
  .ik-badge[data-variant="outline"] { background: transparent; border-color: var(--border-default); color: var(--text-body); }
  `;
  const el = document.createElement("style");
  el.id = "ik-badge-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function Badge({
  tone = "neutral",
  variant = "soft",
  size = "md",
  dot = false,
  icon,
  children,
  ...rest
}) {
  useBadgeStyles();
  return /*#__PURE__*/React.createElement("span", _extends({
    className: "ik-badge",
    "data-tone": tone,
    "data-variant": variant,
    "data-size": size
  }, rest), dot && /*#__PURE__*/React.createElement("span", {
    className: "ik-badge__dot",
    "aria-hidden": "true"
  }), icon && !dot && /*#__PURE__*/React.createElement("span", {
    className: "ik-badge__ico"
  }, icon), children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Badge.jsx", error: String((e && e.message) || e) }); }

// components/core/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Inject this component's CSS once. Self-contained: references design
   tokens via CSS custom properties from styles.css. */
let injected = false;
function useButtonStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-btn {
    --_h: 2.5rem; --_px: 1rem; --_fs: var(--text-body-sm); --_gap: 0.5rem;
    display: inline-flex; align-items: center; justify-content: center;
    gap: var(--_gap); height: var(--_h); padding: 0 var(--_px);
    font-family: var(--font-sans); font-size: var(--_fs);
    font-weight: var(--weight-semibold); letter-spacing: var(--tracking-snug);
    line-height: 1; white-space: nowrap; border-radius: var(--radius-md);
    border: 1px solid transparent; cursor: pointer; user-select: none;
    transition: background var(--dur-fast) var(--ease-out),
                border-color var(--dur-fast) var(--ease-out),
                color var(--dur-fast) var(--ease-out),
                box-shadow var(--dur-fast) var(--ease-out),
                transform var(--dur-fast) var(--ease-out);
  }
  .ik-btn:focus-visible { outline: none; box-shadow: var(--focus-ring); }
  .ik-btn:active:not(:disabled) { transform: scale(var(--press-scale)); }
  .ik-btn[disabled], .ik-btn[aria-disabled="true"] { cursor: not-allowed; opacity: 0.5; }
  .ik-btn[data-full="true"] { width: 100%; }

  .ik-btn[data-size="sm"] { --_h: 2rem; --_px: 0.75rem; --_fs: var(--text-caption); --_gap: 0.375rem; border-radius: var(--radius-sm); }
  .ik-btn[data-size="lg"] { --_h: 3rem; --_px: 1.375rem; --_fs: var(--text-body); --_gap: 0.5rem; }

  /* primary */
  .ik-btn[data-variant="primary"] { background: var(--accent); color: var(--accent-contrast); }
  .ik-btn[data-variant="primary"]:hover:not(:disabled) { background: var(--accent-hover); box-shadow: var(--shadow-accent); }
  .ik-btn[data-variant="primary"]:active:not(:disabled) { background: var(--accent-press); box-shadow: none; }

  /* secondary (outline on paper) */
  .ik-btn[data-variant="secondary"] { background: var(--surface-card); color: var(--text-strong); border-color: var(--border-default); box-shadow: var(--shadow-xs); }
  .ik-btn[data-variant="secondary"]:hover:not(:disabled) { background: var(--surface-hover); border-color: var(--border-strong); }
  .ik-btn[data-variant="secondary"]:active:not(:disabled) { background: var(--surface-active); }

  /* ghost */
  .ik-btn[data-variant="ghost"] { background: transparent; color: var(--text-body); }
  .ik-btn[data-variant="ghost"]:hover:not(:disabled) { background: var(--surface-hover); color: var(--text-strong); }
  .ik-btn[data-variant="ghost"]:active:not(:disabled) { background: var(--surface-active); }

  /* danger */
  .ik-btn[data-variant="danger"] { background: var(--danger); color: #fff; }
  .ik-btn[data-variant="danger"]:hover:not(:disabled) { background: var(--red-600); }

  .ik-btn__spinner { width: 1em; height: 1em; border-radius: 50%;
    border: 2px solid currentColor; border-top-color: transparent;
    animation: ik-btn-spin 0.6s linear infinite; }
  @keyframes ik-btn-spin { to { transform: rotate(360deg); } }
  .ik-btn__ico { display: inline-flex; flex: 0 0 auto; }
  `;
  const el = document.createElement("style");
  el.id = "ik-button-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function Button({
  variant = "primary",
  size = "md",
  iconLeft,
  iconRight,
  loading = false,
  fullWidth = false,
  disabled = false,
  type = "button",
  children,
  ...rest
}) {
  useButtonStyles();
  return /*#__PURE__*/React.createElement("button", _extends({
    type: type,
    className: "ik-btn",
    "data-variant": variant,
    "data-size": size,
    "data-full": fullWidth ? "true" : undefined,
    disabled: disabled || loading
  }, rest), loading && /*#__PURE__*/React.createElement("span", {
    className: "ik-btn__spinner",
    "aria-hidden": "true"
  }), !loading && iconLeft && /*#__PURE__*/React.createElement("span", {
    className: "ik-btn__ico"
  }, iconLeft), children, !loading && iconRight && /*#__PURE__*/React.createElement("span", {
    className: "ik-btn__ico"
  }, iconRight));
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }

// components/core/Card.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useCardStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-card {
    display: flex; flex-direction: column;
    background: var(--surface-card); color: var(--text-body);
    border: 1px solid var(--border-subtle); border-radius: var(--radius-lg);
    padding: var(--space-6);
    transition: border-color var(--dur-base) var(--ease-out),
                box-shadow var(--dur-base) var(--ease-out),
                transform var(--dur-base) var(--ease-out);
  }
  .ik-card[data-pad="sm"] { padding: var(--space-4); }
  .ik-card[data-pad="lg"] { padding: var(--space-8); }
  .ik-card[data-pad="none"] { padding: 0; }

  .ik-card[data-elevation="flat"]    { box-shadow: none; }
  .ik-card[data-elevation="raised"]  { box-shadow: var(--shadow-sm); border-color: var(--border-subtle); }
  .ik-card[data-elevation="floating"]{ box-shadow: var(--shadow-lg); border-color: transparent; }

  .ik-card[data-interactive="true"] { cursor: pointer; }
  .ik-card[data-interactive="true"]:hover {
    border-color: var(--border-default);
    box-shadow: var(--shadow-md);
    transform: translateY(-2px);
  }
  .ik-card[data-interactive="true"]:active { transform: translateY(0); box-shadow: var(--shadow-sm); }
  .ik-card[data-interactive="true"]:focus-visible { outline: none; box-shadow: var(--focus-ring); }

  .ik-card[data-accent="true"] {
    border-color: var(--accent-border);
    background: linear-gradient(180deg, var(--teal-50), var(--surface-card) 60%);
  }
  `;
  const el = document.createElement("style");
  el.id = "ik-card-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function Card({
  elevation = "raised",
  padding = "md",
  interactive = false,
  accent = false,
  as = "div",
  children,
  ...rest
}) {
  useCardStyles();
  const Comp = as;
  return /*#__PURE__*/React.createElement(Comp, _extends({
    className: "ik-card",
    "data-elevation": elevation,
    "data-pad": padding,
    "data-interactive": interactive ? "true" : undefined,
    "data-accent": accent ? "true" : undefined,
    tabIndex: interactive ? 0 : undefined
  }, rest), children);
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Card.jsx", error: String((e && e.message) || e) }); }

// components/core/IconButton.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useIconButtonStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-iconbtn {
    --_s: 2.5rem;
    display: inline-flex; align-items: center; justify-content: center;
    width: var(--_s); height: var(--_s); padding: 0;
    border-radius: var(--radius-md); border: 1px solid transparent;
    cursor: pointer; color: var(--text-body); background: transparent;
    transition: background var(--dur-fast) var(--ease-out),
                color var(--dur-fast) var(--ease-out),
                border-color var(--dur-fast) var(--ease-out),
                box-shadow var(--dur-fast) var(--ease-out),
                transform var(--dur-fast) var(--ease-out);
  }
  .ik-iconbtn:focus-visible { outline: none; box-shadow: var(--focus-ring); }
  .ik-iconbtn:active:not(:disabled) { transform: scale(var(--press-scale)); }
  .ik-iconbtn[disabled] { cursor: not-allowed; opacity: 0.45; }
  .ik-iconbtn[data-size="sm"] { --_s: 2rem; border-radius: var(--radius-sm); }
  .ik-iconbtn[data-size="lg"] { --_s: 3rem; }

  .ik-iconbtn[data-variant="ghost"]:hover:not(:disabled) { background: var(--surface-hover); color: var(--text-strong); }
  .ik-iconbtn[data-variant="ghost"]:active:not(:disabled) { background: var(--surface-active); }

  .ik-iconbtn[data-variant="outline"] { border-color: var(--border-default); background: var(--surface-card); box-shadow: var(--shadow-xs); }
  .ik-iconbtn[data-variant="outline"]:hover:not(:disabled) { background: var(--surface-hover); border-color: var(--border-strong); }

  .ik-iconbtn[data-variant="solid"] { background: var(--accent); color: var(--accent-contrast); }
  .ik-iconbtn[data-variant="solid"]:hover:not(:disabled) { background: var(--accent-hover); box-shadow: var(--shadow-accent); }

  .ik-iconbtn[data-active="true"] { background: var(--accent-soft); color: var(--accent-text); }
  `;
  const el = document.createElement("style");
  el.id = "ik-iconbutton-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function IconButton({
  variant = "ghost",
  size = "md",
  active = false,
  label,
  disabled = false,
  children,
  ...rest
}) {
  useIconButtonStyles();
  return /*#__PURE__*/React.createElement("button", _extends({
    type: "button",
    className: "ik-iconbtn",
    "data-variant": variant,
    "data-size": size,
    "data-active": active ? "true" : undefined,
    "aria-label": label,
    title: label,
    disabled: disabled
  }, rest), children);
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/core/Tag.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useTagStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-tag {
    display: inline-flex; align-items: center; gap: 0.375rem;
    height: 1.75rem; padding: 0 0.625rem;
    font-family: var(--font-sans); font-size: var(--text-caption);
    font-weight: var(--weight-medium); line-height: 1; color: var(--text-body);
    background: var(--surface-card); border: 1px solid var(--border-default);
    border-radius: var(--radius-pill); white-space: nowrap;
    transition: background var(--dur-fast) var(--ease-out),
                border-color var(--dur-fast) var(--ease-out),
                color var(--dur-fast) var(--ease-out);
  }
  button.ik-tag, .ik-tag[data-clickable="true"] { cursor: pointer; }
  button.ik-tag:hover, .ik-tag[data-clickable="true"]:hover { border-color: var(--border-strong); background: var(--surface-hover); }
  .ik-tag[data-selected="true"] { background: var(--accent-soft); border-color: var(--accent-border); color: var(--accent-text); }
  .ik-tag__ico { display: inline-flex; margin-left: -0.125rem; opacity: 0.85; }
  .ik-tag__x {
    display: inline-flex; align-items: center; justify-content: center;
    width: 1.05rem; height: 1.05rem; margin-right: -0.25rem; border: none;
    border-radius: 50%; background: transparent; color: inherit; cursor: pointer;
    opacity: 0.55; transition: opacity var(--dur-fast) var(--ease-out), background var(--dur-fast) var(--ease-out);
  }
  .ik-tag__x:hover { opacity: 1; background: var(--surface-active); }
  `;
  const el = document.createElement("style");
  el.id = "ik-tag-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function Tag({
  icon,
  selected = false,
  onRemove,
  onClick,
  children,
  ...rest
}) {
  useTagStyles();
  const clickable = !!onClick;
  const Comp = clickable ? "button" : "span";
  return /*#__PURE__*/React.createElement(Comp, _extends({
    className: "ik-tag",
    type: clickable ? "button" : undefined,
    "data-clickable": clickable ? "true" : undefined,
    "data-selected": selected ? "true" : undefined,
    onClick: onClick
  }, rest), icon && /*#__PURE__*/React.createElement("span", {
    className: "ik-tag__ico"
  }, icon), children, onRemove && /*#__PURE__*/React.createElement("span", {
    className: "ik-tag__x",
    role: "button",
    "aria-label": "Remove",
    onClick: e => {
      e.stopPropagation();
      onRemove(e);
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "11",
    height: "11",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "2.5",
    strokeLinecap: "round"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M18 6 6 18M6 6l12 12"
  }))));
}
Object.assign(__ds_scope, { Tag });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Tag.jsx", error: String((e && e.message) || e) }); }

// components/forms/Input.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useInputStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-field { display: flex; flex-direction: column; gap: 0.375rem; font-family: var(--font-sans); }
  .ik-field__label { font-size: var(--text-label); font-weight: var(--weight-semibold); color: var(--text-strong); letter-spacing: var(--tracking-snug); }
  .ik-field__req { color: var(--danger); margin-left: 0.15em; }
  .ik-field__optional { color: var(--text-subtle); font-weight: var(--weight-regular); margin-left: 0.4em; }

  .ik-input {
    display: flex; align-items: center; gap: 0.5rem;
    background: var(--surface-card); border: 1px solid var(--border-default);
    border-radius: var(--radius-md); padding: 0 0.75rem; height: 2.625rem;
    box-shadow: var(--shadow-xs);
    transition: border-color var(--dur-fast) var(--ease-out), box-shadow var(--dur-fast) var(--ease-out);
  }
  .ik-input[data-size="sm"] { height: 2.25rem; border-radius: var(--radius-sm); }
  .ik-input[data-size="lg"] { height: 3rem; }
  .ik-input:hover { border-color: var(--border-strong); }
  .ik-input[data-focused="true"] { border-color: var(--accent); box-shadow: var(--focus-ring); }
  .ik-input[data-invalid="true"] { border-color: var(--danger); }
  .ik-input[data-invalid="true"][data-focused="true"] { box-shadow: 0 0 0 4px rgba(229,72,77,0.18); }
  .ik-input[data-disabled="true"] { background: var(--surface-sunken); opacity: 0.65; cursor: not-allowed; }

  .ik-input__el {
    flex: 1 1 auto; min-width: 0; border: none; outline: none; background: transparent;
    font-family: inherit; font-size: var(--text-body-sm); color: var(--text-strong);
    height: 100%; padding: 0;
  }
  .ik-input__el::placeholder { color: var(--text-subtle); }
  .ik-input__affix { display: inline-flex; align-items: center; color: var(--text-muted); flex: 0 0 auto; font-size: var(--text-body-sm); }
  .ik-input__prefix-text { color: var(--text-muted); font-size: var(--text-body-sm); white-space: nowrap; }

  .ik-field__hint { font-size: var(--text-caption); color: var(--text-muted); }
  .ik-field__hint[data-invalid="true"] { color: var(--danger-text); }
  `;
  const el = document.createElement("style");
  el.id = "ik-input-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function Input({
  label,
  hint,
  error,
  size = "md",
  prefix,
  suffix,
  prefixText,
  required = false,
  optional = false,
  disabled = false,
  id,
  ...rest
}) {
  useInputStyles();
  const [focused, setFocused] = React.useState(false);
  const autoId = React.useId();
  const fieldId = id || autoId;
  const invalid = !!error;
  return /*#__PURE__*/React.createElement("div", {
    className: "ik-field"
  }, label && /*#__PURE__*/React.createElement("label", {
    className: "ik-field__label",
    htmlFor: fieldId
  }, label, required && /*#__PURE__*/React.createElement("span", {
    className: "ik-field__req"
  }, "*"), optional && /*#__PURE__*/React.createElement("span", {
    className: "ik-field__optional"
  }, "optional")), /*#__PURE__*/React.createElement("div", {
    className: "ik-input",
    "data-size": size,
    "data-focused": focused ? "true" : undefined,
    "data-invalid": invalid ? "true" : undefined,
    "data-disabled": disabled ? "true" : undefined
  }, prefix && /*#__PURE__*/React.createElement("span", {
    className: "ik-input__affix"
  }, prefix), prefixText && /*#__PURE__*/React.createElement("span", {
    className: "ik-input__prefix-text"
  }, prefixText), /*#__PURE__*/React.createElement("input", _extends({
    id: fieldId,
    className: "ik-input__el",
    disabled: disabled,
    "aria-invalid": invalid || undefined,
    onFocus: e => {
      setFocused(true);
      rest.onFocus?.(e);
    },
    onBlur: e => {
      setFocused(false);
      rest.onBlur?.(e);
    }
  }, rest)), suffix && /*#__PURE__*/React.createElement("span", {
    className: "ik-input__affix"
  }, suffix)), (error || hint) && /*#__PURE__*/React.createElement("span", {
    className: "ik-field__hint",
    "data-invalid": invalid ? "true" : undefined
  }, error || hint));
}
Object.assign(__ds_scope, { Input });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Input.jsx", error: String((e && e.message) || e) }); }

// components/forms/Switch.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useSwitchStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-switch { display: inline-flex; align-items: center; gap: 0.625rem; cursor: pointer; font-family: var(--font-sans); user-select: none; }
  .ik-switch[data-disabled="true"] { cursor: not-allowed; opacity: 0.55; }
  .ik-switch__track {
    position: relative; flex: 0 0 auto; width: 2.5rem; height: 1.5rem;
    background: var(--ink-200); border-radius: var(--radius-pill);
    transition: background var(--dur-base) var(--ease-out);
  }
  .ik-switch__track[data-size="sm"] { width: 2rem; height: 1.2rem; }
  .ik-switch__thumb {
    position: absolute; top: 2px; left: 2px; width: 1.25rem; height: 1.25rem;
    background: #fff; border-radius: 50%; box-shadow: var(--shadow-sm);
    transition: transform var(--dur-base) var(--ease-spring);
  }
  .ik-switch__track[data-size="sm"] .ik-switch__thumb { width: 0.95rem; height: 0.95rem; }
  .ik-switch input { position: absolute; opacity: 0; width: 100%; height: 100%; margin: 0; cursor: inherit; }
  .ik-switch input:checked + .ik-switch__track { background: var(--accent); }
  .ik-switch input:checked + .ik-switch__track .ik-switch__thumb { transform: translateX(1rem); }
  .ik-switch__track[data-size="sm"] .ik-switch__thumb { left: 2px; }
  .ik-switch input:checked + .ik-switch__track[data-size="sm"] .ik-switch__thumb { transform: translateX(0.8rem); }
  .ik-switch input:focus-visible + .ik-switch__track { box-shadow: var(--focus-ring); }
  .ik-switch__label { display: flex; flex-direction: column; gap: 0.1rem; }
  .ik-switch__title { font-size: var(--text-body-sm); font-weight: var(--weight-medium); color: var(--text-strong); }
  .ik-switch__desc { font-size: var(--text-caption); color: var(--text-muted); }
  `;
  const el = document.createElement("style");
  el.id = "ik-switch-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function Switch({
  checked,
  defaultChecked,
  onChange,
  label,
  description,
  size = "md",
  disabled = false,
  id,
  ...rest
}) {
  useSwitchStyles();
  const autoId = React.useId();
  const fieldId = id || autoId;
  return /*#__PURE__*/React.createElement("label", {
    className: "ik-switch",
    htmlFor: fieldId,
    "data-disabled": disabled ? "true" : undefined
  }, /*#__PURE__*/React.createElement("input", _extends({
    id: fieldId,
    type: "checkbox",
    role: "switch",
    checked: checked,
    defaultChecked: defaultChecked,
    onChange: onChange,
    disabled: disabled
  }, rest)), /*#__PURE__*/React.createElement("span", {
    className: "ik-switch__track",
    "data-size": size
  }, /*#__PURE__*/React.createElement("span", {
    className: "ik-switch__thumb"
  })), (label || description) && /*#__PURE__*/React.createElement("span", {
    className: "ik-switch__label"
  }, label && /*#__PURE__*/React.createElement("span", {
    className: "ik-switch__title"
  }, label), description && /*#__PURE__*/React.createElement("span", {
    className: "ik-switch__desc"
  }, description)));
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Switch.jsx", error: String((e && e.message) || e) }); }

// components/forms/Textarea.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useTextareaStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-textarea-field { display: flex; flex-direction: column; gap: 0.375rem; font-family: var(--font-sans); }
  .ik-textarea-field__label { font-size: var(--text-label); font-weight: var(--weight-semibold); color: var(--text-strong); }
  .ik-textarea {
    width: 100%; resize: vertical; min-height: 5.5rem;
    background: var(--surface-card); border: 1px solid var(--border-default);
    border-radius: var(--radius-md); padding: 0.625rem 0.75rem; box-shadow: var(--shadow-xs);
    font-family: inherit; font-size: var(--text-body-sm); line-height: var(--leading-normal);
    color: var(--text-strong);
    transition: border-color var(--dur-fast) var(--ease-out), box-shadow var(--dur-fast) var(--ease-out);
  }
  .ik-textarea::placeholder { color: var(--text-subtle); }
  .ik-textarea:hover { border-color: var(--border-strong); }
  .ik-textarea:focus { outline: none; border-color: var(--accent); box-shadow: var(--focus-ring); }
  .ik-textarea[aria-invalid="true"] { border-color: var(--danger); }
  .ik-textarea:disabled { background: var(--surface-sunken); opacity: 0.65; cursor: not-allowed; }
  .ik-textarea-field__foot { display: flex; justify-content: space-between; gap: 1rem; }
  .ik-textarea-field__hint { font-size: var(--text-caption); color: var(--text-muted); }
  .ik-textarea-field__hint[data-invalid="true"] { color: var(--danger-text); }
  .ik-textarea-field__count { font-size: var(--text-caption); color: var(--text-subtle); font-variant-numeric: tabular-nums; margin-left: auto; }
  .ik-textarea-field__count[data-over="true"] { color: var(--danger-text); }
  `;
  const el = document.createElement("style");
  el.id = "ik-textarea-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function Textarea({
  label,
  hint,
  error,
  maxLength,
  showCount = false,
  value,
  defaultValue,
  id,
  disabled = false,
  ...rest
}) {
  useTextareaStyles();
  const autoId = React.useId();
  const fieldId = id || autoId;
  const invalid = !!error;
  const [internal, setInternal] = React.useState(defaultValue || "");
  const len = (value !== undefined ? value : internal)?.length || 0;
  const over = maxLength ? len > maxLength : false;
  return /*#__PURE__*/React.createElement("div", {
    className: "ik-textarea-field"
  }, label && /*#__PURE__*/React.createElement("label", {
    className: "ik-textarea-field__label",
    htmlFor: fieldId
  }, label), /*#__PURE__*/React.createElement("textarea", _extends({
    id: fieldId,
    className: "ik-textarea",
    maxLength: maxLength,
    disabled: disabled,
    "aria-invalid": invalid || undefined,
    value: value,
    defaultValue: defaultValue,
    onChange: e => {
      if (value === undefined) setInternal(e.target.value);
      rest.onChange?.(e);
    }
  }, rest)), (error || hint || showCount) && /*#__PURE__*/React.createElement("div", {
    className: "ik-textarea-field__foot"
  }, (error || hint) && /*#__PURE__*/React.createElement("span", {
    className: "ik-textarea-field__hint",
    "data-invalid": invalid ? "true" : undefined
  }, error || hint), showCount && maxLength && /*#__PURE__*/React.createElement("span", {
    className: "ik-textarea-field__count",
    "data-over": over ? "true" : undefined
  }, len, "/", maxLength)));
}
Object.assign(__ds_scope, { Textarea });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/forms/Textarea.jsx", error: String((e && e.message) || e) }); }

// components/navigation/Tabs.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useTabsStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-tabs { display: inline-flex; font-family: var(--font-sans); }
  /* segmented (default) */
  .ik-tabs[data-variant="segmented"] {
    padding: 0.25rem; gap: 0.125rem; background: var(--surface-sunken);
    border: 1px solid var(--border-subtle); border-radius: var(--radius-md);
  }
  .ik-tabs[data-variant="segmented"] .ik-tab {
    border-radius: var(--radius-sm); padding: 0.375rem 0.75rem; height: 2rem;
  }
  .ik-tabs[data-variant="segmented"] .ik-tab[data-active="true"] {
    background: var(--surface-card); color: var(--text-strong); box-shadow: var(--shadow-sm);
  }
  /* underline */
  .ik-tabs[data-variant="underline"] {
    gap: 0.25rem; border-bottom: 1px solid var(--border-subtle);
  }
  .ik-tabs[data-variant="underline"] .ik-tab {
    height: 2.5rem; padding: 0 0.5rem; border-radius: 0;
    border-bottom: 2px solid transparent; margin-bottom: -1px;
  }
  .ik-tabs[data-variant="underline"] .ik-tab[data-active="true"] {
    color: var(--text-strong); border-bottom-color: var(--accent);
  }

  .ik-tab {
    display: inline-flex; align-items: center; gap: 0.4rem; border: none;
    background: transparent; cursor: pointer; color: var(--text-muted);
    font-family: inherit; font-size: var(--text-body-sm); font-weight: var(--weight-medium);
    white-space: nowrap; transition: color var(--dur-fast) var(--ease-out),
      background var(--dur-fast) var(--ease-out), box-shadow var(--dur-fast) var(--ease-out);
  }
  .ik-tab:hover { color: var(--text-strong); }
  .ik-tab:focus-visible { outline: none; box-shadow: var(--focus-ring); }
  .ik-tab[data-active="true"] { color: var(--text-strong); font-weight: var(--weight-semibold); }
  .ik-tab__count {
    font-size: var(--text-overline); font-weight: var(--weight-semibold);
    padding: 0.05rem 0.3rem; border-radius: var(--radius-pill);
    background: var(--ink-100); color: var(--text-muted); font-variant-numeric: tabular-nums;
  }
  .ik-tab[data-active="true"] .ik-tab__count { background: var(--accent-soft); color: var(--accent-text); }
  `;
  const el = document.createElement("style");
  el.id = "ik-tabs-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function Tabs({
  items = [],
  value,
  defaultValue,
  onChange,
  variant = "segmented",
  ...rest
}) {
  useTabsStyles();
  const [internal, setInternal] = React.useState(defaultValue ?? items[0]?.value);
  const active = value !== undefined ? value : internal;
  const select = v => {
    if (value === undefined) setInternal(v);
    onChange?.(v);
  };
  return /*#__PURE__*/React.createElement("div", _extends({
    className: "ik-tabs",
    role: "tablist",
    "data-variant": variant
  }, rest), items.map(it => /*#__PURE__*/React.createElement("button", {
    key: it.value,
    type: "button",
    role: "tab",
    "aria-selected": active === it.value,
    className: "ik-tab",
    "data-active": active === it.value ? "true" : undefined,
    onClick: () => select(it.value)
  }, it.icon && /*#__PURE__*/React.createElement("span", {
    className: "ik-tab__ico"
  }, it.icon), it.label, it.count != null && /*#__PURE__*/React.createElement("span", {
    className: "ik-tab__count"
  }, it.count))));
}
Object.assign(__ds_scope, { Tabs });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/Tabs.jsx", error: String((e && e.message) || e) }); }

// components/product/LinkRow.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useLinkRowStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-linkrow {
    display: flex; align-items: center; gap: 0.875rem; width: 100%;
    text-align: left; text-decoration: none; cursor: pointer;
    background: var(--surface-card); color: var(--text-strong);
    border: 1px solid var(--border-default); border-radius: var(--radius-lg);
    padding: 0.75rem 0.875rem; box-shadow: var(--shadow-sm);
    transition: transform var(--dur-base) var(--ease-out),
                box-shadow var(--dur-base) var(--ease-out),
                border-color var(--dur-base) var(--ease-out);
  }
  .ik-linkrow:hover { transform: translateY(-2px); box-shadow: var(--shadow-md); border-color: var(--border-strong); }
  .ik-linkrow:active { transform: translateY(0); box-shadow: var(--shadow-sm); }
  .ik-linkrow:focus-visible { outline: none; box-shadow: var(--focus-ring); }

  .ik-linkrow__thumb {
    flex: 0 0 auto; width: 2.75rem; height: 2.75rem; border-radius: var(--radius-md);
    overflow: hidden; background: var(--accent-soft); color: var(--accent-text);
    display: inline-flex; align-items: center; justify-content: center; font-weight: var(--weight-semibold);
  }
  .ik-linkrow__thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .ik-linkrow__body { flex: 1 1 auto; min-width: 0; display: flex; flex-direction: column; gap: 0.1rem; }
  .ik-linkrow__title { font-size: var(--text-body); font-weight: var(--weight-semibold); letter-spacing: var(--tracking-snug);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .ik-linkrow__sub { font-size: var(--text-caption); color: var(--text-muted);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .ik-linkrow__trail { flex: 0 0 auto; display: inline-flex; align-items: center; gap: 0.5rem; color: var(--text-subtle); }
  .ik-linkrow__arrow { transition: transform var(--dur-base) var(--ease-out); }
  .ik-linkrow:hover .ik-linkrow__arrow { transform: translate(2px, -2px); color: var(--accent-text); }

  /* feature: full-bleed image hero tile */
  .ik-linkrow[data-layout="feature"] { flex-direction: column; align-items: stretch; gap: 0; padding: 0; overflow: hidden; }
  .ik-linkrow[data-layout="feature"] .ik-linkrow__hero { width: 100%; aspect-ratio: 16 / 9; background: var(--ink-100); overflow: hidden; }
  .ik-linkrow[data-layout="feature"] .ik-linkrow__hero img { width: 100%; height: 100%; object-fit: cover; display: block; }
  .ik-linkrow[data-layout="feature"] .ik-linkrow__featbody { display: flex; align-items: center; gap: 0.75rem; padding: 0.875rem 1rem; }
  .ik-linkrow[data-layout="feature"] .ik-linkrow__body { flex: 1 1 auto; }
  `;
  const el = document.createElement("style");
  el.id = "ik-linkrow-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
function LinkRow({
  title,
  subtitle,
  href,
  thumbnail,
  icon,
  image,
  layout = "row",
  trailing,
  ...rest
}) {
  useLinkRowStyles();
  const arrow = /*#__PURE__*/React.createElement("span", {
    className: "ik-linkrow__arrow",
    "aria-hidden": "true"
  }, /*#__PURE__*/React.createElement("svg", {
    width: "18",
    height: "18",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "2",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M7 17 17 7M7 7h10v10"
  })));
  if (layout === "feature") {
    return /*#__PURE__*/React.createElement("a", _extends({
      className: "ik-linkrow",
      "data-layout": "feature",
      href: href
    }, rest), /*#__PURE__*/React.createElement("span", {
      className: "ik-linkrow__hero"
    }, image && /*#__PURE__*/React.createElement("img", {
      src: image,
      alt: ""
    })), /*#__PURE__*/React.createElement("span", {
      className: "ik-linkrow__featbody"
    }, /*#__PURE__*/React.createElement("span", {
      className: "ik-linkrow__body"
    }, /*#__PURE__*/React.createElement("span", {
      className: "ik-linkrow__title"
    }, title), subtitle && /*#__PURE__*/React.createElement("span", {
      className: "ik-linkrow__sub"
    }, subtitle)), /*#__PURE__*/React.createElement("span", {
      className: "ik-linkrow__trail"
    }, trailing, arrow)));
  }
  return /*#__PURE__*/React.createElement("a", _extends({
    className: "ik-linkrow",
    "data-layout": "row",
    href: href
  }, rest), (thumbnail || icon) && /*#__PURE__*/React.createElement("span", {
    className: "ik-linkrow__thumb"
  }, thumbnail ? /*#__PURE__*/React.createElement("img", {
    src: thumbnail,
    alt: ""
  }) : icon), /*#__PURE__*/React.createElement("span", {
    className: "ik-linkrow__body"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ik-linkrow__title"
  }, title), subtitle && /*#__PURE__*/React.createElement("span", {
    className: "ik-linkrow__sub"
  }, subtitle)), /*#__PURE__*/React.createElement("span", {
    className: "ik-linkrow__trail"
  }, trailing, arrow));
}
Object.assign(__ds_scope, { LinkRow });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/product/LinkRow.jsx", error: String((e && e.message) || e) }); }

// components/product/Stat.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
let injected = false;
function useStatStyles() {
  if (injected || typeof document === "undefined") return;
  injected = true;
  const css = `
  .ik-stat { display: flex; flex-direction: column; gap: 0.375rem; font-family: var(--font-sans); }
  .ik-stat__label { display: inline-flex; align-items: center; gap: 0.4rem;
    font-size: var(--text-caption); font-weight: var(--weight-medium); color: var(--text-muted); }
  .ik-stat__label-ico { display: inline-flex; color: var(--text-subtle); }
  .ik-stat__value { font-size: 1.875rem; font-weight: var(--weight-bold); color: var(--text-strong);
    letter-spacing: var(--tracking-tight); line-height: 1.1; font-variant-numeric: tabular-nums; }
  .ik-stat[data-size="sm"] .ik-stat__value { font-size: 1.375rem; }
  .ik-stat[data-size="lg"] .ik-stat__value { font-size: 2.5rem; }
  .ik-stat__foot { display: inline-flex; align-items: center; gap: 0.5rem; }
  .ik-stat__delta { display: inline-flex; align-items: center; gap: 0.2rem;
    font-size: var(--text-caption); font-weight: var(--weight-semibold); font-variant-numeric: tabular-nums; }
  .ik-stat__delta[data-dir="up"]   { color: var(--positive-text); }
  .ik-stat__delta[data-dir="down"] { color: var(--danger-text); }
  .ik-stat__delta[data-dir="flat"] { color: var(--text-muted); }
  .ik-stat__caption { font-size: var(--text-caption); color: var(--text-subtle); }
  `;
  const el = document.createElement("style");
  el.id = "ik-stat-styles";
  el.textContent = css;
  document.head.appendChild(el);
}
const arrows = {
  up: "M7 17 17 7M9 7h8v8",
  down: "M7 7 17 17M17 9v8H9",
  flat: "M5 12h14"
};
function Stat({
  label,
  value,
  delta,
  direction,
  caption,
  icon,
  size = "md",
  ...rest
}) {
  useStatStyles();
  const dir = direction || (delta == null ? undefined : "flat");
  return /*#__PURE__*/React.createElement("div", _extends({
    className: "ik-stat",
    "data-size": size
  }, rest), /*#__PURE__*/React.createElement("span", {
    className: "ik-stat__label"
  }, icon && /*#__PURE__*/React.createElement("span", {
    className: "ik-stat__label-ico"
  }, icon), label), /*#__PURE__*/React.createElement("span", {
    className: "ik-stat__value"
  }, value), (delta != null || caption) && /*#__PURE__*/React.createElement("span", {
    className: "ik-stat__foot"
  }, delta != null && /*#__PURE__*/React.createElement("span", {
    className: "ik-stat__delta",
    "data-dir": dir
  }, /*#__PURE__*/React.createElement("svg", {
    width: "13",
    height: "13",
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: "2.5",
    strokeLinecap: "round",
    strokeLinejoin: "round"
  }, /*#__PURE__*/React.createElement("path", {
    d: arrows[dir] || arrows.flat
  })), delta), caption && /*#__PURE__*/React.createElement("span", {
    className: "ik-stat__caption"
  }, caption)));
}
Object.assign(__ds_scope, { Stat });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/product/Stat.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/AddComposer.jsx
try { (() => {
/* AddComposer — the registry-powered "Add" modal, now TYPE-AWARE.
   One Add surface, genuinely different branches (Phase 20: "one adder,
   template-filtered branches"):
     • Link / Booking / Offer -> stacked link (URL + title + presentation)
     • Video / Music          -> media link with a Style choice (card vs button) + live preview
     • Social                 -> adds to the PLATFORM ICON STRIP, not the link list
   Detection (icon, name, suggested type) is deterministic — no model call. */

const {
  useState: ac_useState,
  useEffect: ac_useEffect,
  useMemo: ac_useMemo
} = React;
const AC_SVC = window.SERVICES;
const TYPES = [{
  id: "suggested",
  label: "Suggested",
  verb: "Add to your page"
}, {
  id: "link",
  label: "Link",
  verb: "Add a link"
}, {
  id: "social",
  label: "Social",
  verb: "Add a platform"
}, {
  id: "video",
  label: "Video",
  verb: "Add a video"
}, {
  id: "music",
  label: "Music",
  verb: "Add music"
}, {
  id: "booking",
  label: "Booking",
  verb: "Add a booking link"
}, {
  id: "offer",
  label: "Offer",
  verb: "Add an offer"
}];
const SUGGESTED = ["instagram", "youtube", "tiktok", "spotify", "substack", "calendly", "gumroad", "linkedin"];
const PLACEHOLDER = {
  link: "https://example.com/your-page",
  social: "Profile URL or @handle",
  video: "https://youtube.com/watch?v=…",
  music: "https://open.spotify.com/…",
  booking: "https://calendly.com/you",
  offer: "https://gumroad.com/l/…",
  suggested: "Paste a link, or search a service…"
};
function AddComposer({
  open,
  onClose,
  onAdd,
  onAddSocial,
  onSetLead,
  initialType = "suggested"
}) {
  const [type, setType] = ac_useState(initialType);
  const [url, setUrl] = ac_useState("");
  const [title, setTitle] = ac_useState("");
  const [variant, setVariant] = ac_useState("classic"); // link presentation
  const [style, setStyle] = ac_useState("card"); // video/music style

  ac_useEffect(() => {
    if (open) {
      setType(initialType);
      setUrl("");
      setTitle("");
      setVariant("classic");
      setStyle("card");
    }
  }, [open, initialType]);
  const detected = ac_useMemo(() => window.detectService(url), [url]);
  const svc = detected ? AC_SVC[detected] : null;
  const meta = TYPES.find(t => t.id === type) || TYPES[0];
  if (!open) return null;
  const close = () => onClose();
  const canSubmit = url.trim().length > 0;
  const submit = () => {
    if (!canSubmit) return;
    const isMedia = type === "video" || type === "music";
    if (type === "social") {
      onAddSocial({
        id: "s" + Date.now(),
        service: detected || "x",
        url: url.trim()
      });
    } else if (isMedia && style === "card") {
      // a media "card" takes over the Latest / Lead Media hero slot
      onSetLead({
        id: "lead",
        service: detected || (type === "video" ? "youtube" : "spotify"),
        title: title.trim() || (svc ? svc.name : "Featured"),
        desc: "",
        url: url.trim(),
        thumb: ""
      });
    } else {
      onAdd({
        id: "l" + Date.now(),
        title: title.trim() || (svc ? svc.name : "New link"),
        url: url.trim(),
        service: detected || null,
        kind: isMedia ? type : undefined,
        featured: isMedia ? false : variant === "featured"
      });
    }
    close();
  };
  const prefill = key => {
    const s = AC_SVC[key];
    setType(s.kind === "social" ? "social" : ["video", "music", "booking", "offer", "link"].includes(s.kind) ? s.kind : "link");
    setUrl("https://" + s.domains[0] + "/");
    setTitle(s.kind === "social" ? "" : s.name);
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "ac-overlay",
    onClick: close
  }, /*#__PURE__*/React.createElement("div", {
    className: "ac",
    onClick: e => e.stopPropagation(),
    role: "dialog",
    "aria-label": meta.verb
  }, /*#__PURE__*/React.createElement("header", {
    className: "ac__head"
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    className: "ac__eyebrow"
  }, "Add to your page"), /*#__PURE__*/React.createElement("h2", {
    className: "ac__title"
  }, meta.verb)), /*#__PURE__*/React.createElement("button", {
    className: "ac__close",
    onClick: close,
    "aria-label": "Close"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "x",
    size: 18
  }))), /*#__PURE__*/React.createElement("div", {
    className: "ac__types"
  }, TYPES.map(t => /*#__PURE__*/React.createElement("button", {
    key: t.id,
    className: "ac__type",
    "data-on": type === t.id ? "true" : undefined,
    onClick: () => setType(t.id)
  }, t.label))), /*#__PURE__*/React.createElement("div", {
    className: "ac__body"
  }, type === "suggested" && /*#__PURE__*/React.createElement("div", {
    className: "ac__suggest"
  }, /*#__PURE__*/React.createElement("div", {
    className: "ac__hint"
  }, "Tap a service to start \u2014 we\u2019ll detect the icon and set things up."), /*#__PURE__*/React.createElement("div", {
    className: "ac__chips"
  }, SUGGESTED.map(k => /*#__PURE__*/React.createElement("button", {
    key: k,
    className: "ac__chip",
    onClick: () => prefill(k)
  }, /*#__PURE__*/React.createElement(window.BrandIcon, {
    slug: AC_SVC[k].slug,
    color: AC_SVC[k].color,
    size: 18
  }), AC_SVC[k].name))), /*#__PURE__*/React.createElement("div", {
    className: "ac__or"
  }, "or paste any link below")), /*#__PURE__*/React.createElement("label", {
    className: "ac__field"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ac__flabel"
  }, type === "social" ? "Profile link" : "Link"), /*#__PURE__*/React.createElement("div", {
    className: "ac__url",
    "data-detected": svc ? "true" : undefined
  }, /*#__PURE__*/React.createElement("span", {
    className: "ac__url-ico"
  }, svc ? /*#__PURE__*/React.createElement(window.BrandIcon, {
    slug: svc.slug,
    color: svc.color,
    size: 18
  }) : /*#__PURE__*/React.createElement(Icon, {
    name: "link",
    size: 17
  })), /*#__PURE__*/React.createElement("input", {
    className: "ac__input",
    placeholder: PLACEHOLDER[type],
    value: url,
    onChange: e => setUrl(e.target.value),
    autoFocus: true
  }), svc && /*#__PURE__*/React.createElement("span", {
    className: "ac__detected"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "check",
    size: 13,
    stroke: 3
  }), " ", svc.name)), type === "social" && /*#__PURE__*/React.createElement("span", {
    className: "ac__sub"
  }, svc ? `Adds a ${svc.name} icon to your platform strip.` : "Adds an icon to your platform strip near your name.")), type !== "social" && /*#__PURE__*/React.createElement("label", {
    className: "ac__field"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ac__flabel"
  }, "Title ", /*#__PURE__*/React.createElement("span", {
    className: "ac__opt"
  }, "\u2014 shows on the button")), /*#__PURE__*/React.createElement("input", {
    className: "ac__input ac__input--bare",
    placeholder: svc ? svc.name : "e.g. Book a travel shoot",
    value: title,
    onChange: e => setTitle(e.target.value)
  })), (type === "link" || type === "booking" || type === "offer") && /*#__PURE__*/React.createElement("div", {
    className: "ac__field"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ac__flabel"
  }, "Presentation"), /*#__PURE__*/React.createElement("div", {
    className: "ac__pres"
  }, /*#__PURE__*/React.createElement("button", {
    className: "ac__pres-opt",
    "data-on": variant === "classic" ? "true" : undefined,
    onClick: () => setVariant("classic")
  }, /*#__PURE__*/React.createElement("span", {
    className: "ac__pres-demo ac__pres-demo--row"
  }, /*#__PURE__*/React.createElement("span", null)), /*#__PURE__*/React.createElement("span", {
    className: "ac__pres-name"
  }, "Classic link"), /*#__PURE__*/React.createElement("span", {
    className: "ac__pres-sub"
  }, "A clean tappable row")), /*#__PURE__*/React.createElement("button", {
    className: "ac__pres-opt",
    "data-on": variant === "featured" ? "true" : undefined,
    onClick: () => setVariant("featured")
  }, /*#__PURE__*/React.createElement("span", {
    className: "ac__pres-demo ac__pres-demo--card"
  }, /*#__PURE__*/React.createElement("span", null)), /*#__PURE__*/React.createElement("span", {
    className: "ac__pres-name"
  }, "Featured"), /*#__PURE__*/React.createElement("span", {
    className: "ac__pres-sub"
  }, "Stands out, larger")))), (type === "video" || type === "music") && /*#__PURE__*/React.createElement("div", {
    className: "ac__field"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ac__flabel"
  }, "Style"), /*#__PURE__*/React.createElement("div", {
    className: "ac__seg-lg"
  }, /*#__PURE__*/React.createElement("button", {
    "data-on": style === "card" ? "true" : undefined,
    onClick: () => setStyle("card")
  }, type === "video" ? "Video card" : "Player card"), /*#__PURE__*/React.createElement("button", {
    "data-on": style === "button" ? "true" : undefined,
    onClick: () => setStyle("button")
  }, "Button")), /*#__PURE__*/React.createElement("div", {
    className: "ac__preview"
  }, style === "card" ? /*#__PURE__*/React.createElement("div", {
    className: "ac__prev-card"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ac__prev-play"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "play",
    size: 18
  })), /*#__PURE__*/React.createElement("span", {
    className: "ac__prev-badge"
  }, svc ? /*#__PURE__*/React.createElement(window.BrandIcon, {
    slug: svc.slug,
    color: "white",
    size: 13
  }) : /*#__PURE__*/React.createElement(Icon, {
    name: "play",
    size: 12
  })), /*#__PURE__*/React.createElement("span", {
    className: "ac__prev-title"
  }, title || "Your link")) : /*#__PURE__*/React.createElement("div", {
    className: "ac__prev-btn"
  }, svc && /*#__PURE__*/React.createElement(window.BrandIcon, {
    slug: svc.slug,
    color: svc.color,
    size: 16
  }), title || (svc ? svc.name : "Your link"))), /*#__PURE__*/React.createElement("span", {
    className: "ac__sub"
  }, style === "card" ? "Takes over the “Latest” lead slot at the top of your page." : "Appears as a tappable button in your link list."))), /*#__PURE__*/React.createElement("footer", {
    className: "ac__foot"
  }, /*#__PURE__*/React.createElement("span", {
    className: "ac__foot-note"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "zap",
    size: 13
  }), " Saves instantly \u2014 no AI needed"), /*#__PURE__*/React.createElement("div", {
    className: "ac__foot-actions"
  }, /*#__PURE__*/React.createElement("button", {
    className: "ac__btn ac__btn--ghost",
    onClick: close
  }, "Cancel"), /*#__PURE__*/React.createElement("button", {
    className: "ac__btn ac__btn--primary",
    disabled: !canSubmit,
    onClick: submit
  }, type === "social" ? "Add to strip" : "Add to page")))));
}
Object.assign(window, {
  AddComposer
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/AddComposer.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/BlockComposer.jsx
try { (() => {
/* BlockComposer — the "Add a section" chooser. Where the AddComposer adds an
   ITEM into an existing block (a link, a platform icon), this adds a whole
   BLOCK (a section) to the page. Block-general per Phase 20: the menu is the
   set of block types this template supports. New block types just register a
   card here. Picking one inserts a default block at the target index and
   selects it so the inspector opens immediately. */

const {
  useEffect: bc_useEffect
} = React;

/* Each card carries a tiny CSS-drawn preview of what the block looks like. */
const BLOCK_TYPES = [{
  type: "links",
  name: "Links",
  desc: "A stacked list of tappable link buttons.",
  preview: "links"
}, {
  type: "gallery",
  name: "Image gallery",
  desc: "A grid of photos — great for portfolios.",
  preview: "gallery",
  isNew: true
}, {
  type: "form",
  name: "Form",
  desc: "Capture emails or messages right on the page.",
  preview: "form",
  isNew: true
}, {
  type: "socials",
  name: "Social strip",
  desc: "A compact row of platform icons.",
  preview: "socials"
}, {
  type: "profile",
  name: "Profile",
  desc: "Avatar, name, handle and a short bio.",
  preview: "profile"
}];
function BlockPreview({
  kind
}) {
  if (kind === "links") return /*#__PURE__*/React.createElement("span", {
    className: "bc-prev bc-prev--links"
  }, /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null));
  if (kind === "gallery") return /*#__PURE__*/React.createElement("span", {
    className: "bc-prev bc-prev--gallery"
  }, /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null));
  if (kind === "form") return /*#__PURE__*/React.createElement("span", {
    className: "bc-prev bc-prev--form"
  }, /*#__PURE__*/React.createElement("i", {
    className: "bc-prev__bar"
  }), /*#__PURE__*/React.createElement("span", {
    className: "bc-prev__field"
  }), /*#__PURE__*/React.createElement("span", {
    className: "bc-prev__btn"
  }));
  if (kind === "socials") return /*#__PURE__*/React.createElement("span", {
    className: "bc-prev bc-prev--socials"
  }, /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null));
  if (kind === "profile") return /*#__PURE__*/React.createElement("span", {
    className: "bc-prev bc-prev--profile"
  }, /*#__PURE__*/React.createElement("i", {
    className: "bc-prev__avatar"
  }), /*#__PURE__*/React.createElement("i", {
    className: "bc-prev__bar"
  }), /*#__PURE__*/React.createElement("i", {
    className: "bc-prev__bar bc-prev__bar--sm"
  }));
  return null;
}
function BlockComposer({
  open,
  index,
  onClose,
  onPick
}) {
  bc_useEffect(() => {
    if (!open) return;
    const onKey = e => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);
  if (!open) return null;
  const close = () => onClose();
  const where = index === 0 ? "at the top" : null;
  return /*#__PURE__*/React.createElement("div", {
    className: "ac-overlay",
    onClick: close
  }, /*#__PURE__*/React.createElement("div", {
    className: "bc",
    onClick: e => e.stopPropagation(),
    role: "dialog",
    "aria-label": "Add a section"
  }, /*#__PURE__*/React.createElement("header", {
    className: "ac__head"
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    className: "ac__eyebrow"
  }, "Add a section"), /*#__PURE__*/React.createElement("h2", {
    className: "ac__title"
  }, "Choose a block", where ? /*#__PURE__*/React.createElement("span", {
    className: "bc__where"
  }, " \xB7 ", where) : null)), /*#__PURE__*/React.createElement("button", {
    className: "ac__close",
    onClick: close,
    "aria-label": "Close"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "x",
    size: 18
  }))), /*#__PURE__*/React.createElement("div", {
    className: "bc__grid"
  }, BLOCK_TYPES.map(b => /*#__PURE__*/React.createElement("button", {
    key: b.type,
    className: "bc-card",
    onClick: () => onPick(b.type, index)
  }, /*#__PURE__*/React.createElement("span", {
    className: "bc-card__art"
  }, /*#__PURE__*/React.createElement(BlockPreview, {
    kind: b.preview
  })), /*#__PURE__*/React.createElement("span", {
    className: "bc-card__meta"
  }, /*#__PURE__*/React.createElement("span", {
    className: "bc-card__name"
  }, b.name, b.isNew && /*#__PURE__*/React.createElement("span", {
    className: "bc-card__new"
  }, "New")), /*#__PURE__*/React.createElement("span", {
    className: "bc-card__desc"
  }, b.desc)), /*#__PURE__*/React.createElement("span", {
    className: "bc-card__add"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 16
  }))))), /*#__PURE__*/React.createElement("footer", {
    className: "bc__foot"
  }, /*#__PURE__*/React.createElement("div", {
    className: "bc__tpl"
  }, /*#__PURE__*/React.createElement("span", {
    className: "bc__tpl-ico"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "layout-template",
    size: 16
  })), /*#__PURE__*/React.createElement("span", {
    className: "bc__tpl-copy"
  }, /*#__PURE__*/React.createElement("span", {
    className: "bc__tpl-t"
  }, "Start from a template"), /*#__PURE__*/React.createElement("span", {
    className: "bc__tpl-s"
  }, "Pre-built block sets for links, stores & portfolios.")), /*#__PURE__*/React.createElement("span", {
    className: "bc__tpl-soon"
  }, "Soon")))));
}
Object.assign(window, {
  BlockComposer
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/BlockComposer.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/ContentPanel.jsx
try { (() => {
/* ContentTeam — the page's structure / outline. This is what the rail's
   "Content" now opens (it used to do nothing). It lists every block in page
   order and is the home for STRUCTURE operations: drag a compact row to
   reorder, toggle visibility, delete, and "Add block". Clicking a row selects
   that block, which swaps this team for the role-dispatched inspector.

   The dedicated outline/section-tree was a Phase-20 non-goal "until taller,
   richer templates need it" — gallery + form blocks are exactly that trigger. */

const {
  useState: cp_useState
} = window.React;
const CP_SVC = window.SERVICES;
const BLOCK_META = {
  profile: {
    icon: "user-round",
    name: "Profile"
  },
  socials: {
    icon: "share-2",
    name: "Social strip"
  },
  lead: {
    icon: "clapperboard",
    name: "Lead media"
  },
  links: {
    icon: "link",
    name: "Links"
  },
  gallery: {
    icon: "layout-grid",
    name: "Image gallery"
  },
  form: {
    icon: "mail",
    name: "Form"
  }
};
function blockSubtitle(blk) {
  switch (blk.type) {
    case "links":
      return `${blk.items.length} link${blk.items.length === 1 ? "" : "s"}`;
    case "socials":
      return `${blk.items.length} platform${blk.items.length === 1 ? "" : "s"}`;
    case "gallery":
      return `${blk.images.length} photo${blk.images.length === 1 ? "" : "s"}`;
    case "lead":
      return blk.title || "Featured link";
    case "form":
      return blk.heading || "Email capture";
    case "profile":
      return "Avatar · name · bio";
    default:
      return "";
  }
}
function ContentPanel({
  data,
  on
}) {
  const [drag, setDrag] = cp_useState(null); // index being dragged
  const [over, setOver] = cp_useState(null); // index being hovered

  const blocks = data.blocks;
  const drop = to => {
    if (drag !== null && to !== drag) on.reorderBlocks(drag, to > drag ? to - 1 : to);
    setDrag(null);
    setOver(null);
  };
  return /*#__PURE__*/React.createElement("aside", {
    className: "insp cp"
  }, /*#__PURE__*/React.createElement("header", {
    className: "insp__head"
  }, /*#__PURE__*/React.createElement("div", {
    className: "insp__role"
  }, "Structure")), /*#__PURE__*/React.createElement("div", {
    className: "insp__title"
  }, "Page blocks"), /*#__PURE__*/React.createElement("div", {
    className: "cp__note"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "grip-vertical",
    size: 14
  }), " Drag to reorder \xB7 click a block to edit it"), /*#__PURE__*/React.createElement("div", {
    className: "cp__list insp__body"
  }, blocks.map((blk, i) => {
    const meta = BLOCK_META[blk.type] || {
      icon: "square",
      name: "Block"
    };
    return /*#__PURE__*/React.createElement("div", {
      key: blk.id,
      className: "cp-row" + (blk.hidden ? " is-hidden" : "") + (over === i ? " is-over" : "") + (drag === i ? " is-dragging" : ""),
      draggable: true,
      onDragStart: () => setDrag(i),
      onDragOver: e => {
        e.preventDefault();
        setOver(i);
      },
      onDragEnd: () => {
        setDrag(null);
        setOver(null);
      },
      onDrop: e => {
        e.preventDefault();
        drop(i);
      },
      onClick: () => on.select(blk.id)
    }, /*#__PURE__*/React.createElement("span", {
      className: "cp-row__grip",
      title: "Drag to reorder"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "grip-vertical",
      size: 16
    })), /*#__PURE__*/React.createElement("span", {
      className: "cp-row__ico"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: meta.icon,
      size: 16
    })), /*#__PURE__*/React.createElement("span", {
      className: "cp-row__text"
    }, /*#__PURE__*/React.createElement("span", {
      className: "cp-row__name"
    }, meta.name), /*#__PURE__*/React.createElement("span", {
      className: "cp-row__sub"
    }, blockSubtitle(blk))), /*#__PURE__*/React.createElement("span", {
      className: "cp-row__actions",
      onClick: e => e.stopPropagation()
    }, /*#__PURE__*/React.createElement("button", {
      className: "cp-row__btn",
      title: blk.hidden ? "Show" : "Hide",
      "data-on": blk.hidden ? "true" : undefined,
      onClick: () => on.toggleBlockHidden(blk.id)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: blk.hidden ? "eye-off" : "eye",
      size: 15
    })), /*#__PURE__*/React.createElement("button", {
      className: "cp-row__btn cp-row__btn--danger",
      title: "Delete",
      onClick: () => on.removeBlock(blk.id)
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "trash-2",
      size: 15
    }))));
  }), /*#__PURE__*/React.createElement("div", {
    className: "cp-droptail" + (over === blocks.length ? " is-over" : ""),
    onDragOver: e => {
      e.preventDefault();
      setOver(blocks.length);
    },
    onDrop: e => {
      e.preventDefault();
      drop(blocks.length);
    }
  })), /*#__PURE__*/React.createElement("footer", {
    className: "cp__foot"
  }, /*#__PURE__*/React.createElement("button", {
    className: "cp__add",
    onClick: () => on.addBlockAt(data.blocks.length)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 17
  }), " Add block"), /*#__PURE__*/React.createElement("button", {
    className: "cp__tpl",
    disabled: true
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "layout-template",
    size: 15
  }), " Start from a template", /*#__PURE__*/React.createElement("span", {
    className: "cp__tpl-soon"
  }, "Soon"))));
}
Object.assign(window, {
  ContentPanel
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/ContentPanel.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/Copilot.jsx
try { (() => {
/* Copilot — the docked AI assistant. Collapsed to a pill by default; never
   required for basic edits. "The brain" — for batch / creative / messy work. */

const {
  useState: co_useState
} = window.React;
const PROMPTS = ["Add all my old socials", "Rewrite my bio shorter", "What should I feature?", "Make this a booking page"];
function Copilot({
  open,
  onToggle
}) {
  const [msgs, setMsgs] = co_useState([{
    from: "ai",
    text: "Hi — I can do the messy stuff. Try one of these, or just ask."
  }]);
  const [text, setText] = co_useState("");
  const send = t => {
    const v = (t || text).trim();
    if (!v) return;
    setMsgs(m => [...m, {
      from: "me",
      text: v
    }, {
      from: "ai",
      text: "On it — I’d turn that into deterministic edits you can preview and undo. (Demo: chat is wired to the same operations as the controls.)"
    }]);
    setText("");
  };
  if (!open) {
    return /*#__PURE__*/React.createElement("button", {
      className: "copilot-pill",
      onClick: onToggle
    }, /*#__PURE__*/React.createElement("span", {
      className: "copilot-pill__spark"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "sparkles",
      size: 16
    })), "Ask Ikiro");
  }
  return /*#__PURE__*/React.createElement("div", {
    className: "copilot"
  }, /*#__PURE__*/React.createElement("header", {
    className: "copilot__head"
  }, /*#__PURE__*/React.createElement("div", {
    className: "copilot__title"
  }, /*#__PURE__*/React.createElement("span", {
    className: "copilot__spark"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sparkles",
    size: 15
  })), " Ikiro copilot"), /*#__PURE__*/React.createElement("button", {
    className: "copilot__close",
    onClick: onToggle,
    "aria-label": "Close"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chevron-down",
    size: 18
  }))), /*#__PURE__*/React.createElement("div", {
    className: "copilot__log"
  }, msgs.map((m, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    className: "copilot__msg copilot__msg--" + m.from
  }, m.text))), /*#__PURE__*/React.createElement("div", {
    className: "copilot__chips"
  }, PROMPTS.map(p => /*#__PURE__*/React.createElement("button", {
    key: p,
    className: "copilot__chip",
    onClick: () => send(p)
  }, p))), /*#__PURE__*/React.createElement("div", {
    className: "copilot__compose"
  }, /*#__PURE__*/React.createElement("input", {
    className: "copilot__input",
    placeholder: "Ask Ikiro to help\u2026",
    value: text,
    onChange: e => setText(e.target.value),
    onKeyDown: e => e.key === "Enter" && send()
  }), /*#__PURE__*/React.createElement("button", {
    className: "copilot__send",
    onClick: () => send(),
    "aria-label": "Send"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "arrow-up",
    size: 17
  }))));
}
Object.assign(window, {
  Copilot
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/Copilot.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/Import.jsx
try { (() => {
/* Import — the bio-import wedge.
   Paste a Linktree / lnk.bio / Beacons URL → Ikiro reads what's public and
   rebuilds it as an owned Default Link Hub. Three stages:
     paste  → the front door (paste field + source auto-detect + trust)
     scan   → the registry doing real work (phase checklist + streaming matches)
     result → the rebuilt page (live LinkHubPage) + the import mapping + handoff
   Stage + URL persist to localStorage so a refresh keeps your place. */

const {
  useState: im_useState,
  useEffect: im_useEffect,
  useRef: im_useRef,
  useMemo: im_useMemo
} = React;
const STORE_STAGE = "ikiro_import_stage";
const STORE_URL = "ikiro_import_url";
function StepBar({
  stage
}) {
  const order = ["paste", "scan", "result"];
  const idx = order.indexOf(stage);
  const labels = [["1", "Paste"], ["2", "Import"], ["3", "Review"]];
  return /*#__PURE__*/React.createElement("div", {
    className: "imp-steps"
  }, labels.map((l, i) => {
    const state = i < idx ? "done" : i === idx ? "active" : "todo";
    return /*#__PURE__*/React.createElement(React.Fragment, {
      key: l[0]
    }, i > 0 && /*#__PURE__*/React.createElement("span", {
      className: "imp-step__line"
    }), /*#__PURE__*/React.createElement("span", {
      className: "imp-step",
      "data-state": state
    }, /*#__PURE__*/React.createElement("span", {
      className: "imp-step__n"
    }, state === "done" ? /*#__PURE__*/React.createElement(Icon, {
      name: "check",
      size: 11,
      stroke: 3
    }) : l[0]), l[1]));
  }));
}

/* ---------------- Stage 1: paste ---------------- */
function PasteStage({
  url,
  setUrl,
  onImport
}) {
  const src = im_useMemo(() => window.detectImportSource(url), [url]);
  const canGo = url.trim().length > 2;
  const SUPPORTED = [{
    name: "Linktree",
    color: "#43E660"
  }, {
    name: "Lnk.Bio",
    color: "#6C5CE7"
  }, {
    name: "Beacons",
    color: "#111111"
  }, {
    name: "Bio.link",
    color: "#2D8CFF"
  }, {
    name: "Campsite",
    color: "#FF6B4A"
  }];
  return /*#__PURE__*/React.createElement("div", {
    className: "imp-paste"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-eyebrow"
  }, "Import your bio link"), /*#__PURE__*/React.createElement("h1", {
    className: "imp-h1"
  }, "Bring your bio link ", /*#__PURE__*/React.createElement("em", null, "home.")), /*#__PURE__*/React.createElement("p", {
    className: "imp-sub"
  }, "Paste your Linktree, Beacons, or lnk.bio. Ikiro reads what\u2019s public and rebuilds it as a fast, no-JavaScript page you actually own \u2014 every destination preserved exactly."), /*#__PURE__*/React.createElement("form", {
    className: "imp-form",
    onSubmit: e => {
      e.preventDefault();
      if (canGo) onImport();
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-field"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-field__ico"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "link",
    size: 19
  })), /*#__PURE__*/React.createElement("input", {
    className: "imp-field__input",
    placeholder: "linktr.ee/yourname",
    value: url,
    onChange: e => setUrl(e.target.value),
    autoFocus: true,
    spellCheck: false
  }), src && /*#__PURE__*/React.createElement("span", {
    className: "imp-field__src"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "check",
    size: 13,
    stroke: 3
  }), " ", src.name), /*#__PURE__*/React.createElement("button", {
    type: "submit",
    className: "imp-go",
    disabled: !canGo
  }, "Rebuild my page ", /*#__PURE__*/React.createElement(Icon, {
    name: "arrow-right",
    size: 17
  })))), /*#__PURE__*/React.createElement("div", {
    className: "imp-example"
  }, "Don\u2019t have one handy?", /*#__PURE__*/React.createElement("button", {
    className: "imp-example__btn",
    onClick: () => setUrl("linktr.ee/remitravels")
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sparkles",
    size: 13
  }), " Try linktr.ee/remitravels")), /*#__PURE__*/React.createElement("div", {
    className: "imp-trust"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-trust__item"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "lock",
    size: 14
  }), " Only reads what\u2019s public \u2014 no account logins"), /*#__PURE__*/React.createElement("span", {
    className: "imp-trust__item"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "zap",
    size: 14
  }), " Deterministic \u2014 no AI needed to import"), /*#__PURE__*/React.createElement("span", {
    className: "imp-trust__item"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "check-check",
    size: 14
  }), " Exact URLs preserved")), /*#__PURE__*/React.createElement("div", {
    className: "imp-sources"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-sources__label"
  }, "Reads pages from"), /*#__PURE__*/React.createElement("div", {
    className: "imp-sources__row"
  }, SUPPORTED.map(s => /*#__PURE__*/React.createElement("span", {
    key: s.name,
    className: "imp-sources__chip"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-sources__dot",
    style: {
      background: s.color
    }
  }), " ", s.name)))));
}

/* ---------------- Stage 2: scan ---------------- */
const PHASE_LABELS = n => ["Fetched the page", "Found Remi Solène’s profile", `Reading links — found ${n}`, "Matching services with the registry"];
const ROUTE_LABEL = {
  strip: "Platform icon",
  lead: "Lead media",
  link: "Link"
};
const ROUTE_ICON = {
  strip: "at-sign",
  lead: "play",
  link: "link"
};
function ScanStage({
  rows,
  onDone
}) {
  const [phase, setPhase] = im_useState(0); // index of the active/just-finished phase
  const [shown, setShown] = im_useState(0); // # of rows revealed
  const [done, setDone] = im_useState(false);
  const timers = im_useRef([]);
  im_useEffect(() => {
    const T = timers.current;
    const at = (ms, fn) => T.push(setTimeout(fn, ms));
    at(500, () => setPhase(1));
    at(1100, () => setPhase(2));
    at(1750, () => setPhase(3));
    const rowStart = 2050,
      rowGap = 230;
    rows.forEach((_, i) => at(rowStart + i * rowGap, () => setShown(i + 1)));
    at(rowStart + rows.length * rowGap + 350, () => {
      setDone(true);
    });
    return () => {
      T.forEach(clearTimeout);
      timers.current = [];
    };
  }, [rows]);
  const matched = rows.slice(0, shown).filter(r => r.matched).length;
  const phaseState = i => {
    if (done) return "done";
    if (i < phase) return "done";
    if (i === phase) return i === 3 && shown >= rows.length ? "done" : "active";
    return "todo";
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "imp-scan"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-scancard"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-scan__head"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-scan__orb",
    "data-done": done ? "true" : undefined
  }, /*#__PURE__*/React.createElement(Icon, {
    name: done ? "check" : "search",
    size: done ? 18 : 17,
    stroke: done ? 3 : 2
  })), /*#__PURE__*/React.createElement("div", {
    className: "imp-scan__where"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-scan__t"
  }, done ? "Import complete" : "Reading your bio page"), /*#__PURE__*/React.createElement("div", {
    className: "imp-scan__u"
  }, "linktr.ee/remitravels")), /*#__PURE__*/React.createElement("div", {
    className: "imp-scan__count"
  }, /*#__PURE__*/React.createElement("b", null, matched, /*#__PURE__*/React.createElement("span", {
    style: {
      display: "inline",
      color: "var(--text-subtle)",
      fontWeight: 700
    }
  }, "/", rows.length)), /*#__PURE__*/React.createElement("span", null, "services matched"))), /*#__PURE__*/React.createElement("div", {
    className: "imp-phases"
  }, PHASE_LABELS(rows.length).map((label, i) => {
    const s = phaseState(i);
    return /*#__PURE__*/React.createElement("div", {
      key: i,
      className: "imp-phase",
      "data-state": s
    }, /*#__PURE__*/React.createElement("span", {
      className: "imp-phase__ico"
    }, s === "done" ? /*#__PURE__*/React.createElement(Icon, {
      name: "check",
      size: 13,
      stroke: 3
    }) : s === "active" ? /*#__PURE__*/React.createElement("span", {
      className: "imp-phase__spin"
    }) : /*#__PURE__*/React.createElement(Icon, {
      name: "circle",
      size: 9
    })), label);
  })), shown > 0 && /*#__PURE__*/React.createElement("div", {
    className: "imp-rows"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-rows__label"
  }, "Detected via @ikiro/service-registry"), rows.slice(0, shown).map(r => /*#__PURE__*/React.createElement("div", {
    key: r.i,
    className: "imp-row"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-row__glyph"
  }, r.matched ? /*#__PURE__*/React.createElement(window.BrandIcon, {
    slug: window.SERVICES[r.service].slug,
    color: r.color,
    size: 20
  }) : /*#__PURE__*/React.createElement(Icon, {
    name: "link",
    size: 18
  })), /*#__PURE__*/React.createElement("div", {
    className: "imp-row__main"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-row__svc" + (r.matched ? "" : " imp-row__svc--unknown")
  }, r.matched ? r.serviceName : "Generic link"), /*#__PURE__*/React.createElement("span", {
    className: "imp-row__url"
  }, r.host, r.matched ? "" : " · no service match")), /*#__PURE__*/React.createElement("span", {
    className: "imp-route",
    "data-route": r.route
  }, /*#__PURE__*/React.createElement(Icon, {
    name: ROUTE_ICON[r.route],
    size: 12
  }), " ", ROUTE_LABEL[r.route]), /*#__PURE__*/React.createElement("span", {
    className: "imp-row__check"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "check",
    size: 16,
    stroke: 2.5
  }))))), /*#__PURE__*/React.createElement("div", {
    className: "imp-scan__foot"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-scan__note"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "shield-check",
    size: 14
  }), " Public read only \xB7 exact URLs preserved"), /*#__PURE__*/React.createElement("button", {
    className: "imp-go",
    disabled: !done,
    onClick: onDone,
    style: {
      height: 42
    }
  }, done ? /*#__PURE__*/React.createElement(React.Fragment, null, "See your page ", /*#__PURE__*/React.createElement(Icon, {
    name: "arrow-right",
    size: 16
  })) : /*#__PURE__*/React.createElement(React.Fragment, null, "Building\u2026")))));
}

/* ---------------- Stage 3: result ---------------- */
function ResultStage({
  hub,
  rows,
  onRestart
}) {
  const socialCount = hub.socials.length;
  const linkCount = hub.links.length;
  const leadSvc = hub.lead && window.SERVICES[hub.lead.service];
  return /*#__PURE__*/React.createElement("div", {
    className: "imp-result"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-devicewrap"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-claimed"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "globe",
    size: 14
  }), " Now live at ", /*#__PURE__*/React.createElement("span", {
    className: "imp-claimed__slug"
  }, "remitravels.ikiro.pro")), /*#__PURE__*/React.createElement("div", {
    className: "imp-device"
  }, /*#__PURE__*/React.createElement(LinkHubPage, {
    data: hub
  }))), /*#__PURE__*/React.createElement("div", {
    className: "imp-surface"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-surface__badge"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "check",
    size: 13,
    stroke: 3
  }), " Rebuilt & owned"), /*#__PURE__*/React.createElement("h2", {
    className: "imp-surface__h"
  }, "Your page, rebuilt as a Default Link Hub."), /*#__PURE__*/React.createElement("p", {
    className: "imp-surface__sub"
  }, rows.length, " links read, ", rows.filter(r => r.matched).length, " services recognized \u2014 and mapped to the right block, automatically. Nothing to copy-paste."), /*#__PURE__*/React.createElement("div", {
    className: "imp-map"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-map__row"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-map__ico"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "at-sign",
    size: 19
  })), /*#__PURE__*/React.createElement("div", {
    className: "imp-map__txt"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-map__t"
  }, socialCount, " platforms \u2192 icon strip"), /*#__PURE__*/React.createElement("div", {
    className: "imp-map__s"
  }, "Recognizable, accessible, registry-backed")), /*#__PURE__*/React.createElement("span", {
    className: "imp-map__glyphs"
  }, hub.socials.slice(0, 5).map(s => /*#__PURE__*/React.createElement("span", {
    key: s.id,
    className: "imp-map__glyph"
  }, /*#__PURE__*/React.createElement(window.BrandIcon, {
    slug: window.SERVICES[s.service].slug,
    color: window.SERVICES[s.service].color,
    size: 14
  }))))), hub.lead && /*#__PURE__*/React.createElement("div", {
    className: "imp-map__row"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-map__ico"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "play",
    size: 18
  })), /*#__PURE__*/React.createElement("div", {
    className: "imp-map__txt"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-map__t"
  }, "1 video \u2192 lead media card"), /*#__PURE__*/React.createElement("div", {
    className: "imp-map__s"
  }, "Your latest film, featured up top")), /*#__PURE__*/React.createElement("span", {
    className: "imp-map__glyphs"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-map__glyph"
  }, leadSvc && /*#__PURE__*/React.createElement(window.BrandIcon, {
    slug: leadSvc.slug,
    color: leadSvc.color,
    size: 14
  })))), /*#__PURE__*/React.createElement("div", {
    className: "imp-map__row"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-map__ico"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "list",
    size: 18
  })), /*#__PURE__*/React.createElement("div", {
    className: "imp-map__txt"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-map__t"
  }, linkCount, " links \u2192 tappable buttons"), /*#__PURE__*/React.createElement("div", {
    className: "imp-map__s"
  }, "Offer, newsletter, booking & guide")), /*#__PURE__*/React.createElement("span", {
    className: "imp-map__n"
  }, linkCount)), /*#__PURE__*/React.createElement("div", {
    className: "imp-map__row"
  }, /*#__PURE__*/React.createElement("span", {
    className: "imp-map__ico"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "image",
    size: 18
  })), /*#__PURE__*/React.createElement("div", {
    className: "imp-map__txt"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-map__t"
  }, "Backdrop & theme applied"), /*#__PURE__*/React.createElement("div", {
    className: "imp-map__s"
  }, "Contrast-safe, curated background layer")), /*#__PURE__*/React.createElement("span", {
    className: "imp-map__n"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "check",
    size: 18,
    stroke: 3
  })))), /*#__PURE__*/React.createElement("div", {
    className: "imp-cta"
  }, /*#__PURE__*/React.createElement("a", {
    className: "imp-cta__primary",
    href: "index.html"
  }, "Open in Studio ", /*#__PURE__*/React.createElement(Icon, {
    name: "arrow-right",
    size: 17
  })), /*#__PURE__*/React.createElement("button", {
    className: "imp-cta__ghost",
    onClick: onRestart
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "rotate-ccw",
    size: 15
  }), " Start over")), /*#__PURE__*/React.createElement("div", {
    className: "imp-note"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "shield-check",
    size: 14
  }), " Renders with JavaScript disabled. No third-party scripts, no tracking.")));
}

/* ---------------- Shell ---------------- */
function ImportApp() {
  const [stage, setStage] = im_useState(() => localStorage.getItem(STORE_STAGE) || "paste");
  const [url, setUrl] = im_useState(() => localStorage.getItem(STORE_URL) || "");
  im_useEffect(() => {
    localStorage.setItem(STORE_STAGE, stage);
  }, [stage]);
  im_useEffect(() => {
    localStorage.setItem(STORE_URL, url);
  }, [url]);
  const rows = im_useMemo(() => window.analyzeImport(window.IMPORT_SOURCE), []);
  const hub = im_useMemo(() => window.buildHub(window.IMPORT_SOURCE), []);
  const restart = () => {
    setStage("paste");
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "imp"
  }, /*#__PURE__*/React.createElement("header", {
    className: "imp-top"
  }, /*#__PURE__*/React.createElement("div", {
    className: "imp-brand"
  }, /*#__PURE__*/React.createElement("img", {
    className: "imp-brand__mark",
    src: "../../assets/ikiro-icon.png",
    alt: ""
  }), /*#__PURE__*/React.createElement("span", {
    className: "imp-brand__name"
  }, "Ikiro"), /*#__PURE__*/React.createElement("span", {
    className: "imp-brand__tag"
  }, "Setup")), /*#__PURE__*/React.createElement(StepBar, {
    stage: stage
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      width: 92
    }
  })), /*#__PURE__*/React.createElement("main", {
    className: "imp-stage"
  }, stage === "paste" && /*#__PURE__*/React.createElement(PasteStage, {
    url: url,
    setUrl: setUrl,
    onImport: () => setStage("scan")
  }), stage === "scan" && /*#__PURE__*/React.createElement(ScanStage, {
    rows: rows,
    onDone: () => setStage("result")
  }), stage === "result" && /*#__PURE__*/React.createElement(ResultStage, {
    hub: hub,
    rows: rows,
    onRestart: restart
  })));
}
ReactDOM.createRoot(document.getElementById("root")).render(/*#__PURE__*/React.createElement(ImportApp, null));
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/Import.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/Inspector.jsx
try { (() => {
/* Inspector — the role-dispatched contextual team. Mounted only when a block
   (or a link item) is selected; it renders a different editor per role
   (profile / socials / lead / links section / gallery / form / link item).
   This is the anti-pattern fix: no persistent form wall — controls appear for
   exactly what you picked, and a "back" affordance returns to the Content
   outline. Block-level Hide / Delete live here too, mirroring the team. */

const IN_SVC = window.SERVICES;
function Field({
  label,
  children,
  hint
}) {
  return /*#__PURE__*/React.createElement("label", {
    className: "insp-field"
  }, /*#__PURE__*/React.createElement("span", {
    className: "insp-field__label"
  }, label), children, hint && /*#__PURE__*/React.createElement("span", {
    className: "insp-field__hint"
  }, hint));
}
function ProfileEditor({
  profile,
  on
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    className: "insp-photo"
  }, /*#__PURE__*/React.createElement("img", {
    src: profile.avatar,
    alt: ""
  }), /*#__PURE__*/React.createElement("button", {
    className: "insp-photo__btn"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "camera",
    size: 15
  }), " Replace photo")), /*#__PURE__*/React.createElement(Field, {
    label: "Display name"
  }, /*#__PURE__*/React.createElement("input", {
    className: "insp-input",
    value: profile.name,
    onChange: e => on.updateProfile({
      name: e.target.value
    })
  })), /*#__PURE__*/React.createElement(Field, {
    label: "Handle"
  }, /*#__PURE__*/React.createElement("input", {
    className: "insp-input",
    value: profile.handle,
    onChange: e => on.updateProfile({
      handle: e.target.value
    })
  })), /*#__PURE__*/React.createElement(Field, {
    label: "Bio",
    hint: `${profile.bio.length}/160`
  }, /*#__PURE__*/React.createElement("textarea", {
    className: "insp-input insp-textarea",
    maxLength: 160,
    value: profile.bio,
    onChange: e => on.updateProfile({
      bio: e.target.value
    })
  })), /*#__PURE__*/React.createElement("button", {
    className: "insp-row-btn"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "image",
    size: 16
  }), " Change backdrop"));
}
function SocialsEditor({
  blk,
  on
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    className: "insp-note"
  }, "A compact row of platform icons. Drag to reorder; services are detected automatically."), /*#__PURE__*/React.createElement("div", {
    className: "insp-list"
  }, blk.items.map(s => /*#__PURE__*/React.createElement("div", {
    className: "insp-listrow",
    key: s.id
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "grip-vertical",
    size: 16
  }), /*#__PURE__*/React.createElement(window.BrandIcon, {
    slug: (IN_SVC[s.service] || {}).slug,
    color: (IN_SVC[s.service] || {}).color,
    size: 18
  }), /*#__PURE__*/React.createElement("span", {
    className: "insp-listrow__label"
  }, (IN_SVC[s.service] || {}).name || s.service), /*#__PURE__*/React.createElement("button", {
    className: "insp-iconbtn",
    title: "Remove",
    onClick: () => on.removeSocial(s.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "x",
    size: 15
  }))))), /*#__PURE__*/React.createElement("button", {
    className: "insp-row-btn",
    onClick: on.addSocial
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 16
  }), " Add platform"));
}
function LeadEditor({
  blk,
  on
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    className: "insp-photo insp-photo--wide"
  }, blk.thumb ? /*#__PURE__*/React.createElement("img", {
    src: blk.thumb,
    alt: ""
  }) : /*#__PURE__*/React.createElement("div", {
    className: "insp-photo__blank"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "play",
    size: 20
  }), " No thumbnail yet"), /*#__PURE__*/React.createElement("button", {
    className: "insp-photo__btn"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "camera",
    size: 15
  }), " Replace thumbnail")), /*#__PURE__*/React.createElement(Field, {
    label: "Destination URL"
  }, /*#__PURE__*/React.createElement("input", {
    className: "insp-input",
    value: blk.url,
    onChange: e => on.updateBlock(blk.id, {
      url: e.target.value
    })
  })), /*#__PURE__*/React.createElement(Field, {
    label: "Title"
  }, /*#__PURE__*/React.createElement("input", {
    className: "insp-input",
    value: blk.title,
    onChange: e => on.updateBlock(blk.id, {
      title: e.target.value
    })
  })), /*#__PURE__*/React.createElement(Field, {
    label: "Description"
  }, /*#__PURE__*/React.createElement("textarea", {
    className: "insp-input insp-textarea",
    value: blk.desc,
    onChange: e => on.updateBlock(blk.id, {
      desc: e.target.value
    })
  })));
}
function LinksSectionEditor({
  blk,
  on
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    className: "insp-note"
  }, "A stacked list of link buttons. Click any link on the page to edit it, or reorder with its drag handle."), /*#__PURE__*/React.createElement("div", {
    className: "insp-list"
  }, blk.items.map(l => /*#__PURE__*/React.createElement("div", {
    className: "insp-listrow insp-listrow--btn",
    key: l.id,
    onClick: () => on.select(l.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "grip-vertical",
    size: 16
  }), l.service ? /*#__PURE__*/React.createElement(window.BrandIcon, {
    slug: (IN_SVC[l.service] || {}).slug,
    color: (IN_SVC[l.service] || {}).color,
    size: 16
  }) : /*#__PURE__*/React.createElement(Icon, {
    name: "link",
    size: 15
  }), /*#__PURE__*/React.createElement("span", {
    className: "insp-listrow__label"
  }, l.title || "Untitled link"), l.featured && /*#__PURE__*/React.createElement(Icon, {
    name: "star",
    size: 13
  }), /*#__PURE__*/React.createElement(Icon, {
    name: "chevron-right",
    size: 15
  })))), /*#__PURE__*/React.createElement("button", {
    className: "insp-row-btn",
    onClick: () => on.add(blk.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 16
  }), " Add a link"));
}
function GalleryEditor({
  blk,
  on
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Field, {
    label: "Section label",
    hint: "Shown as a heading above the grid."
  }, /*#__PURE__*/React.createElement("input", {
    className: "insp-input",
    value: blk.label || "",
    placeholder: "e.g. Recent work",
    onChange: e => on.updateBlock(blk.id, {
      label: e.target.value
    })
  })), /*#__PURE__*/React.createElement("div", {
    className: "insp-field__label"
  }, "Photos"), /*#__PURE__*/React.createElement("div", {
    className: "insp-thumbs"
  }, blk.images.map((src, i) => /*#__PURE__*/React.createElement("span", {
    className: "insp-thumb",
    key: i,
    style: {
      backgroundImage: `url(${src})`
    }
  }, /*#__PURE__*/React.createElement("button", {
    className: "insp-thumb__x",
    title: "Remove",
    onClick: () => on.galleryRemove(blk.id, i)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "x",
    size: 13,
    stroke: 3
  })))), /*#__PURE__*/React.createElement("button", {
    className: "insp-thumb insp-thumb--add",
    onClick: () => on.galleryAdd(blk.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 20
  }))), /*#__PURE__*/React.createElement("div", {
    className: "insp-note"
  }, "Drag photos to reorder. JPG, PNG or WebP up to 10MB."));
}
function FormEditor({
  blk,
  on
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Field, {
    label: "Heading"
  }, /*#__PURE__*/React.createElement("input", {
    className: "insp-input",
    value: blk.heading,
    onChange: e => on.updateBlock(blk.id, {
      heading: e.target.value
    })
  })), /*#__PURE__*/React.createElement(Field, {
    label: "Description"
  }, /*#__PURE__*/React.createElement("textarea", {
    className: "insp-input insp-textarea",
    value: blk.sub,
    onChange: e => on.updateBlock(blk.id, {
      sub: e.target.value
    })
  })), /*#__PURE__*/React.createElement(Field, {
    label: "Button label"
  }, /*#__PURE__*/React.createElement("input", {
    className: "insp-input",
    value: blk.button,
    onChange: e => on.updateBlock(blk.id, {
      button: e.target.value
    })
  })), /*#__PURE__*/React.createElement(Field, {
    label: "Email placeholder"
  }, /*#__PURE__*/React.createElement("input", {
    className: "insp-input",
    value: blk.placeholder,
    onChange: e => on.updateBlock(blk.id, {
      placeholder: e.target.value
    })
  })), /*#__PURE__*/React.createElement(Field, {
    label: "Fields"
  }, /*#__PURE__*/React.createElement("div", {
    className: "insp-seg"
  }, /*#__PURE__*/React.createElement("button", {
    "data-on": !blk.nameField ? "true" : undefined,
    onClick: () => on.updateBlock(blk.id, {
      nameField: false
    })
  }, "Email only"), /*#__PURE__*/React.createElement("button", {
    "data-on": blk.nameField ? "true" : undefined,
    onClick: () => on.updateBlock(blk.id, {
      nameField: true
    })
  }, "Name + email"))), /*#__PURE__*/React.createElement("div", {
    className: "insp-note"
  }, "Submissions collect to your inbox. No third-party scripts load on the public page."));
}
function LinkEditor({
  link,
  on
}) {
  const svc = link.service && IN_SVC[link.service];
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Field, {
    label: "Destination URL",
    hint: "The exact link \u2014 preserved on save."
  }, /*#__PURE__*/React.createElement("div", {
    className: "insp-url"
  }, /*#__PURE__*/React.createElement("span", {
    className: "insp-url__ico"
  }, svc ? /*#__PURE__*/React.createElement(window.BrandIcon, {
    slug: svc.slug,
    color: svc.color,
    size: 16
  }) : /*#__PURE__*/React.createElement(Icon, {
    name: "link",
    size: 15
  })), /*#__PURE__*/React.createElement("input", {
    className: "insp-input insp-input--bare",
    value: link.url,
    onChange: e => on.updateLink(link.id, {
      url: e.target.value
    })
  }))), /*#__PURE__*/React.createElement(Field, {
    label: "Title"
  }, /*#__PURE__*/React.createElement("input", {
    className: "insp-input",
    value: link.title,
    onChange: e => on.updateLink(link.id, {
      title: e.target.value
    })
  })), /*#__PURE__*/React.createElement(Field, {
    label: "Presentation"
  }, /*#__PURE__*/React.createElement("div", {
    className: "insp-seg"
  }, /*#__PURE__*/React.createElement("button", {
    "data-on": !link.featured ? "true" : undefined,
    onClick: () => on.updateLink(link.id, {
      featured: false
    })
  }, "Classic"), /*#__PURE__*/React.createElement("button", {
    "data-on": link.featured ? "true" : undefined,
    onClick: () => on.updateLink(link.id, {
      featured: true
    })
  }, "Featured"))), /*#__PURE__*/React.createElement("div", {
    className: "insp-actions"
  }, /*#__PURE__*/React.createElement("button", {
    className: "insp-row-btn",
    onClick: () => on.toggleHide(link.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: link.hidden ? "eye" : "eye-off",
    size: 16
  }), " ", link.hidden ? "Show on page" : "Hide from page"), /*#__PURE__*/React.createElement("button", {
    className: "insp-row-btn insp-row-btn--danger",
    onClick: () => on.remove(link.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "trash-2",
    size: 16
  }), " Delete link")));
}
const ROLE_LABEL = {
  profile: "Profile",
  socials: "Platform icons",
  lead: "Lead media",
  links: "Links section",
  gallery: "Image gallery",
  form: "Form"
};
function Inspector({
  selected,
  data,
  on
}) {
  if (!selected) return null;
  const blk = data.blocks.find(b => b.id === selected);
  let link = null;
  if (!blk) {
    for (const b of data.blocks) {
      if (b.type === "links") {
        const f = b.items.find(l => l.id === selected);
        if (f) {
          link = f;
          break;
        }
      }
    }
  }
  if (!blk && !link) return null;
  let role, title, body;
  if (link) {
    role = "Link";
    title = link.title || "Untitled link";
    body = /*#__PURE__*/React.createElement(LinkEditor, {
      link: link,
      on: on
    });
  } else if (blk.type === "profile") {
    role = ROLE_LABEL.profile;
    title = "Identity";
    body = /*#__PURE__*/React.createElement(ProfileEditor, {
      profile: data.profile,
      on: on
    });
  } else if (blk.type === "socials") {
    role = ROLE_LABEL.socials;
    title = "Social strip";
    body = /*#__PURE__*/React.createElement(SocialsEditor, {
      blk: blk,
      on: on
    });
  } else if (blk.type === "lead") {
    role = ROLE_LABEL.lead;
    title = blk.title || "Lead media";
    body = /*#__PURE__*/React.createElement(LeadEditor, {
      blk: blk,
      on: on
    });
  } else if (blk.type === "links") {
    role = ROLE_LABEL.links;
    title = "Links";
    body = /*#__PURE__*/React.createElement(LinksSectionEditor, {
      blk: blk,
      on: on
    });
  } else if (blk.type === "gallery") {
    role = ROLE_LABEL.gallery;
    title = blk.label || "Gallery";
    body = /*#__PURE__*/React.createElement(GalleryEditor, {
      blk: blk,
      on: on
    });
  } else if (blk.type === "form") {
    role = ROLE_LABEL.form;
    title = blk.heading || "Form";
    body = /*#__PURE__*/React.createElement(FormEditor, {
      blk: blk,
      on: on
    });
  }
  return /*#__PURE__*/React.createElement("aside", {
    className: "insp"
  }, /*#__PURE__*/React.createElement("header", {
    className: "insp__head insp__head--nav"
  }, /*#__PURE__*/React.createElement("button", {
    className: "insp__back",
    onClick: on.close
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "chevron-left",
    size: 16
  }), " All blocks"), /*#__PURE__*/React.createElement("div", {
    className: "insp__role"
  }, role)), /*#__PURE__*/React.createElement("div", {
    className: "insp__title"
  }, title), /*#__PURE__*/React.createElement("div", {
    className: "insp__body"
  }, body), /*#__PURE__*/React.createElement("footer", {
    className: "insp__foot"
  }, blk && /*#__PURE__*/React.createElement("div", {
    className: "insp-blockactions"
  }, /*#__PURE__*/React.createElement("button", {
    className: "insp-row-btn",
    onClick: () => on.toggleBlockHidden(blk.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: blk.hidden ? "eye" : "eye-off",
    size: 16
  }), " ", blk.hidden ? "Show section" : "Hide section"), /*#__PURE__*/React.createElement("button", {
    className: "insp-row-btn insp-row-btn--danger",
    onClick: () => on.removeBlock(blk.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "trash-2",
    size: 16
  }), " Delete section")), /*#__PURE__*/React.createElement("button", {
    className: "insp__ai",
    onClick: on.improveWithAI
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "sparkles",
    size: 15
  }), " Improve with AI")));
}
Object.assign(window, {
  Inspector
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/Inspector.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/LinkHubPage.jsx
try { (() => {
/* LinkHubPage — the default Link Hub, warm editorial theme (the Remi Solène
   reference). The page is rendered from an ORDERED BLOCK LIST. One component
   renders both the public page and the editable canvas; pass `editable` +
   handlers to light up direct-manipulation chrome (selection, quick actions,
   inline block inserts, and the bottom "Add a section"). */

const {
  BrandIcon: LH_Brand,
  SERVICES: LH_SVC
} = window;
function ServiceGlyph({
  service,
  size = 20,
  white
}) {
  const svc = service && LH_SVC[service];
  if (svc) return /*#__PURE__*/React.createElement(LH_Brand, {
    slug: svc.slug,
    color: white ? "white" : svc.color,
    size: size
  });
  return /*#__PURE__*/React.createElement(Icon, {
    name: "link",
    size: size
  });
}

/* ---- block-level chrome ---------------------------------------------------- */

function BlockShell({
  blk,
  tag,
  editable,
  selected,
  on,
  className = "",
  children
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "lh-block lh-" + blk.type + (className ? " " + className : "") + (selected ? " is-selected" : "") + (blk.hidden ? " is-hidden-block" : ""),
    "data-editable": editable ? "true" : undefined,
    onClick: e => {
      if (editable && on.select) {
        e.stopPropagation();
        on.select(blk.id);
      }
    }
  }, children, editable && /*#__PURE__*/React.createElement("span", {
    className: "lh-tag"
  }, tag), editable && blk.hidden && /*#__PURE__*/React.createElement("span", {
    className: "lh-hidden-pill"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "eye-off",
    size: 12
  }), " Hidden"));
}

/* a thin hover-to-reveal "insert a block here" control between blocks */
function InsertZone({
  index,
  on
}) {
  return /*#__PURE__*/React.createElement("button", {
    className: "lh-insert",
    title: "Add a block here",
    onClick: e => {
      e.stopPropagation();
      on.addBlockAt && on.addBlockAt(index);
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "lh-insert__rule"
  }), /*#__PURE__*/React.createElement("span", {
    className: "lh-insert__btn"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 15
  })), /*#__PURE__*/React.createElement("span", {
    className: "lh-insert__rule"
  }));
}

/* ---- individual blocks ----------------------------------------------------- */

function ProfileBlock({
  profile,
  editable
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "lh-identity"
  }, /*#__PURE__*/React.createElement("div", {
    className: "lh-avatar"
  }, /*#__PURE__*/React.createElement("img", {
    src: profile.avatar,
    alt: profile.name
  }), editable && /*#__PURE__*/React.createElement("span", {
    className: "lh-avatar__edit"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "camera",
    size: 16
  }))), /*#__PURE__*/React.createElement("h1", {
    className: "lh-name"
  }, profile.name), /*#__PURE__*/React.createElement("p", {
    className: "lh-bio"
  }, /*#__PURE__*/React.createElement("span", {
    className: "lh-bio__handle"
  }, profile.handle), " \xB7 ", profile.bio));
}
function SocialStrip({
  blk,
  editable,
  on
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "lh-socials__row"
  }, blk.items.map(s => /*#__PURE__*/React.createElement("a", {
    key: s.id,
    className: "lh-social",
    href: editable ? undefined : s.url,
    onClick: e => editable && e.preventDefault(),
    title: (LH_SVC[s.service] || {}).name
  }, /*#__PURE__*/React.createElement(ServiceGlyph, {
    service: s.service,
    size: 20,
    white: true
  }))), editable && /*#__PURE__*/React.createElement("button", {
    className: "lh-social lh-social--add",
    onClick: e => {
      e.stopPropagation();
      on.addSocial && on.addSocial();
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 18
  })));
}
function LeadBlock({
  blk,
  editable
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    className: "lh-label"
  }, "Latest"), /*#__PURE__*/React.createElement("a", {
    className: "lh-lead__card",
    href: editable ? undefined : blk.url,
    onClick: e => editable && e.preventDefault()
  }, /*#__PURE__*/React.createElement("div", {
    className: "lh-lead__thumb" + (blk.thumb ? "" : " lh-lead__thumb--blank"),
    style: blk.thumb ? {
      backgroundImage: `url(${blk.thumb})`
    } : undefined
  }, /*#__PURE__*/React.createElement("span", {
    className: "lh-lead__play"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "play",
    size: 22
  })), /*#__PURE__*/React.createElement("span", {
    className: "lh-lead__badge"
  }, /*#__PURE__*/React.createElement(ServiceGlyph, {
    service: blk.service,
    size: 15,
    white: true
  }))), /*#__PURE__*/React.createElement("div", {
    className: "lh-lead__body"
  }, /*#__PURE__*/React.createElement("div", {
    className: "lh-lead__title"
  }, blk.title), blk.desc && /*#__PURE__*/React.createElement("div", {
    className: "lh-lead__desc"
  }, blk.desc))));
}
function QuickActions({
  link,
  on
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "lh-quick",
    onClick: e => e.stopPropagation()
  }, /*#__PURE__*/React.createElement("button", {
    className: "lh-quick__btn",
    title: link.featured ? "Unfeature" : "Feature",
    "data-on": link.featured ? "true" : undefined,
    onClick: () => on.feature(link.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "star",
    size: 15
  })), /*#__PURE__*/React.createElement("button", {
    className: "lh-quick__btn",
    title: link.hidden ? "Show" : "Hide",
    onClick: () => on.toggleHide(link.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: link.hidden ? "eye-off" : "eye",
    size: 15
  })), /*#__PURE__*/React.createElement("button", {
    className: "lh-quick__btn",
    title: "Edit",
    onClick: () => on.select(link.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "pencil",
    size: 15
  })), /*#__PURE__*/React.createElement("button", {
    className: "lh-quick__btn lh-quick__btn--danger",
    title: "Delete",
    onClick: () => on.remove(link.id)
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "trash-2",
    size: 15
  })));
}
function LinksBlock({
  blk,
  editable,
  selected,
  on
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    className: "lh-label"
  }, "Start here"), /*#__PURE__*/React.createElement("div", {
    className: "lh-links"
  }, blk.items.map(l => {
    const isVidCard = l.kind === "video" && l.featured;
    return /*#__PURE__*/React.createElement("div", {
      key: l.id,
      className: "lh-link" + (isVidCard ? " lh-link--card" : "") + (editable && selected === l.id ? " is-selected" : "") + (l.hidden ? " is-hidden" : "") + (l.featured && !isVidCard ? " is-featured" : ""),
      "data-editable": editable ? "true" : undefined,
      onClick: e => {
        if (editable) {
          e.stopPropagation();
          on.select(l.id);
        }
      }
    }, editable && /*#__PURE__*/React.createElement("span", {
      className: "lh-link__handle",
      title: "Drag to reorder"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "grip-vertical",
      size: 18
    })), isVidCard ? /*#__PURE__*/React.createElement("a", {
      className: "lh-vidcard",
      href: editable ? undefined : l.url,
      onClick: e => editable && e.preventDefault()
    }, /*#__PURE__*/React.createElement("span", {
      className: "lh-vidcard__play"
    }, /*#__PURE__*/React.createElement(Icon, {
      name: "play",
      size: 20
    })), /*#__PURE__*/React.createElement("span", {
      className: "lh-vidcard__badge"
    }, /*#__PURE__*/React.createElement(ServiceGlyph, {
      service: l.service || "youtube",
      size: 14,
      white: true
    })), /*#__PURE__*/React.createElement("span", {
      className: "lh-vidcard__title"
    }, l.title)) : /*#__PURE__*/React.createElement("a", {
      className: "lh-link__hit",
      href: editable ? undefined : l.url,
      onClick: e => editable && e.preventDefault()
    }, l.service && /*#__PURE__*/React.createElement("span", {
      className: "lh-link__ico"
    }, /*#__PURE__*/React.createElement(ServiceGlyph, {
      service: l.service,
      size: 18
    })), /*#__PURE__*/React.createElement("span", {
      className: "lh-link__title"
    }, l.title)), editable && /*#__PURE__*/React.createElement(QuickActions, {
      link: l,
      on: on
    }));
  }), editable && /*#__PURE__*/React.createElement("button", {
    className: "lh-add",
    onClick: e => {
      e.stopPropagation();
      on.add && on.add(blk.id);
    }
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "plus",
    size: 18
  }), " Add a link")));
}
function GalleryBlock({
  blk,
  editable
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, blk.label && /*#__PURE__*/React.createElement("div", {
    className: "lh-label"
  }, blk.label), /*#__PURE__*/React.createElement("div", {
    className: "lh-gallery__grid"
  }, blk.images.map((src, i) => /*#__PURE__*/React.createElement("span", {
    key: i,
    className: "lh-gallery__tile",
    style: {
      backgroundImage: `url(${src})`
    }
  }))));
}
function FormBlock({
  blk,
  editable
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "lh-form__card"
  }, /*#__PURE__*/React.createElement("div", {
    className: "lh-form__heading"
  }, blk.heading), blk.sub && /*#__PURE__*/React.createElement("div", {
    className: "lh-form__sub"
  }, blk.sub), /*#__PURE__*/React.createElement("div", {
    className: "lh-form__fields"
  }, blk.nameField && /*#__PURE__*/React.createElement("input", {
    className: "lh-form__input",
    placeholder: "Your name",
    readOnly: editable
  }), /*#__PURE__*/React.createElement("div", {
    className: "lh-form__row"
  }, /*#__PURE__*/React.createElement("input", {
    className: "lh-form__input",
    placeholder: blk.placeholder,
    readOnly: editable
  }), /*#__PURE__*/React.createElement("button", {
    className: "lh-form__btn",
    type: "button",
    onClick: e => editable && e.preventDefault()
  }, blk.button))));
}
const BLOCK_TAG = {
  profile: "Profile",
  socials: "Platform icons",
  lead: "Lead media",
  links: "Links",
  gallery: "Gallery",
  form: "Form"
};
function BlockView({
  blk,
  profile,
  editable,
  selected,
  on
}) {
  let inner = null;
  if (blk.type === "profile") inner = /*#__PURE__*/React.createElement(ProfileBlock, {
    profile: profile,
    editable: editable
  });else if (blk.type === "socials") inner = /*#__PURE__*/React.createElement(SocialStrip, {
    blk: blk,
    editable: editable,
    on: on
  });else if (blk.type === "lead") inner = /*#__PURE__*/React.createElement(LeadBlock, {
    blk: blk,
    editable: editable
  });else if (blk.type === "links") inner = /*#__PURE__*/React.createElement(LinksBlock, {
    blk: blk,
    editable: editable,
    selected: selected,
    on: on
  });else if (blk.type === "gallery") inner = /*#__PURE__*/React.createElement(GalleryBlock, {
    blk: blk,
    editable: editable
  });else if (blk.type === "form") inner = /*#__PURE__*/React.createElement(FormBlock, {
    blk: blk,
    editable: editable
  });
  return /*#__PURE__*/React.createElement(BlockShell, {
    blk: blk,
    tag: BLOCK_TAG[blk.type] || "Block",
    editable: editable,
    selected: editable && selected === blk.id,
    on: on
  }, inner);
}
function LinkHubPage({
  data,
  editable = false,
  selected,
  on = {},
  scale = 1
}) {
  const {
    profile,
    blocks
  } = data;
  const shown = editable ? blocks : blocks.filter(b => !b.hidden);
  return /*#__PURE__*/React.createElement("div", {
    className: "lh",
    style: {
      "--lh-scale": scale
    }
  }, /*#__PURE__*/React.createElement("div", {
    className: "lh__bg",
    style: {
      backgroundImage: `url(${profile.backdrop})`
    }
  }), /*#__PURE__*/React.createElement("div", {
    className: "lh__scrim"
  }), /*#__PURE__*/React.createElement("div", {
    className: "lh__inner",
    onClick: () => editable && on.select && on.select(null)
  }, shown.flatMap((blk, i) => {
    const idx = blocks.indexOf(blk);
    const nodes = [];
    if (editable && i > 0) nodes.push(/*#__PURE__*/React.createElement(InsertZone, {
      key: "ins-" + blk.id,
      index: idx,
      on: on
    }));
    nodes.push(/*#__PURE__*/React.createElement(BlockView, {
      key: blk.id,
      blk: blk,
      profile: profile,
      editable: editable,
      selected: selected,
      on: on
    }));
    return nodes;
  }), editable && /*#__PURE__*/React.createElement("button", {
    className: "lh-add-section",
    onClick: e => {
      e.stopPropagation();
      on.addBlockAt && on.addBlockAt(blocks.length);
    }
  }, /*#__PURE__*/React.createElement("span", {
    className: "lh-add-section__ico"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "layout-grid",
    size: 18
  })), /*#__PURE__*/React.createElement("span", {
    className: "lh-add-section__t"
  }, "Add a section"), /*#__PURE__*/React.createElement("span", {
    className: "lh-add-section__s"
  }, "Links \xB7 Gallery \xB7 Form \xB7 Profile \xB7 Social")), /*#__PURE__*/React.createElement("div", {
    className: "lh-footer"
  }, /*#__PURE__*/React.createElement("div", {
    className: "lh-footer__note"
  }, profile.footerNote), /*#__PURE__*/React.createElement("div", {
    className: "lh-footer__row"
  }, /*#__PURE__*/React.createElement("a", {
    href: "#"
  }, profile.contact), /*#__PURE__*/React.createElement("span", null, "\xB7"), /*#__PURE__*/React.createElement("a", {
    href: "#"
  }, "Press kit")))));
}
Object.assign(window, {
  LinkHubPage
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/LinkHubPage.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/PublicMount.jsx
try { (() => {
/* Public render of the default Link Hub — the page a visitor sees at
   {slug}.ikiro.pro. Same component as the editor canvas, with no edit chrome.
   Full-bleed backdrop, centered column, mobile-first. */

ReactDOM.createRoot(document.getElementById("root")).render(/*#__PURE__*/React.createElement("div", {
  className: "lh-public"
}, /*#__PURE__*/React.createElement(LinkHubPage, {
  data: window.HUB
})));
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/PublicMount.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/StudioApp.jsx
try { (() => {
/* StudioApp — the reimagined Ikiro Studio editor.
   Thesis: the page IS the editor. Editing is direct (hover actions on canvas),
   contextual (the role-dispatched inspector appears on selection), structural
   (the Content team lists/reorders/adds blocks), or composed (Add modals).
   The page is an ordered BLOCK LIST; reorder / hide / delete / add are all
   deterministic operations over `data.blocks`. AI is docked and optional. */

const {
  useState: st_useState
} = React;
function RailItem({
  icon,
  label,
  active,
  onClick
}) {
  return /*#__PURE__*/React.createElement("button", {
    className: "rail__item",
    "data-active": active ? "true" : undefined,
    onClick: onClick,
    title: label
  }, /*#__PURE__*/React.createElement(Icon, {
    name: icon,
    size: 20
  }), /*#__PURE__*/React.createElement("span", {
    className: "rail__label"
  }, label));
}
function DeviceToggle({
  device,
  onChange
}) {
  return /*#__PURE__*/React.createElement("div", {
    className: "device-toggle",
    role: "tablist",
    "aria-label": "Preview device"
  }, /*#__PURE__*/React.createElement("button", {
    className: "device-toggle__btn",
    role: "tab",
    "aria-selected": device === "desktop",
    "data-on": device === "desktop" ? "true" : undefined,
    onClick: () => onChange("desktop"),
    title: "Desktop preview",
    "aria-label": "Desktop preview"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "laptop",
    size: 18
  })), /*#__PURE__*/React.createElement("button", {
    className: "device-toggle__btn",
    role: "tab",
    "aria-selected": device === "mobile",
    "data-on": device === "mobile" ? "true" : undefined,
    onClick: () => onChange("mobile"),
    title: "Mobile preview",
    "aria-label": "Mobile preview"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "smartphone",
    size: 18
  })));
}
function DesignPanel({
  data,
  on
}) {
  const BACKDROPS = ["https://images.unsplash.com/photo-1444930694458-01babf71870c?w=200&h=260&fit=crop&q=70", "https://images.unsplash.com/photo-1505228395891-9a51e7e86bf6?w=200&h=260&fit=crop&q=70", "https://images.unsplash.com/photo-1470770841072-f978cf4d019e?w=200&h=260&fit=crop&q=70", "https://images.unsplash.com/photo-1418065460487-3e41a6c84dc5?w=200&h=260&fit=crop&q=70"];
  return /*#__PURE__*/React.createElement("aside", {
    className: "insp"
  }, /*#__PURE__*/React.createElement("header", {
    className: "insp__head"
  }, /*#__PURE__*/React.createElement("div", {
    className: "insp__role"
  }, "Design")), /*#__PURE__*/React.createElement("div", {
    className: "insp__title"
  }, "Backdrop & theme"), /*#__PURE__*/React.createElement("div", {
    className: "insp__body"
  }, /*#__PURE__*/React.createElement("div", {
    className: "insp-field__label",
    style: {
      marginBottom: 8
    }
  }, "Backdrop"), /*#__PURE__*/React.createElement("div", {
    className: "design-backdrops"
  }, BACKDROPS.map(b => /*#__PURE__*/React.createElement("button", {
    key: b,
    className: "design-backdrop",
    "data-on": data.profile.backdrop.split("?")[0] === b.split("?")[0] ? "true" : undefined,
    onClick: () => on.updateProfile({
      backdrop: b.replace("w=200&h=260", "w=1280")
    }),
    style: {
      backgroundImage: `url(${b})`
    }
  }))), /*#__PURE__*/React.createElement("div", {
    className: "insp-field__label",
    style: {
      margin: "18px 0 8px"
    }
  }, "Link style"), /*#__PURE__*/React.createElement("div", {
    className: "insp-seg"
  }, /*#__PURE__*/React.createElement("button", {
    "data-on": "true"
  }, "Pill"), /*#__PURE__*/React.createElement("button", null, "Rounded"), /*#__PURE__*/React.createElement("button", null, "Square")), /*#__PURE__*/React.createElement("div", {
    className: "insp-field__label",
    style: {
      margin: "18px 0 8px"
    }
  }, "Identity font"), /*#__PURE__*/React.createElement("div", {
    className: "insp-seg"
  }, /*#__PURE__*/React.createElement("button", {
    "data-on": "true",
    style: {
      fontFamily: "var(--font-serif)"
    }
  }, "Serif"), /*#__PURE__*/React.createElement("button", {
    style: {
      fontFamily: "var(--font-sans)"
    }
  }, "Sans"))));
}
function Placeholder({
  view
}) {
  const copy = view === "analytics" ? {
    icon: "bar-chart-3",
    t: "Analytics",
    b: "Clicks, views and top links land here once your page is live."
  } : {
    icon: "settings",
    t: "Settings",
    b: "Custom domain, SEO, and the Website.md export live here."
  };
  return /*#__PURE__*/React.createElement("div", {
    className: "studio-placeholder"
  }, /*#__PURE__*/React.createElement("span", {
    className: "studio-placeholder__ico"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: copy.icon,
    size: 24
  })), /*#__PURE__*/React.createElement("div", {
    className: "studio-placeholder__t"
  }, copy.t), /*#__PURE__*/React.createElement("p", {
    className: "studio-placeholder__b"
  }, copy.b));
}
const GALLERY_POOL = ["https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1454496522488-7a8e488e8606?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1426604966848-d7adac402bff?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1472214103451-9374bd1c798e?w=400&h=400&fit=crop&q=80"];
function StudioApp() {
  const [data, setData] = st_useState(window.HUB);
  const [view, setView] = st_useState("content");
  const [selected, setSelected] = st_useState(null);
  const [addOpen, setAddOpen] = st_useState(false);
  const [addType, setAddType] = st_useState("suggested");
  const [addTarget, setAddTarget] = st_useState(null); // links block id for item adds
  const [blockOpen, setBlockOpen] = st_useState(false); // block composer
  const [blockIndex, setBlockIndex] = st_useState(null); // insert index
  const [copilot, setCopilot] = st_useState(false);
  const [device, setDevice] = st_useState("mobile");
  const [status, setStatus] = st_useState("ready");
  const [publishing, setPublishing] = st_useState(false);
  const [toast, setToast] = st_useState(false);
  const dirty = () => setStatus("draft");
  const mutate = fn => {
    setData(d => fn(d));
    dirty();
  };
  const mapLinks = (d, fn) => ({
    ...d,
    blocks: d.blocks.map(b => b.type === "links" ? {
      ...b,
      items: fn(b.items)
    } : b)
  });
  const on = {
    select: id => {
      setSelected(id);
      setView("content");
    },
    close: () => setSelected(null),
    // ---- item adds (within a block) ----
    add: blockId => {
      setAddTarget(blockId || null);
      setAddType("suggested");
      setAddOpen(true);
    },
    addSocial: () => {
      setAddType("social");
      setAddOpen(true);
    },
    onAdd: link => mutate(d => {
      const target = addTarget && d.blocks.some(b => b.id === addTarget && b.type === "links") ? addTarget : null;
      if (target) return {
        ...d,
        blocks: d.blocks.map(b => b.id === target ? {
          ...b,
          items: [...b.items, link]
        } : b)
      };
      let done = false;
      let blocks = d.blocks.map(b => {
        if (!done && b.type === "links") {
          done = true;
          return {
            ...b,
            items: [...b.items, link]
          };
        }
        return b;
      });
      if (!done) blocks = [...blocks, {
        id: "blk-" + Date.now(),
        type: "links",
        items: [link]
      }];
      return {
        ...d,
        blocks
      };
    }),
    addSocialItem: s => mutate(d => {
      let done = false;
      let blocks = d.blocks.map(b => {
        if (!done && b.type === "socials") {
          done = true;
          return {
            ...b,
            items: [...b.items, s]
          };
        }
        return b;
      });
      if (!done) blocks = [...blocks, {
        id: "blk-" + Date.now(),
        type: "socials",
        items: [s]
      }];
      return {
        ...d,
        blocks
      };
    }),
    setLead: lead => mutate(d => {
      let done = false,
        newId = null;
      let blocks = d.blocks.map(b => {
        if (!done && b.type === "lead") {
          done = true;
          return {
            ...b,
            ...lead,
            id: b.id
          };
        }
        return b;
      });
      if (!done) {
        newId = "blk-" + Date.now();
        blocks = [...blocks, {
          id: newId,
          ...lead
        }];
      }
      setTimeout(() => setSelected(done ? d.blocks.find(b => b.type === "lead").id : newId), 0);
      return {
        ...d,
        blocks
      };
    }),
    // ---- field updates ----
    updateProfile: patch => mutate(d => ({
      ...d,
      profile: {
        ...d.profile,
        ...patch
      }
    })),
    updateBlock: (id, patch) => mutate(d => ({
      ...d,
      blocks: d.blocks.map(b => b.id === id ? {
        ...b,
        ...patch
      } : b)
    })),
    updateLink: (id, patch) => mutate(d => mapLinks(d, items => items.map(l => l.id === id ? {
      ...l,
      ...patch
    } : l))),
    toggleHide: id => mutate(d => mapLinks(d, items => items.map(l => l.id === id ? {
      ...l,
      hidden: !l.hidden
    } : l))),
    feature: id => mutate(d => mapLinks(d, items => items.map(l => l.id === id ? {
      ...l,
      featured: !l.featured
    } : l))),
    remove: id => {
      setSelected(null);
      mutate(d => mapLinks(d, items => items.filter(l => l.id !== id)));
    },
    removeSocial: id => mutate(d => ({
      ...d,
      blocks: d.blocks.map(b => b.type === "socials" ? {
        ...b,
        items: b.items.filter(s => s.id !== id)
      } : b)
    })),
    // ---- gallery items ----
    galleryAdd: id => mutate(d => ({
      ...d,
      blocks: d.blocks.map(b => b.id === id ? {
        ...b,
        images: [...b.images, GALLERY_POOL[b.images.length % GALLERY_POOL.length]]
      } : b)
    })),
    galleryRemove: (id, i) => mutate(d => ({
      ...d,
      blocks: d.blocks.map(b => b.id === id ? {
        ...b,
        images: b.images.filter((_, j) => j !== i)
      } : b)
    })),
    // ---- block (section) operations ----
    addBlockAt: index => {
      setBlockIndex(index);
      setBlockOpen(true);
    },
    addBlock: (type, index) => {
      const def = (window.BLOCK_DEFAULTS[type] || (() => ({
        type
      })))();
      const nb = {
        id: "blk-" + Date.now(),
        ...def
      };
      mutate(d => {
        const blocks = [...d.blocks];
        const at = index == null || index < 0 ? blocks.length : Math.min(index, blocks.length);
        blocks.splice(at, 0, nb);
        return {
          ...d,
          blocks
        };
      });
      setBlockOpen(false);
      setView("content");
      setSelected(nb.id);
    },
    reorderBlocks: (from, to) => mutate(d => {
      const blocks = [...d.blocks];
      const [m] = blocks.splice(from, 1);
      blocks.splice(Math.max(0, Math.min(to, blocks.length)), 0, m);
      return {
        ...d,
        blocks
      };
    }),
    toggleBlockHidden: id => mutate(d => ({
      ...d,
      blocks: d.blocks.map(b => b.id === id ? {
        ...b,
        hidden: !b.hidden
      } : b)
    })),
    removeBlock: id => {
      setSelected(s => s === id ? null : s);
      mutate(d => ({
        ...d,
        blocks: d.blocks.filter(b => b.id !== id)
      }));
    },
    improveWithAI: () => setCopilot(true)
  };
  const publish = () => {
    if (status === "ready") return;
    setPublishing(true);
    setTimeout(() => {
      setPublishing(false);
      setStatus("ready");
      setToast(true);
      setTimeout(() => setToast(false), 2600);
    }, 850);
  };
  const showInspector = view === "content" && selected;
  const showContent = view === "content" && !selected;
  const showDesign = view === "design";
  return /*#__PURE__*/React.createElement("div", {
    className: "studio"
  }, /*#__PURE__*/React.createElement("header", {
    className: "studio-top"
  }, /*#__PURE__*/React.createElement("div", {
    className: "studio-top__left"
  }, /*#__PURE__*/React.createElement("img", {
    className: "studio-top__mark",
    src: "../../assets/ikiro-icon.png",
    alt: ""
  }), /*#__PURE__*/React.createElement("span", {
    className: "studio-top__brand"
  }, "Ikiro Studio"), /*#__PURE__*/React.createElement("span", {
    className: "studio-top__divider"
  }), /*#__PURE__*/React.createElement("span", {
    className: "studio-top__page"
  }, "Live page"), /*#__PURE__*/React.createElement("span", {
    className: "studio-top__slug"
  }, "dev-mq6ttj5m.ikiro.pro")), /*#__PURE__*/React.createElement("div", {
    className: "studio-top__center"
  }, /*#__PURE__*/React.createElement(DeviceToggle, {
    device: device,
    onChange: setDevice
  })), /*#__PURE__*/React.createElement("div", {
    className: "studio-top__right"
  }, /*#__PURE__*/React.createElement("span", {
    className: "studio-top__status",
    "data-status": status
  }, /*#__PURE__*/React.createElement("span", {
    className: "studio-top__dot"
  }), status === "ready" ? "Ready to publish" : "Draft saved"), /*#__PURE__*/React.createElement("button", {
    className: "studio-btn studio-btn--ghost"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "eye",
    size: 16
  }), " Preview"), /*#__PURE__*/React.createElement("button", {
    className: "studio-btn studio-btn--primary",
    onClick: publish,
    "data-loading": publishing ? "true" : undefined
  }, publishing ? /*#__PURE__*/React.createElement("span", {
    className: "studio-spin"
  }) : /*#__PURE__*/React.createElement(Icon, {
    name: "rocket",
    size: 16
  }), status === "ready" ? "Published" : "Publish"))), /*#__PURE__*/React.createElement("div", {
    className: "studio-body"
  }, /*#__PURE__*/React.createElement("nav", {
    className: "rail"
  }, /*#__PURE__*/React.createElement(RailItem, {
    icon: "layout-sidebar",
    label: "Content",
    active: view === "content",
    onClick: () => {
      setView("content");
    }
  }), /*#__PURE__*/React.createElement(RailItem, {
    icon: "palette",
    label: "Design",
    active: view === "design",
    onClick: () => {
      setView("design");
      setSelected(null);
    }
  }), /*#__PURE__*/React.createElement(RailItem, {
    icon: "bar-chart-3",
    label: "Stats",
    active: view === "analytics",
    onClick: () => {
      setView("analytics");
      setSelected(null);
    }
  }), /*#__PURE__*/React.createElement(RailItem, {
    icon: "settings",
    label: "Settings",
    active: view === "settings",
    onClick: () => {
      setView("settings");
      setSelected(null);
    }
  })), /*#__PURE__*/React.createElement("main", {
    className: "canvas",
    onClick: () => setSelected(null)
  }, (view === "content" || view === "design") && /*#__PURE__*/React.createElement("div", {
    className: "canvas__inner canvas__inner--" + device,
    onClick: e => e.stopPropagation()
  }, /*#__PURE__*/React.createElement("div", {
    className: "canvas__bar"
  }, /*#__PURE__*/React.createElement("span", {
    className: "canvas__url"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "lock",
    size: 12
  }), " dev-mq6ttj5m.ikiro.pro"), /*#__PURE__*/React.createElement("span", {
    className: "canvas__hint"
  }, device === "desktop" ? "Desktop preview" : "Mobile preview", " \xB7 click anything to edit")), /*#__PURE__*/React.createElement("div", {
    className: "canvas__device canvas__device--" + device
  }, device === "desktop" && /*#__PURE__*/React.createElement("div", {
    className: "canvas__chrome"
  }, /*#__PURE__*/React.createElement("span", {
    className: "canvas__dots"
  }, /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null), /*#__PURE__*/React.createElement("i", null))), /*#__PURE__*/React.createElement(LinkHubPage, {
    data: data,
    editable: true,
    selected: selected,
    on: on
  }))), (view === "analytics" || view === "settings") && /*#__PURE__*/React.createElement(Placeholder, {
    view: view
  })), showContent && /*#__PURE__*/React.createElement(ContentPanel, {
    data: data,
    on: on
  }), showInspector && /*#__PURE__*/React.createElement(Inspector, {
    selected: selected,
    data: data,
    on: on
  }), showDesign && /*#__PURE__*/React.createElement(DesignPanel, {
    data: data,
    on: on
  })), /*#__PURE__*/React.createElement(AddComposer, {
    open: addOpen,
    initialType: addType,
    onClose: () => setAddOpen(false),
    onAdd: on.onAdd,
    onAddSocial: on.addSocialItem,
    onSetLead: on.setLead
  }), /*#__PURE__*/React.createElement(BlockComposer, {
    open: blockOpen,
    index: blockIndex,
    onClose: () => setBlockOpen(false),
    onPick: on.addBlock
  }), /*#__PURE__*/React.createElement(Copilot, {
    open: copilot,
    onToggle: () => setCopilot(c => !c)
  }), toast && /*#__PURE__*/React.createElement("div", {
    className: "studio-toast"
  }, /*#__PURE__*/React.createElement("span", {
    className: "studio-toast__ico"
  }, /*#__PURE__*/React.createElement(Icon, {
    name: "check",
    size: 15,
    stroke: 3
  })), /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    className: "studio-toast__t"
  }, "Published"), /*#__PURE__*/React.createElement("div", {
    className: "studio-toast__s"
  }, "Live at dev-mq6ttj5m.ikiro.pro"))));
}
ReactDOM.createRoot(document.getElementById("root")).render(/*#__PURE__*/React.createElement(StudioApp, null));
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/StudioApp.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/design-canvas.jsx
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
  // any overlay inside the world (e.g. a TweaksTeam on an artboard) can use
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
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/design-canvas.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/footerBadges.jsx
try { (() => {
/* Tasteful "made with Ikiro" word-of-mouth footers for public bio pages.
   Each is designed to sit at the very bottom of the warm-editorial Link Hub,
   over the dark photographic scrim. The brief: quiet, classy, never the loud
   Linktree pill. The page owner should never feel the badge embarrasses them. */

const MARK = "../../assets/ikiro-icon-on-dark.png";
function Mark({
  size = 16,
  style
}) {
  return /*#__PURE__*/React.createElement("img", {
    src: MARK,
    alt: "Ikiro",
    width: size,
    height: size,
    style: {
      display: "block",
      width: size,
      height: size,
      opacity: 0.92,
      ...style
    }
  });
}

/* The owner's own footer — always present above the Ikiro badge.
   Shown faded here so the eye lands on the badge being compared. */
function OwnerFooter() {
  return /*#__PURE__*/React.createElement("div", {
    className: "fx-owner"
  }, /*#__PURE__*/React.createElement("div", {
    className: "fx-owner__note"
  }, "Remi Sol\xE8ne \u2014 coastal photography & slow travel."), /*#__PURE__*/React.createElement("div", {
    className: "fx-owner__row"
  }, /*#__PURE__*/React.createElement("a", {
    href: "#"
  }, "hello@remitravels.co"), /*#__PURE__*/React.createElement("span", null, "\xB7"), /*#__PURE__*/React.createElement("a", {
    href: "#"
  }, "Press kit")));
}

/* ── V1 · Hairline whisper ────────────────────────────────────────────────
   A single hairline, then the mark and a quiet line. The most restrained
   possible attribution — reads as a colophon, not an ad. */
function V1_Hairline() {
  return /*#__PURE__*/React.createElement("div", {
    className: "fxb fxb--center"
  }, /*#__PURE__*/React.createElement("span", {
    className: "fxb__rule"
  }), /*#__PURE__*/React.createElement("a", {
    className: "fxb-whisper",
    href: "#"
  }, /*#__PURE__*/React.createElement(Mark, {
    size: 15
  }), /*#__PURE__*/React.createElement("span", {
    className: "fxb-whisper__t"
  }, "Made with ", /*#__PURE__*/React.createElement("b", null, "Ikiro"))));
}

/* ── V2 · Address stamp ───────────────────────────────────────────────────
   The page's own ikiro.pro address set as a maker's stamp in mono. The viral
   hook is implicit: every visitor sees the namespace and that handles are
   claimable — no sales copy required. */
function V2_Stamp() {
  return /*#__PURE__*/React.createElement("a", {
    className: "fxb fxb--center fxb-stamp",
    href: "#"
  }, /*#__PURE__*/React.createElement(Mark, {
    size: 14
  }), /*#__PURE__*/React.createElement("span", {
    className: "fxb-stamp__url"
  }, "ikiro.pro/", /*#__PURE__*/React.createElement("b", null, "remitravels")));
}

/* ── V3 · Editorial signature ─────────────────────────────────────────────
   Set in the page's own Newsreader serif, italic — a print signature on a
   photograph. Matches the editorial voice so completely it feels authored. */
function V3_Signature() {
  return /*#__PURE__*/React.createElement("div", {
    className: "fxb fxb--center"
  }, /*#__PURE__*/React.createElement("span", {
    className: "fxb__rule fxb__rule--short"
  }), /*#__PURE__*/React.createElement("a", {
    className: "fxb-sig",
    href: "#"
  }, /*#__PURE__*/React.createElement("span", {
    className: "fxb-sig__pre"
  }, "Made on"), /*#__PURE__*/React.createElement(Mark, {
    size: 16,
    style: {
      opacity: 1
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "fxb-sig__name"
  }, "Ikiro")));
}

/* ── V4 · Ghost pill ──────────────────────────────────────────────────────
   The Linktree pattern, dialled all the way down: a translucent glass pill
   that borrows the page's own backdrop instead of shouting over it. */
function V4_Ghost() {
  return /*#__PURE__*/React.createElement("div", {
    className: "fxb fxb--center"
  }, /*#__PURE__*/React.createElement("a", {
    className: "fxb-pill",
    href: "#"
  }, /*#__PURE__*/React.createElement(Mark, {
    size: 15
  }), /*#__PURE__*/React.createElement("span", null, "Make a page like this")));
}

/* ── V5 · Value line ──────────────────────────────────────────────────────
   Leads with the value, not the brand. Two quiet lines that invite on merit —
   the upgrade is a "want", never a "make-this-stop". */
function V5_Value() {
  return /*#__PURE__*/React.createElement("a", {
    className: "fxb fxb--row fxb-value",
    href: "#"
  }, /*#__PURE__*/React.createElement(Mark, {
    size: 26,
    style: {
      opacity: 1
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "fxb-value__text"
  }, /*#__PURE__*/React.createElement("span", {
    className: "fxb-value__l1"
  }, "Beautifully simple bio pages."), /*#__PURE__*/React.createElement("span", {
    className: "fxb-value__l2"
  }, "Build yours on Ikiro ", /*#__PURE__*/React.createElement("span", {
    className: "fxb-value__arr"
  }, "\u2192"))));
}

/* ── V6 · Watermark ───────────────────────────────────────────────────────
   Barely there. Mark + wordmark at colophon scale, like a paper watermark in
   the corner of a print. For owners who want the page to feel entirely theirs. */
function V6_Watermark() {
  return /*#__PURE__*/React.createElement("div", {
    className: "fxb fxb--center"
  }, /*#__PURE__*/React.createElement("a", {
    className: "fxb-water",
    href: "#"
  }, /*#__PURE__*/React.createElement(Mark, {
    size: 13,
    style: {
      opacity: 0.6
    }
  }), /*#__PURE__*/React.createElement("span", {
    className: "fxb-water__t"
  }, "Ikiro")));
}
const FOOTER_VARIANTS = {
  V1_Hairline,
  V2_Stamp,
  V3_Signature,
  V4_Ghost,
  V5_Value,
  V6_Watermark,
  OwnerFooter
};
Object.assign(window, FOOTER_VARIANTS, {
  FOOTER_VARIANTS
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/footerBadges.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/hubData.jsx
try { (() => {
/* Seed content for the default Link Hub — the Remi Solène reference page.
   The page is now a real ORDERED BLOCK LIST (`blocks`). Profile identity +
   page-level theme (backdrop, footer) stay top-level; everything else is a
   block with its own content. This is the block-general model from Phase 20:
   `Add` adds a block, the inspector is role-dispatched, and reorder / hide /
   delete are deterministic operations over `blocks`. */

const HUB = {
  profile: {
    name: "Remi Solène",
    handle: "@remitravels",
    bio: "Photographer & slow-travel guide. A new film every Friday.",
    avatar: "https://images.unsplash.com/photo-1502685104226-ee32379fefbe?w=240&h=240&fit=crop&q=80",
    backdrop: "https://images.unsplash.com/photo-1505228395891-9a51e7e86bf6?w=1280&q=80",
    footerNote: "Remi Solène — coastal photography & slow travel.",
    contact: "hello@remitravels.co"
  },
  blocks: [{
    id: "b-profile",
    type: "profile"
  }, {
    id: "b-socials",
    type: "socials",
    items: [{
      id: "s1",
      service: "youtube",
      url: "https://youtube.com/@remitravels"
    }, {
      id: "s2",
      service: "instagram",
      url: "https://instagram.com/remitravels"
    }, {
      id: "s3",
      service: "tiktok",
      url: "https://tiktok.com/@remitravels"
    }, {
      id: "s4",
      service: "x",
      url: "https://x.com/remitravels"
    }, {
      id: "s5",
      service: "spotify",
      url: "https://open.spotify.com/user/remitravels"
    }]
  }, {
    id: "b-lead",
    type: "lead",
    service: "youtube",
    title: "Sardinia in 4K — the new film",
    desc: "28 minutes along the wild eastern coast, shot at golden hour. Out now.",
    url: "https://youtu.be/xxxxxxxx",
    thumb: "https://images.unsplash.com/photo-1505228395891-9a51e7e86bf6?w=720&h=420&fit=crop&q=80"
  }, {
    id: "b-links",
    type: "links",
    items: [{
      id: "l1",
      title: "Free Light & Travel guide (PDF)",
      url: "https://remitravels.co/guide",
      service: null
    }, {
      id: "l2",
      title: "Lightroom preset pack — Coastal Gold",
      url: "https://gumroad.com/l/coastalgold",
      service: "gumroad"
    }, {
      id: "l3",
      title: "Join the Friday newsletter",
      url: "https://remitravels.substack.com",
      service: "substack"
    }, {
      id: "l4",
      title: "Book a travel shoot",
      url: "https://calendly.com/remitravels/shoot",
      service: "calendly"
    }]
  }, {
    id: "b-gallery",
    type: "gallery",
    label: "Recent work",
    images: ["https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1519046904884-53103b34b206?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1505228395891-9a51e7e86bf6?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1502082553048-f009c37129b9?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1439066615861-d1af74d74000?w=400&h=400&fit=crop&q=80"]
  }]
};

/* Defaults used by the Block composer when a new block is inserted. */
const BLOCK_DEFAULTS = {
  profile: () => ({
    type: "profile"
  }),
  socials: () => ({
    type: "socials",
    items: []
  }),
  links: () => ({
    type: "links",
    items: []
  }),
  lead: () => ({
    type: "lead",
    service: null,
    title: "Featured",
    desc: "",
    url: "",
    thumb: ""
  }),
  gallery: () => ({
    type: "gallery",
    label: "Gallery",
    images: ["https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1470770841072-f978cf4d019e?w=400&h=400&fit=crop&q=80", "https://images.unsplash.com/photo-1418065460487-3e41a6c84dc5?w=400&h=400&fit=crop&q=80"]
  }),
  form: () => ({
    type: "form",
    heading: "Join the Friday newsletter",
    sub: "One film, one story, one place — every Friday.",
    button: "Subscribe",
    placeholder: "you@email.com",
    nameField: false
  })
};
Object.assign(window, {
  HUB,
  BLOCK_DEFAULTS
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/hubData.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/icons.jsx
try { (() => {
/* Shared icon helper for the Ikiro editor kit.
   Renders Lucide icons (loaded via UMD) as React SVGs, plus the Ikiro
   wordmark/mark from the asset PNGs. Exposed on window for sibling scripts. */

function toPascal(s) {
  return String(s).replace(/(^|[-_ ])([a-z0-9])/g, (_, sep, ch) => ch.toUpperCase());
}
function Icon({
  name,
  size = 20,
  stroke = 2,
  ...rest
}) {
  const lib = typeof window !== "undefined" && window.lucide && window.lucide.icons;
  // Lucide nodes are ["svg", svgAttrs, children]; keys are PascalCase.
  const data = lib && (lib[toPascal(name)] || lib[name]);
  if (!Array.isArray(data)) return null;
  const children = Array.isArray(data[2]) ? data[2] : [];
  return React.createElement("svg", {
    width: size,
    height: size,
    viewBox: "0 0 24 24",
    fill: "none",
    stroke: "currentColor",
    strokeWidth: stroke,
    strokeLinecap: "round",
    strokeLinejoin: "round",
    ...rest
  }, children.map((c, i) => React.createElement(c[0], {
    key: i,
    ...c[1]
  })));
}
Object.assign(window, {
  Icon
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/icons.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/importData.jsx
try { (() => {
/* importData — the bio-import wedge's data + deterministic mapper.

   A pasted bio link (Linktree / Beacons / lnk.bio) is fetched server-side
   (SSRF-safe, public only) and reduced to a flat list of {title, url} rows plus
   a scraped profile. The MAPPER turns that raw scrape into a Default Link Hub:
     • registry detectService(url) supplies the icon + service name (the "real
       work" the import shows off) — no model call;
     • routeOf(url) decides the destination block: platform strip / lead media /
       tappable link, deterministically from host + path;
     • exact destination URLs are preserved verbatim through the whole pipeline.
   The result is the same data shape LinkHubPage already renders. */

const {
  SERVICES: IMP_SVC,
  detectService: imp_detect
} = window;

/* What a public Linktree-style page reduces to after the SSRF-safe fetch. */
const IMPORT_SOURCE = {
  source: "Linktree",
  sourceUrl: "linktr.ee/remitravels",
  profile: {
    name: "Remi Solène",
    handle: "@remitravels",
    bio: "Photographer & slow-travel guide. A new film every Friday.",
    avatar: "https://images.unsplash.com/photo-1502685104226-ee32379fefbe?w=240&h=240&fit=crop&q=80"
  },
  // The raw rows, in the order they appear on the source page.
  rawLinks: [{
    title: "YouTube",
    url: "https://youtube.com/@remitravels"
  }, {
    title: "Instagram",
    url: "https://instagram.com/remitravels"
  }, {
    title: "TikTok",
    url: "https://tiktok.com/@remitravels"
  }, {
    title: "Twitter / X",
    url: "https://x.com/remitravels"
  }, {
    title: "Listen on Spotify",
    url: "https://open.spotify.com/user/remitravels"
  }, {
    title: "Sardinia in 4K — the new film",
    url: "https://youtu.be/aQ8sh180bd"
  }, {
    title: "Free Light & Travel guide (PDF)",
    url: "https://remitravels.co/guide"
  }, {
    title: "Lightroom preset pack — Coastal Gold",
    url: "https://gumroad.com/l/coastalgold"
  }, {
    title: "Join the Friday newsletter",
    url: "https://remitravels.substack.com"
  }, {
    title: "Book a travel shoot",
    url: "https://calendly.com/remitravels/shoot"
  }]
};

/* Known bio-link hosts we can read. Drives the source chip on the paste screen. */
const IMPORT_HOSTS = {
  "linktr.ee": "Linktree",
  "lnk.bio": "Lnk.Bio",
  "beacons.ai": "Beacons",
  "bio.link": "Bio.link",
  "campsite.bio": "Campsite",
  "solo.to": "Solo",
  "linkin.bio": "Link in Bio"
};
function detectImportSource(value) {
  if (!value) return null;
  let host = "";
  try {
    host = new URL(value.includes("://") ? value : "https://" + value).hostname.replace(/^www\./, "");
  } catch (e) {
    return null;
  }
  for (const h in IMPORT_HOSTS) {
    if (host === h || host.endsWith("." + h)) return {
      host: h,
      name: IMPORT_HOSTS[h]
    };
  }
  return null;
}
function parseUrl(url) {
  try {
    const u = new URL(url.includes("://") ? url : "https://" + url);
    return {
      host: u.hostname.replace(/^www\./, ""),
      path: u.pathname
    };
  } catch (e) {
    return {
      host: "",
      path: ""
    };
  }
}

/* Where does a raw link belong on the rebuilt page? Deterministic, host+path. */
function routeOf(url) {
  const {
    host,
    path
  } = parseUrl(url);
  // A watchable video => the single Lead Media slot.
  if (/(^|\.)youtu\.be$/.test(host) || /youtube\.com$/.test(host) && /\/(watch|shorts|live)/.test(path)) return "lead";
  const svc = imp_detect(url);
  const kind = svc ? IMP_SVC[svc].kind : null;
  // Identity profiles (incl. a YouTube channel / Spotify profile) => icon strip.
  if (kind === "social") return "strip";
  if (svc === "youtube" && /^\/(@|c\/|channel\/|user\/)/.test(path)) return "strip";
  if (svc === "spotify" && /^\/(user|artist)\//.test(path)) return "strip";
  // Everything else is a tappable link (keeps its detected service glyph).
  return "link";
}

/* Per-link presentation hints discovered during enrichment (P20-S06 fast-follow:
   live OG title / thumbnail). Demo ships the lead's enrichment inline. */
const LEAD_ENRICH = {
  title: "Sardinia in 4K — the new film",
  desc: "28 minutes along the wild eastern coast, shot at golden hour. Out now.",
  thumb: "https://images.unsplash.com/photo-1505228395891-9a51e7e86bf6?w=720&h=420&fit=crop&q=80"
};

/* Annotate each raw row with what the registry detected + where it routes.
   This is the list the scan screen streams, one row at a time. */
function analyzeImport(src) {
  return src.rawLinks.map((raw, i) => {
    const service = imp_detect(raw.url);
    const svc = service ? IMP_SVC[service] : null;
    const route = routeOf(raw.url);
    return {
      i,
      title: raw.title,
      url: raw.url,
      host: parseUrl(raw.url).host,
      service,
      // registry key or null
      serviceName: svc ? svc.name : null,
      color: svc ? svc.color : null,
      route,
      // "strip" | "lead" | "link"
      matched: !!svc
    };
  });
}

/* Fold the analyzed rows into the LinkHubPage data shape. */
function buildHub(src) {
  const rows = analyzeImport(src);
  const socials = rows.filter(r => r.route === "strip").map((r, n) => ({
    id: "s" + (n + 1),
    service: r.service,
    url: r.url
  }));
  const leadRow = rows.find(r => r.route === "lead");
  const lead = leadRow ? {
    id: "lead",
    service: leadRow.service || "youtube",
    title: LEAD_ENRICH.title,
    desc: LEAD_ENRICH.desc,
    url: leadRow.url,
    thumb: LEAD_ENRICH.thumb
  } : null;
  const links = rows.filter(r => r.route === "link").map((r, n) => ({
    id: "l" + (n + 1),
    title: r.title,
    url: r.url,
    service: r.service || null
  }));
  return {
    profile: {
      ...src.profile,
      backdrop: "https://images.unsplash.com/photo-1505228395891-9a51e7e86bf6?w=1280&q=80",
      footerNote: "Remi Solène — coastal photography & slow travel.",
      contact: "hello@remitravels.co"
    },
    socialsPosition: "top",
    socials,
    lead,
    links
  };
}
Object.assign(window, {
  IMPORT_SOURCE,
  IMPORT_HOSTS,
  detectImportSource,
  analyzeImport,
  buildHub,
  routeOf
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/importData.jsx", error: String((e && e.message) || e) }); }

// ui_kits/studio/registry.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
/* Service registry — the backbone of the Platform Icon Strip and the Add
   composer's auto-detection. Brand glyphs come from simple-icons via the
   cdn.simpleicons.org service (authentic, monochrome, recolorable).
   Generic UI icons (plus, pencil, drag) come from Lucide via <Icon>. */

const SERVICES = {
  youtube: {
    name: "YouTube",
    slug: "youtube",
    color: "#FF0000",
    kind: "video",
    domains: ["youtube.com", "youtu.be"]
  },
  instagram: {
    name: "Instagram",
    slug: "instagram",
    color: "#E4405F",
    kind: "social",
    domains: ["instagram.com"]
  },
  tiktok: {
    name: "TikTok",
    slug: "tiktok",
    color: "#111111",
    kind: "social",
    domains: ["tiktok.com"]
  },
  x: {
    name: "X",
    slug: "x",
    color: "#111111",
    kind: "social",
    domains: ["x.com", "twitter.com"]
  },
  spotify: {
    name: "Spotify",
    slug: "spotify",
    color: "#1DB954",
    kind: "music",
    domains: ["spotify.com", "open.spotify.com"]
  },
  applemusic: {
    name: "Apple Music",
    slug: "applemusic",
    color: "#FA243C",
    kind: "music",
    domains: ["music.apple.com"]
  },
  soundcloud: {
    name: "SoundCloud",
    slug: "soundcloud",
    color: "#FF5500",
    kind: "music",
    domains: ["soundcloud.com"]
  },
  threads: {
    name: "Threads",
    slug: "threads",
    color: "#111111",
    kind: "social",
    domains: ["threads.net"]
  },
  linkedin: {
    name: "LinkedIn",
    slug: "linkedin",
    color: "#0A66C2",
    kind: "social",
    domains: ["linkedin.com"]
  },
  github: {
    name: "GitHub",
    slug: "github",
    color: "#181717",
    kind: "social",
    domains: ["github.com"]
  },
  substack: {
    name: "Substack",
    slug: "substack",
    color: "#FF6719",
    kind: "link",
    domains: ["substack.com"]
  },
  gumroad: {
    name: "Gumroad",
    slug: "gumroad",
    color: "#FF90E8",
    kind: "offer",
    domains: ["gumroad.com"]
  },
  calendly: {
    name: "Calendly",
    slug: "calendly",
    color: "#006BFF",
    kind: "booking",
    domains: ["calendly.com"]
  },
  patreon: {
    name: "Patreon",
    slug: "patreon",
    color: "#000000",
    kind: "offer",
    domains: ["patreon.com"]
  }
};

// Lucide fallbacks for non-brand link kinds (used when no service matches).
const KIND_ICON = {
  link: "link",
  social: "at-sign",
  video: "play",
  music: "music",
  booking: "calendar",
  offer: "tag",
  contact: "mail",
  website: "globe",
  collection: "layout-list"
};
function detectService(url) {
  if (!url) return null;
  let host = "";
  try {
    host = new URL(url.includes("://") ? url : "https://" + url).hostname.replace(/^www\./, "");
  } catch (e) {
    return null;
  }
  for (const key in SERVICES) {
    if (SERVICES[key].domains.some(d => host === d || host.endsWith("." + d))) return key;
  }
  return null;
}

/* Brand glyph as an <img> from simple-icons. color: hex without # or a name
   like "white". Falls back silently if the slug is unknown. */
function BrandIcon({
  slug,
  color,
  size = 20,
  style,
  ...rest
}) {
  const c = (color || "").replace("#", "") || "_";
  return /*#__PURE__*/React.createElement("img", _extends({
    src: `https://cdn.simpleicons.org/${slug}/${c}`,
    width: size,
    height: size,
    alt: "",
    onError: e => {
      e.currentTarget.style.visibility = "hidden";
    },
    style: {
      width: size,
      height: size,
      display: "block",
      ...style
    }
  }, rest));
}
Object.assign(window, {
  SERVICES,
  KIND_ICON,
  detectService,
  BrandIcon
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/studio/registry.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Avatar = __ds_scope.Avatar;

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.Tag = __ds_scope.Tag;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.Switch = __ds_scope.Switch;

__ds_ns.Textarea = __ds_scope.Textarea;

__ds_ns.Tabs = __ds_scope.Tabs;

__ds_ns.LinkRow = __ds_scope.LinkRow;

__ds_ns.Stat = __ds_scope.Stat;

})();
