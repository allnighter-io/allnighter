# 08 — Transport and Pairing

Status: Draft
Milestone: C (Mobile floor manager)
Depends on: 01, 05
Owner: Mac + Shared Core
Created: 2026-06-13

## Goal

Expose the Mac's API to the iPhone over the local network with secure pairing and
a **resumable event stream**. The phone is a resilient client; the Mac stays the
source of truth. This phase delivers the embedded server, discovery, auth, and the
event replay/dedup machinery from `00` §5.

## Non-Goals

- Remote/relay/push (Phase 20) — LAN only here.
- iOS UI (Phase 09) — this phase is the server + a mock client.

## Approach (per `00` §3, §5, §6, §10)

- **Embedded server:** Hummingbird 2 inside the Mac app serving the `00` §6 routes
  + `GET /events/stream?since=<seq>` WebSocket.
- **Discovery:** Bonjour `_allnighter._tcp` via Network.framework; the phone
  browses, the Mac advertises with a TXT record (device name, version).
- **Pairing/auth** (`00` §10): Mac shows a code/QR; iOS posts its Ed25519 pubkey +
  code to `/pair/complete`; the Mac stores the trusted device. Connections use TLS
  (pinned self-signed cert) + a signed challenge. Secrets stay in Mac Keychain.
- **Resumable stream:** server replays events `> since`, then streams live;
  `GET /projects/:id/snapshot?since=<seq>` for cold hydration. Clients dedupe by
  event `id`.
- Test with the `MockiOSClient` from Core: pair, snapshot, stream, reconnect with
  `since`, assert no gaps/dupes.

## Ordered Slices

- [ ] P08-S01 — Hummingbird server in the Mac app serving `/health` + `/projects`.
- [ ] P08-S02 — Bonjour advertise/browse (`_allnighter._tcp`).
- [ ] P08-S03 — Pairing handshake (`/pair/begin`, `/pair/complete`) + trusted-device store.
- [ ] P08-S04 — TLS + signed-challenge auth on all routes.
- [ ] P08-S05 — `/events/stream?since=` WebSocket with replay + live; snapshot endpoint.
- [ ] P08-S06 — Reconnect/resume test with `MockiOSClient` (no gaps, no dupes).

## Works Test

```text
A mock client discovers the Mac via Bonjour, pairs (code exchange + pubkey),
fetches a snapshot, streams live lane events, disconnects, reconnects with the
last seq, and receives exactly the missed events with no duplicates. Unpaired /
unsigned requests are rejected.
```

## Exit Gates

- [ ] Works Test passes; resume correctness proven.
- [ ] Auth rejects unpaired devices; secrets never leave the Mac.
- [ ] MAC-9, IOS-1 (server side) satisfied; `00` §5 stream contract honored.
- [ ] Code Audit CLEAN.

## Closeout

Activate Phase 09 (iOS app consumes this).
