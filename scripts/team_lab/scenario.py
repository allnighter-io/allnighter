#!/usr/bin/env python3
"""Fresh-input generation per round, with a no-reuse ledger.

Every calibration round must use a NEW input. Reusing one input across rounds is
overfitting — exactly what the Spec Upgrade cycle did wrong. Statistical power
comes from input DIVERSITY across rounds, not repetition of one input.

    python3 scripts/team_lab/scenario.py <suite-id> [--mock]

Generates one fresh case from the suite's job distribution, refuses anything whose
normalized hash is already in the ledger, and appends it. The generator is an LLM
(env ALLN_JUDGE1_CMD — reuse a configured CLI; do NOT use the same model that
judges the same round, to avoid a self-consistency loop).

Ledger: docs/team-lab/used_inputs/<suite-id>.jsonl  (committed — the burn list).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import judge as J  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SUITES = REPO / "docs/team-lab/suites"
LEDGER_DIR = REPO / "docs/team-lab/used_inputs"


def normalize(prompt: str) -> str:
    return re.sub(r"\s+", " ", prompt.strip().lower())


def input_hash(prompt: str) -> str:
    return hashlib.sha256(normalize(prompt).encode()).hexdigest()[:16]


def load_ledger(suite_id: str) -> set[str]:
    path = LEDGER_DIR / f"{suite_id}.jsonl"
    if not path.exists():
        return set()
    seen: set[str] = set()
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            seen.add(json.loads(line)["hash"])
    return seen


def append_ledger(suite_id: str, prompt: str, case_id: str) -> None:
    LEDGER_DIR.mkdir(parents=True, exist_ok=True)
    path = LEDGER_DIR / f"{suite_id}.jsonl"
    rec = {"hash": input_hash(prompt), "caseId": case_id, "prompt": prompt}
    with path.open("a") as f:
        f.write(json.dumps(rec) + "\n")


def generator_prompt(suite: dict[str, Any], existing: list[dict[str, Any]]) -> str:
    examples = "\n".join(f"- {c.get('title')}: {c.get('prompt')[:200]}" for c in suite.get("cases", [])[:4])
    return (
        f"You design evaluation scenarios for the '{suite.get('title')}' team "
        f"(lane: {suite.get('cases', [{}])[0].get('lane', 'code')}).\n\n"
        "Produce ONE new, realistic task in this team's real job distribution — varied "
        "in difficulty and shape, NOT a copy of the examples. It must be answerable from "
        "the repo/context a real user would have. Avoid toy/synthetic puzzles.\n\n"
        f"## Example tasks (do not repeat)\n{examples}\n\n"
        'Reply with ONLY JSON: {"title": "...", "prompt": "...", '
        '"expectedQualities": ["...advisory only, never keyword-matched..."]}'
    )


def generate(suite_id: str, backend: J.Backend, *, max_tries: int = 5) -> dict[str, Any]:
    suite = json.loads((SUITES / f"{suite_id}.json").read_text())
    seen = load_ledger(suite_id)
    for _ in range(max_tries):
        raw = backend.run(generator_prompt(suite, suite.get("cases", [])))
        obj = J.extract_json(raw)
        if not obj or not obj.get("prompt"):
            continue
        if input_hash(obj["prompt"]) in seen:
            continue  # already burned — try again
        case_id = f"gen_{input_hash(obj['prompt'])}"
        append_ledger(suite_id, obj["prompt"], case_id)
        return {"caseId": case_id, "lane": suite.get("cases", [{}])[0].get("lane", "code"), **obj}
    raise SystemExit("could not generate a fresh (unused) input — widen the generator or check the ledger")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("suite_id")
    p.add_argument("--mock", action="store_true")
    args = p.parse_args()

    if args.mock:
        n = len(load_ledger(args.suite_id))
        backend: J.Backend = J.MockBackend(
            "mockgen",
            lambda _p, n=n: {"title": f"mock case {n}", "prompt": f"mock fresh scenario #{n} unique body",
                             "expectedQualities": ["advisory"]},
        )
    else:
        backends = J.backends_from_env()
        if not backends:
            raise SystemExit("set ALLN_JUDGE1_CMD (generator CLI), or use --mock")
        backend = backends[0]

    case = generate(args.suite_id, backend)
    print(json.dumps(case, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
