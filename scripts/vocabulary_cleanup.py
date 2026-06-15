#!/usr/bin/env python3
"""Team-first vocabulary cleanup — mechanical renames across the repo."""
from __future__ import annotations

import os
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# File renames: old relative path -> new relative path
FILE_RENAMES: list[tuple[str, str]] = [
    # Core types
    ("Packages/AllnighterCore/Sources/AllnighterCore/Model.swift", "Packages/AllnighterCore/Sources/AllnighterCore/Model.swift"),
    ("Packages/AllnighterCore/Sources/AllnighterCore/Model.swift", "Packages/AllnighterCore/Sources/AllnighterCore/TeamModel.swift"),
    ("Packages/AllnighterCore/Sources/AllnighterCore/TeamRun.swift", "Packages/AllnighterCore/Sources/AllnighterCore/TeamRun.swift"),
    ("Packages/AllnighterCore/Sources/AllnighterCore/WorkerAnswer.swift", "Packages/AllnighterCore/Sources/AllnighterCore/WorkerAnswer.swift"),
    ("Packages/AllnighterCore/Sources/AllnighterCore/TeamPreset.swift", "Packages/AllnighterCore/Sources/AllnighterCore/TeamPreset.swift"),
    ("Packages/AllnighterCore/Sources/AllnighterCore/TeamTool.swift", "Packages/AllnighterCore/Sources/AllnighterCore/TeamTool.swift"),
    ("Packages/AllnighterCore/Sources/AllnighterCore/PlanAnalysis.swift", "Packages/AllnighterCore/Sources/AllnighterCore/PlanAnalysis.swift"),
    ("Packages/AllnighterCore/Sources/AllnighterCore/ModelSetup.swift", "Packages/AllnighterCore/Sources/AllnighterCore/ModelSetup.swift"),
    # Engine
    ("Packages/AllnighterCore/Sources/AllnighterEngine/TeamService.swift", "Packages/AllnighterCore/Sources/AllnighterEngine/TeamService.swift"),
    ("Packages/AllnighterCore/Sources/AllnighterEngine/TeamRunCoordinator.swift", "Packages/AllnighterCore/Sources/AllnighterEngine/TeamRunCoordinator.swift"),
    ("Packages/AllnighterCore/Sources/AllnighterEngine/TeamPresetStore.swift", "Packages/AllnighterCore/Sources/AllnighterEngine/TeamPresetStore.swift"),
    ("Packages/AllnighterCore/Sources/AllnighterEngine/PlanWriter.swift", "Packages/AllnighterCore/Sources/AllnighterEngine/PlanWriter.swift"),
    # Tests
    ("Packages/AllnighterCore/Tests/AllnighterEngineTests/TeamServiceTests.swift", "Packages/AllnighterCore/Tests/AllnighterEngineTests/TeamServiceTests.swift"),
    ("Packages/AllnighterCore/Tests/AllnighterEngineTests/TeamRunCoordinatorTests.swift", "Packages/AllnighterCore/Tests/AllnighterEngineTests/TeamRunCoordinatorTests.swift"),
    # Fixtures
    ("Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/models_six.json", "Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/models_six.json"),
    ("Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/team_preset_default.json", "Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/team_preset_default.json"),
    ("Apps/AllnighterMac/Resources/Drivers/team_default.json", "Apps/AllnighterMac/Resources/Drivers/team_default.json"),
    # GUI reference
    ("docs/gui/surfaces/council", "docs/gui/surfaces/team"),
    ("docs/design-system/ui_kits/council", "docs/design-system/ui_kits/team"),
]

# Second pass: TeamModel.swift -> Model.swift after Model exists
FINAL_RENAME = (
    "Packages/AllnighterCore/Sources/AllnighterCore/TeamModel.swift",
    "Packages/AllnighterCore/Sources/AllnighterCore/Model.swift",
)

# Extensions to process
EXTENSIONS = {".swift", ".json", ".md", ".sh", ".py", ".jsx", ".js", ".html", ".prompt.md"}

# Directories to skip
SKIP_DIRS = {".git", ".build", "DerivedData", "node_modules", "_ds"}

# Ordered text replacements (longer/more specific patterns first)
REPLACEMENTS: list[tuple[str, str]] = [
    # --- Phase 1: bare model Model -> Model (before Worker -> Model) ---
    ("ModelRole", "ModelRole"),
    ("ModelSetup", "ModelSetup"),
    ("ModelHealthChecker", "ModelHealthChecker"),
    # struct/type Model when it's the bench model — use word boundaries carefully
    ("struct Model:", "struct Model:"),
    ("struct Model ", "struct Model "),
    ("[Model]", "[Model]"),
    ("[Model:", "[Model:"),
    ("(Model)", "(Model)"),
    ("(Model,", "(Model,"),
    ("(Model ", "(Model "),
    ("-> Model", "-> Model"),
    ("-> [Model]", "-> [Model]"),
    ("Model.self", "Model.self"),
    ("Model(", "Model("),
    (" Model ", " Model "),
    (" Model,", " Model,"),
    (" Model.", " Model."),
    (" Model?", " Model?"),
    (" Model]", " Model]"),
    (" Model}", " Model}"),
    (" Model:", " Model:"),
    (" Worker\n", " Model\n"),
    (" Model)", " Model)"),
    ("as Model", "as Model"),
    ("of Model", "of Model"),
    ("for Model", "for Model"),
    ("where Model", "where Model"),
    ("Element == Model", "Element == Model"),
    ("resolvePlanWriter", "resolvePlanWriter"),
    ("resolvePlanWriter", "resolvePlanWriter"),
    # Model role enum cases
    (".planWriter", ".planWriter"),
    ("case planWriter", "case planWriter"),
    ("canWritePlan", "canWritePlan"),
    # --- Phase 2: Worker -> Model (runtime assignment) ---
    ("WorkerSpec", "WorkerSpec"),
    ("Worker", "Worker"),
    ("instanceIndex", "instanceIndex"),
    ("skillId:", "skillId:"),
    ('"skillId"', '"skillId"'),
    ("SkillLibrary", "SkillLibrary"),
    # --- Phase 3: Council -> Team ---
    ("TeamRunCoordinator", "TeamRunCoordinator"),
    ("TeamRun", "TeamRun"),
    ("TeamRequest", "TeamRequest"),
    ("TeamToolResult", "TeamToolResult"),
    ("TeamGovernor", "TeamGovernor"),
    ("TeamService", "TeamService"),
    ("TeamTool", "TeamTool"),
    # --- Phase 4: Panel preset -> Team preset ---
    ("TeamPresetStore", "TeamPresetStore"),
    ("TeamPreset", "TeamPreset"),
    # --- Phase 5: Member -> ModelAnswer ---
    ("WorkerAnswerErrorKind", "WorkerAnswerErrorKind"),
    ("WorkerAnswerStatus", "WorkerAnswerStatus"),
    ("WorkerAnswer", "WorkerAnswer"),
    ("WorkerPrompt", "WorkerPrompt"),
    ("answeredWorkers", "answeredWorkers"),
    ("failedWorkerAnswers", "failedWorkerAnswers"),
    ("allWorkerAnswersSettled", "allWorkerAnswersSettled"),
    # --- Phase 6: Judge/PlanWriter -> Plan ---
    ("PlanOutputParser", "PlanOutputParser"),
    ("PlanAnalysis", "PlanAnalysis"),
    ("PlanWriter", "PlanWriter"),
    # --- Phase 7: Field renames in types ---
    ("planWriterModelId", "planWriterModelId"),
    ("plan_analysis", "plan_analysis"),
    ("plan_writer", "plan_writer"),
    ("plan_analysis_v1", "plan_analysis_v1"),
    ("plan_writer_v1", "plan_writer_v1"),
    ("plan", "plan"),
    ("Plan", "Plan"),
    ("plan", "plan"),
    ("Plan", "Plan"),
    # TeamRun fields
    ("workers", "workers"),
    ("var workers:", "var workers:"),
    ("models: [Model]", "models: [Model]"),
    ("workers: seats", "workers: seats"),
    ("workers: panel", "workers: panel"),
    ("workers =", "workers ="),
    ("run.workers", "run.workers"),
    ("$0.workers", "$0.workers"),
    ("var workerAnswers:", "var workerAnswers:"),
    ("workerAnswers:", "workerAnswers:"),
    ("run.workerAnswers", "run.workerAnswers"),
    ("$0.workerAnswers", "$0.workerAnswers"),
    (".workerAnswers[", ".workerAnswers["),
    ("workerAnswers.map", "workerAnswers.map"),
    ("workerAnswers.filter", "workerAnswers.filter"),
    ("workerAnswers.allSatisfy", "workerAnswers.allSatisfy"),
    ("workerAnswers.first", "workerAnswers.first"),
    ("workerAnswers.indices", "workerAnswers.indices"),
    # Model (runtime) model reference field
    ("var workerId: String\n    /// 0-based index", "var modelId: String\n    /// 0-based index"),
    ("workerId: String,\n        instanceIndex", "modelId: String,\n        instanceIndex"),
    ("self.modelId = modelId", "self.modelId = modelId"),
    ("spec.modelId", "spec.modelId"),
    ("worker.modelId", "worker.modelId"),
    ("$0.modelId", "$0.modelId"),
    ("modelId: $0.id", "modelId: $0.id"),
    ("modelId: model.id", "modelId: model.id"),
    ("modelId: model.id", "modelId: model.id"),
    ("modelId: strongest.id", "modelId: strongest.id"),
    ("workerByID[worker.modelId]", "modelByID[worker.modelId]"),
    ("modelByID[worker.modelId]", "modelByID[worker.modelId]"),
    ("Dictionary(models.map { ($0.id, $0) }", "Dictionary(models.map { ($0.id, $0) }"),
    ("models: [Model]", "models: [Model]"),
    ("seats: [Model]", "teamWorkers: [Model]"),
    ("for worker in teamWorkers", "for worker in teamWorkers"),
    ("for worker in teamWorkers", "for worker in teamWorkers"),
    ("worker.skillId", "worker.skillId"),
    ("worker.id", "worker.id"),
    ("$0.id, workerId: $0.modelId", "$0.id, modelId: $0.modelId"),
    ("WorkerAnswer(workerId:", "WorkerAnswer(workerId:"),
    ("workerId: $0.modelId, status:", "modelId: $0.modelId, status:"),
    ("func workerAnswer(workerId:", "func workerAnswer(workerId:"),
    ("$0.workerId == workerId", "$0.modelId == workerId"),
    ("teamSummary", "teamSummary"),
    ("workerCount:", "workerCount:"),
    ("Fixtures.models()", "Fixtures.models()"),
    ("func models()", "func models()"),
    ("models()", "models()"),
    ("tieredPresets(models:", "tieredPresets(models:"),
    ("builtInDefault(\n        panel:", "builtInDefault(\n        models:"),
    ("models: [Model]", "models: [Model]"),
    ("models.map", "models.map"),
    ("models.first", "models.first"),
    ("models.filter", "models.filter"),
    ("models.prefix", "models.prefix"),
    ("Array(models", "Array(models"),
    ("let six = models", "let six = models"),
    ("diverseTeam = models", "diverseTeam = models"),
    ("diverseTeam.isEmpty ? six : diverseTeam", "diverseTeam.isEmpty ? six : diverseTeam"),
    ("diverseTeam", "diverseTeam"),
    # WorkerFailure -> ModelFailure
    ("WorkerFailure", "WorkerFailure"),
    ("failedWorkers", "failedWorkers"),
    ("sourceWorkerIds", "sourceWorkerIds"),
    # Analysis structures
    ("workerId", "workerId"),
    # Environment / config
    ("ALLNIGHTER_TEAM_DEPTH", "ALLNIGHTER_TEAM_DEPTH"),
    ("maxConcurrentTeamRuns", "maxConcurrentTeamRuns"),
    ("maxTeamRunDepth", "maxTeamRunDepth"),
    # Fixture names
    ("models_six", "models_six"),
    ("team_preset_default", "team_preset_default"),
    ("modelsSix", "modelsSix"),
    ("teamPresetDefault", "teamPresetDefault"),
    ("team_default", "team_default"),
    ("teamFileName", "teamFileName"),
    # CLI / MCP
    ("team_ask", "team_ask"),
    ("team_presets", "team_presets"),
    ("team_recall", "team_recall"),
    ("alln team", "alln team"),
    ("alln doctor", "alln doctor"),
    # Preset display names
    ("Fast Team", "Fast Team"),
    ("Quality Team", "Quality Team"),
    ("Diverse Team", "Diverse Team"),
    # Model IDs worker_* -> model_*
    ("model_chatgpt", "model_chatgpt"),
    ("model_opus", "model_opus"),
    ("model_sonnet", "model_sonnet"),
    ("model_composer", "model_composer"),
    ("model_gemini", "model_gemini"),
    ("model_grok", "model_grok"),
    # Run status
    ("case planning", "case planning"),
    (".planning", ".planning"),
    ("planning", "planning"),
    # File path references
    ("TeamServiceTests", "TeamServiceTests"),
    ("TeamRunCoordinatorTests", "TeamRunCoordinatorTests"),
    ("Model.swift", "Model.swift"),
    ("Model.swift", "Model.swift"),
    ("TeamRun.swift", "TeamRun.swift"),
    ("WorkerAnswer.swift", "WorkerAnswer.swift"),
    ("TeamPreset.swift", "TeamPreset.swift"),
    ("TeamTool.swift", "TeamTool.swift"),
    ("PlanAnalysis.swift", "PlanAnalysis.swift"),
    ("TeamService.swift", "TeamService.swift"),
    ("TeamRunCoordinator.swift", "TeamRunCoordinator.swift"),
    ("TeamPresetStore.swift", "TeamPresetStore.swift"),
    ("PlanWriter.swift", "PlanWriter.swift"),
]

# Additional JSON-specific field renames for TeamRun
JSON_REPLACEMENTS: list[tuple[str, str]] = [
    ('"panel"', '"workers"'),
    ('"members"', '"workerAnswers"'),
    ('"skillId"', '"skillId"'),
    ('"seats"', '"workerSpecs"'),
]

# Public copy replacements (user-facing strings in Swift)
COPY_REPLACEMENTS: list[tuple[str, str]] = [
    ("Run council", "Run team"),
    ("run council", "run team"),
    ("Ask council", "Ask team"),
    ("ask council", "ask team"),
    ("the council", "the team"),
    ("The council", "The team"),
    ("a council", "a team"),
    ("A council", "A team"),
    ("Council run", "Team run"),
    ("council run", "team run"),
    ("council runs", "team runs"),
    ("Council preset", "Team preset"),
    ("council preset", "team preset"),
    ("council presets", "team presets"),
    ("prior councils", "prior team runs"),
    ("Panel seat", "Worker"),
    ("panel seat", "worker"),
    ("panel seats", "workers"),
    ("Panel member", "Worker"),
    ("panel member", "worker"),
    ("Add seat", "Add worker"),
    ("add seat", "add worker"),
    ("seat count", "worker count"),
    ("Member answer", "Worker answer"),
    ("member answer", "worker answer"),
    ("member answers", "worker answers"),
    ("PlanWriter", "Plan writer"),
    ("synthesizer", "plan writer"),
    ("allnighter", "alln"),
    ("Council-as-Tool", "Team-as-Tool"),
    ("council engine", "team engine"),
    ("local Fusion council", "local team run"),
    ("run a council", "run a team"),
    ("Run a council", "Run a team"),
    ("list the council presets", "list the team presets"),
    ("search prior councils", "search prior team runs"),
    ("local multi-model council", "local multi-model team"),
    ("synthesized plan", "synthesized plan"),
    ("no plan", "no plan"),
    ("Diverse Team", "Diverse Team"),
    ("Self-Double", "Self-Double"),  # keep
    ("Founder's Six", "Founder's Six"),  # keep
]


def should_process(path: Path) -> bool:
    if path.suffix not in EXTENSIONS and path.name not in {"AGENTS.md", "ALLNIGHTER.md", "README.md"}:
        if path.suffix:
            return False
    parts = set(path.parts)
    if parts & SKIP_DIRS:
        return False
    # Skip the cleanup doc itself (documents old terms intentionally)
    if path.name == "Team_First_Vocabulary_Cleanup.md":
        return False
    # Skip archive — historical
    if "archive" in path.parts:
        return False
    # Skip design-system uploads (historical mentor input)
    if "uploads" in path.parts and "design-system" in path.parts:
        return False
    # Skip duplicate hashed upload copies
    if re.search(r"-[a-f0-9]{8}\.md$", path.name):
        return False
    return True


def apply_replacements(text: str, replacements: list[tuple[str, str]]) -> str:
    for old, new in replacements:
        text = text.replace(old, new)
    return text


def process_file(path: Path) -> bool:
    try:
        original = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return False
    text = original
    text = apply_replacements(text, REPLACEMENTS)
    if path.suffix == ".json":
        text = apply_replacements(text, JSON_REPLACEMENTS)
    if path.suffix == ".swift":
        text = apply_replacements(text, COPY_REPLACEMENTS)
    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def rename_files() -> None:
    for old_rel, new_rel in FILE_RENAMES:
        old = ROOT / old_rel
        new = ROOT / new_rel
        if not old.exists():
            print(f"SKIP rename (missing): {old_rel}")
            continue
        new.parent.mkdir(parents=True, exist_ok=True)
        if new.exists():
            print(f"SKIP rename (target exists): {new_rel}")
            continue
        shutil.move(str(old), str(new))
        print(f"RENAMED: {old_rel} -> {new_rel}")


def main() -> None:
    os.chdir(ROOT)
    print("=== File renames ===")
    rename_files()

  # Final rename TeamWorker -> Model
    old, new = FINAL_RENAME
    old_path, new_path = ROOT / old, ROOT / new
    if old_path.exists() and not new_path.exists():
        shutil.move(str(old_path), str(new_path))
        print(f"RENAMED: {old} -> {new}")

    print("\n=== Content replacements ===")
    changed = 0
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            path = Path(dirpath) / name
            if should_process(path):
                if process_file(path):
                    changed += 1
                    print(f"UPDATED: {path.relative_to(ROOT)}")
    print(f"\n{changed} files updated")


if __name__ == "__main__":
    main()
