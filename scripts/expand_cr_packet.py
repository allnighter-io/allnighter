#!/usr/bin/env python3
"""Expand a code-review WorkSlicePacket with inlined sources and mode=review.

Usage:
  scripts/expand_cr_packet.py <repo-root> <packet.json> [output.json]

Reads each readPaths entry from the repo, applies optional lineRange (1-based inclusive
"start-end"), sets mode=review + inlinedSources, and writes the expanded packet.

Typical flow:
  scripts/expand_cr_packet.py . docs/phases/code_review/packets/CR-01.json
  alln pair slice docs/phases/code_review/packets/CR-01.expanded.json --project Allnighter
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def parse_line_range(raw: str | None) -> tuple[int, int] | None:
    if not raw or not str(raw).strip():
        return None
    parts = str(raw).split("-", 1)
    if len(parts) != 2:
        raise ValueError(f"lineRange must be start-end, got: {raw!r}")
    start, end = int(parts[0]), int(parts[1])
    if start < 1 or end < start:
        raise ValueError(f"invalid lineRange: {raw!r}")
    return start, end


def read_chunk(repo_root: Path, rel_path: str, line_range: str | None) -> str:
    full = (repo_root / rel_path).resolve()
    if not full.is_file():
        raise FileNotFoundError(f"readPaths target missing: {rel_path} ({full})")
    text = full.read_text(encoding="utf-8")
    bounds = parse_line_range(line_range)
    if bounds is None:
        return text
    start, end = bounds
    lines = text.splitlines()
    if end > len(lines):
        raise ValueError(f"{rel_path} lineRange {start}-{end} exceeds file length {len(lines)}")
    return "\n".join(lines[start - 1 : end])


def expand_packet(repo_root: Path, packet: dict) -> dict:
    out = dict(packet)
    out["mode"] = "review"
    inlined: list[dict] = []
    for anchor in out.get("readPaths") or []:
        path = anchor["path"]
        line_range = anchor.get("lineRange")
        content = read_chunk(repo_root, path, line_range)
        inlined.append(
            {
                "path": path,
                "lineRange": line_range,
                "content": content,
            }
        )
    out["inlinedSources"] = inlined
    return out


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    repo_root = Path(sys.argv[1]).resolve()
    packet_path = Path(sys.argv[2]).resolve()
    if len(sys.argv) > 3:
        out_path = Path(sys.argv[3]).resolve()
    else:
        out_path = packet_path.with_name(packet_path.stem + ".expanded.json")

    packet = json.loads(packet_path.read_text(encoding="utf-8"))
    expanded = expand_packet(repo_root, packet)
    out_path.write_text(json.dumps(expanded, indent=2) + "\n", encoding="utf-8")
    total_chars = sum(len(s["content"]) for s in expanded.get("inlinedSources", []))
    print(f"wrote {out_path.relative_to(repo_root)} ({len(expanded.get('inlinedSources', []))} sources, {total_chars:,} chars)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
