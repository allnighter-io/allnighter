# HY-S04 — Contract retired handoff summary (no step --no-wait)

Status: ready
Owner: hygiene / contract truth
Updated: 2026-08-03

## Goal

Retired `pair pilot handoff` command summary must not teach `--no-wait` on
`loop step`. Match HY-S03 help truth.

## Copy-paste prompt

```text
Implement HY-S04 only. Read this file.

Touch:
- Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift
  — ONLY the `pair pilot handoff` CommandSpec summary string (~line 777).

Change summary from teaching "Long jobs: prefer --no-wait" to:
loop step blocks by default; after step use `loop wait <loop-id>` or
`loop status <loop-id> --wait-for parked`. `--no-wait` is NOT on loop step.

Then regenerate contracts (do not hand-edit generated files):
alln dev export-contracts

Proof:
scripts/swift-test.sh --filter ContractExport
scripts/swift-test.sh --filter RetiredVocabulary

Commit ContractRegistry + regenerated docs/generated/ artifacts together.
git commit -m "contracts: retired handoff summary drops false step --no-wait"
```

## Touch only

- `ContractRegistry+Milestone1.swift` (one summary string)
- Regenerated output from `alln dev export-contracts`

## Works Test

```text
scripts/swift-test.sh --filter ContractExport
alln dev export-contracts --check
```

## Done when

- [ ] No `--no-wait` on loop step in that summary
- [ ] Generated contracts regenerated, not hand-edited
- [ ] ContractExport + export-contracts --check green
- [ ] One commit
