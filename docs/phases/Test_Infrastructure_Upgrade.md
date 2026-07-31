# Test Infrastructure Upgrade

Status: **OPEN — incident-driven 2026-07-31; Spec Review Min incorporated**  
Sprint mapping: **TIU-S00** (kill + lock) → **TIU-S07** (closeout)  
Authority: `AGENTS.md`, `docs/operations/Execution-Playbook.md`,
`docs/operations/TechStack.md`, `docs/phases/sprint/README.md`  
Depends on: none — execution-speed stop-gate, not product semantics  
Blocks: agent throughput on every slice; repeated `check.sh` pile-ups make
closeout and debugging unreliable. Urgent correctness fixes may still proceed
with one exact filtered proof.

**Precedent:** KansoBooks archived `TestInfraUpgrade` (TIU0–TIU7) plus
`Docs/operations/Test-Infra-Runbook.md`. This packet adapts those lessons to
Allnighter's SwiftPM + Xcode wall.

**Spec review:** `code_spec_review_min` run `17E96993-2852-4A6F-B217-B1B81AE15C1D`
(2026-07-31). Two workers completed; Lead did not synthesize (`reconciledOrphan`).
Findings incorporated below — see § Spec Review record.

---

## Goal

Restore fast, trustworthy local feedback **without** lowering the correctness
bar.

Testing is not optional. The problem is that agents and humans often spend
minutes on opaque compile + full-suite runs before answering the actual risk
question — and **multiple concurrent runs against one `.build/` directory can
look hung indefinitely** (observed 2026-07-31: four overlapping `swift test` /
`xctest` invocations on the same package for 17–21 minutes under contention).

Target loop:

```text
edit owning source
  → run one named smoke wrapper for the touched risk
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

Rough scale today (verified in repo):

- ~370 test source files; **2,689** listed SwiftPM test cases
  (`swift test --list-tests` took ~8.5 min even when uncontended)
- `scripts/check.sh` runs: full `swift test` → `code_red_works_test.sh structural`
  (more filtered `swift test`) → `alln dev export-contracts --check` →
  `xcodegen` + full `xcodebuild test`
- **No** `.github/workflows/` — all heavy proof is local
- **No clean single-runner full-wall timing yet** — the 17–21 min figure is from
  four-way contention; S01 baseline must capture an uncontended run

---

## Operating principles

1. **Fast path and closeout path are different products.**
2. **One test run per clone at a time** — no parallel `swift test` / `xcodebuild
   test` against the same package artifact dir.
3. **A focused command answers one risk** — teach one **named wrapper**, not raw
   `swift test` syntax (`scripts/swift-test.sh --filter …`).
4. **Agents default to momentum**, not proof farming (`fix → check.sh → fix`
   loops are forbidden).
5. **Founder smoke uses exact commands.** Archive/merge uses full gates.
6. **Heavy proof belongs on CI** once wired; local Mac is for narrow proof +
   manual app try.
7. **Do not delete tests to go green** — quarantine, serialize, or move to
   nightly/CI lanes instead.
8. **Timing is a guardrail**, not a benchmarking project.
9. **Product proof ≠ implementation confidence** — label which gate proves
   behavior vs which only proves a script landed (§ Proof taxonomy).

---

## Lessons from KansoBooks (what applies here)

| Kanso lesson | Allnighter application | Priority |
| --- | --- | --- |
| Founder Momentum: exact smoke wrapper, not full suite | `scripts/swift-test.sh --filter <Suite>` — single copy-paste command | **P0** |
| `ci-fast` — hygiene only, no compile/test suites | `scripts/check-fast.sh` (~2s gates) | **P0** |
| Agent shell guard blocks broad `cargo test` | Deny-list guard (not a three-mode policy system in v1) | **P0** |
| `push-ci` — heavy matrix on GitHub, not local | `.github/workflows/check.yml` on feature branches | **P0** |
| No parallel Cargo on shared `target/` | Repo-root lock + wrapper (not `.build/` — `swift package clean` deletes it) | **P0** |
| Forbidden fix→test→fix loops | `AGENTS.md` + Execution Playbook | **P0** |
| `Founder test:` + `Proof command:` in handoffs | Filter = touched `*Tests` class name | **P1** |
| Verification modes in runbook | `docs/operations/Test-Infra-Runbook.md` (S05) | **P1** |
| Split CI: cheap hygiene ∥ expensive macOS wall | Linux job for grep gates; macOS for `swift test` + `xcodebuild` | **P1** |
| Integration test size limits | Audit largest files; split only when blocking filters | **P2** |
| `cargo nextest` profiles | `--parallel=false` for server suites (S06a); no nextest equivalent | **P2** |
| `sccache` / profile tuning | Optional; not first wave | **P3** |

**Rejected (same as Kanso):**

- Lowering the acceptance bar or skipping required gates by convention only
- Making CI green by removing wall coverage
- Hiding slow tests instead of profiling/quarantining them
- Splitting `check.sh` coverage to make CI cheaper

**Adjusted after spec review:**

- Shell guard **v1 = deny-list only**; `momentum`/`smoke`/`closeout` mode
  machinery deferred until a second mode is needed
- Guard installs via Cursor hooks — **host-agnostic enforcement is the lock +
  wrapper as the only documented test path**; Codex/Claude seats do not honor
  Cursor hooks
- CI push convention: agents push to **`tiu/*` or personal feature branches** —
  not unproven commits straight to shared `feat/design-chain` for proof farming

---

## Target verification taxonomy

| Mode | Purpose | Default posture |
| --- | --- | --- |
| **Momentum** (default) | Ship the next reviewable slice | `scripts/swift-test.sh --filter …` or none + WIP note |
| **Hygiene** | Fast SSOT/grep gates | `scripts/check-fast.sh` |
| **Focused proof** | Prove touched behavior | Named wrapper or `xcodebuild test -only-testing:…` |
| **Agent eval** | Mechanical menu/CLI matrix | `scripts/agent_eval.sh`, `verify_menu_contract.py` |
| **Closeout** | Accept a slice locally | Full `scripts/check.sh` (`ALLN_VERIFY_MODE=closeout` one command) |
| **CI** | Protect main | `check.sh` on push to feature branch |

---

## Current commands (today)

```text
# Full green wall — closeout / CI only (NOT default agent iteration)
bash scripts/check.sh

# Shared package — prefer named wrapper once landed (until then, filtered only)
scripts/swift-test.sh --filter RelayLaunchViewModelTests   # TIU-S00/S02
swift test --disable-sandbox --package-path Packages/AllnighterCore --filter Relay

# Mac app
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS' \
  -only-testing:AllnighterMacTests/RelayLaunchViewModelTests

# Mechanical agent suites (quota-free)
scripts/agent_eval.sh --suite menu-not-router
python3 scripts/verify_menu_contract.py
```

**Anti-patterns (do not use during momentum):**

- `bash scripts/check.sh` after every edit
- `swift test` with no `--filter` while iterating (use wrapper when landed)
- Multiple agents each starting their own `swift test` / `check.sh`
- `swift test --list-tests` as a routine step (~8+ min; forces package graph)
- Polling `alln loop status --wait-for …` in agent fix loops

**Choosing a filter (template):** use the touched test **class** name:
`--filter LoopDispatch` matches `LoopDispatchTests`. When unsure,
`rg 'class .*Tests' path/to/changed/file` or the sprint work order names the
exact filter.

---

## Proof taxonomy

Every sprint Works Test must say whether it is **product** (proves the incident
class is fixed) or **confidence** (proves tooling landed).

| Product outcome | Proof that counts | Confidence-only (insufficient alone) |
| --- | --- | --- |
| Founder clears pile-up | Live kill removes stale `AllnighterCorePackageTests` runner | `--dry-run` lists PIDs |
| Second suite cannot wedge `.build/` | Two terminals; second wrapper exits fast with lock message | Lock file exists |
| Agents stop farming full wall | Guard blocks bare `check.sh` / unfiltered `swift test` in hooked shell | Policy JSON parses |
| Hygiene without compile | `check-fast` green; **negative:** no `swift test`/`xcodebuild` in script | `time check-fast` < 10s |
| Full wall still at closeout | Golden ordered stage list after fast prefix | CI green on trial branch |
| Default wall does not wedged-hang | Serialized server suites complete (S06a) | Profiling report (S06b) |

---

## Sprints (recut after spec review)

> **Ordering law:** S00 stops recurrence (kill + lock). S01 extracts fast wall
> and records baseline. S02 hardens wrapper + integrates `check.sh`. S03 adds
> deny-list guard. S04 CI is **gated on S01 baseline** and a decided branch
> convention. Implement via one-screen work orders in
> `docs/phases/sprint/test-infra/` (one per slice).

### TIU-S00 — Stop recurrence (kill + minimal lock)

**Status:** Not started

Deliver:

- `scripts/kill-stale-tests.sh`
  - Match **only** this package's runners (`AllnighterCorePackageTests`,
    `swift-test.*AllnighterCore`)
  - Default stale threshold: **30 minutes** (`--max-age-minutes`, overridable)
  - `--dry-run` lists targets; default mode **kills** stale PIDs
- `scripts/alln-test-lock.sh` — repo-root lock at **`.alln-test.lock`**
  (not under `.build/` — `swift package clean` deletes `.build/`)
- `scripts/swift-test.sh` — minimal v1: acquire lock →
  `swift test --disable-sandbox --package-path Packages/AllnighterCore "$@"` → release
- § Emergency triage below stays accurate

Gate (**product**):

- Spawn/hold a dummy long-runner matching package naming →
  `kill-stale-tests.sh` removes it
- Terminal A: `scripts/swift-test.sh --filter Foo` holding lock; Terminal B:
  same command exits non-zero with actionable message within 5s

Gate (**confidence**): `--dry-run` does not kill non-matching PIDs

---

### TIU-S01 — Fast wall extraction + baseline

**Status:** Not started

Deliver:

- `scripts/check-fast.sh` — extract cheap gates currently inline in `check.sh`
  (lines 8–119): architecture policy (+ self-test), TCC asserts, gui proof,
  swiftui state, ThreadStore allowlist, spawn policy, ASF-S08 deny-list
- `scripts/check.sh` — `check-fast.sh` first, then heavy steps **unchanged**
- `docs/operations/Test-Infra-Baseline.md`:
  - `time bash scripts/check-fast.sh` cold/warm
  - `time scripts/swift-test.sh --filter RetiredVocabularyTests` warm
  - `time bash scripts/check.sh` **once, single runner, uncontended** (CI sizing input)
- Update `docs/operations/Execution-Playbook.md` § Green Wall:
  - iteration → wrapper/`--filter` + optional `check-fast.sh`
  - closeout → `check.sh`

Gate (**product**):

- `bash scripts/check-fast.sh` < 10s cold; **must not** invoke `swift test`,
  `xcodebuild test`, or `code_red_works_test.sh` (grep/trace fixture)
- `check.sh` still runs full Core suite + structural + contracts + Mac tests
  after fast prefix (golden ordered stage list or diff fixture)

Gate (**confidence**): baseline doc rerunnable via one command

---

### TIU-S02 — Wrapper hardening + wall integration

**Status:** Not started

Deliver:

- Harden `scripts/swift-test.sh`: TTL, holder PID in lock file, trap release on
  exit/signal; **canonical flag set** (`--disable-sandbox` always on — today
  `check.sh` line 123 omits it; wrapper is SSOT)
- `scripts/code_red_works_test.sh` structural path uses wrapper
- `check.sh` uses wrapper for all `swift test` invocations
- Document: bare `swift test` bypasses lock — product safety requires wrapper +
  guard, not filesystem magic alone
- Lock covers **Core `swift test` path**; document that concurrent
  `xcodebuild test` while Core holds lock is undefined until Mac wrapper lands
  (S06a follow-up or explicit second lock)

Gate (**product**): S00 dual-terminal lock test still passes after hardening;
lock survives holder crash (stale lock recoverable via TTL)

Gate (**confidence**): wrapper `--help` documents canonical flags

---

### TIU-S03 — Deny-list shell guard (v1)

**Status:** Not started

Deliver:

- `scripts/agent-shell-policy.json` — **deny-list only** (no mode system v1):
  block `swift test` without non-empty `--filter`, `swift test --list-tests`,
  `bash scripts/check.sh`, `xcodebuild test` without `-only-testing:`
- Allow: `scripts/check-fast.sh`, `scripts/swift-test.sh`, `scripts/agent_eval.sh`,
  read-only git, `kill-stale-tests.sh`
- `scripts/agent-shell-guard.py` + `scripts/test_agent_shell_guard.py` (table-driven
  near-miss corpus: empty `--filter`, `bash -c 'scripts/check.sh'`, etc.)
- `scripts/install_agent_shell_guard.sh` for Cursor (local, gitignored)
- Bypass: **`ALLN_VERIFY_MODE=closeout` applies to the next guarded command only**
  (guard clears/unsets after one allow — not a permanent env escape hatch)
- `AGENTS.md` teaches wrapper as the only documented test entrypoint

Gate (**product**): policy self-test blocks near-miss strings

Gate (**confidence**): Cursor hook install documented; fleet-complete enforcement
explicitly **not** claimed (multi-CLI seats rely on lock + docs)

---

### TIU-S04 — GitHub Actions CI

**Status:** Not started — **blocked on S01 baseline**

Deliver:

- `.github/workflows/check.yml`:
  - **Job 1 (ubuntu):** `bash scripts/check-fast.sh` only (cheap hygiene)
  - **Job 2 (macos):** full `bash scripts/check.sh` (install `xcodegen` on runner)
- Branch convention documented: CI proof on `tiu/*` or agent feature branches;
  agents do not push proof-farming commits to shared integration branches
- `docs/operations/TechStack.md` CI row updated

Gate: green CI on trial branch; S01 baseline compared to CI wall time

---

### TIU-S05 — Canonical runbook

**Status:** Not started

Deliver:

- `docs/operations/Test-Infra-Runbook.md` — verification modes, wrappers,
  deny-list, closeout vs CI finish lines, filter-selection template
- Promote binding rules; route `AGENTS.md` + Execution Playbook here

Gate (**product**): runbook is sole SSOT for test commands (grep audit)

Gate (**confidence**): `AGENTS.md` cites runbook; no duplicate Green Wall prose

---

### TIU-S06 — Test hygiene (split)

**Status:** Not started

#### TIU-S06a — Mechanical (hang class)

- Serialize server suites (6 files touch `LoopbackHealthServer` /
  `DirectModeCommandServer`): e.g. `@Suite(.serialized)` or CI-only group
- Relocate 4 `*PerformanceTests` to nightly / `-only-testing` group
- Audit tests missing `ALLNIGHTER_SUPPORT_DIR` isolation
- Dedup: `code_red_works_test.sh structural` redundant `swift test` after full
  suite — merge filters or CI-only

Gate (**product**): `scripts/swift-test.sh --filter DirectModeCommandServerTests`
completes cleanly; full wall no longer wedged-hangs on server accept loops

#### TIU-S06b — Analytical (deferred)

- Profile top slow tests from CI logs
- Record owners in baseline doc

Gate (**confidence**): slow-test table in baseline doc

---

### TIU-S07 — Closeout

**Status:** Not started

Deliver:

- Compare timings to S01 baseline
- Two-agent manual soak: concurrent full-suite attempts → one runs, one fails fast
  (observational; document result in baseline)
- Archive packet → `docs/archive/phases/Test_Infrastructure_Upgrade.md`

Gate:

- Filtered warm proof < 30s typical slice (founder machine)
- Full wall in CI, not required every agent turn
- Runbook canonical

---

## Sprint work orders

Each TIU slice gets a one-screen work order per `docs/phases/sprint/README.md`:

```text
docs/phases/sprint/test-infra/TIU-S00-kill-and-lock.md
docs/phases/sprint/test-infra/TIU-S01-check-fast.md
…
```

Work orders land with S00 implementation — the phase packet stays law; work
orders are the execute surface for 32K agents.

---

## Emergency triage

When tests "cannot complete" or the Mac feels wedged:

```bash
# 1. See what is running
ps aux | rg 'xctest|swift-test|check\.sh'

# 2. Kill stale Allnighter package test runners
pkill -f 'AllnighterCorePackageTests'   # until scripts/kill-stale-tests.sh lands

# 3. Do not start another full suite until the previous one is gone
```

If multiple agents share one clone: **one runner at a time**.

---

## Works tests (phase-level)

| Sprint | Proof command | Kind |
| --- | --- | --- |
| S00 | Live kill + dual-terminal lock (see S00 gates) | **product** |
| S00 | `bash scripts/kill-stale-tests.sh --dry-run` | confidence |
| S01 | `time bash scripts/check-fast.sh` + grep negative (no swift/xcodebuild) | product |
| S01 | `bash scripts/record-test-infra-baseline.sh` (one command) | confidence |
| S02 | Lock TTL/crash recovery + `check.sh` uses wrapper | product |
| S03 | `python3 scripts/test_agent_shell_guard.py` | product |
| S04 | Green GitHub Actions on `tiu/ci-smoke` trial branch | product |
| S05 | `rg 'swift test' AGENTS.md docs/operations/Execution-Playbook.md` → wrapper only | confidence |
| S06a | `scripts/swift-test.sh --filter DirectModeCommandServerTests` | product |
| S06b | Baseline slow-test table populated | confidence |
| S07 | Baseline diff vs S01 + two-agent soak note | product |

---

## Spec Review record (2026-07-31)

| Field | Value |
| --- | --- |
| Run | `17E96993-2852-4A6F-B217-B1B81AE15C1D` |
| Team | `code_spec_review_min` |
| Outcome | `failed` / `reconciledOrphan` — 2/3 workers complete, no Lead synthesis |
| Artifact | `alln artifact show 17E96993-2852-4A6F-B217-B1B81AE15C1D` |

**Incorporated findings:**

1. **Reorder:** lock in S00, not S02; baseline after `check-fast` exists (S01).
2. **Repo-root lock** — not `.build/.alln-test.lock`.
3. **Named wrapper** as SSOT for flags and lock — not raw `swift test` in docs.
4. **Guard v1 = deny-list**; mode machinery deferred; fleet limits documented.
5. **Product vs confidence** proofs labeled; live kill required; S05/S07 proofs added.
6. **S06 split** mechanical (serialize 6 server files, 4 perf files) vs analytical.
7. **CI gated** on uncontended baseline; split Linux hygiene + macOS wall.
8. **Block `--list-tests`** in guard; define stale threshold (30 min).
9. **Sprint work orders** required for unattended agent execution.
10. **Waive** “default wall never wedged-hangs” until S06a — explicit in Done when.

**Deferred / rejected from review:**

- Deferring shell guard entirely — lock alone is insufficient if agents bypass wrapper
- Splitting full wall coverage to cheapen CI — forbidden by decisions log

---

## Done when (phase)

- [ ] S00 kill + repo-root lock + minimal wrapper shipped
- [ ] S01 `check-fast.sh` + uncontended baseline recorded
- [ ] Agents default to `scripts/swift-test.sh --filter …`; full `check.sh` is closeout/CI only
- [ ] Deny-list guard + policy self-test green
- [ ] GitHub Actions runs full wall on feature branches
- [ ] S06a server suites serialized; hang class explicitly tested
- [ ] `docs/operations/Test-Infra-Runbook.md` canonical; packet archived

---

## Decisions log

| Question | Ruling |
| --- | --- |
| Lower the test bar to go faster? | **No** — workflow + enforcement |
| Delete old tests? | **No** — serialize, quarantine, CI-only |
| Replace `check.sh`? | **Split** — `check-fast.sh` + `check.sh` |
| Lock path? | **Repo root** `.alln-test.lock` (2026-07-31 spec review) |
| Stale kill threshold? | **30 minutes** default |
| Swift parallel testing? | **Off** for server suites until S06a proves safe |
| Shell guard modes v1? | **Deny-list only** |
| CI branch for agent proof? | **`tiu/*` or personal feature branches** — not proof-farming on shared integration branches |
| `alln serve` during tests? | `ALLNIGHTER_SUPPORT_DIR` required in tests |
| Wedged-hang product claim before S06a? | **Waived** — pile-up prevention is S00–S03; hang class is S06a |
| Agent layout-watcher subagents? | Out of scope |
