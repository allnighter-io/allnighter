# 01 — Connection Spine (the reusable core)

Status: Draft — **buildable in parallel with the Mac MVP** once its dependencies
(below) land. This is foundation, not deferred GUI.
Milestone: iOS (Remote Floor Manager)
Depends on: `00_iOS_Transport_Decision.md`, `../../mvp/RB6_Council_As_Tool.md`
(RB6-S08), `../../mvp/00_MVP_Architecture.md` §4/§6/§10
Owner: Mac + Shared Core
Created: 2026-06-15

## Reality check (read before scoping — corrected after mentor review)

Earlier drafts said this phase "just binds the server RB6 already built." **That
server does not exist yet.** Verified in-tree (2026-06-15): `AllnighterCLI` has
`ask / presets / recall / doctor / mcp / install-cli / mcp-install` — **no
`serve`, no HTTP listener, no WebSocket.** RB6-S08 (the loopback HTTP/WS server)
was specced but never built; only the **stdio** MCP server exists. Two honest
consequences:

1. **The real work includes building the server**, not just binding it. See the
   dependency chain below; `iOS01-S00.5` lands the loopback server first.
2. **Events are not durably stored.** `RunEvent` is an in-process
   `AsyncStream` (`00_MVP_Architecture` §6) and `RunStore` persists only
   `run.json` + derived Markdown. A phone that was offline during a whole council,
   or across a Mac restart, **cannot** be replayed from memory. Resume requires a
   durable **event journal** (§ Event durability). This is the make-or-break of the
   spine and is core foundation work.

**Pre-req — freeze the event vocabulary.** `RunEvent.swift` still ships legacy
`synthesis.*` constants alongside the generic `stage.*` family. Per
`00_MVP_Architecture` §6 the wire vocabulary is `run.* / member.* / stage.*`. The
`synthesis.*` constants must be **retired/mapped to `stage.*` before the iOS wire
contract locks** — the phone decodes this vocabulary and we will not version it
twice. (Mac/Core change, but it gates `iOS01-S00`.)

## Goal

Make the Mac's run state reachable from the phone over Tailscale with a
**resumable, durably-backed event stream** and **app-level device authorization**
— the spine every iOS screen sits on. Concretely: finish the loopback HTTP/WS
server, add an event journal for replay, expose it on the tailnet (per `00` §2.5),
and add pairing + per-request device assertions. Provable end-to-end with a
`MockiOSClient` and **zero SwiftUI**.

## Non-Goals

- iOS UI / onboarding wizard (that is `02`). This doc is server + wire contract +
  Core client + a mock client, all headless-testable.
- Push notifications (deferred seam — `00` §5; seam defined below).
- Any change to the `RunEvent` *envelope* or run model. The contract is fixed in
  `00_MVP_Architecture` §4/§6 and stays byte-identical (the vocabulary *freeze*
  above is removing dead constants, not reshaping the envelope).

## Dependency chain (what lands first)

```text
freeze event vocabulary (synthesis.* -> stage.*)        [Core/Mac pre-req]
  -> iOS01-S00   Core models + fixtures (no I/O)
  -> iOS01-S00.5 RB6-S08: loopback HTTP/WS server (127.0.0.1, bearer) + event journal
  -> iOS01-S01   expose on the tailnet (tailscale serve | interface bind)
  -> pairing + device assertions + commands + resume
  -> MockiOSClient Works Test over real Tailscale
```

## The durable contract (extracted from `00`, envelope unchanged)

The phone is a resilient client; the **Mac is the source of truth**. State syncs
via the append-only event stream — clients never mutate truth directly.

- **Event envelope** (`00` §6): `{ id, seq, ts, kind, payload }`. Kinds: `run.*`,
  `member.*` (keyed on `seatId`), `stage.*` (`started`/`output`/`completed`/
  `failed`/`reused`, carrying `stageId` + `purpose`). Clients **dedupe by `id`**
  and apply idempotently (upsert) — a reconnecting phone never double-counts.
- **`seq` is monotonic and persisted** (§ Event durability) — it must survive a
  Mac restart and a brand-new run started from the Mac GUI while the phone was
  away. A reset seq is a correctness bug.
- **Resumable stream**: `GET /events/stream?since=<seq>` (WebSocket) replays
  events with `seq > since`, then streams live.
- **Resume horizon (the "too stale" case — was undefined):** if `since` is older
  than the oldest retained event (journal truncated, or unknown), the server does
  **not** silently send a partial gap. It returns/over-the-WS signals
  **`resyncRequired`** (HTTP `410` on the REST probe); the client falls back to a
  full `/snapshot` cold-hydration, then resumes streaming from the snapshot's
  `lastSeq`. This is an explicit Works-Test rung.
- **Snapshot schema** (pin in Core as a `Codable` type, shared by mock + live):
  `SnapshotEnvelope { runs: [CouncilRun], lastSeq, serverTime, protocolVersion }`;
  `GET /runs/:id/snapshot` returns one `CouncilRun`. One fixture drives both the
  mock client and the future UI.
- **Commands** (phone → Mac, Mac executes): start a council run / work request,
  stop a run, **global kill switch** (`/control/stop-all`), landing actions — all
  device-bound. Commands return a transport ack; the real outcome arrives as
  `run.*`/`stage.*` events. **Exception:** `/control/stop-all` returns a confirmed
  `{ terminated: <count> }` — it is the safety feature; an anxious user on a walk
  needs certainty, not just "ack."

## Event durability (the journal — new, required for resume)

Replay needs a durable, seq-ordered source. Add an append-only journal the server
reads for history; live events still flow from the in-process stream.

- **Shape:** `events.jsonl` (one `RunEvent` per line), append-only, seq-ordered.
  Per-run under `Runs/run_<id>/` plus a small global index, **or** a single global
  journal — pick one and document it; the server reads it for any `since` replay.
- **Monotonic seq across runs + processes.** Lift seq from per-coordinator memory
  to a durable counter (file + `flock(2)`, matching RB6's cross-process pattern)
  so the Mac app and a headless `allnighter serve` agree and never reissue a seq.
- **Truncation is allowed but bounded and honest:** when old events are evicted,
  `?since=<evicted>` yields `resyncRequired` (above), never a silent gap.
- **Reconstruction fallback:** if a full journal is too much for v1, the snapshot
  path must still be correct — a reconnecting client with a stale/unknown `since`
  always converges via `/snapshot`. The journal is the optimization; the snapshot
  is the floor.

## Server, binding, and the auth matrix

One HTTP+WS server (SwiftNIO per the TechStack note; `00` §2 "boring deps" — if a
dependency is added, record it in the `00` log) with **pluggable auth** by client
class. Binding follows `00` §2.5 (`tailscale serve` preferred; tailnet-IP bind as
fallback) — the server itself stays on `127.0.0.1`.

| Client | Reaches via | Auth | Notes |
| --- | --- | --- | --- |
| Local agent (RB6 CLI/MCP) | `127.0.0.1` | RB6 **bearer token** + mandatory `ALLNIGHTER_COUNCIL_DEPTH` header | Unchanged from RB6; recursion guard intact |
| iOS over tailnet | `tailscale serve` / tailnet IP | **Device assertion** (Ed25519, below) | Bearer not required on this path |
| `/health` | both | none | Liveness + protocol version + tailnet hint |
| pairing routes | both | short-lived **pairing token** | Issued by the Mac when pairing is armed |

- **WebSocket auth:** the device assertion travels as an **HTTP header on the WS
  upgrade request** (`URLSessionWebSocketTask` supports this); verify it survives
  whatever `tailscale serve` proxies (a stated validation step, not a redesign).
- Loopback and tailnet listeners must not both claim the tailnet surface; only one
  process serves it (coordinate via the same `flock` pattern as `RunStore`).

## Tailscale operations (foundation primitives — headless, testable)

These are *using* Tailscale, never rebuilding it. All are headless and unit-test
with injected command output; the GUI in `02` only presents them.

- **`TailscaleStatus` (Mac):** parse `tailscale status --json` for `BackendState`,
  `Self.DNSName`, `TailscaleIPs`, MagicDNS on/off, tailnet name, peer list. Fall
  back to `getifaddrs` filtering `utun*` addresses in `100.64.0.0/10`. Exposes:
  installed / running / logged-in / tailnet-IP / MagicDNS-ok / this-machine-name /
  visible-peers. Drives both `/health` and the Mac preflight gate.
- **Mac preflight gate (before a QR is ever shown):** installed → logged-in →
  tailnet-IP assigned → MagicDNS resolves → server can bind → remote enabled. The
  QR is only armed when all are green, so a pairing token is never wasted on a
  dead connection. Each failed check carries one concrete next action (open
  Tailscale via `open -a Tailscale`, download link, etc.).
- **iOS connectivity is reachability-only** (`00` §2): there is no iOS Tailscale
  CLI / URL scheme. The honest signal is **probing `/health`** (MagicDNS first,
  then the tailnet IP from the QR); plus a `getifaddrs` `utun`/CGNAT hint. Use the
  **App Store smart link** (`https://apps.apple.com/app/tailscale/id1475387142`)
  to install/open — do **not** call `canOpenURL("tailscale://")` (it doesn't
  exist).
- **Diagnostic ladder** (the single biggest real-world friction killer — "it won't
  connect and I don't know why"). An ordered probe with an exact next step at each
  rung, returned by the Core client so `02` and `doctor` both consume it:
  1. Tailscale present on this phone? → App Store smart link.
  2. Tailscale running / logged in? → "open Tailscale, turn it on."
  3. **Same tailnet as the Mac?** (the #1 silent failure) → "sign in with the same
     Google/GitHub/Apple you used on your Mac." (Pairing payload carries the Mac's
     tailnet name; the client compares.)
  4. Mac reachable (`/health` 200, MagicDNS then IP)? → distinguish **Mac asleep**
     / Tailscale-down-on-Mac / **server not running** as distinct states, never a
     generic "offline."
  5. Paired + approved? → run/approve pairing.

## Caffeination (keep the Mac reachable)

A sleeping Mac silently kills remote control. While the server has an active run
(or a remote session is connected), hold a macOS power assertion
(`IOPMAssertionCreateWithName`, `PreventUserIdleSystemSleep`) and release it when
idle. Independently, the phone treats **"Mac asleep / unreachable"** as a
first-class state showing *last seen / last seq / last active run* — never faked
liveness (`00_MVP_Architecture` §9 honesty; README §4.5).

## Pairing handshake (concrete)

```text
Mac (preflight all-green) arms pairing and shows a QR/code encoding:
  { magicDNSName, tailnetIP, port, serverPubkey, tailnetName,
    protocolVersion, pairingToken, expiresAt }          // see "richer payload" below
  phone -> POST /pair/begin   { pairingToken }           -> { challenge }
  phone generates Ed25519 keypair via CryptoKit (Curve25519.Signing);
        private key in iOS Keychain
  phone verifies it is on the SAME tailnet (compare tailnetName) before continuing
  phone -> POST /pair/complete{ pairingToken, devicePubkey, deviceName,
                                signature(challenge) }
  Mac: verify signature + token (unexpired); HUMAN APPROVES (see headless surface);
       on approve, store TrustedDevice; return { deviceId }
  thereafter every request carries:
       X-Allnighter-Device: <deviceId>
       X-Allnighter-Assert: signature(method | path | requestId | timestamp |
                                       protocolMajor | sha256(body))
```

**Richer QR payload (mentor-converged) — why each field:**
- `magicDNSName` — friendly primary address.
- `tailnetIP` — fallback when **MagicDNS is disabled** on the tailnet (else the
  name won't resolve and pairing dies confusingly). Client tries name, then IP.
- `serverPubkey` — **pin the Mac's identity at first contact** so the phone knows
  it's talking to the right Mac on a shared tailnet (must be in the QR, not only
  returned from `/pair/begin`, which is too late to pin).
- `tailnetName` — lets the phone detect the same-tailnet mismatch (ladder rung 3).
- `protocolVersion`, `port`, `expiresAt` — version match, address, and a visible
  countdown so users don't scan a stale code.

**Headless approval surface (so `01` is provable without the `02` GUI):**
pairing's human-in-the-loop step must work from the terminal, because the GUI is
deferred:
- `allnighter pair begin` → arms pairing, prints the code/URL + an ASCII QR.
- `allnighter pair list` → pending + trusted devices.
- `allnighter pair approve <deviceId>` / `allnighter pair revoke <deviceId>`.
- For a headless/closet Mac, also post a `UserNotifications` alert "Pairing
  request from <name> — approve with `allnighter pair approve <id>`."
The `02` GUI later becomes a thin presenter over this same flow, not the only way
to approve. **Revocation** (lost phone) lives here too and is cross-referenced by
the Mac settings UI in `02`.

Keys: phone private key in iOS Keychain; trusted devices + `serverPubkey` identity
in Mac Keychain (secret material in Keychain; the device list may live in
`Config/` with strict perms). Secrets never leave the Mac.

## Device assertion + replay protection (hardened)

The assertion is **authorization** (Tailscale already encrypts the channel, `00`
§4). Hardened per mentor feedback:

- **Sign the whole request:** `method | path | requestId | timestamp |
  protocolMajor | sha256(body)` — not just method+path, so a captured signature
  can't be replayed against a different body.
- **`requestId` dedup store** (already specced for command idempotency) **also
  rejects reused `requestId`s** — this is the real replay defense. It must be
  **persisted and bounded** so a retried `stop-all` after a Mac restart is still
  safe and the store can't grow unbounded.
- **Clock-skew window: ±60s, explicit.** iOS clocks drift (Airplane Mode, DST).
  Outside the window → a **distinct `clockSkew` error code** (not generic
  `unauthorized`), which the app surfaces as "your device clock may be off," not a
  mystery network failure.
- Mac rejects: unknown/`revoked` deviceId, bad signature, reused `requestId`,
  out-of-window timestamp, protocol-major mismatch.

## New `AllnighterCore` models (contract-first; round-trip tested + fixtures)

Pure `Codable`, no I/O — same discipline as the run model (`00` §4). The only new
shapes the spine adds; the `RunEvent`/`CouncilRun` envelope is untouched.

```text
PairingPayload  : { magicDNSName, tailnetIP, port, serverPubkey, tailnetName,
                    protocolVersion, pairingToken, expiresAt }   (QR contents)
PairingToken    : { token, expiresAt }                          (short-lived, Mac-issued)
TrustedDevice   : { deviceId, deviceName, pubkey, approvedAt, lastSeenAt, revoked }
DeviceAssertion : { deviceId, requestId, timestamp, protocolMajor, signature }
ProtocolVersion : { major, minor }                             (negotiated at /health)
SnapshotEnvelope: { runs:[CouncilRun], lastSeq, serverTime, protocolVersion }
CommandRequest  : { requestId, kind, payload }                 (start|stop|stopAll|land)
CommandAck      : { requestId, accepted, reason? }             (transport ack; outcome via events)
StopAllResult   : { terminated }                               (authoritative kill-switch reply)
ResyncRequired  : { reason, snapshotHint }                     (since-too-stale signal)
ConnectionDiagnosis : ordered [ { rung, ok, nextAction? } ]    (the diagnostic ladder)
```

`CommandRequest.kind` is a **closed enum** (exhaustive switch, like `StagePurpose`
in `00` §4.1) so adding a command is a deliberate, compiler-guided change.

## `RemoteClient` in Core (shared by mock + live + the future UI)

Put the transport logic in Core so iOS never reinvents state interpretation and is
testable without an app target:

```text
protocol RemoteClient {                       // MockiOSClient + live impl both conform
  func connect(_ payload: PairingPayload) async throws
  func snapshot(since: Seq?) async throws -> SnapshotEnvelope
  func stream(since: Seq) -> AsyncStream<RunEvent>      // auto-resync on resyncRequired
  func send(_ command: CommandRequest) async throws -> CommandAck
  func diagnose() async -> ConnectionDiagnosis
}
```

Plus a **shared sync reducer** `apply(SnapshotEnvelope, [RunEvent]) -> ViewState`
(dedupe by `id`, upsert) used by **both** Mac and iOS — today `AppModel.apply`
only handles status changes, which is too thin for mobile. The reducer is pure and
exhaustively unit-tested in Core. `02`'s "live client" slice then just swaps the
fixture source for the live `RemoteClient` — it does **not** reimplement transport.

## `PushNotifier` seam (defined now, unimplemented in v1)

Push is deferred (`00` §5) but its seam is defined so v1 builds around it:

```text
protocol PushNotifier {            // Mac-side; v1 impl is a no-op
  func register(device: TrustedDevice, pushToken: String) async
  func notify(device: TrustedDevice, doorbell: Doorbell) async
}
Doorbell : { title, body, runId?, kind }   // content-light; no secrets — data fetched over Tailscale
```

Default impl likely **OneSignal**, but the protocol is the commitment; Ably/FCM
drop in (`00` §5). v1 ships the no-op; the phone gets live updates over the open
stream.

## Ordered Slices

Built in three groups so the spine is proven before any iOS target exists.

**Group A — Core + mock (no app target, all `swift test`):**
- [ ] (pre-req) Freeze event vocabulary: retire `synthesis.*`, map to `stage.*`.
- [ ] iOS01-S00 — Core models above + fixtures + round-trip tests.
- [ ] iOS01-S00b — `RemoteClient` protocol + shared `apply()` reducer +
  `MockiOSClient`; resume/dedupe/resync tested entirely in `swift test`.

**Group B — Mac server:**
- [ ] iOS01-S00.5 — **Land RB6-S08:** loopback HTTP/WS server (`allnighter serve`),
  `127.0.0.1`, bearer + depth header, `/health` + `/snapshot` + `RunEvent` WS.
- [ ] iOS01-S00.6 — Event journal + monotonic persisted `seq`; `resyncRequired`
  on stale `since`.
- [ ] iOS01-S01 — Expose on the tailnet (`tailscale serve` default; tailnet-IP
  bind fallback). Reachable from another tailnet device; **not** off-tailnet.
- [ ] iOS01-S01b — `TailscaleStatus` + Mac preflight gate (QR only when green).

**Group C — pairing, auth, commands, resume:**
- [ ] iOS01-S02 — Pairing handshake + richer QR payload + headless
  `allnighter pair begin/list/approve/revoke` + trusted-device store (Keychain).
- [ ] iOS01-S03 — Device assertion on every tailnet route (signed body, requestId
  dedup, ±60s skew + `clockSkew` code); reject unpaired/unsigned/replayed.
- [ ] iOS01-S04 — `/events/stream?since=` replay→live; auto-resync on stale since.
- [ ] iOS01-S05 — `/snapshot?since=` + `/runs/:id/snapshot` (`SnapshotEnvelope`).
- [ ] iOS01-S06 — Command routes (start/work-request, stop, `stop-all`→count, land).
- [ ] iOS01-S07 — Caffeination (power assertion while serving an active run).
- [ ] iOS01-S08 — `MockiOSClient` Works Test over **real Tailscale** between two
  machines: no gaps, no dupes; auth/replay rejection; off-tailnet unreachable.

## Works Test

```text
A MockiOSClient on a second tailnet device (a second Mac, Linux box, or second
account — CI uses unit/property tests for the logic) pairs with the Mac via the
CLI approval flow, fetches a snapshot, streams live run/member/stage events, drops
the connection, reconnects with its last seq, and receives exactly the missed
events with no duplicates. Negative cases all hold:
  - a device NOT on the tailnet cannot reach the server;
  - a device on a DIFFERENT tailnet is caught at pairing (tailnet mismatch);
  - an expired pairing token is rejected;
  - a reused requestId / out-of-window timestamp is rejected (distinct codes);
  - since older than the journal returns resyncRequired and the client converges
    via /snapshot with no gap;
  - /control/stop-all returns a confirmed terminated count and stops all work.
```

## Exit Gates

- [ ] Works Test passes, including every negative case above.
- [ ] Resume correct across a Mac restart (persisted seq + journal), not just a
  brief drop.
- [ ] Server reachable only over the tailnet (off-tailnet failure verified); auth
  rejects unpaired/replayed; secrets never leave the Mac.
- [ ] `RunEvent` envelope unchanged from `00` §6; `synthesis.*` retired.
- [ ] `RemoteClient` + reducer covered by `swift test`; the proof needs no SwiftUI.
- [ ] `swift test` + app build green via `scripts/check.sh`; Code Audit CLEAN.

## Closeout

Activate `02` (the iOS app consumes this spine). The remote control loop now has a
secure, resumable, durably-backed pipe with a tested Core client — the GUI is
"just" wiring SwiftUI to an already-proven surface.
