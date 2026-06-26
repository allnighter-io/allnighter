# Lab reliability unblock + beta team campaign

**Date:** 2026-06-26 · Branch `feat/design-chain` · Owner: founder + lab

## Why the lab only ran 1–2×/day ("workers always stop")

| Root cause | Fix |
| --- | --- |
| A single stuck worker hit `run.py`'s hard deadline and `raise SystemExit` killed the whole run — **no retry, no resume**. Restart was manual. | `supervisor.py`: per-job retry + exponential backoff, failure isolation (one job failing never stops the campaign), resume (done jobs skip). |
| Runs died when the IDE shell / agent turn ended. | Detached launch via `start_new_session` (`spawn_campaign.py`, `spawn_lab_daemon.py`) — reparented to init (PPID 1), survives session end. |
| The writer auto-chain (v4→v5→v6…) silently burned paid-CLI quota every ~12 min. | Auto-chain neutralized (`run_lab_daemon_inner.sh`). |
| Quota/capacity failures had no cooldown — they looked like hard failures. | Supervisor classifies capacity/quota errors and applies a **bounded** cooldown budget (`capacityRetries`, default 3) — long backoff without an infinite loop. |
| `model_cursor_auto` preferred model is unavailable → silent fallback to ChatGPT 5.5 every run (`TeamResolver.swift:180`). | **Not yet fixed** — model-catalog gap. Set `ALLN_LAB_STRICT_MODEL_SEATS=1` to fail loudly instead. |

## The engine

- `scripts/team_lab/supervisor.py` — serialized job queue, retry/backoff, bounded
  capacity cooldown, heartbeat in `.lab/campaign/state.json`, resume, per-job
  failure isolation. `--dry-run` exercises the loop with no commands.
- `scripts/team_lab/spawn_campaign.py` — detached launch.
- `scripts/team_lab/validate_team.sh` — runs every case in a suite for one team;
  first arg is a champion-overlay path **or** `team:<built-in-id>`.
- `scripts/team_lab/beta_campaign.jsonl` — the 6 beta teams as jobs.

Verified end-to-end with forced-failure, capacity, and resume cases (no quota),
then a live run: `code_bug_hunt_lite` deployed + ran 4 workers unattended.

**Observability note:** during a long single job the `state.json` heartbeat does
not tick (the supervisor blocks on the subprocess); the live signal is the job
log `tail -f .lab/campaign/logs/<job>.log`. A live heartbeat is a future upgrade.

## The 6 beta teams — they already exist as built-ins

`BuiltInTeams.swift` already registers teams in every craft. The "garbage number"
was **validated lab teams**, not product teams. Real remaining gap = a validation
**suite** per craft (all 3 current suites are `lane:code`).

| Beta team | Built-in id | Status |
| --- | --- | --- |
| Bug Hunt Lite | `code_bug_hunt_lite` | Validating now (regressions suite) |
| Bug Hunt | `code_bug_hunt` | Queued, runnable |
| Code Build | `code_core` | Needs a plan/build necessity suite |
| Design Board | `design_core` | Needs a design necessity suite |
| Copy | `copy_core` | Needs a copy necessity suite |
| Signal | `signal_what_to_build_next` | Needs a signal necessity suite |

## Run / observe

```bash
# launch (or relaunch — failed/pending jobs resume, done jobs skip)
python3 scripts/team_lab/spawn_campaign.py --queue scripts/team_lab/beta_campaign.jsonl
# observe
cat .lab/campaign/state.json
tail -f .lab/campaign/logs/<job-id>.log
```

## Next steps to finish the 6

1. Author necessity suites: `plan/build`, `design`, `copy`, `signal` (JSON cases:
   prompt + contextPolicy + expectedQualities + scoringRubricId).
2. Confirm `lane:design|copy|signal` runs end-to-end through `run.py` (rubric/judge
   coverage may need craft-specific rubrics).
3. Swap the 4 `blocked:true` jobs for `team:<id>` validate jobs once suites exist.
4. Fix the `model_cursor_auto` fallback before trusting model-attributed results.
