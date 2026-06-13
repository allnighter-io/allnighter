# Contributing

## Working Rules

- Read `AGENTS.md` before editing.
- Keep diffs scoped to the routed task.
- Do not rewrite unrelated user work.
- Prefer local patterns over imported architecture.
- Add abstractions only when they remove real duplication or clarify ownership.
- For high-risk behavior, write the proof plan before product code.

## Swift Conventions

- Shared models and protocol types belong in `Packages/CLILociCore/`.
- Mac-only process/PTY code stays in `Apps/CLILociMac/`.
- iOS UI and remote transport stay in `Apps/CLILociIOS/`.
- SwiftUI views render truth; they do not own durable session semantics.
- Prefer `async`/`await` and structured concurrency for WebSocket and PTY I/O.

## Proof Rules

- Run the narrowest useful proof for the touched surface.
- If no proof command exists yet, name the missing proof in closeout.
- Do not claim behavior is proven by screenshots or build success alone.
- For UI behavior, prove the user gesture when practical (XCUITest or manual
  Works Test script), not only a unit-tested helper.

## Git Hygiene

- Main should remain reviewable.
- Stage explicit paths only.
- Do not sweep unrelated dirty files into commits.
- Mention unrun proof and residual risk in closeout.
- Codex agents enqueue commits through `scripts/commit_handoff_queue.py`; Cursor
  processes the queue. See `Docs/operations/Execution-Playbook.md` § Codex
  commit handoff.
