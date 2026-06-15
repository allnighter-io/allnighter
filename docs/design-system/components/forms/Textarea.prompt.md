Multi-line input for prompts, descriptions, and notes. Optional live character counter. The team's prompt composer is a `Textarea`.

```jsx
<Textarea label="Prompt" rows={6} placeholder="Ask the team one thing…" />
<Textarea label="Note" maxLength={280} showCount hint="Seasons the work order" />
```

`mono` switches to the mono face. Set `maxLength` + `showCount` for the counter.
