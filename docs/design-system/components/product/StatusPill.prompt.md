The team's signature status indicator: a pill with a colored dot. `running` blinks — the same heartbeat as the live logo block.

```jsx
<StatusPill status="running" />
<StatusPill status="done" />
<StatusPill status="failed">Auth expired</StatusPill>
```

Statuses: `queued` · `running` (blinks) · `done` · `failed` · `timedout`. Pass children to override the label.
