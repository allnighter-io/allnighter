# 02 — iOS App Shell (the remote floor manager)

Status: Draft — **deferred GUI**. Build after `01`'s spine is green.
Milestone: iOS (Remote Floor Manager)
Depends on: `01_Connection_Spine.md` (its `RemoteClient` + reducer), `00`,
`../../mvp/00_MVP_Architecture.md`
Owner: iOS
Created: 2026-06-15

## Goal

Ship the phone's core surfaces: onboard (Tailscale + pair), see what the Mac is
doing, **review finished runs/lanes**, **send new work requests**, and hit the
**global kill switch** — from anywhere, over the `01` spine. The reusable bones of
old `../ON HOLD/09_iOS_App_MVP.md`, re-pointed at Tailscale + the `RemoteClient`
that `01` already proved. This phase is **presentation only**: it must not
reimplement transport, state interpretation, or auth — those live in Core (`01`).

## Pre-req — delete the template scaffold (verified drift)

The repo currently has a root-level `Allnighter/Allnighter.xcodeproj` — a **vanilla
SwiftData Xcode template** (`Item.swift`, a persistent `ModelContainer`,
`ContentView` with `@Query`). It is wrong on two counts and must be removed before
this phase: (1) it persists durable model truth on the device, violating "the Mac
is the source of truth"; (2) it is a hand-managed `.xcodeproj` at the repo root,
not XcodeGen under `Apps/`, unlike `AllnighterMac`. First slice deletes it and
stands up `Apps/AllnighteriOS/` via XcodeGen depending on `AllnighterCore`.

> Pre-req note: `docs/FOLDER_MAP.md` routes to Allnighter paths (`AllnighterCore`,
> `Apps/AllnighterMac/`, `docs/`). `AGENTS.md` is owned separately — trust this
> folder + `docs/mvp/` for iOS-specific execution truth.

## Non-Goals

- New backend behavior — the phone only drives what `01` exposes.
- Push / Live Activities (deferred seam — `00` §5).
- Typing-heavy authoring. The phone is a *floor manager*, not a full composer;
  keep decisions to 1–2 taps.

## Platform decisions (state them; cheap to get wrong)

- **Minimum deployment target: iOS 17.** `@Observable` is iOS 17+; the modern
  SwiftUI/Observation idioms the Mac app already uses need it. No reason to floor
  lower.
- **No durable run truth on device.** State comes from `01`'s `RemoteClient` and a
  **cache** (below). SwiftData/Core Data are not used for run truth.

## Cache vs. fixtures — keep them architecturally separate (common SwiftUI bug)

Two distinct sources of "data when the Mac isn't answering," and they must never
blur:

- **Dev fixtures** — `AllnighterCore` JSON (`run_inflight.json` etc.), used only
  in `#if DEBUG` / Xcode Previews to build screens before/without a live Mac. They
  must **never** render in a production build.
- **Production cache** — the last `SnapshotEnvelope` + applied events, persisted to
  device storage (a plain `Codable` blob in Application Support, *not* a model
  store), so the app shows **real** last-known state offline, labeled "last seen
  <time>" (`01` honesty). Invalidated/replaced on the next successful snapshot.

The view-model init path selects exactly one source — fixture (debug only) or
cache→live — so fixtures can't leak into shipping. This is its own slice.

## Onboarding = the `01` diagnostic ladder, made visual

Reuse `01`'s `ConnectionDiagnosis`; don't invent new logic. A first-run wizard,
4–5 screens max, with the "why" copy from `00`/`README` on screen 1 ("private
Tailscale connection; your Mac is never on the public internet; we never see your
traffic"):

1. **Install/enable Tailscale** — App Store **smart link**
   (`apps.apple.com/app/tailscale/id1475387142`; shows *Open* if installed). No
   `tailscale://` scheme exists — detection is reachability + a `utun`/CGNAT hint
   only (`01`).
2. **Sign in with the SAME account as your Mac** — the #1 silent failure; the
   pairing payload's `tailnetName` lets the app catch a mismatch and say so.
3. **Scan QR (or enter the backup code)** — *gated on a green `/health` probe* so
   users never scan-and-fail.
4. **Wait for Mac approval** — show progress on both sides (phone: "waiting for
   approval"; Mac: "Allow remote control for <device>?"), with the pairing token's
   **TTL countdown** visible.

**Five-light status** (Mac side mirrors this, `01` preflight): Mac app ready ·
Tailscale on Mac · Tailscale on phone · same tailnet reachable · device approved.
Each red light gets one concrete fix. Connection failures are **distinct states**,
never a generic "offline": Tailscale-off-phone / Tailscale-off-Mac / **Mac asleep**
/ server-not-running / unapproved (`01` § Connectivity).

## Surfaces

- **Home:** Mac state (online / asleep / unreachable, with last-seen), active
  run/lane count, top pending decisions, a **prominent always-visible kill
  switch**, and a quick "new work request" entry.
- **Active runs/lanes:** worker, prompt/task, plain-language status, elapsed time,
  latest artifact; tap → detail (master plan / latest output + a stop control).
- **Review:** read a finished run's master plan / final spec; landing actions where
  applicable (land / ask-for-changes / open-on-Mac), routed as `01` commands.
- **New work request:** preset + prompt → start a run on the Mac (`01` command).
  The headline "send out more work while walking" flow — prioritized right after
  Home + Active, before Review polish.
- **Settings → Trusted devices:** list approved phones + last-seen, **revoke**
  (the lost-phone safety valve; the action is `01`'s `pair revoke`).
- Vocabulary: panel / run / worker / lane / landing (`../../mvp/README.md` §4).

## Deferred seam — Attention Queue (design now, build later)

Don't let Home become a raw log viewer. The Mac will eventually emit first-class
*attention items* (`needs_read`, `needs_pick`, `needs_approval`,
`failed_needs_decision`, `ready_to_build`, `ready_to_land`) that become Home,
future Morning Pull, notifications, and Shortcuts. **Not built in v1** — but keep
Home reading from a small typed summary, not by scraping raw runs, so the queue
drops in without a rewrite. (Same posture as the `PushNotifier` seam.)

## Fixture → screen map (decide now, saves design thrash)

`run_inflight.json` → Active runs/lanes; `run_complete.json` → Review (master
plan); `run_partial.json` → Review with a failed seat. Previews bind these.

## Ordered Slices

- [ ] iOS02-S01 — Delete the SwiftData template; stand up `Apps/AllnighteriOS/`
  (XcodeGen) on `AllnighterCore`, iOS 17 target; `scripts/check.sh` runs its scheme.
- [ ] iOS02-S02 — Onboarding wizard over `ConnectionDiagnosis` (5 lights,
  same-account guidance, QR gated on green `/health`).
- [ ] iOS02-S03 — Bind to `01`'s **live `RemoteClient`** (swap fixture source →
  live; no transport code here) + the production **cache** layer.
- [ ] iOS02-S04 — Home (state, active count, pending decisions) **with a working
  kill switch wired the moment the client connects** (see below).
- [ ] iOS02-S05 — Active runs/lanes list + detail (status, latest output, stop).
- [ ] iOS02-S06 — New work request (preset + prompt → start run).
- [ ] iOS02-S07 — Review a finished run (master plan / final spec) + landing.
- [ ] iOS02-S08 — Settings → Trusted devices + revoke.
- [ ] iOS02-S09 — Kill-switch polish (confirm dialog, terminated-count feedback,
  haptics). *Functionality lands in S04; this is the hardening pass.*

> **Kill switch is safety-critical, so capability exists from S04, not S08.** It is
> a single `/control/stop-all` call (returns a confirmed count, `01`) with no UI
> complexity — wiring it the moment the live client connects means testing S05–S07
> always has a stop. The dedicated late slice is only polish.

## Works Test

```text
On cellular (off the Mac's wifi), the phone is paired and shows the Mac online,
lists live runs with plain-language statuses, opens a finished run and reads its
master plan, sends a new work request that starts a council run on the Mac, and
the global kill switch stops all work and shows the terminated count. Walking
through a dead zone (drop + restore) loses no events (resume via 01). With the Mac
asleep the app shows "asleep, last seen <time>" — not a generic error — and renders
last-known state from the production cache. A DEBUG build's fixtures never appear
in a release build.
```

## Exit Gates

- [ ] Works Test passes against a live Mac **over cellular** (proves from-anywhere).
- [ ] No transport/auth/reducer logic in the app target — all from Core (`01`).
- [ ] No durable run truth on device; cache is a plain blob; fixtures are DEBUG-only
  (verified absent from a release build).
- [ ] Distinct connection states (asleep / server-off / wrong-tailnet) shown, never
  generic "offline."
- [ ] `swift test` + `xcodebuild test` (iOS scheme) green via `scripts/check.sh`;
  Code Audit CLEAN.

## Closeout

The decision loop has a home on the phone: check in, review, dispatch, stop — from
anywhere. Next deferred layers: push (`00` §5) so the phone can ring, and the
Attention Queue so Home becomes a decision list, not a log.
