# Execution Playbook

Pair this with exactly one target doc or explicit user request. Process lives
here; scope and product truth live in the target.

## Modes

| Mode | Trigger | Behavior |
| --- | --- | --- |
| Direct | Ordinary implementation request | Implement the smallest useful slice, then close out. |
| Packet | Ambiguous feature/sprint request | Produce a feature or task packet before code. |
| Orchestrated | User asks to orchestrate, run a chain, or use workers | Separate implementer, deslop, audit, and closeout roles when tooling exists. |

## Slice Packet

Use before non-trivial product work.

```text
Slice:
Goal:
Out of scope:
Truth owner:
Lie-prone layer:
Works Test:
Proof command:
Missing proof / waiver:
Done when:
```

## Execution Order

1. Read `AGENTS.md` and the routed docs.
2. Inspect current state before planning new structure.
3. Name the smallest owner-visible slice.
4. Name the truth owner and proof path.
5. Edit narrowly.
6. Run focused proof while iterating; closeout runs the green wall.
7. Run deslop for hunk-level cleanup.
8. Run Code Audit for non-trivial product or architecture changes.
9. Update durable docs/logs only when the lesson should survive the turn.
10. If changed work should be saved, `git add` the explicit paths and `git commit`
    directly (see § Commits).

## Green Wall

When Swift targets exist, follow Green Wall rules below (promoted from archived
`docs/archive/phases/Test_Infrastructure_Upgrade.md`). Binding rules:

1. Raw `swift test` / `xcodebuild test` do not work outside the wrapper (PATH shim).
2. One test run per clone — second attempt fails fast with a lock message.
3. Iteration proof = filtered only: `scripts/swift-test.sh --filter <TouchedTests>`
4. `bash scripts/check.sh` = closeout only — never mid-slice, never in a fix→test loop.
5. Do not run `swift test --list-tests` as routine (~8+ min cold).
6. Lock failure or timeout is a stop signal — do not retry, poll, or wait-loop.
7. Wedged Mac: `scripts/kill-stale-tests.sh`, then continue — do not stack full suites.
8. **A test may not reach a live vendor or the user's real state.** Promoted from
   2026-08-12 (`26a6e582`, `27a99e3f`); code SSOT `AllnighterSupportRoot`
   (`.xctest` support-root redirect) and `WorkerInvokerFactory`
   (`routeOpenCodeToServe`). Three separate seams were found in one day:
   a "stubbed" test sent real prompts to the live `opencode serve` (45–70s and
   real quota per run); the Mac suite wrote fixture drivers into the real
   `cli_setup.json`, so `alln menu` then reported CLIs the machine did not have;
   and three tests passed only because this Mac happens to run `alln serve`.
   Rules that follow:
   - Never infer "this is a test" from an injected double — production injects
     runners and command runners too. The opt-out must be explicit at the call
     site, or keyed to the XCTest host itself.
   - A test that depends on a live vendor, daemon, or account must SKIP with the
     reason (quoting the vendor where there is one), never fail the wall. An
     out-of-quota account is not a defect in this repo.
   - Suspect any proof whose runtime is dominated by something you did not stub.
   - When a seal like this lands, expect previously-green tests to turn red. That
     is discovery, not regression: they were passing on real state.

```text
scripts/install-test-guard.sh              # optional: direnv for interactive shells
scripts/swift-test.sh --filter LoopDispatch  # iteration proof (auto-activates PATH shim)
bash scripts/check-fast.sh                 # hygiene only (TIU-S01)
bash scripts/check.sh                        # closeout / founder-requested full wall (prints wall-clock)
scripts/kill-stale-tests.sh                # emergency
```

Agents do not run `install-test-guard.sh` manually — `check-fast.sh`, `swift-test.sh`,
and `check.sh` source `scripts/ensure-test-guard-path.sh` first, which prepends
`scripts/bin` to PATH for that shell.

Until targets exist, closeout names missing proof explicitly.

**Guard self-heals (2026-07-31).** `kill-stale-tests.sh` was locale-broken
from the day it shipped: it parsed `ps -o lstart=` with a hardcoded English
day-month strptime format, this machine's locale transposes them, the parse
silently failed, and the swallowed error made every runner's age look like
0 — so rule 7 above always reported "sent TERM to 0 stale runner(s)" even
against a confirmed real orphan (`AllnighterCorePackageTests.xctest`,
PPID=1, 2h17m elapsed, 0.0% CPU, no `.alln-test.lock` in sight). Fixed to a
locale-independent `ps -o etime=` parse under `LC_ALL=C`, with a failed
probe now treated as stale-eligible instead of silently becoming age=0.

`scripts/swift-test.sh` now self-heals on every invocation instead of
relying on a human to notice and run rule 7 by hand:
- **preflight sweep** — before acquiring the lock, it TERM/KILLs any live
  `AllnighterCorePackageTests` runner and re-scans the process table (never
  the lock file) before proceeding;
- **process-group reaping** — the timeout/trap paths used to kill `tee`
  (the last stage of a piped background job) instead of `swift`/`xctest`;
  the runner now starts under `set -m` in its own process group, and every
  exit path kills the whole group;
- **lock records the runner's pgid**, not just the wrapper's pid, so a
  dead wrapper no longer erases the only record of what it spawned;
  `recover_stale_lock` reaps an orphaned group before clearing the lock;
- **wedge detection in ~90s**, not the 900s wall-clock backstop — three
  consecutive flat samples of process-group CPU time and log size mean
  deadlock, and it kills and exits loud and non-zero immediately.

Proof: `scripts/works-test-test-guard.sh` — self-contained, seconds not
minutes, injects a fixture runner via `ALLNIGHTER_SWIFT_TEST_CMD_OVERRIDE`
(test-only) that ignores SIGTERM and blocks forever, and asserts SIGKILL
escalation, zero surviving processes, a cleared lock file, fast wedge exit,
and that `kill-stale-tests.sh` actually kills a stale runner.

## Codex permissions (one-time, per machine)

Managed permission profiles need **codex-cli `0.138.0+`**. Legacy sandbox settings
(`sandbox_mode`, `[sandbox_workspace_write]`, or CLI `--sandbox`) override
`default_permissions` and block scoped `.git` writes Codex needs for commit
handoff and hook installers.

**Install once** (merges `workspace-git` into `~/.codex/config.toml`):

```bash
bash scripts/install_codex_workspace_permissions.sh
```

Then **fully quit Codex** and **start a new thread** — existing threads keep
their launch-time sandbox. Verify in the new thread:

```bash
touch .git/codex-write-test && rm .git/codex-write-test && echo OK
```

Do not pass `--sandbox` to `codex exec` from drivers or scripts.

## Commits

The commit-queue/handoff watcher is **retired** (2026-06-18). There is no
`.wmd/commit-queue.jsonl`, no poll watcher, and no `--wait` handoff. Every agent
(including Codex, which now has direct workspace git permissions) commits its own
work directly:

```text
git add <explicit-path> <explicit-path>
git commit -m "<scope>: <what changed>"
```

Binding rules:

- Stage only the explicit paths you changed; never `git add -A`/`git add .` that
  could sweep in unrelated dirty or pre-existing staged files.
- Commit in small, regular increments as work lands — do not batch a whole sprint
  into one commit and do not leave finished work uncommitted.
- Never `git reset --hard`, force-push, or rewrite shared history on
  `feat/design-chain`. (The retired watcher's `reset --hard` loop is why this rule
  exists.)
- Do not push unless the task explicitly asks for it.
- The old control-plane scripts (`scripts/commit_handoff_queue.py`,
  `scripts/commit_queue_watcher.py`, `scripts/install_commit_queue_watcher.sh`,
  `scripts/commit-handoff-hooks/*`, `.cursor/hooks/*commit*`) are dormant and may
  be removed; `.cursor/hooks.json` no longer registers them.

### OpenCode mutating (OMH)

- Mutating OpenCode seats must `git commit` run-owned paths unless `--no-commit`
  was explicit. Help: `opencode_mutating_commit_contract`.
- **Works Test gate:** if DeepSeek V4 Pro (or any OpenCode mutator) answers
  “deferred” / “follow-up” / “TODO” for an in-slice Works Test, the **host
  completes that Works Test before the next slice** (CRS-S04 incident:
  mid-probe cancel deferred → host `8a0e7306`). Paste
  `docs/qa/opencode-mutating-commit/SLICE_TEMPLATE.md` into Pro prompts.
- **Slice bounds for OpenCode Pro mutating:** ≤3 production files + ≤1 test
  file **or** ≤1 behavioral theme; ≤3 named Works Tests; wall target ≤15m. If
  exceeded, `alln kill <id>`, split the remainder, and log the overrun in
  `docs/qa/opencode-mutating-commit/OPENCODE_BUG_LOG.md`.

## Closeout

Closeout is complete when all are true:

- The requested slice is done or clearly blocked.
- Green wall passes, or the blocker is explicit (including quarantine with valid
  expiry).
- Focused proof ran during the slice; the wall is the final proof scope.
- No unrelated cleanup is mixed into the diff.
- Deslop findings are fixed or explicitly not applicable.
- Code Audit is `CLEAN`, or the reason it did not run is stated.
- New durable lessons are logged in `DEBUGLOG`, maintainer logs, SSOT, or phase
  docs.
- Changed work that should be saved is committed directly with git (explicit
  paths), or the save waiver/blocker is explicit.
- **If the contract changed, the derived artifacts were regenerated** —
  `bash scripts/rebuild_cli.sh` then `alln dev export-contracts`, **before**
  committing. A contract change means: bumping `ContractRegistry.contractVersion`,
  or adding/removing/renaming any command, flag, error code, or wire field.

`docs/generated/alln/` is derived from the registry, so hand-editing it is
already banned — but the regeneration step is easy to forget and
`ContractExportTests` only catches it at test time. It caught three separate
slices on 2026-08-06 alone.

### Known intermittent: LoopCoordinatorTests wedge (2026-08-08)

`check.sh` has wedged twice in `LoopCoordinatorTests` around
`testPreflightStartDirectScanShapes`, killed by the guard at ~90s of no CPU
progress (exit 99). It is **not** a real failure and not worth a blind retry
loop:

- the suite passes 37/37 in isolation, in ~8s, repeatedly;
- it was clean on 3 of 5 full-wall runs the same day;
- the helper writes a fake pid rather than spawning anything, so nothing in the
  named test obviously blocks — and the wedge line is the last test *printed*,
  which is not necessarily the one hanging.

If you hit it: `scripts/kill-stale-tests.sh`, then re-run once. If it wedges
twice in a row at the same test, stop and diagnose — that is a different
signal from this flake.

### Rebuild the CLI at every packet closeout (founder 2026-08-08)

While alln is improving itself, **closeout is not done until the rebuilt binary
is on PATH**:

```text
bash scripts/rebuild_cli.sh
alln version          # confirm the new build answered
alln menu --json      # confirm contractVersion moved if the contract changed
```

This is required at **every** packet closeout during a self-improvement run, not
only when the contract changed. The PM agent is the heaviest alln user in the
loop: if the binary on PATH lags the fixes just landed, every following slice is
dogfooded against known-broken behavior and we rediscover bugs we already fixed.
Each rebuild should make the next packet's dogfood measurably quieter — that
decay is the evidence the improvements are real.

The version itself is authored in exactly one place — `ContractRegistry.contractVersion`.
Everything else, including the `team_run.json` fixture, is regenerated by the
command above (`87def7d8`). If you find yourself hand-editing a version string
anywhere else, that is a bug in the export, not a step you missed.

## Phase Archive

When a phase reaches `Status: Complete`, archive it as part of the same
closeout. `Docs/phases/` is for live phase work only.

**Archiving is a PRUNE, not a promotion dump.** `AGENTS.md` is loaded into every
agent session via `CLAUDE.md`, so every line added there is a permanent
per-session tax on every agent in the repo. A closeout that only adds is how a
router becomes a monster: by 2026-08-06 it had reached 259 lines against its own
stated 150 target, with 21% of its routing table pointing at already-archived
packets. `scripts/check-fast.sh` now enforces a byte budget — **raising that
budget is a founder decision, never a build fix.**

Before adding anything to `AGENTS.md` at closeout, apply this test:

| Candidate | Where it goes |
| --- | --- |
| A route to the packet being archived | **Nowhere.** Archived packets are not routed from `AGENTS.md`; the archive index owns them. |
| The packet's durable law | `AGENTS.md` § Project Laws — **only if** no code gate already enforces it. If code enforces it, the code is the SSOT and the law is a comment there. |
| Ops detail, commands, test procedure | This playbook. |
| "How did we get here" narrative | The archived packet. It is history, not routing. |

Every closeout that adds a line must name a line it removed, or state why none
was removable. Net-zero is the default; net-negative is better.

Archive workflow:

1. Confirm exit gates are checked or explicitly waived in the phase closeout.
2. Move durable truth to its owner before moving the phase. There is no
   `docs/product/SSOT.md`; owners are, in order of preference:
   - **code** — the type, registry or service that now enforces the rule. Record
     it in the archive index's *Successor owner* column so the code is findable
     from the phase.
   - **the living contract** — code `ContractRegistry` / CLI for
     contract-visible surface (commands, flags, JSON, exit codes). Historical
     packet only: `docs/archive/phases/CLI_Implementation_Contract.md`.
   - **the workflow docs** — `docs/workflows/SSOT_Feature_Workflow.md` for build
     laws the phase taught us, `SSOT_Founder_Input_Workflow.md` for intake rules.
   A law that exists only inside an archived phase doc is not durable truth; it
   is history.
3. Move the completed phase doc to `Docs/archive/phases/<same filename>`.
4. Remove the phase from the active table in `Docs/phases/README.md`.
5. Add it to `Docs/archive/phases/README.md` with status, archive date, proof,
   and successor owner.
6. Update routed references that still point at `Docs/phases/<archived file>`.
7. Run `rg "Docs/phases/<archived file>"` and confirm no stale live route
   remains.

## Human Stops

Stop and ask when the next action changes product scope, kills user sessions,
deletes worktrees, touches secrets, changes permission posture, affects
distribution/notarization, or requires choosing between two business meanings.

Not stops: ordinary refactors, audit findings, missing tests that can be added,
format failures, or proof failures with an obvious local fix.

## Progress Note Format

```text
Scope:
Changed:
Verified:
Left:
Next:
```
