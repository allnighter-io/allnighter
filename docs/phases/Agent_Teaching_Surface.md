# Agent Teaching Surface

Status: **Open — BS slices implementation-ready; DEL slices proposed.**
Owner: unassigned (AllnighterCore `TeachingSnippet` + `HelpTopicRegistry`)
Created: 2026-08-06
Origin: Founder caught the lead using `pair relay` / `pair pilot` — vocabulary
retired in favour of `alln loop`. The same dead words were then found **shipping
from `alln bootstrap` itself**, inside a hash-verified teaching block, and
pinned in place by a test. Founder ruling: *"we have to fix or kill bootstrap.
It has drift and will have drift again unless we fix it."*

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## 1. Founder intake

Per `docs/workflows/SSOT_Founder_Input_Workflow.md` §Default Output.

```text
Founder intent:      Stop the agent-teaching surface from rotting, then give the
                     caller agent the one skill it has never had — how to
                     delegate and verify, not just which command to type.

Product value:       The teaching block is the most widely distributed string
                     ALLN ships: it is pasted permanently into every host's
                     context file. When it is wrong, it is wrong in every repo,
                     for every agent, until each host is re-pasted. It is also
                     the surface with the weakest truth gate in the product.

Trusted workflow:    `alln bootstrap` → paste → agent reads live `alln menu`
                     → agent delegates with `alln run` / `alln loop start`.

Current state:       2 of 11 teaching rules name retired product nouns. See §2.

Truth owner:         `TeachingSnippet.swift` (block body + hash),
                     `HelpTopicRegistry.swift` (narrative topics),
                     `RetiredVocabulary.swift` (deny lists),
                     `LoopPrompts.swift` (spawned PM prompt).

CLI surface:         `alln bootstrap` (narrowed body), `alln help get delegation`
                     (new topic), `alln loop start --pm <agent-id>` (injected).

Help surface:        §5 BS-S02 and §6 DEL-S01 name topics, search terms, and
                     empty-search recovery.

Proof scenario:      §7 — every slice lands with a gate that goes red when the
                     defect returns, verified by mutation.

Blocking questions:  §9 — one, on the width of the noun deny-list.

Next slice:          BS-S01.
```

## 2. The drift is structural, not editorial

Fixing the two bad lines is a ten-minute edit that changes nothing. The reason
they survived is a seam between two gates, and the seam is still open.

### 2.1 What is actually wrong today

`TeachingSnippet.swift:26–38` holds eleven hand-authored rules. Two are dead:

| Rule | Text | Status |
| --- | --- | --- |
| 6 | "**Relay** running ≠ dev running — check `devRunId`." | `pair relay` retired → `alln loop` |
| 9 | "**Pilot/relay** dev report is `pmTurn.report`…" | `pair pilot` retired → `alln loop` |

`alln --help` prints every `pair pilot` / `pair relay` row as **"Retired — use
`alln loop …` instead."** The teaching block teaches the retired noun anyway.

The same eleven lines are duplicated verbatim into shipped resources —
`Resources/Recipes/get-another-model-to-implement-this.md:22` and
`ask-several-models-and-compare.md:22` both carry rule 9. Three copies of one
truth.

Separately, live help prose at `HelpTopicRegistry.swift:222` instructs with
`pilot status` / `relay-status` — retired commands, in a topic body.

### 2.2 Root cause A — the block falls in the seam between two gates

ALLN has two retired-vocabulary gates. Both are good. Neither can see the
teaching block.

| Gate | Where | Corpus | Sees `TeachingSnippet`? |
| --- | --- | --- | --- |
| `testNoRetiredVocabularyInHelpTopicProse` | `RetiredVocabularyTests.swift:86` | `HelpTopicRegistry.topics` | **No** — different type |
| `testEveryBacktickedAllnCommandInTopicProseResolves` | `RetiredVocabularyTests.swift:196` | `HelpTopicRegistry.topics` | **No** — different type |
| Living-doc deny grep | `scripts/check-fast.sh:55–95` | `*.md` under docs/, AGENTS.md, Recipes | **No** — it is `.swift` |

The Swift gates scan help topics. The shell gate scans markdown. The teaching
body is Swift and is not a help topic, so it is in the corpus of neither. It is
the single most-distributed agent-facing string in the product and it is the one
string nothing checks.

This is the exact failure this workflow already documents —
`SSOT_Founder_Input_Workflow.md` §"Why the teaching layer needs its own gate":
*"Version sync and teaching sync are separate machines, and only the first was
ever gated."* ASF closed that hole for `HelpTopicRegistry` and left
`TeachingSnippet` outside it.

### 2.3 Root cause B — the integrity machine authenticates provenance, not truth

`TeachingSnippet` has a genuinely strong integrity design: `schemaVersion = 8`, a
SHA256 of the canonical body, and five parse states (`absent`, `installed`,
`stale`, `modified`, `malformed`) so a hand-edited or outdated host file is
detectable.

Every one of those mechanisms answers *"does this paste match the source?"*
**None answers "does the source match the CLI?"** The hash over rule 9 is
perfectly valid. Every host file reports `installed`. The content is false.

A hash cannot detect drift in the thing being hashed. That is not a bug in the
hash — it is a missing second gate.

### 2.4 Root cause C — the gate that exists is inverted

`TeachingSnippetTests.swift:35`:

```swift
XCTAssertTrue(TeachingSnippet.body.contains("Relay running"))
```

The teaching block is not merely ungated. It is gated **in the wrong
direction**: a test asserts the retired vocabulary must be present. Anyone
fixing rule 6 turns that test red and is told their fix broke the build.

This is a repeat of the ASF root cause — an inverted test gate frozen on dead
vocabulary — in a different file of the same product. Content-pinning assertions
of the form `body.contains("<prose>")` freeze whatever is there, correct or not.
They are the mechanism by which drift acquires a defender.

### 2.5 The invariant was already written, then violated seven times

`TeachingSnippet.swift:24`:

> *"Protocol only — never embed models, teams, recipes, or command rows."*

Seven of the eleven rules name a command, flag, or JSON field. The rule was
authored, nothing enforced it, and drift ate it. **Every unenforced invariant in
this file has already failed.** That is the strongest available argument for
making this one executable rather than restating it.

## 3. Fix or kill — the ruling

Both cases are real. Take neither.

**Kill case.** The block is a paste, and rule 4 of the block says *"never trust
a pasted catalog."* It is a pasted catalog instructing agents not to trust
pasted catalogs. Retrieval (`alln help get`) cannot rot, is versioned with the
binary, and is already gated. Deleting the block removes an entire drift surface
and one of three duplicate truths.

**Fix case.** The paste is the only channel that works *before* the agent knows
`alln` exists. `alln help get delegation` requires already knowing to call
`alln help`. Cold start is a real problem with its own packet
(`One_Paste_Cold_Start.md`). Kill bootstrap and there is no front door.

**Ruling: narrow it.** The block keeps only what must be true *before the first
command* and what cannot rot. Everything that names a command, a flag, or a JSON
field moves to a help topic, where the ASF gate already covers it.

> **The paste carries protocol. Retrieval carries grammar.**

Applying that test to the eleven rules:

| Rule | Content | Verdict |
| --- | --- | --- |
| 1 | read `alln menu --json` first | **Keep** — points at a live surface |
| 2 | choose from `useWhen`/`dontUseWhen`, canonical ids | **Keep** — protocol |
| 3 | run the validation template first | **Keep** — protocol |
| 4 | re-read the live menu; never trust a pasted catalog | **Keep** — protocol |
| 5 | `--no-wait`, `nextAction.command`, `alln show --stream` | Move → `results_and_history` |
| 6 | "Relay running ≠ dev running", `devRunId` | **Rotted.** Move → `loop` |
| 7 | `--read-only` vs `--no-commit` | Move → `team_run_loop` |
| 8 | queue ticket, `observation`, `alln show --json` | Move → `results_and_history` |
| 9 | "Pilot/relay", `pmTurn.report`, `devLeg` | **Rotted.** Move → `loop` |
| 10 | `artifact.path` / `artifact.openCommand` | Move → `artifact` |
| 11 | print `alln capacity` verbatim | Move → `capacity` |

Eleven rules become four. The four survivors share one property: **they name no
output field and no flag, and they stay true no matter what the CLI does**,
because their whole content is *go read the live surface*. Rules 5–11 rot by
construction — they encode grammar into a string that is copied out of the
binary and never updated again.

Note this is a **narrowing, not a deletion**: nothing is lost, every moved rule
lands in a gated topic that agents already retrieve.

## 4. What makes this stay fixed

Three mechanical properties, in priority order. Each is deterministic — no agent
judgment, per the Project Law preferring deterministic checks.

1. **The corpus must include the teaching block.** One line changed in the gates
   of §2.2, not new policy. The deny list already contains `pair pilot` and
   `pair relay`; it simply never scanned this string.
2. **The stated invariant must be executable.** A teaching line may not contain
   a backticked token matching `alln `, a leading `--`, or a dotted JSON path.
   That is a regex, and it is exactly `TeachingSnippet.swift:24` made real. It
   fails today on seven lines, which is the point.
3. **No content-pinning assertions.** `body.contains("<prose>")` is banned in
   `TeachingSnippetTests`. Structural assertions only (count, hash round-trip,
   marker grammar, invariant-2 conformance).

Property 2 is what makes the founder's *"will have drift again"* false. A
narrowed block cannot rot because there is nothing in it that a CLI change can
invalidate — and the gate refuses to let anything rottable back in.

## 5. Slices — bootstrap (BS)

**BS-S01 — Make the invariant executable.** Add the no-grammar regex gate over
`TeachingSnippet.reflexLines`, and add `TeachingSnippet.body` to both
`RetiredVocabulary` corpora (Swift test + `check-fast.sh`). Land the gate
**before** the content fix, red. Proof: gate is red on `main` at HEAD, naming
rules 5–11 and the two retired nouns.

**BS-S02 — Narrow the block to four rules; bump to v9.** Delete rules 5–11 from
`reflexLines`; land their content in the help topics named in §3, each with
search aliases and non-empty recovery per
`SSOT_Founder_Input_Workflow.md` §Agent-facing help. Delete the content-pinning
assertions in `TeachingSnippetTests`. Bump `schemaVersion` to 9 so every
already-pasted v8 host file parses as `stale` and re-prompts. Proof: BS-S01 gate
goes green by content change alone, never by narrowing the gate.

**BS-S03 — Kill the duplicates.** The recipes must not restate the teaching
body. Replace the inlined eleven lines in `Resources/Recipes/*.md` with a
pointer. Fix `HelpTopicRegistry.swift:222`'s `pilot status` / `relay-status`
prose to `alln loop status`. Proof: one grep asserts the teaching body appears
in exactly one source location.

**BS-S04 — Repair the routing that started this.** `AGENTS.md` still routes
`pair relay` / `pair pilot` / `relay adopt` in five table rows. Replace with
`alln loop`. Proof: the living-doc gate covers `AGENTS.md` already — add the
bare nouns per §9 and it goes red first.

## 6. Then: the delegation gap (DEL)

Bootstrap is the *channel*. This is what the channel has never carried.

### 6.1 The gap, verified

`SkillCatalog.builtIns` ships skills for every seat family — build, design,
design-panel, copy, signal, writer. **Not one skill id contains `lead`, `pm`, or
`synth`.** There is a lead layer — `SkillCatalog.leadCallEnvelope:388` — but read
what it governs: *"Your visible product is a one-page decision memo… Status must
be exactly Ready or Partial."* That is an **output contract for the Lead who
summarises a finished run.** It says nothing about how to delegate.

And the omission was deliberate. `LoopPrompts.swift:5`:

> *"The prompt teaches loop mechanics only — batching, gating, and review depth
> are the PM's judgment call, never prescribed here."*

The dev prompt (`LoopPrompts.swift:171`) is *"deliberately thin… the PM's
handover, passed through untouched."* So the brief is the single uninstrumented
input in the entire loop, by design.

### 6.2 Why that ruling should be revisited

`Scarcity_Aware_Routing.md` §5a measured 14 delegated slices across seven seats.
9 landed clean; 4 needed intervention. Sorted by brief shape:

| Brief shape | Result |
| --- | --- |
| Fix this named defect, here is the property it must satisfy | **9 / 9 clean** — including rank-55 and rank-65 seats |
| Build this new capability | **1 / 5 clean** |

Seat strength predicted nothing; the cheapest seat on the bench produced the
drift gates. **Every one of the four failures was caught by re-running the gate,
mutation-testing, or grepping for the symbol under test — none by the delivering
seat's report**, and in three cases that report said complete and green.

"The PM's judgment call" is precisely where every failure happened. Gating is
not a matter of taste; it is the component that makes delegation work at all.

### 6.3 Two consumers, two delivery paths, one SSOT

This is why the PM skill was never a `SkillCatalog` entry: ALLN composes the
prompt of every *seat*, and never composes the prompt of the *caller*.

| Consumer | Does ALLN own the prompt? | Delivery |
| --- | --- | --- |
| Spawned PM (`loop start --pm <agent-id>`) | Yes | Injected via `LoopPrompts` |
| Caller PM (`--pm caller`, plain `alln run`) | **No** | Retrieved via `alln help get delegation` |

Content lives once. This mirrors the Ikiro pattern the founder cited — a thin
adapter (`bootstrap`) pointing at a tool-neutral SSOT (`help get`) — except
`bootstrap` already *is* the adapter.

### 6.4 Slices — delegation (DEL)

**DEL-S01 — `alln help get delegation`.** New `HelpTopicRegistry` topic carrying
the eight rules the tally supports: route by brief shape not seat strength; a
net-new brief must name the failing state that must become passing before any
code is written; state the required property, not the field to add; the commit
is the completion signal, never the seat's report; re-run the gate yourself;
grep that the test references the symbol under test; one symbol per commit; the
lead is not exempt. Aliases: *delegate, brief, work order, send to a seat, how
to review a seat's work, dev turn*. Recovery on miss → `loop`, `team_run_loop`.

**DEL-S02 — Point at it from the narrowed block.** One line, landing in the same
v9 bump as BS-S02: *"Before delegating a build slice, read `alln help get
delegation`."* Passes the §4 invariant — it names a retrieval surface, not
grammar.

**DEL-S03 — Inject for the spawned PM.** `LoopPrompts` carries the same rules
for `--pm <agent-id>`. Reverses the `LoopPrompts.swift:5` ruling explicitly, in
a comment citing this packet and the tally.

DEL-S01 is independently testable the cheap way: if the next fortnight's
delegated slices stop needing the same four interventions, S02 and S03 earn
themselves. If nothing changes, DEL dies at S01 having cost one help topic.

### 6.5 Third layer, out of scope here

Project-local delegation facts (`which seat may mutate this repo`, vendors
banned here, the review seat must not be the authoring seat) are owner-authored
truth ALLN cannot observe. Recorded so the layering is legible; not proposed.
See `Scarcity_Aware_Routing.md` for why model-quality routing tables are not the
answer and this is.

## 7. Proof scenarios

| Slice | Gate | Mutation that must turn it red |
| --- | --- | --- |
| BS-S01 | Teaching body in both deny corpora + no-grammar regex | Re-add `--no-commit` or `Pilot/relay` to `reflexLines` |
| BS-S02 | v9 parse of a v8 host file | Feed a v8 block to `TeachingSnippet.parse` → `stale` |
| BS-S03 | Single-source grep | Re-inline the body into any recipe |
| BS-S04 | Living-doc deny over `AGENTS.md` | Re-add a `pair relay` routing row |
| DEL-S01 | Topic resolves; `help search "brief"` non-empty | Delete the topic |
| DEL-S03 | Spawned PM prompt contains the anchor rule | Remove it from `LoopPrompts` |

No slice closes on a gate that has not been shown to fail. Per
`docs/operations/Spec_Review.md` §3, a check that cannot be made to fail is
decoration — and this packet exists because of a check that was pointed the
wrong way.

## 8. Inference bans

| Junction | Bad inference | Ban |
| --- | --- | --- |
| Hash is valid → content is true | Provenance mistaken for truth | The hash proves the paste matches the source; only a corpus gate proves the source matches the CLI (§2.3) |
| Block is gated → block is safe | Wrong-direction gate reads as coverage | `body.contains("<prose>")` freezes content; banned (§2.4) |
| Rules are useful → keep them in the paste | Grammar re-enters the block | Useful and rottable both true → it belongs in a help topic (§3) |
| Retired noun removed from deny list → CI green | Narrowing a red gate | Deny lists append forever (`RetiredVocabulary.swift:8`) |
| Delegation rules exist → seats will follow them | Teaching mistaken for proof | The gate the lead re-runs is the proof; the seat's report never is (§6.2) |
| DEL ships → route-down is safe | One packet's evidence becomes policy | 14 slices, one subsystem, one lead judging its own briefs |

## 9. Open questions

1. **How wide is the noun deny-list?** Catching rule 6/9 needs the bare nouns
   `relay` and `pilot`, not just the command forms already listed. But
   `HelpTopicRegistry.swift:271` legitimately keeps `pair relay` / `pilot` as
   **search aliases** so an agent typing the old word finds the `loop` topic —
   that is discoverability, and must not go red. **Recommendation:** deny the
   bare nouns in *instructional prose fields only* (titles, summaries, bodies,
   teaching lines); exempt `aliases` explicitly, in one named allow-path with a
   comment. Do not deny the noun globally.
2. **Does BS-S02's v9 bump strand host files?** Every v8 paste becomes `stale`
   and needs re-pasting. That is correct behaviour — they contain false rules —
   but it is user-visible. **Recommendation:** ship it; `stale` is exactly the
   state the machine was built to express, and a false `installed` is worse.

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| `alln bootstrap` content, teaching block, host paste going stale | This packet §2–§5; code SSOT `TeachingSnippet.swift` |
| Retired vocabulary in help, docs, or the teaching block | `RetiredVocabulary.swift` + `check-fast.sh:55` — never narrow a red gate |
| How to brief a delegated seat / verify what comes back | `alln help get delegation` (after DEL-S01); evidence in `Scarcity_Aware_Routing.md` §5a |
| Spawned PM prompt content | `LoopPrompts.swift` — see §6.1 before assuming it is deliberate |
