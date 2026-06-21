#!/usr/bin/env python3
"""Score a completed team-lab experiment from local artifacts."""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def load_worker_answers(run_dir: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for sub in ("workers", "worker_answers"):
        ans = run_dir / sub
        if not ans.exists():
            continue
        for p in sorted(ans.glob("*.md")):
            if ".answer." in p.name or sub == "worker_answers":
                out[p.stem] = p.read_text()
            elif p.name.endswith(".answer.md"):
                out[p.stem.replace(".answer", "")] = p.read_text()
    workers = run_dir / "workers"
    if workers.exists():
        for p in sorted(workers.glob("*.answer.md")):
            out[p.name.replace(".answer.md", "")] = p.read_text()
    return out


def score_worker(worker_id: str, text: str, expected: list[str]) -> dict:
    lower = text.lower()
    hits = [q for q in expected if any(tok in lower for tok in q.lower().split()[:3])]
    novel_markers = [
        "evidence inspected",
        "confidence",
        "falsif",
        "missing observation",
        "what i reject",
        "mcp",
        "contract",
        "proof",
    ]
    structure_hits = sum(1 for m in novel_markers if m in lower)
    return {
        "workerId": worker_id,
        "chars": len(text),
        "expectedQualityHits": len(hits),
        "structureMarkers": structure_hits,
        "failedOrEmpty": len(text.strip()) < 80,
    }


def score_writer(bundle_path: Path, answers: dict[str, str]) -> dict:
    if not bundle_path.exists():
        return {"ok": False, "reason": "missing bundle.md"}
    text = bundle_path.read_text()
    lower = text.lower()
    cites_workers = sum(1 for wid in answers if wid.replace("#", "") in text or wid in text)
    return {
        "ok": True,
        "chars": len(text),
        "mentionsWorkers": cites_workers,
        "hasDissent": "dissent" in lower or "reject" in lower,
        "hasProofSection": "proof" in lower,
        "hasCutOrDefer": "defer" in lower or "cut" in lower,
    }


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("lab_dir", type=Path)
    args = p.parse_args()
    lab = args.lab_dir
    exp = json.loads((lab / "experiment.json").read_text()) if (lab / "experiment.json").exists() else {}
    suite_id = exp.get("suiteId", "")
    expected: list[str] = []
    if suite_id:
        suite_path = Path(__file__).resolve().parents[2] / "docs/team-lab/suites" / f"{suite_id}.json"
        if suite_path.exists():
            suite = json.loads(suite_path.read_text())
            for c in suite.get("cases", []):
                if c.get("caseId") == exp.get("caseId"):
                    expected = c.get("expectedQualities", [])
                    break

    run_dir = lab / "run"
    answers = load_worker_answers(run_dir)
    worker_scores = [score_worker(wid, body, expected) for wid, body in answers.items()]
    writer = score_writer(run_dir / "bundle.md", answers)

    failures = [w for w in worker_scores if w["failedOrEmpty"]]
    team_quality = 0.0
    if worker_scores:
        ok_frac = 1.0 - (len(failures) / len(worker_scores))
        struct_avg = sum(w["structureMarkers"] for w in worker_scores) / len(worker_scores)
        team_quality = round(min(1.0, 0.5 * ok_frac + 0.1 * struct_avg), 3)

    out = {
        "workerScores": worker_scores,
        "writerScore": writer,
        "teamQualityScore": team_quality,
        "workerFailures": [w["workerId"] for w in failures],
    }
    eval_dir = lab / "evaluation"
    eval_dir.mkdir(exist_ok=True)
    (eval_dir / "worker-scores.json").write_text(json.dumps(out, indent=2))

    lines = [
        "## Team quality (heuristic)",
        "",
        f"- Score: **{team_quality}**",
        f"- Workers scored: {len(worker_scores)}",
        f"- Failed/empty: {len(failures)}",
        "",
    ]
    report = lab / "report.md"
    if report.exists():
        report.write_text(report.read_text() + "\n" + "\n".join(lines))
    print(json.dumps(out, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
