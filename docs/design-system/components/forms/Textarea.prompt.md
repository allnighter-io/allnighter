Multi-line text field — the prompt composer and any long-form entry. Vertically resizable; carries label, hint, and an optional character counter.

```jsx
<Textarea label="Ask the panel" rows={3} placeholder="Ask the panel one thing…" />
<Textarea label="Notes" maxLength={280} showCount hint="Saved locally." />
```

`showCount` + `maxLength` renders a mono `count/limit` readout in the corner. `mono` switches to the mono face. Focus shows the amber ring.
