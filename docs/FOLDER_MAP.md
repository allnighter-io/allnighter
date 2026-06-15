# Folder Map

## Current

```txt
Allnighter/
  README.md
  ALLNIGHTER.md
  AGENTS.md
  .gitignore
  docs/
    FOLDER_MAP.md
    WORKING_RULES.md
    mvp/                          # active MVP execution truth
    phases/                       # full build phases + ios/ remote spine
    strategy/
    workflows/
    operations/
    archive/
    design-system/
  Packages/
    AllnighterCore/               # shared models, engine, CLI tools
  Apps/
    AllnighterMac/                # macOS menu-bar + council UI
  Allnighter/                     # transitional iOS Xcode scaffold (replace with Apps/AllnighteriOS/)
  scripts/
    commit_handoff_queue.py
    commit_queue_watcher.py
    install_commit_queue_watcher.sh
  .cursor/hooks/
  .wmd/                           # local workflow artifacts (gitignored)
```

## File Roles

- `AGENTS.md`: agent/human/CI router and project laws.
- `ALLNIGHTER.md`: product spec index and platform summary.
- `README.md`: human overview and doc index.
- `docs/mvp/README.md`: active Council MVP execution truth.
- `docs/phases/README.md`: full product phases and priority stack.
- `docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md`: agent control loop strategy.
- `docs/phases/*.md`: live execution docs with ordered slices and exit gates.
- `docs/archive/`: superseded docs; history only after closeout.
- `docs/workflows/SSOT_*.md`: founder intake and feature packet shape.
- `docs/operations/Execution-Playbook.md`: slice process and closeout checklist.
- `docs/operations/code-maintainer/SKILL.md`: rotating repo health loop.
- `scripts/commit_handoff_queue.py`: Codex → Cursor commit handoff queue.
- `.wmd/commit-queue.jsonl`: local commit queue state.

## Truth Placement

| Layer | Location |
| --- | --- |
| Run/event models | `Packages/AllnighterCore/Sources/` + `docs/mvp/00_MVP_Architecture.md` |
| Council/worker orchestration | `Packages/AllnighterCore/Sources/AllnighterEngine/` |
| Mac app shell + UI | `Apps/AllnighterMac/` |
| iOS remote UI state | `docs/phases/ios/` + `Allnighter/` or `Apps/AllnighteriOS/` (presenters only; state from Mac) |
| Product semantics | `docs/mvp/` and `docs/phases/` before code diverges |
