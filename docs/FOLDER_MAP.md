# Folder Map

## Current

```txt
Allnighter/
  README.md
  ALLNIGHTER.md                 # product spec index (links law; does not restate it)
  AGENTS.md                     # agent/human/CI router (byte-budgeted)
  CLAUDE.md                     # pointer → AGENTS.md
  MEMORY.md
  .gitignore
  config/                       # architecture-policy and related gates
  Packages/
    AllnighterCore/             # shared models, engine, CLI (alln)
    AllnighterMarkdown/
  Apps/
    AllnighterMac/              # macOS Dock app + team UI
    AllnighteriOS/              # parked iOS companion
  scripts/                      # check.sh, rebuild_cli.sh, swift-test.sh, …
  docs/
    FOLDER_MAP.md
    WORKING_RULES.md
    mvp/                        # built MVP foundation
    phases/                     # ephemeral build packets only (never SSOT)
    archive/                    # closed packets; successor SSOT named per entry
    strategy/
    workflows/
    operations/                 # standing how-we-build (can be SSOT)
    design-system/              # standing visual/brand law
    gui/                        # GUI engineering governance + surface briefs
    marketing/
    legal/
    qa/                         # dogfood / bakeoff notes
  tools/
  infra/                        # get-faucet (install) + pay (Stripe entitlement)
  supabase/
  dist/
```

Sibling (not in this tree): `../AgentOS` — required by
`Packages/AllnighterCore/Package.swift`. `scripts/rebuild_cli.sh` fails fast
if it is missing.

## File Roles

- `AGENTS.md`: agent/human/CI router (byte-budgeted). Full project laws:
  `docs/operations/Project_Laws.md`.
- `ALLNIGHTER.md`: product spec index and platform summary (defers to AGENTS /
  WORKING_RULES on credentials, shell, and iOS transport).
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
- `docs/gui/`: GUI workflow and surface briefs (how to build UI — not visual SSOT).
- `docs/operations/Execution-Playbook.md`: slice process and closeout checklist.
- `docs/operations/Public_Release.md`: ship CLI + Mac DMG to `get.allnighter.io`.
- `docs/operations/Project_Laws.md`: standing product/engineering laws.
- `docs/operations/TechStack.md`: stack + **wrapper** commands (never raw test runners).
- `scripts/rebuild_cli.sh`: rebuild/install `alln`; AgentOS sibling gate.
- `scripts/swift-test.sh` / `scripts/check.sh`: Green Wall wrappers.

## Truth Placement

| Layer | Location |
| --- | --- |
| Run/event models | `Packages/AllnighterCore/Sources/` + `docs/mvp/00_MVP_Architecture.md` |
| Team/worker orchestration | `Packages/AllnighterCore/Sources/AllnighterEngine/` |
| Mac app shell + UI | `Apps/AllnighterMac/` |
| iOS companion (parked) | `Apps/AllnighteriOS/` + `docs/phases/ios/` |
| Product semantics | Code for runtime; standing `docs/operations/` / `workflows/` / `design-system/` / `gui/` for process & invariants; `docs/phases/` only while building (then promote + archive) |
| Team run artifact HTML | Code SSOT: `ArtifactProjector` / `ArtifactWriter` / `ArtifactCLI` |
| AI Readiness team | Code SSOT: `BuiltInTeams.code_ai_readiness`, `AIReadinessReport`, archive `AI_Readiness.md` |
