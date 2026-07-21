# Agent Dogfood Papercuts (ADP)

**Status: Done (2026-07-21).** ADP-S01–S05 all landed. SSOT for the post-Sharpening dogfood batch.
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
| 4 | `help search "create team"` weak; `teams new` summary says "Not an alias for `teams create`" — names a verb that does not exist | Both halves verified. (a) `ContractRegistry+Milestone1.swift:248` contained the phrasing verbatim — sweep of the repo found no other command summary naming a nonexistent verb. (b) The search weakness reproduces beyond "create team": `HelpService.search("create a team")` / `"make a custom team"` / `"new team"` / `"customize a team"` / `"build a team")` all topped out at `team_run_loop` ("Running a Team") instead of `teams_and_workers` (which teaches `teams duplicate`/`teams new`) — `team_run_loop`'s title/summary/related-commands are saturated with the bare word "team", outscoring `teams_and_workers`' plural-only id/title/commands on every tie. | CONFIRMED on both halves. Fixed — see ADP-S04. |

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
| **ADP-S04 — Team-authoring findability + false-affordance sweep** | **Done 2026-07-21.** Findability: `HelpTopicRegistry.swift` `teams_and_workers` topic gained 7 task-verb aliases ("create a team", "make a team", "make a custom team", "new team", "customize a team", "build a team", "build a custom team"). Root cause was ranking, not absence — the phrase already scored non-trivially on `teams_and_workers` but always lost the tie to `team_run_loop`, whose title ("Running a Team")/summary/related-command-names are saturated with the bare singular "team" token; the new aliases both add exact-phrase alias hits (`+10` in `HelpService.search`'s scorer) and new alias-token overlap, flipping every query in the ledger to `teams_and_workers`. False affordance: `ContractRegistry+Milestone1.swift:248` `teams new` summary — "Not an alias for teams create" (no such command) — replaced with "To copy a shipped team instead, use teams duplicate." (truthful, names a real command). Repo sweep for other instances of a nonexistent named verb found none (`AllnighterCLI.swift`'s "No `teams create` alias" is a source comment, not caller-facing; the phrase also appears in the archived `Alln_Sharpening.md` record and this SSOT's own claim ledger describing the bug — left untouched, neither is live disclosure). `RetiredVocabulary.denyTerms` gained `"not an alias for"` so the pattern can never silently return; `RetiredVocabularyTests.testNoFalseAffordancePhraseInCommandSummaries` sweeps every `CommandSpec` summary/arg/flag summary for it directly (not via the full deny-list sweep — several other deny-terms, e.g. `"dryrun"`, are legitimate substrings of real schema type names like `RunDryRunJSON` in these summaries and would false-positive under `proseContainsDenyTerm`'s prose-oriented matcher). Regenerated `docs/generated/alln/*` via `alln dev export-contracts` (hash lock refreshed for the `teams new` summary change; `contractVersion` stays 3.0.0 per law — `alln dev export-contracts --check` green). Gate: `HelpTopicRegistryTests.testSearchRoutesTeamAuthoringQueries` (new) + `RetiredVocabularyTests.testNoFalseAffordancePhraseInCommandSummaries` (new). Filter: `swift test … --filter 'TeamCatalog|HelpDiscovery|HelpSearch|MenuSearch|HelpProjector|ContractRegistry|VersionIdentity|TypedRef|Docs|HelpTopicRegistry|RetiredVocabulary|TeamsNew|ContractExport|ContractLock'` (101 passed, 1 skipped [regenerate-guarded, opt-in only]). |
| **ADP-S05 — Version identity: single source + bump rule** | **Done 2026-07-21.** Added `AllnighterVersionIdentity.binaryVersion` (`VersionJSON.swift`, AllnighterCore — same file as the `VersionJSON` contract it feeds) as the one definition, bumped to **"0.9.1"**. `AllnighterCLI.binaryVersion` (`AllnighterCLI.swift:316`) and the Codex `clientInfo` handshake (`CodexMessage.swift:16`, `Codex.initialize(id:)`) both now project it instead of carrying their own `"0.9.0"` literal. Drift gate: `VersionIdentityTests.swift` (new, `Tests/AllnighterEngineTests` — same location/pattern as `PortabilityHygieneTests` since it needs `@testable import AllnighterCLI`) — asserts `AllnighterCLI.binaryVersion == AllnighterVersionIdentity.binaryVersion` (single-source), the Codex handshake JSON literally contains the constant's value and not `"0.9.0"`, the constant is pinned at `"0.9.1"`, and a tree-scan (mirroring `PortabilityHygieneTests`' `#filePath`-relative walk) over `AllnighterCore`/`AllnighterEngine`/`AllnighterCLI` sources finds no other quoted `"0.9.0"` literal (matches on the exact quoted form so it does not false-positive on `VersionTests.swift`'s unrelated `"0.9.0-test"` fixture literal, which is a Codable-shape test value, not a real version and left untouched). `alln dev export-contracts --check` confirms `contractVersion` untouched (registry text unchanged by this slice, no hash to refresh). `alln version --json` on a fresh build reports `binaryVersion: "0.9.1"`, `contractVersion: "3.0.0"`. Gate: `swift test … --filter 'VersionIdentity'` (4 passed); broader `Version|CodexMessage|CodexSession|ContractSchema` sweep also green (46 passed) confirming no regression. |

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
