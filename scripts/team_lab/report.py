"""Regenerate team-lab report.md from canonical experiment + evaluation artifacts."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def write_lab_report(
    lab_dir: Path,
    *,
    contract: dict[str, Any],
    team_eval: dict[str, Any],
) -> None:
    exp_path = lab_dir / "experiment.json"
    if not exp_path.exists():
        raise FileNotFoundError(f"missing experiment.json: {lab_dir}")
    exp = json.loads(exp_path.read_text())

    preflight = exp.get("preflight") or {}
    preflight_path = lab_dir / "team-preflight.json"
    if preflight_path.exists():
        pf = json.loads(preflight_path.read_text())
        preflight = {**preflight, **pf}

    run = exp.get("run") or {}
    report_lines = [
        f"# Team Lab Report — {lab_dir.name}",
        "",
        f"- Team: `{exp.get('teamId', '?')}`",
        f"- Suite: `{exp.get('suiteId', '?')}` / case `{exp.get('caseId', '?')}`",
        f"- Round: {exp.get('round', '?')} variant `{exp.get('variant', '?')}`",
        f"- Run: `{run.get('runId', '?')}`",
        f"- Terminal status: `{run.get('status', 'unknown')}`",
        f"- Run contract score: **{contract.get('runContractScore')}**",
        f"- Scoring source: `{contract.get('scoringSource')}` (fsBypass={contract.get('fsBypass')})",
    ]
    if exp.get("writerResumedAt"):
        report_lines.append(f"- Writer resumed at: `{exp['writerResumedAt']}`")
    report_lines += ["", "## Preflight warnings", ""]
    for w in preflight.get("warnings", []):
        report_lines.append(f"- {w}")
    if not preflight.get("warnings"):
        report_lines.append("- (none)")
    report_lines += ["", "## Run contract checks", ""]
    for c in contract.get("checks", []):
        mark = "ok" if c.get("ok") else "FAIL"
        report_lines.append(f"- [{mark}] {c['name']}")
    report_lines += ["", "## Team quality", ""]
    if team_eval.get("teamQualityWithheld"):
        report_lines.append(
            f"- Quality not judgeable: **withheld** ({team_eval.get('teamQualityWithheldReason')}) — "
            "fix the substrate before judging."
        )
    else:
        report_lines.append(
            "- Quality is **judge-pending** — no deterministic score. Run a blind "
            "two-judge A/B against a baseline/candidate via `compare.py`."
        )
    ready_workers = preflight.get("readyWorkers") or []
    ready_count = len(ready_workers) if ready_workers else preflight.get("readyWorkerCount", 0)
    report_lines += [
        f"- Preflight-ready sources: {ready_count} (incl. writer)",
        f"- Answer/review workers (judged per-role by compare.py): {team_eval.get('answerReviewWorkerCount')}",
        f"- Writer consistency issues (truth check): {team_eval.get('writerConsistency', {}).get('issueCount', 0)}",
        "",
        "## Next",
        "",
        "- Generate a FRESH input each round: `scenario.py <suite>` (never reuse an input)",
        "- Blind A/B vs the champion run: `compare.py <baseline_dir> <candidate_dir>`",
        "- Bank per-worker wins (both judges agree); audit the deliverable for regressions",
        "",
    ]
    (lab_dir / "report.md").write_text("\n".join(report_lines))
