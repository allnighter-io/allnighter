#!/usr/bin/env python3
"""Lab-only model routing (SSOT for Team Lab worker seats).

Policy (2026-06-22+):
- **Never** assign Antigravity / `model_gemini*` to lab worker seats on code teams. The
  `agy` driver was excluded after R6 (wrong-cwd fixed separately; wall-clock / vendor
  timeouts remain). Re-enable only with an explicit policy change + green calibration.
- **Design lab fanouts:** Grok Build + GPT 5.5 only (no Gemini/AGY in lab even though
  product image engines include Gemini Flash). Duplicate seats are fine.
- **Opus** (`model_opus`) is lead + synthesis/writer only — never a worker seat.
- **Code workers:** rotate Grok Build, Composer 2.5, GPT 5.5, Cursor Auto; Sonnet 4.6
  at most once per run for diversity.
- **Duplicates OK:** the same catalog model may appear on more than one seat when
  preferred is unavailable and bounded-pool fallback resolves inside the allowed pool.
- **Bounded pool fallback:** `fallbackPolicy: exactOnly` with `allowedModelIds` set to
  the lane worker pool means “stay inside the pool; pick strongest ready substitute if
  preferred is down.” Set `ALLN_LAB_STRICT_MODEL_SEATS=1` to fail instead.

Wired by `overlay.ensure_model_policy_team` on every `run.py` experiment unless
`ALLN_LAB_MODEL_POLICY=0`. See `docs/phases/Team_Lab_Run_Factory.md` § Lab model policy.
"""
from __future__ import annotations

import os
from typing import Any

# Built-in catalog ids (Packages/AllnighterCore/Sources/AllnighterCore/ModelCatalog.swift)
LEAD_OPUS = "model_opus"

# Solo-model override: when ALLN_LAB_SOLO_MODEL is set, EVERY seat (lead + all
# workers + scout) is pinned to that one catalog model. Use when only one provider
# has credits (e.g. Composer-only days). This deliberately sacrifices fan-out
# diversity for a runnable baseline — note it loudly in any result.
SOLO_MODEL_ENV = "ALLN_LAB_SOLO_MODEL"


def solo_model() -> str | None:
    v = os.environ.get(SOLO_MODEL_ENV, "").strip()
    return v or None

# Code lane — round-robin pool (every seat except the single Sonnet slot).
CODE_ROTATING_WORKER_POOL = [
    "model_grok",
    "model_cursor_composer_25",
    "model_chatgpt",
    "model_cursor_auto",
]

# Design lane lab fanouts — text/mockup workers only; no Gemini/AGY in lab.
DESIGN_LAB_ROTATING_WORKER_POOL = [
    "model_grok",
    "model_chatgpt",
]

# Claude Sonnet 4.6 — at most one code-lane seat per run for diversity.
SONNET_WORKER = "model_sonnet"
SONNET_SEAT_INDEX = 2

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

CODE_WORKER_POOL = [*CODE_ROTATING_WORKER_POOL, SONNET_WORKER]
DESIGN_LAB_WORKER_POOL = list(DESIGN_LAB_ROTATING_WORKER_POOL)

WORKER_POOL_LABEL = "Grok · Composer 2.5 · GPT 5.5 · Cursor Auto · Sonnet×1"
DESIGN_LAB_POOL_LABEL = "Grok · GPT 5.5 (lab only — no Gemini/AGY)"

LAB_FALLBACK_POLICY = "exactOnly"
LAB_FALLBACK_SEMANTICS = "bounded_pool"


def _lane_policy(lane: str) -> tuple[list[str], list[str], int | None, str]:
    if lane == "design":
        return (
            DESIGN_LAB_ROTATING_WORKER_POOL,
            DESIGN_LAB_WORKER_POOL,
            None,
            DESIGN_LAB_POOL_LABEL,
        )
    return CODE_ROTATING_WORKER_POOL, CODE_WORKER_POOL, SONNET_SEAT_INDEX, WORKER_POOL_LABEL


def preferred_worker_model(seat_index: int, *, lane: str = "code") -> str:
    """Assign a worker model to seat `seat_index`. Code lane: Sonnet once at index 2."""
    rotating, _, sonnet_at, _ = _lane_policy(lane)
    if sonnet_at is not None and seat_index == sonnet_at:
        return SONNET_WORKER
    rotate_index = seat_index if sonnet_at is None or seat_index < sonnet_at else seat_index - 1
    return rotating[rotate_index % len(rotating)]


def apply_model_policy(team_def: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Patch a full TeamPreset for lab runs. Lead Opus only; workers restricted to lane pool."""
    lane = str(team_def.get("lane") or "code")
    rotating, worker_pool, sonnet_at, label = _lane_policy(lane)
    solo = solo_model()
    if solo:
        # One provider has credits today: every seat on the same model, no fan-out.
        worker_pool = [solo]
        rotating = [solo]
        sonnet_at = None
        label = f"SOLO {solo}"

    out = dict(team_def)
    lead = dict(out.get("lead") or {})
    lead["preferredModelId"] = solo or LEAD_OPUS
    lead["allowedModelIds"] = [solo] if solo else lead.get("allowedModelIds")
    lead["fallbackPolicy"] = LAB_FALLBACK_POLICY
    if lead["allowedModelIds"] is None:
        lead.pop("allowedModelIds", None)
    out["lead"] = lead

    specs: list[dict[str, Any]] = []
    sonnet_seats = 0
    for i, spec in enumerate(out.get("workerSpecs") or []):
        row = dict(spec)
        mid = solo or preferred_worker_model(i, lane=lane)
        if mid == SONNET_WORKER:
            sonnet_seats += 1
        row["preferredModelId"] = mid
        row["allowedModelIds"] = list(worker_pool)
        row["fallbackPolicy"] = LAB_FALLBACK_POLICY
        specs.append(row)
    if sonnet_at is not None and sonnet_seats > 1:
        raise ValueError(f"model policy assigned Sonnet to {sonnet_seats} seats (max 1)")
    out["workerSpecs"] = specs

    scout = out.get("scout")
    if isinstance(scout, dict):
        s = dict(scout)
        s["preferredModelId"] = solo or rotating[0]
        s["allowedModelIds"] = list(worker_pool)
        s["fallbackPolicy"] = LAB_FALLBACK_POLICY
        out["scout"] = s

    policy_meta = {
        "lane": lane,
        "lead": solo or LEAD_OPUS,
        "workers": worker_pool,
        "rotatingWorkers": rotating,
        "sonnetWorker": SONNET_WORKER if sonnet_at is not None else None,
        "sonnetSeatIndex": sonnet_at,
        "soloModel": solo,
        "excluded": sorted(BLOCKED_WORKER_MODELS),
        "label": label,
        "fallbackPolicy": LAB_FALLBACK_POLICY,
        "fallbackSemantics": LAB_FALLBACK_SEMANTICS,
        "duplicateModelsAllowed": True,
        "strictModelSeatsEnv": "ALLN_LAB_STRICT_MODEL_SEATS",
    }
    return out, policy_meta
