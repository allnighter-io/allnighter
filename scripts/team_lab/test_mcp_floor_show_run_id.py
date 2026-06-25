#!/usr/bin/env python3
"""Regression test for floor_show run selector (run vs runId).

This is the decisive e2e seam test for the floor_show wrong-run bug.

- Isolated ALLNIGHTER_SUPPORT_DIR so concurrent labs cannot interfere.
- Seeds two persisted runs (RA older, RB latest) by writing minimal valid run.json.
- Spawns the real `alln mcp serve --stdio` binary.
- Calls floor_show with both documented key ("run") and the lifecycle key ("runId").
- Asserts the returned floor always describes the requested run, never silently "latest".

Run:
  python3 scripts/team_lab/test_mcp_floor_show_run_id.py

Requires a built alln (Packages/AllnighterCore/.build/debug/alln or $ALLN_BIN).
This test does not invoke agents/models; it only exercises the MCP query path + RunStore load.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path

from mcp_client import MCPStdioClient

REPO = Path(__file__).resolve().parents[2]
DEFAULT_ALLN = REPO / "Packages/AllnighterCore/.build/debug/alln"


def repo_alln() -> Path:
    env = os.environ.get("ALLN_BIN")
    if env:
        return Path(env)
    return DEFAULT_ALLN


MINIMAL_RUN_JSON = {
    "createdAt": "1970-01-12T13:46:40Z",
    "id": "PLACEHOLDER",
    "mutating": False,
    "origin": "mcp",
    "prompt": "minimal floor show seed for run selector regression",
    "stages": [],
    "status": "complete",
    "warnings": [],
    "workerAnswers": [
        {"modelId": "model_opus", "output": "ans", "status": "done", "workerId": "w#0"}
    ],
    "workers": [{"id": "w#0", "instanceIndex": 0, "modelId": "model_opus", "purpose": "answer"}],
}


def write_minimal_run(runs_dir: Path, run_id: str, created_at_iso: str) -> Path:
    """Write a minimal but loadable run_<id>/run.json under the Runs dir."""
    run_dir = runs_dir / f"run_{run_id}"
    run_dir.mkdir(parents=True, exist_ok=True)
    data = dict(MINIMAL_RUN_JSON)
    data["id"] = run_id
    data["createdAt"] = created_at_iso
    (run_dir / "run.json").write_text(json.dumps(data, indent=2))
    return run_dir


def parse_floor_run_id(floor_resp: dict) -> str | None:
    """Extract run id from the floor projection (structured or text fallbacks)."""
    structured = floor_resp.get("structured") or {}
    if isinstance(structured, dict):
        r = structured.get("run") or {}
        if isinstance(r, dict) and r.get("id"):
            return r["id"]
        if structured.get("runId"):
            return structured["runId"]
    # fallback parse from text if needed
    text = (floor_resp.get("text") or "").strip()
    for line in text.splitlines():
        if '"id"' in line and "MINI" in line:
            # naive grab
            try:
                return json.loads(line).get("id")
            except Exception:
                pass
    return None


def main() -> int:
    alln = repo_alln()
    if not alln.exists():
        print(f"SKIP: alln binary not found at {alln} (run swift build -c debug first)", file=sys.stderr)
        return 0

    # Isolated support dir so we control exactly which runs exist.
    with tempfile.TemporaryDirectory(prefix="mcp_floor_test_") as td:
        support = Path(td) / "Allnighter"
        runs = support / "Runs"
        runs.mkdir(parents=True)

        # RA is older; RB is strictly later so "latest" would pick RB.
        ra_id = "MINI-RA-001"
        rb_id = "MINI-RB-002"
        write_minimal_run(
            runs, ra_id, "2026-06-20T00:00:00Z"
        )
        write_minimal_run(
            runs, rb_id, "2026-06-24T00:00:00Z"
        )

        env = os.environ.copy()
        env["ALLNIGHTER_SUPPORT_DIR"] = str(support)
        # Ensure HOME is sane for other fallbacks inside the binary.
        env.setdefault("HOME", str(Path.home()))

        transcript = support / "mcp-transcript.jsonl"
        proc, client = None, None
        try:
            proc = subprocess.Popen(
                [str(alln), "mcp", "serve", "--stdio"],
                cwd=str(REPO),
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                env=env,
            )
            client = MCPStdioClient(proc, transcript_path=transcript)
            client.request(
                "initialize",
                {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "test-mcp-floor-runid", "version": "1"},
                },
            )
            client.notify("notifications/initialized")

            # List tools to confirm floor_show is present (contract surface).
            tools = client.request("tools/list")
            names = [t["name"] for t in tools.get("tools", [])]
            if "floor_show" not in names:
                print("FAIL: floor_show not advertised by this alln binary")
                return 1

            # --- The actual regression calls ---
            # 1. Explicit "run" key (canonical for query tools per contract + runRef).
            floor_run = client.call_tool("floor_show", {"run": ra_id})
            got_ra = parse_floor_run_id(floor_run)
            if got_ra != ra_id:
                print(f"FAIL: floor_show(run=RA) returned {got_ra} (expected {ra_id})")
                print("raw:", floor_run.get("text")[:300])
                return 1

            # 2. The lifecycle key "runId" that team_* tools use (defensive alias must hold).
            floor_runid = client.call_tool("floor_show", {"runId": ra_id})
            got_ra2 = parse_floor_run_id(floor_runid)
            if got_ra2 != ra_id:
                print(f"FAIL: floor_show(runId=RA) returned {got_ra2} (expected {ra_id})")
                print("raw:", floor_runid.get("text")[:300])
                return 1

            # 3. Omitting the selector must still yield latest (RB).
            floor_latest = client.call_tool("floor_show", {})
            got_latest = parse_floor_run_id(floor_latest)
            if got_latest != rb_id:
                print(f"FAIL: floor_show() without selector returned {got_latest} (expected latest=RB {rb_id})")
                return 1

            print("PASS: floor_show honors 'run', 'runId', and falls back to latest only when absent")
            print(f"  RA via run:   {got_ra}")
            print(f"  RA via runId: {got_ra2}")
            print(f"  latest:       {got_latest}")
            return 0

        except Exception as e:
            print(f"ERROR during MCP roundtrip: {e}", file=sys.stderr)
            # Print a bit of stderr from the child for triage.
            if proc and proc.stderr:
                try:
                    err = proc.stderr.read(4000)
                    if err:
                        print("child stderr head:", err[:2000], file=sys.stderr)
                except Exception:
                    pass
            return 1
        finally:
            if client:
                try:
                    client.close()
                except Exception:
                    pass
            if proc:
                try:
                    proc.wait(timeout=2)
                except Exception:
                    try:
                        proc.kill()
                    except Exception:
                        pass


if __name__ == "__main__":
    sys.exit(main())
