#!/usr/bin/env python3
"""MCP-only team lab driver — LAB-S01/S02 from MCP_Run_Factory_Team_Lab.md."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

from mcp_client import MCPStdioClient, parse_tool_json
from scoring import evaluate_team_quality, score_run_contract

REPO = Path(__file__).resolve().parents[2]
DEFAULT_ALLN = REPO / "Packages/AllnighterCore/.build/debug/alln"
SUITES_DIR = REPO / "docs/team-lab/suites"
LAB_ROOT = REPO / ".lab"


def repo_alln() -> Path:
    env = os.environ.get("ALLN_BIN")
    if env:
        return Path(env)
    return DEFAULT_ALLN


def load_suite(suite_id: str) -> dict:
    path = SUITES_DIR / f"{suite_id}.json"
    if not path.exists():
        raise SystemExit(f"unknown suite: {suite_id} ({path})")
    return json.loads(path.read_text())


def load_case(suite: dict, case_id: str | None) -> dict:
    cases = suite["cases"]
    if case_id:
        for c in cases:
            if c["caseId"] == case_id:
                return c
        raise SystemExit(f"unknown case {case_id} in suite {suite['suiteId']}")
    if len(cases) != 1:
        raise SystemExit("suite has multiple cases; pass --case")
    return cases[0]


def load_case_json(path: Path, suite: dict) -> dict:
    """Load a generated scenario case without editing the committed suite file."""
    case = json.loads(path.read_text())
    if not case.get("caseId") or not case.get("prompt"):
        raise SystemExit(f"case json must include caseId and prompt: {path}")
    out = dict(case)
    out.setdefault("lane", suite.get("cases", [{}])[0].get("lane", "code"))
    out.setdefault("teamId", suite.get("defaultTeamId"))
    out.setdefault("contextPolicy", {})
    out.setdefault("generatedCasePath", str(path))
    return out


def context_for_case(case: dict) -> str:
    policy = case.get("contextPolicy", {})
    parts: list[str] = []
    repo_root = policy.get("repoRoot", str(REPO))
    for ref in policy.get("contextFiles", []):
        p = Path(ref) if Path(ref).is_absolute() else Path(repo_root) / ref
        if p.exists():
            parts.append(f"## {p.relative_to(REPO) if p.is_relative_to(REPO) else p}\n\n{p.read_text()}")
    return "\n\n".join(parts)


def copy_run_journal(run_id: str, dest: Path) -> bool:
    support = Path.home() / "Library/Application Support/Allnighter"
    src = support / "Runs" / f"run_{run_id}"
    if not src.exists():
        return False
    if dest.exists():
        shutil.rmtree(dest)
    shutil.copytree(src, dest)
    return True


def git_head(repo: Path) -> str | None:
    try:
        out = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repo, text=True).strip()
        return out[:12] if out else None
    except (subprocess.CalledProcessError, OSError):
        return None


def write_experiment(
    lab_dir: Path,
    *,
    suite: dict,
    case: dict,
    team_id: str,
    effort: str,
    round_no: int,
    variant: str,
    run_id: str,
    status: str,
    preflight: dict,
    start: dict,
    status_history: list[dict],
    idempotency_key: str,
    alln_path: Path,
    tools_hash: str,
    contract_version: str | None,
    contract: dict | None = None,
    team_eval: dict | None = None,
) -> None:
    started = status_history[0].get("polledAt") if status_history else None
    completed = datetime.now(timezone.utc).isoformat()
    duration_ms = None
    if started:
        try:
            s = datetime.fromisoformat(started.replace("Z", "+00:00"))
            e = datetime.fromisoformat(completed.replace("Z", "+00:00"))
            duration_ms = int((e - s).total_seconds() * 1000)
        except ValueError:
            pass
    exp = {
        "experimentId": lab_dir.name,
        "suiteId": suite["suiteId"],
        "caseId": case["caseId"],
        "teamId": team_id,
        "variant": variant,
        "round": round_no,
        "startedAt": started,
        "completedAt": completed,
        "gitHead": git_head(REPO),
        "allnBinary": str(alln_path),
        "allnVersion": "0.1.0",
        "contractVersion": contract_version,
        "mcpServer": {
            "command": "alln mcp serve --stdio",
            "protocolVersion": "2024-11-05",
            "toolsListHash": tools_hash,
        },
        "request": {
            "prompt": case["prompt"],
            "lane": case.get("lane", "code"),
            "team": team_id,
            "effort": effort,
            "idempotencyKey": idempotency_key,
        },
        "run": {
            "runId": run_id,
            "status": status,
            "pollCount": len(status_history),
            "durationMs": duration_ms,
        },
        "preflight": {
            "canStart": preflight.get("canStart"),
            "readyWorkerCount": len(preflight.get("readyWorkers", [])),
            "resolvedSourceIds": preflight.get("resolvedSourceIds", []),
            "warnings": preflight.get("warnings", []),
        },
        "start": {"nextPollAfterMs": start.get("nextPollAfterMs")},
    }
    if contract:
        exp["evaluation"] = {
            "runContract": contract.get("runContractScore"),
            "fsBypass": contract.get("fsBypass"),
            "scoringSource": contract.get("scoringSource"),
            # No deterministic team-quality score — quality is judged by compare.py.
            "teamQuality": None,
            "judgePending": team_eval.get("judgePending") if team_eval else None,
            "teamQualityWithheld": team_eval.get("teamQualityWithheld") if team_eval else None,
            "writerConsistencyIssues": (
                team_eval.get("writerConsistency", {}).get("issueCount") if team_eval else None
            ),
        }
    support_root = os.environ.get("ALLNIGHTER_SUPPORT_DIR") or str(
        Path.home() / "Library/Application Support/Allnighter"
    )
    exp["supportRoot"] = support_root
    (lab_dir / "experiment.json").write_text(json.dumps(exp, indent=2))


def run_experiment(
    *,
    alln: Path,
    suite_id: str,
    case_id: str | None,
    case_json: Path | None,
    team_id: str | None,
    effort: str,
    round_no: int,
    variant: str,
    deadline_s: int,
) -> Path:
    suite = load_suite(suite_id)
    if case_id and case_json:
        raise SystemExit("pass either --case or --case-json, not both")
    case = load_case_json(case_json, suite) if case_json else load_case(suite, case_id)
    team = team_id or case.get("teamId") or suite.get("defaultTeamId")
    if not team:
        raise SystemExit("team id required")
    lane = case.get("lane", "code")
    prompt = case["prompt"]
    context = context_for_case(case)

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    lab_dir = LAB_ROOT / f"{team}_{variant}_r{round_no}_{stamp}"
    lab_dir.mkdir(parents=True)
    (lab_dir / "evaluation").mkdir()
    transcript = lab_dir / "mcp-transcript.jsonl"

    env = os.environ.copy()
    env.setdefault("HOME", str(Path.home()))

    proc = subprocess.Popen(
        [str(alln), "mcp", "serve", "--stdio"],
        cwd=str(REPO),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
    )
    client = MCPStdioClient(proc, transcript_path=transcript)

    try:
        init = client.request(
            "initialize",
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "team-lab", "version": "0.1"},
            },
        )
        client.notify("notifications/initialized")
        (lab_dir / "initialize.json").write_text(json.dumps(init, indent=2))

        tools = client.request("tools/list")
        (lab_dir / "tools-list.json").write_text(json.dumps(tools, indent=2))
        tools_hash = hashlib.sha256(json.dumps(tools, sort_keys=True).encode()).hexdigest()
        (lab_dir / "tools-list.sha256").write_text(tools_hash)

        hello = client.call_tool("mcp_hello", {"originAgent": "team-lab"})
        (lab_dir / "mcp-hello.json").write_text(json.dumps(hello, indent=2))

        preflight_call = client.call_tool(
            "team_preflight",
            {"lane": lane, "team": team, "effort": effort},
        )
        preflight = parse_tool_json(preflight_call)
        (lab_dir / "team-preflight.json").write_text(json.dumps(preflight, indent=2))
        if not preflight.get("canStart"):
            write_experiment(
                lab_dir,
                suite=suite,
                case=case,
                team_id=team,
                effort=effort,
                round_no=round_no,
                variant=variant,
                run_id="",
                status="blocked",
                preflight=preflight,
                start={},
                status_history=[],
                idempotency_key="",
                alln_path=alln,
                tools_hash=tools_hash,
                contract_version=None,
            )
            raise SystemExit(f"preflight blocked: {preflight.get('blockedReason')}")

        idem = f"lab-{team}-r{round_no}-{uuid.uuid4()}"
        start_call = client.call_tool(
            "team_start",
            {
                "prompt": prompt,
                "lane": lane,
                "team": team,
                "effort": effort,
                "context": context,
                "idempotencyKey": idem,
                "originAgent": "team-lab",
                "originConversationId": f"lab-{suite_id}",
                "originMessageId": idem,
            },
        )
        start = parse_tool_json(start_call)
        (lab_dir / "team-start.json").write_text(json.dumps(start, indent=2))
        run_id = start["runId"]
        print(f"run_id={run_id} team={team} round={round_no}")

        poll_ms = start.get("nextPollAfterMs", 3000)
        terminal = {"completed", "failed", "cancelled", "interrupted"}
        status_history: list[dict] = []
        deadline = time.time() + deadline_s

        while time.time() < deadline:
            time.sleep(max(poll_ms / 1000.0, 2.0))
            status_call = client.call_tool("team_status", {"runId": run_id})
            status_data = parse_tool_json(status_call)
            status_data["polledAt"] = datetime.now(timezone.utc).isoformat()
            status_history.append(status_data)
            status = status_data.get("status")
            print(
                f"  status={status} workers={status_data.get('workersDone')}/"
                f"{status_data.get('workersTotal')} stage={status_data.get('stage')}"
            )
            poll_ms = status_data.get("nextPollAfterMs", poll_ms)
            if status in terminal:
                break
        else:
            raise SystemExit("deadline waiting for terminal status")

        (lab_dir / "team-status-history.json").write_text(json.dumps(status_history, indent=2))

        result_ok = False
        result_call = client.call_tool("team_result", {"runId": run_id, "detail": "full"})
        (lab_dir / "team-result-raw.txt").write_text(result_call["text"])
        try:
            result_data = parse_tool_json(result_call)
            (lab_dir / "team-result.json").write_text(json.dumps(result_data, indent=2))
            result_ok = True
        except ValueError:
            result_data = None

        tool_names = [t["name"] for t in tools.get("tools", [])]
        if "floor_show" in tool_names:
            floor = client.call_tool("floor_show", {"runId": run_id})
            (lab_dir / "floor-show.txt").write_text(floor["text"])
            if floor.get("structured"):
                (lab_dir / "floor-show.json").write_text(json.dumps(floor["structured"], indent=2))

        journal_copied = copy_run_journal(run_id, lab_dir / "run")

        terminal_status = status_history[-1].get("status", "")
        hello_structured = hello.get("structured") if isinstance(hello, dict) else None
        contract_version = None
        if isinstance(hello_structured, dict):
            contract_version = hello_structured.get("contractVersion")

        exp_kwargs = dict(
            suite=suite,
            case=case,
            team_id=team,
            effort=effort,
            round_no=round_no,
            variant=variant,
            run_id=run_id,
            status=terminal_status,
            preflight=preflight,
            start=start,
            status_history=status_history,
            idempotency_key=idem,
            alln_path=alln,
            tools_hash=tools_hash,
            contract_version=contract_version,
        )

        # Write experiment.json BEFORE evaluation. The writer stale-claim check reads
        # run status from this file; running it before the file exists disables the
        # consistency check.
        write_experiment(lab_dir, **exp_kwargs)

        contract = score_run_contract(
            lab_dir,
            status=terminal_status,
            result_ok=result_ok,
            journal_copied=journal_copied,
            expected_run_id=run_id,
        )
        team_eval = evaluate_team_quality(lab_dir)

        # Re-write with embedded evaluation facts now that they exist.
        write_experiment(lab_dir, contract=contract, team_eval=team_eval, **exp_kwargs)

        report_lines = [
            f"# Team Lab Report — {lab_dir.name}",
            "",
            f"- Team: `{team}`",
            f"- Suite: `{suite_id}` / case `{case['caseId']}`",
            f"- Round: {round_no} variant `{variant}`",
            f"- Run: `{run_id}`",
            f"- Terminal status: `{status_history[-1].get('status')}`",
            f"- Run contract score: **{contract['runContractScore']}**",
            f"- Scoring source: `{contract.get('scoringSource')}` (fsBypass={contract.get('fsBypass')})",
            "",
            "## Preflight warnings",
            "",
        ]
        for w in preflight.get("warnings", []):
            report_lines.append(f"- {w}")
        report_lines += ["", "## Run contract checks", ""]
        for c in contract["checks"]:
            mark = "ok" if c["ok"] else "FAIL"
            report_lines.append(f"- [{mark}] {c['name']}")
        report_lines += ["", "## Team quality", ""]
        if team_eval.get("teamQualityWithheld"):
            report_lines.append(
                f"- Quality not judgeable: **withheld** ({team_eval.get('teamQualityWithheldReason')}) — "
                "fix the substrate before judging."
            )
        else:
            report_lines.append(
                "- Quality is **judge-pending** — no deterministic score. Run a blind "
                "two-judge A/B against a baseline/candidate via `compare.py`."
            )
        report_lines += [
            f"- Preflight-ready sources: {len(preflight.get('readyWorkers', []))} (incl. writer)",
            f"- Answer/review workers (judged per-role by compare.py): {team_eval.get('answerReviewWorkerCount')}",
            f"- Writer consistency issues (truth check): {team_eval.get('writerConsistency', {}).get('issueCount', 0)}",
            "",
            "## Next",
            "",
            "- Generate a FRESH input each round: `scenario.py <suite>` (never reuse an input)",
            "- Blind A/B vs the champion run: `compare.py <baseline_dir> <candidate_dir>`",
            "- Bank per-worker wins (both judges agree); audit the deliverable for regressions",
            "",
        ]
        (lab_dir / "report.md").write_text("\n".join(report_lines))

        print(f"LAB_DIR={lab_dir}")
        print(f"run_contract_score={contract['runContractScore']}")
        return lab_dir
    finally:
        try:
            proc.terminate()
        except Exception:
            pass
        proc.wait(timeout=10)


def main() -> int:
    # Line-buffered status for long-running team polls.
    sys.stdout.reconfigure(line_buffering=True)
    p = argparse.ArgumentParser(description="Run a team lab experiment via MCP stdio")
    p.add_argument("--suite", required=True)
    p.add_argument("--case")
    p.add_argument("--case-json", type=Path, help="generated scenario JSON; use same file for both A/B arms")
    p.add_argument("--team")
    p.add_argument("--effort", default="high")
    p.add_argument("--round", type=int, default=1)
    p.add_argument("--variant", default="baseline")
    p.add_argument("--deadline-seconds", type=int, default=7200)
    p.add_argument("--alln", type=Path, default=repo_alln())
    args = p.parse_args()

    if not args.alln.exists():
        raise SystemExit(f"alln binary not found: {args.alln} — run swift build first")

    run_experiment(
        alln=args.alln,
        suite_id=args.suite,
        case_id=args.case,
        case_json=args.case_json,
        team_id=args.team,
        effort=args.effort,
        round_no=args.round,
        variant=args.variant,
        deadline_s=args.deadline_seconds,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
