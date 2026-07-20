# MR-S02 — Clean-cut wrong and duplicate grammars

Status: **complete**
SSOT: `docs/archive/phases/Menu_Not_Router.md` §MR-S02 + one-run-primitive ownership

## Goal

Delete the intent router and every duplicate direct-run / selection grammar.
Route the product contract to `alln run` (+ `--detach` for async). Major contract cut.

## Slice packet

```text
Slice: MR-S02
Goal: One direct-run grammar; router and aliases gone; major contractVersion cut
Out of scope: selection-grade copy (S03), exact-id polish (S04), bootstrap rewrite (S05), cold-agent matrix (S06)
Truth owner: ContractRegistry + RetiredVocabulary + RunCLI
Lie-prone layer: aliases left as soft redirects; oracle-shaped replacements for readiness
Works Test: phase Works Test router-gone + one-run-grammar section
Done when: retired paths do not parse; AgentIntentRouter/AgentHello gone; contracts regenerated at major version
```

## Delete / replace

- `AgentIntentRouter.swift`, `AgentHello.swift`, all router tests/errors/help/recipes
- `team hello`, `route`, `resolve`, `--for`
- `team list` alias; selection duplicates `team show`, `team preflight`
- Direct-run aliases `alln team [prompt]`, `alln team start [prompt]`
- `commands --json` surface (replaced by `menu`; no alias)
- Preserve async as `alln run --detach`
- Add every retired path/token to `RetiredVocabulary`; regenerate; major version bump (e.g. 2.0.0)
- Preserve readiness via `menu`, `doctor`, `run --dry-run` — no oracle replacement

## Works Test (slice-focused)

```bash
B=Packages/AllnighterCore/.build/release/alln
$B team hello --for anything >/dev/null 2>&1; test $? -ne 0
$B route --for anything >/dev/null 2>&1; test $? -ne 0
$B resolve --for anything >/dev/null 2>&1; test $? -ne 0
$B commands --json >/dev/null 2>&1; test $? -ne 0
$B team list --json >/dev/null 2>&1; test $? -ne 0
$B team show --json >/dev/null 2>&1; test $? -ne 0
$B team preflight --team code_growth --json >/dev/null 2>&1; test $? -ne 0
test ! -e Packages/AllnighterCore/Sources/AllnighterCore/AgentIntentRouter.swift
test ! -e Packages/AllnighterCore/Sources/AllnighterCore/AgentHello.swift
$B run "probe" --team code_growth --dry-run --json
$B run "probe" --team code_growth --detach --dry-run --json
$B team "probe" --json; test $? -ne 0
$B team start "probe" --json; test $? -ne 0
$B menu --json >/dev/null
$B dev export-contracts --check
```

## SSOT

`docs/archive/phases/Menu_Not_Router.md` — MR-S02
