# HY-S05 — Loop comment scrub (pair relay → alln loop)

Status: ready
Owner: hygiene / comment truth
Updated: 2026-08-03

## Goal

File-level comments that teach retired `pair relay` CLI should say `alln loop`.
**Comments and docstrings only — zero symbol renames.**

## Copy-paste prompt

```text
Implement HY-S05 only. Read this file.

Touch ONLY these files — change COMMENTS and docstrings only (// and /// lines).
Do NOT rename types, functions, variables, or string literals in code.

Allowlist:
- Packages/AllnighterCore/Sources/AllnighterCore/LoopJSON.swift
- Packages/AllnighterCore/Sources/AllnighterCore/LoopState.swift
- Packages/AllnighterCore/Sources/AllnighterCLI/LoopEngineCLI.swift (comments only)

In comments, replace teaching prose:
- `pair relay` / `alln pair relay` → `alln loop` (with appropriate subcommand)
- `pair relay-status` → `loop status`
- `pair relay-resume` → `loop resume`
Keep mentions of "retired pair relay" where explaining migration if needed.

Do NOT touch: LoopCoordinator.swift, tests, GUI, ContractRegistry.

Proof:
scripts/swift-test.sh --filter RetiredVocabulary

Commit:
git add the three files above only
git commit -m "docs(swift): loop comment scrub — pair relay → alln loop"
```

## Touch only

Three files listed above — comment lines only.

## Works Test

```text
scripts/swift-test.sh --filter RetiredVocabulary
```

## Done when

- [ ] No symbol renames
- [ ] Comment prose uses loop vocabulary
- [ ] RetiredVocabulary tests green
- [ ] One commit, three files max
