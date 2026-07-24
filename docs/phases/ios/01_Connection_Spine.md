# 01 — Connection Spine (cloud-first; the reusable core)

Status: Draft — headless foundation in progress; iOS product UI remains deferred.
Not a Mac blocker.
Milestone: iOS (Remote Project Manager)
Owner: Mac + Shared Core
Created: 2026-06-15
Updated: 2026-06-21 (headless foundation status sync)
Depends on: `00a_iOS_Foundation_Slice_0.md`, `00_iOS_Transport_Decision.md` (architecture & trust), `../../mvp/00_MVP_Architecture.md`
§4/§6/§9, `../../mvp/RB6_Team_As_Tool.md`, `../CLI_Product_Spine.md`,
`../Work_Order_Team_Model.md` (vocabulary),
`../Mac_Standalone_App_And_Background_Coordinator.md`. Historical cleanup record:
`../../archive/phases/Team_First_Vocabulary_Cleanup.md`.

## Architecture principle (carries the whole design)

**The network is just a cable. The Mac is truth + the final authorizer. The cloud is
a blind relay/cache — untrusted in both directions.** The Mac **dials out** to the
control plane and **re-verifies everything** (`00` §3); a Supabase/R2 breach yields
**minimized metadata + ciphertext — never control, never plaintext.** Swapping the
carrier (cloud relay ↔ Tailscale Direct) never changes the trust model, the
`RunEvent` contract, the registry, the command set, revocation, or audit.

```text
iPhone (Supabase-authed) ──┐                              ┌──► Anthropic/OpenAI/xAI/Gemini/…
                          Supabase  (control plane)        │   (the AI actually runs here)
Mac agent ──dials OUT──►  command inbox + events + auth ───┘
   holds subscription CLI logins · VERIFIES every command · executes locally
   · SIGNS events · SEALS sensitive content both directions
                          Cloudflare R2 (media plane)
                          encrypted transient blobs (presigned, TTL)
```

## Reality check (verified in-tree, 2026-06-19)

- **CLI/Core foundation exists.** `alln` is the product CLI, `TeamRunJSON` is the
  shared machine contract, async team status/result/cancel exists, Pending/Project
  Core pieces exist, and `alln serve` exists as a background scheduler health/wake
  skeleton.
- **The remote foundation is headless.** `RemoteMacAgent`, the poll coordinator,
  bootstrap wiring, command router, event sync, snapshot publisher, Supabase relay
  adapter, and Direct Mode carrier surfaces exist in Core/Engine tests. Remaining
  product work is runtime wiring (app/launchd), live credentials, and the full
  carrier Works Test.
- **Run durability is wired for async team runs.** `RunStore` writes non-terminal
  `run.json` snapshots + `owner.pid` and reads dead owners as `interrupted`.
  `RemoteRunEventJournal` persists append-only per-run events plus the global
  monotonic `seq`, and `AsyncTeamService` now records `CatalogRunCoordinator`
  events there. Remaining proof is carrier-level resume across Mac restart and any
  future non-async-team event sources.
- **Pre-req complete — event/run vocabulary is frozen.** Remote public output is
  `run.*`, `worker.*`, and `stage.*`; `synthesis.*` is rejected before signing.
  iOS consumes the same `TeamRunJSON` shape as `alln team --json`; it never gets
  a dual vocabulary.
- **iOS app target is quarantined.** `Apps/AllnighteriOS/` is still the SwiftData
  starter scaffold. Foundation work happens in Core/Engine and proves with
  `MockiOSClient`; no SwiftUI dependency.

## Goal

A phone, signed in, can securely **see and drive** its Mac's runs **from anywhere
with no networking setup**, over the cloud relay by default. The Mac verifies and
executes locally; all sensitive content (in **both** directions) stays end-to-end
encrypted. Provable end-to-end with `MockiOSClient` and **zero SwiftUI**.

## Non-Goals

- iOS UI (`02`); pairing *experience* (`01a`).
- Push (deferred seam — `00` §7).
- A generic remote-shell / remote-MCP pathway — **forbidden** (`00` §3.1).
- Any change to the `RunEvent` *envelope* (the vocabulary *freeze* removes dead
  constants only). Becoming durable cloud storage — the cloud is a transient cache.

## Security & crypto contract (LOCKED — build this first, in `S00`)

The pivot is only "cheap" if this contract is right. Prove it with round-trip test
vectors in Core **before** any Supabase/R2 wiring.

### Keys — two per device, two per Mac (do not conflate)

Signing ≠ sealing. You cannot encrypt to an Ed25519 signing key.

```text
Per device (phone/iPad):  deviceSigningPubkey  = Curve25519.Signing  (Ed25519) — command auth
                          deviceSealingPubkey  = Curve25519.KeyAgreement (X25519) — receive sealed content
Per Mac agent:            agentSigningPubkey   = Ed25519 — signs outbound events/acks
                          agentSealingPubkey   = X25519 — receives sealed inbound commands (e.g. startRun prompt)
```

Private keys: device keys in iOS Keychain; Mac keys in Mac Keychain. Both pubkeys are
exchanged + pinned at pairing (`01a`). **`deviceId` is a hint**; the verifying key is
resolved by the Mac from its **own** `TrustedRemoteStore` (never from the spoofable
row).

### Sealing — HPKE (RFC 9180) via `CryptoKit.HPKE`

One primitive, both directions. Suite: **DHKEM(X25519) · HKDF-SHA256 · AES-GCM-256.**
A single Core type:

```text
SealedBlob : { ciphertext, encapsulatedKey, sealedForKeyId, suite, contentType }
```

Used for: inbound sealed command payloads (phone→Mac, sealed to `agentSealingPubkey`),
outbound `media_keys`/`event sealedRef` (Mac→device, sealed to `deviceSealingPubkey`).
**One crypto story, every direction, shared test vectors.**

### Signing — both directions, bound to identity

- **Phone → Mac (commands):** sign `deviceId | method | requestId | timestamp |
  protocolMajor | kind | sha256(payload)`. **`deviceId` is in the signed string**
  (defense in depth) but the Mac still resolves the key from its store.
- **Mac → phone (events/acks):** the Mac **signs `event_envelopes`/`command_acks`**
  with `agentSigningPubkey`; the phone verifies against the pinned key. So a Supabase
  row-injection cannot fabricate run state (it can be dropped, not forged). May be
  batched per journal segment for efficiency.

### Replay, skew, versioning

- **Clock skew ±60s.** On reject, the error returns the Mac's **`serverTime`**; the
  phone computes an offset and **signs relative to server time** thereafter
  (`SnapshotEnvelope.serverTime` seeds this on first contact). `RemoteDoctor` adds a
  "your phone's clock is off" rung. → the whole clock-skew failure class becomes a
  non-event for non-developers.
- **Dedupe window = skew window.** Reject anything older than ±60s on timestamp
  alone; the `requestId` dedupe set therefore only needs to cover that window —
  persisted, pruned on startup, hard-capped (e.g. 10k entries) against inbox flooding.
- **Protocol version.** v1 = `protocolVersion: 1`. A major mismatch (either
  direction) returns a distinct **`upgradeRequired`** error → plain-language "update
  the app." (Seeds real negotiation later; not decorative.)
- **Error taxonomy (distinct codes):** `clockSkew`, `revoked`, `expired`,
  `unauthorizedKind`, `replayedRequestId`, `badSignature`, `upgradeRequired`.

## Control plane — Supabase (default carrier)

Auth + Postgres + RLS + Realtime. **RLS is defense-in-depth; the signature is the
authority** — the Mac re-verifies every command regardless of what RLS passed.

```text
accounts          Supabase Auth users (Apple primary, Google fallback)
mac_agents        { id, accountId, displayName, agentSigningPubkey, agentSealingPubkey, lastSeenAt }
trusted_devices   { deviceId, accountId, macAgentId, displayName,
                    deviceSigningPubkey, deviceSealingPubkey,
                    pairedAt, validUntil, revoked, revokedAt, lastSeenAt, capabilities }
command_inbox     { requestId(PK), accountId, macAgentId, fromDeviceId, kind,
                    payload(content-light OR SealedBlob), signature, createdAt, status }
command_acks      { requestId, macAgentId, accepted, reason?, outcome, sig }
event_envelopes   { id, seq, ts, macAgentId, runId, kind, lightPayload,
                    sealedRef?, sig, createdAt(TTL) }
media_refs        { ref, macAgentId, r2Key, contentType, expiresAt }            one row per blob
media_keys        { macAgentId, ref, deviceId, sealedKey,
                    PRIMARY KEY(macAgentId, ref, deviceId) }                  one row per device (fan-out)
```

- **Mac agent auth (the third leg).** The Mac signs into the **same account** and
  registers itself as a `mac_agent` (storing both agent pubkeys); the agent
  authenticates to Supabase with its account session + a per-agent credential held in
  **Mac Keychain**. RLS scopes every table by `accountId`/`macAgentId`.
- **Three-tier RLS** (else pairing can't bootstrap):
  1. **Authed but unapproved** → may **read `mac_agents` display info** (for the "Your
     Macs" picker) and **write a pair request** only.
  2. **Approved + unrevoked** → full read of its Mac's `event_envelopes`/`acks`;
     write to `command_inbox`.
  3. **Revoked** → none.
- **Content-light control plane.** Supabase carries **metadata only**; sensitive
  content (prompts, outputs, plans, board images) is **sealed by reference**
  (`SealedBlob` inline for small, `media_ref` for blobs). Enforced at write sites.
- **Filtered Realtime.** The Mac subscribes `command_inbox:macAgentId=eq.<id>`; the
  phone subscribes `event_envelopes`/`command_acks` filtered to its Mac. (Postgres
  changes is fine at v1 scale.)

## The Mac agent (outbound — the new core component)

In the Mac app **and** a headless `alln serve` remote mode. For a closet Mac, a
**launchd agent with `KeepAlive`** relaunches it across crash/reboot (a power
assertion is not durability). The agent:
1. **Dials out** to Supabase (authed as its `mac_agent`); heartbeat + exponential-
   backoff reconnect.
2. **On (re)connect: sync `trusted_devices` FIRST** (refresh the local
   `TrustedRemoteStore`), **then** process the inbox — so a device revoked while
   offline can't slip a queued command through.
3. **Subscribes** to its inbox **and polls** for unacked commands (delivery is
   **at-least-once**: poll + push; idempotent by `requestId`). Realtime is best-
   effort — the poll is the guarantee, and it is what makes the **kill switch**
   reliable.
4. **Verifies independently of the cloud** (signature/key/freshness/capability/skew),
   **unseals** any sealed payload, then executes via the async team-run service
   with a remote `RunOrigin`.
5. **Writes back** a signed `command_ack`, then signed content-light
   `event_envelopes`; seals sensitive content and posts `media_refs` + per-device
   `media_keys`.
6. **Reachability posture (`00` §3.3):** honors the user's "Keep my Mac available for
   remote work" setting — holds a power assertion (`IOPMAssertionCreateWithName`,
   `PreventUserIdleSystemSleep`) while connected/running, with a ~10-min idle release
   when nothing is in-flight; when sleep is allowed, commands queue and drain on next
   wake (the poll). "Mac asleep / agent-off / signed-out" stay honest, distinct states.

## Media plane — Cloudflare R2 (E2E, transient, multi-device)

For design-board images (`Design0`) and large sealed artifacts. **R2 Standard** (not
IA — short-lived):
1. Mac creates a **per-blob content key**, encrypts the blob, and also generates a
   **sealed thumbnail** (Mac-side, so the board is *truly* thumbnail-first on
   cellular — the phone must never download full-res just to render a grid).
2. Upload ciphertext to R2 via a **presigned PUT minted by a Supabase Edge Function**
   authed as the `mac_agent` — **R2 credentials never live on the Mac** (blast-radius
   containment). Lifecycle rule deletes after the TTL (v1: **72h**).
3. Post one `media_ref` (the blob) + one `media_keys` row **per approved device**
   (content key sealed to each `deviceSealingPubkey`). One ciphertext, N sealed keys.
4. Phone unseals its `media_keys` row, downloads ciphertext (R2 **free egress**),
   decrypts locally. **Direct Mode bypasses R2** (P2P).
- **Later-paired / new device:** existing blobs are sealed only for older devices. On
  first access a new device **requests a re-seal**; the Mac (truth) re-seals the
  content key to the new `deviceSealingPubkey` and adds a `media_keys` row.
- **Expired blob (offline past TTL):** the Mac journal still has the original; the
  phone requests **re-upload + re-seal**; if unavailable, an honest **"content
  expired — your Mac will refresh it"** state (never a broken image).

## The durable contract (envelope unchanged) + resume

- **Envelope** (`00_MVP_Architecture` §6): `{ id, seq, ts, kind, payload }`, kinds
  `run.*/worker.*/stage.*`; dedupe by `id`, apply idempotently. Wire payloads are
  **content-light** (sealed refs for sensitive fields).
- **`seq` is monotonic + persisted** (journal) — survives a Mac restart and a run
  started from the Mac GUI while the phone was away.
- **Resume:** reconnect with last `seq`; if older than the cloud mirror retains →
  **`resyncRequired`** → fetch a `SnapshotEnvelope`, then resume live. **`seq = 0`
  (fresh install) goes straight to snapshot**, skipping the delta. No silent gaps.
- **Snapshot includes recently-completed runs** (bounded/paginated), not just
  in-flight ones — the **Morning Pull** (overnight results, by then past event TTL)
  is the headline moment and must be in the snapshot. `SnapshotEnvelope { runs:
  [TeamRunLight], lastSeq, serverTime, protocolVersion }`; sensitive fields are
  sealed refs. One fixture drives mock + UI and should derive from the same
  `TeamRunJSON` contract as the CLI.
- **Commands** return a signed `command_ack`; outcomes arrive as `run.*/stage.*`
  events. **`stopAll` returns a confirmed `{ terminated: count }`** and is **never
  capability-gated** — the kill switch is a safety floor available to any trusted,
  unrevoked device.

## Event durability (the journal — Mac-side, required)

Append-only `events.jsonl` (one `RunEvent`/line), seq-ordered, per-run under
`Runs/run_<id>/` + a small global index. The Mac journal is **truth**; the cloud
mirror is transient (TTL'd). Monotonic seq across runs + processes (file + `flock(2)`,
RB6 pattern) so the Mac app and the headless agent agree. Bounded replay/snapshot
pagination. Snapshot is the convergence floor. Async team runs append their
coordinator events into this journal; carrier-level restart/resume proof remains.

## Trust model (transport-agnostic — see `00` §3)

- **`TrustedRemoteStore`** — the registry; two pubkeys per device; `deviceId` a hint,
  signature the truth; `capabilities` grant `startRun`/`stopRun` only; `stopAll` is
  ungated; `validUntil` (v1: **long-lived ~1 year, explicit re-approval on
  expiry, surfaced in Settings** — never silent expiry that looks like a bug).
- **`RemoteCommandRouter`** — closed enum `startRun/stopRun/stopAll` (v1). Future
  commands require an explicit contract change. **No shell case, ever.** Capability check +
  idempotent dedupe + per-device rate limits + size caps.
- **Revocation = real teardown:** reject new → tear down that device's filtered
  subscription (without touching others) → cancel its in-flight scopes → (later) clear
  push token → metadata-only audit → purge cached refs. Honest running-job outcomes.
  *Honesty: revocation stops future access; content a device already unsealed cannot
  be recalled (inherent to E2E).*
- **`RemoteAuditEvent`** `{ ts, deviceId, commandKind, requestId, targetSummary,
  outcome }` — **metadata only**: a structural test fails the build on a
  `body/raw/content/prompt/output` field **and** `targetSummary` is capped at **≤200
  chars** (so the ban can't be evaded by stuffing content into a summary).

## `RemoteClient` + `ConnectionMode` in Core

```text
enum ConnectionMode { cloudRelay (default), tailscaleDirect (premium), loopback }

protocol RemoteClient {                       // MockiOSClient + live impls conform
  func connect(account: Session, mode: ConnectionMode) async throws
  func macs() async throws -> [MacAgentRef]                       // account-based discovery (tier-1 RLS)
  func snapshot(macId, since: Seq?) async throws -> SnapshotEnvelope
  func stream(macId, since: Seq) -> AsyncStream<RunEvent>         // verifies Mac sig; resync on resyncRequired
  func send(_ command: RemoteCommand) async throws -> CommandAck  // device-signed; sealed payload if sensitive
  func fetchSealed(_ ref: MediaRef) async throws -> Data          // R2 (cloud) or P2P (direct); re-seal fallback
  func diagnose() async -> ConnectionDiagnosis
}
```

Plus a shared, pure **`apply(SnapshotEnvelope, [RunEvent]) -> ViewState`** reducer
(dedupe by `id`, upsert), used by both Mac and iOS, exhaustively unit-tested. `02`
swaps the fixture source for the live `RemoteClient`; it reimplements nothing.
**One verification path, two carriers:** `RemoteCommandRouter` is shared by the
outbound Supabase agent and the Direct-Mode loopback server — they must not diverge.

## New `AllnighterCore` models (contract-first; round-trip tested + fixtures)

```text
ConnectionMode  : cloudRelay | tailscaleDirect | loopback
MacAgentRef     : { macAgentId, displayName, agentSigningPubkey, agentSealingPubkey, lastSeenAt }
TrustedDevice   : { deviceId, displayName, deviceSigningPubkey, deviceSealingPubkey,
                    accountId, macAgentId, pairedAt, validUntil, revoked, revokedAt,
                    lastSeenAt, capabilities }
SealedBlob      : { ciphertext, encapsulatedKey, sealedForKeyId, suite, contentType }
DeviceAssertion : { deviceId, requestId, timestamp, protocolMajor, kind, signature }
RemoteCommand   : { requestId, kind, payload(content-light or SealedBlob) }   // kind = closed enum; no shell
CommandAck      : { requestId, accepted, reason?, outcome, sig }
StopAllResult   : { terminated }
RunEvent        : { id, seq, ts, kind, payload(content-light), sealedRef?, sig }
MediaRef        : { ref, macAgentId, r2Key, contentType, expiresAt }
SnapshotEnvelope: { runs:[TeamRunLight], lastSeq, serverTime, protocolVersion }
ResyncRequired  : { reason, snapshotHint }
RemoteAuditEvent: { ts, deviceId, commandKind, requestId, targetSummary(<=200), outcome }
ConnectionDiagnosis : ordered [ { rung, ok, nextAction? } ]
```

`RemoteCommand.kind` is a **closed enum** (exhaustive switch) — no shell case.

## Connectivity & diagnostics (`RemoteDoctor`, read-only)

Account-centric rungs, each with one concrete fix:
1. Signed in? → Sign in with Apple/Google.
2. **Provider/account match?** If the phone is Apple and the Mac registered under
   Google (two distinct Supabase users → the phone sees no Mac), **say so**: "You're
   signed in with Apple here but your Mac used Google — sign in with the same one."
   (This silent same-account-different-provider dead end is a top real-world drop-off.)
3. Any Macs on this account? → "Open Allnighter on your Mac, same account."
4. Target Mac reachable (agent seen recently)? → distinguish **asleep / agent-off /
   signed-out** as distinct honest states.
5. Clock in sync? (uses `serverTime`) → "your phone's clock is off."
6. Device approved? → run/approve pairing (`01a`).

## `PushNotifier` seam (defined now, no-op in v1)

```text
protocol PushNotifier { func register(device, pushToken) async
                        func notify(device, doorbell: Doorbell) async }   // Mac-side; v1 no-op
Doorbell : { title, body, runId?, kind }    // content-light; no secrets
```
Likely **OneSignal**, swappable; v1 ships no-op (live updates ride Supabase Realtime
while the app is open). `00` §7.

## Direct Mode (Tailscale) — premium carrier (fast-follow)

The earlier Tailscale design **is** `tailscaleDirect` (`00` §2.5). The Mac runs the
loopback HTTP/WS server (RB6-S08) exposed via an `ExposureProvider` (`tailscale serve`
→ auto-HTTPS, server stays on `127.0.0.1`; `tailnetIpHttp` fallback). **Same
`RemoteClient`, same trust spine, same `RunEvent` contract.** Notes:
- `RemoteDoctor` (Mac) checks `tailscale cert` succeeds; if not, guides the user to
  enable HTTPS in the Tailscale admin console.
- iOS `Info.plist` ATS: HTTPS enforced for external domains, with explicit exceptions
  for the tailnet/local ranges (`100.64.0.0/10`, RFC-1918) for the `tailnetIpHttp`
  fallback.
- **Switching a cloud-paired device to Direct Mode needs no second human approval** —
  same `trusted_devices` row + same device keys; the `01a` QR ceremony only teaches
  the phone the P2P endpoint + pins `serverPubkey`.

## Ordered Slices

**Group 0 — Foundation Slice 0 (docs + cleanup gates, no app target):**
- [x] iOS00a-S00 — Sync foundation docs to current repo state and route all
  implementation through `00a`.
- [x] iOS00a-S01 — Freeze remote event vocabulary (`synthesis.*` rejected before
  signing; public remote output is `run.*`/`worker.*`/`stage.*`).
- [x] iOS00a-S02 — Specify event journal/snapshot hardening over the current
  incremental `run.json` snapshots.
- [x] iOS00a-S03 — Mark the `alln serve` coordinator boundary: health/wake exists;
  remote typed command/event carriers are headless foundation, not product runtime.
- [x] iOS00a-S04 — Quarantine the SwiftData iOS scaffold until `02`.

**Group A — Core + crypto + mock (no app target, `swift test`):**
- [x] (pre-req from Group 0) Freeze event/run vocabulary (`synthesis.*` rejected;
  public remote output is `run.*`/`worker.*`/`stage.*`)
  against the CLI schema.
- [ ] iOS01-S00 — Core models above **+ the crypto contract** (two-key model, `SealedBlob`/HPKE,
  signing string incl. `deviceId`, dedupe=skew, protocol version) with **round-trip
  test vectors**; fixtures.
- [ ] iOS01-S00b — `RemoteClient` + shared `apply()` reducer + `MockiOSClient`
  (resume/dedupe/resync + signature verify both directions, tested).

**Group B — cloud control plane + agent:**
- [ ] iOS01-S01 — Supabase: schema + **three-tier RLS** + Auth (Apple/Google) + Mac
  agent auth/registration (both agent pubkeys).
- [ ] iOS01-S02 — **Mac agent:** dial out, sync-trusted-devices-then-inbox, **verify
  independently**, unseal, execute, **sign** ack + events, post media; at-least-once
  poll; reachability posture + launchd KeepAlive.
- [ ] iOS01-S03 — Event journal + monotonic persisted `seq`; `resyncRequired` →
  **snapshot incl. recently-completed runs**; `seq=0`→snapshot; bounded responses.

**Group C — media + trust:**
- [ ] iOS01-S04 — E2E media via R2: per-blob key + Mac-side thumbnail, Edge-Function
  presign, `media_refs` + per-device `media_keys` fan-out, re-seal-on-new-device,
  TTL + expired-recovery.
- [ ] iOS01-S05 — `RemoteCommandRouter` (closed enum, capability check w/ ungated
  `stopAll`, idempotent dedupe, rate limits, size caps); `stopAll` → terminated count.
- [ ] iOS01-S06 — Revocation teardown (surgical per-device) + `RemoteAuditEvent`
  (metadata-only, `targetSummary≤200`) + structural test.

**Group D — premium carrier (fast-follow):**
- [ ] iOS01-S07 — Direct Mode: RB6-S08 loopback server + `ExposureProvider`; ATS +
  `tailscale cert` check; identical `RemoteClient`.
- [ ] iOS01-S08 — Works Test over **both** carriers.

## Works Test

```text
A MockiOSClient signed into an account drives a Mac over the CLOUD relay:
  - tier-1 discovery lists the Mac (unapproved); pairing (01a) approves the device;
  - startRun's PROMPT travels as a SealedBlob (sealed to agentSealingPubkey) -> the
    Supabase row carries ONLY ciphertext; the Mac unseals + runs the right preset;
  - signed, content-light run/member/stage events stream; the phone VERIFIES the Mac
    signature and rejects any event with a bad/absent agent signature;
  - a design board's images arrive E2E (per-device media_keys + R2 ciphertext),
    thumbnail-first, and decrypt; a SECOND paired device decrypts only its own key;
  - drop + reconnect by seq -> exactly missed events, no dupes; seq=0 -> snapshot;
    a snapshot after the event-TTL still shows the recently-COMPLETED overnight run;
  - injected command_inbox row (valid account session, bad/missing signature OR
    spoofed fromDeviceId) -> rejected by the Mac (not the cloud); audit metadata-only;
  - reused requestId / out-of-window timestamp -> rejected (distinct codes); a phone
    with a skewed clock recovers via serverTime and succeeds;
  - revoke device A -> A's new commands rejected AND A's live subscription torn down;
    device B unaffected; running-job outcomes honest;
  - stopAll delivered even after a Realtime drop (poll backstop) -> confirmed
    terminated count; stopAll works regardless of capabilities.
Then the SAME MockiOSClient drives the SAME Mac over Direct Mode with identical results.
```

## Exit Gates

- [ ] Works Test passes on **both** carriers, including every negative case.
- [ ] **Crypto contract proven by round-trip vectors** (two-key sealing via HPKE,
  both-direction signing, replay/skew, protocol version) before any cloud wiring.
- [ ] **Cloud breach can't control or read:** injected rows rejected by the Mac;
  no plaintext prompts/outputs/plans/images anywhere in Supabase or R2 (content-light
  or sealed only); audit metadata-only (`targetSummary≤200`).
- [ ] Resume correct across a **Mac restart**; snapshot includes recently-completed runs.
- [ ] **No remote-shell pathway** (enum has none; test asserts the closed set).
- [x] `RunEvent` envelope unchanged; `synthesis.*` retired from remote output.
- [ ] `RemoteClient` + reducer covered by `swift test`; proof needs no SwiftUI.
- [ ] `swift test` + app build green via `scripts/check.sh`; Code Audit CLEAN.

## Closeout

Activate `02`. The remote loop now has a frictionless cloud-relay default, a proven
two-key E2E crypto contract sealing content **both directions**, at-least-once
delivery with a reliable kill switch, a transport-agnostic trust spine with surgical
revocation and metadata-only audit, snapshots that carry overnight results, and
Direct Mode as the premium carrier — the GUI is "just" wiring SwiftUI to an
already-proven surface.
