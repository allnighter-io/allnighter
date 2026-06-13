# 09 — iOS App MVP

Status: Draft
Milestone: C (Mobile floor manager)
Depends on: 01, 08
Owner: iOS
Created: 2026-06-13

## Goal

Ship the iPhone floor manager's core: pair with the Mac, show Home (factory
status), show Active Lanes with plain-language statuses, view a lane's latest
artifact, and provide the **global kill switch** and basic landing actions. Built
on `AllnighterCore` fixtures first, then live API.

## Non-Goals

- Capture/work orders (Phase 10), race/council review (Milestone D), push/Live
  Activities (Phase 20). Typing-heavy flows — keep decisions to 1–2 taps.

## Approach (per `00`, Principles 1–4)

- SwiftUI app, `@Observable` view models hydrated from `AllnighterCore` fixtures,
  then swapped to the live `/events/stream` + snapshot client (`00` §5).
- **Pairing:** scan QR / enter code → submit Ed25519 pubkey → store trusted Mac.
- **Home:** active agent-hours, idle/busy workers, top pending decisions, next
  quota reset (placeholder until Phase 17), Morning Pull entry (placeholder).
- **Active Lanes:** worker, task, plain-language status, elapsed time, latest
  artifact, stop control.
- **Landing actions:** for a green-tier card, land / ask-for-changes / open-on-Mac.
- **Kill switch:** prominent global `stop-all` (IOS-9).
- Use the hidden-plumbing vocabulary everywhere (lane/draft/worker/landing).

## Ordered Slices

- [ ] P09-S01 — iOS app target (XcodeGen) + `AllnighterCore` dependency + fixture-backed view models.
- [ ] P09-S02 — Pairing flow (Bonjour discover + code/QR + pubkey).
- [ ] P09-S03 — Live client: snapshot + resumable `/events/stream` with dedupe.
- [ ] P09-S04 — Home screen (status, workers, pending decisions).
- [ ] P09-S05 — Active Lanes list + lane detail with latest artifact + stop.
- [ ] P09-S06 — Global kill switch (`/control/stop-all`).
- [ ] P09-S07 — Green-tier landing card actions (land / changes / open on Mac).

## Works Test

```text
The iPhone discovers and pairs with the Mac, shows it online, lists live lanes
with plain-language statuses, shows a lane's latest screenshot, lands a green-tier
card, and the global kill switch stops all work on the Mac. Dropping and
restoring the connection loses no events.
```

## Exit Gates

- [ ] Works Test passes against a live Mac.
- [ ] App renders fully from fixtures with the Mac offline (graceful).
- [ ] IOS-1, IOS-4, IOS-8, IOS-9, IOS-15 satisfied.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 10 (capture). The decision loop now has a home on the phone.
