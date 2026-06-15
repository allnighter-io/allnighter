Contextual dropdown menu — the kebab/⋯ on a run or worker, right-click actions. Closes on pick, outside-click, or Esc.

```jsx
<Menu align="end" trigger={<IconButton label="More"><Icon name="settings-2" /></IconButton>}
  items={[
    { label: 'Rerun', icon: <Icon name="rotate-cw" /> },
    { label: 'Duplicate', icon: <Icon name="copy" />, kbd: '⌘D' },
    { divider: true },
    { label: 'Delete run', icon: <Icon name="x" />, danger: true },
  ]} />
```

Item fields: `label`, `icon`, `onClick`, `kbd`, `danger`, `divider`, `heading`.
