#!/usr/bin/env python3
"""Compute safe parallel batches for code-review fan-out (PM rule: disjoint touch only).

Usage:
  scripts/cr_parallel_plan.py docs/phases/code_review/packets/CR-01.json ...

Prints JSON: { "safe": true, "violations": [], "batches": [["CR-01", "CR-02"], ...] }
Exit 1 if any packet violates findings-scoped touch rules.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

FINDINGS_PREFIX = "docs/phases/code_review/findings/"
MAX_CONCURRENT = 4


def load_surface(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    return {
        "sliceId": data.get("sliceId", path.stem),
        "touchAllowlist": data.get("touchAllowlist") or [],
        "readPaths": [a.get("path", "") for a in data.get("readPaths") or []],
    }


def violations(packets: list[dict]) -> list[str]:
    out: list[str] = []
    if len(packets) > MAX_CONCURRENT:
        out.append(f"batch size {len(packets)} exceeds max {MAX_CONCURRENT}")
    ids = [p["sliceId"] for p in packets]
    if len(ids) != len(set(ids)):
        out.append("duplicate sliceId in batch")
    for p in packets:
        if not p["touchAllowlist"]:
            out.append(f"{p['sliceId']}: empty touchAllowlist")
        for touch in p["touchAllowlist"]:
            norm = touch.replace("\\", "/")
            if not norm.startswith(FINDINGS_PREFIX) or norm.endswith("/"):
                out.append(f"{p['sliceId']}: touch outside findings: {touch}")
    for i, a in enumerate(packets):
        for b in packets[i + 1 :]:
            overlap = set(a["touchAllowlist"]).intersection(b["touchAllowlist"])
            if overlap:
                out.append(
                    f"touch overlap {a['sliceId']} vs {b['sliceId']}: {sorted(overlap)}"
                )
    return out


def safe_batches(surfaces: list[dict]) -> list[list[str]]:
    remaining = list(surfaces)
    batches: list[list[str]] = []
    while remaining:
        batch: list[dict] = []
        i = 0
        while i < len(remaining) and len(batch) < MAX_CONCURRENT:
            candidate = remaining[i]
            trial = batch + [candidate]
            if not violations(trial):
                batch.append(candidate)
                remaining.pop(i)
            else:
                i += 1
        if not batch and remaining:
            batches.append([remaining.pop(0)["sliceId"]])
        elif batch:
            batches.append([p["sliceId"] for p in batch])
    return batches


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    paths = [Path(p) for p in sys.argv[1:]]
    surfaces = [load_surface(p) for p in paths]
    all_violations: list[str] = []
    for p in surfaces:
        all_violations.extend(violations([p]))
    batches = safe_batches(surfaces)
    for batch in batches:
        batch_packets = [s for s in surfaces if s["sliceId"] in batch]
        all_violations.extend(violations(batch_packets))
    result = {
        "safe": len(all_violations) == 0,
        "violations": all_violations,
        "batches": batches,
        "maxConcurrent": MAX_CONCURRENT,
    }
    print(json.dumps(result, indent=2))
    return 0 if result["safe"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
