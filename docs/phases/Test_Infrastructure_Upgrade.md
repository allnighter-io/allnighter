# Test Infrastructure Upgrade

Status: **OPEN — incident-driven 2026-07-31**  
Sprint mapping: **TIU-S00** (baseline + stop bleeding) → **TIU-S07** (closeout)  
Authority: `AGENTS.md`, `docs/operations/Execution-Playbook.md`,
`docs/operations/TechStack.md`, `docs/phases/sprint/README.md`  
Depends on: none — execution-speed stop-gate, not product semantics  
Blocks: agent throughput on every slice; repeated `check.sh` pile-ups make
closeout and debugging unreliable. Urgent correctness fixes may still proceed
with one exact filtered proof.

**Precedent:** KansoBooks shipped an equivalent program as archived
`TestInfraUpgrade` (TIU0–TIU7) plus canonical
`Docs/operations/Test-Infra-Runbook.md`. This packet adapts those lessons to
Allnighter's SwiftPM + Xcode wall.

---

## Goal

Restore fast, trustworthy local feedback **without** lowering the correctness
bar.

Testing is not optional. The problem is that agents and humans often spend
minutes on opaque compile + full-suite runs before answering the actual risk
question — and **multiple concurrent runs against one `.build/` directory can
look hung indefinitely** (observed 2026-07-31: four overlapping `swift test` /
`xctest` invocations on the same package for 17–21 minutes).

Target loop:

```text
edit owning source
  → run the narrow deterministic check for that risk
  → (optional) check-fast hygiene gates
  → run full closeout wall only at closeout or in CI
```

---

## Incident summary (2026-07-31)

Observed on the founder machine during normal agent work:

| Symptom | Evidence |
| --- | --- |
| `check.sh` never finishes | Wrapper alive 17+ min while child `swift test` still running |
| Multiple full suites at once | Two `xctest` processes on `AllnighterCorePackageTests.xctest` + `swift test --list-tests` + `check.sh` |
| Apparent hang, not slow progress | Stack sample: main thread in `XCTWaiter`; hundreds of threads in `LoopbackHealthServer.acceptConnections()` / `DirectModeCommandServer.acceptConnections()` |
| Agent behavior amplifies | Each agent runs `bash scripts/check.sh` or `swift test` with no lock; no policy distinguishes iteration from closeout |

Cheap shell gates alone finish in **~2 seconds**. The pain is **orchestration**
(full wall as default proof) plus **concurrent `.build/` contention**, not the
grep scripts.

Rough scale today:

- ~370 test source files, ~2,870 `func test` methods in Core + Mac targets
- `scripts/check.sh` runs: full `swift test` → `code_red_works_test.sh structural`
  (more filtered `swift test`) → `alln dev export-contracts --check` →
  `xcodegen` + full `xcodebuild test`
- **No** `.github/workflows/` — all heavy proof is local

---

## Operating principles

1. **Fast path and closeout path are different products.**
2. **One test run per clone at a time** — no parallel `swift test` / `xcodebuild
   test` against the same `Packages/AllnighterCore/.build/`.
3. **A focused command answers one risk**, not every possible risk.
4. **Agents default to momentum**, not proof farming (`fix → check.sh → fix`
   loops are forbidden).
5. **Founder smoke uses exact commands.** Archive/merge uses full gates.
6. **Heavy proof belongs on CI** once wired; local Mac is for narrow proof +
   manual app try.
7. **Do not delete tests to go green** — quarantine, serialize, or move to
   nightly/CI lanes instead.
8. **Timing is a guardrail**, not a benchmarking project.

---

## Lessons from KansoBooks (what applies here)

| Kanso lesson | Allnighter application | Priority |
| --- | --- | --- |
| Founder Momentum: exact smoke wrapper, not full suite | `swift test --filter <TouchedTests>` during slices | **P0** |
| `ci-fast` — hygiene only, no compile/test suites | `scripts/check-fast.sh` (~2s gates) | **P0** |
| Agent shell guard blocks broad `cargo test` | `scripts/agent-shell-guard.py` + policy JSON | **P0** |
| `push-ci` — heavy matrix on GitHub, not local | `.github/workflows/check.yml` | **P0** |
| No parallel Cargo on shared `target/` | File lock on `.build/.alln-test.lock` | **P0** |
| Forbidden fix→test→fix loops | `AGENTS.md` + Execution Playbook | **P0** |
| `Founder test:` line in handoffs | Keep; add `Proof command:` for filtered test | **P1** |
| Verification modes table in runbook | `docs/operations/Test-Infra-Runbook.md` | **P1** |
| Integration test size limits | Audit largest `*Tests.swift` files; split only when blocking filters | **P2** |
| `cargo nextest` profiles | No direct equivalent; use `--filter`, consider `--parallel=false` for server suites | **P2** |
| `sccache` / profile tuning | Optional Swift build cache docs; not first wave | **P3** |

**Rejected for Allnighter (same as Kanso):**

- Lowering the acceptance bar or skipping required gates locally with convention only
- Making CI green by removing wall coverage
- Hiding slow tests instead of profiling/quarantining them

---

## Target verification taxonomy

| Mode | Purpose | Default posture |
| --- | --- | --- |
| **Momentum** (default) | Ship the next reviewable slice | One `--filter` proof or none + WIP note |
| **Hygiene** | Fast SSOT/grep gates | `scripts/check-fast.sh` |
| **Focused proof** | Prove touched behavior | `swift test --filter …` and/or `xcodebuild test -only-testing:…` |
| **Agent eval** | Mechanical menu/CLI matrix | `scripts/agent_eval.sh`, `verify_menu_contract.py` |
| **Closeout** | Accept a slice locally | Full `scripts/check.sh` (founder-approved or closeout unlock) |
| **CI** | Protect main | `check.sh` on push (macOS runner) |

---

## Current commands (today)

```text
# Full green wall — closeout / CI only (NOT default agent iteration)
bash scripts/check.sh

# Shared package — prefer filtered during work
swift test --disable-sandbox --package-path Packages/AllnighterCore
swift test --disable-sandbox --package-path Packages/AllnighterCore --filter Relay

# Mac app
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS'

# Mechanical agent suites (quota-free)
scripts/agent_eval.sh --suite menu-not-router
python3 scripts/verify_menu_contract.py
```

**Anti-patterns (do not use during momentum):**

- `bash scripts/check.sh` after every edit
- `swift test` with no `--filter` while iterating
- Multiple agents each starting their own `swift test` / `check.sh`
- `swift test --list-tests` as a routine step (forces package graph work)
- Polling `alln loop status --wait-for …` in agent fix loops

---

## Sprints

### TIU-S00 — Stop bleeding

**Status:** Not started  
**Owner:** infra

Deliver:

- `scripts/kill-stale-tests.sh` — terminate `xctest` / `swift-test` on this
  package older than N minutes (document in script header)
- Document emergency triage in this packet (see § Emergency triage below)
- Record baseline timings in `docs/operations/Test-Infra-Baseline.md`:
  - `check-fast` (once it exists) cold/warm
  - one representative `--filter` run warm
  - full `check.sh` once (CI target input)

Gate:

- Founder can clear a pile-up in one command
- Baseline doc exists and is rerunnable

---

### TIU-S01 — Split fast vs full wall

**Status:** Not started

Deliver:

- `scripts/check-fast.sh` — cheap gates only (~2s):
  - `check_architecture_policy.sh` (+ negative self-test)
  - TCC-safe `dev.sh` / `rebuild_cli.sh` asserts
  - `check_gui_proof.sh`
  - `check_swiftui_state.sh`
  - ThreadStore caller allowlist grep
  - `check_spawn_policy.sh`
  - ASF-S08 living-doc deny-list
- `scripts/check.sh` — calls `check-fast.sh` first, then heavy steps unchanged
- Update `docs/operations/Execution-Playbook.md` § Green Wall:
  - iteration → filtered proof + optional `check-fast.sh`
  - closeout → `check.sh`

Gate:

- `bash scripts/check-fast.sh` < 10s cold on founder machine
- `check.sh` behavior unchanged aside from fast prefix

---

### TIU-S02 — One runner lock

**Status:** Not started

Deliver:

- `scripts/alln-test-lock.sh` — acquire `Packages/AllnighterCore/.build/.alln-test.lock`
  (or repo-root lock) with TTL + holder PID
- Wire lock into a thin `scripts/swift-test.sh` wrapper used by docs/agents:
  `scripts/swift-test.sh [--filter …]`
- `check.sh` uses the wrapper for all `swift test` invocations

Gate:

- Second concurrent `swift test` fails fast with actionable message (not silent hang)
- Lock released on exit/trap

---

### TIU-S03 — Agent policy + shell guard

**Status:** Not started

Deliver:

- `scripts/agent-shell-policy.json` — modes: `momentum` (default), `smoke`,
  `closeout`
- `scripts/agent-shell-guard.py` — block during momentum:
  - `swift test` without `--filter`
  - `bash scripts/check.sh`
  - `xcodebuild test` without `-only-testing:`
- Allow: `check-fast.sh`, `swift test --filter`, `agent_eval.sh`, read-only git
- `scripts/install_agent_shell_guard.sh` for Cursor hooks (local, gitignored)
- `AGENTS.md` row → this packet + future `Test-Infra-Runbook.md`

Gate:

- Policy self-test script green
- Documented bypass: `ALLN_VERIFY_MODE=closeout` for one turn

---

### TIU-S04 — GitHub Actions CI

**Status:** Not started

Deliver:

- `.github/workflows/check.yml` on `push` + `pull_request`:
  - macOS runner
  - `bash scripts/check.sh` (or split jobs: fast gates ∥ swift test ∥ mac tests)
- `docs/operations/TechStack.md` CI row updated

Gate:

- Green CI on a trial branch
- Agents instructed: commit + push for remote proof; do not local `check.sh` during momentum

---

### TIU-S05 — Canonical runbook

**Status:** Not started

Deliver:

- `docs/operations/Test-Infra-Runbook.md` — verification modes, exact wrappers,
  what agents must not run, closeout vs CI finish lines
- Promote binding rules from this packet; archive packet when runbook + guard +
  CI are live

Gate:

- `AGENTS.md` routes test/CI questions to runbook only
- Execution Playbook links runbook, not duplicated prose

---

### TIU-S06 — Flaky / expensive test hygiene

**Status:** Not started

Deliver:

- Profile: top slow tests (log test duration once in CI or local `--enable-code-coverage` sample)
- **Serialize** server suites using `LoopbackHealthServer` /
  `DirectModeCommandServer` (document suite list)
- Audit tests missing `ALLNIGHTER_SUPPORT_DIR` isolation
- Move performance tests (`*PerformanceTests`) to CI nightly or `-only-testing` group
- Revisit `code_red_works_test.sh structural` inside every `check.sh` — avoid
  redundant second `swift test` pass after full suite (merge filters or CI-only)

Gate:

- Named slow-test owners in baseline doc
- No known hang > 60s in default wall without documented reason

---

### TIU-S07 — Closeout

**Status:** Not started

Deliver:

- Compare timings to TIU-S00 baseline
- Promote durable policy to `Test-Infra-Runbook.md` + `AGENTS.md`
- Archive this packet to `docs/archive/phases/Test_Infrastructure_Upgrade.md`

Gate:

- Filtered warm proof < 30s for typical slice (founder machine)
- Full wall runs in CI, not required for every agent turn
- No multi-runner pile-ups in a normal two-agent session

---

## Emergency triage

When tests "cannot complete" or the Mac feels wedged:

```bash
# 1. See what is running
ps aux | rg 'xctest|swift-test|check\.sh'

# 2. Kill stale Allnighter package test runners (review list first)
pkill -f 'AllnighterCorePackageTests'   # or scripts/kill-stale-tests.sh once landed

# 3. Do not start another full suite until the previous one is gone
```

If multiple agents share one clone: **one runner at a time**. Starting
`check.sh` while another `swift test` is active recreates the 2026-07-31
incident.

---

## Works tests (phase-level)

| Sprint | Proof command |
| --- | --- |
| S00 | `bash scripts/kill-stale-tests.sh --dry-run` lists only stale PIDs |
| S01 | `time bash scripts/check-fast.sh` |
| S02 | Two terminals: second `scripts/swift-test.sh --filter Foo` exits with lock error |
| S03 | `python3 scripts/test_agent_shell_guard.py` |
| S04 | Green GitHub Actions run on trial branch |
| S06 | `swift test --filter DirectModeCommandServerTests` serial clean run |

---

## Done when (phase)

- [ ] Agents default to filtered proof; full `check.sh` is closeout/CI only
- [ ] Concurrent test pile-ups are structurally prevented (lock + guard)
- [ ] `check-fast.sh` exists and is < 10s
- [ ] GitHub Actions runs the full wall
- [ ] `docs/operations/Test-Infra-Runbook.md` is canonical; this packet archived

---

## Decisions log

| Question | Ruling |
| --- | --- |
| Lower the test bar to go faster? | **No** — change workflow and enforcement |
| Delete old tests? | **No** — audit, serialize, quarantine, CI-only |
| Replace `check.sh`? | **Split** — `check-fast.sh` + `check.sh`; do not remove full wall |
| Swift parallel testing? | **Default off** for server/process suites until S06 proves safe |
| `alln serve` during tests? | Tests must use `ALLNIGHTER_SUPPORT_DIR`; document isolation |
| Agent layout-watcher subagents? | Out of scope — GUI proof gate unchanged; this packet is test execution only |
