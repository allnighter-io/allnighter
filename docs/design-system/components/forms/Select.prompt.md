Dropdown select — choose the plan writer, a team preset, a risk tier. Closes on pick or outside-click.

```jsx
<Select label="PlanWriter" defaultValue="opus" onChange={setSynth}
  options={[{value:'opus',label:'Opus 4.8'},{value:'sonnet',label:'Sonnet 4.6'}]} />
```

`mono` renders the value in the mono face; `leading` slots a glyph before it.
