# 23 — Distribution and Dogfood

Status: Draft
Milestone: F (Always-on and ship)
Depends on: 05, 09, 20
Owner: Mac + iOS + Relay
Created: 2026-06-13

## Goal

Ship installable builds and a diagnostics story so the founder can dogfood the
full loop daily on real devices: notarized Mac DMG, TestFlight iOS, a `doctor`
that catches setup problems, and the daily dogfood ritual.

## Non-Goals

- App Store submission (after TestFlight dogfood) and auto-update polish can be
  incremental.

## Approach (per `00` §13)

- **Mac:** Developer ID signed, **notarized DMG**, hardened runtime with the
  entitlements needed to spawn processes and read enrolled paths; menu bar +
  command center; an auto-update channel (e.g. Sparkle).
- **iOS:** TestFlight build; pairing onboarding; BYOK/permissions wizard (Keychain
  for keys, first-run copy for Full Disk Access + Local Network prompts).
- **Doctor:** `scripts/doctor` + in-app Diagnostics tab checking git, driver smoke
  tests, port availability, Node/Playwright sidecar, permissions, relay
  reachability — with actionable fixes.
- **Dogfood loop:** install both, run the North-Star demo (README §4) daily, file
  issues into the backlog (closing the speculative-build source loop).

## Ordered Slices

- [ ] P23-S01 — Notarized, signed Mac DMG with required entitlements + hardened runtime.
- [ ] P23-S02 — Auto-update channel.
- [ ] P23-S03 — TestFlight iOS build + pairing onboarding.
- [ ] P23-S04 — BYOK Keychain flow + first-run permissions wizard (Full Disk Access, Local Network).
- [ ] P23-S05 — `doctor` script + Diagnostics tab (git, drivers, ports, sidecar, permissions, relay).
- [ ] P23-S06 — Daily dogfood ritual running the North-Star demo end to end.

## Works Test

```text
Install the notarized DMG and the TestFlight build on real devices and complete
the North-Star demo (README §4) end to end: dictate three dashboard directions,
get three drafts, pick one with a note, implement it, and land it — with revert
available. `doctor` flags any missing dependency before the run.
```

## Exit Gates

- [ ] Works Test (North-Star demo) passes on real Mac + iPhone.
- [ ] BYOK keys in Keychain; never stored on iOS (IOS-15).
- [ ] `doctor` catches a deliberately-broken dependency.
- [ ] Code Audit CLEAN.

## Closeout

v1 shippable. Promote durable operational truth into `00`; archive completed
phases. The product now runs the loop the README describes.
