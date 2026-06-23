#!/usr/bin/env python3
"""Resume synthesis for a partial team run — re-invoke only the plan writer.

Workers are preserved in the run journal; use when the lead timed out or hit
capacity during synthesis (status partial, plan stage failed).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import uuid
from datetime import datetime, timezone
from pathlib import Path

from mcp_client import MCPStdioClient, parse_tool_json
from report import write_lab_report
from run import copy_run_journal, repo_alln
from scoring import evaluate_team_quality, score_run_contract

REPO = Path(__file__).resolve().parents[2]
SKILL_CATALOG = REPO / "Packages/AllnighterCore/Sources/AllnighterCore/SkillCatalog.swift"
RUNS_ROOT = Path.home() / "Library/Application Support/Allnighter/Runs"

DISSENT_LINES = {
    "preserveDissent": (
        "Preserve genuine dissent. Decide, but do not flatten disagreement; "
        "record minority positions."
    ),
    "compareOptions": (
        "Present the distinct options side by side with their tradeoffs, then recommend one."
    ),
    "riskRegister": (
        "Output a prioritized risk register: each item with severity, owner, and any required stop."
    ),
}


def load_skill_template(skill_id: str) -> str:
    text = SKILL_CATALOG.read_text()
    marker = f's("{skill_id}"'
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"skill template not found: {skill_id}")
    triple = text.find('"""', start)
    if triple < 0:
        raise SystemExit(f"skill template opening not found: {skill_id}")
    end = text.find('"""', triple + 3)
    if end < 0:
        raise SystemExit(f"skill template closing not found: {skill_id}")
    return text[triple + 3 : end].strip()


def run_journal_path(run_id: str) -> Path:
    return RUNS_ROOT / f"run_{run_id}" / "run.json"


def answers_block(answers: list[dict], workers_by_id: dict[str, dict]) -> str:
    parts: list[str] = []
    for answer in answers:
        wid = answer.get("workerId", "")
        worker = workers_by_id.get(wid, {})
        label = worker.get("skillName") or worker.get("skillId") or wid
        output = (answer.get("output") or answer.get("markdown") or "").strip()
        if output:
            parts.append(f"## {label}\n\n{output}")
        else:
            status = answer.get("status", "unknown")
            reason = answer.get("errorReason") or "no answer"
            parts.append(f"## {label}\n\n_({status}: {reason})_")
    return "\n\n".join(parts)


def build_writer_founder_prompt(run: dict, dissent: str = "preserveDissent") -> str:
    workers_by_id = {w["id"]: w for w in run.get("workers", []) if w.get("id")}
    answer_ids = {w["id"] for w in run["workers"] if w.get("purpose") == "answer"}
    review_ids = {w["id"] for w in run["workers"] if w.get("purpose") == "review"}
    answers = [a for a in run.get("workerAnswers", []) if a.get("workerId") in answer_ids]
    reviews = [a for a in run.get("workerAnswers", []) if a.get("workerId") in review_ids]
    answer_workers = [workers_by_id[i] for i in sorted(answer_ids) if i in workers_by_id]
    review_workers = [workers_by_id[i] for i in sorted(review_ids) if i in workers_by_id]

    parts = [run.get("prompt", "").strip(), "# Worker answers\n\n" + answers_block(answers, workers_by_id)]
    if reviews:
        parts.append("# Reviews\n\n" + answers_block(reviews, workers_by_id))
    parts.append(DISSENT_LINES.get(dissent, DISSENT_LINES["preserveDissent"]))
    return "\n\n".join(p for p in parts if p.strip())


def assemble_writer_prompt(skill_id: str, founder_prompt: str) -> str:
    template = load_skill_template(skill_id)
    return f"{template}\n\n{founder_prompt}"


def invoke_claude_opus(prompt: str, *, repo_root: Path, timeout_s: int) -> str:
    cmd = [
        "claude",
        "-p",
        prompt,
        "--model",
        "opus",
        "--effort",
        "high",
    ]
    proc = subprocess.run(
        cmd,
        cwd=str(repo_root),
        capture_output=True,
        text=True,
        timeout=timeout_s,
    )
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip()
        raise SystemExit(f"claude writer failed (exit {proc.returncode}): {err[:2000]}")
    out = (proc.stdout or "").strip()
    if not out:
        raise SystemExit("claude writer returned empty output")
    return out


def patch_run_journal(run_id: str, markdown: str, *, stage_id: str | None = None) -> dict:
    path = run_journal_path(run_id)
    if not path.exists():
        raise SystemExit(f"run journal not found: {path}")
    run = json.loads(path.read_text())
    writer = next((w for w in run.get("workers", []) if w.get("purpose") == "plan"), None)
    if not writer:
        raise SystemExit("no plan writer on run")
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    stages = run.get("stages") or []
    stage = stages[-1] if stages else {}
    stage_id = stage_id or stage.get("id") or str(uuid.uuid4()).upper()
    stage.update(
        {
            "id": stage_id,
            "purpose": "plan",
            "producedByWorkerId": writer["id"],
            "promptProfileId": writer.get("skillId") or "bug_packet_writer",
            "status": "done",
            "payload": {"kind": "plan", "markdown": markdown},
            "startedAt": stage.get("startedAt") or now,
            "finishedAt": now,
        }
    )
    stage.pop("errorReason", None)
    if stages:
        stages[-1] = stage
    else:
        stages = [stage]
    run["stages"] = stages
    run["status"] = "complete"
    path.write_text(json.dumps(run, indent=2))
    return run


def refresh_floor_show(alln: Path, lab_dir: Path, run_id: str) -> None:
    """CLI floor show — MCP floor_show can return a stale run id."""
    proc = subprocess.run(
        [str(alln), "floor", "show", run_id, "--json"],
        cwd=str(REPO),
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise SystemExit(f"floor show failed: {proc.stderr[:500]}")
    (lab_dir / "floor-show.json").write_text(proc.stdout)
    try:
        structured = json.loads(proc.stdout)
        floor_run = (structured.get("run") or {}).get("id") or structured.get("runId")
        if floor_run and floor_run != run_id:
            raise SystemExit(f"floor show run id mismatch: got {floor_run}, expected {run_id}")
    except json.JSONDecodeError as e:
        raise SystemExit(f"floor show returned invalid JSON: {e}") from e


def refresh_mcp_artifacts(alln: Path, lab_dir: Path, run_id: str) -> bool:
    proc = subprocess.Popen(
        [str(alln), "mcp", "serve", "--stdio"],
        cwd=str(REPO),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    client = MCPStdioClient(proc, transcript_path=lab_dir / "resume-writer-mcp.jsonl")
    try:
        client.request("initialize", {"protocolVersion": "2024-11-05", "capabilities": {}, "clientInfo": {"name": "team-lab-resume-writer", "version": "0.1.0"}})
        client.notify("notifications/initialized")
        tools = client.request("tools/list")
        tool_names = [t["name"] for t in tools.get("tools", [])]

        result_call = client.call_tool("team_result", {"runId": run_id, "detail": "full"})
        (lab_dir / "team-result-raw.txt").write_text(result_call["text"])
        result_ok = False
        try:
            result_data = parse_tool_json(result_call)
            (lab_dir / "team-result.json").write_text(json.dumps(result_data, indent=2))
            result_ok = True
        except ValueError:
            result_ok = False

        if "floor_show" in tool_names:
            refresh_floor_show(alln, lab_dir, run_id)
            floor_path = lab_dir / "floor-show.json"
            if floor_path.exists():
                (lab_dir / "floor-show.txt").write_text(
                    subprocess.run(
                        [str(alln), "floor", "show", run_id],
                        cwd=str(REPO),
                        capture_output=True,
                        text=True,
                    ).stdout
                )

        export = subprocess.run(
            [str(alln), "export", run_id, "--format", "md"],
            cwd=str(REPO),
            capture_output=True,
            text=True,
        )
        if export.returncode == 0 and export.stdout.strip():
            (lab_dir / "run" / "bundle.md").write_text(export.stdout)
        return result_ok
    finally:
        client.close()


def rescore_lab(lab_dir: Path, *, terminal_status: str, run_id: str) -> tuple[dict, dict]:
    journal_copied = copy_run_journal(run_id, lab_dir / "run")
    contract = score_run_contract(
        lab_dir,
        status=terminal_status,
        result_ok=(lab_dir / "team-result.json").exists(),
        journal_copied=journal_copied,
        expected_run_id=run_id,
    )
    team_eval = evaluate_team_quality(lab_dir)
    (lab_dir / "evaluation" / "run-contract-score.json").write_text(json.dumps(contract, indent=2))
    (lab_dir / "evaluation" / "team-quality.json").write_text(json.dumps(team_eval, indent=2))
    write_lab_report(lab_dir, contract=contract, team_eval=team_eval)
    return contract, team_eval


def main() -> int:
    p = argparse.ArgumentParser(description="Resume plan writer for a partial team run")
    p.add_argument("--run-id", help="run UUID from team_start")
    p.add_argument("--lab-dir", type=Path, help="lab experiment directory to refresh")
    p.add_argument("--timeout-seconds", type=int, default=900, help="writer CLI timeout (default 900)")
    p.add_argument("--alln", type=Path, default=repo_alln())
    p.add_argument("--dry-run", action="store_true", help="assemble prompt only; do not invoke writer")
    args = p.parse_args()

    lab_dir = args.lab_dir
    run_id = args.run_id
    if lab_dir and not run_id:
        exp_path = lab_dir / "experiment.json"
        if exp_path.exists():
            run_id = (json.loads(exp_path.read_text()).get("run") or {}).get("runId")
    if not run_id:
        raise SystemExit("need --run-id or --lab-dir with experiment.json")

    journal = json.loads(run_journal_path(run_id).read_text())
    writer = next((w for w in journal.get("workers", []) if w.get("purpose") == "plan"), None)
    if not writer:
        raise SystemExit("run has no plan writer worker")
    skill_id = writer.get("skillId") or "bug_packet_writer"

    founder = build_writer_founder_prompt(journal)
    prompt = assemble_writer_prompt(skill_id, founder)
    if lab_dir:
        lab_dir.mkdir(parents=True, exist_ok=True)
        (lab_dir / "resume-writer-prompt.md").write_text(prompt)
        print(f"prompt_chars={len(prompt)} saved={lab_dir / 'resume-writer-prompt.md'}")
    else:
        print(f"prompt_chars={len(prompt)}")

    if args.dry_run:
        return 0

    repo_root = Path(journal.get("repoRoot") or REPO)
    print(f"invoking claude opus writer timeout={args.timeout_seconds}s ...", flush=True)
    markdown = invoke_claude_opus(prompt, repo_root=repo_root, timeout_s=args.timeout_seconds)
    print(f"writer_chars={len(markdown)}", flush=True)

    patch_run_journal(run_id, markdown)
    print(f"patched journal run_id={run_id} status=complete", flush=True)

    if lab_dir:
        if not args.alln.exists():
            raise SystemExit(f"alln not found: {args.alln}")
        refresh_mcp_artifacts(args.alln, lab_dir, run_id)
        contract, team_eval = rescore_lab(lab_dir, terminal_status="completed", run_id=run_id)
        exp_path = lab_dir / "experiment.json"
        if exp_path.exists():
            exp = json.loads(exp_path.read_text())
            exp.setdefault("run", {})["status"] = "completed"
            exp["completedAt"] = datetime.now(timezone.utc).isoformat()
            exp["runContractScore"] = contract.get("runContractScore")
            exp["writerResumedAt"] = datetime.now(timezone.utc).isoformat()
            exp_path.write_text(json.dumps(exp, indent=2))
            write_lab_report(lab_dir, contract=contract, team_eval=team_eval)
        print(f"run_contract_score={contract.get('runContractScore')} fsBypass={contract.get('fsBypass')}")
        print(f"LAB_DIR={lab_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
