#!/usr/bin/env python3
"""Merge workspace-git into ~/.codex/config.toml and strip legacy sandbox blocks."""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FRAGMENT = ROOT / "scripts" / "codex-workspace-git.fragment.toml"
CODEX_HOME = Path.home() / ".codex"
CONFIG_PATH = CODEX_HOME / "config.toml"
MIN_CODEX_VERSION = (0, 138, 0)


def parse_version(raw: str) -> tuple[int, int, int] | None:
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", raw)
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def codex_version() -> tuple[int, int, int] | None:
    codex = shutil.which("codex")
    if not codex:
        return None
    try:
        proc = subprocess.run(
            [codex, "--version"],
            check=False,
            capture_output=True,
            text=True,
        )
    except OSError:
        return None
    return parse_version(proc.stdout + proc.stderr)


def remove_toml_section(text: str, section: str) -> str:
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    skipping = False
    header = f"[{section}]"
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            skipping = stripped == header
        if not skipping:
            out.append(line)
    return "".join(out)


def strip_legacy_sandbox(text: str) -> str:
    text = remove_toml_section(text, "sandbox_workspace_write")
    text = re.sub(r"^sandbox_mode\s*=.*\n", "", text, flags=re.MULTILINE)
    text = text.replace(
        '[permissions.workspace-git.filesystem.":project_roots"]',
        '[permissions.workspace-git.filesystem.":workspace_roots"]',
    )
    text = text.replace('.git/hooks" = "none"', '.git/hooks" = "deny"')
    return text


def has_workspace_git_profile(text: str) -> bool:
    return "[permissions.workspace-git.filesystem]" in text


def ensure_default_permissions(text: str, *, migrated_legacy: bool) -> str:
    has_default = bool(re.search(r"^default_permissions\s*=", text, flags=re.MULTILINE))
    if has_default and not migrated_legacy:
        return text
    if has_default:
        return re.sub(
            r'^default_permissions\s*=.*$',
            'default_permissions = "workspace-git"',
            text,
            count=1,
            flags=re.MULTILINE,
        )
    fragment = FRAGMENT.read_text(encoding="utf-8")
    default_line = 'default_permissions = "workspace-git"'
    for line in fragment.splitlines():
        if line.startswith("default_permissions"):
            default_line = line
            break
    return f"{default_line}\n\n{text}"


def merge_fragment(text: str) -> str:
    if has_workspace_git_profile(text):
        return text
    fragment = FRAGMENT.read_text(encoding="utf-8")
    profile_lines = [
        line
        for line in fragment.splitlines(keepends=True)
        if not line.startswith("default_permissions")
        and not line.startswith("#")
        and line.strip()
    ]
    if text and not text.endswith("\n"):
        text += "\n"
    return text + "\n" + "".join(profile_lines)


def main() -> int:
    version = codex_version()
    if version is None:
        print("error: codex not found on PATH", file=sys.stderr)
        return 1
    if version < MIN_CODEX_VERSION:
        print(
            f"error: codex {version[0]}.{version[1]}.{version[2]} is too old; "
            f"need >= {MIN_CODEX_VERSION[0]}.{MIN_CODEX_VERSION[1]}.{MIN_CODEX_VERSION[2]}",
            file=sys.stderr,
        )
        print("hint: brew upgrade codex", file=sys.stderr)
        return 1

    if not FRAGMENT.is_file():
        print(f"error: missing fragment: {FRAGMENT}", file=sys.stderr)
        return 1

    CODEX_HOME.mkdir(parents=True, exist_ok=True)
    original = CONFIG_PATH.read_text(encoding="utf-8") if CONFIG_PATH.exists() else ""
    migrated_legacy = (
        "[sandbox_workspace_write]" in original
        or bool(re.search(r"^sandbox_mode\s*=", original, flags=re.MULTILINE))
    )
    stripped = strip_legacy_sandbox(original)
    updated = merge_fragment(
        ensure_default_permissions(stripped, migrated_legacy=migrated_legacy)
    )

    if updated == original:
        print(f"ok: {CONFIG_PATH} already uses workspace-git (legacy sandbox stripped)")
        return 0

    backup = CONFIG_PATH.with_suffix(".toml.bak")
    if CONFIG_PATH.exists():
        backup.write_text(original, encoding="utf-8")
        print(f"backup: {backup}")

    CONFIG_PATH.write_text(updated, encoding="utf-8")
    print(f"ok: updated {CONFIG_PATH}")
    print("next: fully quit Codex, start a new thread, then verify:")
    print("  touch .git/codex-write-test && rm .git/codex-write-test && echo OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
