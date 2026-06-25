#!/usr/bin/env python3
"""Append rollup summary to .lab/macro-evidence/benchmarks.jsonl for trend tracking."""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--tag", required=True)
    p.add_argument("--rollup", type=Path, required=True)
    p.add_argument("--note", default="")
    args = p.parse_args()

    rollup_path = args.rollup if args.rollup.is_absolute() else REPO / args.rollup
    r = json.loads(rollup_path.read_text())
    roll = r.get("rollup") or {}
    row = {
        "tag": args.tag,
        "at": datetime.now(timezone.utc).isoformat(),
        "verdict": r.get("verdict"),
        "deliverableOutcome": r.get("deliverableOutcome"),
        "deliverableCounts": roll.get("deliverableCounts"),
        "candidateWinRate": roll.get("candidateWinRate"),
        "valueSuppressedTotal": roll.get("valueSuppressedTotal"),
        "gateReason": r.get("gateReason"),
        "note": args.note,
        "rollupPath": str(rollup_path),
    }
    out = REPO / ".lab/macro-evidence/benchmarks.jsonl"
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("a") as f:
        f.write(json.dumps(row) + "\n")
    print(json.dumps(row, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
