# CR-04 — CheckRunner subprocess boundary

## Summary
`CheckRunner` correctly delegates subprocess lifecycle to `CommandRunner` and its
`CheckResult.passed` is conservative on the timeout/skipped axes. Two security
issues sit at the subprocess boundary: (1) the full host environment is forwarded
to a `/bin/sh -c` run whose captured stdout/stderr is stored onward — a direct
secret-exfiltration surface; (2) arbitrary shell execution of `check.command` is
by-design, so the file's security depends entirely on upstream provenance of
`WorkSlicePacket.Check.command`, which is not guarded here. There is also a
correctness footgun: skipped GUI/observation results carry `exitCode == 0`,
inviting any consumer that reads `exitCode` directly (bypassing `.passed`) to
treat a skipped check as a pass.

## Findings

### P0 — Full parent environment forwarded to repo-declared shell command (secret exfiltration surface)
- **Invariant:** a subprocess spawned to run repo-declared logic must receive a
  minimal, allowlisted environment; it must never inherit the host process's
  full env (which may carry API keys, tokens, Keychain-derived values, or
  provider credentials).
- **Evidence:** `CheckRunner.swift:45` (`env: ProcessInfo.processInfo.environment`)
  combined with `CheckRunner.swift:42-44` (`commandRunner.run(command: "/bin/sh",
  args: ["-c", command], ...)`). The captured `stdoutTail` at `CheckRunner.swift:52`
  is built from `result.stdout + result.stderr` (`CheckRunner.swift:49`) and is
  stored/passed onward, so a check command that runs `printenv` / `env` can
  exfiltrate any inherited secret into the stored tail.
- **Suggested fix:** construct an explicit env map (PATH, HOME, LANG, plus an
  allowlist of `ALLN_*` vars) and pass that; never forward
  `ProcessInfo.processInfo.environment` wholesale. At minimum, strip known-secret
  env keys (anything matching provider credential prefixes) before forwarding.
- **Suggested slice:** "CheckRunner: substitute minimal env for subprocess"

### P0 — Arbitrary shell execution of `check.command` — trust boundary must be enforced upstream (by-design, unguarded here)
- **Invariant:** `check.command` is executed verbatim by `/bin/sh -c`; any party
  able to influence `WorkSlicePacket.Check.command` obtains arbitrary code
  execution as the Allnighter user. The invariant ("only the repo's own,
  user-reviewed check declaration may populate this field") must be guaranteed
  *before* this function is reached.
- **Evidence:** `CheckRunner.swift:42-44` (`commandRunner.run(command: "/bin/sh",
  args: ["-c", command], ...)`); `command` is sourced from `check.command`
  (`CheckRunner.swift:38`). There is no provenance check in `CheckRunner`.
- **Note:** this is the intended design ("repo-declared check"), so it is not a
  defect in this file. It is a P0 because the file's security posture is
  *entirely* contingent on an invariant this file does not enforce. Model output,
  network packets, or untrusted `WorkSlicePacket`s must never reach
  `check.command`.
- **Suggested fix:** document the trust boundary on the `WorkSlicePacket.Check`
  constructor / `.command` setter; add a debug assertion that `check.command`
  originated from a repo-declared source (not a model or network payload). Confirm
  no caller constructs `Check` from untrusted input.
- **Suggested slice:** "WorkSlicePacket.Check: assert repo-declared provenance for command"

### P1 — Skipped GUI/observation result sets `exitCode = 0`, inviting false-positive reads by consumers that bypass `.passed`
- **Invariant:** a skipped check must never be observable as "succeeded." The
  only safe exit code for "did not run" is `nil`.
- **Evidence:** `CheckRunner.swift:56` (`return .init(exitCode: 0, skipped: true)`)
  vs. the empty-command branch at `CheckRunner.swift:39` (`return .init(skipped:
  true)` — implicitly `exitCode: nil`, the safe form). `passed`
  (`CheckRunner.swift:18`) correctly returns false because of `!skipped`, but any
  consumer that reads `exitCode == 0` directly — a telemetry path, a judgment
  chain, a log filter, a metrics counter — will treat the GUI/observation branch
  as a pass. The two skipped returns are asymmetric, which is the footgun.
- **Suggested fix:** return `.init(skipped: true)` (exitCode nil) in the
  `.guiFixture, .userObservation` branch too; or, better, replace the
  exitCode/skipped bool pair with a `CheckStatus` enum so `exitCode` is only
  attached to a real `.ran` case.
- **Suggested slice:** "CheckResult: never attach exitCode=0 to skipped results"

### P1 — `exitCode == nil` from a real `.command` run is a silent failure with no diagnostic signal
- **Invariant:** a `.command` run that fails to spawn (`CommandRunner` returns
  `exitCode == nil`, `timedOut == false`) must be distinguishable from a real
  non-zero exit and from "not yet run."
- **Evidence:** `CheckRunner.swift:51-54` forwards `result.exitCode` directly;
  `passed` (`CheckRunner.swift:18`) = `exitCode == 0 && !timedOut && !skipped`. A
  nil exitCode yields `passed == false` with neither `timedOut` nor `skipped` set,
  so a downstream "why did it fail?" probe has nothing to read, and the captured
  tail may be empty.
- **Suggested fix:** when `result.exitCode == nil && !result.timedOut`, set
  `skipped: true` (or a new `didNotRun` flag) so spawn failures surface
  distinctly from real failures; at minimum, synthesize a diagnostic tail like
  `<check did not start>`.
- **Suggested slice:** "CheckRunner: distinguish spawn-failure from non-zero exit"

### P2 — `tail` counts grapheme clusters, not bytes; `stdoutTailLimit` unit is ambiguous
- **Invariant (clarity):** the documented unit of `stdoutTailLimit` should match
  what `tail` actually enforces.
- **Evidence:** `CheckRunner.swift:24` (`stdoutTailLimit = 4_096`) and
  `CheckRunner.swift:62-63` (`trimmed.count > stdoutTailLimit` then
  `String(trimmed.suffix(stdoutTailLimit))`). Swift `String.count`/`suffix`
  operate on extended grapheme clusters, so a 4096-emoji tail is ~16 KB UTF-8.
  Callers budgeting "4 KB" for `stdoutTail` will overshoot.
- **Suggested fix:** rename to `stdoutTailCharLimit` to make the unit explicit,
  or truncate on `utf8.count` if a byte budget is intended. Grapheme-aware
  truncation is actually *good* (no broken UTF-8), so I lean toward renaming +
  doc, not changing behavior.
- **Suggested slice:** (nit, optional)

### P2 — Inherited `PATH` (subset of P0 env finding) — binary resolution not pinned
- **Evidence:** `CheckRunner.swift:45` forwards the full environment, including
  `PATH`. A repo-declared check like `npm test` resolves `npm` via the host PATH,
  which may include user-local dirs (`~/.local/bin`, volta, nvm shims) absent in
  CI. The check may pass locally and fail in CI (or vice versa), undermining the
  "advance signal" value.
- **Suggested fix:** alongside the minimal-env fix in the first P0, either pin a
  documented PATH or record the resolved binary path in `CheckResult` for
  diagnostics.
- **Suggested slice:** (fold into the P0 env slice)

## False alarms ruled out
- **Shell injection via `/bin/sh -c`.** By design. The check command is meant to
  be an arbitrary shell snippet authored by the repo. The argv is constructed
  correctly (`args: ["-c", command]`, `CheckRunner.swift:43-44`), so there is no
  second level of shell interpolation. The real risk is *provenance* of
  `check.command` (covered in the second P0), not the use of `/bin/sh -c`.
- **Empty-command `sh -c ""` falsely passing.** Guarded: `CheckRunner.swift:38-41`
  trims and rejects empty commands, returning `skipped`. Verified `skipped == true`
  ⇒ `passed == false` (`CheckRunner.swift:18`). No false pass.
- **Zombie processes / timeout reaping.** Not introduced by this file. The
  subprocess lifecycle (SIGKILL on timeout, `waitpid`) is delegated to
  `CommandRunner.run` (`CheckRunner.swift:41-48`); `timedOut` is faithfully
  propagated (`CheckRunner.swift:53`). Within this file's boundary every spawn
  goes through `commandRunner`, so no zombie leak originates here. Verify
  `CommandRunner` separately.
- **`tail` producing broken UTF-8.** Not a defect: `String.suffix` is
  grapheme-cluster-aware (`CheckRunner.swift:63`), so it never splits a
  multi-byte sequence. See the P2 only for unit-naming clarity.
- **Timeout default.** 300 s (`CheckRunner.swift:23`) is a reasonable signal
  budget and the caller can override (`CheckRunner.swift:34`). Not a finding.
- **`Sendable` soundness of `CheckRunner`.** Holds iff `CommandRunner` is
  `Sendable`; that contract is owned by `CommandRunner`, not this file.
- **`combined = stdout + stderr` ordering.** Concatenation order is a deliberate
  choice (stdout first, stderr appended, `CheckRunner.swift:49`); for an "advance
  signal" tail this is acceptable. Not a defect.

## Greps avoided
- Did not read or grep any other file. Only the inlined `CheckRunner.swift` and
  the resolved-symbol annotations were used. `CommandRunner`, `WorkSlicePacket.Check`,
  and consumers of `CheckResult.passed` were *not* inspected; findings that
  depend on their behavior are explicitly flagged as depending on those owners
  (the second P0, the second P1, the second P2, and the zombie false-alarm).