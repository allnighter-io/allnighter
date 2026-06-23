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


def run_cmd(argv: list[str], *, env: dict | None = None) -> str:
    print(f"+ {' '.join(argv)}", flush=True)
    proc = subprocess.run(argv, cwd=str(REPO), env=env, text=True, capture_output=True)
    if proc.stdout:
        print(proc.stdout, end="", flush=True)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr, end="", flush=True)
        raise SystemExit(proc.returncode)
    return proc.stdout


def parse_lab_dir(output: str) -> Path:
    for line in output.splitlines():
        if line.startswith("LAB_DIR="):
            return Path(line.split("=", 1)[1].strip())
    raise SystemExit("run.py did not print LAB_DIR=")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--suite", required=True)
    p.add_argument("--case", required=True)
    p.add_argument("--baseline-overlay", type=Path, required=True)
    p.add_argument("--donor-overlay", type=Path, required=True)
    p.add_argument("--add-role", action="append", required=True, dest="add_roles")
    p.add_argument("--round", type=int, default=1)
    p.add_argument("--skip-runs", action="store_true", help="only build overlay; use with existing lab dirs")
    p.add_argument("--baseline-lab", type=Path)
    p.add_argument("--candidate-lab", type=Path)
    p.add_argument("--mock-compose", action="store_true")
    p.add_argument("--auto-promote", action="store_true")
    p.add_argument("--fresh-input-count", type=int, default=3)
    args = p.parse_args()

    sys.path.insert(0, str(SCRIPTS))
    from macro_overlay import forward_add_overlay, write_overlay  # noqa: E402

    suite_id = args.suite
    base = json.loads(args.baseline_overlay.read_text())
    donor = json.loads(args.donor_overlay.read_text())
    cand_team = f"{base.get('teamId', 'team')}_plus_{args.add_roles[0].split('#')[0]}"
    overlay = forward_add_overlay(base, donor, args.add_roles, round_no=args.round, suite_id=suite_id)
    overlay["teamId"] = cand_team
    overlay["labTeamId"] = f"lab_{cand_team}_r{args.round}"

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
            f"genesis-{roster_id}",
            "--champion-overlay",
            str(args.baseline_overlay),
            "--record-genesis",
            "--roster-id",
            roster_id,
        ]
        base_out = run_cmd(base_argv, env=env)
        base_dir = parse_lab_dir(base_out)

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
            f"macro-{cand_team}",
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
        str(args.fresh_input_count),
        "--added-role",
        *args.add_roles,
    ]
    if args.mock_compose:
        cmp_argv.append("--mock")
    cmp_out = run_cmd(cmp_argv, env=env)
    print(cmp_out, flush=True)

    macro_path = cand_dir / "evaluation" / "macro-verdict.json"
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
