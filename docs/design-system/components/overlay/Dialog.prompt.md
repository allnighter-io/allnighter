Modal dialog — confirm a destructive action (Stop all, Revert landing), a focused form, or settings. Backdrop blur + scrim; closes on backdrop click or Esc.

```jsx
<Dialog open={open} onClose={close}
  icon={<Icon name="square" />} iconTone="danger"
  title="Stop all runs?" description="3 workers are still running. Their answers will be discarded."
  footer={<>
    <Button variant="ghost" onClick={close}>Keep running</Button>
    <Button variant="danger" onClick={stopAll}>Stop all</Button>
  </>} />
```

Sizes `sm`/`md`/`lg`. Put action Buttons in `footer`.
