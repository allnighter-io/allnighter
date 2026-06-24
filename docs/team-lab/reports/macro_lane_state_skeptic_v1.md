# Macro lane: Lite + State Skeptic

**Status:** active · round 1 · measurement only (no auto-promote)

## Why this lane

`code_bug_hunt_lite_plus_trace` is **parked** (hold on live deliverable; writer experiments failed). Trace workers showed signal in Round 1, but synthesis could not carry it — that is not solved by another Trace run.

Next forward_select on **Bug Hunt Lite**:

| Candidate | Rationale |
| --- | --- |
| **State Skeptic `#0`** (this lane) | Banked on full Bug Hunt R6; targets duplicated/stale state — fits `composer_paste_dead`, session continuity, floor_show contamination |
| ~~Trace Mapper~~ | Parked — see `hardened_writer_v1_negative_experiment.md` |

## Arm

- **Baseline:** `code_bug_hunt_lite` champion overlay
- **Candidate:** Lite + `state_skeptic#0` from full Bug Hunt donor
- **Overlay:** `docs/team-lab/candidates/bug_hunt_necessity_v1/code_bug_hunt_lite_plus_state_skeptic_r1.json`
- **Operation:** `forward_select` on `bug_hunt_necessity_v1` (same 3 cases as Trace bundle)

## Bundle cases

1. `floor_show_wrong_run_v1`
2. `mcp_fs_bypass_scoring_v1`
3. `cursor_composer_session_continuity_v1`

Reuses Round 1 genesis baseline labs (`--baseline-lab`) — candidate arm only per case.

## Run

```bash
bash scripts/team_lab/run_lite_plus_state_skeptic_bundle.sh
```

Manifest: `.lab/macro-evidence/manifest_lite_plus_state_skeptic_v1.jsonl`  
Rollup: `.lab/macro-evidence/rollup_lite_plus_state_skeptic_v1.json`

## Promotion gate

Same as spec: ≥3 fresh inputs, deliverable favors candidate, suppression gate clear, live judges. **Do not auto-promote.**
