#!/usr/bin/env python3
"""CLI concurrency spike — does each headless CLI survive concurrent invocation?

For each driver: run 1 serial baseline, then N concurrent invocations of the
SAME trivial prompt. A CLI that works serially but hangs / returns 0 bytes /
times out under concurrency has the agy-class bug (singleton session store or
global lock) and needs maxConcurrentSpawns=1 in its driver manifest.

Usage: cli-concurrency-spike.py [driver ...]   (default: all but agy)
"""
from __future__ import annotations

import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor

PROMPT = "Reply with exactly the two characters: OK"
CWD = "/Users/mike/Documents/GitHub/Allnighter"

# command builders: each returns argv for one invocation.
DRIVERS = {
    "claude_code": lambda: ["claude", "-p", PROMPT, "--model", "sonnet"],
    "codex": lambda: ["codex", "exec", "--skip-git-repo-check", "--color", "never",
                      "-m", "gpt-5.4-mini", PROMPT],
    "cursor_agent": lambda: ["agent", "-p", "--output-format", "text", "--model",
                             "composer-2.5-fast", "--trust", "--workspace", CWD, PROMPT],
    "grok": lambda: ["grok", "-p", PROMPT, "-m", "grok-composer-2.5-fast",
                     "--output-format", "plain", "--always-approve", "--cwd", CWD],
    # agy is already proven broken; include only if asked, as a positive control.
    "antigravity": lambda: ["agy", "--print", PROMPT, "--model", "Gemini 3.5 Flash",
                            "--dangerously-skip-permissions"],
}

CONCURRENCY = 3
SERIAL_TIMEOUT = 100
CONC_TIMEOUT = 150


def one_run(argv, timeout):
    start = time.monotonic()
    try:
        p = subprocess.run(argv, capture_output=True, cwd=CWD, timeout=timeout)
        dt = time.monotonic() - start
        return {"exit": p.returncode, "out": len(p.stdout), "err": len(p.stderr),
                "dt": round(dt, 1), "timeout": False,
                "errtail": p.stderr.decode("utf-8", "replace")[-180:].strip()}
    except subprocess.TimeoutExpired:
        return {"exit": None, "out": 0, "err": 0, "dt": round(time.monotonic() - start, 1),
                "timeout": True, "errtail": "TIMEOUT"}


def fmt(r):
    state = "TIMEOUT" if r["timeout"] else ("OK" if r["out"] > 0 and r["exit"] == 0 else "FAIL")
    return f"[{state:7}] exit={r['exit']} out={r['out']}B err={r['err']}B {r['dt']}s  {r['errtail'][:120]}"


def probe(driver, build):
    print(f"\n{'='*70}\n{driver}\n{'='*70}")
    print(f"  SERIAL baseline (timeout {SERIAL_TIMEOUT}s)...")
    base = one_run(build(), SERIAL_TIMEOUT)
    print("    " + fmt(base))
    serial_ok = (not base["timeout"]) and base["out"] > 0 and base["exit"] == 0
    if not serial_ok:
        print(f"  -> serial baseline did not produce clean output; concurrency signal unreliable. Skipping fan-out.")
        return driver, base, None
    print(f"  CONCURRENT x{CONCURRENCY} (timeout {CONC_TIMEOUT}s each)...")
    with ThreadPoolExecutor(max_workers=CONCURRENCY) as ex:
        results = list(ex.map(lambda _: one_run(build(), CONC_TIMEOUT), range(CONCURRENCY)))
    for i, r in enumerate(results):
        print(f"    #{i+1} " + fmt(r))
    n_ok = sum(1 for r in results if not r["timeout"] and r["out"] > 0 and r["exit"] == 0)
    verdict = "PARALLEL-SAFE" if n_ok == CONCURRENCY else f"NEEDS LIMIT=1 ({n_ok}/{CONCURRENCY} ok)"
    print(f"  VERDICT: {verdict}")
    return driver, base, results


if __name__ == "__main__":
    targets = sys.argv[1:] or ["claude_code", "codex", "cursor_agent", "grok"]
    summary = []
    for d in targets:
        if d not in DRIVERS:
            print(f"unknown driver {d}; known: {list(DRIVERS)}"); continue
        _, base, results = probe(d, DRIVERS[d])
        if results is None:
            summary.append((d, "SERIAL-UNCLEAR"))
        else:
            n_ok = sum(1 for r in results if not r["timeout"] and r["out"] > 0 and r["exit"] == 0)
            summary.append((d, "PARALLEL-SAFE" if n_ok == CONCURRENCY else f"NEEDS-LIMIT-1 ({n_ok}/{CONCURRENCY})"))
    print(f"\n{'#'*70}\nSUMMARY")
    for d, v in summary:
        print(f"  {d:14} {v}")
