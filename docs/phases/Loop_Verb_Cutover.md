# Loop Verb Cutover — `alln loop`

Status: **v5 — LOCKED 2026-07-30. Grammar final, no open questions. Not started.**
Owner: Founder ruling; implementer TBD
Updated: 2026-07-30

Founder intent: the multi-round PM↔dev feature is named things nobody says.
`relay` is confusing, `pilot` is fine but hidden, and `pair` — the word the CLI
organizes them under — is a word the founder has never once uttered when asking
for one. Rename now, while it is cheap, and give the category a shape that holds
the loops we have not built yet.

Product value: one sayable word for a whole class of work, and one vocabulary
across CLI, JSON, disk, and UI.

Trusted workflow slice: `alln loop start deliver "<brief>" --spec <path> --pm
<agent> --dev <agent>` runs unattended until the work is delivered, reviewing real
commits every round. The Mac composer does the same thing behind one sheet.

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
alln loop start <kind> <brief> [--spec <path>] --pm <occupant> --dev <agent-id> [--dry-run]
alln loop list
alln loop status <loop-id>
alln loop stop <loop-id>                    # terminal, durable, NOT resumable
alln loop resume <loop-id>
alln loop wait <loop-id>                    # disposable waiter; blocks, prints event, exits
alln loop step <loop-id> <message>          # submit the next PM decision
alln loop step <loop-id> --done <summary>   # PM decision: delivered, end successfully
alln loop pm <loop-id> <occupant>           # reassign the chair; loop must be parked
alln teams                                  # manage the noun
alln pair                                   # device pairing ONLY
```

- `<kind>` — today the only value is **`deliver`**. Required positional, never
  defaulted (§3).
- `<occupant>` — **`caller`** (the live agent session holds the chair) or a
  canonical agent id (alln spawns that agent into it).
- `--pm` is **required**. No silent default for a cold agent to guess wrong.

### Full old → new matrix

Live registry: `ContractRegistry+Milestone1.swift:609-666`, `PairCLI.swift:20-31`,
`PilotCLI.swift:32-37`.

| Today | After |
| --- | --- |
| `pair relay --pm-model X --dev-model Y` | `alln loop start deliver … --pm X --dev Y` |
| `pair pilot start` | `alln loop start deliver … --pm caller --dev Y` |
| `pair relay-status` / `pair pilot status` | `alln loop status <id>` |
| `pair relay-resume` | `alln loop resume <id>` |
| `pair relay stop` | `alln loop stop <id>` |
| `pair relay adopt` (pilot → spawned) | `alln loop pm <id> <agent-id>` |
| `pair pilot adopt` (spawned → pilot) | `alln loop pm <id> caller` |
| `pair pilot handoff` | `alln loop step <id> <message>` |
| `pair pilot watch` | `alln loop wait <id>` |
| `pair pilot scaffold-handover` | **deleted** — a chair-specific helper the neutral `step` removes the need for. If a real need survives, it is internal, not a verb. |
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

### Both adopts collapse

They were never two operations. They are one — **reassign the chair** — with the
target named explicitly. `alln loop pm <id> caller` ⇄ `alln loop pm <id> <agent-id>`.
Preconditions do not change: both still require a parked loop in an
adopt-eligible status. This is a rename plus a merge, never a loosening.

---

## 3. The three naming laws

### Law 1 — `kind` names what *done* means

`deliver` = runs until the work is delivered. Future kinds name their own terminal
condition: `research` (until questions are exhausted), `review` (until clean).
That is what keeps the slot coherent.

**The kind is required today, with only one value.** An unnamed sole kind becomes
"the implicit default" the moment a second arrives — and under a no-aliases rule
that means renaming on-disk state and menu ids later. Name it now; pay once.

### Law 2 — the chair is an occupant, not a mode

One slot, one word: `pm`. At start it is `--pm <occupant>`; reassignment is the
subcommand `loop pm`. `caller` is a reserved occupant id.

This is what prevents the two configurations from ever becoming two products.
They differ only in a field value — not a verb, not a mode, not a subtree.

### Law 3 — operations are defined against the state machine, never the chair

`step` is the first command that is only *meaningful* for one occupant. Left as a
special case, the grammar accretes more caller-only and spawned-only surface until
the command tree forks.

So `step` is chair-neutral by definition: *submit a PM decision into the loop.* A
spawned PM submits through the identical internal operation; the CLI errors
uniformly (`chair is occupied by <agent-id>`) when the caller does not hold it.

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
| `PMMode` enum (`spawned \| external`) | **Deleted.** The chair is an occupant id with `caller` reserved. `external` was wrong (external to *what*?) and `spawned` becomes redundant — an occupant either is `caller` or is an agent. The codebase already faked this: `RelayState.swift:293` stamps a sentinel `pmModelId` for external mode. The sentinel becomes the real model. |
| `--relay <id>` | **Deleted** → positional `<loop-id>`. |
| `kind: relay\|pilot` in `alln ps` / journals | **Renamed → `loop`.** Agent-readable: an agent that ran `alln loop start` cannot then read a noun the CLI does not have. |
| `relay.needs_answer` event id | **Renamed → `loop.needs_answer`.** Same reason. |
| `RelayCoordinator`, `RelayState`, `RelayCLI`, `RelayVerdict`, `Relays/` dir | **Renamed → `Loop*` / `Loops/` — but in LVC-S09**, a separate slice. Internal *and* accurate; the rename has zero semantic content and a large mechanical diff. Mixing a repo-wide symbol sweep into a contract cut makes the reviewable diff unreviewable, which project law forbids. |

**Decode break is accepted, not migrated.** On-disk `RelayState` carrying
`"pmMode":"external"` will not decode. Pre-user, so no shim and no dual-read —
foundation-first, build the correct final model now. It fails **loud**, never
silently. Operational cost, and it goes in the release note: **finish or `stop`
any in-flight loop before upgrading.**

---

## 5. Execution

S00–S08 land as **one merge unit**. v1 planned S00 as a standalone commit ahead of
the binary, which would have the SSOT teaching `alln loop …` while the shipped CLI
still only had `pair relay` — recreating the exact word-split this cutover exists
to kill.

**LVC-S00 — Vocabulary.** Rewrite `Product_Vocabulary.md` §Human layer and
§Loop-vs-Pilot-vs-Relay per §4. Add the three laws from §3. No open rulings remain.

**LVC-S01 — Retire the old vocabulary.** Add `pair relay`, `pair relay-status`,
`pair relay-resume`, `pair pilot`, `relay adopt`, `--relay`, `--pm-model`,
`--dev-model` to `RetiredVocabulary.swift`. **Also widen the gate** — see below.

**LVC-S02 — `LoopCLI` + wire renames.** The full §2 grammar. Retired verbs error
naming their replacement — hard cutover, no aliases. Deletes `PMMode`; renames
`kind` and the notification event id.

**LVC-S03 — Agent-facing surfaces.** `MenuCatalog.swift`, `HelpTopicRegistry.swift`
(topic `pm_relay`, `:221-275`), `Bootstrap.swift`, `TeachingSnippet.swift`,
`RecipeCatalog` + the four recipe bodies (§6).

**LVC-S04 — Living docs.** `AGENTS.md` routing table (four rows),
`docs/phases/README.md`, `docs/operations/`, `Product_Vocabulary.md`. **Do not
rewrite `docs/archive/phases/`** — that makes the record lie about what shipped
when. A one-line header note (`relay → alln loop, renamed 2026-07-30`) on
`PM_Relay.md`, `Pilot_Relay.md`, `Round_Survives_The_Caller.md`,
`Agent_Team_Loop.md` is enough.

**LVC-S05 — Version.** `contractVersion` **6.13.0 → 7.0.0**, `binaryVersion`
**0.10.7 → 0.11.0**. Regenerate `docs/generated/alln/*` via
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
- `NotificationDeliveryFilter.swift:99-102` — `"PM Relay needs an answer"`
- `ContractRegistry+Milestone1.swift:742` — `serve` summary teaches four old verbs
- `ContractRegistry+Milestone1.swift:1181,1183` — `ErrorSpec.agentAction` for
  `RELAY_INVALID_STATE` / `RELAY_ALREADY_ACTIVE`
- `PilotCLI.swift` / `RelayCoordinator.swift` — embedded next-action strings

**Recipes** (agent-facing, not gate-covered): `keep-working-while-im-away.md`,
`get-another-model-to-implement-this.md`, `recover-a-run-that-lost-its-terminal.md`,
`challenge-this-decision-before-i-commit.md`

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
- `alln loop start deliver "<brief>" --spec <path> --pm <agent> --dev <agent>` lands a real commit
- `--pm caller` → `step` → `status` (parked) → `wait`
- `loop pm <id> caller` and `loop pm <id> <agent-id>` both flip a parked loop
- `step` errors uniformly with `chair is occupied by <agent-id>` when the caller does not hold it
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

Fixtures to update: contract export, `ContractRegistryTests` command-name list,
Mac `RelayDetachedLauncher` / `RelayStatusLoader` unit tests.

**The cold-agent matrix is non-optional.** `menu-not-router` /
`scripts/menu_not_router_eval.py` must be extended to cover the `loop` family —
specifically whether a cold agent reaches for `--pm caller` rather than hunting a
`pilot` verb that no longer exists. No waiver.

Done when: no product surface an agent or human can read says `pair relay`,
`pair pilot`, `relay-resume`, `--relay`, or `external`; `alln loop` is the only way
to start a multi-round thing; `alln loop start --dry-run` exists and spends nothing;
contract 7.0.0 / binary 0.11.0 ship together; the Mac popover offers Delivery Loop.

## 10. Decisions log — nothing is open

| Question | Ruling |
| --- | --- |
| Sibling verb or flag on `run`? | **Sibling verb.** The verb is the object (§1). |
| Does that violate Menu_Not_Router? | **No** — it bills effects + a free twin (§1). |
| Two kinds (`delegate`/`pilot`) or one? | **One kind, `deliver`.** The chair is not a kind (§3). |
| Kind slot empty or named today? | **Named.** An unnamed sole kind becomes an implicit default (§3, Law 1). |
| How is the chair expressed? | `--pm <caller\|agent-id>`; reassignment is `loop pm` (§3, Law 2). |
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
