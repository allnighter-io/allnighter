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
10. If changed work should be saved, enqueue Codex commit handoff and wait for
    `done`.

## Green Wall

When Swift targets exist:

```text
bash scripts/check.sh
```

Or individually:

```text
swift test --package-path Packages/AllnighterCore
xcodebuild test -scheme AllnighterMac   # Mac app (see TechStack.md)
xcodebuild test -scheme Allnighter      # iOS app (see TechStack.md)
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

## Codex Commit Handoff

When Codex finishes work that should be saved locally, it uses the queue at
`.wmd/commit-queue.jsonl` instead of staging or committing directly:

```text
python3 scripts/commit_handoff_queue.py request \
  --message "<commit message>" \
  --path <explicit-file> \
  --path <explicit-file> \
  --wait
```

Queue items record `id`, `repo`, expected `branch`, explicit `paths`,
`commit_message`, `status`, timestamps, `commit_sha`, and `failure_reason`.
Pending items are processed automatically while Cursor is open via hooks
installed by `bash scripts/install_commit_queue_watcher.sh` (which also runs the
Codex permissions installer above if present): `sessionStart` starts a repo-local
poll watcher on `.wmd/commit-queue.jsonl` (2s interval); `stop` drains once
immediately. Run the installer once per clone; restart Cursor after install.
Manual fallback: `python3 scripts/commit_handoff_queue.py process-next`.

To prove an in-progress Codex slice with the same unrelated-dirty-work
isolation but without creating a commit:

```text
python3 scripts/commit_handoff_queue.py check-request \
  --path <explicit-file> \
  --wait
```

Binding rules:

- Cursor stages only listed paths, commits once, and never pushes.
- Unrelated dirty files are normal and must not block handoff.
- Pre-existing staged changes fail the handoff because `git commit` would sweep
  them in.
- Commit-handoff control-plane files (`scripts/commit_handoff_queue.py`,
  `scripts/commit_queue_watcher.py`, `scripts/install_commit_queue_watcher.sh`,
  `.cursor/hooks*`, `scripts/commit-handoff-hooks/*`) are blocked unless the
  human explicitly requested queue maintenance and the request uses
  `--allow-control-plane`.
- Codex polls the queue item by `id` until `done`, `failed`, or timeout.

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
- Changed work that should be saved has a Codex commit handoff item marked
  `done`, or the save waiver/blocker is explicit.

## Phase Archive

When a phase reaches `Status: Complete`, archive it as part of the same
closeout. `Docs/phases/` is for live phase work only.

Archive workflow:

1. Confirm exit gates are checked or explicitly waived in the phase closeout.
2. Copy durable product truth into `Docs/product/SSOT.md` or the owning product
   contract before moving the phase.
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
