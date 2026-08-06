# Agent Teaching Surface

Status: **Open — BS slices implementation-ready; DEL slices proposed.**
Priority: **Sequenced below [`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md).**
That packet's VSI-S01/S02 land first: teaching a caller agent to delegate is
worth less than nothing while the bench misreports why a delegation failed.
Owner: unassigned (AllnighterCore `TeachingSnippet` + `HelpTopicRegistry`)
Created: 2026-08-06
Origin: Founder caught the lead using `pair relay` / `pair pilot` — vocabulary
retired in favour of `alln loop`. The same dead nouns were then found shipping
from `alln bootstrap` itself, inside a hash-verified teaching block, and pinned
in place by a test (`TeachingSnippetTests.swift:35`). Founder ruling: *"we have
to fix or kill bootstrap. It has drift and will have drift again unless we fix
it."*

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## 1. Founder intake

Intake per `docs/workflows/SSOT_Founder_Input_Workflow.md`.

- **Intent.** Stop the agent-teaching surface from rotting; then give the
  caller agent the one skill it has never had — how to delegate and verify,
  not just which command to type.
- **Value.** The teaching block is the most widely distributed string ALLN
  ships: pasted permanently into every host's context file. When it is wrong,
  it is wrong in every repo, for every agent, until each host is re-pasted —
  and it is the surface with the weakest truth gate in the product.
- **Trusted workflow.** `alln bootstrap` → paste → agent reads live `alln
  menu` → agent delegates with `alln run` / `alln loop start`.
- **Current state.** 2 of the 11 teaching rules (rules 6 and 9) teach retired
  relay/pilot nouns. See §2.
- **Truth owners.** `TeachingSnippet.swift` (block body + hash),
  `HelpTopicRegistry.swift` (narrative topics), `RetiredVocabulary.swift`
  (deny lists), `LoopPrompts.swift` (spawned PM prompt).
- **CLI surface.** `alln bootstrap` (narrowed body), `alln help get
  delegation` (new topic), `alln loop start --pm <agent-id>` (injected).
- **Proof.** §7 — every slice lands with a gate shown to fail by mutation.
- **Blocking question.** §9 — one, on the width of the noun deny-list.
- **Next slice.** BS-S01.

## 2. The drift is structural, not editorial

Fixing the two bad lines is a ten-minute edit that changes nothing. They
survived because of a seam between gates, and the seam is still open.

### 2.1 What is actually wrong today

`TeachingSnippet.swift:26–38` holds eleven hand-authored rules. Two are dead:

| Rule | Text (verbatim) | Status |
| --- | --- | --- |
| 6 | "Relay running ≠ dev running — check devRunId." | relay/pilot retired → `alln loop` |
| 9 | "Pilot/relay dev report is `pmTurn.report` (not `devLeg` — that is settle/liveness only)." | relay/pilot retired → `alln loop` |

The verbs are retired at the contract: `ContractRegistry+Milestone1.swift:733–851`
still lists `pair relay` through `pair pilot adopt` as ten command rows whose
summaries begin **"Retired — use `alln loop …` instead."**, and
`PairCLI.swift:252` answers any live invocation with *"is retired — use …
instead."* The teaching block teaches the retired nouns anyway.

The same block — all eleven rules, markers, and hash — is duplicated verbatim
into **all seven** shipped recipes (`Resources/Recipes/*.md`; open marker at
line 13 in every file, rule 9 at line 22, hash `ef3cbd5b…`), under a header
that literally says "keep in sync with TeachingSnippet". One truth, eight
copies.

Separately, live help prose at `HelpTopicRegistry.swift:222` instructs with
`pilot status` / `relay-status` — retired command forms, in a topic body.

### 2.2 Root cause A — the block falls in the seam between gates

| Gate | Where | Corpus | Sees `TeachingSnippet`? |
| --- | --- | --- | --- |
| `testNoRetiredVocabularyInHelpTopicProse` | `RetiredVocabularyTests.swift:86` | `HelpTopicRegistry.topics` prose (title/summary/body/sections; `aliases` not scanned) | **No** — different type |
| `testEveryBacktickedAllnCommandInTopicProseResolves` | `RetiredVocabularyTests.swift:196` | `HelpTopicRegistry.topics` prose | **No** — different type |
| Living-doc deny grep | `scripts/check-fast.sh:55–95` | selected `.md`: docs/operations, docs/phases, docs/workflows, AGENTS.md, `CLI_Product_Spine.md`, one archived contract, Recipes | **No** — the block is `.swift` |
| Bootstrap stdout spot-check | `scripts/menu_not_router_eval.py`, `bootstrap_checks()` | `alln bootstrap` stdout, three literal substrings (`team hello`, `route --for`, `resolve --for`) | Partial — three hard-coded strings, not the deny list |

The Swift gates scan help topics; the shell gate scans markdown; the eval
checks three strings. The teaching body is Swift and not a help topic, so it
is in no deny-list corpus. The most-distributed agent-facing string in the
product is the one string no deny-list gate checks.

This is the failure that workflow already documents —
`SSOT_Founder_Input_Workflow.md` §"Why the teaching layer needs its own gate":
*"Version sync and teaching sync are separate machines, and only the first was
ever gated."* ASF closed that hole for `HelpTopicRegistry` and left
`TeachingSnippet` outside it.

### 2.3 Root cause B — the integrity machine authenticates provenance, not truth

`TeachingSnippet` has a strong integrity design: `schemaVersion = 8`
(`TeachingSnippet.swift:16`), a SHA256 of the canonical body, and five parse
states (`absent`, `installed`, `stale`, `modified`, `malformed`). Every one
of those answers *"does this paste match the source?"* **None answers "does
the source match the CLI?"** The hash over rule 9 is perfectly valid; every
host file reports `installed`; the content is false. A hash cannot detect
drift in the thing being hashed — that is a missing second gate, not a bug in
the hash.

### 2.4 Root cause C — the gate that exists is inverted

`TeachingSnippetTests.swift:35`:

```swift
XCTAssertTrue(TeachingSnippet.body.contains("Relay running"))
```

The block is gated **in the wrong direction**: a test asserts retired
vocabulary must be present. That file carries twenty-one positive
content-pinning assertions (nineteen `body.contains`, two
`reflexLines.contains`) plus eight negative ones. Anyone fixing rule 6 turns
the test red and is told their fix broke the build. Content-pinning
assertions of the form `body.contains("<prose>")` freeze whatever is there,
correct or not — the mechanism by which drift acquires a defender.

### 2.5 The invariant was already written, then violated seven times

`TeachingSnippet.swift:24`:

> *"Protocol only — never embed models, teams, recipes, or command rows."*

Seven of the eleven rules name a command, flag, or JSON field (rules 1, 5, 7,
8, 9, 10, 11). The rule was authored, nothing enforced it, and drift ate it.
**Every unenforced invariant in this file has already failed.** Note rule 1
is among the seven — it survives the ruling (§3) only as the live-surface
pointer, which is why the executable gate in §4 needs exactly one named
allow-path.

## 3. Fix or kill — the ruling

**Kill case.** The block is a paste, and rule 4 says *"never trust a pasted
catalog."* Retrieval (`alln help get`) cannot rot, is versioned with the
binary, and is already gated (both Swift gates of §2.2). Deleting the block
removes an entire drift surface and seven of the eight duplicate truths.

**Fix case.** The paste is the only channel that works *before* the agent
knows `alln` exists — `alln help get delegation` requires already knowing to
call `alln help`. Cold start has its own packet (`One_Paste_Cold_Start.md`);
kill bootstrap and there is no front door.

**Ruling: narrow it.** Keep only what must be true *before the first command*
and cannot rot; everything that names a command, a flag, or a JSON field moves
to a help topic, where the ASF gate already covers it.

> **The paste carries protocol. Retrieval carries grammar.**

| Rule | Content | Verdict |
| --- | --- | --- |
| 1 | read `alln menu --json` first | **Keep** — live-surface pointer; the single §4 allow-path |
| 2 | choose from `useWhen`/`dontUseWhen`, canonical ids | **Keep** — protocol |
| 3 | run the validation template first | **Keep** — protocol |
| 4 | re-read the live menu; never trust a pasted catalog | **Keep** — protocol |
| 5 | `--no-wait`, `nextAction.command`, `alln show --stream` | Move → `team_run_loop` (already there: sections `no-wait`, `delivery`) |
| 6 | "Relay running ≠ dev running", devRunId | **Rotted.** Move → `loop` (content not there yet — add it) |
| 7 | `--read-only` vs `--no-commit` | Move → `team_run_loop` (already there: section `read-only`) |
| 8 | one mutator; queue ticket; `observation` | Move → `results_and_history` (not there yet — add it) |
| 9 | "Pilot/relay", `pmTurn.report`, `devLeg` | **Rotted.** Move → `loop` (not there yet — add it) |
| 10 | `artifact.path` / `artifact.openCommand` | Move → `artifact` (not there yet — add it) |
| 11 | print `alln capacity` verbatim | Move → `capacity` (already there: "Agent print contract") |

Eleven rules become four. The survivors teach retrieval only; rule 1's
`alln menu --json` is the one command line that stays, carried as the named
allow-path. This is a **narrowing, not a deletion**: every moved rule lands in
a gated topic agents already retrieve.

## 4. What makes this stay fixed

Three mechanical properties, in priority order. Each is deterministic — no
agent judgment, per the Project Law preferring deterministic checks.

1. **The corpus must include the teaching block.** Extend the gates of §2.2
   to `TeachingSnippet.reflexLines` — not new policy. The deny list already
   contains `pair pilot` and `pair relay`; it simply never scanned this
   string.
2. **The stated invariant must be executable.** A line of `reflexLines` may
   not contain a backticked span that (a) contains a `--` flag, (b) matches a
   dotted identifier (`a.b…`), or (c) contains a `<placeholder>`. Exactly one
   named allow-path — rule 1's `alln menu --json` — lives in one commented
   constant, the same mechanism §9 prescribes for aliases. At HEAD this fails
   on rules 5, 7, 8, 9, 10, 11 (rule 1 sits in the allow-path; rule 6 carries
   no backticked grammar and is only reachable via §9 bare nouns). This is
   exactly `TeachingSnippet.swift:24` made real.
3. **No content-pinning assertions.** Positive `body.contains("<prose>")` is
   banned in `TeachingSnippetTests`; structural assertions only (count, hash
   round-trip, marker grammar, property-2 conformance). The existing negative
   `contains` assertions are deny-gates, not truth pins — keep them.

Property 2 is what makes the founder's *"will have drift again"* false: a
narrowed block has nothing in it a CLI change can invalidate, and the gate
refuses to let anything rottable back in.

## 5. Slices — bootstrap (BS)

**BS-S01 — Make the invariant executable. Land the gate red, before the
content fix.**
- In `RetiredVocabularyTests.swift`, beside
  `testNoRetiredVocabularyInHelpTopicProse` (:86), add a test scanning every
  `TeachingSnippet.reflexLines` line with
  `RetiredVocabulary.proseContainsDenyTerm`.
- Add the §4 property-2 regex test over `reflexLines`, with the named
  allow-path.
- Add `TeachingSnippet.swift` to the `scripts/check-fast.sh:71–95` scan list.
- Proof: at HEAD the regex test is red naming rules 5, 7, 8, 9, 10, 11. The
  deny-corpus test is green at HEAD — no current deny term matches the body;
  the bare nouns needed to catch rules 6/9 are §9 Q1.

**BS-S02 — Narrow the block to four rules; bump to v9.**
- Delete rules 5–11 from `reflexLines` (`TeachingSnippet.swift:26–38`); land
  their content in the §3 topics, adding text only where §3 says "not there
  yet".
- Add the delegation pointer line (this absorbs DEL-S02): *"Before delegating
  a build slice, read `alln help get delegation`."* It passes §4 property 2
  with no allow-path (no flag, no dotted path, no placeholder).
- Bump `schemaVersion` to 9 (`TeachingSnippet.swift:16`) so every v8 host
  file parses as `stale` (`parse()` version check) and stops reporting a
  false `installed`. Update the test's count pin from 11 to 5 (four rules +
  pointer) and its version pin from 8 to 9.
- Replace the twenty-one positive content-pinning assertions in
  `TeachingSnippetTests.swift` with structural ones (count, hash round-trip,
  marker grammar, property-2 conformance); keep the eight negative pins.
- Proof: BS-S01's gate goes green by content change alone, never by narrowing
  the gate.

**BS-S03 — Kill the duplicates.**
- Replace the inlined block (lines 13–25) in **all seven**
  `Resources/Recipes/*.md` with a pointer (e.g. `alln bootstrap` /
  `alln help get recipes --format md`).
- Fix `HelpTopicRegistry.swift:222`'s `pilot status` / `relay-status` prose
  to `alln loop status`. The `pilot status` alias at :201 stays — aliases are
  discoverability (§9).
- Gate: a `scripts/check-fast.sh` step asserting `ALLNIGHTER:TEACHING` occurs
  in zero files under `Resources/Recipes/` — the single source is then
  `TeachingSnippet.swift`.
- Proof: re-inline the body into any recipe → red.

**BS-S04 — Repair the routing that started this.**
- Rewrite the retired nouns in `AGENTS.md`'s First Routing rows at lines
  96–99 and 128–129 (`pair pilot status`, `pair relay` / `relay-resume` /
  `relay adopt`, `pilot watch`) to `alln loop` grammar.
- Gate: bare-form patterns (`pair relay`, `pair pilot`, `relay adopt`)
  checked against **AGENTS.md only**. Do NOT append them to
  `livingDocDenyPatterns` unscoped: that list scans `docs/phases/*.md`, which
  carries migration-teaching docs that legitimately contain these strings
  (this packet; `Work_Recovery_And_PM_Continuity.md:128`;
  `sprint/hygiene/HY-S04`–`HY-S07`).
- Proof: re-add a `pair relay` routing row to `AGENTS.md` → red.

## 6. Then: the delegation gap (DEL)

Bootstrap is the *channel*. This is what the channel has never carried.

### 6.1 The gap, verified

`SkillCatalog.builtIns` (`SkillCatalog.swift:61`) ships skills for every seat
family — build, design, design-panel, copy, signal, writer. **Not one skill
id contains `lead`, `pm`, or `synth`.** There is a lead layer —
`SkillCatalog.leadCallEnvelope` (`SkillCatalog.swift:388`) — but read what it
governs: *"Your visible product is a one-page decision memo… Status must be
exactly Ready or Partial."* That is an **output contract for the Lead who
summarises a finished run.** It says nothing about how to delegate.

The omission was deliberate. `LoopPrompts.swift:5–6`:

> *"The prompt teaches loop mechanics only — batching, gating, and review
> depth are the PM's judgment call (§3), never prescribed here."*

The dev prompt (`LoopPrompts.swift:171–172`) is *"Deliberately thin… the
PM's handover, passed through untouched."* The brief is the single
uninstrumented input in the loop, by design.

### 6.2 Why that ruling should be revisited

`Scarcity_Aware_Routing.md` §5a (2026-08-06 tally) recorded **13 delegated
build slices** across seven seats (ranks 55–90, plus Sonnet 5): 9 landed
clean, 4 needed intervention. Sorting the day's slices by brief shape ("all
14 slices"):

| Brief shape | Result |
| --- | --- |
| Fix this named defect, here is the property it must satisfy | **9 / 9 clean** — including rank-55 and rank-65 seats |
| Build this new capability | **1 / 5 clean** |

Seat strength predicted nothing; the cheapest seat on the bench produced the
drift gates. *"Every single failure was caught by re-running the gate,
mutation-testing, or grepping for the symbol under test. Not one was caught
by the delivering seat's own report"*, and in three of the four cases that
report said the work was complete and green.

"The PM's judgment call" is precisely where every failure happened. Gating is
not a matter of taste; it is the component that makes delegation work at all.

### 6.3 Two consumers, two delivery paths, one SSOT

ALLN composes the prompt of every *seat*, and never composes the prompt of
the *caller*.

| Consumer | Does ALLN own the prompt? | Delivery |
| --- | --- | --- |
| Spawned PM (`loop start --pm <agent-id>`) | Yes | Injected via `LoopPrompts` |
| Caller-held PM seat (`loop start --pm caller`) and plain one-shot `alln run` delegation | **No** | Retrieved via `alln help get delegation` |

Content lives once. This mirrors the Ikiro pattern the founder cited — a thin
adapter pointing at a tool-neutral SSOT — except `bootstrap` already *is* the
adapter.

### 6.4 Slices — delegation (DEL)

**DEL-S01 — `alln help get delegation`.** New `HelpTopicRegistry` topic
carrying the seven rules the tally supports: route by brief shape not seat
strength; a net-new brief must name the failing state that must become
passing before any code is written; state the required property, not the
field to add; the commit is the completion signal, never the seat's report;
re-run the gate yourself; grep that the test references the symbol under
test; the lead is not exempt. (An original eighth rule — "one symbol per
commit" — is not in the tally and was dropped; see Reviewer dissent.)
Aliases: *brief, work order, send to a seat, how to review a seat's work, dev
turn, delegate*. Note `delegate` is already a `team_run_loop` alias
(`HelpTopicRegistry.swift:199`); the alias map resolves in topic-array order
(`HelpTopicRegistry.swift:698`), so place `delegation` after `team_run_loop`.
Miss recovery is the existing H0a behavior (closeMatches + full sitemap +
search nextToolPlan) — assert it non-empty. Gate: `HelpService.get(topic:
"delegation").found` is true and each alias resolves via
`HelpTopicRegistry.canonicalTopicId`; deleting the topic turns both red.
**Not** `alln help search`: that path is `MenuCatalog.search` over menu cards
(`HelpCLI.swift:28` → `HelpProjector.search`) and never sees help topics.

An eighth rule, earned the expensive way while producing this packet's own v2:
**never ask one seat to both verify and rewrite.** The v2 brief was correctly
*shaped* — it stated acceptance properties, not fields — and still cost ~4% of
a weekly quota, because it mandated reading ~4,300 lines across ten files
(including `SkillCatalog.swift` at 1,561 lines, where one grep was needed).
Verification is grep-shaped: N discrete claims, each a two-line match.
Rewriting is context-shaped. Fused, the whole verification corpus enters the
rewrite's context and is re-sent every turn. **Brief shape and brief context
budget are independent axes**, and a well-shaped brief can still bankrupt a
window. Split the jobs and both are small.

**DEL-S02 — merged into BS-S02** (the one pointer line, same v9 bump). The
number is kept only for traceability.

**DEL-S03 — Inject for the spawned PM.** `RelayPMPrompt.assemble` carries the
same rules for `--pm <agent-id>`. This reverses the `LoopPrompts.swift:5–6`
ruling explicitly, in a comment citing this packet and the §5a tally. Gate: a
test asserting `RelayPMPrompt.assemble` output contains the anchor rule;
removing it from `LoopPrompts` turns the test red.

DEL-S01 is independently testable the cheap way: if the next fortnight's
delegated slices stop needing the same four interventions, DEL-S03 earns
itself. If nothing changes, DEL dies at S01 having cost one help topic.

### 6.5 Third layer, out of scope here

Project-local delegation facts (`which seat may mutate this repo`, vendors
banned here, the review seat must not be the authoring seat) are owner-
authored truth ALLN cannot observe. Recorded so the layering is legible; not
proposed. See `Scarcity_Aware_Routing.md` for why model-quality routing
tables are not the answer and this is.

## 7. Proof scenarios

| Slice | Gate | Mutation that must turn it red |
| --- | --- | --- |
| BS-S01 | §4 property-2 regex test + deny-corpus test over `reflexLines`; `TeachingSnippet.swift` in the check-fast scan | Re-add `--no-commit` to `reflexLines` → regex red. Re-adding bare `Pilot/relay` prose goes red **only after §9 Q1** bare nouns land — until then that half is unproven |
| BS-S02 | v9 schema bump | Feed a v8 block to `TeachingSnippet.parse` → must be `.stale`; `.installed` means the bump is missing |
| BS-S03 | check-fast step: zero `ALLNIGHTER:TEACHING` markers under `Resources/Recipes/` | Re-inline the block into any recipe |
| BS-S04 | AGENTS.md-scoped bare-form patterns | Re-add a `pair relay` routing row to `AGENTS.md` |
| DEL-S01 | `help get delegation` resolves; aliases resolve via `canonicalTopicId`; miss recovery non-empty | Delete the topic → get misses and the alias map drops it. (`help search` is not a valid gate — it reads menu cards, not topics) |
| DEL-S03 | Test: `RelayPMPrompt.assemble` contains the anchor rule | Remove it from `LoopPrompts` |

No slice closes on a gate that has not been shown to fail. Per
`docs/operations/Spec_Review.md` §3 Measurement: *"A check that cannot be
made to fail is decoration"* — and this packet exists because of a check that
was pointed the wrong way.

## 8. Inference bans

| Junction | Ban |
| --- | --- |
| Hash is valid → content is true | The hash proves the paste matches the source; only a corpus gate proves the source matches the CLI (§2.3) |
| Block is gated → block is safe | `body.contains("<prose>")` freezes content; the wrong-direction gate reads as coverage (§2.4) |
| Rules are useful → keep them in the paste | Useful and rottable both true → it belongs in a help topic (§3) |
| Retired noun removed from deny list → CI green | Deny lists append forever (`RetiredVocabulary.swift:8`) — never narrow a red gate |
| Delegation rules exist → seats will follow them | The gate the lead re-runs is the proof; the seat's report never is (§6.2) |
| DEL ships → route-down is safe | 13 slices, one subsystem, one lead judging its own briefs (§5a caveat) |

## 9. Open questions

1. **How wide is the noun deny-list?** Catching rules 6/9 needs the bare
   nouns `relay` and `pilot`, not just the command forms already listed. But
   `HelpTopicRegistry.swift:271–272` legitimately keeps `pair relay` /
   `pilot` as **search aliases** so an agent typing the old word finds the
   `loop` topic — that is discoverability (the Swift prose gate already does
   not scan `aliases`). **Recommendation:** deny the bare nouns in
   instructional prose fields only (titles, summaries, bodies, teaching
   lines); exempt `aliases` explicitly in one named allow-path with a
   comment. Do not deny the noun globally, and do not add the bare forms to
   `livingDocDenyPatterns` unscoped — that corpus includes migration-teaching
   docs that must keep naming the old words (BS-S04).
2. **Does BS-S02's v9 bump strand host files?** Every v8 paste becomes
   `stale` and needs re-pasting. That is correct behaviour — they contain
   false rules — but it is user-visible. **Recommendation:** ship it;
   `stale` is exactly the state the machine was built to express, and a
   false `installed` is worse.

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| `alln bootstrap` content, teaching block, host paste going stale | This packet §2–§5; code SSOT `TeachingSnippet.swift` |
| Retired vocabulary in help, docs, or the teaching block | `RetiredVocabulary.swift` + `check-fast.sh:55` — never narrow a red gate |
| How to brief a delegated seat / verify what comes back | `alln help get delegation` (after DEL-S01); evidence in `Scarcity_Aware_Routing.md` §5a |
| Spawned PM prompt content | `LoopPrompts.swift` — see §6.1 before assuming it is deliberate |

## Reviewer dissent

Corrections made against source, disclosed rather than silent:

- **"One symbol per commit" dropped from DEL-S01.** Presented as a rule the
  tally supports; `Scarcity_Aware_Routing.md` contains no such finding.
- **The original §4 regex was ungateable.** Banning any backticked token
  matching "`alln `" flags the kept rule 1 (`alln menu --json`) and the
  DEL-S02 pointer line — BS-S02 could never have gone green "by content
  change alone". Replaced with span-level bans plus one named allow-path.
- **BS-S03 scope was wider than written.** Two recipes were named; all seven
  ship the block.
- **The DEL-S01 gate as written cannot see the topic.** `alln help search`
  projects menu cards (`MenuCatalog.search`), not help topics, so "delete the
  topic" would never turn it red. Gate moved to `help get` + alias
  resolution.
- **BS-S01 proof overclaimed.** At HEAD the deny corpus catches nothing in
  the body (the bare nouns are §9 Q1); only the regex is red, on rules 5, 7,
  8, 9, 10, 11.
