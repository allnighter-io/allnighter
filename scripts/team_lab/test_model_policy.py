#!/usr/bin/env python3
"""Unit tests for lab model policy (no Gemini; Sonnet at most once)."""
from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
sys.path.insert(0, str(SCRIPTS))

from model_policy import (  # noqa: E402
    LEAD_OPUS,
    SONNET_SEAT_INDEX,
    SONNET_WORKER,
    apply_model_policy,
    preferred_worker_model,
)


class ModelPolicyTests(unittest.TestCase):
    def test_nine_seats_sonnet_once(self) -> None:
        team_def = {"lead": {}, "workerSpecs": [{} for _ in range(9)]}
        patched, meta = apply_model_policy(team_def)
        mids = [s["preferredModelId"] for s in patched["workerSpecs"]]
        self.assertEqual(mids.count(SONNET_WORKER), 1)
        self.assertEqual(mids[SONNET_SEAT_INDEX], SONNET_WORKER)
        self.assertNotIn("model_gemini", mids)
        self.assertNotIn(LEAD_OPUS, mids)
        self.assertEqual(patched["lead"]["preferredModelId"], LEAD_OPUS)
        self.assertEqual(meta["sonnetSeatIndex"], SONNET_SEAT_INDEX)
        self.assertEqual(meta["fallbackSemantics"], "bounded_pool")
        self.assertTrue(meta["duplicateModelsAllowed"])

    def test_design_lane_grok_chatgpt_only(self) -> None:
        team_def = {"lane": "design", "lead": {}, "workerSpecs": [{} for _ in range(3)]}
        patched, meta = apply_model_policy(team_def)
        mids = [s["preferredModelId"] for s in patched["workerSpecs"]]
        self.assertTrue(all(m in ("model_grok", "model_gpt_sol") for m in mids))
        self.assertEqual(meta["lane"], "design")
        self.assertNotIn("model_gemini", meta["workers"])

    def test_rotation_excludes_gemini(self) -> None:
        mids = [preferred_worker_model(i) for i in range(12)]
        self.assertEqual(mids.count(SONNET_WORKER), 1)
        self.assertTrue(all("gemini" not in m for m in mids))
        self.assertTrue(all(m != LEAD_OPUS for m in mids))


if __name__ == "__main__":
    unittest.main()
