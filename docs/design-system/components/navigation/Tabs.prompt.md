Switch between views or filter sets. `segmented` for compact in-panel switches, `underline` for page-level section nav.

```jsx
<Tabs
  variant="segmented"
  items={[{value:'all',label:'All',count:6},{value:'run',label:'Running',count:3}]}
  defaultValue="all"
  onChange={setFilter}
/>
```

Controlled (`value`) or uncontrolled (`defaultValue`). Items can carry a mono `count`.
