#!/usr/bin/env python3
"""Macro forward-selection round: genesis baseline → add seat → compose → optional promote.

    python3 scripts/team_lab/macro_advance.py \\
        --suite bug_hunt_necessity_v1 \\
        --case floor_show_wrong_run_v1 \\
        --baseline-overlay docs/team-lab/champions/.../code_bug_hunt_lite.json \\
        --donor-overlay docs/team-lab/champions/.../code_bug_hunt.json \\
        --add-role trace_mapper#0 \\
        --round 1 \\
        --mock-compose

Without --skip-runs: runs baseline (lite) then candidate (lite+seat) on the same case.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "scripts/team_lab"
CHAMPIONS = REPO / "docs/team-lab/champions"
CANDIDATES = REPO / "docs/team-lab/candidates"
MACRO_EVIDENCE = REPO / ".lab/macro-evidence"


def run_cmd(argv: list[str], *, env: dict | None = None) -> str:
    print(f"+ {' '.join(argv)}", flush=True)
    proc = subprocess.Popen(
        argv,
        cwd=str(REPO),
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert proc.stdout is not None
    captured: list[str] = []
    for line in proc.stdout:
        print(line, end="", flush=True)
        captured.append(line)
    if proc.wait() != 0:
        raise SystemExit(proc.returncode)
    return "".join(captured)


def parse_lab_dir(output: str) -> Path:
    for line in output.splitlines():
        if line.startswith("LAB_DIR="):
            return Path(line.split("=", 1)[1].strip())
    raise SystemExit("run.py did not print LAB_DIR=")


def resolve_fresh_input_count(explicit: int | None, *, cases_run: int, case_id: str) -> int:
    """Distinct necessity inputs for macro gate — not run count (A/B arms share one case)."""
    fresh = cases_run if explicit is None else explicit
    if fresh > cases_run:
        raise SystemExit(
            f"--fresh-input-count {fresh} exceeds cases run ({cases_run} for --case {case_id!r}); "
            "do not inflate the macro gate"
        )
    return fresh


def append_macro_evidence(
    *,
    case_id: str,
    macro_path: Path,
    baseline_lab: Path,
    candidate_lab: Path,
    fresh_input_count: int,
    manifest_path: Path | None = None,
    bundle_tag: str | None = None,
) -> None:
    """Append durable pointer to macro verdict artifacts (promotion evidence set)."""
    MACRO_EVIDENCE.mkdir(parents=True, exist_ok=True)
    manifest = manifest_path or (MACRO_EVIDENCE / "manifest.jsonl")
    record = {
        "caseId": case_id,
        "freshInputCount": fresh_input_count,
        "macroVerdict": str(macro_path),
        "baselineLab": str(baseline_lab),
        "candidateLab": str(candidate_lab),
    }
    if bundle_tag:
        record["bundleTag"] = bundle_tag
    if macro_path.exists():
        verdict = json.loads(macro_path.read_text())
        record.update(
            {
                "deliverableOutcome": verdict.get("deliverableOutcome"),
                "verdict": verdict.get("verdict"),
                "valueSuppressedCount": len(
                    (verdict.get("writerDisposition") or {}).get("value_suppressed") or []
                ),
                "candidatePreflightFallbacks": (verdict.get("preflightFallbacks") or {}).get(
                    "candidate"
                )
                or [],
            }
        )
    with manifest.open("a") as f:
        f.write(json.dumps(record) + "\n")
    print(f"MACRO_EVIDENCE={manifest}", flush=True)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--suite", required=True)
    p.add_argument("--case", required=True)
    p.add_argument("--baseline-overlay", type=Path, required=True)
    p.add_argument("--donor-overlay", type=Path, required=True)
    p.add_argument("--add-role", action="append", required=True, dest="add_roles")
    p.add_argument("--round", type=int, default=1)
    p.add_argument("--skip-runs", action="store_true", help="only build overlay; use with existing lab dirs")
    p.add_argument(
        "--baseline-lab",
        type=Path,
        help="reuse completed baseline lab dir (skips baseline run; e.g. genesis record dir)",
    )
    p.add_argument("--candidate-lab", type=Path, help="reuse completed candidate lab dir (skips candidate run)")
    p.add_argument("--mock-compose", action="store_true")
    p.add_argument("--auto-promote", action="store_true")
    p.add_argument(
        "--fresh-input-count",
        type=int,
        default=None,
        help="distinct necessity inputs exercised this round (default: 1 — one --case, two rosters)",
    )
    p.add_argument(
        "--evidence-manifest",
        type=Path,
        help="append macro evidence to this manifest (default: .lab/macro-evidence/manifest.jsonl)",
    )
    p.add_argument("--bundle-tag", help="tag recorded on manifest row (e.g. hardened_writer_v1)")
    args = p.parse_args()

    cases_run = 1  # macro_advance runs a single --case today (A/B arms share that input)
    fresh_input_count = resolve_fresh_input_count(
        args.fresh_input_count, cases_run=cases_run, case_id=args.case
    )

    sys.path.insert(0, str(SCRIPTS))
    from macro_overlay import forward_add_overlay, write_overlay  # noqa: E402

    suite_id = args.suite
    base = json.loads(args.baseline_overlay.read_text())
    donor = json.loads(args.donor_overlay.read_text())
    cand_team = f"{base.get('teamId', 'team')}_plus_{args.add_roles[0].split('#')[0]}"
    overlay = forward_add_overlay(base, donor, args.add_roles, round_no=args.round, suite_id=suite_id)
    overlay["teamId"] = cand_team
    overlay["labTeamId"] = f"lab_{cand_team}_r{args.round}_candidate"

    suite_dir = args.baseline_overlay.parent
    if suite_dir.name != suite_id.split("_v")[0] and "bug_hunt" in str(suite_dir):
        suite_dir = CHAMPIONS / suite_id.replace("_v1", "").replace("bug_hunt_necessity", "bug_hunt_repo_regressions_v1")
    cand_overlay_path = CANDIDATES / suite_id / f"{cand_team}_r{args.round}.json"
    if not cand_overlay_path.parent.exists():
        cand_overlay_path = args.baseline_overlay.parent / f"{cand_team}.json"
    write_overlay(cand_overlay_path, overlay)
    print(f"CANDIDATE_OVERLAY={cand_overlay_path}", flush=True)

    env = os.environ.copy()
    roster_id = base.get("teamId", "baseline")

    if args.skip_runs:
        if not args.baseline_lab or not args.candidate_lab:
            raise SystemExit("--skip-runs requires --baseline-lab and --candidate-lab")
        base_dir, cand_dir = args.baseline_lab, args.candidate_lab
    else:
        if args.baseline_lab:
            base_dir = args.baseline_lab.resolve()
            if not base_dir.is_dir():
                raise SystemExit(f"--baseline-lab not found: {base_dir}")
            print(f"BASELINE_LAB={base_dir}", flush=True)
        else:
            base_argv = [
                sys.executable,
                str(SCRIPTS / "run.py"),
                "--suite",
                args.suite,
                "--case",
                args.case,
                "--round",
                str(args.round),
                "--variant",
                f"genesis-{roster_id}-r{args.round}",
                "--champion-overlay",
                str(args.baseline_overlay),
                "--record-genesis",
                "--roster-id",
                roster_id,
            ]
            base_out = run_cmd(base_argv, env=env)
            base_dir = parse_lab_dir(base_out)

        if args.candidate_lab:
            cand_dir = args.candidate_lab.resolve()
            if not cand_dir.is_dir():
                raise SystemExit(f"--candidate-lab not found: {cand_dir}")
            print(f"CANDIDATE_LAB={cand_dir}", flush=True)
        else:
            cand_argv = [
                sys.executable,
                str(SCRIPTS / "run.py"),
                "--suite",
                args.suite,
                "--case",
                args.case,
                "--round",
                str(args.round),
                "--variant",
                f"macro-{cand_team}-r{args.round}",
                "--candidate-overlay",
                str(cand_overlay_path),
            ]
            cand_out = run_cmd(cand_argv, env=env)
            cand_dir = parse_lab_dir(cand_out)

    for d in (base_dir, cand_dir):
        run_cmd([sys.executable, str(SCRIPTS / "evaluate.py"), str(d), "--rescore-contract"], env=env)

    cmp_argv = [
        sys.executable,
        str(SCRIPTS / "compose.py"),
        str(base_dir),
        str(cand_dir),
        "--suite",
        args.suite,
        "--macro-operation",
        "forward_select",
        "--round",
        str(fresh_input_count),
        "--added-role",
        *args.add_roles,
    ]
    if args.mock_compose:
        cmp_argv.append("--mock")
    cmp_out = run_cmd(cmp_argv, env=env)
    print(cmp_out, flush=True)

    macro_path = cand_dir / "evaluation" / "macro-verdict.json"
    append_macro_evidence(
        case_id=args.case,
        macro_path=macro_path,
        baseline_lab=base_dir,
        candidate_lab=cand_dir,
        fresh_input_count=fresh_input_count,
        manifest_path=args.evidence_manifest,
        bundle_tag=args.bundle_tag,
    )
    if args.auto_promote:
        promo_argv = [
            sys.executable,
            str(SCRIPTS / "promote.py"),
            "--macro-verdict",
            str(macro_path),
            "--baseline-overlay",
            str(args.baseline_overlay),
            "--candidate-overlay",
            str(cand_overlay_path),
            "--baseline-lab",
            str(base_dir),
            "--candidate-lab",
            str(cand_dir),
            "--suite",
            suite_id.replace("necessity", "repo_regressions") if "necessity" in suite_id else suite_id,
            "--team",
            cand_team,
            "--round",
            str(args.round + 1),
        ]
        run_cmd(promo_argv, env=env)

    print(
        json.dumps(
            {
                "baselineLab": str(base_dir),
                "candidateLab": str(cand_dir),
                "candidateOverlay": str(cand_overlay_path),
                "macroVerdict": str(macro_path),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
