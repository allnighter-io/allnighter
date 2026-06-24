#!/usr/bin/env python3
"""Sample suppressed claims vs writer plan — path-variant audit.

    python3 scripts/team_lab/audit_suppression.py <candidate_lab> [<baseline_lab>]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from macro_schema import (  # noqa: E402
    claim_carried_in_plan,
    claim_dedupe_key,
    dedupe_claim_refs,
    infer_writer_disposition,
    normalize_claim_ref,
    plan_claims,
    vnrc_delta_from_labs,
)

REPO = Path(__file__).resolve().parents[2]


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("candidate_lab", type=Path)
    p.add_argument("baseline_lab", type=Path, nargs="?")
    p.add_argument("--sample", type=int, default=5)
    args = p.parse_args()

    cand = args.candidate_lab.resolve()
    base = args.baseline_lab.resolve() if args.baseline_lab else None
    if base is None:
        exp = json.loads((cand / "experiment.json").read_text())
        case_id = exp.get("caseId", "?")
        macro_path = cand / "evaluation" / "macro-verdict.json"
        if macro_path.exists():
            arm = json.loads(macro_path.read_text()).get("arm") or {}
            bl = arm.get("baselineLab")
            if bl:
                base = (REPO / ".lab" / bl).resolve() if not Path(bl).is_absolute() else Path(bl)

    if base is None or not base.exists():
        raise SystemExit("baseline lab not found — pass baseline_lab explicitly")

    disp = infer_writer_disposition(base, cand, added_roles=["trace_mapper#0"])
    suppressed = dedupe_claim_refs(disp["value_suppressed"])
    plan = plan_claims(cand) | plan_claims(base)
    vnrc = vnrc_delta_from_labs(base, cand)

    print(f"candidate={cand.name}")
    print(f"baseline={base.name}")
    print(f"vnrc_candidate_only={len(vnrc['candidateOnly'])} deduped_suppressed={len(suppressed)}")
    print()
    for claim in suppressed[: args.sample]:
        carried = claim_carried_in_plan(claim, plan)
        print(f"{'CARRIED' if carried else 'MISSING':7} {normalize_claim_ref(claim)}")
        if not carried:
            tr = json.loads((cand / "team-result.json").read_text())
            md = (tr.get("plan") or {}).get("markdown") or ""
            bn = Path(claim.rsplit(":", 1)[0]).name
            if bn in md:
                print(f"        note: basename {bn!r} appears in plan prose (possible line mismatch)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
