# Loop Verb Cutover — `alln loop delegate` / `alln loop pilot`

Status: **Draft — founder approved 2026-07-30, not started**
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
sheet redesign is **§7 — a separate slice**, deliberately landed after the name.

---

## 1. The ruling

### Verbs are lifetimes. Nouns are seatings.

This is the durable law the cutover produces, and it is the part to promote into
`docs/workflows/Product_Vocabulary.md`:

> **`run` and `loop` are lifetimes. `team`, `seat`, `model` are seatings that
> modify either.**

The test for "does this deserve its own verb" is not *is it different* — it is:
**does it have an identity that outlives a single turn and owns other things'
identities?**

| | Identity | Owns | Verb |
| --- | --- | --- | --- |
| Run | one `runId`, ends with the turn | nothing | `alln run` |
| Loop | survives the caller; has rounds; resumable, adoptable, stoppable | many `runId`s | `alln loop` |

A loop is not a *kind of* run. It is a thing *made of* runs — containment, not
specialization. That is why it earns a sibling verb rather than a posture flag.

Proof the cut is along the joint: modifiers cross-apply cleanly.
`alln loop delegate --team <x>` reads correctly and means something — one round
can be a parallel judgment team, the next a single mutating seat. If `team` were
a verb instead of a seating, that sentence could not exist.

### `alln team` must not exist

Team is a seating, not a lifetime. It does not change how long the thing lives
or what it owns; it says who is in the chairs. So it stays a modifier
(`alln run --team <id>`), and it would collide with `alln teams` (manage the
noun) besides.

### Why this is a correction, not a rearchitecture

`pair` already split off from `run` — nobody designed that split for taxonomy
reasons, it happened because cramming a multi-round thing into `run` did not
work. The category was discovered correctly and named badly. This cut renames
one word and regularizes the grammar around a category that already exists.

---

## 2. New grammar

```text
alln run                     # one turn (team is a modifier: --team, --seat, --model)
alln loop delegate <brief>   # many turns — a spawned PM steers, unattended
alln loop pilot <brief>      # many turns — THIS live CLI session is the PM (CLI only)
alln loop status
alln loop stop
alln loop resume
alln loop adopt
alln teams                   # manage the noun
```

`loop` is the **family**; `delegate` and `pilot` are the first two **types**.
Adding a third loop type must be a data change in `MenuCatalog` + a type case —
never a new top-level verb and never a new help-topic tree. That extension point
is the main thing this cutover buys.

### Orphans get better homes

| Today | After |
| --- | --- |
| `alln pair relay` | `alln loop delegate` |
| `alln pair pilot` | `alln loop pilot` |
| `alln pair relay-status` | `alln loop status` |
| `alln pair relay stop` | `alln loop stop` |
| `alln pair relay-resume` | `alln loop resume` |
| `alln pair relay adopt` | `alln loop adopt` |

Three hyphenated one-offs become regular subcommands of one family.

### `alln pair` is freed for its real meaning

Today `PairCLI.run` dispatches **two unrelated products** under one verb:

- device pairing — `list` / `approve` / `revoke` / `begin` (iOS↔Mac trust,
  `--agent-signing-pubkey`, `--transport`, `--ttl-seconds`)
- the multi-round loop — `relay` / `relay-status` / `relay-resume` / `pilot`

`ContractRegistry+Milestone1.swift:1042` already documents `pair` as
*"Approve iOS/Mac pairing."* — which is true of half its subcommands. Moving the
loop verbs out leaves `pair` meaning exactly one thing. This was not the reason
for the rename, but it is a real cleanup that falls out of it for free.

---

## 3. Naming — why `delegate`, and what was rejected

**Delegation Loop** wins because it lands on a word already locked in the
vocabulary. Delegate is "hand intent to a team." The loop is: delegate, review
the commits, delegate again, until delivered. Anyone who knows what Delegate
means can derive what Delegation Loop means **without a tooltip** — which is the
whole test. It is also craft-neutral.

Rejected — **Pair Programming Loop**: inaccurate in the way that matters. Pair
programming is two people at one keyboard, synchronous, both present. This is
one agent briefing another and reviewing its commits after the fact,
unattended. It also hardcodes *programming* into a loop that should run Design
and Copy work. It inherits the exact confusion `pair` already has.

Rejected — **`Loop` alone as the feature name**: burns the family name on one
member. Reserved for the category.

### Vocabulary collision to settle in the same slice

`Delegate` is locked as "send to team," one round. `loop delegate` reuses it for
many rounds. **Ruling: coherent — same act, one round vs. until-delivered.**
This is recorded here so an implementing agent does not re-decide it mid-slice,
per the laws-are-hypotheses rule.

### "Dev" has the craft problem too

`--dev-model`, "Dev seat" — fine while the loop is code-first in practice, but
the label lies the moment Design or Copy runs through it. **Not solved in this
cutover.** Do not let `dev` into `Product_Vocabulary.md` as locked vocabulary;
leave it as an unpromoted implementation word so a later rename is free.

---

## 4. Supersedes existing vocabulary rulings

`docs/workflows/Product_Vocabulary.md` currently rules the **opposite** of this
packet in three places. All three are superseded by the 2026-07-30 founder
ruling and must be rewritten in the same slice as the code:

| Line | Current text | Disposition |
| --- | --- | --- |
| 27 | "**Loop** \| Mac composer noun for an unattended Relay … CLI stays `pair relay*` and is **never** renamed to `pair loop`." | **Superseded.** Loop is now the family noun in *both* surfaces. The old rule kept a human word and a machine word deliberately out of sync; the ruling is that they converge. |
| 29 | "**Pilot** \| … CLI-only, always. The Mac app is never the PM seat and offers no Pilot entry." | **Kept and strengthened.** Still true, and now expressible: pilot is a *type* the app does not expose, not a mysteriously missing sibling. |
| 51–53 | "Loop vs Pilot vs Relay: … Teach `pair relay` / `pair relay stop` / `pair relay-status`; **never invent `pair loop`**." | **Superseded.** Replace with the `alln loop <type>` grammar. Founder Stop moves to `alln loop stop` (durable `stopped`, reason `founder stopped`, PM Turn written, not resumable) — still never `alln kill`, which stays process machinery. |

"Relay" survives as **an internal machine word only** — `RelayCoordinator`,
`RelayVerdict`, the on-disk relay id. Swift symbols do not need to move for a
product-surface rename. But anything an agent or human can *read* is product
surface and must move.

---

## 5. Execution — gate first, then sweep

Ordering is not optional. The vocabulary ruling lands first, then the deny-list
gate turns everything red, then surfaces get fixed until green.

**LVC-S00 — Vocabulary ruling.** Rewrite `Product_Vocabulary.md` §Human layer
and §Loop-vs-Pilot-vs-Relay per §4. Add the *verbs are lifetimes, nouns are
seatings* law. No code. This is the SSOT and everything else is mechanical
after it.

**LVC-S01 — Retire the old vocabulary, deliberately red.** Add `pair relay`,
`pair relay-status`, `pair relay-resume`, `pair pilot`, `relay adopt` to
`RetiredVocabulary.swift` **before** implementing the new verbs. The build goes
red across menu, help topics, bootstrap snippets, and living docs. That red is
the sweep — it is the only mechanism that finds the surface we would otherwise
forget.

> **Never narrow the gate to make it pass.** Allowlists are where these gates
> die (see archived `CLI_Agent_Surface_Fidelity.md`).

**LVC-S02 — New verb.** `LoopCLI` with `delegate|pilot|status|stop|resume|adopt`
dispatch. Retired verbs error with the new name — **hard cutover, no aliases**,
per the standing vocabulary rule.

**LVC-S03 — Agent-facing surfaces.** `MenuCatalog.swift`,
`HelpTopicRegistry.swift`, `Bootstrap.swift`, `TeachingSnippet.swift`,
`RecipeCatalog`. Loop types enumerated as data, not as separate menu entries per
verb.

**LVC-S04 — Living docs.** `AGENTS.md` routing table (four rows name
`pair relay` today), `docs/phases/README.md` routing table, `docs/operations/`
playbooks. **Do not rewrite `docs/archive/phases/`** — rewriting the archive
makes the record lie about what shipped when. A one-line header note
(`relay → loop delegate, renamed 2026-07-30`) on `PM_Relay.md`,
`Pilot_Relay.md`, `Round_Survives_The_Caller.md`, `Agent_Team_Loop.md` is
enough.

**LVC-S05 — Version.** Agent-facing verbs *are* the contract, so this is a
breaking cut: `contractVersion` **6.13.0 → 7.0.0**, `binaryVersion`
**0.10.7 → 0.11.0** (+0.1.0 on a contract major, per the standing version rule).
Same slice, so the version never describes a vocabulary that is not shipping.

**LVC-S06 — Mac app: Delegation Loop only.** The popover offers Delegation Loop,
full stop. **Pilot is not shown, not shown-disabled, not mentioned.** Pilot
means "this live CLI session is the PM"; there is no live session behind a
modal, so the option is nonsense there.

**LVC-S07 — Seat defaults, not recommendations.** PM = **Frontier** tier,
Dev = **Balanced** tier, resolved through the existing tier SSOT
(`DefaultModelSettings.swift`). No hardcoded model ids in the sheet — that is
what makes a down CLI route around itself instead of the sheet defaulting to a
seat that cannot run. The sheet displays what resolved; click to change.

---

## 6. Truth ownership

Truth owner: `Product_Vocabulary.md` for the words; `LoopCLI` + `MenuCatalog` +
`ContractRegistry` for the surface; `RelayCoordinator` (unchanged) for round
mechanics.

Lie-prone layers:
- `RetiredVocabulary` allowlists — the historical failure mode is narrowing the
  gate rather than fixing the surface.
- Help text and teaching snippets, which have drifted from shipped verbs before
  (the whole reason `RetiredVocabulary.swift` exists).
- `ContractRegistry+Milestone1.swift:1042`, which already describes `pair` as
  pairing-only while it also dispatches loop verbs.

Duplicate truth to delete: the `Loop`-is-Mac-only / `relay`-is-CLI-only split in
`Product_Vocabulary.md` — one concept, two names, by prior design. Gone.

Implementation impact: new `LoopCLI`; `PairCLI` loses `relay*` and `pilot`
dispatch and keeps device pairing; `RetiredVocabulary` entries; menu/help/
bootstrap; contract + binary version.
Mac app impact: popover entry renamed and pilot removed (S06); sheet defaults
(S07). Sheet redesign is §7, not this cutover.
iOS app impact: none — device pairing keeps `alln pair` and gets it to itself.
Driver/protocol impact: none.
Auth/privacy/permissions impact: none.

---

## 7. Deferred — the Delegation Loop sheet (separate packet)

Approved in principle 2026-07-30, **explicitly not in this cutover.** The rename
touches contract, menu, help, bootstrap, and docs; the sheet touches layout and
copy. Land the name first, then build the surface on a name that is already
true.

Recorded so it is not lost:

**The bug is two homes.** Today "Loop" is a composer mode that hijacks what
Return does, *and then* a modal opens and asks for the brief again — the mode is
surprising and the modal is redundant. Pick one home: **the sheet, opened
immediately on select.** Carry any composer text into the brief field so nothing
is lost (decide explicitly: consumed or copied — if copied and left behind, the
user can send it twice). The "brief once, then Return opens the launch sheet"
tooltip then becomes unnecessary, which is the point: a tooltip explaining what a
keystroke will do is evidence the interaction should not exist.

**Sheet shape — one required field, one row of defaults, one optional field, one
button:**

1. **Brief teaches by example.** Replace "KICKOFF / Brief the PM once — not a
   chat" with a real placeholder. Label: "What should this loop deliver?"
   Helper: "Write a short note to your PM. It will delegate the work one slice
   at a time until everything is delivered." Placeholder: *"Execute the spec in
   docs/phases/110-connect-resume.md — build each slice, prove it works, then
   move to the next."* That placeholder teaches more than all current microcopy
   combined.
2. **Collapse the seat pickers** from two full-height scrolling model lists to
   two compact dropdowns on one row, pre-filled by tier (§LVC-S07). Role as
   helper text: "PM — reviews each round, decides what's next" / "Dev — builds
   and commits."
3. **Spec doc optional** — "Point at a spec (optional)". Do **not** build repo-
   path detection in the brief; inference is scope creep and will guess wrong.
4. **Footer in plain words.** "Runs unattended. Your PM reviews the actual
   commits after every round and stops when the work is delivered."

**Design constraint carried forward:** a Delegation Loop is *not* rare. Relay is
a co-equal hero loop — all-day, high-frequency, not a multi-hour ceremony.
Design the sheet for the tenth launch, not the first: remember last seats and
spec so the repeat path is type-one-field-and-go. Do not add ceremony on the
theory that it is rare.

---

## 8. Proof

Works Test: from a clean shell, `alln loop delegate --doc <spec>` starts a round
that lands a real commit, `alln loop status` reports it, `alln loop stop` stops
it durably. `alln pair relay` errors and names `alln loop delegate`. `alln pair
approve` still works.

Proof command:
```text
swift test --filter Relay
swift test --filter RetiredVocabulary
scripts/agent_eval.sh --suite menu-not-router
python3 scripts/verify_menu_contract.py
swift test                     # once, at closeout
```

Missing proof / waiver: the cold-agent matrix (`menu-not-router`) is the real
gate on whether the new grammar is *selectable* by an agent that has never seen
it. If that suite cannot be extended to cover loop types in this slice, name the
waiver at closeout — do not claim the grammar is agent-legible without it.

Done when: no product surface an agent or human can read says `pair relay`,
`pair pilot`, or `relay-resume`; `alln loop` is the only way to start a
multi-round thing; contract 7.0.0 / binary 0.11.0 ship together; the Mac popover
offers Delegation Loop and no Pilot.

## 9. Open questions

- **Third loop type?** The family only pays for itself if a third type is
  plausible. None is authorized — do not build speculative type machinery beyond
  the enum + menu data.
- **`--dev-model` / `--pm-model` flag names.** Left alone (§3). Revisit only
  when a non-code craft actually runs through a loop.
- **Sheet packet scoping** (§7) — needs its own doc before implementation.
