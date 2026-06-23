#!/usr/bin/env python3
"""Record genesis baseline outcomes for necessity-suite cases.

    python3 scripts/team_lab/genesis.py record --lab-dir .lab/... \\
        --suite bug_hunt_necessity_v1 --roster-id code_bug_hunt_lite

Also invoked automatically when run.py finishes with --record-genesis.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GENESIS_ROOT = REPO / ".lab/genesis"

sys.path.insert(0, str(Path(__file__).resolve().parent))
from macro_schema import genesis_record_template, write_genesis_record  # noqa: E402


def context_hash(lab_dir: Path) -> str | None:
    exp_path = lab_dir / "experiment.json"
    if not exp_path.exists():
        return None
    exp = json.loads(exp_path.read_text())
    req = exp.get("request") or {}
    body = json.dumps({"prompt": req.get("prompt"), "caseId": exp.get("caseId")}, sort_keys=True)
    return hashlib.sha256(body.encode()).hexdigest()[:16]


def record_from_lab(lab_dir: Path, *, suite_id: str, roster_id: str) -> Path:
    exp_path = lab_dir / "experiment.json"
    if not exp_path.exists():
        raise SystemExit(f"missing experiment.json: {lab_dir}")
    exp = json.loads(exp_path.read_text())
    case_id = exp.get("caseId") or "unknown"
    contract_path = lab_dir / "evaluation" / "run-contract-score.json"
    contract = json.loads(contract_path.read_text()) if contract_path.exists() else {}
    score = contract.get("runContractScore")
    status = (exp.get("run") or {}).get("status")
    run_ok = status == "completed" and score is not None and score >= 0.95 and not contract.get("fsBypass")

    rec = genesis_record_template(case_id, suite_id, roster_id)
    rec["contextHash"] = context_hash(lab_dir)
    rec["outcome"] = "pass" if run_ok else "fail"
    rec["runContractScore"] = score
    rec["terminalStatus"] = status
    rec["fsBypass"] = contract.get("fsBypass")
    rec["labDir"] = lab_dir.name

    out = GENESIS_ROOT / suite_id / f"{case_id}__{roster_id}.json"
    write_genesis_record(out, rec)
    return out


def load_genesis(suite_id: str, case_id: str, roster_id: str) -> dict | None:
    path = GENESIS_ROOT / suite_id / f"{case_id}__{roster_id}.json"
    if not path.exists():
        return None
    return json.loads(path.read_text())


def genesis_failed(suite_id: str, case_id: str, roster_id: str) -> bool:
    rec = load_genesis(suite_id, case_id, roster_id)
    return rec is not None and rec.get("outcome") == "fail"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    rec = sub.add_parser("record", help="write genesis record from completed lab dir")
    rec.add_argument("--lab-dir", type=Path, required=True)
    rec.add_argument("--suite", required=True)
    rec.add_argument("--roster-id", required=True)

    chk = sub.add_parser("check", help="print genesis record if present")
    chk.add_argument("--suite", required=True)
    chk.add_argument("--case", required=True)
    chk.add_argument("--roster-id", required=True)

    args = p.parse_args()
    if args.cmd == "record":
        out = record_from_lab(args.lab_dir, suite_id=args.suite, roster_id=args.roster_id)
        print(f"GENESIS_RECORD={out}")
        print(json.dumps(json.loads(out.read_text()), indent=2))
        return 0
    if args.cmd == "check":
        rec = load_genesis(args.suite, args.case, args.roster_id)
        if not rec:
            print("missing")
            return 1
        print(json.dumps(rec, indent=2))
        return 0
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
