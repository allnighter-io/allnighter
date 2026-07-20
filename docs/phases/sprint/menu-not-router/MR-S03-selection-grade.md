# MR-S03 — Make every row selection-grade

Status: **complete**
SSOT: `docs/phases/Menu_Not_Router.md` §MR-S03

## Goal

Author bounded `useWhen` / `dontUseWhen` for every team, model, recipe, and
fast-path action. Wire structured effects and direct validation/run templates.
Gate declared template variables, target-bound ids, valid command refs, and
cross-verb anti-examples. Derived generic prose does not satisfy the gate.

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter MenuSelectionGrade
B=Packages/AllnighterCore/.build/release/alln
$B menu --json | /usr/bin/python3 scripts/verify_menu_contract.py /dev/stdin \
  --max-built-in-bytes 32768 --require-complete --require-unique-refs --require-selection-grade
```

## SSOT

`docs/phases/Menu_Not_Router.md` — MR-S03
