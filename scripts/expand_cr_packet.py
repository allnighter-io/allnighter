#!/usr/bin/env python3
"""Expand a code-review WorkSlicePacket with inlined sources, auto symbols, and mode.

Usage:
  scripts/expand_cr_packet.py <repo-root> <packet.json> [output.json]
  scripts/expand_cr_packet.py --verify <repo-root> <review.expanded.json> [output.json]

Review expansion:
  - reads readPaths, inlines content, sets mode=review
  - auto-generates resolvedSymbols from Swift source (drops hand-authored stubs)

Verify expansion (after review findings exist):
  - copies review inlinedSources + inlinedFindings
  - sets mode=reviewVerify, sliceId CR-NN-verify, touch findings/CR-NN-verified.md
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SWIFT_SYMBOL_RE = re.compile(
    r"^(?:(?:public|private|fileprivate|internal|open)\s+)*"
    r"(?:(?:static)\s+)?"
    r"(?:func|actor|class|struct|enum|protocol|var|let)\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)"
    r"(?:\s*\([^)]*\))?"
    r"(?:\s*->\s*[^{]+)?",
    re.MULTILINE,
)

SWIFT_FUNC_RE = re.compile(
    r"^\s*(?:(?:public|private|fileprivate|internal|open)\s+)*"
    r"(?:(?:static)\s+)?func\s+"
    r"([A-Za-z_][A-Za-z0-9_]*)"
    r"\s*(\([^)]*\))"
    r"(?:\s*->\s*([^{;]+))?",
    re.MULTILINE,
)


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


def line_number_at(content: str, index: int, line_offset: int = 1) -> int:
    return content[:index].count("\n") + line_offset


def extract_swift_symbols(content: str, file_path: str, line_offset: int = 1) -> list[dict]:
    symbols: list[dict] = []
    seen: set[str] = set()
    base = Path(file_path).name
    for match in SWIFT_FUNC_RE.finditer(content):
        name = match.group(1)
        if name in seen:
            continue
        seen.add(name)
        params = (match.group(2) or "").strip()
        ret = (match.group(3) or "").strip()
        sig = f"func {name}{params}"
        if ret:
            sig += f" -> {ret}"
        line = line_number_at(content, match.start(), line_offset)
        symbols.append(
            {
                "name": name,
                "signature": sig.strip(),
                "definedAt": f"{base}:{line}",
            }
        )
    return symbols[:24]


def inline_sources(repo_root: Path, packet: dict) -> list[dict]:
    inlined: list[dict] = []
    for anchor in packet.get("readPaths") or []:
        path = anchor["path"]
        line_range = anchor.get("lineRange")
        content = read_chunk(repo_root, path, line_range)
        inlined.append({"path": path, "lineRange": line_range, "content": content})
    return inlined


def auto_resolved_symbols(inlined: list[dict]) -> list[dict]:
    out: list[dict] = []
    seen: set[str] = set()
    for source in inlined:
        if not source["path"].endswith(".swift"):
            continue
        bounds = parse_line_range(source.get("lineRange"))
        offset = bounds[0] if bounds else 1
        for sym in extract_swift_symbols(source["content"], source["path"], offset):
            if sym["name"] in seen:
                continue
            seen.add(sym["name"])
            out.append(sym)
    return out


def expand_review(repo_root: Path, packet: dict) -> dict:
    out = dict(packet)
    out["mode"] = "review"
    inlined = inline_sources(repo_root, out)
    out["inlinedSources"] = inlined
    out["resolvedSymbols"] = auto_resolved_symbols(inlined)
    return out


def review_id_from_slice(slice_id: str) -> str:
    return slice_id.replace("-verify", "")


def expand_verify(repo_root: Path, review_expanded: dict) -> dict:
    base_id = review_id_from_slice(review_expanded.get("sliceId", "CR-00"))
    findings_rel = f"docs/phases/code_review/findings/{base_id}.md"
    findings_path = repo_root / findings_rel
    if not findings_path.is_file():
        raise FileNotFoundError(f"findings required for verify: {findings_rel}")

    verified_rel = f"docs/phases/code_review/findings/{base_id}-verified.md"
    out = {
        "schemaVersion": review_expanded.get("schemaVersion", 1),
        "sliceId": f"{base_id}-verify",
        "title": f"Verify {review_expanded.get('title', base_id)}",
        "readPaths": review_expanded.get("readPaths", []),
        "intent": (
            "ADVERSARIAL VERIFY. Default every P0 in findings to REJECT unless upheld in "
            "inlined source. Reject claims that require actor suspension not present in code."
        ),
        "touchAllowlist": [verified_rel],
        "check": {
            "method": "command",
            "command": (
                f"test -f {verified_rel} && "
                f"grep -qi '## P0 adjudication' {verified_rel}"
            ),
        },
        "maxRetries": 1,
        "stallTimeoutSeconds": review_expanded.get("stallTimeoutSeconds", 900),
        "compactionGraceSeconds": review_expanded.get("compactionGraceSeconds", 300),
        "dangerFlags": [],
        "mode": "reviewVerify",
        "inlinedSources": review_expanded.get("inlinedSources") or inline_sources(repo_root, review_expanded),
        "inlinedFindings": findings_path.read_text(encoding="utf-8"),
        "resolvedSymbols": review_expanded.get("resolvedSymbols") or auto_resolved_symbols(
            review_expanded.get("inlinedSources") or []
        ),
    }
    return out


def main() -> int:
    args = sys.argv[1:]
    verify = False
    if args and args[0] == "--verify":
        verify = True
        args = args[1:]
    if len(args) < 2:
        print(__doc__, file=sys.stderr)
        return 2

    repo_root = Path(args[0]).resolve()
    packet_path = Path(args[1]).resolve()
    if len(args) > 2:
        out_path = Path(args[2]).resolve()
    else:
        stem = packet_path.stem.replace(".expanded", "")
        suffix = ".verify.expanded.json" if verify else ".expanded.json"
        out_path = packet_path.with_name(stem + suffix)

    packet = json.loads(packet_path.read_text(encoding="utf-8"))
    expanded = expand_verify(repo_root, packet) if verify else expand_review(repo_root, packet)
    out_path.write_text(json.dumps(expanded, indent=2) + "\n", encoding="utf-8")

    sym_count = len(expanded.get("resolvedSymbols") or [])
    src_count = len(expanded.get("inlinedSources") or [])
    total_chars = sum(len(s["content"]) for s in expanded.get("inlinedSources") or [])
    try:
        rel = out_path.relative_to(repo_root)
    except ValueError:
        rel = out_path
    print(
        f"wrote {rel} "
        f"({src_count} sources, {sym_count} symbols, {total_chars:,} chars, mode={expanded.get('mode')})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
