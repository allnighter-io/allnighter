#!/usr/bin/env python3
"""Zero legacy public vocabulary in docs/. Mechanical pass + file renames."""
from __future__ import annotations

import os
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOCS = ROOT / "docs"

SKIP_DIRS = {".git", "node_modules"}

EXTENSIONS = {
    ".md", ".swift", ".html", ".jsx", ".js", ".css", ".json", ".prompt.md", ".d.ts"
}

# Longer patterns first
REPLACEMENTS: list[tuple[str, str]] = [
    ("CouncilRun", "TeamRun"),
    ("PanelSeatSpec", "WorkerSpec"),
    ("PanelSeat", "Worker"),
    ("PanelPreset", "TeamPreset"),
    ("MemberResponse", "WorkerAnswer"),
    ("memberResponses", "workerAnswers"),
    ("panelSeats", "workers"),
    ("masterPlan", "plan"),
    ("Master Plan", "Plan"),
    ("master plan", "plan"),
    ("Master plan", "Plan"),
    ("allnighter ask", "alln team"),
    ("allnighter detect", "alln doctor"),
    ("council_ask", "team_ask"),
    ("council_presets", "team_presets"),
    ("council_recall", "team_recall"),
    ("council_run", "team_run"),
    ("Council run", "Team run"),
    ("council run", "team run"),
    ("council runs", "team runs"),
    ("council preset", "team preset"),
    ("Council preset", "Team preset"),
    ("council presets", "team presets"),
    ("Design Council", "Design team"),
    ("Image Council", "Image team"),
    ("Design council", "Design team"),
    ("design council", "design team"),
    ("The Council", "The team"),
    ("the council", "the team"),
    ("a council", "a team"),
    ("A council", "A team"),
    ("Council-as-Tool", "Team-as-Tool"),
    ("Council as Tool", "Team as Tool"),
    ("Council ", "Team "),
    ("council ", "team "),
    (" Council", " Team"),
    (" council", " team"),
    ("panel orchestrator", "team orchestrator"),
    ("panel fan-out", "team fan-out"),
    ("panel fanout", "team fanout"),
    ("panel_fanout", "team_fanout"),
    ("panel member", "worker"),
    ("Panel member", "Worker"),
    ("panel members", "workers"),
    ("panel seat", "worker"),
    ("Panel seat", "Worker"),
    ("panel seats", "workers"),
    ("panel preset", "team preset"),
    ("Panel preset", "Team preset"),
    ("panel presets", "team presets"),
    ("ask panel", "ask team"),
    ("Ask panel", "Ask team"),
    ("ask the panel", "ask the team"),
    ("Ask the panel", "Ask the team"),
    ("the panel", "the team"),
    ("The panel", "The team"),
    ("a panel", "a team"),
    ("A panel", "a team"),
    ("panel of models", "team of models"),
    ("panel of seats", "team of workers"),
    ("panel of workers", "team of workers"),
    ("Custom panel", "Custom team"),
    ("custom panel", "custom team"),
    ("default panel", "default team"),
    ("design panel", "design team"),
    ("six-worker panel", "six-worker team"),
    ("founder's six", "Founder's Six"),
    ("member answer", "worker answer"),
    ("Member answer", "Worker answer"),
    ("member answers", "worker answers"),
    ("synthesizer", "plan writer"),
    ("Synthesizer", "Plan writer"),
    ("seat count", "worker count"),
    ("Add seat", "Add worker"),
    ("add seat", "add worker"),
    ("seat index", "instance index"),
    ("seatIndex", "instanceIndex"),
    ("seatId", "workerId"),
    ("seat id", "worker id"),
    ("per-seat", "per-worker"),
    ("Per-seat", "Per-worker"),
    ("one seat", "one worker"),
    ("each seat", "each worker"),
    ("failed seat", "failed worker"),
    ("panel_default", "team_default"),
    ("panel_six", "models_six"),
    ("panel_six", "models_six"),
    ("Fast Council", "Fast Team"),
    ("Quality Council", "Quality Team"),
    ("Diverse Panel", "Diverse Team"),
    ("Run council", "Run team"),
    ("run council", "run team"),
    ("Council health", "Team health"),
    ("CouncilState", "TeamState"),
    ("CouncilView", "TeamView"),
    ("CouncilData", "TeamData"),
    ("CouncilApp", "TeamApp"),
    ("ui_kits/council", "ui_kits/team"),
    ("surfaces/council", "surfaces/team"),
    ("judgeWorkerId", "planWriterModelId"),
    ("judge_analysis", "plan_analysis"),
    ("judge_plan", "plan_writer"),
    ("judge success", "plan writer success"),
    ("judge call", "plan writer call"),
    ("judge writes", "plan writer writes"),
    ("judge label", "plan writer label"),
    ("the judge", "the plan writer"),
    ("The judge", "The plan writer"),
    ("a judge", "a plan writer"),
    ("Judge ", "Plan writer "),
    (" judge", " plan writer"),
    ("Judgment", "Review"),
    ("judgment", "review"),
    ("RB6_Council", "RB6_Team"),
    ("Design_Council", "Design_Team"),
    ("Image_Council", "Image_Team"),
    ("Master_Plan", "Plan"),
    ("And_Master_Plan", "And_Plan"),
    ("prior councils", "prior team runs"),
    ("local councils", "local team runs"),
    ("multi-model council", "multi-model team"),
    ("Council ↔", "Team ↔"),
    ("Council,", "Team,"),
    ("· council", "· team"),
    ("Run council", "Run team"),
    ("No council", "No team run"),
    ("hollow council", "hollow team"),
    ("legacy panel", "legacy team lineup"),
    ("legacy council", "legacy team"),
    ("council/panel", "team"),
    ("panel/", "team/"),
    ("Panel/", "Team/"),
    (" Panel", " Team"),
    (" panel", " team"),
    ("PanelSidebar", "TeamSidebar"),
    ("Panel ", "Team "),
    (" seats", " workers"),
    (" seat", " worker"),
    ("Seat", "Worker"),
    ("seated", "on team"),
    ("isSeated", "isOnTeam"),
    ("seatCount", "workerCount"),
    ("expandedSeats", "expandedWorkers"),
    ("currentSeats", "currentWorkerSpecs"),
    ("panelAnswerRate", "teamAnswerRate"),
    ("judgeSuccessRate", "planWriterSuccessRate"),
    ("failedSeats", "failedWorkers"),
    ("sourceSeatIds", "sourceWorkerIds"),
    ("rejectedSeatIds", "rejectedWorkerIds"),
    ("forSeat", "forWorker"),
    ("IdentifiedSeat", "IdentifiedWorker"),
    ("fullscreenSeat", "fullscreenWorker"),
    ("designSeats", "designWorkers"),
    ("chosenSeatId", "chosenWorkerId"),
]

# Phrases that must not contain forbidden words after cleanup
FORBIDDEN = re.compile(
    r"\b(council|Council|panel|Panel|seat|Seat|member answer|Member answer|"
    r"master plan|Master plan|synthesizer|Synthesizer|judge|Judge)\b"
)

SUPERSEDED_BANNER = """> **Vocabulary (2026-06-15).** Current product language lives in
> `docs/phases/Work_Order_Team_Model.md`. This doc uses team/model/worker/plan
> terms only.

"""

FILE_RENAMES = [
    ("docs/gui/surfaces/team/CouncilState.reference.swift", "docs/gui/surfaces/team/TeamState.reference.swift"),
    ("docs/mvp/RB6_Council_As_Tool.md", "docs/mvp/RB6_Team_As_Tool.md"),
    ("docs/mvp/Design0_Design_Council_Overview.md", "docs/mvp/Design0_Design_Team_Overview.md"),
    ("docs/mvp/Design1_Image_Council.md", "docs/mvp/Design1_Image_Team.md"),
    ("docs/mvp/04_Synthesis_And_Master_Plan.md", "docs/mvp/04_Synthesis_And_Plan.md"),
]


def should_process(path: Path) -> bool:
    if path.suffix not in EXTENSIONS and path.name not in {"README", "SKILL.md"}:
        if not path.suffix:
            return False
    parts = set(path.parts)
    if parts & SKIP_DIRS:
        return False
    return path.is_relative_to(DOCS)


def apply_replacements(text: str) -> str:
    for old, new in REPLACEMENTS:
        text = text.replace(old, new)
    return text


def add_banner_if_mvp(path: Path, text: str) -> str:
    if "/mvp/" not in str(path) or text.startswith("> **Vocabulary"):
        return text
    if path.name == "README.md":
        return text  # handled separately
    return SUPERSEDED_BANNER + text


def process_file(path: Path) -> bool:
    try:
        original = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False
    text = apply_replacements(original)
    text = add_banner_if_mvp(path, text)
    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def rewrite_archive_cleanup_doc(path: Path) -> None:
    """Archive cleanup doc: describe outcome without re-listing forbidden nouns."""
    path.write_text("""# Team-First Vocabulary Cleanup

Status: **Complete** (2026-06-15). Archived to `docs/archive/phases/`.
Owner: Founder + Shared Core + Mac + CLI + iOS
Updated: 2026-06-15

## Outcome

Public product language is **team-first** everywhere in code, CLI, Mac app, GUI
briefs, fixtures, and forward docs. Bench models sit at rest; runtime lineup
rows are **workers** (`model + skill`); one prompt fans out as a **team run**;
outputs are **worker answers** and a synthesized **plan**.

Durable owners going forward:

- Vocabulary: `docs/phases/Work_Order_Team_Model.md`
- Machine contract: `docs/phases/CLI_Product_Spine.md` +
  `docs/phases/CLI_Implementation_Contract.md`
- Implementation proof: `Packages/AllnighterCore` types (`TeamRun`, `Model`,
  `Worker`, `WorkerAnswer`, `TeamPreset`) and `alln team`

## Works Test (must be zero hits in `docs/`)

```bash
rg -n '\\\\b(council|Council|panel|Panel|seat|Seat|member answer|Member answer|master plan|Master plan|synthesizer|Synthesizer|judge|Judge)\\\\b' docs
rg -n 'CouncilRun|PanelSeat|PanelPreset|MemberResponse|masterPlan|panelSeats|memberResponses' docs
rg -n 'allnighter ask|allnighter detect|council_ask|council_|masterPlan|panelSeats|memberResponses' docs
```

## Done When (met)

- `docs/phases/README.md` routes vocabulary to `Work_Order_Team_Model.md`
- CLI uses `alln team` and `alln models`; MCP uses `team_*` tools
- `TeamRunJSON` fixture exists (`team_run.json`)
- Mac GUI says Run team / Ask the team / Team sidebar
- MVP and GUI docs use forward vocabulary only
""", encoding="utf-8")


def rewrite_mvp_readme(path: Path) -> None:
    path.write_text("""# Allnighter MVP — Team-run foundation (parallel judgment, zero marginal cost)

> **This folder is the source of truth for the built MVP foundation.**
> New post-MVP work starts in `docs/phases/`. This folder describes what
> shipped using **current product vocabulary** (`docs/phases/Work_Order_Team_Model.md`).

Status: **Build-ready.** Mac first. iOS is a designed-for, deferred follow-on.
Updated: 2026-06-15

---

## 0. One-Page Brief

The founder runs a fixed, proven ritual for every non-trivial decision:

1. Take **one prompt**.
2. Send it, unchanged, to a **team** of models the founder **already pays for**:
   ChatGPT 5.5, Opus 4.8, Sonnet 4.6, Composer 2.5, Gemini Flash, Grok Build.
3. Ask a configured **plan writer** (built-in default: **Opus 4.8**) to turn
   all **worker answers** into a single **plan**.

Today that is ~12 manual copy/paste actions per question. The MVP deletes that labor:

> **One prompt in. One plan out. The team answers in parallel.
> You never touch the clipboard.**

Hard constraints:

- **Zero marginal cost.** Local CLIs the founder already pays for. No API keys.
- **Local and private.** Everything runs on the Mac.
- **One command / one click.** Fan-out + plan writing is a single action.

This is **not** a model provider, chat aggregator, IDE, or coding agent. It is a
**team orchestrator + plan writer** on top of CLIs the user installed.

---

## 1. The MVP Loop

```text
Prompt → Team (workers) → Worker answers → Plan → (optional) Work order
```

---

## 2. Doc Map

| Doc | Topic |
| --- | --- |
| [`00_MVP_Architecture.md`](00_MVP_Architecture.md) | End-to-end architecture |
| [`01_Core_Package.md`](01_Core_Package.md) | Shared types and fixtures |
| [`02_Worker_Drivers_And_Fanout.md`](02_Worker_Drivers_And_Fanout.md) | Model drivers and fan-out |
| [`03_Mac_App_And_Run_Loop.md`](03_Mac_App_And_Run_Loop.md) | Mac app run loop |
| [`04_Synthesis_And_Plan.md`](04_Synthesis_And_Plan.md) | Plan writer and analysis |
| [`05_History_Presets_And_Distribution.md`](05_History_Presets_And_Distribution.md) | Presets and history |
| [`06_Fusion_Grade_Synthesis_And_Evals.md`](06_Fusion_Grade_Synthesis_And_Evals.md) | Fusion-grade synthesis |
| [`Design0_Design_Team_Overview.md`](Design0_Design_Team_Overview.md) | Design lane overview |
| [`Design1_Image_Team.md`](Design1_Image_Team.md) | Image design team |
| [`Design2_Build_This.md`](Design2_Build_This.md) | Build-this handoff |
| [`RB0_Judgment_Workflow_Overview.md`](RB0_Judgment_Workflow_Overview.md) | Review workflow chain |
| [`RB1`–`RB6`](RB1_Workflow_Presets_And_Stage_Primitives.md) | Review-board stages |
| [`RB6_Team_As_Tool.md`](RB6_Team_As_Tool.md) | `alln team` tool surface |

Forward vocabulary: `docs/phases/Work_Order_Team_Model.md`.
""", encoding="utf-8")


def main() -> None:
    os.chdir(ROOT)

    # Remove stale duplicate council GUI folder
    stale = DOCS / "gui/surfaces/council"
    if stale.exists():
        shutil.rmtree(stale)
        print(f"REMOVED stale {stale.relative_to(ROOT)}")

    for old, new in FILE_RENAMES:
        o, n = ROOT / old, ROOT / new
        if o.exists() and not n.exists():
            n.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(o), str(n))
            print(f"RENAMED {old} -> {new}")

    changed = 0
    for dirpath, dirnames, filenames in os.walk(DOCS):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = Path(dirpath) / name
            if should_process(path):
                if process_file(path):
                    changed += 1

    rewrite_archive_cleanup_doc(DOCS / "archive/phases/Team_First_Vocabulary_Cleanup.md")
    rewrite_mvp_readme(DOCS / "mvp/README.md")
    print(f"UPDATED {changed} files under docs/")


if __name__ == "__main__":
    main()
