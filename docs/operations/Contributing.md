# Contributing

## Working Rules

- Read `AGENTS.md` before editing.
- Keep diffs scoped to the routed task.
- Do not rewrite unrelated user work.
- Prefer local patterns over imported architecture.
- Add abstractions only when they remove real duplication or clarify ownership.
- For high-risk behavior, write the proof plan before product code.

## Swift Conventions

- Shared models and engine types belong in `Packages/AllnighterCore/`.
- Mac-only app shell and UI stay in `Apps/AllnighterMac/`.
- iOS UI and remote transport stay in `Allnighter/` or `Apps/AllnighteriOS/`.
- SwiftUI views render truth; they do not own durable run semantics.
- Prefer `async`/`await` and structured concurrency for WebSocket and process I/O.

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
- All agents (including Codex) commit their own work directly with git; the
  commit-queue/handoff watcher is retired. See
  `docs/operations/Execution-Playbook.md` § Commits.
