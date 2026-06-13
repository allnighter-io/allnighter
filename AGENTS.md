# CLI Loci - Agent Workflow

Applies to agents, humans, and CI. This file is the router. Put durable policy
in routed docs; add links here, not long prose.

## Default Loop

```text
Read route -> name slice + truth owner + proof -> edit narrowly -> focused proof
-> deslop -> code audit -> log durable lessons -> commit handoff when saving
```

No silent WIP: if work stops mid-slice, leave a short status note naming scope,
files touched, proof state, and next action.

## First Routing

| Task type | Read first |
| --- | --- |
| Product scope, vision, MVP boundary, architecture | `CLILOCI.md` + `Docs/WORKING_RULES.md` + `Docs/FOLDER_MAP.md` |
| Strategy, positioning, mentor feedback | `Docs/strategy/CLI-Loci-Vision.md` |
| New feature, product idea, rough spec | `Docs/workflows/SSOT_Founder_Input_Workflow.md` + `Docs/workflows/SSOT_Feature_Workflow.md` |
| Shared models, parsers, WebSocket protocol | `Docs/product/WebSocket_Protocol_Contract.md` + `Docs/product/Session_Model_Contract.md` + `Packages/CLILociCore/` |
| Mac PTY/session orchestration, background agents | `Docs/product/Session_Orchestration_Contract.md` + `Docs/phases/02_Mac_PTY_And_Session_Spine.md` |
| Agent bridge layer (Claude Code, Grok, Aider, etc.) | `Docs/product/Agent_Bridge_Contract.md` |
| Mac app UI, menu bar, dashboard | `Apps/CLILociMac/` + `Docs/phases/` active Mac phase |
| iOS companion, Live Activities, remote control | `Apps/CLILociIOS/` + `Docs/phases/` active iOS phase |
| Tailscale pairing, device auth, local networking | `Docs/product/Pairing_And_Auth_Contract.md` |
| Diff parsing, approval cards, output events | `Docs/product/Diff_And_Approval_Contract.md` |
| Keychain, BYOK, API key storage | `Docs/product/Secrets_And_BYOK_Contract.md` |
| Sprint or phase execution | `Docs/phases/README.md` + `Docs/operations/Execution-Playbook.md` |
| Completed phase archive, stale phase docs | `Docs/operations/Execution-Playbook.md` § Phase Archive + `Docs/phases/README.md` + `Docs/archive/phases/README.md` |
| Bug report or broken workflow | `Docs/operations/Debugger.md` |
| Code cleanup, maintainability, file hygiene | `Docs/operations/code-maintainer/SKILL.md` |
| Pre-closeout architecture review | `Docs/operations/Code_Audit.md` |
| Hunk-level cleanup after product work | `Docs/operations/Deslop.md` |
| Product vocabulary and durable truths | `Docs/product/SSOT.md` |
| Stack, commands, Xcode setup | `Docs/operations/TechStack.md` |
| Repo conventions | `Docs/operations/Contributing.md` |
| Codex commit handoff queue or Cursor git automation | `Docs/operations/Execution-Playbook.md` § Codex commit handoff |

## Codex Commit Handoff

Hookless agents (Codex) must not `git add` or `git commit` directly at slice
close. When changed work should be saved, closeout is not complete until a
handoff item is `done` or the save is explicitly waived. Enqueue explicit paths
instead:

```text
python3 scripts/commit_handoff_queue.py request \
  --message "<commit message>" \
  --path <explicit-file> \
  --wait
```

Cursor drains `.wmd/commit-queue.jsonl` via hooks installed by
`bash scripts/install_commit_queue_watcher.sh`. Cursor stages only listed
paths, commits once, and never pushes. See
`Docs/operations/Execution-Playbook.md` § Codex commit handoff.

## Project Laws

- Founder/user input is intent, not final authority.
- SwiftUI may render truth; it must not invent durable product truth.
- Prompt prose may request work; it must not be the only owner of semantics.
- Generated parser output is derived. Change the source contract, then regenerate.
- Every feature slice needs one owner-visible Works Test or an explicit proof
  waiver.
- Every non-trivial bug fix names the truth owner, lie-prone layer, and missing
  proof before editing.
- Maintenance preserves behavior unless the task is explicitly a bug fix.
- Do not mix broad cleanup into a feature or bug fix.
- Prefer deterministic checks over recurring agent judgment.
- Mac app is unsandboxed by design; still minimize privilege surface and document
  every permission request.
- iOS companion connects only to the user's own Mac over Tailscale/local network
  by default. No mandatory third-party coordination cloud.
- Agent bridge configs describe how to spawn CLI agents; they must not become
  hidden runtime truth for session state.

## High-Risk Stops

Ask before proceeding when the change could affect:

- privacy or session data leaving the user's machines;
- credentials, Keychain items, or API keys;
- Full Disk Access or other macOS permission posture;
- destructive session kill, worktree deletion, or git operations;
- App Store / notarization / distribution identity;
- billing or entitlement behavior;
- production deploy or TestFlight release.

## Proof Wall (when code exists)

Closeout runs the green wall:

```text
swift test                    # shared package + unit tests
xcodebuild test -scheme ...   # app targets (see TechStack.md)
```

Until Xcode targets exist, name the missing proof in closeout. Do not claim
behavior is proven without a Works Test or explicit waiver.
