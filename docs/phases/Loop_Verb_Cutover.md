# Loop Verb Cutover — `alln loop delegate` / `alln loop pilot`

Status: **Draft v3 — founder approved 2026-07-30; reviewed 2026-07-30 (Cursor Grok 4.5, Doc Review); naming closed; not started**
Owner: Founder ruling; implementer TBD
Updated: 2026-07-30

Founder intent: the multi-round PM↔dev feature is named things nobody says.
`relay` is confusing, `pilot` is fine but hidden, and `pair` — the word the CLI
actually organizes them under — is a word the founder has never once uttered
when asking for one. Rename now, while it is cheap, and give the category a
name that can hold the loops we have not built yet.

Product value: one sayable word for a whole class of work. "Setup a delegation
loop with `docs/phases/X.md`" is a sentence a human says unprompted, in the CLI
and in the app. The current grammar requires knowing that `pair` means
"multi-round" and that `relay` means "unattended."

Trusted workflow slice: from the Mac composer, pick **Delegation Loop**, brief
it once, walk away. From the CLI, `alln loop delegate --doc <spec>` does the
same thing and `alln loop pilot` supervises it from the live session.

Non-goals: no change to run semantics, round mechanics, write-lock behavior, or
`RelayCoordinator` internals. This is a vocabulary and surface cut. The Mac
sheet redesign is **§8 — a separate slice**, deliberately landed after the name.

> **v2 note.** A Doc Review pass killed three claims in v1: a fabricated
> `--team` proof, an over-strong taxonomy law, and a "the gate finds everything"
> claim the gate cannot support. All three are corrected below, and v1's verb
> map was missing five of Pilot's six subcommands. See §7 for the full review
> disposition.
>
> **v3 note.** Naming is **closed** (§3). The review's Delegate-collision
> objection is withdrawn on a false premise — `delegate` has zero occurrences in
> the CLI. `autopilot | pilot` was proposed, seriously considered, and rejected:
> a minimal pair is a closed set of two, and attendedness is orthogonal to type.
> §3 now carries the law that protects the type slot, plus the known debt that
> `pilot` — not `delegate` — is the misfit sitting in it.

---

## 1. Why `loop` is a sibling verb, not a flag on `run`

The test is **not** "is it different." It is: **does it have an identity that
outlives a single turn and owns other things' identities?**

| | Identity | Owns | Verb |
| --- | --- | --- | --- |
| Run | one `runId`, ends with the turn | nothing | `alln run` |
| Loop | survives the caller; has rounds; resumable, adoptable, stoppable | many `runId`s | `alln loop` |

A loop is not a *kind of* run. It is a thing *made of* runs — containment, not
specialization. `alln run --loop` would lie about identity: `RunService` owns a
one-turn `runId`, and a loop owns many. That is the argument for the sibling
verb, and it is sufficient on its own.

### Menu_Not_Router permits this — with two obligations

`docs/archive/phases/Menu_Not_Router.md:229-257` ("One direct-run grammar") kills
*duplicate spending grammars* (`alln team "…"`), not distinct lifecycle verbs. It
says explicitly:

> "Distinct workflow commands may eventually create runs, but they must
> represent a real product operation — not an alias for direct `run` — and must
> **declare effects and a free twin in `ContractRegistry`**."

So the sibling verb is allowed, and v1 missed the price of admission:

- **`alln loop delegate --dry-run` is mandatory**, not optional. Every
  worker-starting path needs a quota-free twin that resolves ids, seats,
  readiness, write policy, and lock state without spending. `pair relay` has no
  such twin today; the cutover must add one. **New slice LVC-S08.**
- Effects must be declared in `ContractRegistry` for every new `loop` verb.

That ruling also settles v1's open question — a second top-level verb does not
violate the one-grammar law. Closed.

### Rejected as promoted law: "verbs are lifetimes, nouns are seatings"

v1 proposed promoting this to `Product_Vocabulary.md`. **Withdrawn** — it does not
survive its own repo:

- `alln pair` (device trust) is neither a lifetime nor a seating, and this packet
  keeps it.
- `alln teams` is noun *management*, not a seating modifier.
- Under `loop`, `status|stop|resume|adopt` are lifecycle ops, not types — yet the
  slogan gives them the same slot as `delegate|pilot`.

It is a useful heuristic for *this* cut and nothing more. Keep the containment
argument above; do not promote a slogan that an implementing agent will later
have to litigate against three counterexamples in the same CLI.

### Withdrawn: the `--team` cross-apply "proof"

v1 claimed `alln loop delegate --team <x>` "reads correctly and means something"
and used it as proof the taxonomy cut along the joint. **It is fiction.**
`RelayCLI.swift:396-397` requires `--pm-model` and `--dev-model`; there is no
`--team` on any relay path. A spec must not invent product behavior to justify
its own taxonomy. Claim deleted, not repaired — whether a loop round can be a
team run is a real question, but it is unbuilt and out of scope here.

### `alln team` still must not exist

Team is a seating, not a lifetime — it says who is in the chairs, not how long
the thing lives. It stays a modifier (`alln run --team <id>`), and it would
collide with `alln teams` besides. This part of v1 survives review.

### Why this is a correction, not a rearchitecture

`pair` already split off from `run` — nobody designed that split for taxonomy
reasons; it happened because cramming a multi-round thing into `run` did not
work. The category was discovered correctly and named badly.

---

## 2. New grammar

```text
alln run                     # one turn (team is a modifier: --team, --seat, --model)
alln loop delegate <brief>   # many turns — a spawned PM steers, unattended
alln loop pilot …            # many turns — THIS live CLI session is the PM (CLI only)
alln teams                   # manage the noun
```

`loop` is the **family**; `delegate` and `pilot` are the first two **types**.
Adding a third type must be a data change in `MenuCatalog` + a type case — never
a new top-level verb and never a new help-topic tree.

### Full verb matrix (v1's was missing five rows)

Live registry: `ContractRegistry+Milestone1.swift:609-666`,
`PairCLI.swift:20-31`, `PilotCLI.swift:32-37`.

| Today | After | Note |
| --- | --- | --- |
| `pair relay` | `alln loop delegate` | + mandatory `--dry-run` twin (LVC-S08) |
| `pair relay-status` | `alln loop status` | see status collapse below |
| `pair relay-resume` | `alln loop resume` | |
| `pair relay stop` | `alln loop stop` | founder stop, durable, not resumable |
| `pair relay adopt` | **unresolved** — see adopt below | pilot → spawned |
| `pair pilot start` | `alln loop pilot start` | |
| `pair pilot handoff` | `alln loop pilot handoff` | |
| `pair pilot status` | `alln loop pilot status` *or* collapse | |
| `pair pilot watch` | `alln loop pilot watch` | disposable waiter |
| `pair pilot adopt` | **unresolved** — see adopt below | spawned → pilot |
| `pair pilot scaffold-handover` | `alln loop pilot scaffold-handover` | |
| `pair list\|approve\|revoke\|begin` | **unchanged** | device trust keeps `pair` |

**The two adopts flip in opposite directions.** Verified in the contract:

- `pair relay adopt` — *"converts a parked Pilot relay (awaitingPM or escalated)
  to a spawned PM relay"* (`ContractRegistry+Milestone1.swift:586`)
- `pair pilot adopt` — *"Reverse flip: hands a parked spawned relay's PM seat to
  a piloting session (pmMode → external)"* (`:658`)

One `alln loop adopt` **cannot** absorb both. Resolve before implementation —
either two verbs (`loop adopt` / `loop pilot adopt`) or one verb with an explicit
direction flag. Do not let an implementer discover this mid-slice.

**Status collapse needs a ruling too.** `relay-status` and `pilot status` have
different wait/mode semantics (parked vs terminal, and `pilot status`'s
stream-primary liveness from the archived `Pilot_Status_Liveness_Lie_Hotfix`).
Collapsing them into one `loop status` without deciding that law is exactly the
lie-prone shape this repo has already been burned by. Owners: `PilotCLI` /
`RelayCLI` status waiters.

### `alln pair` is freed for its real meaning

Today `PairCLI.run` dispatches **two unrelated products** under one verb: device
pairing (`list|approve|revoke|begin`, `--agent-signing-pubkey`, `--transport`,
`--ttl-seconds`) and the multi-round loop. `ContractRegistry+Milestone1.swift:1042`
already documents `pair` as *"Approve iOS/Mac pairing."* — true of half its
subcommands. Moving the loop verbs out leaves `pair` meaning one thing. Not the
reason for the rename; a real cleanup that falls out of it.

---

## 3. Naming — the type slot holds *whats*, not postures

**Ruling: `delegate`. Closed 2026-07-30.** The v2 "standing objection" is
withdrawn on verified facts (below), and the `autopilot` alternative is rejected
on the axis argument (below). Do not relitigate either.

### The law this section exists to protect

> **The type slot names what the loop DOES. Attendedness is a different axis and
> must never be spent there.**

Every plausible future loop — research, review, migration, debug — differs by
*what it does*, and each could run attended or unattended. Attendedness is
therefore **orthogonal** to type. Burn the type slot on a posture and the day
`alln loop research` ships it sits beside a sibling that answers a different
question — a category error visible in `alln menu --json`, unfixable without
another cutover.

`delegate` passes: it names an act — this loop hands work to another agent, slice
by slice — occupying the same slot a future `research` or `review` would.

### Rejected — `autopilot | pilot`

Proposed 2026-07-30 and genuinely attractive: a minimal pair sharing a stem, one
morpheme carrying the whole semantic difference, self-teaching for a cold agent,
and it dissolves the Delegate collision by deleting the word.

**Rejected because a minimal pair is a closed set of two.** `autopilot|pilot` is
one axis with both values already spent — the property that makes it elegant is
exactly what makes it unextendable. It also commits the family to the aviation
metaphor, which a third type would have to satisfy or visibly break.

Recorded here so it is not re-proposed. It is the best *wrong* answer in this
section.

### Rejected — `Pair Programming Loop`

Pair programming is two people at one keyboard, synchronous, both present. This
is one agent briefing another and reviewing its commits after the fact. It also
hardcodes *programming* into a loop that should run Design and Copy work.

### Rejected — `Loop` alone as the feature name

Burns the family name on one member.

### Withdrawn — the "Delegate collision" objection (false premise)

v2 recorded a review objection that `loop delegate` collides with locked one-shot
`Delegate`, and added a required `dontUseWhen` mitigation. **Both are withdrawn.**
Grep, 2026-07-30 — `delegate` does not exist in the CLI:

- `alln menu --json` — **zero** occurrences
- No verb, no flag, no JSON key, no contract `CommandSpec`
- `Product_Vocabulary.md:21` — a **doc-layer** word whose own entry states the UI
  label is "Send to team"
- `HelpTopicRegistry.swift:191` — **one search alias**, so `alln help search
  delegate` finds the send-to-team topic

So the "locked" word is one we use *about* the product in docs, not *in* the
product. There is nothing in the agent-facing surface to collide with, and the
mitigation is unnecessary.

**One real consequence survives:** that help alias will point the wrong way once
`alln loop delegate` ships. Re-point or disambiguate it in **LVC-S03**. One line,
not a naming problem.

### Known debt — `pilot` is the misfit, not `delegate`

By this section's own law, `pilot` is attendedness wearing a type's clothes. It
is grandfathered into the type slot because it is the shipped word and there is
no second genuine *what* yet to force the issue.

The forward-compatible grammar is almost certainly `alln loop <type>` with
attendedness as a **modifier**. When a second real type arrives, re-home `pilot`
then — do not pre-build that machinery now, and do not let an implementer
pattern-match a third type onto the attendedness axis because `pilot` sits there.
**This paragraph is the warning that prevents that.**

### "Dev" has the craft problem too

`--dev-model`, "Dev seat" — fine while the loop is code-first, but the label lies
the moment Design or Copy runs through it. **Not solved here.** Do not promote
`dev` into `Product_Vocabulary.md`, so a later rename stays free.

### "Dev" has the craft problem too

`--dev-model`, "Dev seat" — fine while the loop is code-first, but the label lies
the moment Design or Copy runs through it. **Not solved here.** Do not promote
`dev` into `Product_Vocabulary.md`, so a later rename stays free.

---

## 4. Supersedes existing vocabulary rulings

`docs/workflows/Product_Vocabulary.md` currently rules the **opposite** of this
packet in three places, superseded by the 2026-07-30 founder ruling:

| Line | Current text | Disposition |
| --- | --- | --- |
| 27 | "**Loop** \| Mac composer noun for an unattended Relay … CLI stays `pair relay*` and is **never** renamed to `pair loop`." | **Superseded.** Loop is now the family noun in *both* surfaces. The old rule deliberately kept the human word and the machine word out of sync; the ruling is that they converge. |
| 29 | "**Pilot** \| … CLI-only, always. The Mac app is never the PM seat and offers no Pilot entry." | **Kept and strengthened.** Now expressible: pilot is a *type* the app does not expose, not a mysteriously missing sibling. |
| 51–53 | "Teach `pair relay` / `pair relay stop` / `pair relay-status`; **never invent `pair loop`**." | **Superseded.** Replace with the `alln loop <type>` grammar. Founder Stop moves to `alln loop stop` (durable `stopped`, reason `founder stopped`, PM Turn written, not resumable) — still never `alln kill`, which stays process machinery. |

### Explicit wire ruling (v1 left this implied)

**CLI verbs move. Wire keys, on-disk state, and internal symbols do not.**

- Unchanged: `RelayCoordinator`, `RelayVerdict`, `RelayState`, `AllnighterPaths`
  `Relays/`, journal `kind: relay|pilot`, notification event ids
  (`relay.needs_answer`), the relay id itself.
- **Undecided and must be decided in LVC-S00:** the agent-facing `--relay <id>`
  flag, and the `kind` strings an agent reads out of `alln ps`. These are read by
  agents, so "internal" is not automatic. Pick one and write it down.

---

## 5. Execution

**LVC-S00 — Vocabulary ruling.** Rewrite `Product_Vocabulary.md` §Human layer and
§Loop-vs-Pilot-vs-Relay per §4. Decide the `--relay` flag and `ps` `kind` question.
Resolve the two adopt directions (§2) and the status collapse (§2). No code.

> **v1 ordering bug, corrected.** v1 landed S00 as a standalone commit *ahead of
> the binary*, which would have the SSOT teaching `alln loop …` while the shipped
> CLI still only had `pair relay` — recreating the exact word-split this cutover
> exists to kill, and inviting agents to invent verbs from the doc.
> **S00–S05 land as one merge unit.** Author S00 first; ship it with the code.

**LVC-S01 — Retire the old vocabulary.** Add `pair relay`, `pair relay-status`,
`pair relay-resume`, `pair pilot`, `relay adopt` to `RetiredVocabulary.swift`.
This turns `HelpTopicRegistryTests` / `RetiredVocabularyTests` red across help
and next-actions. That red is real and useful — but see the gate's limits below.
**Not a standalone green commit.**

**LVC-S02 — New verb.** `LoopCLI` with the full matrix from §2. Retired verbs
error naming the new one — **hard cutover, no aliases**.

**LVC-S03 — Agent-facing surfaces.** `MenuCatalog.swift`,
`HelpTopicRegistry.swift` (topic `pm_relay`, `:221-275`), `Bootstrap.swift`,
`TeachingSnippet.swift`, `RecipeCatalog` + the four recipe bodies (§6).

**LVC-S04 — Living docs.** `AGENTS.md` routing table (four rows), `docs/phases/README.md`,
`docs/operations/`, `Product_Vocabulary.md`. **Do not rewrite `docs/archive/phases/`** —
rewriting the archive makes the record lie about what shipped when. A one-line
header note (`relay → loop delegate, renamed 2026-07-30`) on `PM_Relay.md`,
`Pilot_Relay.md`, `Round_Survives_The_Caller.md`, `Agent_Team_Loop.md` is enough.

**LVC-S05 — Version.** Agent-facing verbs *are* the contract:
`contractVersion` **6.13.0 → 7.0.0**, `binaryVersion` **0.10.7 → 0.11.0** (+0.1.0
on a contract major). Same merge unit. Regenerate `docs/generated/alln/*` via
`alln dev export-contracts` — it is generated output, never hand-edited.

**LVC-S06 — Mac app: Delegation Loop only.** Popover offers Delegation Loop, full
stop. **Pilot is not shown, not shown-disabled, not mentioned** — there is no live
session behind a modal, so the option is nonsense there. Code: §6.

**LVC-S07 — Seat defaults, not recommendations.** PM = **Frontier** tier,
Dev = **Balanced** tier via the tier SSOT (`DefaultModelSettings.swift`). No
hardcoded model ids — that is what lets a down CLI route around itself instead of
the sheet defaulting to a seat that cannot run. Sheet shows what resolved; click
to change.

**LVC-S08 — The free twin (new; Menu_Not_Router obligation).**
`alln loop delegate --dry-run` resolving project, canonical ids, both seat models,
readiness, write policy, and lock state; creating no state and spending no quota.
Declare effects for every `loop` verb in `ContractRegistry`. **Non-optional** —
this is the price of admission for a distinct workflow verb.

### The gate is narrower than v1 claimed

v1 said the deny-list red "is the only mechanism that finds the surface we would
otherwise forget." **That is false as the gate stands**, and shipping on that
belief is how surfaces get missed:

- `livingDocDenyPatterns` is a **separate list** from the term deny-list
  (`RetiredVocabulary.swift:119-134`).
- `scripts/check.sh:93-99` greps **only** `docs/operations/*.md` plus two named
  files. It does **not** scan `AGENTS.md`, `Product_Vocabulary.md`,
  `docs/phases/README.md`, recipe bodies, or Mac strings — every one of which
  carries `pair relay` today.
- Bootstrap already avoids teaching `pair pilot`
  (`BootstrapTests.swift:59-60`), so "red across bootstrap" was overstated.

**Therefore LVC-S01 must also widen the gate**: add the new phrases to
`livingDocDenyPatterns` *and* extend `check.sh` scan roots to `AGENTS.md`,
`docs/workflows/*.md`, `docs/phases/*.md`, and `Resources/Recipes/*.md`. Widening
the gate is in scope. Narrowing it to pass is never in scope — allowlists are
where these gates die (archived `CLI_Agent_Surface_Fidelity.md`).

---

## 6. Surfaces (verified by grep, 2026-07-30)

Truth owner: `Product_Vocabulary.md` for the words; `LoopCLI` + `MenuCatalog` +
`ContractRegistry` for the surface; `RelayCoordinator` (unchanged) for round
mechanics.

**Mac app — does key off the verb** (v1 said "sheet only"; wrong):
- `Apps/AllnighterMac/Sources/RelayDetachedLauncher.swift:103` — hardcoded
  `"pair", "relay"` argv
- `Apps/AllnighterMac/Tests/RelayLaunchViewModelTests.swift:154,158` — asserts
  that argv
- `Apps/AllnighterMac/Sources/RelayStatusLoader.swift` — `pair relay-status`
- `Apps/AllnighterMac/Sources/RoutingComposer.swift` — composer tab copy (says
  "Loop", must become "Delegation Loop")

**Product-facing strings** (rule on each: product copy or machine word?):
- `RelayThreadProjector.swift:271` — thread titles `"PM Relay"` / `"PM Relay: …"`
- `NotificationDeliveryFilter.swift:99-102` — `"PM Relay needs an answer"`
- `ContractRegistry+Milestone1.swift:742` — `serve` summary teaches four old verbs
- `ContractRegistry+Milestone1.swift:1181,1183` — `ErrorSpec.agentAction` for
  `RELAY_INVALID_STATE` / `RELAY_ALREADY_ACTIVE` teach `pair relay-status`
- `PilotCLI.swift` / `RelayCoordinator.swift` — embedded next-action strings

**Recipes** (agent-facing, not gate-covered):
`Resources/Recipes/keep-working-while-im-away.md`,
`get-another-model-to-implement-this.md`,
`recover-a-run-that-lost-its-terminal.md`,
`challenge-this-decision-before-i-commit.md`

**Living docs carrying `pair relay|pilot` outside archive/:** `AGENTS.md`,
`docs/workflows/Product_Vocabulary.md`, `docs/phases/README.md`,
`docs/phases/Work_Recovery_And_PM_Continuity.md`,
`docs/phases/atl/ATL_S01_S02_execution.md`,
`docs/phases/closeout/Open_Items_Closeout.md`,
`docs/operations/debugger/DEBUGLOG.md`, `docs/generated/alln/help_alln_cli_spec.md`
(generated — regenerate, do not edit).

Lie-prone layers: `RetiredVocabulary` allowlists (historical failure mode is
narrowing the gate); help text and teaching snippets, which have drifted from
shipped verbs before; `ContractRegistry+Milestone1.swift:1042`, which already
describes `pair` as pairing-only while it also dispatches loop verbs.

Duplicate truth to delete: the `Loop`-is-Mac-only / `relay`-is-CLI-only split in
`Product_Vocabulary.md` — one concept, two names, by prior design.

iOS app impact: device pairing keeps `alln pair` and gets it to itself. v1
asserted "none" — **verify no remote/control path teaches `pair relay*` before
closeout.** Do not assert impact from silence.
Driver/protocol impact: none. Auth/privacy/permissions impact: none.

---

## 7. Review disposition (Doc Review, Cursor Grok 4.5, 2026-07-30)

| Finding | Verified? | Disposition |
| --- | --- | --- |
| `--team` cross-apply proof is fiction (`RelayCLI.swift:396-397`) | ✅ | **Accepted** — claim deleted (§1) |
| Taxonomy law breaks on `pair`, `teams`, and loop's own lifecycle ops | ✅ | **Accepted** — demoted from promoted law (§1) |
| Menu_Not_Router permits the sibling verb but demands effects + free twin | ✅ `:229-257` | **Accepted** — new LVC-S08; open question closed |
| Verb map missing 5 pilot subcommands | ✅ `PilotCLI.swift:32-37` | **Accepted** — full matrix (§2) |
| Two adopts flip in opposite directions | ✅ `ContractRegistry:586,658` | **Accepted** — flagged unresolved, must be decided in S00 |
| Gate does not scan the docs v1 claimed (`check.sh:93-99`) | ✅ | **Accepted** — claim corrected, widening the gate added to S01 |
| S00-before-binary teaches phantom verbs | ✅ | **Accepted** — S00–S05 now one merge unit |
| Mac app keys off the verb (launcher argv, status loader) | ✅ | **Accepted** — §6 |
| `delegate` collides with locked one-shot Delegate | ❌ **false premise** | **Rejected (v3).** `delegate` has zero occurrences in `alln menu --json` and no verb/flag/JSON key anywhere — it is a doc word whose UI label is "Send to team". Only real artifact is one help alias (`HelpTopicRegistry.swift:191`), re-pointed in LVC-S03. v2's `dontUseWhen` mitigation withdrawn. |
| Version 7.0.0 / 0.11.0 correct | ✅ | No change |
| Collapsing `relay-status` + `pilot status` is lie-prone | ✅ | **Accepted** — must be ruled in S00 |

---

## 8. Deferred — the Delegation Loop sheet (separate packet)

Approved in principle 2026-07-30, **explicitly not in this cutover.** The rename
touches contract, menu, help, bootstrap, and docs; the sheet touches layout and
copy. Land the name first, then build the surface on a name that is already true.

**The bug is two homes.** Today "Loop" is a composer mode that hijacks what Return
does, *and then* a modal opens and asks for the brief again — the mode is
surprising and the modal is redundant. Pick one home: **the sheet, opened
immediately on select.** Carry any composer text into the brief field (decide
explicitly: consumed or copied — if copied and left behind, the user can send it
twice). The "brief once, then Return opens the launch sheet" tooltip then becomes
unnecessary, which is the point: a tooltip explaining what a keystroke will do is
evidence the interaction should not exist.

**Sheet shape — one required field, one row of defaults, one optional field, one
button:**

1. **Brief teaches by example.** Replace "KICKOFF / Brief the PM once — not a
   chat" with a real placeholder. Label: "What should this loop deliver?"
   Helper: "Write a short note to your PM. It will delegate the work one slice at
   a time until everything is delivered." Placeholder: *"Execute the spec in
   docs/phases/110-connect-resume.md — build each slice, prove it works, then
   move to the next."*
2. **Collapse the seat pickers** from two full-height scrolling lists to two
   compact dropdowns on one row, pre-filled by tier (LVC-S07). Role as helper
   text: "PM — reviews each round, decides what's next" / "Dev — builds and
   commits."
3. **Spec doc optional** — "Point at a spec (optional)". Do **not** build repo-path
   detection in the brief; inference is scope creep and will guess wrong.
4. **Footer in plain words.** "Runs unattended. Your PM reviews the actual commits
   after every round and stops when the work is delivered."

**Design constraint carried forward:** a Delegation Loop is *not* rare. It is a
co-equal hero loop — all-day, high-frequency, not a multi-hour ceremony. Design
for the tenth launch, not the first: remember last seats and spec so the repeat
path is type-one-field-and-go.

---

## 9. Proof

Works Test: from a clean shell — start an unattended loop that lands a real
commit; `pilot start → handoff → status (parked) → watch`; **both** adopt
directions; stop; resume; every old verb hard-errors naming its replacement;
`alln pair approve` still works; the Mac detached launcher spawns the new argv.

Proof command:
```text
swift test --filter Relay
swift test --filter Pilot
swift test --filter RetiredVocabulary
swift test --filter ContractRegistry
scripts/check.sh
scripts/agent_eval.sh --suite menu-not-router
python3 scripts/verify_menu_contract.py
swift test                     # once, at closeout
```

Fixtures to update: contract export + `ContractRegistryTests` command-name list;
Mac `RelayDetachedLauncher` / `RelayStatusLoader` unit tests.

Missing proof / waiver: **the cold-agent matrix is non-optional.**
`menu-not-router` / `scripts/menu_not_router_eval.py` must be extended to cover
the `loop` family — it is the only gate on whether a never-before-seen grammar is
*selectable* by an agent, and the `delegate` collision (§3) is precisely the kind
of thing it exists to catch. v1 half-admitted this as a possible waiver; v2 does
not permit the waiver.

Done when: no product surface an agent or human can read says `pair relay`,
`pair pilot`, or `relay-resume`; `alln loop` is the only way to start a
multi-round thing; `alln loop delegate --dry-run` exists and spends nothing;
contract 7.0.0 / binary 0.11.0 ship together; the Mac popover offers Delegation
Loop and no Pilot.

## 10. Open questions

- ~~`delegate` vs `unattended`/`autopilot` as the type id~~ — **CLOSED 2026-07-30**
  (§3). The collision was a false premise and `autopilot` spends the type slot on
  an orthogonal axis. Do not reopen.
- **Two adopt directions** — two verbs or one verb with a direction flag. Must be
  ruled in LVC-S00.
- **`relay-status` + `pilot status` collapse** — one verb needs one wait/mode law
  first. Must be ruled in LVC-S00.
- **`--relay` flag and `alln ps` `kind` strings** — agent-readable, so "internal"
  is not automatic. Must be ruled in LVC-S00.
- **Third loop type?** The family only pays for itself if one is plausible. None
  is authorized — do not build speculative type machinery beyond the enum + menu
  data.
- **`--dev-model` / `--pm-model` flag names** — left alone; revisit when a
  non-code craft actually runs through a loop.
