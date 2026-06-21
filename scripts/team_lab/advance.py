#!/usr/bin/env python3
"""One full lab round: fresh scenario → champion vs material candidate → compare → auto-promote.

    python3 scripts/team_lab/advance.py \\
        --suite bug_hunt_repo_regressions_v1 \\
        --team code_bug_hunt \\
        --round 4 \\
        --champion-overlay docs/team-lab/champions/.../code_bug_hunt.json \\
        --hypotheses-from .lab/.../compare-record.json

Refuses to run a quality-learning round without a material candidate delta.
Use --calibration-smoke only for automation/calibration (no promotion).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPTS = REPO / "scripts/team_lab"
CANDIDATES_DIR = REPO / "docs/team-lab/candidates"


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
    p.add_argument("--team", required=True)
    p.add_argument("--round", type=int, required=True)
    p.add_argument("--champion-overlay", type=Path, required=True)
    p.add_argument("--candidate-overlay", type=Path, help="explicit candidate overlay JSON")
    p.add_argument(
        "--hypotheses-from",
        type=Path,
        help="prior compare-record.json — builds candidate overlay with hypothesis patches",
    )
    p.add_argument("--case-json", type=Path, help="reuse case; default generate fresh via scenario.py")
    p.add_argument("--mock-judges", action="store_true")
    p.add_argument("--skip-compare", action="store_true")
    p.add_argument("--auto-promote-next", action="store_true", default=True)
    p.add_argument("--no-auto-promote-next", action="store_false", dest="auto_promote_next")
    p.add_argument(
        "--calibration-smoke",
        action="store_true",
        help="allow identical configs for automation smoke only (no promotion)",
    )
    args = p.parse_args()

    if args.calibration_smoke and args.hypotheses_from:
        raise SystemExit("use either --calibration-smoke or --hypotheses-from, not both")

    env = os.environ.copy()

    if args.case_json:
        case_path = args.case_json
    else:
        gen_argv = [sys.executable, str(SCRIPTS / "scenario.py"), args.suite]
        if args.mock_judges:
            gen_argv.append("--mock")
        case_json = run_cmd(gen_argv, env=env)
        case = json.loads(case_json)
        fd, tmp = tempfile.mkstemp(prefix=f"team-lab-r{args.round}-", suffix=".json")
        os.close(fd)
        case_path = Path(tmp)
        case_path.write_text(json.dumps(case, indent=2))
        print(f"CASE_JSON={case_path}", flush=True)

    champ_argv = [
        sys.executable,
        str(SCRIPTS / "run.py"),
        "--suite",
        args.suite,
        "--round",
        str(args.round),
        "--variant",
        f"champion-r{args.round}",
        "--champion-overlay",
        str(args.champion_overlay),
        "--case-json",
        str(case_path),
    ]
    champ_out = run_cmd(champ_argv, env=env)
    champ_dir = parse_lab_dir(champ_out)

    if args.candidate_overlay:
        cand_overlay_path = args.candidate_overlay
    elif args.hypotheses_from:
        sys.path.insert(0, str(SCRIPTS))
        from candidate_overlay import build_candidate_overlay, write_candidate_overlay  # noqa: E402

        champion = json.loads(args.champion_overlay.read_text())
        compare_record = json.loads(args.hypotheses_from.read_text())
        compare_record["_path"] = str(args.hypotheses_from)
        cand_overlay = build_candidate_overlay(
            champion, compare_record=compare_record, round_no=args.round
        )
        cand_overlay_path = CANDIDATES_DIR / args.suite / f"{args.team}_r{args.round}.json"
        write_candidate_overlay(cand_overlay_path, cand_overlay)
        print(f"CANDIDATE_OVERLAY={cand_overlay_path}", flush=True)
    elif args.calibration_smoke:
        cand_overlay_path = None
    else:
        raise SystemExit(
            "quality-learning round requires --hypotheses-from or --candidate-overlay "
            "(or --calibration-smoke for automation-only)"
        )

    if cand_overlay_path:
        cand_argv = [
            sys.executable,
            str(SCRIPTS / "run.py"),
            "--suite",
            args.suite,
            "--round",
            str(args.round),
            "--variant",
            f"candidate-r{args.round}",
            "--candidate-overlay",
            str(cand_overlay_path),
            "--case-json",
            str(case_path),
        ]
    else:
        cand_argv = [
            sys.executable,
            str(SCRIPTS / "run.py"),
            "--suite",
            args.suite,
            "--team",
            args.team,
            "--round",
            str(args.round),
            "--variant",
            f"candidate-r{args.round}",
            "--case-json",
            str(case_path),
        ]
    cand_out = run_cmd(cand_argv, env=env)
    cand_dir = parse_lab_dir(cand_out)

    for d in (champ_dir, cand_dir):
        run_cmd([sys.executable, str(SCRIPTS / "evaluate.py"), str(d), "--rescore-contract"], env=env)

    if args.skip_compare:
        print(json.dumps({"champion": str(champ_dir), "candidate": str(cand_dir)}, indent=2))
        return 0

    cmp_argv = [
        sys.executable,
        str(SCRIPTS / "compare.py"),
        str(champ_dir),
        str(cand_dir),
        "--hypotheses",
    ]
    if args.mock_judges:
        cmp_argv.append("--mock")
    cmp_out = run_cmd(cmp_argv, env=env)
    print(cmp_out, flush=True)

    compare_record_path = cand_dir / "evaluation" / "compare-record.json"
    compare_record = json.loads(compare_record_path.read_text())

    if args.calibration_smoke:
        print("CALIBRATION_SMOKE: promotion skipped", flush=True)
        return 0

    if not compare_record.get("materialCandidateDelta"):
        print("HOLD: no material candidate delta — not a quality-learning round", file=sys.stderr)
        return 3

    if args.auto_promote_next:
        check = subprocess.run(
            [
                sys.executable,
                str(SCRIPTS / "promote.py"),
                "--compare-record",
                str(compare_record_path),
                "--baseline-lab",
                str(champ_dir),
                "--candidate-lab",
                str(cand_dir),
                "--suite",
                args.suite,
                "--team",
                args.team,
                "--round",
                str(args.round + 1),
                "--check-only",
            ],
            cwd=str(REPO),
            text=True,
            capture_output=True,
        )
        gate = json.loads(check.stdout or "{}")
        if gate.get("verdict") == "promote":
            run_cmd(
                [
                    sys.executable,
                    str(SCRIPTS / "promote.py"),
                    "--compare-record",
                    str(compare_record_path),
                    "--baseline-lab",
                    str(champ_dir),
                    "--candidate-lab",
                    str(cand_dir),
                    "--suite",
                    args.suite,
                    "--team",
                    args.team,
                    "--round",
                    str(args.round + 1),
                ],
                env=env,
            )
        elif gate.get("verdict") == "escalate":
            print(f"ESCALATE: {gate.get('reason')}", file=sys.stderr)
            return 2
        else:
            print(f"HOLD: {gate.get('reason')} — no promotion", flush=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
