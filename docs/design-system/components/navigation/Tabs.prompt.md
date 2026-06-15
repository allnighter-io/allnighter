Tab strip for switching between views. `segmented` reads as a compact control (e.g. Master plan / Member answers); `underline` reads as a section header. Controlled or uncontrolled.

```jsx
<Tabs variant="segmented" defaultValue="plan" onChange={setTab}
  items={[{ value: 'plan', label: 'Master plan' },
          { value: 'answers', label: 'Member answers', count: 6 }]} />

<Tabs variant="underline" value={view} onChange={setView}
  items={[{ value: 'overview', label: 'Overview' }, { value: 'logs', label: 'Logs' }]} />
```

Each item takes `value`, `label`, and an optional mono `count`. The active tab is amber-underlined (underline) or filled (segmented).
