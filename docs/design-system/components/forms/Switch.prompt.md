On/off toggle for settings and preferences. The track turns amber when on and the thumb springs across — the one place a spring easing is used.

```jsx
<Switch label="Run on a schedule" description="Kick off the council nightly at 3am." defaultChecked />
<Switch label="Local only" checked={local} onChange={e => setLocal(e.target.checked)} />
```

Pass `label` and optional `description` for a stacked text block, or use it bare as a standalone control. Honors `disabled`.
