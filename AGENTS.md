# Allnighter — Agent Workflow

Applies to Claude, Codex, Cursor, humans, and CI. **Router only** — durable
policy lives in routed docs. Add paths here, not long prose. Target <=150 lines.

## Expansion Rule

This file routes; it does not hold ops detail. New operational policy goes in the
routed doc (most often `docs/operations/Execution-Playbook.md`), then gets a link
here. Never treat chat notes, scratch files, generated output, code comments, or
experiments as more authoritative than the routed source docs.

## Mission

Allnighter is the **all-day multi-CLI bench** for the coding agents the user
already pays for (Claude Code, Codex, Grok, Gemini CLI, Aider, Cursor, Composer,
local models). Hero use is attended and high-frequency on the Mac (CLI + app as
one floor). Two co-equal loops:

1. **Named Teams** (parallel judgment) — Spec Review, Bug Hunt, Growth,
   Research, and other Teams. Not Spec Review–only.
2. **Pilot / relay** (multi-round floor) — a strong lead (e.g. Opus in Claude)
   steers and reviews; execution seats (e.g. Grok, Composer) do the mutating
   work. Exactly one mutating worker per root.

Detach / while-away is a supported mode, not the product story. The name
Allnighter is brand and domain only. Run model code SSOT: `RunService.swift`
(the one run owner).

> You already pay for the team. Allnighter makes it show up to work.

It is **not** a model provider, IDE, chat aggregator, cloud coding service, or
terminal viewer. Dark-mode-only native macOS app; brand is "amber phosphor on
midnight." Agents must preserve: parallel research from the selected Team in the
canonical repository, exactly one mutating worker per root, option generation,
quota harvesting, and preference compounding.

**Do not pitch overnight / "while you sleep" / wake-up-to-diffs as the default
value prop.** Dogfood reality is all-day Teams + pilot/relay (strong lead →
execution workers) — not sleep automation.

## Authoritative Sources

Root docs are the source of truth. Read the relevant one before changing that area.

- **Canonical product vocabulary (read first):** `docs/workflows/Product_Vocabulary.md` —
 Chat / Delegate ("Send to team") / Execute; **Team** is the noun; crafts are
 **Code · Design · Copy** (+ **Signal** scout); machine layer is one `team.run`
 primitive (posture + `mutating`). Retired: `Fan out`, `Build`-as-craft,
 `Execute`-as-mode, "Move Card", `lane`=single-run. Hard cutover, no aliases.
 Run semantics remain code SSOT (`RunService.swift`).
- **Run model + execution safety (read before team/run changes):** a run =
  message + optional preset + worker, in the repo root. Research Teams are
  parallel and observational; execution Teams are one worker (mutating) under
  the per-root write lock. No mirror, clone, or blanket read-only layer. Code
  SSOT: `RunService.swift` (the one run owner), `TeamPreset`/`TeamCatalog`,
  `RunWriteLockRegistry`. Enforced by `config/architecture-policy.json` +
  `scripts/check_architecture_policy.sh`.
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
| Core execution broken, Team research or execution does not work in the real repo | One run owner: `RunService.run`. Mirrors, clones, mechanical read-only Teams, and resident execution do not exist — `config/architecture-policy.json` + `scripts/check_architecture_policy.sh` fail the build if they return. |
| Product scope, MVP foundation, what shipped | `docs/mvp/README.md` + `docs/mvp/00_MVP_Architecture.md` |
| Post-MVP planning, open build packets, what to archive next | `docs/phases/README.md` (ephemeral packets only — never SSOT; closeout = promote + archive) |
| Run model: chat/run = agent in repo root, Default Team, presets, write lock | Code SSOT: `RunService.swift`, `TeamPreset`/`TeamCatalog`, `RunWriteLockRegistry` |
| Run started — what is happening, is anything needed, where is the result | `alln show <id> --json` snapshot / `alln show <id> --stream` observe + deliver. Code SSOT: `RunService.swift`, `TeamRunJSONMapper` (`observation`), `RemoteRunEventJournal` (derived history) |
| Run stuck, status/journal mismatch, opaque contention, orphan worker, kill/retry failure, missing progress stream | Code SSOT: `KillSettlement.swift`, `RunClockEnforcer.swift`, `IdempotencyStore.swift`, `ProcessOwnership.swift` |
| Codex/host sandbox blocks child CLIs, source processes missing from `alln ps` | The sandbox blocks the Keychain, not the repo — vendor CLIs then believe they are logged out. `alln run` hands off to the open Mac app; a per-session `codex --sandbox danger-full-access` also works. Never a global `sandbox_mode` change. Code SSOT: `SandboxHandoffSpool.swift`, `SandboxHandoffRunner.swift`, `HostSandboxAdvice.swift` |
| Plan-time quota routing, capacity in menu/bootstrap, loop session-cap wake | Open packet: `docs/phases/Quota_Aware_Bench_Continuity.md` — code SSOT `CapacityDisplayAcquisition`, `MenuCatalog`, `LoopCoordinator.dispatchDevTurn`, `VendorBackoffReconciler`, `VendorSubstitutionPolicy` |
| Vendor usage limit / parked run / wake-resume / authorized substitute | Code SSOT: `VendorBackoffReconciler.swift`, `VendorSubstitutionPolicy.swift` |
| Composer `@` file references, Project file search, file chips | Open packet: `docs/phases/Composer_File_References.md` (not SSOT) |
| One-off team seating / custom `*_` picker sprawl / “staff these models once” | archived `docs/archive/phases/Ephemeral_Teams.md` — runtime `--seat` on `alln run` (Option C); code SSOT `TeamExplicitSeats`, `RunInvocationResolver`; do not `teams duplicate` for one-offs |
| Relay/pilot round lands or escalates with nobody notified (Mac app closed) | archived `docs/archive/phases/Unattended_Round_Notification.md` — Code Complete 2026-07-27; code SSOT `NotificationScheduler.swift`, `ServeAutoLaunch.swift`, `NotificationCandidateDetection.swift` |
| `pair pilot status` fresh silenceAge while `alln ps` says no stream for Ns; hung child under worker (e.g. wrangler tail); pgid heartbeat lie | archived `docs/archive/phases/Pilot_Status_Liveness_Lie_Hotfix.md` + `Core_Loop_Improvements.md` — Complete 2026-07-28; code SSOT `StreamLiveness`, `PilotCLI.resolveLastProgressAt`, `ProcessOwnershipSurface` |
| `alln ps` museum rows, manual reconcile before session, ghost `running` relays | archived `docs/archive/phases/Core_Loop_Improvements.md` — Complete 2026-07-28; code SSOT `ProcessOwnershipSurface.list` (reconcile-on-read, `--all` history), `StreamLiveness` |
| `pair relay`/`relay-resume`/`relay adopt`/`alln run` die when the caller dies; relay dispatch race (no in-flight guard) | Archived `docs/archive/phases/Round_Survives_The_Caller.md` + Hot Fixes — Code Complete 2026-07-28; code SSOT `DetachedHandoff.swift`, `DetachedDispatch.swift`, `LoopCoordinator.swift` (`claimStart`/`persistClaim`), `RunCLI.swift` |
| Model/skill/agent/team vocabulary | `docs/workflows/Product_Vocabulary.md` + code catalogs; historical cutover + optional hygiene backlog: `docs/archive/phases/Worker_To_Agent_Migration.md` |
| Model catalog sprawl, effort variants, adding/removing default seats | archived `docs/archive/phases/Model_Catalog_Simplification.md` — Complete 2026-07-28; code SSOT AgentOS `CatalogLoader` + `catalog.json`, Allnighter `CatalogOverlayLoader` + `catalog_overlay.json`, `ModelCatalog.bundledRegistry()` |
| GUI visual layout proof / layout-watcher | `docs/gui/Visual_Proof_Gate.md` + `docs/gui/GUI_Workflow.md` |
| Design team (build → screenshot, not Midjourney) | `docs/operations/Design_Lane.md` + code `DesignBoardCapture` |
| Spec Review hero loop | `docs/operations/Spec_Review.md` + `BuiltInTeams` / `SkillCatalog.leadCallEnvelope` |
| Green suite over a real defect; a proof that could never fail; tolerance fitted until the test passed; "we measured the wrong thing" | `docs/operations/Spec_Review.md` §3 Measurement + §4 instrumentation rule — code SSOT `measurement_auditor` (Spec Review Max, Release Proof) |
| Adding/removing a seat at a Min or Max tier | `docs/operations/Spec_Review.md` §Depth splits charters — a dropped seat's questions must be absorbed by a named pass on a seat that remains, never silently lost |
| Execution/answer teams, mutating runs, source/write safety | Code SSOT: `RunService.swift`, `RunWriteLockRegistry` |
| CLI product surface, `alln`, TeamRunJSON | Code SSOT: `ContractRegistry` / CLI; naming packet: `CLI_Product_Spine.md` (not SSOT) |
| Team run artifact / `alln artifact` | Code SSOT: `ArtifactProjector.swift`, `ArtifactWriter.swift`, `ArtifactCLI.swift`; closed record: archived `Team_Run_Receipt.md` |
| Agent surface, `alln bootstrap` activation, help/menu routing (MCP retired 2026-07-16) | Live `alln menu --json` is the selection front door; `alln bootstrap` prints the paste-ready host context; CLI is the only agent surface. Code SSOT: `MenuCatalog.swift`, `Bootstrap.swift`, `HelpTopicRegistry.swift` |
| Agent front door: `install-cli`, `bootstrap`, live menu selection | Front door V1 complete; there is no intent router — the caller chooses from the live menu. Code SSOT: `InstallCLI.swift`, `Bootstrap.swift`, `TeachingSnippet.swift`, `MenuCatalog.swift` |
| Cold start — no `alln` on PATH yet (Hermes/OpenClaw one-paste curl install) | Open packet: `docs/phases/One_Paste_Cold_Start.md` — curl faucet + bootstrap host paste; MCP stays dead; app is human faucet; npm deferred |
| Stale MCP / invented flags in help, empty `help search`, dead verbs in living docs, `version` freshness | Code SSOT: `RetiredVocabulary.swift`, `HelpTopicRegistry.swift`, `AllnighterVersionIdentity` + `docs/workflows/SSOT_Founder_Input_Workflow.md` §Agent-facing help |
| Copy lane, `/copy`, copy type packs, copy work orders | `docs/phases/copy/README.md` |
| iOS companion, remote control, Tailscale pairing | `docs/phases/ios/README.md` + `docs/operations/ios-testing-loop.md` |
| Shared Mac/iOS SwiftUI or `Packages/AllnighterUI` | `docs/gui/GUI_Workflow.md` §5 — default **no**; founder escalation required |
| SwiftUI state, `@Observable`, replacing old view models | `docs/operations/SwiftUI_State_Rules.md` + `docs/gui/GUI_Workflow.md` |
| **Visual** design, brand, styling, tokens, mocks, prototypes | `allnighter-design` skill → `docs/design-system/readme.md` + `docs/design-system/production.md` |
| **Building** a UI surface (SwiftUI window/view/component) | `docs/gui/GUI_Workflow.md`, then the routed GUI docs + surface brief |
| Shared models, worker drivers, fan-out, synthesis | `docs/mvp/01_Core_Package.md` → `02`/`04` as scoped |
| Forward Mac app shell, Dock app, background scheduler | `alln serve` is a background SCHEDULER only (Pending wake, Boost seed, vendor-backoff continuation, cloud relay). It owns no run semantics and `alln run` never needs it; adding an operation to it is a new feature packet. |
| Historical MVP Mac app shell, run loop, what shipped | `docs/mvp/03_Mac_App_And_Run_Loop.md` |
| Judgment chain / Review Board (RB0–RB6) | `docs/mvp/RB0_Judgment_Workflow_Overview.md` + routed RB docs |
| New feature, rough product idea, founder note | `docs/workflows/SSOT_Founder_Input_Workflow.md` → `docs/workflows/SSOT_Feature_Workflow.md` |
| Team lab seat economics, roster ablation, named variants, necessity suite | Team Lab is SHUT DOWN (founder, 2026-07-24) — do not resume; built-in Teams ship as-is via `TeamCatalog`/`BuiltInTeams.swift` |
| Sprint or phase execution (Task → Deslop → Code Audit → closeout) | `docs/operations/Execution-Playbook.md` + the target phase doc |
| **Implement one bounded slice (32K agents)** | `docs/phases/sprint/README.md` — one work order only |
| PM↔dev unattended loop (mechanized copy-paste relay) | archived `docs/archive/phases/PM_Relay.md` + `Pilot_Relay.md` (code SSOT: `LoopCoordinator`, `PilotCLI`) |
| Pilot/Relay long turn; harness reaped `pilot watch`; detached handoff binary/cwd; status vs watch | archived `docs/archive/phases/Pilot_Long_Turn_Survival.md` — code SSOT `PilotCLI.swift`, `LoopCoordinator.swift` |
| GLM advisory review / serial hardening pass | `docs/operations/GLM_Worker_Best_Practices.md` + `docs/archive/phases/code_review/README.md` |
| OpenCode smoke probe blocked (handoff) | archived `docs/archive/phases/OpenCode_Smoke_Probe_Blocker.md` (RESOLVED) |
| Sprint closeout / committing work | `docs/operations/Execution-Playbook.md` § Commits |
| Deslop pass (slice slop cleanup) | `docs/operations/Deslop.md` |
| Code Audit (structural verdict at closeout) | `docs/operations/Code_Audit.md` |
| Bug report / fix a bug / broken workflow | `docs/operations/Debugger.md` (+ `docs/operations/debugger/`) |
| Code cleanup, maintainability, file hygiene | `docs/operations/code-maintainer/` |
| Stack, Xcode, Swift package, commands | `docs/operations/TechStack.md` |
| Test / CI / `check.sh` / agent proof commands / test pile-ups | `docs/operations/Execution-Playbook.md` § Green Wall (PATH shim + token makes the wrapper the only working path on every agent host; history: `docs/archive/phases/Test_Infrastructure_Upgrade.md`) |
| iOS simulator dev / test loop (preview vs live) | `docs/operations/ios-testing-loop.md` |
| Marketing, positioning, pricing copy | `docs/marketing/README.md` |
| Changing a price, tier, trial length, or the free core | `docs/phases/Pricing_Change_Process.md` (founder ruling required; offer SSOT is `docs/marketing/Pricing_Recommendation.md`) |
| EULA, terms, acceptance gate, credential/compliance posture | `docs/legal/README.md` |
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

Test infrastructure rules (TIU — standing in Execution Playbook § Green Wall;
history: `docs/archive/phases/Test_Infrastructure_Upgrade.md`)

1. Raw `swift test` / `xcodebuild test` do not work outside the wrapper (PATH shim).
2. One test run per clone — second attempt fails fast with a lock message.
3. Iteration proof = filtered only: `scripts/swift-test.sh --filter <TouchedTests>`
4. `bash scripts/check.sh` = closeout only — never mid-slice, never in a fix→test loop.
5. Do not run `swift test --list-tests` as routine (~8+ min cold).
6. Lock failure or timeout is a stop signal — do not retry, poll, or wait-loop.
7. Wedged Mac: `scripts/kill-stale-tests.sh`, then continue — do not stack full suites.
8. Wall is admission-controlled (45m cooldown; CI exempt); genuine closeout: `ALLNIGHTER_WALL_REASON="<why>" bash scripts/check.sh`.

```text
scripts/install-test-guard.sh   # optional: direnv for interactive shells (agents auto-activate via test scripts)
scripts/swift-test.sh --filter LoopDispatch   # iteration proof
bash scripts/check.sh           # closeout / founder-requested full wall (prints wall-clock at end)
scripts/kill-stale-tests.sh     # emergency stale runner cleanup
```

Test PATH shims auto-activate when any agent runs `check-fast.sh`, `swift-test.sh`,
or `check.sh` (`scripts/ensure-test-guard-path.sh` prepends `scripts/bin` — no
human `direnv allow` step required).

Until Xcode targets exist, name the missing proof in closeout. Do not claim
behavior is proven without a Works Test or explicit waiver.
