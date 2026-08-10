# Debugger Packet — Cursor missing from home CLI strip after Find my team

Date: 2026-08-10
Tier: T2 SSOT (cross-surface projection; persisted probe → home strip)
Status: fixed (code + Works Test green)

## Fingerprint

```text
HomeMarketingCLIStrip.visibleCards + omit .notInstalled when any .ready
+ Cursor.app present / cursor_agent .notInstalled invisible after Find my team
+ truth owner HomeMarketingCLIStrip; prior fe8acf5e only patched TeamReadinessView
```

## Symptom

Fresh Allnighter install → Find my team → home chips show Claude / Codex / Grok /
OpenCode. Cursor never appears. Cursor.app is on the Mac; Agent CLI may be missing.

## Truth owner

`HomeMarketingCLIStrip.visibleCards` (FLCS-S01) — projects `setupCards` to the
home marketing chip row. Probe truth remains `ToolProbeRecord` / `AppModel.setupCards`.
Promotion rule: `CLISetupGrouping.cursorInstallPromptCards` /
`CursorAgentCLIInstall.shouldPromptInstall`.

## Lie-prone layer

Home chip filter that treats every `.notInstalled` as a catalog absence once any
CLI is `.ready`. Correct for random unsupported installs; a lie for Cursor when
`Cursor.app` proves the user already pays for that product.

Secondary: `BenchHealthPopover` also used `recognizedCards` only (patched in same
fix). Full CLI setup (`TeamReadinessView`) was patched in fe8acf5e; Find-my-team
home surface was not.

## Missing proof (pre-fix)

No Works Test that: Cursor.app present + `cursor_agent` `.notInstalled` + at least
one other `.ready` ⇒ Cursor remains in `HomeMarketingCLIStrip.visibleCards`.
`testAfterScanShowsOneCardPerCLI` encoded the opposite generic rule.

## Root cause

```swift
// HomeMarketingCLIStrip.visibleCards (pre-fix)
if hasReady {
    return cards.filter { $0.state != .notInstalled }
}
```

After Find my team, Codex/Grok are ready → Cursor (notInstalled) dropped.
fe8acf5e only merged `cursorInstallPromptCards` into `TeamReadinessView.attentionCards`.

Confirmed independently by Sonnet review (same fingerprint).

## Fix

1. `HomeMarketingCLIStrip.visibleCards` keeps `cursorInstallPromptCards` when filtering.
2. Cursor install-prompt cards use amber `.attention` dots, not dormant gray.
3. `BenchHealthPopover.attentionCards` merges the same prompt cards.
4. Works Test: `testCursorAppPresentKeepsNotInstalledWhenOthersReady` (green).

## Regression law

Never hide `cursor_agent` from the home Find-my-team chip row when Cursor.app is
present and the Agent CLI is absent. Any future "surface despite catalog absence"
override must live in `CLISetupGrouping` / `CursorAgentCLIInstall` and be applied
at every `.notInstalled` filter call site before closeout.
