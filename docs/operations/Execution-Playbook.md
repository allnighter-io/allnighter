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

```text
scripts/install-test-guard.sh              # one-time per clone
scripts/swift-test.sh --filter LoopDispatch  # iteration proof
bash scripts/check-fast.sh                 # hygiene only (TIU-S01)
bash scripts/check.sh                        # closeout / founder-requested full wall
scripts/kill-stale-tests.sh                # emergency
```

Until targets exist, closeout names missing proof explicitly.

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

## Phase Archive

When a phase reaches `Status: Complete`, archive it as part of the same
closeout. `Docs/phases/` is for live phase work only.

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
