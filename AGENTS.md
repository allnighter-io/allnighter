# Allnighter — Agent Workflow

Applies to Claude, Codex, Cursor, humans, and CI. **Router only** — durable
policy lives in routed docs. Add paths here, not long prose. Target <=150 lines.

## Expansion Rule

This file routes; it does not hold ops detail. New operational policy goes in the
routed doc (most often `docs/operations/Execution-Playbook.md`), then gets a link
here. Never treat chat notes, scratch files, generated output, code comments, or
experiments as more authoritative than the routed source docs.

## Mission

The **all-day multi-CLI bench** for coding agents the user already pays for
(Claude Code, Codex, Grok, Cursor, Composer, OpenCode, local models). Hero use is
attended and high-frequency on the Mac. Two co-equal loops:

1. **Named Teams** — parallel judgment (Spec Review, Bug Hunt, Growth, Research).
   Not Spec Review–only.
2. **Loop** (`alln loop`) — a strong lead steers and reviews; execution seats do
   the mutating work. Exactly one mutating worker per root.

> You already pay for the team. Allnighter makes it show up to work.

**Not** a model provider, IDE, chat aggregator, cloud coding service, or terminal
viewer. Dark-mode-only native macOS app; brand is "amber phosphor on midnight."
Preserve: parallel research from the selected Team in the canonical repository,
one mutating worker per root, option generation, quota harvesting, preference
compounding.

**Do not pitch overnight / "while you sleep" / wake-up-to-diffs as the value
prop.** Dogfood reality is all-day Teams + Loop, not sleep automation. The name
is brand and domain only. Run model code SSOT: `RunService.swift`.

## Authoritative Sources

Root docs are the source of truth. Read the relevant one before changing that area.

- **Canonical product vocabulary (read first):** `docs/workflows/Product_Vocabulary.md`
  — hard cutover, no aliases. Run semantics stay code SSOT (`RunService.swift`).
- **Run model + execution safety (read before team/run changes):** a run =
  message + optional preset + worker, in the repo root. Research Teams are
  parallel and observational; execution Teams are one mutating worker under the
  per-root write lock. No mirror, clone, or blanket read-only layer. Code SSOT
  `RunService.swift`, `TeamPreset`/`TeamCatalog`, `RunWriteLockRegistry`;
  enforced by `scripts/check_architecture_policy.sh`.
- **Built MVP foundation:** `docs/mvp/README.md` + `docs/mvp/00_MVP_Architecture.md`.
- **Post-MVP phases:** `docs/phases/README.md` (active forward phase router).
- **Active iOS work:** `docs/phases/ios/README.md` (future remote Project Manager).
- **Visual design SSOT** (brand, voice, tokens, components, logo, icon):
  `docs/design-system/readme.md` + binding rules in `production.md`.
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
| Core execution broken, Team research or execution does not work in the real repo | One run owner: `RunService.run`. Mirrors, clones, mechanical read-only Teams, and resident execution do not exist — `scripts/check_architecture_policy.sh` fails the build if they return. |
| Product scope, MVP foundation, what shipped | `docs/mvp/README.md` + `docs/mvp/00_MVP_Architecture.md` |
| Post-MVP planning, open build packets, what to archive next | `docs/phases/README.md` (ephemeral packets only — never SSOT; closeout = promote + archive) |
| Run model: chat/run = agent in repo root, Default Team, presets, write lock | Code SSOT: `RunService.swift`, `TeamPreset`/`TeamCatalog`, `RunWriteLockRegistry` |
| Run started — what is happening, is anything needed, where is the result | `alln show <id> --json` snapshot / `alln show <id> --stream` observe + deliver. Code SSOT: `RunService.swift`, `TeamRunJSONMapper` (`observation`), `RemoteRunEventJournal` (derived history) |
| Multi-seat / `--seat` on a spawn-gated CLI (cursor_agent, opencode, agy); same-CLI crew on large teams | **Closed 2026-08-08** — serialize, never refuse. Code SSOT: AgentOS `GatedWorkerRunner.invoke`; Allnighter `RunInvocationResolver.spawnSerializationWarnings`; archive `Crew_Understaffed_Signal.md` |
| Run stuck, status/journal mismatch, opaque contention, orphan worker, kill/retry failure, missing progress stream | Code SSOT: `KillSettlement.swift`, `RunClockEnforcer.swift`, `IdempotencyStore.swift`, `ProcessOwnership.swift` |
| Capacity strip, `alln capacity`, warm pool, menu-bar resident | [`Capacity_Warm_Bench.md`](Capacity_Warm_Bench.md) — S02 `capacity.sock` shipped (code SSOT `CapacitySocket.swift`); host lock superseded by `Probe_Freshness.md` §0.2; menu bar / warm PTY not v1 |
| Plan-time quota routing, capacity in menu/bootstrap, loop session-cap wake | Open packet: `docs/phases/Quota_Aware_Bench_Continuity.md` — runtime park/sub only; menu capacity suspended per CWB; code SSOT `VendorBackoffReconciler`, `VendorSubstitutionPolicy`, `LoopCoordinator.dispatchDevTurn` |
| OpenCode Go plan capacity (browser `/go` scrape, encrypted credentials) | Open packet: `docs/phases/OpenCode_Go_Capacity.md` — not PTY; v1 strip only; code SSOT TBD `OpenCodeGoCapacityProbe`, `OpenCodeGoCredentialStore` |
| OpenCode `:4096` leftover serve between runs | **Closed 2026-08-08** — attach healthy listener; never SIGTERM to clear port. Code SSOT: AgentOS `OpenCodeServeCoordinator.ensureRunning`; help `opencode_headless_completion`; archive `OpenCode_Serve_Attach.md` |
| OpenCode local / Ollama seats; frontier→local labor; local-vs-cloud benchmark proposals | Open packet **1 of 3**: `docs/phases/OpenCode_Local_Ollama_Seats.md` — frontier plans, local executes; code unauthorized until ready |
| Context Firewall / egress ledger / root-less dispatch; privacy buyers | Open packet **2 of 3**: `docs/phases/Context_Firewall.md` — auditable egress, never sanitisation; root-less dispatch undesigned |
| Second Mac / LAN bench / remote `OLLAMA_HOST` | Open packet **3 of 3**: `docs/phases/Second_Mac_Bench.md` — fence only; refuse cross-host mutators |
| OpenCode long runs / `stream_drop` / `task` hang | Open: `docs/phases/OpenCode_Long_Run_Continuity.md` + `OpenCode_Completion_Truth_Followup.md`; code SSOT AgentOS `OpenCode*` + `OpenCodeOutcomeAuthority` |
| OpenCode long mutating under-ship / commit dogfood | Open: `docs/phases/OpenCode_Mutating_Long_Run_Hardening.md` |
| OpenCode empty `incomplete_no_final_message` / stall mid-`task` / seat timeout 2× | **Closed 2026-08-09** — OCH AgentOS `65da768`. Archive `OpenCode_Turn_Capture_Hardening.md`; help `opencode_headless_completion` |
| Smart / auto model routing, economy vs balanced seats, "always prefer vendor X" | Brainstorm only: `docs/phases/Scarcity_Aware_Routing.md` — read §3 rejected list first |
| Vendor usage limit / parked run / wake-resume / authorized substitute | Code SSOT: `VendorBackoffReconciler.swift`, `VendorSubstitutionPolicy.swift` |
| Wrong/invented capacity verdict; cross-vendor limit detection; failed-run work missing from `alln show` | Open: `docs/phases/Vendor_Signal_Isolation.md` — parser scoped by `sourceId`. Code SSOT: AgentOS `CapacityClassifier`, `DriverManifest` |
| Stale teaching / invented flags / empty `help search` / `version` freshness | Open: `docs/phases/Agent_Teaching_Surface.md`. Code SSOT: `TeachingSnippet`, `HelpTopicRegistry`, `RetiredVocabulary`, `AllnighterVersionIdentity` |
| Composer `@` file references, Project file search, file chips | Open packet: `docs/phases/Composer_File_References.md` (not SSOT) |
| GUI visual layout proof / layout-watcher | `docs/gui/Visual_Proof_Gate.md` + `docs/gui/GUI_Workflow.md` |
| Design team (build → screenshot, not Midjourney) | `docs/operations/Design_Lane.md` + code `DesignBoardCapture` |
| Spec Review hero loop | `docs/operations/Spec_Review.md` + `BuiltInTeams` / `SkillCatalog.leadCallEnvelope` |
| AI Readiness (is this repo workable by agents; first recommended Code Team; scoring is banned — see §3) | Open packet: `docs/phases/AI_Readiness.md` — not built; archive + promote on ship |
| Green suite over a real defect; a proof that could never fail; tolerance fitted until the test passed; "we measured the wrong thing" | `docs/operations/Spec_Review.md` §3 Measurement + §4 instrumentation rule — code SSOT `measurement_auditor` (Spec Review Max, Release Proof) |
| Adding/removing a seat at a Min or Max tier | `docs/operations/Spec_Review.md` §Depth splits charters — a dropped seat's questions must be absorbed by a named pass on a seat that remains, never silently lost |
| Execution/answer teams, mutating runs, source/write safety | Code SSOT: `RunService.swift`, `RunWriteLockRegistry` |
| CLI product surface, `alln`, TeamRunJSON | Code SSOT: `ContractRegistry` / CLI; naming packet: `CLI_Product_Spine.md` (not SSOT) |
| Team run artifact / `alln artifact` | Code SSOT: `ArtifactProjector.swift`, `ArtifactWriter.swift`, `ArtifactCLI.swift`; closed record: archived `Team_Run_Receipt.md` |
| Agent surface / front door: `install-cli`, `bootstrap`, live menu selection, help routing (MCP retired 2026-07-16) | Live `alln menu --json` is the selection front door and the CLI is the only agent surface; `alln bootstrap [--host]` prints the paste-ready host context. There is no intent router — the caller chooses from the live menu. Code SSOT: `MenuCatalog.swift`, `Bootstrap.swift`, `InstallCLI.swift`, `TeachingSnippet.swift`, `HelpTopicRegistry.swift` |
| Cold start — no `alln` on PATH yet (Hermes/OpenClaw one-paste curl install) | Open packet: `docs/phases/One_Paste_Cold_Start.md` — curl faucet + bootstrap host paste; MCP stays dead; app is human faucet; npm deferred |
| Copy lane, `/copy`, copy type packs, copy work orders | `docs/phases/copy/README.md` |
| iOS companion, remote control, Tailscale pairing | `docs/phases/ios/README.md` + `docs/operations/ios-testing-loop.md` |
| Shared Mac/iOS SwiftUI or `Packages/AllnighterUI` | `docs/gui/GUI_Workflow.md` §5 — default **no**; founder escalation required |
| SwiftUI state, `@Observable`, replacing old view models | `docs/operations/SwiftUI_State_Rules.md` + `docs/gui/GUI_Workflow.md` |
| **Visual** design, brand, styling, tokens, mocks, prototypes | `docs/design-system/readme.md` + `docs/design-system/production.md` |
| **Building** a UI surface (SwiftUI window/view/component) | `docs/gui/GUI_Workflow.md`, then the routed GUI docs + surface brief |
| Shared models, worker drivers, fan-out, synthesis | `docs/mvp/01_Core_Package.md` → `02`/`04` as scoped |
| Forward Mac app shell, Dock app, background scheduler | `alln serve` is a background SCHEDULER only (Pending wake, Boost seed, vendor-backoff continuation, cloud relay, probe/capacity refresh). It owns no run semantics; adding an operation to it is a new feature packet. |
| Historical MVP Mac app shell, run loop, what shipped | `docs/mvp/03_Mac_App_And_Run_Loop.md` |
| Judgment chain / Review Board (RB0–RB6) | `docs/mvp/RB0_Judgment_Workflow_Overview.md` + routed RB docs |
| New feature, rough product idea, founder note | `docs/workflows/SSOT_Founder_Input_Workflow.md` → `docs/workflows/SSOT_Feature_Workflow.md` |
| Sprint or phase execution (Task → Deslop → Code Audit → closeout) | `docs/operations/Execution-Playbook.md` + the target phase doc |
| **Implement one bounded slice (32K agents)** | `docs/phases/sprint/README.md` — one work order only |
| GLM advisory review / serial hardening pass | `docs/operations/GLM_Worker_Best_Practices.md` + `docs/archive/phases/code_review/README.md` |
| Sprint closeout / committing work | `docs/operations/Execution-Playbook.md` § Commits |
| Deslop pass (slice slop cleanup) | `docs/operations/Deslop.md` |
| Code Audit (structural verdict at closeout) | `docs/operations/Code_Audit.md` |
| Bug report / fix a bug / broken workflow | `docs/operations/Debugger.md` (+ `docs/operations/debugger/`) |
| Code cleanup, maintainability, file hygiene | `docs/operations/code-maintainer/` |
| Stack, Xcode, Swift package, commands | `docs/operations/TechStack.md` |
| Test / CI / `check.sh` / agent proof commands / test pile-ups | `docs/operations/Execution-Playbook.md` § Green Wall (PATH shim + token make the wrapper the only working path on every agent host) |
| iOS simulator dev / test loop (preview vs live) | `docs/operations/ios-testing-loop.md` |
| Marketing, positioning, pricing copy | `docs/marketing/README.md` |
| Changing a price, tier, trial length, or the free core | `docs/phases/Pricing_Change_Process.md` (founder ruling required; offer SSOT is `docs/marketing/Pricing_Recommendation.md`) |
| EULA, terms, acceptance gate, credential/compliance posture | `docs/legal/README.md` |
| Strategy, control-loop thesis, A/B extension | `docs/strategy/` |

| Anything already shipped and archived (closed hot fixes, completed migrations, retired machinery) | `docs/archive/phases/README.md` — the archive index. Closed packets are NOT routed from here; their durable truth is the code SSOT they name. |

This table is first routing only. Narrower docs named by the target phase doc,
GUI brief, or design-system page still apply.

## Commits

Agents commit their own work directly with git — no queue, no watcher, no
`--wait` handoff. Stage **explicit paths**; never sweep unrelated dirty files
into a commit; never `git reset --hard` or rewrite shared history on
`feat/design-chain`. Finished work is not left uncommitted unless the waiver is
explicit.

Full rules: `docs/operations/Execution-Playbook.md` § Commits.

## Project Laws

- Founder/user input is intent, not final authority.
- Projects own repo/folder scope for new work; regular chat in a project is an
  agent running in the repo root (the Default Team) — code SSOT `RunService.swift`.
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
- A derived signal is attributed to the source that produced it. One vendor's
  parser, matcher, or heuristic never answers for another vendor's output —
  scope it by source id, not by whichever pattern happens to match first.
- Absence of a declared signal yields no observation, never an inferred one. A
  false positive here is silent and expensive; a missed signal fails loudly and
  is cheap. Fail closed.
- A locally computed value is never presented as a vendor-stated fact. Local
  boundaries and vendor-sourced truth may both exist, but the storage, the
  confidence, and the user-visible wording must keep them distinct.
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
- Readiness/health/derived-state instruments INFORM; they never BLOCK an
  explicit request — the owner's request takes precedence and fails loudly if it
  fails. Parked driver, disabled model, unknown model id, and the per-root write
  lock still refuse (user intent / real invariants); sensor readings alone never
  veto.
- A command that returns without queued work must leave none behind: if `alln run`
  reports failure, no later process may execute that request. Prove a host will
  claim before queuing, and refuse loudly — one typed terminal answer — when none
  will.

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

Raw `swift test` / `xcodebuild test` are blocked by a PATH shim; the wrappers are
the only working path, and they activate the shim themselves.

```text
scripts/swift-test.sh --filter <TouchedTests>   # iteration proof
bash scripts/check.sh                           # closeout ONLY, never mid-slice
scripts/kill-stale-tests.sh                     # emergency stale-runner cleanup
```

A lock failure or timeout is a stop signal — do not retry, poll, or wait-loop.
Binding rules (one run per clone, admission control, `ALLNIGHTER_WALL_REASON`):
`docs/operations/Execution-Playbook.md` § Green Wall.

Until Xcode targets exist, name the missing proof in closeout. Do not claim
behavior is proven without a Works Test or explicit waiver.
