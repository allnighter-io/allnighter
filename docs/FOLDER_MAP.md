# Folder Map

## Current (bootstrap)

```txt
CLILoci/
  README.md
  CLILOCI.md
  AGENTS.md
  .gitignore
  Docs/
    FOLDER_MAP.md
    WORKING_RULES.md
    strategy/
      CLI-Loci-Vision.md
    workflows/
      SSOT_Founder_Input_Workflow.md
      SSOT_Feature_Workflow.md
    operations/
      Execution-Playbook.md
      Contributing.md
      Deslop.md
      Code_Audit.md
      Debugger.md
      TechStack.md
      code-maintainer/
      debugger/
    phases/
    archive/phases/
    product/
  scripts/
    commit_handoff_queue.py
    commit_queue_watcher.py
    install_commit_queue_watcher.sh
  .cursor/hooks/
  .wmd/                         # local workflow artifacts (gitignored)
```

## Planned (Phase 01+)

```txt
CLILoci/
  Packages/
    CLILociCore/                # shared models, parsers, protocol
  Apps/
    CLILociMac/                 # macOS menu-bar + dashboard
    CLILociIOS/                 # iOS companion
  CLILoci.xcworkspace           # Xcode workspace (or SPM-only initially)
  scripts/
    check.sh                    # green wall wrapper
```

## File Roles

- `AGENTS.md`: agent/human/CI router and project laws.
- `CLILOCI.md`: product spec index and platform summary.
- `README.md`: human overview and doc index.
- `Docs/strategy/CLI-Loci-Vision.md`: mentor-ready vision and architecture draft.
- `Docs/product/SSOT.md`: durable product facts table and open decisions.
- `Docs/product/*_Contract.md`: domain truth owners (protocol, sessions, agents, etc.).
- `Docs/phases/*.md`: live execution docs with ordered slices and exit gates.
- `Docs/archive/phases/`: completed phases; history only after closeout.
- `Docs/workflows/SSOT_*.md`: founder intake and feature packet shape.
- `Docs/operations/Execution-Playbook.md`: slice process and closeout checklist.
- `Docs/operations/code-maintainer/SKILL.md`: rotating repo health loop.
- `scripts/commit_handoff_queue.py`: Codex → Cursor commit handoff queue.
- `.wmd/commit-queue.jsonl`: local commit queue state.

## Truth Placement

| Layer | Location |
| --- | --- |
| Session/event/diff models | `Packages/CLILociCore/Sources/` |
| WebSocket message types | `Packages/CLILociCore/` + `WebSocket_Protocol_Contract.md` |
| PTY/process orchestration | `Apps/CLILociMac/` + `Session_Orchestration_Contract.md` |
| Agent spawn configs | `Agent_Bridge_Contract.md` + bridge modules |
| macOS permissions/entitlements | `Apps/CLILociMac/` Info.plist + contracts |
| iOS remote UI state | `Apps/CLILociIOS/` (presenters only; state from Mac) |
| Product semantics | `Docs/product/*_Contract.md` before code diverges |
