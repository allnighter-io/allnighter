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
    phases/                       # ephemeral build packets only (never SSOT)
    strategy/
    workflows/
    operations/
    archive/
    design-system/
  Packages/
    AllnighterCore/               # shared models, engine, CLI tools
  Apps/
    AllnighterMac/                # macOS menu-bar + team UI
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
- `docs/mvp/README.md`: built Team MVP execution truth.
- `docs/phases/README.md`: ephemeral post-MVP phase router (**not** SSOT).
- `docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md`: agent control loop strategy.
- `docs/phases/*.md`: open build packets only; on closeout **promote** keepable
  law into ops/workflows/design-system/gui/strategy and/or code, then archive.
- `docs/archive/`: closed phase records (history). Successor SSOT is named per
  packet — code and/or standing docs outside phases.
- `docs/workflows/SSOT_*.md`: founder intake and feature packet shape (standing).
- `docs/operations/`: standing how-we-build / how-we-operate docs (can be SSOT).
- `docs/design-system/`: standing visual/brand law (can be SSOT).
- `docs/operations/Execution-Playbook.md`: slice process and closeout checklist.
- `docs/operations/GLM_Worker_Best_Practices.md`: GLM seating, serial hardening pass, F1–F5.
- `docs/operations/code-maintainer/SKILL.md`: rotating repo health loop.
- `scripts/commit_handoff_queue.py`: retired commit-handoff queue (dormant; agents
  now commit directly — see `docs/operations/Execution-Playbook.md` § Commits).
- `.wmd/commit-queue.jsonl`: stale local queue state from the retired watcher.

## Truth Placement

| Layer | Location |
| --- | --- |
| Run/event models | `Packages/AllnighterCore/Sources/` + `docs/mvp/00_MVP_Architecture.md` |
| Team/worker orchestration | `Packages/AllnighterCore/Sources/AllnighterEngine/` |
| Mac app shell + UI | `Apps/AllnighterMac/` |
| iOS remote UI state | `docs/phases/ios/` + `Allnighter/` or `Apps/AllnighteriOS/` (presenters only; state from Mac) |
| Product semantics | Code for runtime; standing `docs/operations/` / `workflows/` / `design-system/` / `gui/` for process & invariants; `docs/phases/` only while building (then promote + archive) |
| Team run artifact HTML | Code SSOT: `ArtifactProjector` / `ArtifactWriter` / `ArtifactCLI`; founder locks also belong in standing design/ops docs when they outlive the phase |
