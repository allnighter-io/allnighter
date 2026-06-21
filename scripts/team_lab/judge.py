#!/usr/bin/env python3
"""LLM-judge evaluation for the team lab.

Design (locked 2026-06-21, see docs/phases/MCP_Run_Factory_Team_Lab.md):

- NO deterministic scoring of judgment. Quality is decided by LLM judges only.
- The GATE is output-only and BLIND: judges see two anonymized outputs (A/B in
  randomized order) for the SAME input and pick the better one. They never see
  the prompts, the model names, or which side is the incumbent.
- TWO judges of DIFFERENT model families, run in isolation. A change is kept only
  if BOTH judges independently pick the candidate. Ties go to the incumbent.
- The WORKER is the unit of optimization: judge every worker's output, not just
  the final deliverable, so each role's prompt can be banked independently.
- The deliverable is the unit of suspicion: judged too, but it AUDITS (flags
  interaction regressions) — it does not veto a clean per-worker win.
- Prompts are only opened AFTER the blind verdicts, to generate next-round
  hypotheses (the non-voting idea-engine).

This module holds the backends, prompt builders, and the pure decision logic.
The pure logic is fully unit-tested with a mock backend (no model quota).
"""
from __future__ import annotations

import hashlib
import json
import os
import shlex
import subprocess
from dataclasses import dataclass, field
from typing import Any, Callable, Protocol

# --------------------------------------------------------------------------- #
# JSON extraction
# --------------------------------------------------------------------------- #


def extract_json(text: str) -> dict[str, Any] | None:
    """First balanced top-level JSON object in a model's free text."""
    start = text.find("{")
    while start != -1:
        depth = 0
        in_str = False
        esc = False
        for i in range(start, len(text)):
            ch = text[i]
            if in_str:
                if esc:
                    esc = False
                elif ch == "\\":
                    esc = True
                elif ch == '"':
                    in_str = False
                continue
            if ch == '"':
                in_str = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    try:
                        return json.loads(text[start : i + 1])
                    except json.JSONDecodeError:
                        break
        start = text.find("{", start + 1)
    return None


# --------------------------------------------------------------------------- #
# Backends — a judge is just "give it a prompt, get text back"
# --------------------------------------------------------------------------- #


class Backend(Protocol):
    name: str

    def run(self, prompt: str) -> str: ...


@dataclass
class CliBackend:
    """Calls a provider CLI (the user's existing subscription — never an API key).

    The command receives the prompt on stdin and must print the model's reply to
    stdout. Configure two DIFFERENT model families via env, e.g.:

        export ALLN_JUDGE1_CMD="claude -p"
        export ALLN_JUDGE2_CMD="codex exec -"

    The exact invocation is environment-specific; the dev validates it live.
    """

    name: str
    command: str
    timeout_s: int = 240

    def run(self, prompt: str) -> str:
        argv = shlex.split(self.command)
        proc = subprocess.run(
            argv,
            input=prompt,
            capture_output=True,
            text=True,
            timeout=self.timeout_s,
        )
        if proc.returncode != 0:
            raise RuntimeError(f"judge backend {self.name} exit {proc.returncode}: {proc.stderr[:400]}")
        return proc.stdout


def mock_prefer_longer(prompt: str) -> dict[str, Any]:
    """Deterministic mock verdict: pick the longer of the two output blocks, ignoring
    the trailing instructions. For pipeline smoke tests only — never real judgment."""
    low = prompt.lower()
    ia, ib = low.find("output a"), low.find("output b")
    if ia == -1 or ib == -1 or ib <= ia:
        return {"winner": "tie", "confidence": "low", "reason": "mock: no segments"}
    ii = low.find("instruction", ib)
    seg_a = prompt[ia:ib]
    seg_b = prompt[ib:ii] if ii > ib else prompt[ib:]
    return {"winner": "A" if len(seg_a) >= len(seg_b) else "B",
            "confidence": "low", "reason": "mock: longer output block"}


@dataclass
class MockBackend:
    """Deterministic backend for testing orchestration without quota.

    `rule(prompt) -> verdict dict` lets a test decide winners by content.
    """

    name: str
    rule: Callable[[str], dict[str, Any]]

    def run(self, prompt: str) -> str:
        return json.dumps(self.rule(prompt))


def backends_from_env() -> list[Backend]:
    out: list[Backend] = []
    for i in (1, 2):
        cmd = os.environ.get(f"ALLN_JUDGE{i}_CMD")
        if cmd:
            out.append(CliBackend(name=f"judge{i}", command=cmd))
    return out


# --------------------------------------------------------------------------- #
# Blind A/B presentation — anonymize + deterministically randomize order
# --------------------------------------------------------------------------- #


@dataclass
class Blinded:
    output_a: str
    candidate_is: str  # "A" or "B" — which slot holds the candidate (hidden from the judge)
    output_b: str

    def resolve(self, winner: str) -> str:
        """Map a judge's A/B/tie verdict to baseline/candidate/tie."""
        if winner == "tie":
            return "tie"
        if winner not in ("A", "B"):
            return "invalid"
        return "candidate" if winner == self.candidate_is else "baseline"


def blind_pair(baseline: str, candidate: str, *, seed: str) -> Blinded:
    """Place baseline/candidate into A/B slots; order seeded so it is reproducible
    on resume but not guessable as 'B is always the new one'."""
    h = int(hashlib.sha256(seed.encode()).hexdigest(), 16)
    candidate_is_a = (h & 1) == 0
    if candidate_is_a:
        return Blinded(output_a=candidate, candidate_is="A", output_b=baseline)
    return Blinded(output_a=baseline, candidate_is="B", output_b=candidate)


# --------------------------------------------------------------------------- #
# Prompt builders
# --------------------------------------------------------------------------- #

_GATE_RULES = (
    "Judge ONLY which output better accomplishes the task. You do NOT know which "
    "system produced which; do not try to guess. Do not reward length, confidence, "
    "or formatting — reward correctness, evidence actually used, and usefulness to "
    "the person who asked. If neither is clearly better, answer \"tie\".\n\n"
    'Reply with ONLY a JSON object: {"winner": "A"|"B"|"tie", '
    '"confidence": "low"|"medium"|"high", "reason": "<=2 sentences citing specifics"}'
)


def deliverable_prompt(task: str, blinded: Blinded) -> str:
    return (
        "You are an expert evaluator comparing two responses to the same task.\n\n"
        f"## Task\n{task}\n\n"
        f"## Output A\n{blinded.output_a}\n\n"
        f"## Output B\n{blinded.output_b}\n\n"
        f"## Instructions\n{_GATE_RULES}"
    )


def worker_prompt(task: str, role_label: str, blinded: Blinded) -> str:
    return (
        "You are an expert evaluator. Two specialists were each given the SAME task "
        f"in the role of: **{role_label}**. Compare only how well each did THAT role.\n\n"
        f"## Task\n{task}\n\n"
        f"## Specialist output A\n{blinded.output_a}\n\n"
        f"## Specialist output B\n{blinded.output_b}\n\n"
        f"## Instructions\n{_GATE_RULES}"
    )


def hypotheses_prompt(role_label: str, baseline_prompt: str, candidate_prompt: str, verdict_summary: str) -> str:
    """Un-blind idea-engine. Non-voting: this never decides keep/discard."""
    return (
        "You are improving a multi-agent team by editing worker prompts. The blind "
        "output verdicts are already decided; your job is ONLY to propose what to try "
        "next.\n\n"
        f"## Role\n{role_label}\n\n"
        f"## Current (incumbent) prompt\n{baseline_prompt}\n\n"
        f"## Candidate prompt just tested\n{candidate_prompt}\n\n"
        f"## Blind verdict\n{verdict_summary}\n\n"
        "## Instructions\nPropose 1–3 concrete, single-variable prompt changes to test "
        "next, each with the one effect you expect it to have. Be specific and brief. "
        'Reply with ONLY JSON: {"hypotheses": [{"change": "...", "expected_effect": "..."}]}'
    )


# --------------------------------------------------------------------------- #
# Run a judge over a blinded pair
# --------------------------------------------------------------------------- #


def judge_pair(backend: Backend, prompt: str, blinded: Blinded) -> dict[str, Any]:
    raw = backend.run(prompt)
    verdict = extract_json(raw) or {}
    winner = verdict.get("winner")
    if winner not in ("A", "B", "tie"):
        return {"backend": backend.name, "winner": "invalid", "resolved": "invalid",
                "confidence": verdict.get("confidence"), "reason": verdict.get("reason"),
                "raw": raw[:500]}
    return {
        "backend": backend.name,
        "winner": winner,
        "resolved": blinded.resolve(winner),
        "confidence": verdict.get("confidence"),
        "reason": verdict.get("reason"),
    }


# --------------------------------------------------------------------------- #
# Pure decision logic — the heart, fully testable
# --------------------------------------------------------------------------- #


@dataclass
class RoleDecision:
    role_key: str
    role_label: str
    verdicts: list[dict[str, Any]]
    keep_candidate: bool
    note: str = ""


@dataclass
class CompareDecision:
    role_decisions: list[RoleDecision] = field(default_factory=list)
    banked_roles: list[str] = field(default_factory=list)
    deliverable_verdicts: list[dict[str, Any]] = field(default_factory=list)
    deliverable_outcome: str = "tie"          # candidate | baseline | tie | invalid
    interaction_warning: bool = False
    unmatched_roles: list[str] = field(default_factory=list)


def _unanimous(verdicts: list[dict[str, Any]], target: str) -> bool:
    """Every judge must independently resolve to `target` (and there must be judges)."""
    return bool(verdicts) and all(v.get("resolved") == target for v in verdicts)


def decide_role(role_key: str, role_label: str, verdicts: list[dict[str, Any]]) -> RoleDecision:
    """Bank the candidate prompt for this role ONLY if BOTH judges agree it is better.
    Any tie, any baseline-better, any invalid, or any disagreement → keep incumbent."""
    keep = _unanimous(verdicts, "candidate")
    if keep:
        note = "both judges: candidate better"
    elif _unanimous(verdicts, "baseline"):
        note = "both judges: incumbent better — keep incumbent"
    else:
        note = "no unanimous candidate win — keep incumbent (tie goes to incumbent)"
    return RoleDecision(role_key, role_label, verdicts, keep, note)


def decide_compare(role_decisions: list[RoleDecision],
                   deliverable_verdicts: list[dict[str, Any]],
                   unmatched_roles: list[str] | None = None) -> CompareDecision:
    """Combine per-role decisions with the deliverable audit.

    Per-worker wins are banked on their own evidence. The deliverable is an AUDIT:
    if any role was banked but the deliverable regressed (incumbent better), raise
    an interaction warning so the dev re-checks the bundle — it does NOT unbank.
    """
    banked = [d.role_key for d in role_decisions if d.keep_candidate]
    if _unanimous(deliverable_verdicts, "candidate"):
        outcome = "candidate"
    elif _unanimous(deliverable_verdicts, "baseline"):
        outcome = "baseline"
    elif deliverable_verdicts and all(v.get("resolved") == "invalid" for v in deliverable_verdicts):
        outcome = "invalid"
    else:
        outcome = "tie"
    interaction = bool(banked) and outcome == "baseline"
    return CompareDecision(
        role_decisions=role_decisions,
        banked_roles=banked,
        deliverable_verdicts=deliverable_verdicts,
        deliverable_outcome=outcome,
        interaction_warning=interaction,
        unmatched_roles=unmatched_roles or [],
    )


# --------------------------------------------------------------------------- #
# Role mapping across baseline/candidate runs
# --------------------------------------------------------------------------- #


def role_key(worker: dict[str, Any]) -> str:
    """Stable identity for a role across runs: skill + instance, not model."""
    skill = worker.get("skillId") or worker.get("skillName") or worker.get("purpose") or worker.get("id")
    idx = worker.get("instanceIndex")
    return f"{skill}#{idx}" if idx is not None else str(skill)


def map_roles(baseline_workers: list[dict[str, Any]],
              candidate_workers: list[dict[str, Any]]) -> tuple[list[tuple[str, dict, dict]], list[str]]:
    """Match answer/review roles 1:1 by role_key. Plan/writer handled via deliverable.
    Returns (matched, unmatched_keys). Structural changes (added/removed roles) show
    up as unmatched and fall back to the deliverable gate."""
    def index(ws: list[dict[str, Any]]) -> dict[str, dict[str, Any]]:
        out: dict[str, dict[str, Any]] = {}
        for w in ws:
            if w.get("purpose") == "plan":
                continue
            out[role_key(w)] = w
        return out

    bi, ci = index(baseline_workers), index(candidate_workers)
    matched = [(k, bi[k], ci[k]) for k in bi if k in ci]
    unmatched = sorted((set(bi) ^ set(ci)))
    return matched, unmatched
