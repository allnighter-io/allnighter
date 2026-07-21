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
| 3 | Empty `name` fields in `teams --json` | To verify at fix time against the current binary; catalog projection owned by `runTeamCatalog` / menu-teams projections. | TO VERIFY → fix if confirmed, else record no-fix ruling here. |
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
| **ADP-S01 — Reproduce round-trips every explicit selector** | **Work order.** `TeamRun.explicitWorkerIds` persists the caller's `--worker` selectors at acceptance (optional; legacy `run.json` decodes nil). Both builders (`RunCLI.reproduceCommand`, legacy `AllnighterCLI.reproduceCommand`) emit `--worker <id>` per selector, `--lane` when explicit (incl. `laneContextOnly`), `--no-commit` when ordered, and the prompt. Gate: round-trip test — resolve a reproduceCommand's argv through the run resolver and assert the resolved seats/policy equal the original run's (`ReproduceCommand` filter). |
| **ADP-S02 — Dry-run teaches the read-only path at the decision point** | **Work order.** When a dry-run resolves `writePolicy` mutating-allowed AND the invocation is a bare prompt ask (no `--team`), `warnings` gains one sentence naming the mechanical read-only alternative and `alternatives` (additive optional teaching field, same `argvTemplate` shape as `nextAction`) carries a ready answer-team invocation with the caller's selectors preserved. No behavior/routing change (SH-S05 intact). Gate: explicit-worker dry-run fixture shows the steer; answer-team dry-run does not; `RunDryRun` filter green. |
| **ADP-S03 — teams list discloses names** | **Work order.** First verify the claim against source/binary and record mechanism + verdict in the ledger (row 3); if confirmed, fix at the projection so `teams --json` / menu teams rows always carry the human display name next to the canonical id (disclosure for caller-side resolution; dispatch stays canonical-ids-only). Gate: catalog projection test asserts non-empty `name` for every catalog row (`TeamCatalog` filter green). |
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
