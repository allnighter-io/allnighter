# Hardened writer v1 — negative experiment

**Status:** retired · do not promote · do not rerun full worker rounds with this writer variant.

**Date:** 2026-06-24 · Round 2 bundle tag `hardened_writer_v1`.

## Verdict

Treat `hardened_writer_v1` as a **failed writer experiment** and a **successful lab capability test**.

The bundle script, per-case macro compose, manifest append, and aggregate rollup all worked. The aggregate gate correctly **held** at 3 fresh inputs. We now have durable macro evidence artifacts.

The writer hardening (Specialist Evidence Disposition section on `bug_packet_writer`) did **not** unlock Trace value. Deliverable got worse and suppression did not improve.

## Evidence (Lite vs Lite+Trace, 3-case necessity bundle)

| Bundle | Deliverable counts | Candidate win rate | Suppressed (raw → deduped) | Gate |
| --- | --- | --- | --- | --- |
| Round 1 (original writer) | 2 candidate / 1 tie | 67% | 34 → **33** | hold |
| `hardened_writer_v1` | 1 baseline / 2 tie | 0% | 38 → **36** | hold |

Deduped counts normalize absolute/relative/basename path variants and line ranges (`dedupe_claim_refs` in `macro_schema.py`). Raw totals inflated by duplicate refs like `run.py:373` vs `scripts/team_lab/run.py:373`.

### Per case (`hardened_writer_v1`)

| Case | Deliverable | Suppressed |
| --- | --- | --- |
| `floor_show_wrong_run_v1` | baseline (was tie) | 15 (was 8) |
| `mcp_fs_bypass_scoring_v1` | tie (was candidate) | 8 (was 11) |
| `cursor_composer_session_continuity_v1` | tie (was candidate) | 15 (same) |

## Interpretation

- **Trace still has positive signal from Round 1** — two candidate wins under the original writer.
- **Hardened writer v1 failed** — likely added process/verbosity without improving synthesis judgment.
- **Do not promote Lite+Trace** on this evidence.
- **Next problem:** synthesis design + suppression-metric cleanup, not more full Trace worker rounds.

## Artifacts (local `.lab/`, gitignored)

| Artifact | Path |
| --- | --- |
| Hardened manifest | `.lab/macro-evidence/manifest_hardened_writer_v1.jsonl` |
| Hardened rollup | `.lab/macro-evidence/rollup_hardened_writer_v1.json` |
| Round 1 rollup | `.lab/macro-evidence/rollup_bug_hunt_necessity_v1.json` |
| Bundle log | `.lab/macro-hardened-writer-bundle.log` |

## Follow-ups

1. **Suppression metric audit (done)** — `claim_carried_in_plan` + `dedupe_claim_refs` in `macro_schema.py`. Re-counted without re-judging deliverable:
   - Round 1: **34 → 29** suppressed (deliverable unchanged: 2 candidate / 1 tie)
   - Hardened v1: **38 → 25** suppressed (deliverable unchanged: 1 baseline / 2 tie)
   - Sample audit (`audit_suppression.py`): many raw suppressions were absolute-path duplicates; `MCPServer.swift:281` is genuinely missing (writer cited `:280`).

2. **Writer-only replay** — `replay_writer_macro.py` + `bug_packet_writer_v2` skill. Writer v2 replay in progress on Round 1 labs (suppression-only until judges configured).

3. **Do not promote Lite+Trace** until writer v2 replay shows lower confirmed suppression **and** live deliverable judges agree.

## Writer v2 replay (complete, suppression-only)

Writer-only replay on Round 1 worker outputs (`manifest_writer_v2.jsonl`). Deliverable outcomes are **provisional** (carried from R1; live judges not run).

| Case | R1 suppressed (metric-fixed) | Writer v2 |
| --- | ---: | ---: |
| `floor_show_wrong_run_v1` | 5 | 6 |
| `mcp_fs_bypass_scoring_v1` | 11 | 10 |
| `cursor_composer_session_continuity_v1` | 13 | 15 |
| **Total** | **29** | **31** |

**Verdict:** v2 did not beat R1 on confirmed suppression (31 vs 29). Mixed per-case movement; not enough to justify full worker reruns or promotion. Next lever: another synthesis iteration or live deliverable compose once judges are configured.
