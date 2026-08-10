# QABC resume dogfood — post-Codex reset (2026-08-09)

Packet: `docs/archive/phases/Quota_Aware_Bench_Continuity.md` (archived 2026-08-09).

## Context

- **Park half:** live 2026-07-31 against Codex 0% weekly wall — loop
  `relay_43079e27-7973-41f6-8703-f061aab435ca` parked with
  `capacityPark{source: "codex"}` (run `64F87616-ABBE-449B-A11C-6E3AE2D26FEC`).
- **Resume half blocked on:** Codex real reset `2026-08-04T21:32Z`.
- **Founder signal 2026-08-09:** Codex capacity is back; close the packet.

## Post-reset verification

### Capacity (live)

```
Codex/ChatGPT  weekly 77% left  reset 2026-08-15T20:32:18Z (observed 2026-08-09)
```

### Standalone dispatch

```bash
alln run --read-only --model model_gpt_sol --message "Reply with exactly: POST_RESET_OK"
```

- **Result:** `POST_RESET_OK` (run `6E0AF25F…`).
- **Verdict:** Codex seat dispatches cleanly after reset.

### Fresh loop (post-reset dev path)

```bash
alln loop start "QABC post-reset resume proof: reply exactly RESUMED_OK with zero repo changes." \
  --dev model_gpt_sol --pm model_gpt_terra --no-wait --json
```

- **Loop:** `relay_e3d399b9-f62e-40c1-ba0a-4df998e0cc92`
- **Wait outcome:** `status: done`, `note: RESUMED_OK`, `rounds: 1`, `capacityPark: null`
- **Duration:** ~15s (no wall — Codex had headroom at 77%).

### July loop resume attempt (not claimed as QABC proof)

```bash
alln loop resume relay_43079e27-7973-41f6-8703-f061aab435ca \
  --answer "QABC resume proof after Codex reset — continue dev turn, reply RESUMED_OK" \
  --no-wait --json
```

- **Result:** `status: escalated`, `AGENT_NOT_AVAILABLE: PM turn failed to dispatch: unknown worker id 'caller'`.
- **Cause:** stale loop used `--pm caller`; parked run `64F87616` no longer in run store.
- **Not a QABC regression** — operator/config issue on an escalated, reconciled loop.

### Hermetic resume machinery

```bash
scripts/swift-test.sh --filter LoopCapacityParkYieldTests
```

- **Result:** 5/5 green (park yield, no competing runIds, claim-or-adopt, deadline stop, PM twin).

## Closeout verdict

| Criterion | Status |
| --- | --- |
| Codex reset observed | **PASS** — reset passed; meter shows 77% weekly |
| Post-reset Codex dispatch | **PASS** — `POST_RESET_OK` |
| Post-reset loop dev path | **PASS** — fresh loop `RESUMED_OK` |
| Live sleep→wake→auto-resume on same parked loop | **NOT RE-RUN** — July parked run gone; Codex no longer at 0% wall |
| Resume path in code | **PASS** — `LoopCapacityParkYieldTests` + July park half (2026-07-31) |

**Packet closed:** reset resolved; post-reset Codex behavior verified; resume
machinery proven by hermetics and the July park half. Re-walling Codex solely to
replay auto-resume would spend quota for no product gain.
