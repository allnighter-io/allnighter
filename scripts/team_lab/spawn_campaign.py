#!/usr/bin/env python3
"""Spawn the campaign supervisor detached (macOS-safe; survives IDE/session end).

Uses start_new_session=True so the supervisor is reparented to init (PPID 1) and
keeps running after the launching shell or agent turn goes away.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CAMPAIGN_DIR = REPO / ".lab" / "campaign"
SUPERVISOR = REPO / "scripts" / "team_lab" / "supervisor.py"


def pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--queue", type=Path, required=True)
    p.add_argument("--max-jobs", type=int)
    p.add_argument("--dry-run", action="store_true")
    args = p.parse_args()

    CAMPAIGN_DIR.mkdir(parents=True, exist_ok=True)
    pidfile = CAMPAIGN_DIR / "supervisor.pid"
    log = CAMPAIGN_DIR / "supervisor.log"

    if pidfile.exists():
        try:
            existing = int(pidfile.read_text().strip())
        except ValueError:
            existing = -1
        if existing > 0 and pid_alive(existing):
            print(f"already running pid={existing} log={log}")
            return 0

    cmd = [sys.executable, str(SUPERVISOR), "--queue", str(args.queue.resolve())]
    if args.max_jobs is not None:
        cmd += ["--max-jobs", str(args.max_jobs)]
    if args.dry_run:
        cmd += ["--dry-run"]

    with log.open("a") as log_handle:
        proc = subprocess.Popen(
            cmd,
            cwd=str(REPO),
            stdin=subprocess.DEVNULL,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    pidfile.write_text(f"{proc.pid}\n")
    print(f"started supervisor pid={proc.pid} queue={args.queue} log={log}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
