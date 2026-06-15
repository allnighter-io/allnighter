# Team-First Vocabulary Cleanup

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

Run the three proof greps documented in `docs/operations/Execution-Playbook.md`
§ Team vocabulary closeout (legacy public noun scan). All must return no matches.

## Done When (met)

- `docs/phases/README.md` routes vocabulary to `Work_Order_Team_Model.md`
- CLI uses `alln team` and `alln models`; MCP uses `team_*` tools
- `TeamRunJSON` fixture exists (`team_run.json`)
- Mac GUI says Run team / Ask the team / Team sidebar
- MVP and GUI docs use forward vocabulary only
