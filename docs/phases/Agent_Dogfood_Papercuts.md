# Agent Dogfood Papercuts (ADP)

**Status: In progress (2026-07-21).** SSOT for the post-Sharpening dogfood batch.
Origin: two independent cold-caller dogfood reports against contract 3.0.0
(2026-07-21). Per the archived Sharpening dogfood law
(`docs/archive/phases/Alln_Sharpening.md`), every factual critique below is
entered as claim + receipt + verdict. Only the four claims that generalize
across the universal agent path (discover → probe → dry-run → run → reproduce)
are in scope. Rejected/parked items are listed at the end so they are not
re-litigated from future tester feedback.

## Claim ledger

| # | Claim (caller) | Receipt | Verdict |
| --- | --- | --- | --- |
| 1 | `reproduceCommand` drops `--worker` (1 caller) | `RunCLI.reproduceCommand` (`RunCLI.swift`) emits only `--project/--team/--effort`; `AllnighterCLI.reproduceCommand` (legacy show/export) emits only `--lane/--team/--effort/prompt`. `TeamRun` persists no explicit-worker selector to rebuild from. | CONFIRMED — violates the Sharpening outright-fail rule "dropped explicit selector". |
| 2 | Trivial single-worker ask resolves `writePolicy: mutating`; agents fall back to `--no-commit` instead of the answer path (BOTH callers independently) | The read-only steer exists only in `ContractDocs.swift` ("Callers that need a mechanical read-only guarantee select an **answer team**") — a docs page. The dry-run `warnings`/`nextAction` for an explicit-worker mutating-allowed resolution do not name the answer-team alternative. | CONFIRMED as a teaching-surface gap. Two independent callers ⇒ mandatory investigation per dogfood law. |
| 3 | Empty `name` fields in `teams --json` | Verified against the current binary (`alln teams --json`): every built-in row's `displayName` is populated (`TeamPreset.displayName` → `MenuCatalog.project` teamRows → `TeamCatalogJSON.project`). The failure is reachable, not phantom: `alln teams duplicate <id> --name "" --json` (an *explicit* blank, not an omitted flag) saves a custom `TeamPreset` with a literal `displayName: ""` — `TeamCatalog.saveCustom` never validated non-blank names — and that empty string then surfaced verbatim in every catalog/menu row keyed on the new custom id. | CONFIRMED (reachable via the `--name ""` path on `teams duplicate`, not on any built-in). Fixed at the disclosure layer — see ADP-S03. |
| 4 | `help search "create team"` weak; `teams new` summary says "Not an alias for `teams create`" — names a verb that does not exist | `ContractRegistry+Milestone1.swift:248` contains the phrasing. Help discovery index lacks task-verb synonyms for team authoring. | CONFIRMED (wording); search weakness to verify with the discovery index. |

## Laws honored (no new laws)

- **Selector preservation** (SH-S01, gate: outright fail on dropped explicit
  selector) — now extends to every replay surface: `reproduceCommand` must
  round-trip every explicit selector (`--worker`, `--team`, `--effort`,
  `--lane`, `--project`) exactly as the caller's invocation resolved.
- **Effects are permission, not prediction** (SH-S05) — unchanged. ADP-S02 does
  NOT change write-policy resolution, add lanes, or auto-route. It only teaches
  the existing read-only answer path at the decision point (dry-run output),
  per Menu-Not-Router: caller chooses, alln discloses.
- **No new grammar** (SH-S10) — no new flags or commands in this batch.
- **Canonical-ids-only dispatch** — name fields are disclosure for the caller
  LLM to resolve; never fuzzy-matched by alln at dispatch.
- **contractVersion stays 3.0.0** — value/teaching fixes only; hash-lock
  refresh allowed where teaching text changes, no schema shape change.

## Slices

| Slice | Deliverable and acceptance |
| --- | --- |
| **ADP-S01 — Reproduce round-trips every explicit selector** | **Done 2026-07-21.** Added `TeamRun.explicitWorkerIds: [String]?` (`TeamRun.swift`, additive optional, canonicalized to the resolved worker id; legacy `run.json` decodes nil / omits the key when unset). Wired at run acceptance in `RunService.swift` (computed from `invocation.explicitWorkerChosen` next to `laneContextOnly`; threaded through `runExecution`/`runAnswer` + set on the pending-lock stub, the execution `TeamRun`, and the answer-path `stamped` closure; parked/retry paths forward the persisted value). Both builders now round-trip every explicit selector — `RunCLI.reproduceCommand(_:project:)` emits prompt + `--project` + `--team` + `--worker` (per id) + `--effort` + `--lane` (only when `laneContextOnly`) + `--no-commit` (when `noCommitOrdered`); legacy `AllnighterCLI.reproduceCommand(_:)` emits the same minus `--project`. Gate: `ReproduceCommandTests` (4 tests) — builder emits `--worker`, reproduce argv re-resolves through `RunInvocationResolver` to the same seats + writePolicy, legacy builder emits `--worker`, and additive-optional legacy byte-parity/decode. Filter: `swift test … --filter 'ReproduceCommand'` (4 passed). |
| **ADP-S02 — Dry-run teaches the read-only path at the decision point** | **Done 2026-07-21.** Added additive optional `RunDryRunJSON.alternatives: [Alternative]?` (`RunDryRunJSON.swift`; `Alternative` = `kind`/`label`/`command`/`argvTemplate`/`templateVariables`, same tokenized-argv teaching shape as the resolver). `ResolvedRunInvocation.makeDryRunJSON()` (`ResolvedRunInvocation.swift`) now calls `readOnlyAnswerTeamSteer()`: when `writePolicy == .mutating && !explicitTeamChosen`, it appends ONE warning naming the canonical read-only answer team (`code_plan`, the Code-lane default the docs already reference) and emits an `alternatives` entry carrying a ready `--team code_plan` invocation built via `RunInvocationResolver.buildTemplate` — preserving the caller's `--worker`/`--effort`/message selectors and dropping the redundant `--no-commit`. Zero write-policy/routing/lane change (SH-S05 intact; discloses, never auto-routes). `contractVersion` unchanged (3.0.0) — `RunDryRunJSON` is not a hashed schema artifact and the teaching text is runtime-generated, so no hash-lock refresh was needed (`ContractLockTests` green). Gate: `ResolvedRunInvocationTests` +4 — bare ask + explicit-worker bare ask show the steer (worker preserved), answer-team (`code_bug_hunt`) and explicit mutating team (`build_slice`) do NOT. Filter: `swift test … --filter 'ResolvedRunInvocation'` (20 passed); `RunDryRun`/`WritePolicy`/`DryRun` filters green. |
| **ADP-S03 — teams list discloses names** | **Done 2026-07-21.** Verified: built-in catalog rows always carry a non-empty `displayName`; the reachable failure is `teams duplicate <id> --name "" --json`, which persists a custom `TeamPreset` with `displayName == ""`. Fixed at the disclosure layer, not the write path (custom teams may legitimately be renamed blank-then-fixed by an editor; the catalog must never leak it either way): added `TeamPreset.disclosedDisplayName` (`TeamCatalog.swift`) — trims and falls back to the canonical `id` when `displayName` is blank/whitespace-only. Wired at every catalog/menu row that discloses a name: `MenuCatalog.project` teamRows (`MenuCatalog.swift`, feeds both `alln menu --json` and `alln teams --json` via `TeamCatalogJSON.project`), `MenuCatalog.showTeam` (`alln menu show team:<id>`), `TeamShowJSON.project` (`alln teams show --json`, `CatalogJSON.swift`), and the plain-text `alln teams` listing (`AllnighterCLI.swift runTeamCatalog`). Dispatch/`displayName` storage itself is untouched (still round-trips whatever a caller wrote) — this is disclosure-only, canonical-ids-only dispatch is unaffected. Gate: `TeamCatalogTests.swift` — `testBlankDisplayNameFallsBackToIdForDisclosure` (unit: blank/whitespace/normal names) + `testTeamCatalogJSONNeverEmitsEmptyDisplayName` (reproduces the `--name ""` duplicate against a temp catalog root, asserts every `TeamCatalogJSON` row has a non-empty `displayName`). Filter: `swift test … --filter 'TeamCatalog'` (9 passed); `MenuCatalog|FrontDoor|ContractRegistry|CatalogPersistence|TeamsDuplicate|TeamsNew|CatalogCLI` also green (60 passed) confirming no regression. |
| **ADP-S04 — Team-authoring findability + false-affordance sweep** | **Work order.** Help discovery index resolves task-verb queries ("create a team", "make a custom team", "new team", "build a team", "customize a team") to the `teams new` / `teams duplicate` authoring topics (synonyms on existing topics; no new grammar), and the `teams new` summary drops "Not an alias for teams create" (never name a verb that does not exist — sweep repo-wide for other instances). Gate: help-search cases in the help corpus (`HelpDiscovery|HelpSearch` filters green); retired-vocabulary wall extended with the false-affordance phrase. |
| **ADP-S05 — Version identity: single source + bump rule** | **Work order.** `binaryVersion` single-sourced in Core (`AllnighterVersionIdentity.binaryVersion`); `AllnighterCLI` + `CodexMessage` clientInfo read it (a second hardcoded `"0.9.0"` exists in `CodexMessage.swift` clientInfo — drift risk). Bumped **0.9.0 → 0.9.1** for this batch. Drift gate: `VersionIdentityTests` asserts no other hardcoded `binaryVersion` literal in Sources. Rule recorded below. |

## Version rule (founder 2026-07-21)

- **Patch (+0.0.1) on every shipped batch** of behavior/teaching changes
  (e.g. this batch: 0.9.0 → 0.9.1). A batch = the set of slices landed under
  one SSOT doc, bumped once when the batch completes, not per commit.
- **Minor (+0.1.0) when `contractVersion` takes a major cut** (public shape
  change, like the 2.1.0 → 3.0.0 cut) — so callers can read "public shape
  changed" off the binary version alone.
- `contractVersion` keeps its own existing law (schema-shape governed); the two
  numbers never substitute for each other.
- The binary version has exactly ONE definition in code; everything else
  (clientInfo handshakes, doctor, version --json) projects it.

## Rejected / parked (do not re-litigate from tester feedback)

- Pre-run cost estimates — violates the no-estimates law (observed facts only);
  observed historicals belong to the parked Cost Advisor.
- Inline per-seat overrides (`--seat X=model`) — no-new-grammar; duplicate →
  definition → edit is the deliberate authoring path (D1).
- Fuzzy name resolution at dispatch — canonical-ids-only; ADP-S03 is the
  legitimate disclosure-side fix.
- Latency chase for token-count probes — floor is the vendor CLI; warm lanes +
  observed `ttftMs` already shipped; NDJSON `--stream` already machine-readable.
- Menu Tier-1 size — inside the ratified ≤32 KiB budget; owned by
  Menu_Not_Router; flagged as budget pressure, not acted on here.

## Routing

- Receipts and verdicts: this doc. Durable laws: `CLI_Implementation_Contract.md`
  (nothing promoted from this batch — no new laws created).
- Fix routing (founder 2026-07-21): Claude-only; ADP-S01/S02 heavy (Opus),
  ADP-S03/S04/S05 light (Sonnet); session is PM.
