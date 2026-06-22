#!/usr/bin/env python3
"""Lab-only model routing — Opus 4.8 lead/writer only; no Gemini/AGY workers."""
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
    lead["fallbackPolicy"] = "exactOnly"
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
        row["fallbackPolicy"] = "exactOnly"
        specs.append(row)
    if sonnet_seats > 1:
        raise ValueError(f"model policy assigned Sonnet to {sonnet_seats} seats (max 1)")
    out["workerSpecs"] = specs

    scout = out.get("scout")
    if isinstance(scout, dict):
        s = dict(scout)
        s["preferredModelId"] = ROTATING_WORKER_POOL[0]
        s["allowedModelIds"] = list(WORKER_POOL)
        s["fallbackPolicy"] = "exactOnly"
        out["scout"] = s

    policy_meta = {
        "lead": LEAD_OPUS,
        "workers": WORKER_POOL,
        "rotatingWorkers": ROTATING_WORKER_POOL,
        "sonnetWorker": SONNET_WORKER,
        "sonnetSeatIndex": SONNET_SEAT_INDEX,
        "excluded": sorted(BLOCKED_WORKER_MODELS),
        "label": WORKER_POOL_LABEL,
    }
    return out, policy_meta
