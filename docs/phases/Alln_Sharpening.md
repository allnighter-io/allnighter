# Alln Sharpening — from a tool agents can use to a tool agents prefer

Status: **In Implementation (2026-07-20) — D1–D4 ratified and D5 replaced by
typed founder reply; SH-S00–S02 done (owned wall green + remaining reds named in
`docs/operations/debugger/QUARANTINE.md` § SH-S00); SH-S03–S10 not
started.**
Owner: AllnighterCore (`TeamRunJSON`, `RunDryRunJSON`, `TeamCatalog`,
`MenuCatalog`, `ContractRegistry`) + AllnighterEngine (run resolution/timing) +
AllnighterCLI (run/docs/teams projections)
Updated: 2026-07-20

Successor to archived `Menu_Not_Router.md` (MNR) and completed
`CLI_Agent_Ergonomics.md` (AE). ASF made the CLI honest in what it says. AE
made it complete in what it reveals. MNR made selection the caller's job with
one bounded menu and one run grammar. **This phase makes the selected operation
cheap to consume, exact to preview, and difficult to misreport.**

Related: archived `Menu_Not_Router.md` (selection laws — do not re-decide) ·
`Unified_Run_Model.md` (write-policy semantics) · `CLI_Implementation_Contract.md`
(public schema/version owner) · `Team_Depth_Naming.md` (team naming) · archived
`Warm_Single_Lane_Chat.md` (latency owner) ·
`docs/workflows/SSOT_Feature_Workflow.md`

## Founder intent and trusted slice

**Intent:** make `alln` faster, simpler, and easier to use until agents prefer
it to calling a vendor CLI directly.

**Product value:** one live discovery read, one truthful free preview, one exact
execution grammar, and one obvious result path—while retaining Allnighter's
team methodology, subscription-CLI leverage, lifecycle truth, and write safety.

**Trusted workflow slice:** discover in `menu` → preview the exact invocation →
run it → read the canonical result → recover mechanically if it fails.

**Prior art adopted:** generated command declarations and fail-closed parsing
(clap/Cobra/Swift ArgumentParser), explicit preview/apply separation
(`terraform plan`, `kubectl --dry-run`), compact machine output (`gh --json`,
Git porcelain), manifest-based creation (`kubectl create -f`), and exact
did-you-mean recovery (git/cargo). We deviate only where the run is inherently
agentic: a preview reports write *permission*, not a prediction that a prompt
will or will not cause a write.

## What happened

Four cold agents on the post-MNR binary (`e17fd892`) were given the same broad
task: use `alln` to get Sonnet 5 to say `success`, explain how to make a Bug Hunt
team, and critique the tool. All four found the front door, used the correct
`run --worker` grammar, and extracted the answer. Scores were 7, 7, 8, and 8.
There were no false-absence reports, wrong spends, or discovery loops.

That is the MNR bet paying off, and it moves the problem. AE-era feedback was
dominated by false absence (7 of 11 claims were false). This round exposed a
smaller but more consequential set: one preview loses the selector it claims to
validate; a tiny answer arrives in a catalog-heavy envelope; and team inspection
has enough split presentation that agents reported the same Bug Hunt as both
four and five workers.

Two caveats bind the phase:

1. **One prompt is one sample.** It over-samples one-shot `--worker` and team
   authoring, and says little about detach, waiting, recovery, or typed outputs.
   The diversified harness defines the bar before another rating round does.
2. **Agent prose is untrusted input.** A model produces plausible explanations;
   it does not become a reliable CLI auditor because it successfully ran one
   command. A complaint enters the phase only after a code read or pinned-binary
   probe. `alln` cannot make a probabilistic caller stop hallucinating. It can
   make the executable truth compact, attributable, and cheap to verify.

## First principles — what makes an agent prefer a tool

An agent choosing between `alln` and the vendor CLI one layer down minimizes
total cost per unit of trusted value:

```text
cost  = discovery calls + execution calls + bytes consumed + wait + recovery ceremony
value = the intended operation, with extractable output and evidence it ran as previewed
```

The vendor CLI starts with a familiarity advantage. Alln earns the extra hop
only when orchestration value exceeds that hop's cost. Therefore:

- **Do not ask the model to remember product truth.** Put ids, constraints,
  effects, and recovery in bounded machine contracts.
- **Do not make the caller re-prove a preview.** Preview and execution share one
  resolved invocation; selectors cannot be re-derived on the real path.
- **Do not make small asks pay for global facts.** Catalog data lives in `menu`;
  run data lives in the run envelope; canonical answer text appears once.
- **Do not optimize inferred latency.** Project already-recorded timing phases;
  optimize only a measured owner.
- **Do not turn feedback into features by vote.** Repeated confusion is a signal
  to inspect. Code and pinned-binary receipts decide whether it is a defect.

## Verified claims ledger

Probed 2026-07-20 against binary `e17fd892` (`contractVersion 2.1.0`; built-in
menu 32,418 bytes, 103 commands, 4 actions, 25 teams, 22 models).

### Confirmed — this phase owns them

| # | Finding | Evidence |
| --- | --- | --- |
| 1 | **Pinned-worker dry-run resolves the Default Team before the explicit worker.** `run "probe" --worker model_sonnet --dry-run --json` reports `default_chat` / Auto, two seats, Default Team warnings, and the Default Team write lock even though the actual selector is `model_sonnet`. | `RunCLI.emitDryRun`; live probe |
| 2 | **The dry-run teaching action drops the worker selector.** Its success command is always `alln run "<message>" --project <id> --json`; following it dispatches Auto. It also uses an undeclared `<message>` placeholder inside a field named `command`. | `RunCLI.swift:328–345`; live probe |
| 3 | **No canonical result field exists.** Callers branch between `workerAnswers[].markdown`, `plan.markdown`, and typed board fields. | `TeamRunJSON.swift`; `TeamRunJSONMapper.swift` |
| 4 | **Every result embeds the entire model input passed to the mapper.** The live bench has 22 models; the mapper serializes all of them even though workers already snapshot run-relevant model/source facts. | `TeamRunJSONMapper.swift:150–159` |
| 5 | **Typed refs do not round-trip across discovery and docs.** `menu` emits `command:teams.duplicate`; `menu show` resolves it; `docs` resolves the spaced command name but not the emitted typed ref. The guessed bare dotted form fails without a suggestion. | live probe |
| 6 | **Run flag constraints are only partly machine-visible.** `ContractRegistry` owns mutual-exclusion groups, but `menu show command:run` and normal `docs run` omit the group set. Mode-scoped flags such as `--thread-id` (detach) and `--executor` (try-fix) can be accepted outside their mode and ignored. | `ContractRegistry+Milestone1.swift`; `RunCLI.run` |
| 7 | **Usage hides enum domains.** `run --help` renders `[--effort <effort>]`; `docs run` knows `low | med | high`. The same source is not driving both projections. | live probe |
| 8 | **There is no CLI create operation for a novel team and duplicate ids are generated.** Core already supports fresh custom ids and saving new definitions; the CLI exposes only duplicate → definition → edit and cannot accept a caller-chosen duplicate id. | `TeamCatalog.freshCustomId/saveCustom`; CLI registry |
| 9 | **One team has two apparent sizes.** `teams --json` reports Bug Hunt `workerCount: 5` (four crew seats + lead); `teams show` returns four `workerSpecs` and no lead. The attached agents consequently reported 4 and 5. Understanding lead models/fallbacks still requires `teams definition`. | live probe |
| 10 | **Dry-run does not project MNR's resolved effect contract.** It exposes one `mutating` boolean, with no resolved `workerStart`, `quotaSpend`, `repoWrite`, `destructive`, or `humanInteraction` block and no distinction between permission to write and an observed repo delta. | `RunDryRunJSON.swift`; MNR §3 |

### Refuted or clarified — do not build these

| Claim | Ruling |
| --- | --- |
| “`help search` has no `--json`.” | False; it returns structured results plus `catalogRevision`. |
| “Enum values are undiscoverable.” | Overstated; `docs run` enumerates effort. Fix the generated projection gap, not a second enum registry. |
| “There is no per-command schema.” | False; `docs "teams duplicate"` and `menu show command:teams.duplicate` expose it. Fix ref round-trip and constraints. |
| “A pure Q&A showing `mutating: true` is wrong.” | False under `Unified_Run_Model`: Default Team is mutating-allowed and prompt prose cannot prove read-only. Clarify permission vs observed mutation; do not classify prompt intent. |
| “Project registration is broken ceremony.” | False. It failed closed with the exact `project add <git-root>` repair and the agent recovered. Keep the one grammar; do not add `--here` as an alias for `.` or silently register state. |
| “Four actions for 103 commands means 99 are unreachable.” | False. `commands` is the exhaustive compact set; `actions` is intentionally a short fast path. Do not chase a coverage percentage or blow the 32 KiB menu budget. |
| “Models needs `--ready` / `--on-bench` / more filters.” | Not shown to reduce calls. `menu.models[]` already carries `enabled`, `ready`, and `blockedReason`; `models` already supports driver/Bench views. Machine callers can filter JSON. |
| “~10 seconds proves Alln is slow.” | Unproven. The vendor invocation dominates many one-shots and warm lanes already exist. Surface observed phase timing; do not infer blame or optimize an unmeasured layer. |
| “Run needs `--max-tokens` and `--temperature`.” | Wrong ownership. Alln drives subscription CLIs and their supported controls, not a model API. Teach the boundary so agents stop hunting. |
| “Add a global `--no-interactive`.” | No probed agent path prompts. A flag guarding nothing adds grammar without safety. |

## Founder decisions — resolved

**Founder-ratified by typed reply, 2026-07-20:** D1 "yes both" · D2 "keep as
is" · D3 "yes, clean single cut" · D4 "yes" · D5 **rejected as proposed**
("stupid and irrelevant, theater") and replaced by the founder's own ruling
below. Implementation agents do not reopen D1–D5; new evidence changes a
decision only through the verified claims ledger.

### D1. Ship `teams new` *and* deterministic duplicate

These are different acts, not aliases:

```bash
alln teams new <team-id> --file <TeamPreset.json> --json
alln teams duplicate <source-id> --id <new-id> [--name <name>] --json
```

`new` creates the supplied manifest and fails if the id exists or the file id
does not match the positional id. `duplicate` remains the preferred Bug Hunt
customization path because it starts from a valid shipped method; `--id` makes
it scriptable and deterministic. This matches the existing `skills new` convention
and exposes Core capability the GUI already relies on. Do **not** add a
`teams create` alias.

### D2. Keep explicit project registration exactly as it is

The status quo is both safe and successful: resolve cwd to a git root, fail
closed if unregistered, and return the exact
`alln project add <absolute-root> --json` next action. `project add .` already
expresses “here.” A new `--here`
spelling would add no capability; silent auto-registration would hide a durable
state change.

### D3. Make one clean schema cut; no `--full` escape hatch

Advance the agent contract to the next major (`3.0.0` from current `2.1.0`) and
`TeamRunJSON.schemaVersion` to `2`. Remove `models` from `TeamRunJSON`; add the
canonical `answer` contract; update CLI, Mac, iOS, fixtures, schemas, and generated
docs in the same cut. There are no external users requiring a compatibility
reader. `menu`/`models` own catalogs; run snapshots own only facts used by the
run. A `--full` flag would preserve two answer contracts and make every caller
choose again.

**Sequencing (founder 2026-07-20): the v3 cut lands once, at the end.**
SH-S01's `ResolvedRunInvocation` is internal and lands first. Every
public-shape change — the S02 envelope, S05 dry-run effects, S06 `seatCount`,
S07's new grammar, and any new error codes — is staged behind one coordinated
v3/schema-v2 landing as the phase's final cut. No intermediate contract bumps;
slices may merge behind the cut but the public surface changes exactly once
(AE-S11 forced-bump fires exactly once).

### D4. Keep one `run` verb and report write policy honestly

No `alln ask`, no prompt classifier, and no silent conversion of an execution
run to read-only because the prompt “looks like” Q&A. Dry-run reports the
resolved `writePolicy` and effect booleans. A caller requiring a mechanical
read-only guarantee selects an answer team; a Default Team or explicit worker
may write and must say so.

### D5. Alln never rates itself — agents rate alln (founder ruling)

Founder, 2026-07-20, replacing the consultant's ≥90/100 scorecard: a
self-assigned score is theater. *"Don't even try to rate it. We know it when
agents start using it well and rave about using it. Agents rate alln. We have
no say. Period."*

So: no 9/10 target, no ≥90/100, no internal rating of any kind, ever. What
remains is not a rating: a **pass/fail regression gate** over mechanical
truths (preview/run identity, selector preservation, zero wrong spend,
budgets) — bug detectors, binary, no number — plus the receipts ledger:
unsupported agent claims are recorded, probed, and promoted to a verified
finding or rejected. Success is observed externally and only externally:
agents choosing alln and raving unprompted. That signal cannot be
manufactured by a gate, and alln has no vote in it.

## Laws

Numbered locally; ASF/AE/MNR laws continue to bind.

**Laws are working hypotheses, not physics** (founder ruling 2026-07-20): a
law is revisable by founder ruling with a recorded why — and never by an
implementing agent mid-slice. The strong word exists to stop quiet mid-slice
erosion, not to forbid amendment.

1. **Cost is proportional to the ask.** A one-worker answer does not carry
   global catalog data. Response overhead is bounded independently of answer
   length.
2. **Canonical answer text appears exactly once.** `answer` is the stable result
   path. The selected worker/plan payload is moved there, not duplicated there.
3. **Preview truth is run truth.** Dry-run and execution consume one resolved
   invocation object. They cannot independently select team, worker, seats,
   effects, or flag mode.
4. **Teaching surfaces preserve behavior.** Every behavior-affecting explicit
   flag survives in a suggested command/template. Sensitive prose uses declared
   variables; it is never echoed merely to make a replay command executable.
5. **One typed ref grammar.** Every typed ref emitted by a surface resolves on
   every compatible consumer. Near-miss spellings fail with the canonical ref
   as a suggestion; they do not become aliases.
6. **Flags are honored or rejected.** A flag cannot be accepted outside the mode
   that consumes it. Constraints are registry data rendered in menu, docs,
   usage, validation, and completion.
7. **Permission is not outcome.** `repoWrite: true` means the resolved invocation
   may write and therefore uses write safety. Only terminal `repoDelta` reports
   whether it did. Prompt prose never owns this fact.
8. **Seat count has one meaning.** `seatCount` is the number of executable seats,
   including lead/scout and row multiplicity. Crew rows and lead are separately
   named; public `workerCount` is retired rather than left ambiguous.
9. **Feedback is a hypothesis ledger.** Claims need pinned binary identity plus
   a command/code receipt before they become scope. Ratings belong to agents;
   alln never rates itself (D5).

## Anti-goals

- No second run verb, intent classifier, recommendation oracle, or model call
  inside discovery.
- No TTY-dependent output, `--quiet`/`--field` matrix, or `--full` compatibility
  branch. One JSON contract is cheaper than format choice.
- No prompt-based read-only inference and no promise that an execution worker
  “will not use tools.”
- No silent project registration, `project add --here` alias, or fuzzy id
  execution.
- No blanket expansion of `menu.actions`; Tier 1 remains ≤32 KiB and complete.
- No model-API controls Alln cannot enforce through the selected subscription
  CLI.
- No latency target or pre-run estimate in this phase.
- No reopening MNR selection, team naming, lane vocabulary, or the Unified Run
  Model.

## Public contract decisions

### Canonical answer

`TeamRunJSON` v2 always serializes `answer` (null while non-terminal or when no
canonical result exists):

```json
{
  "answer": {
    "status": "done",
    "outputKind": "bugPacket",
    "markdown": "...",
    "source": {
      "kind": "plan",
      "workerId": "model_opus#lead",
      "modelId": "model_opus",
      "stageId": "stage_plan_01"
    },
    "typedResultField": null
  }
}
```

Derivation is deterministic:

1. A completed synthesized text result becomes `answer.markdown`; `plan` keeps
   provenance/status but no duplicate markdown.
2. A successful single-worker run moves that worker's markdown to `answer`; the
   corresponding `workerAnswers[]` row keeps status/model/timing but no duplicate
   markdown.
3. A typed board result sets `typedResultField` to the owning top-level field and
   may carry a lead summary in `markdown`; typed payload remains in its typed
   field.
4. A partial multi-seat run without synthesis does not guess a winner. `answer`
   is null and raw successful/failed seat outputs remain in `workerAnswers`.
5. Failed/cancelled/timed-out runs serialize `answer: null`; `outcome`, errors,
   and worker states explain why.

### Resolved dry-run effects

`RunDryRunJSON` v2 replaces ambiguous top-level `mutating` with:

```json
{
  "writePolicy": "readOnly | mutating",
  "effects": {
    "workerStart": true,
    "quotaSpend": true,
    "repoWrite": true,
    "destructive": false,
    "humanInteraction": false
  },
  "writeLockHeld": false
}
```

These booleans describe the real invocation after selectors and flags resolve.
`repoWrite` means permitted/possible, not predicted or observed.

## Implementation impact

- **Truth owners:** `ContractRegistry` owns commands/flags/constraints/refs;
  `ResolvedRunInvocation` (new Core/Engine value) owns preview/run selection;
  `TeamRunJSONMapper` owns canonical answer/timing projection; `TeamCatalog` owns
  create/duplicate validation.
- **Lie-prone layers:** `RunCLI.emitDryRun`, next-action/template renderers,
  docs/menu projections, `teams show`, generated schemas/fixtures, and Mac/iOS
  decoders.
- **Duplicate truth to delete:** `TeamRunJSON.models`, canonical markdown at
  `plan.markdown`/the selected one-worker answer, public `workerCount`, hand-built
  usage enum text, and CLI-local flag-mode checks not represented in registry
  constraints.
- **CLI surface:** only `teams new` is a new command; `teams duplicate --id` is
  a new flag. Existing `run`, `docs`, `menu`, `teams show`, and JSON shapes change
  in place under contract v3.
- **Teaching surface:** generated docs/usage/menu detail expose constraints,
  answer extraction, write-policy meaning, stream framing, and the subscription-
  CLI control boundary. `help search` terms include `create team`, `custom team`,
  `read only`, `stream`, and `answer field`.
- **Mac/iOS:** no new UI or parallel model. Both consume `TeamRunJSON` v2 in the
  same cut; compile/tests are required. No SwiftUI state owns these semantics.
- **Drivers/protocol:** no driver invocation change except using the same resolved
  preview object. NDJSON event framing is documented, not redesigned.
- **Auth/privacy/permissions:** no new permission, credential, network, quota, or
  cloud behavior. Dry-run templates keep prompt/context/commit prose as declared
  variables so preview output does not newly echo sensitive text.

New/duplicate team success exits 0 with structured team detail. Usage errors
exit 2 as `CLI_USAGE_ERROR`; invalid manifests/ids/collisions exit non-zero as
the existing `TEAM_INVALID`, `CATALOG_ID_INVALID`, or `TEAM_ID_COLLISION`
envelopes with exact recovery. Invalid run-flag combinations likewise exit 2
before preview, run-record creation, or provider start. No new untyped error
path is introduced.

## Slices — implementation order

Each slice is one bounded work order and leaves the release binary runnable.
Public-shape changes are staged behind the single end-of-phase v3 cut (D3
Sequencing).

| Slice | Deliverable and acceptance |
| --- | --- |
| **SH-S00 — Green the wall (entry gate)** ✅ | **Done 2026-07-20.** Owned fixes landed: fixture/`ContractRegistryTests` `2.1.0`; `CodeReviewParallelSafety` test passes `maxConcurrent: 2`; hermetic `ALLNIGHTER_SUPPORT_DIR` for `ExecutionLaneTests` + `RunAcceptanceBoundaryTests` (assertions unchanged). Focused owned filter green. Full package wall is **green-for-owned + quarantined-for-rest** — remaining reds (CursorAgent staffing, DefaultConfigDrift, `ExecutionTeamSourceGateTests.testMixedSourceJudgmentTeamPassesSourceGate`, Pilot/Relay/ProcessOwnership crash bucket, RelayCLI `model_pm` abort + post-truncation) named in `docs/operations/debugger/QUARANTINE.md` § SH-S00 (2026-07-20). SH-S01 may start with an attributable wall. |
| **SH-S01 — One resolved invocation serves preview and run** ✅ | **Done 2026-07-20.** Internal `ResolvedRunInvocation` + `RunInvocationResolver` in Engine; dry-run / `RunService.run` / `AsyncTeamService.start` consume one resolution (selected seats only; `--worker` no longer projects Default Team roster). Teaching `nextAction.command` preserves selectors via tokenized `argvTemplate` + `{name}` `templateVariables` (internal). Public `RunDryRunJSON` v1 unchanged (no contract bump). Gate: `swift test --package-path Packages/AllnighterCore --filter ResolvedRunInvocation` (10 tests). Fixes 1–2; Laws 3–4. |
| **SH-S02 — TeamRunJSON v2: answer-first and catalog-free** ✅ | **Done 2026-07-20.** One clean cut: `contractVersion` 2.1.0 → **3.0.0**, `TeamRunJSON.schemaVersion` 1 → **2**. Removed top-level `models`; added canonical `answer` (always serialized, null when none). Mapper `deriveAnswer` follows the derivation table; plan/one-worker markdown moved once (Law 2). Fixture is a minimal honest one-worker terminal (`answer.markdown` = `"success"`, ≤256 bytes). **Envelope overhead measurement (2026-07-20):** CoreJSON-style pretty+sortedKeys encoding of that fixture is 2300 bytes; `answer.markdown` is 7 UTF-8 bytes → **measured overhead = 2293 bytes**. **Budget = 4096 bytes** (measured + headroom for honest optional fields such as `repoDelta` / capacity observations — never truncate truth). Gate: `testOneWorkerEnvelopeOverheadWithinBudget`. Fixes 3–4; Laws 1–2. |
| **SH-S03 — Typed refs round-trip** | `docs command:teams.duplicate` and every other emitted typed command ref resolve directly. Existing quoted command names remain their canonical human grammar. Bare `teams.duplicate` stays a near-miss and returns a structured suggestion for `command:teams.duplicate` / `teams duplicate`; no alias. Add a walker over refs and templates emitted by menu/docs/errors that resolves each on its stated consumer. Fixes 5; Law 5. |
| **SH-S04 — Run flags are honor-or-fail** | Extend registry constraint data beyond mutual exclusion to mode requirements (`requires`, `onlyWith`) and route validation through it before dry-run/run. At minimum: detach-only thread/conversation/message ids; `--executor` only with `--try-fix`; `--accept-survivors` only with `--retry-of`; current dry-run/stream/try-fix and detach/stream/try-fix exclusions; commit flags exclusive. No accepted flag may disappear in foreground, detach, try-fix, or dry-run. Gate every declared run flag across valid/invalid modes and assert invalid combinations create no run/provider process. Fixes 6; Law 6. |
| **SH-S05 — Resolved effects say permission, not prediction** | Project the v2 `writePolicy` + full boolean `effects` block from `ResolvedRunInvocation`; remove top-level `mutating` from dry-run. Docs define `repoWrite` as permission and point mechanically read-only callers to answer teams. Run results retain actual `repoDelta`; no prompt inspection. Gate execution team, answer team, explicit worker, and `--dry-run` free-twin matrices against registry effects and lock behavior. Fixes 10 and the Q&A confusion; Law 7. |
| **SH-S06 — One team read explains the whole team** | Clean-cut public `workerCount` to `seatCount`. `teams show` exposes crew, optional scout, and lead with role, skill, count, preferred/fallback/allowed models, required capabilities, and triangulation; `teams definition` remains the full round-trippable manifest, not a prerequisite for understanding. Menu/list/show/dry-run derive seat count from `TeamPreset.catalogSeatCount`. Gate all built-ins/customs: projected seat sum = list = menu = preview, including row multiplicity. Fixes 9; Law 8. |
| **SH-S07 — Team authoring has two explicit motions** | Add `teams new <team-id> --file <path> --json` and `teams duplicate <source-id> --id <new-id> [--name] --json`. `new` rejects an existing/reserved/mismatched/invalid id with stable errors; duplicate rejects collisions and preserves generated-id behavior only when `--id` is omitted. Both return the same structured team detail. Generated docs/cards teach duplicate → definition → edit for variants and definition → new for novel manifests. Gate deterministic ids, collisions, built-in immutability, restore, and cold-agent custom Bug Hunt. Fixes 8; D1. |
| **SH-S08 — Surface observed timing without causal fiction** | Add per-worker `queueMs`, `ttftMs`, and `durationMs` from existing timing truth plus terminal `outcome.timing.wallMs`. Null means the driver did not report the observation. Docs state clock boundaries; headline may summarize a single-worker split but may not call subtraction “Alln overhead” or assign blame in parallel runs. No forecasts or targets. Gate exact fixture timestamps and absence of `estimate` vocabulary. |
| **SH-S09 — Diversified, quota-free regression gate** | Add `scripts/agent_eval.sh --suite sharpening` backed by fixture drivers and isolated temporary project/catalog state; it starts no paid provider. Cases: one-worker answer, answer team, team inspect, both authoring paths, detach + wait + result, bad-id recovery, unregistered-root recovery, typed-ref docs. Capture binary SHA, argv, exit, response bytes, created-run/provider evidence, preview/result identity, and claim ledger. Enforce the pass/fail gate below (no score — D5). |
| **SH-S10 — Generated papercuts, no new grammar** | Render enum domains and registry flag constraints in usage, docs, menu detail, and generated schema; document NDJSON `--stream` framing/terminal rule and why token/temperature controls belong to vendor CLIs. Keep `menu.actions` short and ≤32 KiB; add no action solely to improve the 4/103 ratio. Gate every enum/constraint projection against its owner and the active help-corpus resolvability/retired-vocabulary wall. Fixes 6–7 and the verified teaching gaps. |

## Mechanical pass/fail gate (no score — D5)

Each case starts from only the bootstrap snippet and its task. Its call budget
includes one `menu --json` discovery read. Poll loops use the blocking/wait form,
not repeated polling. Fixture answers are ≤256 bytes so envelope overhead is
comparable.

| Case | Maximum CLI calls | Required result |
| --- | ---: | --- |
| Ask one named worker | 3 | menu → dry-run → run; `answer.markdown` first try; envelope overhead within the SH-S02 budget (**4096 bytes**; measured 2293) |
| Send to one answer team | 3 | menu → dry-run → run; preview/result team and seats identical |
| Inspect one team | 2 | menu → show; lead + crew + exact `seatCount` visible |
| Make a custom Bug Hunt | 4 | menu → duplicate → definition → edit; caller-chosen id survives |
| Create a novel team | 3 | menu → definition/schema read → new; no generated-id parse |
| Detach and retrieve | 5 | menu → dry-run → detach → wait/status → result; one run id |
| Recover bad id / unregistered root | 4 each | structured error → exact next action → successful retry; zero spend before retry |
| Open docs from a menu ref | 2 | menu → `docs <typed-ref>`; no spelling translation |

There is no score (D5). The gate is binary: every case passes within its
budgets or the phase is not done. The checked truths: bounded complete menu;
one-worker call budget; one-worker byte budget; preview/result identity;
selector preservation; team inspection/count consistency; both authoring
paths; detach lifecycle; error recovery without spend; typed-ref round-trip.

Independently of the case table, any preview/result identity mismatch, dropped
explicit selector, unintended provider start, accepted-but-ignored flag, or
write-policy falsehood fails the gate outright.

Dogfood corroboration runs after the mechanical gate with at least three
caller model families and varied tasks. Every factual critique is entered as
`claim + binary SHA + command/code receipt + verdict`; repeated unsupported
claims from two independent callers require a teaching-surface investigation
or an explicit no-fix ruling. Ratings belong to the agents (D5): alln records
them as external signal and never computes one of its own. The rave —
unprompted preference by working agents — is the only rating that counts.

## Works Test

The default proof is quota-free and isolated:

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
B=Packages/AllnighterCore/.build/release/alln

scripts/agent_eval.sh --suite sharpening --binary "$B"
bash scripts/check.sh
```

The suite must print per-case pass/fail, hard-failure count, per-case calls and
bytes, binary SHA/version, and its isolated state directory — no score (D5). It must also prove
no provider process started in preview/recovery cases. A live Sonnet smoke is
optional corroboration and requires explicit quota-spend approval; it is not
part of the green wall.

## Inference bans

| Junction | Truth owner | Bad inference | Mechanical ban |
| --- | --- | --- | --- |
| dry-run → run | `ResolvedRunInvocation` | “Preview is approximate.” | one value serves both; identity fixtures |
| explicit flag → mode | registry constraints | “Unused here means harmless.” | invalid mode fails before run/provider creation |
| teaching action → invocation | argv template projector | “The suggested command is close enough.” | selector/flag round-trip matrix; declared sensitive variables |
| envelope → answer | `TeamRunJSON.answer` | “The caller will find it somewhere.” | derivation table + answer-once fixture gate |
| run → catalog | `MenuCatalog` | “Embed all models just in case.” | no-models schema + byte budget |
| team rows → size | `catalogSeatCount` | “Crew rows equal executable seats.” | one `seatCount` across list/show/menu/preview |
| prompt → write safety | resolved `writePolicy` | “This sounds like Q&A, so it is read-only.” | no prompt classifier; answer-team mechanism only |
| timings → blame | recorded timing keys | “Wall minus vendor equals Alln overhead.” | named clock boundaries; no inferred phase |
| agent critique → roadmap | verified claim ledger | “Several models said it, so it exists.” | receipt required before promotion |

## Done when

- SH-S00–S10 are checked or explicitly waived by the founder; no blocking
  product question remains.
- The wall was green (or quarantined by written ruling) *before* SH-S01
  started, and is fully green at close.
- Contract v3/schema v2 is one clean cut across CLI, generated artifacts,
  Engine, Mac, and iOS; no compatibility branch or duplicate canonical markdown
  survives.
- `scripts/agent_eval.sh --suite sharpening` passes every case with zero hard
  failures on a release binary built from committed HEAD.
- One-worker answer overhead is within the SH-S02 measured budget, Tier-1 menu
  is ≤32 KiB, and the caller reaches every matrix result within its call
  budget.
- The full green wall passes, the phase is archived, and durable laws are
  promoted to the owning code/docs.

## Open questions

None. D1–D4 ratified and D5 replaced by typed founder reply 2026-07-20; the
three PM hardening additions (SH-S00 green-wall entry gate, single
end-of-phase v3 cut, measured-not-asserted envelope budget) ride with them.
Laws-are-working-hypotheses and budgets-as-guards were founder-authored the
same day. New evidence changes a decision only through the verified claims
ledger.

## Routing

| Work | Read first |
| --- | --- |
| Preview, run flags, effects, teaching templates | **This doc** SH-S01/S04/S05 + archived MNR |
| Run envelope / canonical answer / timing | **This doc** SH-S02/S08 → `CLI_Implementation_Contract.md` |
| Docs/menu/error refs and generated help | **This doc** SH-S03/S10 |
| Team projection and authoring | **This doc** SH-S06/S07 → `TeamCatalog.swift` |
| Write semantics | `Unified_Run_Model.md` + this doc D4/SH-S05 |
| Selection/menu/bootstrap | archived `Menu_Not_Router.md` — settled |
| Runtime latency optimization | archived `Warm_Single_Lane_Chat.md` — not this phase |
