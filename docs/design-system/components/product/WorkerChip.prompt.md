A worker in the team or the live run grid: brand glyph, name, model ID, and run status. Selectable in the team; read-only with status/meta in the run view.

```jsx
// Team — pick which workers answer
<WorkerChip name="Opus 4.8" model="via claude-code"
  glyph={<img src="https://cdn.simpleicons.org/anthropic/E1E5F0" />}
  selectable selected onToggle={toggle} />

// Live run — show progress
<WorkerChip name="Gemini Flash" model="via gemini-cli" status="running"
  meta="842 tok · 00:21"
  glyph={<img src="https://cdn.simpleicons.org/googlegemini/E1E5F0" />} />
```

Composes `StatusPill`. `running` tints the border blue. Pass the brand glyph as a node (Simple Icons `<img>` or your own asset).
