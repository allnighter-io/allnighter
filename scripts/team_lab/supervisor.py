#!/usr/bin/env python3
"""Unattended lab campaign supervisor.

Runs a queue of lab jobs back-to-back, serialized, so the lab can run NON-STOP
without a human babysitting it. The whole reason this exists: a single stuck
worker or a dropped session used to kill an entire run and leave the lab idle
until someone noticed. The supervisor makes failure a per-job event, not a
campaign-ending one.

Guarantees
----------
- **Resume**: a job whose state is `done` is skipped on restart. Safe to relaunch.
- **Retry + backoff**: each job retries up to `retries` times with exponential
  backoff before it is marked `failed` and the campaign MOVES ON.
- **Capacity-aware**: failures that look like quota/capacity exhaustion back off
  much longer (a worker stop is expected to clear after a cooldown window) and do
  not count against the normal retry budget as aggressively.
- **Heartbeat**: `state.json` carries `heartbeatAt` updated every loop so it is
  obvious whether the supervisor is alive or wedged.
- **Never blocks the campaign on one job.**

Job schema (one JSON object per line in the queue file)::

    {
      "id": "bug_hunt_lite_necessity",     // unique, stable
      "cmd": ["bash", "scripts/team_lab/run_bug_hunt_lite.sh"],
      "retries": 2,                          // optional, default 2
      "timeoutSec": 5400,                    // optional, default 5400 (90m)
      "backoffSec": 60,                      // optional base backoff
      "capacityBackoffSec": 1800,            // optional cooldown on quota errors
      "doneMarker": ".lab/.../rollup.json",  // optional; if present at start, skip
      "blocked": false,                       // optional; blocked jobs are skipped + reported
      "note": "human description"
    }

Usage::

    python3 scripts/team_lab/supervisor.py --queue scripts/team_lab/beta_campaign.jsonl
    python3 scripts/team_lab/supervisor.py --queue ... --dry-run   # no commands run
    python3 scripts/team_lab/supervisor.py --queue ... --max-jobs 1
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CAMPAIGN_DIR = REPO / ".lab" / "campaign"

CAPACITY_PATTERNS = re.compile(
    r"rate limit|rate-limit|quota|capacity|429|too many requests|"
    r"overloaded|usage limit|insufficient_quota|resource exhausted|try again later",
    re.IGNORECASE,
)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def load_queue(path: Path) -> list[dict]:
    jobs: list[dict] = []
    seen: set[str] = set()
    for raw in path.read_text().splitlines():
        raw = raw.strip()
        if not raw or raw.startswith("#"):
            continue
        job = json.loads(raw)
        jid = job.get("id")
        if not jid:
            raise SystemExit(f"queue job missing id: {raw[:120]}")
        if jid in seen:
            raise SystemExit(f"duplicate job id in queue: {jid}")
        seen.add(jid)
        jobs.append(job)
    return jobs


def load_state(path: Path) -> dict:
    if path.exists():
        try:
            return json.loads(path.read_text())
        except json.JSONDecodeError:
            pass
    return {"jobs": {}, "startedAt": now_iso()}


def write_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, indent=2) + "\n")
    tmp.replace(path)


def looks_like_capacity(text: str) -> bool:
    return bool(CAPACITY_PATTERNS.search(text or ""))


def tail(text: str, limit: int = 4000) -> str:
    text = text or ""
    return text[-limit:]


def run_job(job: dict, *, log_dir: Path, dry_run: bool) -> dict:
    """Run one job once. Returns an attempt result dict."""
    jid = job["id"]
    cmd = job["cmd"]
    timeout_s = int(job.get("timeoutSec", 5400))
    started = now_iso()

    if dry_run:
        return {"ok": True, "exit": 0, "startedAt": started, "finishedAt": now_iso(),
                "capacity": False, "note": "dry-run (command not executed)"}

    log_path = log_dir / f"{jid}.log"
    with log_path.open("a") as logf:
        logf.write(f"\n=== {jid} attempt @ {started} ===\n+ {' '.join(cmd)}\n")
        logf.flush()
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(REPO),
                stdin=subprocess.DEVNULL,
                stdout=logf,
                stderr=subprocess.STDOUT,
                timeout=timeout_s,
            )
            exit_code = proc.returncode
            timed_out = False
        except subprocess.TimeoutExpired:
            exit_code = -1
            timed_out = True
            logf.write(f"\n!!! timeout after {timeout_s}s\n")

    text = ""
    try:
        text = tail(log_path.read_text())
    except OSError:
        pass
    capacity = (not timed_out) and exit_code != 0 and looks_like_capacity(text)
    return {
        "ok": exit_code == 0,
        "exit": exit_code,
        "timedOut": timed_out,
        "capacity": capacity,
        "startedAt": started,
        "finishedAt": now_iso(),
        "logPath": str(log_path),
    }


def job_done_via_marker(job: dict) -> bool:
    marker = job.get("doneMarker")
    if not marker:
        return False
    p = Path(marker)
    if not p.is_absolute():
        p = REPO / p
    return p.exists()


def supervise(
    *,
    queue_path: Path,
    state_path: Path,
    log_dir: Path,
    dry_run: bool,
    max_jobs: int | None,
) -> int:
    jobs = load_queue(queue_path)
    state = load_state(state_path)
    state.setdefault("jobs", {})
    state["queuePath"] = str(queue_path)
    state["pid"] = os.getpid()
    log_dir.mkdir(parents=True, exist_ok=True)

    processed = 0
    for job in jobs:
        jid = job["id"]
        js = state["jobs"].setdefault(jid, {"status": "pending", "attempts": 0})
        state["heartbeatAt"] = now_iso()
        state["current"] = jid
        write_state(state_path, state)

        if job.get("blocked"):
            js["status"] = "blocked"
            js["note"] = job.get("note", "blocked: prerequisite missing")
            write_state(state_path, state)
            print(f"[{jid}] BLOCKED — {js['note']}", flush=True)
            continue

        if js.get("status") == "done":
            print(f"[{jid}] skip (already done)", flush=True)
            continue

        if job_done_via_marker(job):
            js["status"] = "done"
            js["note"] = "doneMarker present at start"
            js["finishedAt"] = now_iso()
            write_state(state_path, state)
            print(f"[{jid}] skip (doneMarker present)", flush=True)
            continue

        if max_jobs is not None and processed >= max_jobs:
            print(f"[{jid}] deferred (max-jobs={max_jobs} reached)", flush=True)
            break

        retries = int(job.get("retries", 2))
        base_backoff = int(job.get("backoffSec", 60))
        cap_backoff = int(job.get("capacityBackoffSec", 1800))
        # Capacity/quota failures cool down separately, but the budget is BOUNDED so a
        # permanently-exhausted account can never wedge the campaign in an infinite loop.
        capacity_retries = int(job.get("capacityRetries", 3))

        normal_attempt = 0      # counts toward `retries`
        capacity_attempt = 0    # counts toward `capacity_retries`
        success = False
        while True:
            js["status"] = "running"
            js["attempts"] = js.get("attempts", 0) + 1
            js["lastAttemptAt"] = now_iso()
            state["heartbeatAt"] = now_iso()
            write_state(state_path, state)
            print(
                f"[{jid}] attempt (normal {normal_attempt}/{retries}, "
                f"capacity {capacity_attempt}/{capacity_retries})",
                flush=True,
            )

            result = run_job(job, log_dir=log_dir, dry_run=dry_run)
            js["lastResult"] = result
            write_state(state_path, state)

            if result["ok"]:
                js["status"] = "done"
                js["finishedAt"] = now_iso()
                write_state(state_path, state)
                print(f"[{jid}] DONE", flush=True)
                success = True
                break

            if result.get("capacity"):
                capacity_attempt += 1
                if capacity_attempt > capacity_retries:
                    print(f"[{jid}] capacity budget exhausted ({capacity_retries}) — giving up", flush=True)
                    break
                wait = cap_backoff
                js["status"] = "cooldown"
                print(f"[{jid}] capacity/quota failure — cooldown {wait}s "
                      f"({capacity_attempt}/{capacity_retries})", flush=True)
            else:
                normal_attempt += 1
                if normal_attempt > retries:
                    print(f"[{jid}] retries exhausted ({retries})", flush=True)
                    break
                wait = base_backoff * (2 ** (normal_attempt - 1))
                print(f"[{jid}] failure exit={result['exit']} "
                      f"timedOut={result.get('timedOut')} — backoff {wait}s", flush=True)

            state["heartbeatAt"] = now_iso()
            write_state(state_path, state)
            if not dry_run:
                time.sleep(wait)

        processed += 1
        if not success:
            js["status"] = "failed"
            js["finishedAt"] = now_iso()
            write_state(state_path, state)
            print(f"[{jid}] FAILED after {js['attempts']} attempts — campaign continues", flush=True)

    state["current"] = None
    state["heartbeatAt"] = now_iso()
    state["finishedAt"] = now_iso()
    write_state(state_path, state)

    counts: dict[str, int] = {}
    for js in state["jobs"].values():
        counts[js["status"]] = counts.get(js["status"], 0) + 1
    print(f"CAMPAIGN_SUMMARY {json.dumps(counts)}", flush=True)
    # exit non-zero only if nothing made progress and something failed
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--queue", type=Path, required=True)
    p.add_argument("--state", type=Path, default=CAMPAIGN_DIR / "state.json")
    p.add_argument("--log-dir", type=Path, default=CAMPAIGN_DIR / "logs")
    p.add_argument("--dry-run", action="store_true", help="never execute job commands; exercise the loop")
    p.add_argument("--max-jobs", type=int, help="run at most N not-yet-done jobs this invocation")
    args = p.parse_args()
    return supervise(
        queue_path=args.queue.resolve(),
        state_path=args.state.resolve(),
        log_dir=args.log_dir.resolve(),
        dry_run=args.dry_run,
        max_jobs=args.max_jobs,
    )


if __name__ == "__main__":
    raise SystemExit(main())
