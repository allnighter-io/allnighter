Primary action control — use for any click target that performs an action; `primary` (amber) for the single most important action on a surface (Run council, Synthesize), `secondary` for supporting actions, `ghost` for low-emphasis/toolbar actions, `danger` for destructive ones.

```jsx
<Button variant="primary" iconLeft={<Icon name="Play" />}>Run council</Button>
<Button variant="secondary">Add worker</Button>
<Button variant="ghost" size="sm">Cancel</Button>
```

Sizes: `sm` (24px) · `md` (30px, default) · `lg` (36px). `block` stretches full width. Primary gains the amber glow on hover; all variants press with `scale(0.97)`. Pass icons as nodes via `iconLeft` / `iconRight` — the button doesn't depend on any icon set.
