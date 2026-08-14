# Allnighter — Agent Workflow

Applies to Claude, Codex, Cursor, humans, and CI. **Router only** — durable
policy lives in routed docs. Add paths here, not long prose. Target <=150 lines.

New operational policy goes in the routed doc (most often
`docs/operations/Execution-Playbook.md` or `docs/operations/Project_Laws.md`),
then a link here. Chat notes, scratch files, generated output, code comments,
and experiments never outrank routed source docs.

## Mission

The **all-day multi-CLI bench** for coding agents the user already pays for
(Claude Code, Codex, Grok, Cursor, Composer, OpenCode, local models). Hero use
is attended and high-frequency on the Mac. Two co-equal loops:

1. **Named Teams** — parallel judgment (Spec Review, Bug Hunt, Growth, Research).
   Not Spec Review–only.
2. **Loop** (`alln loop`) — a strong lead steers and reviews; execution seats do
   the mutating work. Exactly one mutating worker per root.

> You already pay for the team. Allnighter makes it show up to work.

**Not** a model provider, IDE, chat aggregator, cloud coding service, or
terminal viewer. Dark-mode-only native macOS app; brand is "amber phosphor on
midnight." Preserve: parallel research from the selected Team in the canonical
repository, one mutating worker per root, option generation, quota harvesting,
preference compounding.

**Do not pitch overnight / "while you sleep" / wake-up-to-diffs as the value
prop.** Dogfood is all-day Teams + Loop. The name is brand and domain only.
Run model code SSOT: `RunService.swift`.

## Authoritative Sources

Read the relevant doc before changing that area.

- **Vocabulary (read first):** `docs/workflows/Product_Vocabulary.md` — hard
  cutover, no aliases. Run semantics stay code SSOT (`RunService.swift`).
- **Project laws (full text):** `docs/operations/Project_Laws.md`.
- **Run model + write lock:** `RunService.swift`, `TeamPreset`/`TeamCatalog`,
  `RunWriteLockRegistry`; `scripts/check_architecture_policy.sh`.
- **MVP foundation:** `docs/mvp/README.md` + `docs/mvp/00_MVP_Architecture.md`.
- **Open packets (never SSOT):** `docs/phases/README.md`.
- **Closed packets:** `docs/archive/phases/README.md`.
- **Visual design:** `docs/design-system/readme.md` + `docs/design-system/production.md`.
- **GUI engineering / SwiftUI state:** `docs/gui/GUI_Workflow.md`,
  `docs/operations/SwiftUI_State_Rules.md`.
- **Founder input / features:** `docs/workflows/SSOT_Founder_Input_Workflow.md`
  + `docs/workflows/SSOT_Feature_Workflow.md`.
- **Strategy / stack / sprint / repo map:**
  `docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md`,
  `docs/operations/TechStack.md`, `docs/operations/Execution-Playbook.md`,
  `docs/operations/Public_Release.md`, `docs/FOLDER_MAP.md`, `docs/operations/Contributing.md`.

## First Routing

| Task type | Read first |
| --- | --- |
| Core execution, run model, Default Team, write lock, mutating vs research | One run owner: `RunService.run`. Research Teams are parallel and observational; execution is one mutating worker under the per-root write lock. No mirror, clone, or blanket read-only layer — `scripts/check_architecture_policy.sh` fails the build if they return. Code: `TeamPreset`/`TeamCatalog`, `RunWriteLockRegistry`. |
| Run started / stuck / kill / retry / missing stream | `alln show <id> --json` / `--stream`. Code: `RunService`, `TeamRunJSONMapper`, `RemoteRunEventJournal`, `KillSettlement`, `RunClockEnforcer`, `IdempotencyStore`, `ProcessOwnership`. |
| Pure model name / family latest / generation pin | Vocabulary `docs/workflows/Product_Vocabulary.md` §pure name; AgentOS `FamilyLatest` + `catalog.json`; run journal `ModelPinFact`. Versioned ids stay exact pins. |
| Capacity (`alln capacity`), automated seat selection, invented verdict, vendor park/substitute, probe freshness | **Automated seat selection KILLED 2026-08-12.** `alln capacity` is daily-use — the founder reads the strip and routes by hand. Never degrade acquisition; "no code consumer" ≠ "no consumer". Full law: `docs/operations/Project_Laws.md` §§Capacity, Vendor signals, Bench tally. Vocab: `docs/workflows/Product_Vocabulary.md` §§Capacity, Quota-aware bench, Probe freshness. Code: `CapacityClassifier` (scoped by `sourceId`), `CapacityPaintGate`, `VendorBackoff*`, `ProbeFreshnessGate`, `ProbeRecordMerge`. History: `docs/archive/phases/README.md`. |
| OpenCode Go plan capacity | `docs/phases/OpenCode_Go_Capacity.md` — CLI beta shipped, metering live; code `OpenCodeGoCapacity*`. |
| OpenCode local / Ollama; Context Firewall; Second Mac | Local Ollama law: `docs/operations/Project_Laws.md` §Local Ollama seats; vocab `docs/workflows/Product_Vocabulary.md` §Local Ollama readiness; code `ModelCatalog` / `ModelDiscoveryProvider`. History: `docs/archive/phases/OpenCode_Local_Ollama_Seats.md`. Packets 2–3 still code unauthorized: `docs/phases/Context_Firewall.md`, `docs/phases/Second_Mac_Bench.md`. |
| Smart / auto model routing | Brainstorm only: `docs/phases/Scarcity_Aware_Routing.md` — read §3 rejected list first. |
| Stale teaching / invented flags / empty `help search` | `docs/phases/Agent_Teaching_Surface.md`. Code: `TeachingSnippet`, `HelpTopicRegistry`, `RetiredVocabulary`, `AllnighterVersionIdentity`. |
| Composer `@` file references | `docs/phases/Composer_File_References.md` (not SSOT). |
| CLI surface, `alln`, TeamRunJSON, `alln artifact` | Code: `ContractRegistry`, `ArtifactProjector`/`ArtifactWriter`/`ArtifactCLI`. Naming: `docs/phases/CLI_Product_Spine.md` (not SSOT). |
| Agent front door: `install-cli`, `bootstrap`, live menu, help | Live `alln menu --json` is the selection front door; CLI is the only agent surface. `alln bootstrap [--host]` prints host context. No intent router. Code: `MenuCatalog`, `Bootstrap`, `InstallCLI`, `TeachingSnippet`, `HelpTopicRegistry`. |
| Cold start — no `alln` on PATH | `docs/phases/One_Paste_Cold_Start.md`. |
| Trial / pay / Stripe / `alln billing` | Law: `docs/operations/Project_Laws.md` §Entitlement. Remaining: `docs/phases/Trial_And_Entitlement.md`. Code: `EntitlementGate`, `BillingCLI`, `infra/pay`. |
| Ship CLI / Mac DMG / notarize / `latest.json` | `docs/operations/Public_Release.md` — **§ Version bump law**: Core/CLI/`get-alln.sh` fixes require a new `binaryVersion` + publish; never reuse a version prefix. Mac-only GUI can ship in the app alone. Verify candidate `alln version` gitSha = `git rev-parse HEAD` before upload. Not Organizer Direct Distribution. |
| `alln serve` dead / stale / disabled | Code: `ServeLifecycle`, `ServeDaemon`, `ServeStatusJSON`. Vocab: `docs/workflows/Product_Vocabulary.md` §Background scheduler. Serve owns scheduling, never run semantics. |
| Spec Review, measurement lies, Min/Max seat changes | `docs/operations/Spec_Review.md` + `BuiltInTeams` / `SkillCatalog.leadCallEnvelope`. Measurement: §3–§4, `measurement_auditor`. A dropped seat's questions must be absorbed by a remaining named pass. |
| Visual design / brand / tokens | `docs/design-system/readme.md` + `docs/design-system/production.md`. |
| Building a UI surface, layout proof, SwiftUI state, Mac vs iOS share | `docs/gui/GUI_Workflow.md` (§5 default **no** shared SwiftUI), `docs/gui/Visual_Proof_Gate.md`, `docs/operations/SwiftUI_State_Rules.md`. |
| Ask AI / in-app help / support email | Title-bar Ask AI. Code: `AskAIPrompt`, `AskAIModel`, `ChromeCatalog`. Hatch: support@allnighter.io. Chrome: `alln chrome --json` (not doctor). Dev-only: `alln dev ask-ai` (not in `alln menu`). Brief: `docs/gui/surfaces/ask-ai/brief.md`. |
| Design team (build → screenshot) | `docs/operations/Design_Lane.md` + `DesignBoardCapture`. |
| Shared models, drivers, fan-out, synthesis | `docs/mvp/01_Core_Package.md` → `docs/mvp/02_Worker_Drivers_And_Fanout.md` / `docs/mvp/04_Synthesis_And_Plan.md` as scoped. |
| Historical Mac shell / what shipped | `docs/mvp/03_Mac_App_And_Run_Loop.md`. |
| Judgment chain (RB0–RB6) | `docs/mvp/RB0_Judgment_Workflow_Overview.md` + routed RB docs. |
| New feature / founder note | `docs/workflows/SSOT_Founder_Input_Workflow.md` → `docs/workflows/SSOT_Feature_Workflow.md`. |
| Sprint / slice / closeout / Green Wall / test pile-ups | `docs/operations/Execution-Playbook.md`. One bounded slice: `docs/phases/sprint/README.md`. |
| Deslop / Code Audit / bugs / cleanup / GLM / stack | `docs/operations/Deslop.md`, `docs/operations/Code_Audit.md`, `docs/operations/Debugger.md`, `docs/operations/code-maintainer/`, `docs/operations/GLM_Worker_Best_Practices.md`, `docs/operations/TechStack.md`. |
| Copy lane | `docs/phases/copy/README.md`. |
| iOS companion / simulator loop | `docs/phases/ios/README.md` + `docs/operations/ios-testing-loop.md`. |
| Marketing / pricing / legal / strategy | `docs/marketing/README.md`; price changes: `docs/phases/Pricing_Change_Process.md` (founder ruling; offer SSOT `docs/marketing/Pricing_Recommendation.md`); `docs/legal/README.md`; `docs/strategy/`. |
| Product scope / MVP | `docs/mvp/README.md` + `docs/mvp/00_MVP_Architecture.md`. |
| Open packets / what to archive next | `docs/phases/README.md` (ephemeral — never SSOT; closeout = promote + archive). |
| Anything already shipped and archived | `docs/archive/phases/README.md`. Closed packets are not routed from here. |

This table is first routing only. Narrower docs named by the target phase doc,
GUI brief, or design-system page still apply.

## Commits

Agents commit their own work directly with git. Stage **explicit paths**; never
sweep unrelated dirty files; never `git reset --hard` or rewrite shared history
on `feat/design-chain`. Finished work is not left uncommitted unless the waiver
is explicit. Full rules: `docs/operations/Execution-Playbook.md` § Commits.

## Project Laws

Full text: `docs/operations/Project_Laws.md`. Incident-preventing subset:

- **Capacity:** `alln capacity` is a daily-use surface the founder reads and
  routes work by hand from. The 2026-08-12 kill covers **automated seat
  selection only**. Never degrade acquisition for any source. "No code
  consumer" ≠ "no consumer".
- One vendor's parser, matcher, or heuristic never answers for another —
  scope every signal by `sourceId`. Absence of a declared signal yields no
  observation.
- Failure to observe is never observation of absence (`ProbeRecordMerge`).
- A test may not reach a live vendor or the user's real state
  (`docs/operations/Execution-Playbook.md` § Green Wall).
- Pure model name = newest in family; versioned ids stay exact pins
  (`docs/workflows/Product_Vocabulary.md` §pure name).
- Exactly one mutating worker per repo root (`RunWriteLockRegistry`;
  `scripts/check_architecture_policy.sh`).
- Sensors inform, never block. Parked driver, disabled model, unknown model
  id, and the per-root write lock still refuse (user intent / real
  invariants). Provenance is not a refuse-class (explicit local `--pm`
  discloses and proceeds).
- Buy path is Stripe Checkout with email, not Sign in with Apple.
  `nextAction.command` is never a Stripe URL. Production Worker uses Allnighter
  live Stripe only — never xterminal keys, never the sandbox in live.
- **CLI version bump:** Any fix in Core, Engine, CLI, or `get-alln.sh` that
  changes shipped behavior requires bumping `AllnighterVersionIdentity.binaryVersion`
  and publishing a **new** version — never overwrite an immutable R2 prefix.
  Shared Core fixes affect CLI-only agents, not just the Mac app. Full steps:
  `docs/operations/Public_Release.md` § Version bump law.

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

Raw `swift test` / `xcodebuild test` are blocked by a PATH shim. Wrappers only:

```text
scripts/swift-test.sh --filter <TouchedTests>   # iteration proof
bash scripts/check.sh                           # closeout ONLY, never mid-slice
scripts/kill-stale-tests.sh                     # emergency stale-runner cleanup
```

A lock failure or timeout is a stop signal — do not retry, poll, or wait-loop.
Rules: `docs/operations/Execution-Playbook.md` § Green Wall.

Until Xcode targets exist, name the missing proof in closeout. Do not claim
behavior is proven without a Works Test or explicit waiver.
