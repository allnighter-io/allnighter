The base surface for grouping content — panels, list rows, stat tiles, upsell blocks. Hairline border + small shadow on a raised midnight surface.

```jsx
<Card>
  <h3>Master plan</h3>
  <p>Consensus, conflicts, and a decisive plan.</p>
</Card>
<Card variant="accent" interactive>Upgrade for deep analytics</Card>
```

Variants: `default` (raised), `flush` (sits on panel surface), `accent` (amber-tinted). `interactive` adds the hover-lift; `pad` toggles the default padding.
