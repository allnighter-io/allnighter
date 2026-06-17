# Anchored popups — `alPopover`

**Status:** Canonical / Always True
**Applies to:** every menu, picker, or dropdown that opens from a button and
must sit relative to that button (compose mode menu, routing target picker,
team dropdown, effort menus, any future "click this chip → panel appears").

## The bug this kills

A popup that does not appear directly on its trigger. Floating in the corner,
clipped at a window edge, drifting when the window resizes, or covering the
button it came from. We hit this repeatedly because the popups were positioned
**by hand**.

## Why hand-positioning always loses

To place a panel above a button manually you have to: read the button's frame in
some coordinate space, pipe it up through a `PreferenceKey`, draw the panel in an
`overlay`, then offset it by the panel's own height (which you also have to
measure) plus a gap, then re-flip it when it would fall off screen, then add an
outside-tap catcher to dismiss it. Every one of those steps is a place to be a
few points wrong, and none of it survives a window resize or a different screen.
AppKit already does all of it correctly. Re-implementing it is the bug.

## The one right way

Attach the **native popover** to the trigger via the `alPopover` helper
(`Apps/AllnighterMac/Sources/DesignComponents.swift`):

```swift
Button { showMenu.toggle() } label: { triggerLabel }
    .buttonStyle(.plain)
    .alPopover(isPresented: $showMenu, arrowEdge: .top) {
        MenuPanel()        // your styled content; sizes itself
    }
```

- The popover renders in its own AppKit window, so it is **never clipped** by the
  parent and is **always anchored** to the button.
- AppKit owns positioning, screen-edge flipping, and outside-click dismissal.
- `arrowEdge: .top` means "arrow leaves the top of the trigger"; AppKit still
  re-places it to fit (a composer at the bottom of the window opens upward).
- `alPopover` forces dark color scheme + the brand surface background so the
  panel matches the app.

### Driving it from a single selection enum

When several triggers share one `@State var pop: Popover?`, bridge each trigger
to a `Bool` binding instead of inventing more state:

```swift
private func popBinding(_ which: Popover) -> Binding<Bool> {
    Binding(get: { pop == which }, set: { pop = $0 ? which : nil })
}
```

### Content rules

- Let the panel size itself (`.frame(width:)` is fine; the popover hugs it).
- Give the panel a solid `.background(ALColor.surface)` as a safety fill.
- Do **not** add your own drop shadow or outer border — the popover supplies its
  own chrome. Doubling them looks like a card inside a card.

## Banned

- `.overlayPreferenceValue` + `GeometryReader` + `.offset` to place a popup.
- `.alignmentGuide` math to nudge a panel above/below a control.
- A hardcoded `.offset(x:y:)` "until it looks right."
- A hand-built `Color.clear.onTapGesture` outside-dismiss layer.

If you find any of these positioning a popup, replace it with `alPopover`.

## Reference

- Helper: `alPopover` in `Apps/AllnighterMac/Sources/DesignComponents.swift`.
- Live use: `RoutingComposer.modePill` / `targetChip` in
  `Apps/AllnighterMac/Sources/RoutingComposer.swift`.
