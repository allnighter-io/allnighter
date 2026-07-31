# Test Infrastructure Upgrade

Status: **FINAL — ready to implement** · 2026-07-31  
Sprints: **TIU-S00 → S02** (core) · **S03** optional stretch  
Authority: `AGENTS.md`, `docs/operations/Execution-Playbook.md`, `docs/operations/TechStack.md`  
Depends on: none — execution stop-gate, not product semantics

**Context:** single-dev, self-funded. Goal is not a Kanso-scale test platform.
Goal: **tests finish, do not pile up, and do not stop the day.**

Spec Review Min (`17E96993`, 2/3 workers) informed the cut. Lead did not
synthesize; useful findings kept, overbuilt ones struck.

---

## Problem

Today agents treat `bash scripts/check.sh` as the default proof. That wall is:

1. full `swift test` (~2,700 cases)
2. another filtered `swift test` via `code_red_works_test.sh structural`
3. contracts check
4. `xcodegen` + full Mac `xcodebuild test`

Multiple agents (or one agent looping) start this at once against one `.build/`.
Observed 2026-07-31: four overlapping runners, 17–21 min of apparent hang,
Mac unusable for further proof. Stack sample showed `XCTWaiter` + hundreds of
`LoopbackHealthServer` / `DirectModeCommandServer` accept threads.

Cheap hygiene gates alone finish in **~2 seconds**. The failure is
**orchestration**, not missing test coverage.

---

## Goal (and non-goal)

```text
edit → one filtered proof (or none) → founder tries app
closeout → check.sh once, one runner
```

**In scope:** prevent concurrent runners; recover when wedged; make iteration
proof cheap; make `check.sh` the closeout path only.

**Out of scope (struck as bloat for a single-dev shop):**

- Agent shell-guard / policy JSON / Cursor hook installer (teach + lock instead)
- Separate `Test-Infra-Runbook.md` and baseline timing project
- GitHub Actions macOS CI (paid minutes; revisit when local loop is calm)
- Three-mode verify systems, sprint work-order folder sprawl, slow-test profiling
- Lowering the correctness bar or deleting tests to go green

---

## Rules (binding once S00 ships)

1. **One test run per clone.** Second attempt fails fast with a lock message.
2. **Iteration proof = filtered only:**
   `scripts/swift-test.sh --filter <TouchedTests>`
3. **`bash scripts/check.sh` = closeout only** (or founder-requested). Never
   mid-slice, never in a fix→test→fix loop.
4. **Do not run** `swift test --list-tests` as routine (~8+ min cold).
5. If the Mac is wedged: kill stale package runners, then continue — do not
   start another full suite on top.

---

## Commands

```text
# Iteration (default)
scripts/swift-test.sh --filter LoopDispatch   # after S00; until then:
swift test --disable-sandbox --package-path Packages/AllnighterCore --filter LoopDispatch

# Hygiene only (~2s) — after S01
bash scripts/check-fast.sh

# Closeout / founder-requested full wall — one runner
bash scripts/check.sh

# Emergency (until kill script lands)
pkill -f 'AllnighterCorePackageTests'
```

Filter = touched test **class** name (e.g. `LoopDispatch` → `LoopDispatchTests`).

---

## Sprints

### TIU-S00 — Lock + kill + wrapper  *(~half day)*

Stops recurrence. This is the structural fix.

Deliver:

- `scripts/kill-stale-tests.sh`
  - Match only this package (`AllnighterCorePackageTests`,
    `swift-test` with `AllnighterCore`)
  - Stale = older than **30 minutes** (`--max-age-minutes`)
  - `--dry-run` lists; default kills
- Repo-root lock: **`.alln-test.lock`** (not under `.build/` — clean deletes it)
- `scripts/swift-test.sh`: acquire lock →
  `swift test --disable-sandbox --package-path Packages/AllnighterCore "$@"` →
  release on exit/trap. Fail fast if lock held (print holder PID + remediation).
- Wire `check.sh` and `code_red_works_test.sh` structural path through the
  wrapper for every `swift test` call.
- Update `AGENTS.md` + Execution Playbook § Green Wall: iteration = wrapper with
  `--filter`; closeout = `check.sh`.

Works Test:

1. Hold lock in terminal A with a long `--filter` run; terminal B exits non-zero
   within 5s with a clear message.
2. `kill-stale-tests.sh --dry-run` lists only matching stale PIDs; live kill
   clears a known stale runner.

---

### TIU-S01 — `check-fast.sh`  *(~2–3 hours)*

Separates the 2s path from the hour-scale wall.

Deliver:

- `scripts/check-fast.sh` — extract cheap gates already inline in `check.sh`
  (architecture policy + self-test, TCC asserts, gui proof, swiftui state,
  ThreadStore allowlist, spawn policy, ASF-S08 deny-list). **Must not** call
  `swift test`, `xcodebuild`, or `code_red_works_test.sh`.
- `check.sh` runs `check-fast.sh` first, then existing heavy steps unchanged.

Works Test: `time bash scripts/check-fast.sh` < 10s; `rg 'swift test|xcodebuild'`
on `check-fast.sh` is empty.

---

### TIU-S02 — Stop the hang class  *(~half day)*

Lock prevents pile-ups; this makes a **single** full wall finish instead of
wedging on accept-loop suites.

Deliver (mechanical only):

- Serialize the ~6 test files that use `LoopbackHealthServer` /
  `DirectModeCommandServer` (Swift Testing `.serialized` or XCTest equivalent —
  pick the smallest change that runs them one-at-a-time).
- Drop or fold the **second** `swift test` pass inside
  `code_red_works_test.sh structural` when `check.sh` already ran the full
  suite (structural filters run as part of the main suite, or structural is
  CI/manual only — pick one; do not run full + filtered back-to-back every
  closeout).

Works Test: `scripts/swift-test.sh --filter DirectModeCommandServerTests`
completes cleanly; one uncontended `bash scripts/check.sh` reaches the Mac
stage without multi-hour stall on Core.

---

### TIU-S03 — Optional stretch *(defer)*

Only if S00–S02 are calm and the founder still wants more:

- Thin GitHub Actions: ubuntu `check-fast.sh` only (cheap). Full macOS wall
  stays local until runner cost is acceptable.
- Cursor deny-list hook (block bare `check.sh` / unfiltered `swift test`) —
  nice; not required if docs + lock are followed.

Do **not** start S03 before S00–S02 are done.

---

## Emergency triage

```bash
ps aux | rg 'xctest|swift-test|check\.sh'
bash scripts/kill-stale-tests.sh          # after S00; else: pkill -f AllnighterCorePackageTests
# Do not start another full suite until the previous one is gone
```

---

## Done when

- [ ] Second concurrent `scripts/swift-test.sh` fails fast (lock)
- [ ] Stale runners clearable in one command
- [ ] Agents / Playbook default to filtered proof; `check.sh` is closeout-only
- [ ] `check-fast.sh` < 10s and has no compile/test suites
- [ ] One uncontended `check.sh` completes without wedging on server suites

Archive this packet to `docs/archive/phases/` when Done when is checked; promote
the Rules + Commands into Execution Playbook (no separate runbook).

---

## Decisions

| Question | Ruling |
| --- | --- |
| Shell guard / policy JSON? | **No** for core — teach + lock |
| Dedicated runbook + baseline docs? | **No** — Playbook + AGENTS only |
| GitHub Actions full wall? | **Defer** (S03); cost vs benefit weak for single-dev now |
| Delete tests to go faster? | **No** |
| Lock path? | Repo root `.alln-test.lock` |
| Stale age? | 30 minutes |
| Correctness bar? | Unchanged — change *when* the wall runs |

---

## Impact & effort

| | Today | After S00–S02 |
| --- | --- | --- |
| Mid-slice proof | Often full `check.sh` / unfiltered suite; can wedge for 15–20+ min | Filtered wrapper, typically **under a few minutes warm** |
| Concurrent agents | Pile up on `.build/`, Mac stops | Second run **fails in seconds** with a clear message |
| Wedged Mac recovery | Manual `ps` / guess | One kill script |
| Closeout | Same wall, but often started on a dirty/contended machine | Same wall, **one runner**, less likely to hang on server suites |
| Day-to-day feel | Full stops | Iteration keeps moving; wall is intentional |

**How much better:** The daily failure mode (progress dead because tests are
stuck or stacked) should go away. Closeout still takes as long as a clean full
wall — that is intentional. The win is **not waiting on the wall during every
edit**, and **not losing the machine to pile-ups**.

**How long:** **~1–1.5 focused days** for S00–S02 end-to-end (roughly half day
lock/kill/docs, 2–3h check-fast, half day hang-class). S03 only if still
needed after that.
