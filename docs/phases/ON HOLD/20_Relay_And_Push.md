# 20 — Relay and Push

Status: Draft
Milestone: F (Always-on and ship)
Depends on: 08, 09
Owner: Relay + iOS + Mac
Created: 2026-06-13

## Goal

Make Allnighter useful when the phone is away from the LAN: a **thin relay** that
delivers push notifications, carries commands when a direct connection is
unavailable, and (opt-in) tunnels previews — **without ever storing code** and
without becoming the source of repo truth.

## Non-Goals

- Any repo/code storage on the relay. Any always-on requirement — local-first
  remains the default; relay is an explicit opt-in.

## Approach (per `00` §3, §10, source §7.5)

- **Relay service:** containerized **Hummingbird** on a small VPS. Responsibilities
  only: device identity/pairing metadata, message queue, push, remote command
  delivery, optional preview tunnel, status heartbeats. **No code storage.**
- **Push:** APNs for lane-completion / decision-needed notifications; **Live
  Activities** (ActivityKit) for long-running lanes; batch during quiet hours
  (IOS-10, IOS-11).
- **Remote command delivery:** when iOS can't reach the Mac directly, commands
  (land, stop, dispatch) route via the relay queue to the Mac; the Mac executes
  and emits events back.
- **Preview tunnel v0:** a **reverse tunnel from the Mac** exposes a lane preview
  via `preview.allnighter.io/p/<device>/<lane>` — never a source upload (`00` §10).
- **Privacy controls:** all relay use is toggleable; artifacts scanned for obvious
  secrets before any sync/tunnel; transcripts already redacted (`00` §10).

## Ordered Slices

- [ ] P20-S01 — Relay service skeleton (device identity, message queue, heartbeats).
- [ ] P20-S02 — APNs push (lane complete / decision needed).
- [ ] P20-S03 — Live Activities for long-running lanes + quiet-hours batching.
- [ ] P20-S04 — Remote command delivery (relay → Mac → events).
- [ ] P20-S05 — Preview tunnel v0 (reverse tunnel from Mac, no source upload).
- [ ] P20-S06 — Relay privacy controls + secret-scan gate before any sync/tunnel.

## Works Test

```text
With the phone off the LAN, a lane completes and the phone receives a push; the
user taps "land" and the command reaches the Mac via the relay and executes,
emitting events back. A preview opens through the tunnel with no source code
leaving the Mac.
```

## Exit Gates

- [ ] Works Test passes off-LAN.
- [ ] Relay stores no code; preview tunnel uploads no source; secret-scan runs.
- [ ] IOS-10, IOS-11, MAC-18 satisfied; `00` §10 relay rules honored.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 21 (Morning Pull).
