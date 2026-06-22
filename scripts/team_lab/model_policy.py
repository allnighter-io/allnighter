#!/usr/bin/env python3
"""Lab-only model routing (SSOT for Team Lab worker seats).

Policy (2026-06-22+):
- **Never** assign Antigravity / `model_gemini*` to lab worker seats. The `agy`
  driver was excluded after R6 proved unreliable harness interaction (wrong-cwd
  bugs fixed separately; wall-clock / vendor timeouts remain). Re-enable only
  with an explicit lab policy change + passing calibration run — not per-round
  overrides in overlays.
- **Opus** (`model_opus`) is lead + synthesis/writer only — never a worker seat.
- **Workers:** rotate Grok Build, Composer 2.5, GPT 5.5, Cursor Auto; Sonnet
  4.6 at most once per run for diversity.
- **Duplicates OK:** the same catalog model may appear on more than one seat
  (e.g. two GPT 5.5 workers when Cursor Auto is unavailable and bounded-pool
  fallback resolves within `WORKER_POOL`). That is expected, not a policy bug.
- **Bounded pool fallback:** `fallbackPolicy: exactOnly` with `allowedModelIds`
  set to the full worker pool means “stay inside the no-AGY pool; pick strongest
  ready model if preferred is unavailable.” Set `ALLN_LAB_STRICT_MODEL_SEATS=1`
  to fail the run instead when preflight reports a preferred→substitute resolution.

Wired by `overlay.ensure_model_policy_team` on every `run.py` experiment unless
`ALLN_LAB_MODEL_POLICY=0`. See `docs/phases/MCP_Run_Factory_Team_Lab.md` § Lab
model policy.
"""
from __future__ import annotations

from typing import Any

# Built-in catalog ids (Packages/AllnighterCore/Sources/AllnighterCore/ModelCatalog.swift)
LEAD_OPUS = "model_opus"

# Round-robin pool (every seat except the single Sonnet slot).
ROTATING_WORKER_POOL = [
    "model_grok",
    "model_cursor_composer_25",
    "model_chatgpt",
    "model_cursor_auto",
]

# Claude Sonnet 4.6 — at most one seat per run for diversity.
SONNET_WORKER = "model_sonnet"
SONNET_SEAT_INDEX = 2

# Allowed on any worker seat (for allowedModelIds + verification). Opus is lead-only.
WORKER_POOL = [*ROTATING_WORKER_POOL, SONNET_WORKER]

BLOCKED_WORKER_MODELS = frozenset(
    {
        LEAD_OPUS,
        "model_gemini",
        "model_gemini_pro",
        "model_agy_sonnet",
        "model_agy_opus",
        "model_agy_gptoss",
    }
)

WORKER_POOL_LABEL = "Grok · Composer 2.5 · GPT 5.5 · Cursor Auto · Sonnet×1"

# Lab `exactOnly` is NOT “preferred or abort.” With allowedModelIds = WORKER_POOL,
# TeamResolver picks the strongest ready model inside the pool when preferred is
# down (see TeamResolver.selectModel case .exactOnly). Record this explicitly so
# experiment preflight warnings like “model_cursor_auto unavailable; resolved to
# ChatGPT 5.5” are expected bounded fallback, not a harness defect.
LAB_FALLBACK_POLICY = "exactOnly"
LAB_FALLBACK_SEMANTICS = "bounded_pool"


def preferred_worker_model(seat_index: int) -> str:
    """Assign a worker model to seat `seat_index`. Sonnet appears exactly once."""
    if seat_index == SONNET_SEAT_INDEX:
        return SONNET_WORKER
    rotate_index = seat_index if seat_index < SONNET_SEAT_INDEX else seat_index - 1
    return ROTATING_WORKER_POOL[rotate_index % len(ROTATING_WORKER_POOL)]


def apply_model_policy(team_def: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Patch a full TeamPreset for lab runs. Lead Opus only; workers restricted to pool."""
    out = dict(team_def)
    lead = dict(out.get("lead") or {})
    lead["preferredModelId"] = LEAD_OPUS
    lead["fallbackPolicy"] = LAB_FALLBACK_POLICY
    out["lead"] = lead

    specs: list[dict[str, Any]] = []
    sonnet_seats = 0
    for i, spec in enumerate(out.get("workerSpecs") or []):
        row = dict(spec)
        mid = preferred_worker_model(i)
        if mid == SONNET_WORKER:
            sonnet_seats += 1
        row["preferredModelId"] = mid
        row["allowedModelIds"] = list(WORKER_POOL)
        row["fallbackPolicy"] = LAB_FALLBACK_POLICY
        specs.append(row)
    if sonnet_seats > 1:
        raise ValueError(f"model policy assigned Sonnet to {sonnet_seats} seats (max 1)")
    out["workerSpecs"] = specs

    scout = out.get("scout")
    if isinstance(scout, dict):
        s = dict(scout)
        s["preferredModelId"] = ROTATING_WORKER_POOL[0]
        s["allowedModelIds"] = list(WORKER_POOL)
        s["fallbackPolicy"] = LAB_FALLBACK_POLICY
        out["scout"] = s

    policy_meta = {
        "lead": LEAD_OPUS,
        "workers": WORKER_POOL,
        "rotatingWorkers": ROTATING_WORKER_POOL,
        "sonnetWorker": SONNET_WORKER,
        "sonnetSeatIndex": SONNET_SEAT_INDEX,
        "excluded": sorted(BLOCKED_WORKER_MODELS),
        "label": WORKER_POOL_LABEL,
        "fallbackPolicy": LAB_FALLBACK_POLICY,
        "fallbackSemantics": LAB_FALLBACK_SEMANTICS,
        "duplicateModelsAllowed": True,
        "strictModelSeatsEnv": "ALLN_LAB_STRICT_MODEL_SEATS",
    }
    return out, policy_meta
