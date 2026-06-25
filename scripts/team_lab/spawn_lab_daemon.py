#!/usr/bin/env python3
"""Spawn a detached lab daemon (macOS-safe — start_new_session, no setsid)."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
INNER = REPO / "scripts" / "team_lab" / "run_lab_daemon_inner.sh"


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def main() -> int:
    skill = os.environ.get("WRITER_SKILL", "bug_packet_writer_v4")
    tag = os.environ.get("WRITER_TAG", "writer_v4")
    pidfile = REPO / f".lab/lab-daemon-{tag}.pid"
    log = REPO / f".lab/lab-daemon-{tag}.log"

    if pidfile.exists():
        try:
            existing = int(pidfile.read_text().strip())
        except ValueError:
            existing = -1
        if existing > 0 and pid_alive(existing):
            print(f"already running pid={existing} log={log}")
            return 0

    log.parent.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["WRITER_SKILL"] = skill
    env["WRITER_TAG"] = tag

    with log.open("a") as log_handle:
        proc = subprocess.Popen(
            ["bash", str(INNER)],
            cwd=str(REPO),
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )

    pidfile.write_text(f"{proc.pid}\n")
    print(f"started pid={proc.pid} skill={skill} tag={tag} log={log}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
