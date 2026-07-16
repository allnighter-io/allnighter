# Allnighter — Agent Workflow

Applies to Claude, Codex, Cursor, humans, and CI. **Router only** — durable
policy lives in routed docs. Add paths here, not long prose. Target <=150 lines.

## Expansion Rule

This file routes; it does not hold ops detail. New operational policy goes in the
routed doc (most often `docs/operations/Execution-Playbook.md`), then gets a link
here. Never treat chat notes, scratch files, generated output, code comments, or
experiments as more authoritative than the routed source docs.

## Mission

Allnighter turns the user's Mac into an overnight **AI-agent factory** and the
app/iPhone into one bench to run them from. It coordinates the coding agents
the user already pays for (Claude Code, Codex, Grok, Gemini CLI, Aider, Cursor)
plus local models — chat with one in your repo, fan out to many for options, all
on one screen. See `docs/phases/Unified_Run_Model.md` for the run model.

> You already pay for the team. Allnighter makes it show up to work.

It is **not** a model provider, IDE, chat aggregator, cloud coding service, or
terminal viewer. Dark-mode-only native macOS app; brand is "amber phosphor on
midnight." Agents must preserve: parallel work isolated per lane (the user never
hears "worktree"), option generation, pick-as-work-order, quota harvesting, and
preference compounding.

## Authoritative Sources

Root docs are the source of truth. Read the relevant one before changing that area.

- **Canonical product vocabulary (read first):** `docs/phases/Language_Cutover.md` —
  Chat / Delegate ("Send to team") / Execute; **Team** is the noun; crafts are
  **Code · Design · Copy** (+ **Signal** scout); machine layer is one `team.run`
  primitive (posture + `mutating`). Retired: `Fan out`, `Build`-as-craft,
  `Execute`-as-mode, "Move Card", `lane`=single-run. Hard cutover, no aliases.
- **Run model + execution safety (read before team/run changes):**
  `docs/phases/Unified_Run_Model.md` — a run = message + optional preset + worker,
  in the repo root. Answer teams are read-only (parallel); execution teams are one
  worker (mutating) under the per-root write lock. Historical source-gate proof:
  `docs/archive/phases/Execution_Team_Source_Gate.md`.
- **Built MVP foundation:** `docs/mvp/README.md` — historical team-run substrate
  (originally called Council: one prompt → parallel CLIs → plan), plus
  `docs/mvp/00_MVP_Architecture.md`.
- **Post-MVP phases:** `docs/phases/README.md` (active forward phase router).
- **Active iOS work:** `docs/phases/ios/README.md` (future remote Project Manager).
- **Visual design SSOT** (brand, voice, tokens, components, logo, icon):
  `docs/design-system/readme.md` + binding app rules in
  `docs/design-system/production.md`. Skill: `allnighter-design`.
- **GUI engineering governance** (how to build UI surfaces — *not* visual design):
  `docs/gui/GUI_Workflow.md`.
- **SwiftUI state rules** (Observation, no Combine-era view state):
  `docs/operations/SwiftUI_State_Rules.md`.
- **Founder input / feature planning:** `docs/workflows/SSOT_Founder_Input_Workflow.md`
  + `docs/workflows/SSOT_Feature_Workflow.md`.
- **Strategy & positioning:** `docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md`.
- **Stack & commands:** `docs/operations/TechStack.md`.
- **Sprint execution:** `docs/operations/Execution-Playbook.md`.
- **Repo map / conventions:** `docs/FOLDER_MAP.md` + `docs/operations/Contributing.md`.

## First Routing

| Task type | Read first |
| --- | --- |
| Product scope, MVP foundation, what shipped | `docs/mvp/README.md` + `docs/mvp/00_MVP_Architecture.md` |
| Post-MVP planning, utilization, cleanup, future phases | `docs/phases/README.md` |
| Run model: chat/run = agent in repo root, Default Team, presets, write lock | `docs/phases/Unified_Run_Model.md` |
| Composer `@` file references, Project file search, file chips | `docs/phases/Composer_File_References.md` |
| Model/skill/worker/team vocabulary | `docs/phases/Work_Order_Team_Model.md` |
| Execution/answer teams, mutating runs, source/write safety | `docs/phases/Unified_Run_Model.md` + `docs/phases/CLI_Implementation_Contract.md` |
| CLI product surface, `alln`, TeamRunJSON | `docs/phases/CLI_Product_Spine.md` + `docs/phases/CLI_Implementation_Contract.md` |
| Agent surface, `alln team hello`, `alln bootstrap` activation, help routing (MCP retired 2026-07-16) | `docs/phases/MCP_Retirement.md` — the CLI is the only agent surface now; `alln bootstrap` prints the paste-ready host context snippet (replaces `alln mcp install`); `docs/phases/MCP_Help_System.md` + `docs/phases/Agent_First_MCP_And_Messaging_Workflows.md` are historical |
| Agent front door: `install-cli`, `bootstrap`, first-contact counsel (`models`, `team hello`, `doctor`) | `docs/phases/Agent_Front_Door.md` |
| Copy lane, `/copy`, copy type packs, copy work orders | `docs/phases/copy/README.md` |
| iOS companion, remote control, Tailscale pairing | `docs/phases/ios/README.md` + `docs/operations/ios-testing-loop.md` |
| Shared Mac/iOS SwiftUI or `Packages/AllnighterUI` | `docs/gui/GUI_Workflow.md` §5 — default **no**; founder escalation required |
| SwiftUI state, `@Observable`, replacing old view models | `docs/operations/SwiftUI_State_Rules.md` + `docs/gui/GUI_Workflow.md` |
| **Visual** design, brand, styling, tokens, mocks, prototypes | `allnighter-design` skill → `docs/design-system/readme.md` + `docs/design-system/production.md` |
| **Building** a UI surface (SwiftUI window/view/component) | `docs/gui/GUI_Workflow.md`, then the routed GUI docs + surface brief |
| Shared models, worker drivers, fan-out, synthesis | `docs/mvp/01_Core_Package.md` → `02`/`04` as scoped |
| Forward Mac app shell, Dock app, background coordinator, resident mode | `docs/phases/Mac_Standalone_App_And_Background_Coordinator.md` |
| Historical MVP Mac app shell, run loop, what shipped | `docs/mvp/03_Mac_App_And_Run_Loop.md` |
| Judgment chain / Review Board (RB0–RB6) | `docs/mvp/RB0_Judgment_Workflow_Overview.md` + routed RB docs |
| New feature, rough product idea, founder note | `docs/workflows/SSOT_Founder_Input_Workflow.md` → `docs/workflows/SSOT_Feature_Workflow.md` |
| Team lab seat economics, roster ablation, named variants, necessity suite | `docs/phases/Team_Lab_Composition_And_Seat_Economics.md` |
| Sprint or phase execution (Task → Deslop → Code Audit → closeout) | `docs/operations/Execution-Playbook.md` + the target phase doc |
| **Implement one bounded slice (32K agents)** | `docs/phases/sprint/README.md` — one work order only |
| PM↔dev unattended loop (mechanized copy-paste relay) | `docs/phases/PM_Relay.md` (supersedes the old slice-queue pair team, deleted R-S09) |
| GLM advisory review / serial hardening pass | `docs/operations/GLM_Worker_Best_Practices.md` + `docs/phases/code_review/README.md` |
| OpenCode smoke probe blocked (handoff) | `docs/phases/OpenCode_Smoke_Probe_Blocker.md` |
| Sprint closeout / committing work | `docs/operations/Execution-Playbook.md` § Commits |
| Deslop pass (slice slop cleanup) | `docs/operations/Deslop.md` |
| Code Audit (structural verdict at closeout) | `docs/operations/Code_Audit.md` |
| Bug report / fix a bug / broken workflow | `docs/operations/Debugger.md` (+ `docs/operations/debugger/`) |
| Code cleanup, maintainability, file hygiene | `docs/operations/code-maintainer/` |
| Stack, Xcode, Swift package, commands | `docs/operations/TechStack.md` |
| iOS simulator dev / test loop (preview vs live) | `docs/operations/ios-testing-loop.md` |
| Marketing, positioning, pricing copy | `docs/marketing/README.md` |
| Strategy, control-loop thesis, A/B extension | `docs/strategy/` |

This table is first routing only. Narrower docs named by the target phase doc,
GUI brief, or design-system page still apply.

## Commits

The commit-queue/handoff watcher is **retired** (2026-06-18). Agents commit their
own work directly with git — there is no queue, no `.wmd/commit-queue.jsonl`, and
no `--wait` handoff. Codex has direct workspace git permissions.

At slice close, stage the explicit files you changed and commit with a clear
message; finished work must not be left uncommitted (or the save is explicitly
waived). Commit in small, regular increments rather than one large drop.

```text
git add <explicit-path> <explicit-path>
git commit -m "<scope>: <what changed>"
```

Never `git reset --hard` or rewrite shared history on `feat/design-chain`; never
sweep unrelated staged/dirty files into a commit (stage explicit paths). Full
rules: `docs/operations/Execution-Playbook.md` § Commits.

## Project Laws

- Founder/user input is intent, not final authority.
- Projects own repo/folder scope for new work; regular chat in a project is an
  agent running in the repo root (the Default Team) — `docs/phases/Unified_Run_Model.md`.
- SwiftUI may render truth; it must not invent durable product truth.
- Owned SwiftUI state uses Observation; no `ObservableObject`/`@Published` era
  state in app-facing code.
- Prompt prose may request work; it must not be the only owner of semantics.
- Generated output (parsers, design bundle) is derived. Change the source
  contract, then regenerate — never hand-edit generated artifacts.
- Every feature slice needs one owner-visible Works Test or an explicit waiver.
- Every non-trivial bug fix names the truth owner, lie-prone layer, and missing
  proof before editing.
- Maintenance preserves behavior unless the task is explicitly a bug fix.
- Do not mix broad cleanup into a feature or bug fix.
- Prefer deterministic checks over recurring agent judgment.
- A failed worker is shown failed, never faked. Hide the plumbing (legacy panel /
  council / master-plan words, worktree, subprocess).
- CLI, GUI, and iOS must share the same team-run contract; do not invent
  parallel JSON around `TeamRunJSON`.
- Mac and iOS do not share SwiftUI views or app-target GUI code; share
  Core/Engine + CLI only (`docs/gui/GUI_Workflow.md` §5).
- Judgment teams may mix sources; mutating/`execute` teams must resolve to one
  CLI/source before dispatch.
- Forward Mac app work targets a standalone Dock app plus explicit background
  coordinator. The menu bar is status/quick controls, not the product shell.
- Mac app is unsandboxed by design; still minimize privilege surface and document
  every permission request.
- iOS companion connects only to the user's own Mac over Tailscale/local network
  by default. No mandatory third-party coordination cloud.
- Agent bridge configs describe how to spawn CLI agents; they must not become
  hidden runtime truth for session state.

## High-Risk Stops

Ask before proceeding when the change could affect:

- privacy or session data leaving the user's machines;
- credentials, Keychain items, or API keys;
- Full Disk Access or other macOS permission posture;
- destructive session kill, worktree deletion, or git operations;
- App Store / notarization / distribution identity;
- billing, entitlement, or quota-spend behavior;
- production deploy or TestFlight release.

## Proof Wall (when code exists)

```text
swift test                    # shared package + unit tests
xcodebuild test -scheme ...   # app targets (see docs/operations/TechStack.md)
```

Until Xcode targets exist, name the missing proof in closeout. Do not claim
behavior is proven without a Works Test or explicit waiver.
