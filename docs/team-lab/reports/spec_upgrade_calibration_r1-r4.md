# Spec Upgrade calibration — rounds 1–4

Team: `code_spec_upgrade` · Suite: `spec_upgrade_mcp_lab_v1`

## Scorecard

| Round | Variant | Contract | fsBypass | Team Q | Writer issues | Duration |
| --- | --- | --- | --- | --- | --- | --- |
| R1 | baseline | 0.714 | true | withheld | — | ~9.4 min |
| R2 | evidence-contract | 1.0 | false | 0.85 | 1 (stale round claim) | ~11 min |
| R3 | evidence-contract-r3 | 1.0 | false | 1.0* | 0 | ~12 min |
| R4 | harness-v2 | 1.0† | false | 1.0* | 0 | ~11.7 min |

\* Heuristic v1 — **not authoritative** for `TeamCatalog` mutations (R4 unanimous).

† After harness fix: `floor_show` run id read from `floor.run.id`.

## Substrate fixes landed (from dogfood)

- MCP Content-Length client; `team_result(detail=full)`; worker progress in status
- MCP-first scoring; `fsBypass` gate; team quality withholding
- `floor_show` / `spec_get` `runId` alias
- Evidence footer on Spec Upgrade worker skills; writer artifact-trust instruction
- `experiment.json` enrichment; `evaluator-record.json`; writer consistency check
- Spec doc: PRE-S0, measurement validity, deferred S06, Python canonical commands

## Repeatable team recommendations (stable across R2–R4)

1. Two-lane scoring — run contract before team quality
2. MCP-only law — FS journal is diff-oracle only
3. Defer S06 sweep; Bug Hunt regression suite is v1 gate
4. Heuristic evaluator is placeholder — do not mutate teams on keyword score
5. Hype Skeptic + Contrarian earn their seats (catch fake victory / stale claims)
6. Contract Auditor + Proof Planner high value on proof architecture

## Verdict

**Substrate:** Spec Upgrade dogfood satisfied PRE-S0 for R2–R4 (`fsBypass=false`, contract ≥ 0.95).

**Team:** Packet quality is strong; calibration loop is not yet proven (self-dogfood on one doc, heuristic judge).

**Next team:** Bug Hunt on `bug_hunt_repo_regressions_v1` (2–3 known regressions) once suite exists.
