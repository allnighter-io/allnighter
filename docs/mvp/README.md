# Allnighter MVP — Team-run foundation (parallel judgment, zero marginal cost)

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
| [`RB0_Review_Workflow_Overview.md`](RB0_Review_Workflow_Overview.md) | Review workflow chain |
| [`RB1`–`RB6`](RB1_Workflow_Presets_And_Stage_Primitives.md) | Review-board stages |
| [`RB6_Team_As_Tool.md`](RB6_Team_As_Tool.md) | `alln team` tool surface |

Forward vocabulary: `docs/phases/Work_Order_Team_Model.md`.
