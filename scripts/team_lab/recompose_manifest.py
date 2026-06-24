#!/usr/bin/env python3
"""Re-compose macro verdicts for manifest rows (same worker outputs, fresh VNRC/suppression)."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "scripts" / "team_lab"


def resolve(raw: str) -> Path:
    p = Path(raw)
    return (REPO / p).resolve() if not p.is_absolute() else p.resolve()


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--manifest", type=Path, required=True)
    p.add_argument("--out-manifest", type=Path, required=True)
    p.add_argument("--bundle-tag", default="metric_fix")
    args = p.parse_args()

    rows = [json.loads(l) for l in args.manifest.read_text().splitlines() if l.strip()]
    args.out_manifest.parent.mkdir(parents=True, exist_ok=True)
    if args.out_manifest.exists():
        args.out_manifest.unlink()

    for row in rows:
        base, cand = resolve(row["baselineLab"]), resolve(row["candidateLab"])
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPT / "compose.py"),
                str(base),
                str(cand),
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
            capture_output=True,
            text=True,
        )
        if proc.returncode != 0:
            print(proc.stderr, file=sys.stderr)
            raise SystemExit(f"compose failed: {row['caseId']}")
        summary = json.loads(proc.stdout)
        macro_path = cand / "evaluation" / "macro-verdict.json"
        verdict = json.loads(macro_path.read_text())
        suppressed = (verdict.get("writerDisposition") or {}).get("value_suppressed") or []
        out = {
            "caseId": row["caseId"],
            "freshInputCount": 1,
            "macroVerdict": str(macro_path),
            "baselineLab": str(base),
            "candidateLab": str(cand),
            "bundleTag": args.bundle_tag,
            "deliverableOutcome": summary["deliverableOutcome"],
            "verdict": summary["verdict"],
            "valueSuppressedCount": len(suppressed),
            "recomposedAt": datetime.now(timezone.utc).isoformat(),
        }
        with args.out_manifest.open("a") as f:
            f.write(json.dumps(out) + "\n")
        print(json.dumps(out, indent=2))

    rollup = subprocess.run(
        [
            sys.executable,
            str(SCRIPT / "macro_rollup.py"),
            "--manifest",
            str(args.out_manifest),
            "--suite",
            "bug_hunt_necessity_v1",
            "--added-role",
            "trace_mapper#0",
            "--out",
            str(args.out_manifest.parent / f"rollup_{args.bundle_tag}.json"),
        ],
        cwd=str(REPO),
    )
    return rollup.returncode


if __name__ == "__main__":
    raise SystemExit(main())
