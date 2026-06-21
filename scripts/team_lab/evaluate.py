#!/usr/bin/env python3
"""Score a completed team-lab experiment from local artifacts."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from scoring import evaluate_team_quality, score_run_contract


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("lab_dir", type=Path)
    p.add_argument("--rescore-contract", action="store_true", help="recompute run-contract from artifacts")
    args = p.parse_args()
    lab = args.lab_dir
    exp = json.loads((lab / "experiment.json").read_text()) if (lab / "experiment.json").exists() else {}

    if args.rescore_contract:
        run = exp.get("run") or {}
        journal_copied = (lab / "run").exists()
        score_run_contract(
            lab,
            status=run.get("status", "unknown"),
            result_ok=(lab / "team-result.json").exists(),
            journal_copied=journal_copied,
            expected_run_id=run.get("runId"),
        )

    out = evaluate_team_quality(lab)

    lines = [
        "## Team quality (heuristic)",
        "",
    ]
    if out.get("teamQualityWithheld"):
        lines.append(f"- Team quality: **withheld** ({out.get('teamQualityWithheldReason')})")
    else:
        lines.append(f"- Score: **{out.get('teamQualityScore')}**")
    lines += [
        f"- Logical workers scored: {out.get('logicalWorkerCount')}",
        f"- Failed/empty: {len(out.get('workerFailures', []))}",
        f"- Writer consistency issues: {out.get('writerConsistency', {}).get('issueCount', 0)}",
        "",
    ]
    report = lab / "report.md"
    if report.exists():
        body = report.read_text()
        marker = "## Team quality (heuristic)"
        if marker in body:
            body = body.split(marker)[0].rstrip() + "\n"
        report.write_text(body + "\n" + "\n".join(lines))

    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
