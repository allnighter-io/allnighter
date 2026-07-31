# Loop Verb Cutover — `alln loop`

> **Archived 2026-07-31.** Shipped LVC-S00–S09: `alln loop` grammar, contract 7.0.0 /
> binary 0.11.0, `Relay*`→`Loop*` symbol sweep, `Relays/`→`Loops/` path move.
> Standing law: `docs/workflows/Product_Vocabulary.md` §Loop + Laws 1–3;
> code SSOT: `LoopCLI`, `LoopEngineCLI`, `LoopCoordinator`, `LoopState`/`LoopStateStore`.

Status: **Complete — archived 2026-07-31** (v7 LOCKED 2026-07-30)
Owner: Founder ruling
Updated: 2026-07-31

Founder intent: the multi-round PM↔dev feature is named things nobody says.
`relay` is confusing, `pilot` is fine but hidden, and `pair` — the word the CLI
organizes them under — is a word the founder has never once uttered when asking
for one. Rename now, while it is cheap, and give the category a shape that holds
the loops we have not built yet.

Product value: one sayable word for a whole class of work, and one vocabulary
across CLI, JSON, disk, and UI.

Trusted workflow slice: **`alln loop start "<what you want done>"`** — one
sentence, nothing else required. It runs round after round, reviewing real commits,
until the work is done. The Mac composer does the same thing behind one sheet.

Non-goals: no change to round mechanics, write-lock behavior, or coordinator
internals beyond what the renames force. The Mac sheet redesign is §8, a separate
packet.

> **Version history.** v1 drafted. v2 corrected by Doc Review (Cursor Grok 4.5) —
> killed a fabricated proof, an overfit law, and a false claim about the gate.
> v3 closed naming. v4 removed `pilot` from the type slot. **v5 is a cold
> first-principles redesign (Fable 5) that converged on v4's object model and
> improved three things: the chair is an occupant, operations are chair-neutral,
> and `kind` names what *done* means.** Rejected alternatives are recorded in §3
> so none of it gets relitigated.
>
> **v6.** Implementation-readiness pass (Sonnet 5), names locked and unchanged.
> Found two places where v5 was *factually wrong* about the state machine — the
> two adopts do **not** share preconditions, and `step` for a spawned chair had no
> existing operation to be neutral over — plus a missing archive step and a dozen
> uncovered surfaces. All corrected below. **The names did not move.**
>
> **v7 — founder ruling, from his own sentences.** v6 was unusable: the founder
> could not say what he wanted. Derived from transcript instead of principle
> (§2 "What the founder actually says"). Three changes, all removals:
> the `deliver` kind slot is **empty**, `--pm` and `--dev` are **optional with tier
> defaults**, and `--spec` is a **shortcut, not the shape**. Nothing was added.
> v6's state-machine corrections and surface inventory stand unchanged.

---

## 1. `loop` is a sibling verb of `run`

`run` is a function call: it returns a value and dies with the call. A loop is a
durable object — it has identity, disk state, a lifecycle, and it **owns runs**.
You cannot `stop`, `resume`, or `wait` on a flag. Putting the loop on `run` would
force every lifecycle operation to address "a run that isn't a run."

| | Identity | Owns | Verb |
| --- | --- | --- | --- |
| Run | one `runId`, ends with the turn | nothing | `alln run` |
| Loop | survives the caller, has rounds, resumable | many `runId`s | `alln loop` |

**The verb is the object.**

### Menu_Not_Router permits this, and bills for it

`docs/archive/phases/Menu_Not_Router.md:229-257` kills *duplicate spending
grammars* (`alln team "…"`), not distinct lifecycle verbs:

> "Distinct workflow commands may eventually create runs, but they must represent
> a real product operation — not an alias for direct `run` — and must **declare
> effects and a free twin in `ContractRegistry`**."

Two obligations, both binding:

- **`alln loop start --dry-run` is mandatory** — resolves project, kind, spec,
  both seats, readiness, write policy, and lock state; creates nothing, spends
  nothing (LVC-S08).
- Effects declared in `ContractRegistry` for every `loop` verb.

That closes the "is a second top-level verb allowed" question permanently.

### `alln team` still must not exist

Team is a seating, not a lifetime — it says who is in the chairs, not how long the
thing lives. It stays a modifier (`alln run --team <id>`), and it would collide
with `alln teams` besides.

---

## 2. The grammar

```text
alln run                                    # one turn
alln loop start "<what you want done>" [--spec <path>] [--pm caller|<agent-id>] [--dev <agent-id>] [--dry-run]
alln loop list
alln loop status <loop-id>
alln loop stop <loop-id>                    # terminal, durable, NOT resumable
alln loop resume <loop-id>
alln loop wait <loop-id>                    # disposable waiter; blocks, prints event, exits
alln loop step <loop-id> <message>          # submit the next PM decision
alln loop step <loop-id> --done <summary>   # decision: work is done, end successfully
alln loop pm <loop-id> <occupant>           # reassign the chair
alln teams                                  # manage the noun
alln pair                                   # device pairing ONLY
```

**Everything in brackets is optional. The brief is the only required input.**

### What the founder actually says — this is the spec, not an illustration

v1–v6 derived the grammar from taxonomy and produced something the founder could
not use. v7 derives it from transcript. These are his sentences, verbatim:

| He says | Invocation |
| --- | --- |
| "Set up a loop using alln and have it execute this doc" | `alln loop start "execute this doc" --spec <doc>` |
| "Set up a loop via alln and have a dev and pm execute this doc" | same — naming two agents *is* the default |
| "You are the pm and the dev is grok via grok CLI" | `--pm caller --dev model_grok` |

Two findings that overturned v6:

1. **No sentence contains an attendedness word.** Not "unsupervised," not
   "unattended." What he varies is **casting** — who sits in which chair. `--pm
   caller` is the literal answer to "who's the PM," not a posture in disguise. The
   design was right; v6's *story* about it was wrong, and the wrong story is what
   made it unusable.
2. **He named seats because nothing defaulted, not because he wanted to.**
   `relay`/`pilot` were memorized as a tax. Once seats default, the default
   sentence names nobody — so a required `--pm` would reject his most natural
   request.

**"Setup a loop → then what" = then nothing.** `alln loop start` plus a brief. Any
further word is optional casting he already speaks in plain English.

### The kind slot ships EMPTY

v5/v6 required a `deliver` positional on Fable's argument that an unnamed sole kind
becomes an implicit default. Real, but it costs the founder the first slot he
types on a word that distinguishes nothing today. **Founder ruling: wrong trade for
the one user.** The slot stays empty and reserved. When a second kind exists
(`research`, `review`) it claims the slot under Law 1 and we pay the rename then —
against a grammar people can actually use, which is the only kind worth migrating.

### `--spec` is a shortcut, not the shape

The loop needs **work that takes multiple rounds and produces commits**, not a
document. A spec doc is the common case, never the requirement:

```
alln loop start "fix every failing test until the suite is green"
alln loop start "migrate all call sites off the old catalog loader"
```

`--spec` exists for when the brief would be three paragraphs. **Binding on S03:
brief-only is the headline example everywhere** — menu, help, bootstrap, recipes.
Leading every example with `--spec` makes it read as mandatory, which narrows the
product to people who write spec docs.

### Defaults

| Flag | Default | Source |
| --- | --- | --- |
| `--pm` | Frontier tier | `DefaultModelSettings.swift` (LVC-S07) |
| `--dev` | Balanced tier | same |
| `--spec` | none — the brief carries the work | — |

`caller` is a reserved `--pm` value meaning the live agent session holds the chair.
It is never resolved as a model id.

**Binding on S03 — menu disclosure:**
- `--pm caller` — *useWhen:* "you (this session) review every round and decide the
  next slice." *dontUseWhen:* "not unattended — the loop waits for you to `step` it."
- `--pm <agent-id>` / omitted — *useWhen:* "that agent reviews every round; nobody
  has to watch."

**Binding on §9 — the cold-agent matrix runs the founder's sentences verbatim**,
not synthetic ones. A grammar he cannot reach from plain speech is not shipped.

### "Parked" is prose, not a status — use these names

`RelayState.Status` has exactly five cases (`RelayState.swift:188-199`):
`running`, `done`, `escalated`, `stopped`, `awaitingPM`. **There is no `parked`.**
v5 used "parked" loosely for two different things. Concrete mapping, binding on
every slice:

| Prose | Real statuses | Accepts |
| --- | --- | --- |
| "parked, chair == `caller`" | `awaitingPM` | `step`, `pm <agent-id>`, `stop` |
| "parked, chair == agent" | `escalated`, reconciled-`stopped` | `resume`, `pm caller`, `stop` |
| in flight | `running` | `stop`, `wait` |
| finished | `done`, ceiling-`stopped` | nothing (not resumable) |

`awaitingPM` today is documented as pilot-only because it is the state a live
session rests in between rounds. Under the occupant model it means **the chair
holder owes a decision** — an agent-occupied loop dispatches its own decision
immediately, so it is only *observable* when the chair is `caller`. Same state,
stated without reference to a mode enum.

### Full old → new matrix

Live registry: `ContractRegistry+Milestone1.swift:609-666`, `PairCLI.swift:20-31`,
`PilotCLI.swift:32-37`.

| Today | After |
| --- | --- |
| `pair relay --pm-model X --dev-model Y` | `alln loop start "<brief>"` (seats default) or `--pm X --dev Y` |
| `pair pilot start` | `alln loop start "<brief>" --pm caller` |
| `pair relay-status` / `pair pilot status` | `alln loop status <id>` |
| `pair relay-resume` | `alln loop resume <id>` |
| `pair relay stop` | `alln loop stop <id>` |
| `pair relay adopt` (pilot → spawned) | `alln loop pm <id> <agent-id>` |
| `pair pilot adopt` (spawned → pilot) | `alln loop pm <id> caller` |
| `pair pilot handoff` | `alln loop step <id> <message>` |
| `pair pilot watch` | `alln loop wait <id>` |
| `pair pilot scaffold-handover` | **CLI verb deleted; engine type stays.** `PilotHandoverScaffold.writeRoundFile` is also called automatically by `pilot start` (`PilotCLI.swift:65`) to seed round 1 — `loop start` must keep that auto-seed. Only the manual re-emit verb goes. |
| — (did not exist) | `alln loop list` |
| `pair list\|approve\|revoke\|begin` | **unchanged** — device trust keeps `pair` |

### Flags

| Before | After |
| --- | --- |
| `--pm-model <id>` | `--pm <caller\|agent-id>` |
| `--dev-model <id>` | `--dev <agent-id>` |
| `--relay <id>` | positional `<loop-id>` |
| `--doc <path>` | `--spec <path>` |

`--pm-model` and `--pm` were two flags for one concept: *which model, and is it
spawned at all.* One field answers both — `caller` is a reserved occupant, any
other value is an agent to spawn.

### Both adopts collapse under one verb — but they are NOT symmetric

v5 claimed "preconditions do not change: both still require a parked loop in an
adopt-eligible status." **That was wrong.** Verified in
`RelayCoordinator.swift:596-598,658-661` and `:735-766`:

| `alln loop pm <id> <agent-id>` (was `relay adopt`) | `alln loop pm <id> caller` (was `pilot adopt`) |
| --- | --- |
| Requires chair == `caller` | Requires chair == an agent |
| Eligible: `awaitingPM` **or** `escalated` | Eligible: `escalated` **or** reconciled-`stopped` (`RelayState.isResumable`) |
| **Dispatches** a round — needs `RunService` | **Never dispatches** — relabels three fields and persists |
| Takes the dispatch lock | `static`, no coordinator needed |

Different eligible statuses, different side effects. `awaitingPM` is not even a
legal resting state on the spawned side.

**Ruling:** one verb, two transitions, and the implementer gets the table above as
the spec. `loop pm` validates the *current* chair, then applies that column's
eligibility and effects. **It is not a merge of identical logic** — do not let an
implementer write one code path and assume symmetry. Neither column's
preconditions may be loosened to make them match.

---

## 3. The three naming laws

### Law 1 — a `kind`, when one exists, names what *done* means

The slot is **empty today** (§2). When a second kind of loop arrives it must name
its own terminal condition — `research` (until questions are exhausted), `review`
(until clean) — never a posture, never a mechanism. That is the rule the slot is
being held for.

Until then there is nothing to type. A word that distinguishes nothing is not
worth the first position in the command.

### Law 2 — the chair is an occupant, not a mode

One slot, one word: `pm`. At start it is `--pm <occupant>`; reassignment is the
subcommand `loop pm`. `caller` is a reserved occupant id.

This is what prevents the two configurations from ever becoming two products.
They differ only in a field value — not a verb, not a mode, not a subtree.

### Law 3 — operations are defined against the state machine, never the chair

`step` is the first command that is only *meaningful* for one occupant. Left as a
special case, the grammar accretes more caller-only and spawned-only surface until
the command tree forks.

So `step` is chair-neutral by definition: *submit the PM decision the loop is
waiting for.*

**v6 correction — v5 broke its own law here.** v5 specified the error as
`chair is occupied by <agent-id>`. That keys the error on the **occupant**, which
is exactly what Law 3 forbids. It also described a spawned PM "submitting through
the identical internal operation" — verified: **no such manual-injection path
exists.** A spawned chair's decisions are dispatched automatically inside
`RelayCoordinator`; there is no verb, internal or external, that injects one.

Corrected, and it is simpler than what v5 imagined:

> `step` is accepted **only in `awaitingPM`** — the state where the loop is
> waiting on a decision. Any other status errors on the **status**, reusing the
> existing `PilotRoundError.notAwaitingPM(status:)`
> (`RelayCoordinator.swift:117-135`): *"loop is not awaiting a PM decision
> (status: running)."*

An agent-occupied loop dispatches its own decision and therefore is never
observably in `awaitingPM`, so it rejects `step` **without the CLI ever consulting
the occupant.** Chair-neutrality is a property of the grammar and the error
surface — not a new dispatch path to build. **No manual-injection path is in
scope. Do not build one.**

**Every future loop operation must be defined this way.** This is the law that
keeps the cutover from having to happen again.

### Rejected — do not relitigate

| Proposal | Why it died |
| --- | --- |
| `autopilot \| pilot` as the two kinds | A minimal pair is a closed set of two — the elegance *is* the unextendability. Also commits the family to an aviation metaphor a third kind must satisfy or break. |
| `Managed Loop` vs `Delegated Loop` | Both name properties **both** loops have: the spawned PM manages, and the piloted loop still delegates every slice. |
| `Pair Programming Loop` | Pair programming is synchronous, two present at one keyboard. This is one agent reviewing another's commits after the fact. Also hardcodes *programming* into a loop that runs Design and Copy work. |
| `delegate` as the kind | Every loop delegates to a dev seat, so it names the shared mechanism, not this kind's terminal condition. Reads generic the day `research` ships. |
| `Loop` alone as the feature name | Burns the family name on one member. |
| Empty kind slot + `loop start` | "Start the loop" only parses if there is exactly one. Kind two forces either `--type` (backwards — kind is the discriminator) or a second breaking cut. |
| `--pm spawned \| session` alongside `--pm-model` | Two flags for one concept. Collapsed into `--pm <caller\|agent-id>`. |
| `handoff` as a chair-conditional verb | Law 3. It is the seed of the fork. |
| `set-pm` | `pm` reuses the flag's word. One concept, one word. |
| A required `deliver` kind positional | Costs the founder the first slot he types on a word that distinguishes nothing today. The slot ships empty (§2). |
| Required `--pm` / `--dev` | Rejects the founder's most natural sentence, which names nobody. Both default by tier (§2). |
| Any attendedness word (`unsupervised`, `unattended`, `away`, `live`) after `loop` | No founder sentence contains one. He varies **casting**, not posture. Adding a mode word re-creates the `relay`/`pilot` tax in new spelling. |

### The `delegate` collision was a false premise

Doc Review objected that a `delegate` kind collides with locked one-shot
`Delegate`. Verified 2026-07-30 — `delegate` does not exist in the CLI: **zero**
occurrences in `alln menu --json`, no verb, no flag, no JSON key, no
`CommandSpec`. It is a doc-layer word whose own entry
(`Product_Vocabulary.md:21`) says the UI label is "Send to team," plus one search
alias at `HelpTopicRegistry.swift:191`. Moot under v5, which names the kind
`deliver` anyway.

### UI naming

Mac feature name follows the kind: **Delivery Loop**. The app exposes no chair
choice at all (LVC-S06), so it needs no second word.

**Do not coin a UI noun for the spawned chair.** Nothing displays it. Every
candidate — Assigned, Managed, Auto — is a term invented for a surface that does
not exist, which is how a fourth vocabulary gets created. `Auto` is doubly out; it
is taken by tier routing (`DefaultModelSettings`).

Where a human string must describe the chair, use a **phrase, not a term**: "its
own PM" / "you're the PM."

---

## 4. Supersedes / wire ruling

`docs/workflows/Product_Vocabulary.md` rules the **opposite** of this packet in
three places, all superseded:

| Line | Current | Disposition |
| --- | --- | --- |
| 27 | "**Loop** \| Mac composer noun … CLI stays `pair relay*` and is **never** renamed to `pair loop`." | **Superseded.** The rule deliberately kept the human word and the machine word out of sync. They converge. |
| 29 | "**Pilot** \| … CLI-only, always. The Mac app is never the PM seat and offers no Pilot entry." | **Kept, re-expressed.** `--pm caller` is a value the app does not expose. |
| 51–53 | "Teach `pair relay` / `pair relay stop` / `pair relay-status`; never invent `pair loop`." | **Superseded.** Replace with §2. Founder Stop is `alln loop stop` (durable `stopped`, reason `founder stopped`, PM Turn written, not resumable) — still never `alln kill`, which is process machinery. |

### Wire ruling

v1–v3 ruled "CLI verbs move; wire keys never do." That was scope control posing as
a principle. Corrected:

> **Rename a wire word when it is *wrong* or *agent-readable*. Leave it when it is
> merely internal-and-accurate.** Zero users: a wrong word costs more to keep than
> to fix, and there is no migration to hedge against.

| Wire word | Verdict |
| --- | --- |
| `PMMode` enum (`spawned \| external`) | **Deleted.** The chair is an occupant id with `caller` reserved. `external` was wrong (external to *what*?) and `spawned` becomes redundant — an occupant either is `caller` or is an agent. The codebase already faked this: `RelayState.swift:293` stamps a sentinel `pmModelId` for external mode. The sentinel becomes the real model. **Blast radius is wider than v5 said — see below.** |
| `--relay <id>` | **Deleted** → positional `<loop-id>`. |
| `kind: relay\|pilot` in `alln ps` / journals | **Renamed → `loop`.** Agent-readable: an agent that ran `alln loop start` cannot then read a noun the CLI does not have. |
| `relay.needs_answer` event id | **Renamed → `loop.needs_answer`.** Same reason. |
| `RelayCoordinator`, `RelayState`, `RelayCLI`, `RelayVerdict`, `Relays/` dir | **Renamed → `Loop*` / `Loops/` — but in LVC-S09**, a separate slice. Internal *and* accurate; the rename has zero semantic content and a large mechanical diff. Mixing a repo-wide symbol sweep into a contract cut makes the reviewable diff unreviewable, which project law forbids. |

#### Deleting `PMMode` touches more than `RelayState`

v5 discussed only the `RelayState` decode break. Verified call sites that must all
change in LVC-S02:

| Site | What it does |
| --- | --- |
| `RelayJSON.swift:19,53,109` | `pmMode: String` with default `"spawned"` — a **public wire type**, not internal |
| `PMTurnJSON.swift:31,47,62` | `pmMode: String?` — same |
| `ProcessOwnershipSurface.swift:374,441`, `ProcessOwnershipGarbageCollector.swift:167` | `relay.pmMode == .external ? "pilot" : "relay"` — **this ternary is what actually produces the `kind` strings** §4 renames to `loop`. After the enum is deleted it has no legal input. It is a separate edit, not implied by "rename `kind`". |
| `RelayThreadProjector.swift:137,148` | branches on `.external` to suppress the sentinel model id in thread titles |
| `docs/generated/alln/ownership-gc.schema.json:24-25`, `ownership-ps.schema.json:169-170`, `team-run.schema.json:804` | literal `"relay"`/`"pilot"` enum values — regeneration only fixes these **after** the source above changes |
| ~60 assertions across `RelayCoordinatorTests`, `PilotCoordinatorTests` (incl. `:572` legacy-decode test), `RelayAdoptTests`, `RelayJSONTests:164,173,183` | fixtures |

**Decode break is accepted, not migrated.** On-disk `RelayState` carrying
`"pmMode":"external"` will not decode, and `RelayJSON`/`PMTurnJSON` consumers see
the field disappear. Pre-user, so no shim and no dual-read —
foundation-first, build the correct final model now. It fails **loud**, never
silently. Operational cost, and it goes in the release note: **finish or `stop`
any in-flight loop before upgrading.**

---

## 5. Execution

S00–S08 land as **one merge unit**. v1 planned S00 as a standalone commit ahead of
the binary, which would have the SSOT teaching `alln loop …` while the shipped CLI
still only had `pair relay` — recreating the exact word-split this cutover exists
to kill.

**LVC-S00 — Vocabulary, and where each law lives.** Rewrite
`Product_Vocabulary.md` §Human layer and §Loop-vs-Pilot-vs-Relay per §4. No open
rulings remain. The three laws do **not** all go to the same home:

| Law | Durable home |
| --- | --- |
| 1 — `kind` names what *done* means | `Product_Vocabulary.md` — it governs future naming |
| 2 — the chair is an occupant, not a mode | **Code.** `Product_Vocabulary.md` gets the word `pm`/`caller`; the invariant is enforced by there being no mode enum to violate |
| 3 — operations are defined against the state machine, never the chair | `Product_Vocabulary.md` — it constrains every future loop verb |

Nothing else in this packet is durable law. §2's matrix, §6's surface inventory,
and §7's review dispositions are **working notes** and die with the archive.

**LVC-S01 — Retire the old vocabulary.** Add `pair relay`, `pair relay-status`,
`pair relay-resume`, `pair pilot`, `relay adopt`, `--relay`, `--pm-model`,
`--dev-model` to `RetiredVocabulary.swift`. **Also widen the gate** — see below.
`RetiredVocabularyTests.swift:264` currently lists `"relay"` in its *allowed* flag
names and `:54` treats `pair_relay(` as current — both assertions must flip, or
the test will contradict the new retired list.

**LVC-S02 — `LoopCLI` + wire renames.** The full §2 grammar. Retired verbs error
naming their replacement — hard cutover, no aliases. Deletes `PMMode` (blast
radius table in §4); renames `kind` and the notification event id; rewrites the
`ProcessOwnershipSurface` / GC `kind` ternary.

> **New work S02 must not miss:** `alln loop status` unifies two waiters that are
> **not** equivalent today. `relay-status` accepts `--wait-for parked|terminal`
> (`RelayCLI.swift:189-206`); `pilot status` accepts **only `parked`** and
> explicitly rejects `terminal` (`PilotCLI.swift:611-628`). One `loop status`
> means adding terminal-wait support to the caller-chair path. v5 called this
> "just a flag"; it is a build item.

> **`loop pm` is two transitions, not one merged code path** (§2 table). Validate
> the current chair, then apply that column's eligibility and effects. Do not
> write it as symmetric.

**LVC-S03 — Agent-facing surfaces.** `MenuCatalog.swift`, `HelpTopicRegistry.swift`
(topic `pm_relay`, `:221-275`), `Bootstrap.swift`, `TeachingSnippet.swift`,
`RecipeCatalog` + the four recipe bodies (§6).

**LVC-S04 — Living docs.** `AGENTS.md` routing table (four rows),
`docs/phases/README.md`, `docs/operations/`, `Product_Vocabulary.md`.

**Live phase docs must be rewritten, not header-noted.** These are being worked
from, so a "renamed" banner is not enough:
- `docs/phases/Work_Recovery_And_PM_Continuity.md` — 11+ live references
  (`:11,104-105,142,193-194,235-266,342`), including `--pm-model` on resume, which
  this cutover renames
- `docs/phases/atl/ATL_S01_S02_execution.md:51,56`
- `docs/phases/closeout/Open_Items_Closeout.md:108,112`

**Do not rewrite `docs/archive/phases/`** — that makes the record lie about what
shipped when. A one-line header note (`relay → alln loop, renamed 2026-07-30`) on
`PM_Relay.md`, `Pilot_Relay.md`, `Round_Survives_The_Caller.md`,
`Agent_Team_Loop.md` is enough **for archived docs only**.

**LVC-S05 — Version.** `contractVersion` **6.13.0 → 7.0.0**, `binaryVersion`
**0.10.7 → 0.11.0** — **two files**: the constant *and*
`VersionIdentityTests.swift:36`, which hardcodes the literal `"0.10.7"`.
Regenerate `docs/generated/alln/*` via
`alln dev export-contracts` — generated output, never hand-edited. Release note
carries the decode break (§4).

**LVC-S06 — Mac app.** Popover offers **Delivery Loop**, full stop. The chair
choice is not shown, not shown-disabled, not mentioned — there is no live session
behind a modal. Code sites in §6.

**LVC-S07 — Seat defaults.** PM = **Frontier** tier, dev = **Balanced** tier via
the tier SSOT (`DefaultModelSettings.swift`). No hardcoded model ids — that is what
lets a down CLI route around itself instead of the sheet defaulting to a seat that
cannot run. `--pm` stays required in the CLI; the sheet fills it.

**LVC-S08 — The free twin.** `alln loop start --dry-run` per §1. Declare effects
for every `loop` verb in `ContractRegistry`. Non-optional.

**LVC-S09 — Symbol sweep (separate slice, after S00–S08).** `Relay*` → `Loop*`,
`Relays/` → `Loops/`. Pure mechanical rename. Behavior first, sweep second.

**LVC-S10 — Promote and archive this packet.** `docs/phases/` is **never SSOT**
(`docs/phases/README.md:11-13,29-31`). Once S00–S09 land: confirm the three laws
are in their homes per S00, then move this file to `docs/archive/phases/` and
update the phase board. A packet left in `phases/` with a LOCKED banner is exactly
the "shipped banner means promote + archive is overdue" failure the router warns
about — and §6's surface inventory is the part most likely to rot into a
pseudo-SSOT if it lingers.

### Widen the gate — it is narrower than it looks

The deny-list red is real but does **not** find everything:

- `livingDocDenyPatterns` is a **separate list** from the term deny-list
  (`RetiredVocabulary.swift:119-134`).
- `scripts/check.sh:93-99` greps **only** `docs/operations/*.md` plus two named
  files. Not `AGENTS.md`, not `Product_Vocabulary.md`, not `docs/phases/README.md`,
  not recipe bodies — all of which carry `pair relay` today.
- Bootstrap already avoids teaching `pair pilot` (`BootstrapTests.swift:59-60`).

So S01 must add the new phrases to `livingDocDenyPatterns` **and** extend
`check.sh` scan roots to `AGENTS.md`, `docs/workflows/*.md`, `docs/phases/*.md`,
and `Resources/Recipes/*.md`. Widening the gate is in scope. **Narrowing it to
pass never is** — allowlists are where these gates die (archived
`CLI_Agent_Surface_Fidelity.md`).

---

## 6. Surfaces (verified by grep, 2026-07-30)

Truth owner: `Product_Vocabulary.md` for the words; `LoopCLI` + `MenuCatalog` +
`ContractRegistry` for the surface.

**Mac app — keys off the verb:**
- `RelayDetachedLauncher.swift:103` — hardcoded `"pair", "relay"` argv
- `RelayLaunchViewModelTests.swift:154,158` — asserts that argv
- `RelayStatusLoader.swift` — `pair relay-status`
- `RoutingComposer.swift` — composer tab copy

**Product-facing strings:**
- `RelayThreadProjector.swift:271` — `"PM Relay"` / `"PM Relay: …"` thread titles
  (and `:137,148`, which branch on `PMMode`)
- `NotificationDeliveryFilter.swift:99-102` — `"PM Relay needs an answer"`; **also
  `:46,122,125,127`** — "PM Relay stopped", "Relay worker stream stalled", and an
  embedded next-action naming the old `pair pilot status` invocation
- `ContractRegistry+Milestone1.swift:742` — `serve` summary teaches four old verbs
- `ContractRegistry+Milestone1.swift:1181,1183` — `ErrorSpec.agentAction` for
  `RELAY_INVALID_STATE` / `RELAY_ALREADY_ACTIVE`
- `PilotCLI.swift:85,1149-1180,1298-1312,1376` — **runtime-formatted** next-action
  and error strings, a surface distinct from `ContractRegistry.ErrorSpec`. e.g.
  *"relay is not a Pilot relay (pmMode != external) — use the old `pair relay`
  verb…"* (prefixed with the binary name at runtime).
  Enumerated here because v5 gestured at these generically and they are real work.
- `RelayCoordinator.swift` — same class of embedded strings

**Agent discovery / teaching surfaces — the full list:**

| Surface | File | Covered by |
| --- | --- | --- |
| `alln menu --json` | `MenuCatalog.swift` — actions, commands, recipes, defaults, `detailTemplate`, `effectProfiles` | S03 |
| `alln help` / `help search` / `help get` | `HelpTopicRegistry.swift` — topic `pm_relay` **`:221-289`** (v5 said `:275`; the declaration including `relatedCommandNames` / `schemaRefs` / `errorRefs` runs to `:289`), plus the `delegate` alias at `:191` | S03 |
| `alln doctor` / `doctor explain` | `ErrorSpec.agentAction` + recovery codes, `ContractRegistry+Milestone1.swift:1181,1183` | S03 |
| `alln doctor handoff` | mailbox liveness copy referencing relay verbs | S03 |
| `alln bootstrap` | `Bootstrap.swift`, `TeachingSnippet.swift`, `GlobalTeachingInstaller` | S03 |
| `ContractRegistry` CommandSpecs | **`:540-606` (`pair relay`, `relay-status`, `relay-resume`, `relay adopt`, `relay stop` + FlagSpecs)** — v5 cited only `:609-666` (pilot) and never named the relay block | S02/S03 |
| `docs/generated/alln/*` | generated — regenerate after the source enums change | S05 |

**Recipes** (agent-facing, not gate-covered) — **seven, not four**:
`keep-working-while-im-away.md`, `get-another-model-to-implement-this.md`,
`recover-a-run-that-lost-its-terminal.md`,
`challenge-this-decision-before-i-commit.md`, and the three v5 missed:
`ask-several-models-and-compare.md`, `get-sols-take-without-changing-files.md`,
`use-a-specific-model-without-silent-substitution.md`

**Living docs carrying `pair relay|pilot` outside archive/:** `AGENTS.md`,
`Product_Vocabulary.md`, `docs/phases/README.md`, `Work_Recovery_And_PM_Continuity.md`,
`atl/ATL_S01_S02_execution.md`, `closeout/Open_Items_Closeout.md`,
`operations/debugger/DEBUGLOG.md`, `docs/generated/alln/help_alln_cli_spec.md`
(generated — regenerate).

Lie-prone layers: `RetiredVocabulary` allowlists; help text and teaching snippets,
which have drifted from shipped verbs before; `ContractRegistry+Milestone1.swift:1042`,
which describes `pair` as pairing-only while it also dispatches loop verbs.

iOS impact: device pairing keeps `alln pair` and gets it to itself. **Verify no
remote/control path teaches `pair relay*`** before closeout — do not assert impact
from silence. Driver/protocol impact: none. Auth/privacy impact: none.

---

## 7. Review disposition

**Doc Review — Cursor Grok 4.5, 2026-07-30** (all findings verified against the repo):

| Finding | Verified | Disposition |
| --- | --- | --- |
| `--team` cross-apply "proof" is fiction (`RelayCLI.swift:396-397`) | ✅ | Accepted — claim deleted |
| "Verbs are lifetimes, nouns are seatings" breaks on `pair`, `teams`, loop's own lifecycle ops | ✅ | Accepted — never promoted; §1 argues from the object model instead |
| Menu_Not_Router permits the sibling verb but demands effects + free twin | ✅ `:229-257` | Accepted — LVC-S08 |
| Verb map missing 5 pilot subcommands | ✅ `PilotCLI.swift:32-37` | Accepted — §2 matrix |
| Two adopts flip in opposite directions | ✅ `ContractRegistry:586,658` | Accepted, then **dissolved** — one `loop pm <id> <occupant>` |
| Gate does not scan the docs claimed (`check.sh:93-99`) | ✅ | Accepted — S01 widens it |
| Vocabulary SSOT ahead of binary teaches phantom verbs | ✅ | Accepted — one merge unit |
| Mac app keys off the verb | ✅ | Accepted — §6 |
| `delegate` collides with locked `Delegate` | ❌ **false premise** | Rejected — zero CLI occurrences; moot under `deliver` |
| Version 7.0.0 / 0.11.0 correct | ✅ | No change |
| `relay-status` + `pilot status` collapse is lie-prone | ✅ | Accepted, then resolved — one object, one `status`; parked-vs-terminal is `--wait-for`, a flag |

**Implementation-readiness pass — Sonnet 5, 2026-07-30** (names locked; every
finding verified against the repo before acceptance):

| Finding | Verified | Disposition |
| --- | --- | --- |
| The two adopts do **not** share preconditions — different eligible statuses, and one dispatches while the other only relabels | ✅ `RelayCoordinator.swift:596-598,658-661` vs `:735-766` | **Accepted — v5 was factually wrong.** §2 now carries the real two-column table; `loop pm` is one verb over two transitions, not one code path. |
| `step` chair-neutrality rests on a spawned-side manual-injection path that does not exist | ✅ no such verb, internal or external | **Accepted — and it exposed that v5 broke its own Law 3.** The error was keyed on the occupant; it is now keyed on the status. No injection path is in scope (§3). |
| `parked` is not a real status | ✅ `RelayState.swift:188-199` — five cases, no `parked` | **Accepted** — §2 has a concrete prose→status→accepts table. |
| `pilot status` rejects `--wait-for terminal`; the collapse is new work | ✅ `PilotCLI.swift:611-628` vs `RelayCLI.swift:189-206` | **Accepted** — called out in S02. |
| `PMMode` reaches public wire types + the ownership `kind` ternary | ✅ `RelayJSON:19,53,109`, `PMTurnJSON:31`, `ProcessOwnershipSurface:374,441`, GC`:167` | **Accepted** — blast-radius table in §4. |
| `scaffold-handover`'s engine type is also called by `pilot start` | ✅ `PilotCLI.swift:65` | **Accepted** — verb dies, auto-seed stays. |
| Packet never schedules its own archival; `phases/` is never SSOT | ✅ `docs/phases/README.md:11-13,29-31` | **Accepted** — LVC-S10; S00 says which law goes where. |
| Surfaces missed: 3 recipes, help topic to `:289`, ContractRegistry `:540-606`, extra `NotificationDeliveryFilter` lines, generated schema enums, live phase docs | ✅ | **Accepted** — §6 and S04. |
| `VersionIdentityTests:36` and `RetiredVocabularyTests:54,264` pin old values | ✅ | **Accepted** — S05, S01. |

**Cold first-principles redesign — Fable 5, 2026-07-30** (no repo docs read, no
anchoring on the draft). Converged independently on the sibling verb, the object
model, and naming the kind now. Three improvements adopted whole: the chair as an
occupant (Law 2), chair-neutral operations (Law 3), and kind-names-terminal-
condition (Law 1). Also added `loop list`, which the draft lacked.

---

## 8. Deferred — the Delivery Loop sheet (separate packet)

Approved in principle, **not in this cutover.** The rename touches contract, menu,
help, bootstrap, and docs; the sheet touches layout and copy. Land the name first.

**The bug is two homes.** Today "Loop" is a composer mode that hijacks Return,
*and then* a modal opens and asks for the brief again. Pick one home: **the sheet,
opened immediately on select.** Carry composer text into the brief field — decide
explicitly whether it is consumed or copied; if copied and left behind, the user
can send it twice. The "brief once, then Return opens the launch sheet" tooltip
becomes unnecessary, which is the point: a tooltip explaining what a keystroke will
do is evidence the interaction should not exist.

**Shape — one required field, one row of defaults, one optional field, one button:**

1. **Brief teaches by example.** Label "What should this loop deliver?"; helper
   "Write a short note to your PM. It will hand out the work one slice at a time
   until everything is delivered."; placeholder *"Execute the spec in
   docs/phases/110-connect-resume.md — build each slice, prove it works, then move
   to the next."*
2. **Collapse the seat pickers** to two compact dropdowns on one row, pre-filled by
   tier (LVC-S07). Helper text: "PM — reviews each round, decides what's next" /
   "Dev — builds and commits."
3. **Spec optional** — "Point at a spec (optional)". Do **not** build repo-path
   detection from the brief; inference is scope creep and will guess wrong.
4. **Footer in plain words.** "Runs unattended. Your PM reviews the actual commits
   after every round and stops when the work is delivered."

**Constraint:** a Delivery Loop is *not* rare — it is a co-equal hero loop,
all-day, high-frequency. Design for the tenth launch, not the first: remember last
seats and spec so the repeat path is type-one-field-and-go.

---

## 9. Proof

Works Test, from a clean shell:
- `alln loop start "<brief>"` — **no other flags** — lands a real commit with defaulted seats
- `--spec <path>` variant lands a real commit
- `--pm caller` → `step` → `status` (`awaitingPM`) → `wait`
- `loop pm <id> caller` and `loop pm <id> <agent-id>` both flip a parked loop
- `step` errors on the **status** (`notAwaitingPM`) for an agent-occupied loop — never on the occupant
- `stop` is durable and not resumable; `resume` works on a parked loop
- `list` shows them
- every old verb, `--relay`, `--pm-model`, `--dev-model` hard-error naming their replacement
- `alln pair approve` still works
- the Mac detached launcher spawns the new argv

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

Fixtures to update — **v5 listed three; the real set is ~12 files.** The Works
Test's `--filter Relay` / `--filter Pilot` surfaces them as compile failures, so
nothing is silently missed, but S02 must be scoped for the real diff:
contract export, `ContractRegistryTests` command-name list,
`VersionIdentityTests.swift:36`, `RetiredVocabularyTests.swift:54,264`,
`RelayCLITests.swift` (~45 literal occurrences), `DetachedDispatchTests.swift`
(~17), `RelayCoordinatorTests`, `PilotCoordinatorTests` (incl. `:572` legacy
decode), `RelayAdoptTests`, `RelayJSONTests:164,173,183`,
`ServeAutoLaunchCLITests`, `ProcessOwnershipSurfaceTests`, `CLIHelpDriftTests`,
`JSONStreamLawTests`, `UnknownFlagTests`, Mac `RelayDetachedLauncher` /
`RelayStatusLoader` tests.

**The cold-agent matrix is non-optional.** `menu-not-router` /
`scripts/menu_not_router_eval.py` must be extended to cover the `loop` family —
and it runs the founder's own sentences verbatim (§2 table): "Set up a loop using
alln and have it execute this doc" must produce a defaulted-seat invocation, and
"You are the pm and the dev is grok via grok CLI" must produce
`--pm caller --dev model_grok`. No waiver.

Done when: no product surface an agent or human can read says `pair relay`,
`pair pilot`, `relay-resume`, `--relay`, or `external`; `alln loop` is the only way
to start a multi-round thing; `alln loop start "<brief>"` works with no other flags; `--dry-run` exists and spends nothing;
contract 7.0.0 / binary 0.11.0 ship together; the Mac popover offers Delivery Loop;
**and this packet is archived to `docs/archive/phases/` with the three laws
promoted (LVC-S10).**

## 10. Decisions log — nothing is open

| Question | Ruling |
| --- | --- |
| Sibling verb or flag on `run`? | **Sibling verb.** The verb is the object (§1). |
| Does that violate Menu_Not_Router? | **No** — it bills effects + a free twin (§1). |
| Two kinds (`delegate`/`pilot`) or one? | **One kind, `deliver`.** The chair is not a kind (§3). |
| Kind slot empty or named today? | **EMPTY (v7).** v5/v6 said named; overturned by founder ruling — a word that distinguishes nothing is not worth the first slot. |
| How is the chair expressed? | `--pm <caller\|agent-id>`, **optional, Frontier default**; reassignment is `loop pm` (§3, Law 2). |
| Two adopts? | **One operation** — `loop pm <id> <occupant>` (§2). |
| `handoff`? | **`step`, chair-neutral** (§3, Law 3). |
| Collapse `relay-status` + `pilot status`? | **Yes** — one object, one `status`; parked-vs-terminal is a flag. |
| `--relay` flag? | **Deleted** → positional `<loop-id>` (§4). |
| `alln ps` `kind: relay`? | **Renamed → `loop`** — agent-readable (§4). |
| `relay.needs_answer`? | **Renamed → `loop.needs_answer`** (§4). |
| `PMMode.external`? | **Enum deleted** — the chair is an occupant id (§4). |
| Migration shim for the decode break? | **None.** Pre-user, fails loud, release note says finish or stop in-flight loops first (§4). |
| Swift symbol sweep? | **Yes, LVC-S09 — separate slice** (§4). |
| Mac feature name? | **Delivery Loop** (§3). |
| First future kind? | Must name a terminal condition (`research`, `review`). **None authorized** — do not build speculative kind machinery. |
| Is `--spec` required? | **No.** The brief carries the work; `--spec` is a shortcut. Brief-only is the headline example everywhere (§2). |
| Is there a mode word? | **No, and never.** No founder sentence has one (§2, §3). |
| Is `loop pm` one code path? | **No** — one verb, two transitions with different eligibility and effects (§2 table). |
| Does `step` need a spawned-side injection path? | **No.** `step` is accepted only in `awaitingPM` and errors on the *status*. Do not build injection (§3, Law 3). |
| Where does this packet end up? | **`docs/archive/phases/`**, after the three laws are promoted (LVC-S10). |
