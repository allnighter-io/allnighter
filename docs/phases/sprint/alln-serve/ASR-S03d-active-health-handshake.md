# ASR-S03d — active loopback health handshake

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §5.2
(`healthy` requires a real `GET /health` response whose daemon id, pid, and
build identity match the durable record; a live PID alone never sets
`loopback.listening = true`), §7 (`pid -> daemon` inference ban), §3 row 4.

**4 of N** in the ASR-S03 cut. Two deliverables only.

## 1. Goal

`loopback.listening` becomes an observation instead of an assumption:
`ServeDaemonProbe` performs a bounded `GET /health` against the recorded
loopback address and only reports listening when a real response comes back
from the expected daemon.

## 2. Copy-paste prompt

> Add a `ServeHealthClient` that performs one bounded `GET /health`, then make
> `ServeDaemonProbe.health(...)` use it instead of setting `listening: true`
> from the durable record. The transport is injected so no test opens a socket.
> Do not add scheduler receipts or change `ServeStatusJSON` — those are separate
> slices.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterEngine/LoopbackHealthServer.swift`
  — the existing server: it binds `127.0.0.1` only and answers `GET /health`
  with a caller-supplied JSON body. This is the thing being called.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemonProbe.swift` —
  `health(...)`, especially the branch that hard-codes
  `loopback: .init(listening: true, ...)`.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemon.swift` lines
  60–100 only — how the daemon constructs the server and what it puts in the
  health body.

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterEngine/ServeHealthClient.swift        (new)
Packages/AllnighterCore/Sources/AllnighterEngine/ServeDaemonProbe.swift
Packages/AllnighterCore/Tests/AllnighterEngineTests/ServeHealthClientTests.swift (new)
```
Plus the existing probe test file if its expectations change.

## 5. Do not read / do not touch

- Do not add scheduler receipts, `runtime.json` rows, or `ServeStatusJSON` v2 —
  ASR-S03e and ASR-S03f own those.
- Do not touch `ServeDaemon`'s runtime behavior, `ServeLifecycle`,
  `ServeDesiredState`, any CLI file, any script, or `Apps/`.
- Do not change what `LoopbackHealthServer` serves. If the body lacks a field
  the client needs, **say so in the report** rather than editing the server —
  that is S03e's slice.
- No test may open a real socket or bind a port.

## 6. Steps

1. **`ServeHealthClient.probe(host:port:timeout:) -> Result<Response, Failure>`.**
   One `GET /health`, bounded by an explicit timeout (default 2s), against
   `127.0.0.1` only. The transport is an injected closure
   (`(URLRequest) async -> (Data?, Int?, Error?)` or equivalent) so tests supply
   canned responses. Refuse a non-loopback host outright — this client never
   talks to the network.

2. **Distinguish the failure modes**, because they mean different things to a
   user: connection refused (nothing listening), timeout (wedged daemon),
   non-200, and unparseable body. Each returns a distinct reason string. A
   generic "unavailable" would erase the difference between a dead daemon and a
   hung one, which is the distinction §5.2 exists to surface.

3. **Rewire the probe.** `ServeDaemonProbe.health(...)` calls the client and
   sets `loopback.listening = true` **only** on a successful response whose
   `daemonId` and `pid` match the durable record. A live pid, a recorded port,
   and a plist all become insufficient — that is the §7 `pid -> daemon` ban.

4. **Mismatch is not listening.** A 200 response from a *different* daemon id or
   pid (a recycled pid, a stale record, a second daemon) reports not-listening
   with the mismatch named. Do not treat any 200 as success.

5. **Bounded, never blocking.** The probe is called by `alln serve status` and
   `alln doctor`; a wedged daemon must not hang either. The timeout is enforced
   by the client, not by the caller remembering to pass one.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'ServeHealthClientTests|ServeDaemonProbe|Coordinator'
```

## 8. Done when

- [ ] A canned 200 with matching daemon id and pid reports listening.
- [ ] Connection refused, timeout, non-200, and unparseable body each report
      not-listening with a **distinct** reason.
- [ ] A 200 from a mismatched daemon id reports not-listening naming the
      mismatch; same for a mismatched pid (the recycled-pid fixture from §7).
- [ ] A live pid with nothing listening reports not-listening — the old
      `listening: true` path is gone (grep-provable).
- [ ] A non-loopback host is refused.
- [ ] No test opens a socket or binds a port; the suite stays sub-second.
- [ ] Focused proof passes. One commit, explicit paths.

## 9. Host-state invariant

Read-only: this changes what `alln serve status`/`doctor` *observe*, never what
runs. On the founder's host it will likely start reporting not-listening if the
frozen daemon has no health server on the recorded port — that is the truth
becoming visible, not a regression. Report it plainly if the proof shows it.
