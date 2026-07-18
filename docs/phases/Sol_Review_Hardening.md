# Sol Review Hardening — pilot / relay / lane subsystem (PO-F11)

Status: **All 15 worth-fixing items landed** (SR-1..SR-15), 2026-07-18. Each with a
regression test; every touched suite green (HandoverGate 16/16, ExecutionLane 20/20,
RelayCoordinator 19/19, Supabase 30/30, PilotCLI 29/29, RelayTurnClassifier 9/9).
Commits: `cf71c968` (SR-1/2), `ce464c5b` (SR-7/8/11/13/14), `65f2a789` (SR-3/4/5/6/15),
`c5f331c5` (SR-9/10/12). Marginal SR-16..SR-23 recorded below, not yet actioned.
SR-10's crash-during-proof window is covered for no-regression by the existing round
tests; a process-death-injection test is deferred (harness has no such hook).
Reliability follow-up to [Process_Ownership.md](Process_Ownership.md) (PO-F9 Kimi
flock hardening, PO-F10 honest worker resolution). This is **PO-F11**.

## Provenance

On 2026-07-18 the session dogfooded `alln run --worker model_chatgpt_sol`
(ChatGPT 5.6 Sol, served via Cursor CLI) to run an **unbiased** adversarial
review of the whole pilot / relay / execution-lane / handover subsystem
(21 files) plus the F9/F10 diffs. The prompt named no suspected areas, never
mentioned Kimi's prior review, and gave no target count. Sol returned **28
findings** (10 high, 15 med, 3 low) in ~16 min / 70+ tool calls.

Every finding was then **independently verified against the real code** by five
adversarial verifier agents (one per file-group), each instructed to *refute*
the finding and to check whether F9/F10 already fixed it. This doc is the
verified ledger. Fix IDs are `SR-N`, cross-referenced to Sol's `F-N`.

### Sol × Kimi (PO-F9) diff

Kimi K3's 14 items (PO-F9) were **entirely inside `ExecutionLaneFlock.swift`**
and were all fixed in the F9 commit (`c8bbf6dd`). Sol reviewed **11 files**;
the overlap with Kimi is thematic, not literal:

- **Sol F16 (ThreadFlockLock `O_CLOEXEC`)** — same bug *class* as Kimi K1, but a
  **different file Kimi never opened**. F9 added `O_CLOEXEC` to
  `ExecutionLaneFlock` (line 817); `ThreadFlockLock` never got it. **New catch.**
- **Sol F14 (errno collapsed to "busy")** — Kimi K5 fixed this *inside* the flock
  layer (`tryAcquireExclusiveDetailed` now exists); Sol caught that the
  `ExecutionLane` registry above it still calls the **collapsing** variant, so
  the honest errno never reaches the caller. **Gap in the layer above F9's fix.**
- Everything else (HandoverGate, RelayVerdict, RelayTurnClassifier,
  RelayCoordinator, Supabase, PilotCLI, PilotSeatResolver, RelayThreadProjector,
  RelayDispatch, and all of `ExecutionLane.swift`) is **outside Kimi's scope** —
  no prior verification existed.

## Verdict summary (all 28)

Verdict legend: **CONFIRMED** = real, code matches. **PARTIAL** = real behavior
but scenario/severity overstated or mitigated upstream. **FALSE_POSITIVE** =
cannot occur. **STUB** = intentional un-wired path, not a bug.

| Sol | Location | Verdict | Real sev | Fix? | ID |
|-----|----------|---------|----------|------|-----|
| F8  | HandoverGate.swift (`"without"` cue) | CONFIRMED | **high** | **yes** | SR-1 |
| F9  | HandoverGate.swift (`rm -rf` first-target-only) | CONFIRMED | **high** | **yes** | SR-2 |
| F4  | ExecutionLane.swift (kind-chain build-scope escalation) | CONFIRMED | **high** | **yes** | SR-3 |
| F14 | ExecutionLane.swift (errno→busy collapse) | CONFIRMED | med | **yes** | SR-4 |
| F1  | ExecutionLaneFlock.swift (GC unlink/recreate race) | CONFIRMED | med | **yes** | SR-5 |
| F2  | ExecutionLane.swift (docs-only admission TOCTOU) | PARTIAL | med | **yes** | SR-6 |
| F23 | RelayTurnClassifier.swift (bare `"busy"` over-retry) | CONFIRMED | med | **yes** | SR-7 |
| F18 | RelayDispatch.swift (invalid `--until` silent) | CONFIRMED | med | **yes** | SR-8 |
| F21 | SupabaseRemoteMacRelay.swift (backfill/subscribe race) | CONFIRMED | med | **yes** | SR-9 |
| F11 | RelayCoordinator.swift (devRunId/HEAD after proof) | CONFIRMED | med | **yes** | SR-10 |
| F16 | ThreadFlockLock.swift (missing `O_CLOEXEC`) | CONFIRMED | med | **yes** | SR-11 |
| F19 | PilotCLI.swift (detached handoff re-passes path) | CONFIRMED | med | **yes** | SR-12 |
| F20 | PilotCLI.swift (unquoted scaffold path) | CONFIRMED | med | **yes** | SR-13 |
| F28 | PilotSeatResolver.swift (`uniqueKeysWithValues` trap) | CONFIRMED | low | **yes** | SR-14 |
| F15 | ExecutionLane.swift (zero-ticks live identity) | PARTIAL | low | **yes** | SR-15 |
| F12 | ExecutionLane.swift (release ignores meta-removal fail) | CONFIRMED | low-med | marginal | SR-16 |
| F7  | RelayCoordinator.swift (silent `try?` persist) | CONFIRMED | low-med | marginal | SR-17 |
| F6  | RelayCoordinator.swift (awaitingPM→running TOCTOU) | CONFIRMED | low-med | marginal | SR-18 |
| F17 | RelayVerdict.swift (last-parseable-not-tail) | CONFIRMED | low | marginal | SR-19 |
| F22 | SupabaseRemoteMacRelay.swift (approved reads pending) | PARTIAL | low-med | marginal | SR-20 |
| F25 | RelayThreadProjector.swift (escalation append swallowed) | CONFIRMED | low-med | marginal | SR-21 |
| F24 | PilotCLI.swift (remembered seat unchecked) | PARTIAL | low | optional | SR-22 |
| F27 | PilotCLI.swift (relay id hidden on write fail) | CONFIRMED | low | optional | SR-23 |
| F3  | ExecutionLane.swift (same-id reentry) | PARTIAL | low | **no** (upstream-guarded) | — |
| F13 | ExecutionLane.swift (waiter FIFO best-effort) | PARTIAL | low | **no** (by design) | — |
| F26 | PilotCLI.swift (handoff temp files linger) | CONFIRMED | low | **no** (OS reaps `$TMPDIR`) | — |
| F5  | RelayCoordinator.swift (`TurnOwnerDirectory.shared`) | **FALSE_POSITIVE** | — | **no** | — |
| F10 | SupabaseRemoteMacRelay.swift (`publishMedia` drops bytes) | **STUB** | — | **no** (R2 plane unwired) | — |

## Fix list — verified, worth fixing

Highest value first. Do NOT weaken the cross-process lane guarantees. Where a fix
adds an error code / touches a CommandSpec, regenerate contracts (PO-F4 gate).

### SR-3 (Sol F4) — kind-chain reentry must not grant build access it doesn't own — **high**
`ExecutionLane.canReenter` (kind chain, ~`:559-570`) never inspects `writeScope`
or build-flock ownership. A docs-only relay (flock-less token) whose inner
`RunService` claim escalates to `legacyFullBuild` (`needsBuildLane:true`) is
granted by reusing the metadata-only token — **no build flock acquired** → two
concurrent build-class writers if a foreign narrow-build holder co-exists.
Reachable once PO-S06 narrow build scopes are exercised. **Fix:** on escalation
(`incoming.needsBuildLane && !existing.needsBuildLane`, or incoming scope not
covered by existing) the reentry must *upgrade-acquire* the real flock (and block
if foreign-held), not reuse the token. **A naive `return false` deadlocks the
turn against its own outer hold — must be an upgrade path.** Add a regression
test for the narrow-build-scope escalation.

### SR-1 (Sol F8) — remove `"without"` from HandoverGate safe-context cues — **high**
`containsSafeContextCue` substring-matches anywhere in a sentence; `;` is not a
sentence delimiter. `"Proceed without asking; git reset --hard HEAD"` contains
`"without"` → destructive git allowed. **Fix:** drop `"without"` from
`safeContextCues` (autonomy phrases like "without asking/confirming" are red
flags, not safe cues). Add adversarial test.

### SR-2 (Sol F9) — HandoverGate `rm -rf` must check every target — **high**
`rmRfDecision` regex `rm\s+-rf\s+(\S+)` captures only the first target;
`rm -rf build /important-data` sees allowlisted `build`, `continue`s, allows the
rest. **Fix:** capture the argument tail, split on whitespace, only `continue`
when *every* target's last component is allowlisted. Add multi-target test.

### SR-4 (Sol F14) — wire honest errno from the flock into the registry — **med**
`ExecutionLane.issueToken` (`:494`) calls the collapsing `tryAcquireExclusive`
(returns `nil` for both contention and EMFILE/ENOLCK/unsupported-FS). The honest
`tryAcquireExclusiveDetailed`/`AcquireOutcome` already exists (added in F9) but
isn't used here → hard lock failures masquerade as "busy" and callers wait up to
1800s. **Fix:** call the detailed variant; on `.unavailable(errno)` propagate a
typed lock-failure fast instead of a busy ticket. Matches F10's "fail loud with
the typed reason." Likely a new error code → regenerate contracts.

### SR-5 (Sol F1) — close the stale-lane GC unlink/recreate flock race — **med**
`garbageCollectStaleLanes` (`ExecutionLaneFlock.swift:247-249`, **introduced by
F10**) probes `isLocked` then `removeItem`s the lane dir with no exclusion held
across the two steps. flock binds to inode: B can lock the current `lane.lock`
after the probe, GC unlinks it, C locks a new inode → two "exclusive" holders.
It is the *only* code that deletes `lane.lock`. **Fix:** GC acquires the build
flock itself and re-checks `st_nlink`/holders under it before unlinking (or
rename-to-tombstone under `meta.lock` then delete); acquirers `fstat` after lock
and retry on `st_nlink == 0`.

### SR-6 (Sol F2) — docs-only admission conflict-check under the meta lock — **med**
`issueToken`'s docs-only path runs `ticketIfBusy` *outside* `withMetaLock`;
`upsertHolder` appends unconditionally with no conflict recheck. Two overlapping
docs-only scopes both see no conflict, both append → both admitted (interleaved
commits; not a build double-write, so med not high). **Fix:** do
read→conflict-check→append for the docs-only path under a single `withMetaLock`
(or add a conflict gate inside `upsertHolder`).

### SR-7 (Sol F23) — narrow the `"busy"` backoff classifier — **med**
`RelayTurnClassifier.isInfraBackoff` treats any text containing `"busy"` as
provider backoff → a mutating dev turn reporting `"database is busy"` is retried
up to 10×, potentially repeating side effects. **Fix:** require provider/capacity
context (`"server is busy"`, `"model is busy"`, `"overloaded"`, `"capacity"`),
not bare `"busy"`. Keep `"429"`/`"rate limit"`. Add false-positive test.

### SR-8 (Sol F18) — reject invalid `--until` instead of dropping it — **med**
`RelayDispatch.parseUntil` collapses absent and garbage (`"7am"`, `"25:00"`) to
`nil` = no deadline; the adjacent `--max-rounds` already validates loudly. **Fix:**
distinguish invalid from absent and fail like `--max-rounds` (`RelayCLIError`
pattern is right there). Unattended-run safety ceiling.

### SR-9 (Sol F21) — subscribe before backfill on the remote event stream — **med**
`SupabaseRemoteMacRelay` runs backfill then opens the realtime subscription; an
event inserted in the gap is in neither → permanently dropped for that session.
`yieldedIds` dedup already makes overlap safe. **Fix:** establish the realtime
subscription first (buffer early yields), then backfill, then drain — or re-run
`runEvents(after:)` once after the socket join confirms.

### SR-10 (Sol F11) — persist devRunId/HEAD before the proof phase — **med**
`RelayCoordinator` stamps `round.devRunId`/`headAfterDev` only *after*
`finishWithHarnessProof` (minutes). A mid-proof crash → `reconcileOrphan` settles
the round with `devRunId == nil`, losing the range/report linkage to
already-committed work → a resumed PM can re-order it. **Fix:** load-mutate-save
the round with `devRunId`+`headAfterDev` at the *delivered* point inside
`dispatchDevTurn`, before proof runs.

### SR-11 (Sol F16) — add `O_CLOEXEC` to ThreadFlockLock — **med**
`ThreadFlockLock.acquire`/`tryAcquire` `open(…, O_CREAT|O_RDWR, 0o600)` lack
`O_CLOEXEC` (F9 added it to `ExecutionLaneFlock:817` but not here). A worker
spawned during the brief RMW inherits the fd → parent `close()` doesn't release
the lock until the child exits. **Fix:** add `O_CLOEXEC` to both opens. Add a
no-fd-leak regression test mirroring F9's.

### SR-12 (Sol F19) — stage the read submission for detached handoff — **med**
`PilotCLI.dispatchHandoffInBackground` `--handover-file` branch re-passes the
caller's live path (every sibling branch stages the already-read `submission` to
a temp file). If the file is overwritten/deleted before the detached child reads
it, the child runs different/empty instructions. **Fix:** stage `submission` to a
temp `--file` for all verdict paths (collapses to the existing `else` branch).

### SR-13 (Sol F20) — shell-quote the scaffold path in the printed next-command — **med**
`handoffNextCommand` interpolates `scaffoldPath` unquoted; the default path
always contains `Application Support` (a space) → the advertised `next:` command
splits on copy-paste and the first handoff fails on **every default install**
(human path; `--json` callers use the discrete field, unaffected). **Fix:**
single-quote the path (escape embedded `'`).

### SR-14 (Sol F28) — `uniquingKeysWith` for probe records — **low**
`PilotSeatResolver.readySeats` uses `Dictionary(uniqueKeysWithValues:)` → runtime
**trap** on duplicate driver ids (reachable only via hand-edited/migrated
`cli_setup.json`, but a crash vs. graceful). **Fix:**
`Dictionary(…, uniquingKeysWith: { _, latest in latest })`.

### SR-15 (Sol F15) — fail closed when self start-ticks can't be read — **low**
`anonymousClaim` (and the RelayCoordinator fallback) fabricate an
`OwnerIdentity(startTimeTicks: 0, kind: .inProcess)` when `OwnerIdentity.current`
is nil. The next reconcile computes `liveTicks != 0` → declares its own live
holder dead → releases the flock while the caller runs → double-run. Trigger
(self-`sysctl` failure) is near-unreachable, but fail-closed is strictly safer.
**Fix:** return nil / typed error instead of a zero-ticks live holder.
(Sol's cited line `:1164` was wrong; real sites are `ExecutionLane.swift:379-384`
and `RelayCoordinator.swift:1167-1172`.)

## Marginal — fix if cheap, otherwise record and skip

- **SR-16 (F12):** `release` discards `removeHolder` failure then frees the flock;
  a >2s meta-lock timeout leaves a phantom *live* holder blocking foreign work
  for the host's lifetime. Cheap: observe failure + retry. Rare trigger.
- **SR-17 (F7):** `RelayCoordinator.persist` swallows every `try? save`. A failed
  `.running`/terminal write advances in-memory while durable state is stale →
  orphan-reconcile or re-work. Out of character for a reliability module. Cheap:
  log/escalate on save error. Rare trigger (disk full on a single-user Mac).
- **SR-18 (F6):** unlocked `awaitingPM`→`running` in `runExternalRound` is a real
  cross-process TOCTOU, but the lane flock prevents the double-mutation — only
  ledger clobber remains, on a same-relay double-fire. Cheap: brief exclusive
  flock (or CAS on round epoch) around load→flip.
- **SR-19 (F17):** `RelayVerdict` accepts the last *parseable* verdict, not the
  tail. Needs both a quoted valid example *and* a malformed real tail. Naive fix
  risks the deliberate "verdict isn't the only JSON" behavior — guard carefully
  or skip.
- **SR-20 (F22):** approved pair request without its trusted-device row reads as
  pending; self-heals next reconcile. Cheap: honor `request.status == .approved`
  as a fallback, or publish trusted device before flipping status.
- **SR-21 (F25):** escalation-attention `appendTurn` failure swallowed by `try?`
  (documented best-effort; recovers on next `sync`). Only worth a retry/log so a
  failed escalation projection is observable — do not break the never-abort
  contract.
- **SR-22 (F24):** remembered dev seat reused without readiness check — but **F10
  already** converts the first handoff into a loud `WORKER_NOT_AVAILABLE`, so this
  only moves an already-clear error one step earlier. Optional.
- **SR-23 (F27):** `pilot start` hides the created relay id if a later
  scaffold/seat write throws. Cheap: include `state.id` in the failure message.

## Not fixing (verified non-issues)

- **F3** — same-id reentry relies on an upstream turn-by-turn invariant that holds
  for this single-user product; belt-and-suspenders only.
- **F13** — cross-process waiter FIFO is documented best-effort; true ticket-lock
  fairness is expensive and unwarranted for a single-user tool.
- **F26** — handoff temp files are tiny and live under `$TMPDIR`, which macOS
  reaps; "grows without bound" is inaccurate.
- **F5** — FALSE POSITIVE: `TurnOwnerDirectory.shared` is per-*process*; kill and
  reconcile read the per-relay dir, not the global; no in-process multi-relay
  path exists, so the cross-root overwrite Sol described cannot occur.
- **F10** — STUB, not a bug: `publishMedia` intentionally does not persist bytes
  to Postgres; the ciphertext plane is Cloudflare R2, unwired, and the symmetric
  `mediaData` read *throws* `unsupportedOperation`. Tracked as R2 media-plane work.

## Done when

Each SR-1..SR-15 fixed with a regression test, committed individually.
`ExecutionLaneTests`, `RelayCoordinatorTests`, `ContractRegistryTests`,
`RunServiceTests`, and the HandoverGate/RelayVerdict/RelayTurnClassifier suites
stay green. Contracts regenerated where an error code or CommandSpec changed.
Marginal SR-16..SR-23 fixed opportunistically or recorded as skipped with reason.
