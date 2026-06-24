#!/usr/bin/env python3
"""Writer-only replay for macro candidate labs — re-synthesize plan, re-compose.

Preserves worker answers from team-result.json; does not re-run workers or patch
the canonical run journal.

    python3 scripts/team_lab/replay_writer_macro.py \\
        --manifest .lab/macro-evidence/manifest.jsonl \\
        --skill-id bug_packet_writer_v2 \\
        --variant-label writer_v2 \\
        --case floor_show_wrong_run_v1
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "scripts" / "team_lab"))

from resume_writer import (  # noqa: E402
    assemble_writer_prompt,
    build_writer_founder_prompt,
    invoke_claude_opus,
)

SCRIPT = REPO / "scripts" / "team_lab"


def load_manifest(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows


def resolve_lab(raw: str) -> Path:
    p = Path(raw)
    if not p.is_absolute():
        p = REPO / p
    return p.resolve()


def team_result_as_run(tr: dict, task: str) -> dict:
    return {
        "prompt": task,
        "workers": tr.get("workers", []),
        "workerAnswers": tr.get("workerAnswers", []),
    }


def clone_lab(src: Path, dst: Path) -> None:
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(
        src,
        dst,
        ignore=shutil.ignore_patterns("evaluation/macro-verdict.json"),
    )


def patch_team_result_plan(lab: Path, markdown: str, *, skill_id: str) -> None:
    tr_path = lab / "team-result.json"
    tr = json.loads(tr_path.read_text())
    tr["plan"] = {"markdown": markdown}
    stages = tr.get("stages") or []
    if stages:
        stages[-1] = {
            **stages[-1],
            "promptProfileId": skill_id,
            "purpose": "plan",
            "status": "done",
            "payload": {"kind": "plan", "markdown": markdown},
        }
        tr["stages"] = stages
    tr_path.write_text(json.dumps(tr, indent=2) + "\n")
    bundle = lab / "run" / "bundle.md"
    if bundle.parent.exists():
        bundle.write_text(markdown)


def append_manifest(path: Path, row: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as f:
        f.write(json.dumps(row) + "\n")


def replay_case(
    *,
    row: dict,
    skill_id: str,
    variant_label: str,
    timeout_s: int,
    dry_run: bool,
    skip_compose: bool,
) -> dict:
    baseline = resolve_lab(row["baselineLab"])
    candidate_src = resolve_lab(row["candidateLab"])
    case_id = row["caseId"]
    replay_dir = REPO / ".lab" / f"writer-replay_{case_id}_{variant_label}"
    clone_lab(candidate_src, replay_dir)

    tr = json.loads((replay_dir / "team-result.json").read_text())
    exp = json.loads((replay_dir / "experiment.json").read_text())
    task = (exp.get("request") or {}).get("prompt") or ""
    run = team_result_as_run(tr, task)
    founder = build_writer_founder_prompt(run)
    prompt = assemble_writer_prompt(skill_id, founder)
    (replay_dir / f"replay-writer-prompt-{variant_label}.md").write_text(prompt)
    print(f"case={case_id} replay_dir={replay_dir} prompt_chars={len(prompt)}", flush=True)

    if dry_run:
        return {"caseId": case_id, "replayDir": str(replay_dir), "dryRun": True}

    repo_root = Path(exp.get("repoRoot") or REPO)
    markdown = invoke_claude_opus(prompt, repo_root=repo_root, timeout_s=timeout_s)
    patch_team_result_plan(replay_dir, markdown, skill_id=skill_id)
    print(f"writer_chars={len(markdown)}", flush=True)

    macro_path = replay_dir / "evaluation" / "macro-verdict.json"
    if skip_compose:
        from macro_schema import dedupe_claim_refs, infer_writer_disposition, vnrc_delta_from_labs

        vnrc = vnrc_delta_from_labs(baseline, replay_dir)
        disp = infer_writer_disposition(baseline, replay_dir, added_roles=["trace_mapper#0"])
        macro_path.parent.mkdir(parents=True, exist_ok=True)
        verdict = {
            "schemaVersion": 1,
            "caseId": case_id,
            "deliverableOutcome": row.get("deliverableOutcome", "tie"),
            "vnrcDelta": vnrc,
            "writerDisposition": disp,
            "arm": {"addedRoles": ["trace_mapper#0"]},
        }
        macro_path.write_text(json.dumps(verdict, indent=2) + "\n")
        suppressed = dedupe_claim_refs(disp.get("value_suppressed") or [])
        return {
            "caseId": case_id,
            "freshInputCount": 1,
            "macroVerdict": str(macro_path),
            "baselineLab": str(baseline),
            "candidateLab": str(replay_dir),
            "bundleTag": variant_label,
            "deliverableOutcome": row.get("deliverableOutcome"),
            "verdict": "hold",
            "valueSuppressedCount": len(suppressed),
            "writerSkillId": skill_id,
            "replayedAt": datetime.now(timezone.utc).isoformat(),
            "deliverableProvisional": True,
        }

    compose = subprocess.run(
        [
            sys.executable,
            str(SCRIPT / "compose.py"),
            str(baseline),
            str(replay_dir),
            "--suite",
            "bug_hunt_necessity_v1",
            "--macro-operation",
            "forward_select",
            "--round",
            "1",
            "--added-role",
            "trace_mapper#0",
        ],
        cwd=str(REPO),
        text=True,
    )
    if compose.returncode != 0:
        raise SystemExit(f"compose failed for {case_id}: {compose.stderr}")

    macro_path = replay_dir / "evaluation" / "macro-verdict.json"
    verdict = json.loads(macro_path.read_text())
    suppressed = (verdict.get("writerDisposition") or {}).get("value_suppressed") or []
    out_row = {
        "caseId": case_id,
        "freshInputCount": 1,
        "macroVerdict": str(macro_path),
        "baselineLab": str(baseline),
        "candidateLab": str(replay_dir),
        "bundleTag": variant_label,
        "deliverableOutcome": verdict.get("deliverableOutcome"),
        "verdict": verdict.get("verdict"),
        "valueSuppressedCount": len(suppressed),
        "writerSkillId": skill_id,
        "replayedAt": datetime.now(timezone.utc).isoformat(),
    }
    return out_row


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--manifest", type=Path, default=REPO / ".lab/macro-evidence/manifest.jsonl")
    p.add_argument("--skill-id", default="bug_packet_writer_v2")
    p.add_argument("--variant-label", default="writer_v2")
    p.add_argument("--evidence-manifest", type=Path, help="append replay rows here")
    p.add_argument("--case", action="append", dest="cases", help="limit to case id(s)")
    p.add_argument("--timeout-seconds", type=int, default=900)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--skip-compose", action="store_true", help="writer only; use refresh_macro_suppression after")
    args = p.parse_args()

    rows = load_manifest(args.manifest.resolve())
    if args.cases:
        want = set(args.cases)
        rows = [r for r in rows if r.get("caseId") in want]
    if not rows:
        raise SystemExit("no manifest rows matched")

    evidence = args.evidence_manifest or (
        REPO / ".lab/macro-evidence" / f"manifest_{args.variant_label}.jsonl"
    )
    results = []
    for row in rows:
        results.append(
            replay_case(
                row=row,
                skill_id=args.skill_id,
                variant_label=args.variant_label,
                timeout_s=args.timeout_seconds,
                dry_run=args.dry_run,
                skip_compose=args.skip_compose,
            )
        )
        if not args.dry_run:
            append_manifest(evidence, results[-1])
            print(json.dumps(results[-1], indent=2))

    if not args.dry_run and len(results) == len(rows):
        if args.skip_compose:
            print(json.dumps({"cases": len(results), "rollup": "skipped (provisional deliverable)"}))
            return 0
        rollup = subprocess.run(
            [
                sys.executable,
                str(SCRIPT / "macro_rollup.py"),
                "--manifest",
                str(evidence),
                "--suite",
                "bug_hunt_necessity_v1",
                "--added-role",
                "trace_mapper#0",
                "--out",
                str(REPO / ".lab/macro-evidence" / f"rollup_{args.variant_label}.json"),
            ],
            cwd=str(REPO),
        )
        return rollup.returncode
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
