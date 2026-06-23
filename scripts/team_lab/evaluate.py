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
    args = p.parse_args()
    lab = args.lab_dir
    exp = json.loads((lab / "experiment.json").read_text()) if (lab / "experiment.json").exists() else {}

    if args.rescore_contract:
        run = exp.get("run") or {}
        journal_copied = (lab / "run").exists()
        contract = score_run_contract(
            lab,
            status=run.get("status", "unknown"),
            result_ok=(lab / "team-result.json").exists(),
            journal_copied=journal_copied,
            expected_run_id=run.get("runId"),
        )
    else:
        contract_path = lab / "evaluation" / "run-contract-score.json"
        if not contract_path.exists():
            raise SystemExit(f"missing {contract_path}; pass --rescore-contract")
        contract = json.loads(contract_path.read_text())

    team_eval = evaluate_team_quality(lab)
    eval_dir = lab / "evaluation"
    eval_dir.mkdir(exist_ok=True)
    (eval_dir / "team-quality.json").write_text(json.dumps(team_eval, indent=2))
    write_lab_report(lab, contract=contract, team_eval=team_eval)

    print(json.dumps(team_eval, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
