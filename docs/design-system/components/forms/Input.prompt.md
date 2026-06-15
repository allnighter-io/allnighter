Labelled text input with hint, error, and affix slots. Used everywhere data is entered.

```jsx
<Input label="Run name" placeholder="dashboard refresh" required />
<Input label="Synthesizer" prefixText="model:" mono placeholder="opus-4.8" />
<Input label="Timeout" suffix="sec" defaultValue="120" />
```

`mono` sets the mono face for slugs/IDs/paths. `error` turns the field red and replaces the hint. Focus shows the amber ring.
