# 02 - iOS App Shell (the remote Project Manager)

Status: Draft — **deferred iOS GUI**. Build after the macOS app is done and
after `01`'s spine is green.
Milestone: iOS (Remote Project Manager)
Owner: iOS
Created: 2026-06-15
Updated: 2026-06-17 (Mac-first reset)
Depends on: `01_Connection_Spine.md` (its `RemoteClient` + reducer), `01a` (pairing),
`00`, `../../mvp/00_MVP_Architecture.md`, `../../mvp/Design0_Design_Team_Overview.md`

## Goal

Ship the phone's core surfaces: **sign in + pair**, see what the Mac is doing,
**review finished runs** (incl. **design boards**), **send new work requests**, and hit
the **global kill switch** — from anywhere, over the `01` cloud-first spine. This phase
is **presentation only**: it must not reimplement transport, state interpretation, or
auth — those live in Core (`01`).

The phone only ever sends `01`'s **typed commands** (`startRun`/`stopRun`/`stopAll`;
later `approveRequest`/`rejectRequest`/`openOnMac`/`landPlane`). **No shell, no
free-text-to-Mac pathway** — every button maps to one modeled, authorized command
(`00` §3.1). That constraint is the product's trust story; surface it.

## Pre-req — delete the template scaffold (verified drift)

The repo has a root-level `Allnighter/Allnighter.xcodeproj` — a vanilla **SwiftData
Xcode template** (`Item.swift`, a persistent `ModelContainer`, `@Query`). Remove it:
(1) it persists durable model truth on the device, violating "the Mac is truth"; (2)
it's a hand-managed `.xcodeproj` at the repo root, not XcodeGen under `Apps/`. First
slice deletes it and stands up `Apps/AllnighteriOS/` via XcodeGen on `AllnighterCore`.

> `docs/FOLDER_MAP.md` routes to Allnighter paths (`AllnighterCore`,
> `Apps/AllnighterMac/`, `docs/`). Trust this folder + `docs/mvp/` for iOS-specific
> execution truth.

## Non-Goals

- New backend behavior — the phone only drives what `01` exposes.
- Push / Live Activities (deferred seam — `00` §7).
- Typing-heavy authoring. The phone is a remote Project Manager, not a composer;
  1-2 taps.

## Platform decisions

- **Minimum deployment target: iOS 17.2** (`@Observable` shipped in 17.0 but had real
  `NavigationStack`/Observation bugs fixed by 17.2 — shipping on 17.0 invites crash
  reports).
- **No durable run truth on device.** State comes from `01`'s `RemoteClient` + a
  **cache** (below). SwiftData/Core Data are not used for run truth.

## Cache vs. fixtures — keep them architecturally separate (common SwiftUI bug)

- **Dev fixtures** — `AllnighterCore` JSON, used only in `#if DEBUG` / Previews. They
  must **never** render in a production build.
- **Production cache** — the last `SnapshotEnvelope` + applied events, persisted as a
  plain `Codable` blob in Application Support (*not* a model store), so the app shows
  **real** last-known state offline, labeled "last seen <time>" (`01` honesty).
  Decrypted sealed content may be cached likewise; invalidated on next snapshot.

The view-model init path selects exactly one source — fixture (debug only) or
cache→live — so fixtures can't leak into shipping. Its own slice.

## Onboarding & pairing — the first screens (thin presenter over `01a`)

**Pairing is the WOW and the trust foundation, so it ships first** — before
Home/Active/Review. It invents no behavior: the cloud-mode ceremony (sign in → tap
your Mac → approve once) and the Direct-Mode carriers are fully specified and proven
headless in **`01a_Pairing_Ceremony.md`**. This screen makes that ritual beautiful.
Hold it to `01a`'s simplicity bar — if a user ever sees an IP/port/UUID/token, it's a
bug.

**Default (cloud) onboarding — ≤3 steps:**
1. **Sign in with Apple** (primary; "Hide My Email" ok) or **Google** (`00` §5). No
   email/password to create.
2. **Your Macs** — the app lists Macs on this account (`RemoteClient.macs()`). If
   empty: *"Open Allnighter on your Mac and sign in with the same account"* (the #1
   guidance; "same Apple ID" replaces the old "same tailnet").
3. **Tap a Mac → approve on the Mac** ("Trust Mike's iPhone?", one tap; or via
   `allnighter pair approve` / notification if headless) → **land on live runs.**

**Connection states are distinct and honest** (`01` `RemoteDoctor`), never a generic
"offline": signed-out · no-Macs-on-account · **Mac asleep** · agent-not-running ·
device-not-approved. Each gets one concrete fix.

**Direct Mode (premium, optional)** lives behind a Settings toggle ("Private Direct
Mode — connect without the Allnighter relay, over your own Tailscale"). Enabling it
runs the `01a` QR/deep-link carrier (Camera → "Open in Allnighter" → approve on Mac).
Not part of the default first-run.

## Surfaces

- **Home:** Mac state (online / asleep / unreachable, last-seen), active run count,
  top pending decisions, a **prominent always-visible kill switch**, quick "new work
  request."
- **Active runs:** worker, prompt/task, plain-language status, elapsed time; tap →
  detail (plan / latest output + stop). Sensitive content is fetched **E2E**
  (sealed key → decrypt locally, `01`), never read from the cloud in plaintext.
- **Design board** (`Design0`): the gallery of generated option images at identical
  scale — *the* hero view for the design side. Images arrive **E2E** (per-device
  sealed key + R2 ciphertext in cloud mode; P2P in Direct Mode), decrypt locally.
  **Thumbnail-first** uses **Mac-generated sealed thumbnails** (`01`) so the grid never
  downloads full-res just to render on cellular; full-res on tap. If a blob has aged
  past its R2 TTL, show an honest **"refreshing from your Mac"** state (the Mac
  re-seals/re-uploads, `01`), never a broken image. The user **picks** (taste decides),
  then "Build this" → a typed command (`RB4` dispatch). Makes the media-plane a v1
  surface, not future.
- **Review:** read a finished run's plan / final spec (E2E); landing actions
  (land / ask-for-changes / open-on-Mac) as `01` commands.
- **New work request:** preset + prompt → `startRun` on the Mac. The headline
  "send out more work while walking" flow — right after Home + Active.
- **Settings → Trusted devices:** the `TrustedRemoteStore` made visible — name,
  last-seen, `validUntil` (with an explicit **re-approve** prompt as it nears expiry,
  not a silent failure — `01`), `capabilities`, one-tap **revoke** (real teardown,
  `01`; honest copy: "This device can no longer control this Mac — already-downloaded
  content can't be recalled"). Plus the **Direct Mode** toggle and the consented
  **"Keep my Mac available for remote work"** setting (`00` §3.3).
- **Remote-control disclosure (App Store + trust):** first-run + Settings copy states
  plainly *"This phone can start and stop AI work on your Mac and review results — it
  can never run arbitrary commands"* (`00` §3.1). Honesty line on privacy: *"We can't
  read your work; we route minimized, auto-deleting metadata."*
- Vocabulary: model / skill / worker / team run / lane / landing / board
  (`../Work_Order_Team_Model.md`, `Design0`).

## Deferred seam — Attention Queue (design now, build later)

Don't let Home become a raw log viewer. The Mac will emit first-class *attention
items* (`needs_read`, `needs_pick`, `needs_approval`, `failed_needs_decision`,
`ready_to_build`, `ready_to_land`) that become Home, Morning Pull, notifications,
Shortcuts. **Not v1** — but keep Home reading a small typed summary, not scraping raw
runs, so Pending and attention items drop in without a rewrite (same posture as
`PushNotifier`).

## Fixture → screen map

`run_inflight.json` → Active; `run_complete.json` → Review (plan); design
fixtures (board.json + option PNGs) → Design board. Previews bind these.

## Ordered Slices

- [ ] iOS02-S01 — Delete the SwiftData template; stand up `Apps/AllnighteriOS/`
  (XcodeGen) on `AllnighterCore`, iOS 17.2; register the **universal link** (AASA) for
  the Direct-Mode pairing carrier (`01a` — preferred over a custom URL scheme, which is
  interceptable); `scripts/check.sh` runs its scheme.
- [ ] iOS02-S02 — **Onboarding + pairing FIRST** (thin presenter over `01a`): Sign in
  with Apple/Google → "Your Macs" → tap → approve. Honest connection states. Held to
  `01a`'s simplicity bar.
- [ ] iOS02-S03 — Bind to `01`'s **live `RemoteClient`** (swap fixture → live; no
  transport code here) + the production **cache** + **E2E sealed-content** decrypt.
- [ ] iOS02-S04 — Home (state, active count, pending decisions) **with a working kill
  switch wired the moment the client connects** (see below).
- [ ] iOS02-S05 — Active runs list + detail (status, latest output, stop).
- [ ] iOS02-S06 — **Design board** (thumbnail-first E2E images, pick, "Build this").
- [ ] iOS02-S07 — New work request (preset + prompt → `startRun`).
- [ ] iOS02-S08 — Review a finished run (plan / final spec) + landing.
- [ ] iOS02-S09 — Settings → Trusted devices + revoke + **Direct Mode** toggle.
- [ ] iOS02-S10 — Kill-switch polish (confirm, terminated-count feedback, haptics).
  *Functionality lands in S04; this is the hardening pass.*

> **Kill switch is safety-critical, so capability exists from S04, not S10.** It's a
> single `stopAll` command (returns a confirmed count, `01`) with no UI complexity —
> wiring it at first connect means S05–S08 always have a stop. The late slice is polish.

## Works Test

```text
On cellular (off the Mac's wifi), the phone signs in with Apple, sees its Mac, pairs
(tap + approve on the Mac), shows the Mac online, lists live runs, opens a design run
and the BOARD renders option images (decrypted E2E, thumbnail-first), the user picks
one and "Build this" dispatches to the Mac, sends a new work request that starts a
team run, and the kill switch stops all work with a terminated count. Walking through a
dead zone (drop + restore) loses no events (resume via 01). With the Mac asleep the app
shows "asleep, last seen <time>" and renders last-known state from cache. No plaintext
sensitive content is ever read from the cloud. DEBUG fixtures never appear in a release
build. (Optional: the same flows work in Direct Mode.)
```

## Exit Gates

- [ ] Works Test passes against a live Mac **over cellular** (proves from-anywhere) in
  cloud mode; Direct Mode optional.
- [ ] No transport/auth/reducer logic in the app target — all from Core (`01`).
- [ ] No durable run truth on device; cache is a plain blob; fixtures DEBUG-only
  (verified absent from a release build).
- [ ] Sensitive content (outputs, plans, board images) is decrypted **on-device** from
  sealed payloads — never read from the cloud in plaintext.
- [ ] Distinct connection states (asleep / agent-off / signed-out / not-approved),
  never generic "offline."
- [ ] `swift test` + `xcodebuild test` (iOS scheme) green via `scripts/check.sh`;
  Code Audit CLEAN.

## Closeout

The decision loop has a home on the phone: sign in, pair, check in, review boards,
dispatch, stop — from anywhere, with almost no setup. Next deferred layers: push
(`00` §7) so the phone can ring, the Attention Queue so Home becomes a decision list,
and Direct Mode polish for the privacy/local-AI cohort.
