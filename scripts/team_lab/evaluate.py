#!/usr/bin/env python3
"""Score a completed team-lab experiment from local artifacts."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from report import write_lab_report
from scoring import evaluate_team_quality, score_run_contract


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("lab_dir", type=Path)
    p.add_argument("--rescore-contract", action="store_true", help="recompute run-contract from artifacts")
    p.add_argument(
        "--regenerate-report",
        action="store_true",
        help="rewrite report.md from experiment.json + evaluation (implies --rescore-contract)",
    )
    args = p.parse_args()
    lab = args.lab_dir
    exp = json.loads((lab / "experiment.json").read_text()) if (lab / "experiment.json").exists() else {}

    contract = None
    if args.rescore_contract or args.regenerate_report:
        run = exp.get("run") or {}
        journal_copied = (lab / "run").exists()
        contract = score_run_contract(
            lab,
            status=run.get("status", "unknown"),
            result_ok=(lab / "team-result.json").exists(),
            journal_copied=journal_copied,
            expected_run_id=run.get("runId"),
        )

    out = evaluate_team_quality(lab)
    eval_dir = lab / "evaluation"
    eval_dir.mkdir(exist_ok=True)
    (eval_dir / "team-quality.json").write_text(json.dumps(out, indent=2))

    if args.regenerate_report:
        if contract is None:
            contract_path = eval_dir / "run-contract-score.json"
            if not contract_path.exists():
                raise SystemExit("run-contract-score.json missing; pass --rescore-contract")
            contract = json.loads(contract_path.read_text())
        write_lab_report(lab, contract=contract, team_eval=out)
    elif args.rescore_contract and contract is not None:
        marker = "## Team quality"
        lines = [marker, ""]
        if out.get("teamQualityWithheld"):
            lines.append(f"- Not judgeable: **withheld** ({out.get('teamQualityWithheldReason')})")
        else:
            lines.append("- **judge-pending** — run `compare.py <baseline> <candidate>` (two blind LLM judges).")
        lines += [
            f"- Answer/review workers (judged per-role by compare.py): {out.get('answerReviewWorkerCount')}",
            f"- Failed/empty (truth): {len(out.get('workerFailures', []))}",
            f"- Writer consistency issues (truth): {out.get('writerConsistency', {}).get('issueCount', 0)}",
            "",
        ]
        report = lab / "report.md"
        if report.exists():
            body = report.read_text()
            for m in (marker, "## Team quality (heuristic)"):
                if m in body:
                    body = body.split(m)[0].rstrip() + "\n"
                    break
            report.write_text(body + "\n" + "\n".join(lines))

    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
