#!/usr/bin/env python3
"""Tests for promote gate and overlay merge (no MCP, no quota).

Run:  python3 scripts/team_lab/test_promote.py
"""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import promote as P  # noqa: E402
from config import config_hash  # noqa: E402

PASSES: list[str] = []
FAILS: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    (PASSES if ok else FAILS).append(f"{name}: {detail}" if detail else name)


def clean_record(**overrides) -> dict:
    base = {
        "judgeMode": "live",
        "evidenceValid": True,
        "sameInput": True,
        "interactionWarning": False,
        "unmatchedRoles": [],
        "bankedRoles": ["correct_fix_planner#1"],
        "deliverableOutcome": "candidate",
        "championConfigHash": "aaa111",
        "candidateConfigHash": "bbb222",
        "materialCandidateDelta": True,
    }
    base.update(overrides)
    return base


def test_gate() -> None:
    v, r = P.autopromote_gate(clean_record())
    check("gate.clean_promote", v == "promote" and r is None)

    v, r = P.autopromote_gate(clean_record(championConfigHash="same", candidateConfigHash="same"))
    check("gate.identical_config_hold", v == "hold" and r == "no material candidate delta")

    v, _ = P.autopromote_gate(clean_record(judgeMode="mock"))
    check("gate.mock_hold", v == "hold")

    v, _ = P.autopromote_gate(clean_record(interactionWarning=True))
    check("gate.interaction_escalate", v == "escalate")

    v, _ = P.autopromote_gate(clean_record(deliverableOutcome="baseline"))
    check("gate.deliverable_regress_escalate", v == "escalate")

    v, _ = P.autopromote_gate(clean_record(bankedRoles=[]))
    check("gate.no_banks_hold", v == "hold")

    v, _ = P.autopromote_gate(
        clean_record(deliverableOutcome="tie", bankedRoles=["a#0", "b#1", "c#2"])
    )
    check("gate.tie_many_banks_escalate", v == "escalate")


def test_config_hash() -> None:
    overlay = {
        "roles": {
            "a#0": {"skillId": "s1", "templateHash": "111", "provenance": "incumbent"},
            "b#1": {"skillId": "s2", "templateHash": "222", "provenance": "banked"},
        }
    }
    h1 = config_hash(overlay, deployed_team_id="code_bug_hunt", arm="champion")
    h2 = config_hash(overlay, deployed_team_id="code_bug_hunt", arm="candidate")
    check("hash.arm_differs", h1 != h2)
    overlay["candidateDelta"] = {"kind": "hypothesis_patch", "patchedRoles": ["b#1"]}
    h3 = config_hash(overlay, deployed_team_id="lab_team", arm="candidate")
    check("hash.delta_changes", h3 != h2)


def test_build_overlay_merge() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        base_lab = root / "baseline"
        cand_lab = root / "candidate"
        for lab, skill_suffix in ((base_lab, "base"), (cand_lab, "cand")):
            lab.mkdir()
            workers = [
                {
                    "id": "w1",
                    "skillId": "correct_fix_planner",
                    "skillName": "Correct Fix Planner",
                    "instanceIndex": 1,
                    "purpose": "answer",
                    "resolvedWorkerPromptSnapshot": f"Plan fix {skill_suffix}\n\nCase body",
                },
            ]
            (lab / "team-result.json").write_text(json.dumps({"workers": workers}))
            (lab / "experiment.json").write_text(
                json.dumps({"teamLab": {"configHash": "x", "deployedTeamId": "code_bug_hunt"}})
            )

        def fake_fetch(_alln: Path, skill_id: str) -> str:
            return {"correct_fix_planner": "Plan fix base"}[skill_id]

        with mock.patch.object(P, "fetch_skill_template", side_effect=fake_fetch):
            overlay = P.build_overlay(
                suite_id="bug_hunt_repo_regressions_v1",
                team_id="code_bug_hunt",
                round_no=3,
                compare_record=clean_record(bankedRoles=["correct_fix_planner#1"]),
                baseline_lab=base_lab,
                candidate_lab=cand_lab,
                alln=Path("/dev/null"),
                prior=None,
            )

    check("overlay.promotion_class", overlay.get("promotionClass") == "quality")


def main() -> int:
    test_gate()
    test_config_hash()
    test_build_overlay_merge()
    print(f"PASS {len(PASSES)}  FAIL {len(FAILS)}")
    for f in FAILS:
        print(f"  FAIL {f}")
    return 1 if FAILS else 0


if __name__ == "__main__":
    raise SystemExit(main())
