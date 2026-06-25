#!/usr/bin/env python3
"""After a writer replay bundle, decide whether to chain the next iteration."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# Synthesis unblocked when deliverable matches R1 and suppression beats v3.
WIN_RATE_MIN = 0.667
SUPPRESSED_MAX = 19

NEXT_SKILL = {
    "writer_v4": ("bug_packet_writer_v5", "writer_v5"),
    "writer_v5": ("bug_packet_writer_v6", "writer_v6"),
}


def load_rollup(tag: str) -> dict:
    path = REPO / f".lab/macro-evidence/rollup_{tag}_live.json"
    if not path.exists():
        raise SystemExit(f"missing rollup: {path}")
    return json.loads(path.read_text())


def summarize(tag: str, rollup_doc: dict) -> dict:
    roll = rollup_doc.get("rollup") or {}
    return {
        "tag": tag,
        "verdict": rollup_doc.get("verdict"),
        "deliverable": rollup_doc.get("deliverableOutcome"),
        "counts": roll.get("deliverableCounts"),
        "winRate": roll.get("candidateWinRate"),
        "suppressed": roll.get("valueSuppressedTotal"),
        "gate": rollup_doc.get("gateReason"),
    }


def passes_bar(summary: dict) -> bool:
    win = summary.get("winRate")
    sup = summary.get("suppressed")
    if win is None or sup is None:
        return False
    return float(win) >= WIN_RATE_MIN and int(sup) <= SUPPRESSED_MAX


def spawn_next(skill: str, tag: str) -> None:
    env = os.environ.copy()
    env["WRITER_SKILL"] = skill
    env["WRITER_TAG"] = tag
    subprocess.run(
        ["python3", str(REPO / "scripts/team_lab/spawn_lab_daemon.py")],
        cwd=str(REPO),
        env=env,
        check=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True, help="Completed writer tag (e.g. writer_v4)")
    parser.add_argument("--spawn-next", action="store_true", help="Start next daemon when bar not met")
    args = parser.parse_args()

    summary = summarize(args.tag, load_rollup(args.tag))
    print(json.dumps({"advance": summary, "passesBar": passes_bar(summary)}, indent=2))

    if passes_bar(summary):
        print("BAR_MET synthesis unblocked — hold full worker reruns until human review")
        return 0

    nxt = NEXT_SKILL.get(args.tag)
    if not nxt:
        print(f"No chained skill after {args.tag}")
        return 0

    skill, tag = nxt
    print(f"BAR_NOT_MET next={tag} skill={skill}")
    if args.spawn_next:
        spawn_next(skill, tag)
        print(f"spawned {tag}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
