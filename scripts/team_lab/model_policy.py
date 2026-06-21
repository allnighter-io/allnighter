#!/usr/bin/env python3
"""Lab-only model routing — Opus 4.8 lead, Gemini / Composer 2.5 / Grok Build workers."""
from __future__ import annotations

from typing import Any

# Built-in catalog ids (Packages/AllnighterCore/Sources/AllnighterCore/ModelCatalog.swift)
LEAD_OPUS = "model_opus"
WORKER_POOL = [
    "model_gemini",
    "model_cursor_composer_25",
    "model_grok",
]
WORKER_POOL_LABEL = "Gemini · Composer 2.5 · Grok Build"


def apply_model_policy(team_def: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Patch a full TeamPreset for lab runs. Lead Opus only; workers restricted to pool."""
    out = dict(team_def)
    lead = dict(out.get("lead") or {})
    lead["preferredModelId"] = LEAD_OPUS
    lead["fallbackPolicy"] = "exactOnly"
    out["lead"] = lead

    specs: list[dict[str, Any]] = []
    for i, spec in enumerate(out.get("workerSpecs") or []):
        row = dict(spec)
        row["preferredModelId"] = WORKER_POOL[i % len(WORKER_POOL)]
        row["allowedModelIds"] = list(WORKER_POOL)
        row["fallbackPolicy"] = "exactOnly"
        specs.append(row)
    out["workerSpecs"] = specs

    scout = out.get("scout")
    if isinstance(scout, dict):
        s = dict(scout)
        s["preferredModelId"] = WORKER_POOL[0]
        s["allowedModelIds"] = list(WORKER_POOL)
        s["fallbackPolicy"] = "exactOnly"
        out["scout"] = s

    policy_meta = {
        "lead": LEAD_OPUS,
        "workers": WORKER_POOL,
        "label": WORKER_POOL_LABEL,
    }
    return out, policy_meta
