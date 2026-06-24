#!/usr/bin/env python3
"""Refresh VNRC + writerDisposition on existing macro-verdict rows (no judge re-run)."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from macro_schema import dedupe_claim_refs, infer_writer_disposition, vnrc_delta_from_labs  # noqa: E402

REPO = Path(__file__).resolve().parents[2]


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
        macro_path = Path(row.get("macroVerdict") or (cand / "evaluation/macro-verdict.json"))
        if not macro_path.is_absolute():
            macro_path = (REPO / macro_path).resolve()
        verdict = json.loads(macro_path.read_text())
        added = (verdict.get("arm") or {}).get("addedRoles") or ["trace_mapper#0"]
        vnrc = vnrc_delta_from_labs(base, cand)
        disp = infer_writer_disposition(base, cand, added_roles=added)
        verdict["vnrcDelta"] = vnrc
        verdict["writerDisposition"] = disp
        # Write sidecar so original macro-verdict stays untouched
        sidecar = cand / "evaluation" / f"macro-verdict-{args.bundle_tag}.json"
        sidecar.write_text(json.dumps(verdict, indent=2) + "\n")

        suppressed = dedupe_claim_refs(disp.get("value_suppressed") or [])
        out = {
            **row,
            "macroVerdict": str(sidecar),
            "bundleTag": args.bundle_tag,
            "valueSuppressedCount": len(suppressed),
            "vnrcCandidateOnly": len(vnrc.get("candidateOnly") or []),
            "refreshedAt": datetime.now(timezone.utc).isoformat(),
        }
        with args.out_manifest.open("a") as f:
            f.write(json.dumps(out) + "\n")
        print(
            f"{row['caseId']}: deliverable={row.get('deliverableOutcome')} "
            f"suppressed={out['valueSuppressedCount']} vnrc_c={out['vnrcCandidateOnly']}"
        )

    import subprocess

    rollup = subprocess.run(
        [
            sys.executable,
            str(REPO / "scripts/team_lab/macro_rollup.py"),
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
