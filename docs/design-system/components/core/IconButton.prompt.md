Icon-only button for toolbars, editor chrome, and card affordances. Always pass a `label` for accessibility (it also becomes the tooltip).

```jsx
<IconButton label="Copy" onClick={copy}><Icon name="Copy" /></IconButton>
<IconButton variant="outline" label="Settings"><Icon name="Settings2" /></IconButton>
```

Variants: `ghost` (default), `outline`, `solid`, `accent` (amber). Sizes `sm`/`md`/`lg`. Presses with `scale(0.93)`.
