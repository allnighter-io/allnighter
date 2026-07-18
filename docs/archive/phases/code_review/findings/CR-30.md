# CR-30 — ResidentCoordinatorProbe liveness

## Summary
The probe correctly branches on record presence and `processAlive(pid)` into
`foregroundOnly` / `unavailable` / `available`, and the dead-PID path honestly
reports `listening: false`. However, liveness is equated with PID aliveness
alone: the record's `startedAt` is carried into the output but never
cross-checked against the live process, so PID reuse can report a dead
coordinator as `.available` with `loopback.listening: true` — a direct violation
of the file's "Never fakes liveness" contract. Separately, `loopback.listening`
is derived from process aliveness rather than a real socket probe, and
`activeObligationCount` is hardcoded to `0` in all three return paths.

## Findings

### P0 — PID reuse reports a dead coordinator as `.available`
- **Invariant:** "Never fakes liveness" (file header, ResidentCoordinatorProbe.swift:5);
  "A failed worker is shown failed, never faked" (AGENTS.md Project Laws).
- **Evidence:** ResidentCoordinatorProbe.swift:40 (`guard processAlive(record.pid)`)
  gates the `.available` return at ResidentCoordinatorProbe.swift:53-63. The only
  identity check is the PID. `startedAt` (ResidentCoordinatorProbe.swift:57) is
  copied into the output but never compared to the live process's actual start
  time. If the coordinator dies and the OS recycles that PID to an unrelated
  process, `processAlive` returns true and the probe emits `state: .available`
  plus `loopback.listening: true` (ResidentCoordinatorProbe.swift:61) for a
  coordinator that no longer exists.
- **Suggested fix:** Before trusting the PID, verify process identity. Compare
  `record.startedAt` to the live process's kernel start time (e.g.
  `proc_pidinfo`/`PROC_PIDTASKINFO` via libproc, or `ps -o lstart`), or verify
  the process executable path matches the coordinator binary, or store a
  coordinator-owned secret token in the record and confirm it over the loopback
  socket. On mismatch, fall through to the `.unavailable` return.
- **Suggested slice:** "ResidentCoordinatorProbe: bind liveness to process start time, not PID alone"

### P1 — `loopback.listening` asserted from process aliveness, not a socket probe
- **Invariant:** "Never fakes liveness" (ResidentCoordinatorProbe.swift:5).
- **Evidence:** ResidentCoordinatorProbe.swift:61 sets
  `loopback: .init(listening: true, ...)` whenever the PID is alive. A live
  process does not prove the loopback listener is bound: the coordinator may be
  alive but not yet listening, may have dropped the socket, or may be hung. The
  `unavailable` path correctly sets `listening: false`
  (ResidentCoordinatorProbe.swift:49), so the asymmetry is deliberate — the
  `available` path over-claims.
- **Suggested fix:** Attempt a short-timeout TCP connect to
  `record.loopbackHost:record.loopbackPort` and set `listening` from the connect
  result, independent of process aliveness. If the PID is alive but the connect
  fails, report `.available` with `loopback.listening: false` (or a distinct
  degraded state) rather than `true`.
- **Suggested slice:** "ResidentCoordinatorProbe: prove loopback listening via connect probe"

### P1 — `activeObligationCount` hardcoded to 0
- **Invariant:** Health output must reflect real coordinator state, not
  decorative defaults.
- **Evidence:** `activeObligationCount: 0` is hardcoded in all three return
  paths — ResidentCoordinatorProbe.swift:37 (foregroundOnly),
  ResidentCoordinatorProbe.swift:50 (unavailable), and
  ResidentCoordinatorProbe.swift:62 (available). The probe already holds
  `runsDirectory` (ResidentCoordinatorProbe.swift:8) and builds a journal with
  `orphanRecovery`/`incrementalDurable` flags (ResidentCoordinatorProbe.swift:25-29),
  but never counts active obligations in `runsDirectory`. The field always
  reports zero even when active runs exist.
- **Suggested fix:** Count active obligation markers in `runsDirectory` (or read
  the count from the coordinator record / loopback health endpoint) and pass the
  real number. If the count is genuinely unknowable in a given state, make the
  field optional or document that `0` means "unknown" rather than "none."
- **Suggested slice:** "ResidentCoordinatorProbe: read real activeObligationCount from runs dir"

### P2 — `currentPID` captured but never used
- **Invariant:** No dead injected dependencies.
- **Evidence:** ResidentCoordinatorProbe.swift:10 declares `currentPID` and
  ResidentCoordinatorProbe.swift:21 assigns it (default
  `ProcessInfo.processInfo.processIdentifier`), but it is never referenced in
  `health` or `doctorCoordinator`. It looks intended for self-liveness
  detection (the probing process is itself the coordinator) but that path is not
  implemented.
- **Suggested fix:** Either use `currentPID()` to short-circuit when the probing
  process is the coordinator (returning self-consistent health), or remove the
  parameter and its default.

### P2 — `directoryWritable` mutates the filesystem on a read-only probe
- **Invariant:** "Builds read-only coordinator health"
  (ResidentCoordinatorProbe.swift:4).
- **Evidence:** ResidentCoordinatorProbe.swift:83 calls
  `try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)`
  on every `health` invocation. Creating directories is a write side effect on a
  probe documented as read-only; the `try?` also swallows the failure reason
  before the `isWritableFile(atPath:)` check at ResidentCoordinatorProbe.swift:84.
- **Suggested fix:** Drop the `createDirectory` call; check
  `isWritableFile(atPath:)` against the existing directory and treat a missing
  directory as non-writable (which is the correct journal state). If directory
  creation is genuinely desired, move it to the writer path, not the read-only
  probe.

### P2 — `doctorCoordinator` passes an empty `binaryVersion`
- **Invariant:** Avoid meaningless intermediate values.
- **Evidence:** ResidentCoordinatorProbe.swift:67 calls
  `health(binaryVersion: "", ...)`. The empty value flows into `CoordinatorHealth`
  on the `foregroundOnly` path (ResidentCoordinatorProbe.swift:34), so a
  `doctorCoordinator` call in the foreground-only state produces a health object
  with `binaryVersion: ""`, which is misleading if that path is ever surfaced.
- **Suggested fix:** Pass the real CLI binary version into `doctorCoordinator`
  (add a parameter or resolve from CLI context), or have `doctorCoordinator`
  skip the `health` call for fields it does not use.

## False alarms ruled out
- **`Sendable` conformance:** `ResidentCoordinatorProbe` is a `struct` with `let`
  properties of `Sendable` type (`ResidentCoordinatorStore`, `URL`, `@Sendable`
  closures). No mutable shared state; conformance is sound.
- **`foregroundOnly` path (ResidentCoordinatorProbe.swift:30-39):** No record →
  no resident coordinator claimed → `foregroundOnly` with `listening: false` is
  correct, not a false-dead report.
- **`unavailable` path (ResidentCoordinatorProbe.swift:40-51):** Dead PID →
  `unavailable` with `listening: false` is correct. Preserving `loopback`
  host/port from the record for diagnostics is fine.
- **Journal flags all tied to `runsWritable` (ResidentCoordinatorProbe.swift:25-29):**
  Reasonable for a probe — all three journal guarantees depend on the runs
  directory being writable. Not a finding.
- **Record versions override probe inputs in `available`/`unavailable`
  (ResidentCoordinatorProbe.swift:46-47, 58-59):** Correct — the resident
  coordinator's own contract/binary versions are authoritative, not the probing
  CLI's. Not a finding.
- **`processAlive` accuracy / false-dead risk:** The default
  `RunStore.processAlive($0)` (ResidentCoordinatorProbe.swift:15) is the
  liveness primitive, but its source is out of scope for this review. A naive
  `kill(pid, 0)` impl can false-dead on EPERM (privileged coordinator) or
  false-alive on zombies; this is flagged as a dependency to verify in a
  follow-up, not a finding against the inlined source.

## Greps avoided
Confirmed: no repo exploration. This review is based solely on the inlined
`ResidentCoordinatorProbe.swift` source and the resolved-symbols list. No
`grep`, `glob`, or `read` tool calls were made against repository sources; the
only filesystem operation was checking that the findings output directory exists
before writing this file.