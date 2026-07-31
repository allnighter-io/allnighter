# Test Infrastructure Upgrade

Status: **FINAL — ready to implement** · 2026-07-31 (rev 2)  
Sprints: **TIU-S00 → S03** (all core) · GitHub Actions CI deferred separately  
Authority: `AGENTS.md`, `docs/operations/Execution-Playbook.md`, `docs/operations/TechStack.md`  
Depends on: none — execution stop-gate, not product semantics

**Context:** single-dev, self-funded, but the "team" is multiple autonomous AI
agents (Claude, Codex, Cursor, Grok) running unsupervised on one machine. That
shape — not solo-human-coder — is what drove the rev-2 changes below. Kanso
was built on the same shape and reached the same conclusion independently.

Goal: **tests finish, do not pile up, and do not stop the day.**

Spec Review Min (`17E96993`, 2/3 workers) informed rev 1. Rev 2 is a
first-principles re-check against the actual incident report, not a new review
run.

---

## Rev 2 — what changed and why

Rev 1 correctly cut Kanso's heavyweight machinery (mode system, env-var
switching, audit logs, dedicated runbook, baseline-timing project, GitHub CI).
That stands. Two things were wrong:

1. **S03 (deny-list guard) was marked optional. It is now core (thin version
   only).** The incident wasn't just concurrent runs — it was an agent that
   *kept creating new watchers to wait, non-stop* until a human stopped it. A
   lock file makes a second attempt fail fast; it does nothing about an
   agent's response to that failure. Kanso hit this exact wall for the exact
   same reason (single founder + multiple coding agents) and concluded
   shell-level blocking was load-bearing, not decorative. What's still
   rejected: the three-mode policy engine, env-var mode switching, audit
   logging. What's promoted to core: one deny-list + one Cursor hook,
   ~2–3 hours, blocking exactly the two commands that caused the incident.

2. **Two cheap items were missing from S00:**
   - **Wrapper-enforced timeout.** S02 fixes today's known hang-prone suites.
     It does nothing for a hang nobody's found yet. A wall-clock timeout in
     the wrapper (kill after N minutes, regardless of cause) is a few lines
     and caps damage from any future hang, known or not. This is cheaper and
     more durable than suite-by-suite fixing, so it belongs in S00, not
     waiting on S02.
   - **Stale-lock auto-recovery.** If the wrapper is killed before it releases
     the lock, every future run is blocked by a dead lock file — the fix for
     "everything's stuck" quietly becomes a new way for everything to get
     stuck. A `kill -0 $PID` check before honoring a lock (auto-clear if the
     holder is gone) is one conditional.

Everything else from rev 1 is unchanged.

---

## Problem

Today agents treat `bash scripts/check.sh` as the default proof. That wall is:

1. full `swift test` (~2,700 cases)
2. another filtered `swift test` via `code_red_works_test.sh structural`
3. contracts check
4. `xcodegen` + full Mac `xcodebuild test`

Multiple agents (or one agent looping) start this at once against one `.build/`.
Observed 2026-07-31: four overlapping runners, 17–21 min of apparent hang, Mac
unusable for further proof, and one agent spawning repeated wait-watchers
instead of stopping. Stack sample showed `XCTWaiter` + hundreds of
`LoopbackHealthServer` / `DirectModeCommandServer` accept threads.

Cheap hygiene gates alone finish in **~2 seconds**. The failure is
**orchestration and agent behavior**, not missing test coverage.

---

## Goal (and non-goal)

```text
edit → one filtered proof (or none) → founder tries app
closeout → check.sh once, one runner
```

**In scope:** prevent concurrent runners; cap any single hang; recover when
wedged; block the two commands that caused the incident; make iteration proof
cheap; make `check.sh` the closeout path only.

**Out of scope (struck as bloat for a single-dev shop):**

- Multi-mode policy engine, env-var mode switching, audit logs
- Separate `Test-Infra-Runbook.md` and baseline-timing project
- GitHub Actions macOS CI (paid minutes; revisit when local loop is calm)
- Sprint work-order folder sprawl, slow-test profiling project
- Lowering the correctness bar or deleting tests to go green

---

## Rules (binding once S00 ships)

1. **One test run per clone.** Second attempt fails fast with a lock message.
2. **Iteration proof = filtered only:**
   `scripts/swift-test.sh --filter <TouchedTests>`
3. **`bash scripts/check.sh` = closeout only** (or founder-requested). Never
   mid-slice, never in a fix→test→fix loop.
4. **Do not run** `swift test --list-tests` as routine (~8+ min cold).
5. **A lock failure or timeout is a stop signal, not a retry signal.** Report
   back or work on something else — do not loop, poll, or spawn a wait watcher.
6. If the Mac is wedged: kill stale package runners, then continue — do not
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

### TIU-S00 — Lock + kill + wrapper (+ timeout, + stale-lock recovery)  *(~1 day)*

Stops recurrence and caps worst-case damage. This is the structural fix.

Deliver:

- `scripts/kill-stale-tests.sh`
  - Match only this package (`AllnighterCorePackageTests`,
    `swift-test` with `AllnighterCore`) — never `alln serve`
  - Stale = older than **30 minutes** (`--max-age-minutes`)
  - `--dry-run` lists; default kills
- Repo-root lock: **`.alln-test.lock`** (not under `.build/` — clean deletes it),
  containing the holder PID
- `scripts/swift-test.sh`:
  - Before acquiring: if the lock file's PID is dead, auto-clear the stale
    lock (`kill -0 $PID` check) instead of blocking forever
  - Acquire lock → run `swift test --disable-sandbox --package-path
    Packages/AllnighterCore "$@"` **wrapped in a wall-clock timeout**
    (default ~15 min for `--filter` runs, override env var for unfiltered/full
    runs invoked from `check.sh`) → release on exit/trap/timeout
  - Fail-fast message includes holder PID, started-at, and the rule-5 text:
    *"another run is in progress — do not retry or wait-loop; stop and report"*
  - Take one real timing measurement while building this (a filtered run and
    one full run) to set a sane default — not a separate baseline project
- Wire `check.sh` and `code_red_works_test.sh` structural path through the
  wrapper for every `swift test` call
- Update `AGENTS.md` + Execution Playbook § Green Wall: iteration = wrapper
  with `--filter`; closeout = `check.sh`; add Rule 5 (stop signal, not retry)

Works Test:

1. Hold lock in terminal A with a long `--filter` run; terminal B exits
   non-zero within 5s with a clear message.
2. Kill terminal A's wrapper process directly (simulate crash) — terminal B's
   next attempt succeeds instead of blocking on the dead lock.
3. A run exceeding the timeout is killed automatically and the lock is
   released (does not require the outer kill script).
4. `kill-stale-tests.sh --dry-run` lists only matching stale PIDs; live kill
   clears a known stale runner without touching `alln serve`.

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

The timeout (S00) caps damage; this fixes root cause for the suites we already
know about, so a normal uncontended closeout doesn't need the safety net.

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
stage without stalling on Core well under the S00 timeout.

---

### TIU-S03 — Minimal deny-list guard  *(~2–3 hours, core — not optional)*

Targets the behavioral half of the incident: an agent bypassing the wrapper or
retry-looping instead of stopping. This is the one piece Kanso's own
single-founder-plus-agents experience says is load-bearing, not decorative —
kept intentionally thin so it doesn't become the policy engine that was
correctly cut from rev 1.

Deliver:

- One deny-list (plain JSON or even a short shell case statement — no mode
  system, no env-var switching): block
  - bare `bash scripts/check.sh`
  - `swift test` without `--filter`
  - `swift test --list-tests`
  - `xcodebuild test` without `-only-testing:`
- One Cursor hook script that checks a shell command against the deny-list
  before execution and, if blocked, prints the Rule-5 stop message and refuses
  to run
- No install automation beyond a one-line note in `AGENTS.md`; no audit log,
  no mode env var, no bypass ceremony — if a real exception is needed, the
  founder runs it manually outside the hook

Works Test: each denied pattern is blocked with the stop message; each allowed
pattern (`scripts/swift-test.sh --filter X`, `scripts/check-fast.sh`) passes
through unchanged.

---

## Deferred separately (not part of core)

- **GitHub Actions CI.** Thin ubuntu `check-fast.sh` job would be cheap, but
  there's no local pain it solves right now — the loop is calm once S00–S03
  land. Revisit only if the founder wants remote proof independent of the
  local machine.
- **Cross-agent-host guard coverage.** The Cursor hook only covers
  Cursor-hosted sessions. Claude/Codex seats rely on Rule 5 + the lock/timeout
  as the actual safety net (host-agnostic); do not build a second hook system
  to cover them unless a second incident proves the lock/timeout insufficient.

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
- [ ] A dead lock holder is auto-recovered, not a permanent block
- [ ] Any single run is capped by a wall-clock timeout
- [ ] Stale runners clearable in one command
- [ ] Agents / Playbook default to filtered proof; `check.sh` is closeout-only
- [ ] `check-fast.sh` < 10s and has no compile/test suites
- [ ] One uncontended `check.sh` completes without wedging on server suites
- [ ] The two incident-causing commands (bare `check.sh`, unfiltered
      `swift test`) are blocked at the shell layer in Cursor sessions

Archive this packet to `docs/archive/phases/` when Done when is checked;
promote the Rules + Commands into Execution Playbook (no separate runbook).

---

## Decisions

| Question | Ruling |
| --- | --- |
| Shell guard / policy JSON? | **No** full engine — one deny-list + one hook (S03, core) |
| Dedicated runbook + baseline docs? | **No** — Playbook + AGENTS only; one timing sample taken inline during S00 |
| GitHub Actions full wall? | **Deferred**, separate from core — cost vs benefit weak right now |
| Delete tests to go faster? | **No** |
| Lock path? | Repo root `.alln-test.lock`, holder PID recorded, auto-recovered if holder is dead |
| Stale age? | 30 minutes (outer net); wrapper timeout (~15 min) is the primary cap |
| Correctness bar? | Unchanged — change *when* the wall runs |
| Is S03 optional? | **No** (rev 2) — thin deny-list only, not the full policy system |

---

## Impact & effort

| | Today | After S00–S03 |
| --- | --- | --- |
| Mid-slice proof | Often full `check.sh` / unfiltered suite; can wedge for 15–20+ min | Filtered wrapper, typically **under a few minutes warm** |
| Concurrent agents | Pile up on `.build/`, Mac stops | Second run **fails in seconds** with a clear stop message |
| Agent bypass / retry-loop | Possible (this is what happened) | Blocked at the shell layer before it starts |
| Any single hang (known or new) | Can run indefinitely | Capped by wrapper timeout |
| Crashed lock holder | Blocks all future runs until manual cleanup | Auto-recovered on next attempt |
| Wedged Mac recovery | Manual `ps` / guess | One kill script |
| Closeout | Same wall, often started on a dirty/contended machine | Same wall, **one runner**, unlikely to hang on server suites |
| Day-to-day feel | Full stops, sometimes requiring human intervention | Iteration keeps moving; wall is intentional and bounded |

**How much better:** The failure mode you actually hit — a wedged Mac plus an
agent that wouldn't stop — should no longer be able to happen unsupervised.
Any single hang is time-boxed even if the root cause isn't fixed yet, a
crashed lock can't brick future runs, and the two commands that caused the
incident are blocked before they execute in Cursor. Closeout still takes as
long as a clean full wall — that's intentional, not a regression.

**How long:** **~2 focused days** for S00–S03 end-to-end (~1 day for the
hardened lock/kill/timeout wrapper, ~2–3h check-fast, ~half day hang-class
serialization, ~2–3h deny-list guard). Up from the rev-1 estimate of 1–1.5
days because S03 moved from optional to core and S00 gained two small but
real deliverables.
