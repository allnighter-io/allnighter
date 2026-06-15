Single-line text field — use for short text entry: names, search, model IDs, paths. Carries its own label, hint/error, and optional mono prefix/suffix.

```jsx
<Input label="Run name" placeholder="premium dashboard directions" required />
<Input label="Endpoint" mono prefixText="https://" defaultValue="localhost:8080" />
<Input label="Token" error="Auth expired — re-link the CLI" />
```

`size`: `md` (30px) · `lg` (36px). `mono` sets the value in the mono face. `error` reddens the border and replaces `hint`. Focus shows the amber ring.
