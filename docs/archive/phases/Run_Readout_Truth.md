# Run Readout Truth — one screen, one status, no plumbing

Status: **CLOSED 2026-08-08 — S02/S03/S04 shipped, cold-agent gate passed,
S01 dropped as unnecessary. Law promoted to `One_Run_Surface.md`
§"What the terminal snapshot must say". ARCHIVED.**
Owner: AllnighterCore (`TeamRunJSONMapper`, `LeadCallParser`, `TeachingSnippet`,
`RunService` settle path, CLI `show`)
Created: 2026-08-08 · Closed: 2026-08-08
Origin: PM incident 2026-08-08 — a completed Spec Review with a **Ready** verdict
was read as a crashed run. Founder: *"why were you just sitting there and doing
nothing… I have tried to improve alln 10 times and this still happens."*

Companion packets:
[`One_Run_Surface.md`](One_Run_Surface.md) — **binding constraint**, owns the
three-key `observation` law (`:30–31`); this packet may not silently break it.
[`Probe_Freshness.md`](Probe_Freshness.md) (sibling truth defect on selection
surfaces), [`Ambient_Dirty_Run_Outcome.md`](Ambient_Dirty_Run_Outcome.md)
(outcome-meter lie on ambient dirt),
[`Agent_Teaching_Surface.md`](Agent_Teaching_Surface.md) (owns `TeachingSnippet`,
co-defendant here), [`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md)
(caused both seat failures cited below).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## Closeout (2026-08-08)

| Slice | Result |
| --- | --- |
| RRT-S02 teaching v11 | **Shipped** `9aa06836` — terminal readers routed to the verdict, not `observation` |
| RRT-S03 headline | **Shipped** `e7087b0d` + `10c287b7` — leads with the verdict; `partial` names its seats; a failed run no longer headlines like a receipt |
| RRT-S04 `errors` | **Shipped** `dbf0f7ce` — was a hardcoded `[]` |
| RRT-S01 top-level `status` | **DROPPED — unnecessary** |

**Cold-agent gate: PASSED**, verified against three real runs on the rebuilt
binary — a partial success, a spawn refusal, and a plain run:

```
FCF51DB2  Ready · Fix the lying bench… · 2 of 3 seats delivered
          status partial · errors ["opencode serve busy: port owned by pid 48831"]
45D454CE  failed · model model_opencode_deepseek_v4_pro …
          status failed · errors ["opencode serve busy: port owned by pid 96665"]
E55A43AD  status completed · answer "OK"
```

Did it work, what did it say, and why — one call, first screen, in all three
shapes.

**Why S01 was dropped rather than deferred.** Two independent reasons. Its
delete math is unpayable — every status-bearing field is load-bearing, and
`pmTurn.lifecycleStatus` in particular carries *loop* state for `kind: relay`
(`LoopCoordinator.swift:2259`), so it is not a duplicate of a run's status.
And the need evaporated: `outcome.status` already answers did-it-work on the
first screen once the headline stopped lying. Adding a field for a question
already answered would violate this packet's own §3.

**Promoted** to `One_Run_Surface.md` §"What the terminal snapshot must say":
the cold-agent gate, the three payload laws, teaching-and-payload-together, and
the do-not-mint-a-second-status ruling. Code SSOT: `TeamRunJSONMapper`
(`runErrors`, `outcomeHeadline`), `LeadCallParser`, `TeachingSnippet`.

**Carried out of this packet, still open:**

- Follow-up (a) — no completion signal for `--no-wait`. Every path is pull.
- Follow-up (b) — `warnings` attribution: a read-only run blamed itself for a
  HEAD change another process made.
- Follow-up (c)/(e) — `errorKind: timed_out` on a 0 ms refusal, and
  `ErrorEnvelope.code` losing the kind in translation. Both
  `Vendor_Signal_Isolation.md`.
- Follow-up (d) — writer emits the Lead Call structured instead of as prose.
- `Options` still has global flag-name shape; the collision fix (`e8d98be8`) is
  a guard, not the per-command refactor.

---

## 0. Review record — two reviews, one disagreement

| | Grok 4.5 `411F2E17` | DeepSeek V4 Pro `AC2E53DC` |
| --- | --- | --- |
| Verdict | **Not ready** | **Ready for Implementation** |
| Can `observation.ownerState` be removed? | **No** — breaks shipped ORS law | **Yes** — "consumed only in tests" |
| Can `outcome.status` be removed? | No — loses multi-seat honesty | Yes — public projection has no production consumer |
| Biggest find | Teaching (`TeachingSnippet:86`) co-owns the incident | **`errors: []` is a hardcoded literal** |

### 0.1 Adjudication (lead-verified, not vote-counted)

**`ownerState` — Grok is right.** `ContractSchema.swift:73–76` declares
`required: ["ownerState", "activityMode", "lastActivityAt"]`, with a comment
citing One Run Surface / ORS-P2-NULL. DeepSeek's "consumed only in tests" is
true of *value readers* and wrong about *contract obligation*: those tests
encode a shipped law, and the schema mandates the key. **Demote, do not remove**
(RRT-S02, unchanged from v2).

**`outcome.status` — DeepSeek is right on the facts, and it does not matter.**
Confirmed: iOS has **zero** `TeamRunJSON` references; the Mac app reads
`teamRun.status` via `TeamRunJSONPresenter`; the public `Outcome.Status`
projection has no production consumer. But it stays anyway, for the independent
reason in §1.2 — it was telling the truth.

**DeepSeek's finding (i) — confirmed, and it is the largest defect in the
packet.** `TeamRunJSONMapper.swift:238` passes `errors: []` as a **hardcoded
empty literal**. Not conditionally empty — never populated, for any run, ever.
`alln show --json` is structurally incapable of reporting a failure reason at
top level. Promoted from a sub-item to its own first-class slice (RRT-S04).

**Cold-agent gate — DeepSeek's amendment accepted.** The gate must name the
derivation chain, or a cargo-culted `status: "done"` passes it while lying
(§3).

**AgentOS `errorKind` — confirmed and routed away.**
`AgentOS/Sources/AgentOSCLI/OpenCodeRoutingWorkerRunner.swift:93–94` maps
`.portOwnedByForeignProcess` → `.timedOut`. Real, and **not this packet's** —
it is a classification stamped during the run, which is
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md)'s charter. Follow-up (c).

**Net verdict: Ready for named slices — RRT-S01 and RRT-S04.** Grok's blocking
edits landed in v2; DeepSeek's landed in v3. RRT-S02 (teaching) and RRT-S03
(headline) follow; neither is red-today in the way S01/S04 are.

---

## If you only read one thing

The payload is not missing the truth. **The truth is misfiled.**

On a **successful** run, the verdict exists as prose inside 14.5 KB of markdown
while the field named `headline` prints the model id. On a **failed** run, the
reason exists in four places while the field named `errors` is `[]`. In both
cases every fact the reader needs is already in the payload, and none of it is
where the reader is told to look — including by our own shipped teaching
(`TeachingSnippet.swift:86`).

So the fix is not another field. **This packet must not increase the number of
status-bearing fields in `alln show --json`.**

---

## 1. Defect

### 1.1 The success path — run `FCF51DB2` (Spec Review Min, verdict Ready)

| Field | Says | True? |
| --- | --- | --- |
| `teamRun.status` | `"done"` | ✅ |
| `teamRun.endReason` | `"completed"` | ✅ |
| `pmTurn.lifecycleStatus` / `pmTurn.reason` | `"done"` | ✅ |
| `outcome.status` | `"partial"` | ✅ **— see §1.2. v1 called this a lie. It was not.** |
| `observation.ownerState` | `"dead"` | ⚠️ true of the process, misleading as an answer |
| *top-level `status`* | absent | — |

Nineteen top-level keys and none of them answers *did it work*.

`outcome.headline` reads `"model model_gpt_sol · lane code · readOnly"` —
byte-identical to `teamRun.identitySummary`. The field named `headline` prints
identity, never outcome.

The verdict lives at `answer.markdown`: 14,573 characters, status line ~40 lines
in. The run emits a machine-readable ` ```lead-call ` block with
`"status": "Ready"` and a one-line `"title"` — and **`LeadCallParser.swift`
already exists** and `ArtifactProjector` already lifts verdict/title for the
HTML artifact. The JSON read surface ignores parsing work already shipped.

`nextActions` on a terminal run offer `alln show <id>` — from inside
`alln show <id>` — and `pmTurn.nextCommands` is `["alln show <id> --json"]`, the
command being executed. (Terminals *do* already lead with `alln artifact show`
via `terminalArtifactNextActions` at `TeamRunJSONMapper.swift:564`; the defect is
the appended circular entries, not a missing answer path.)

### 1.2 Correction: `partial` was telling the truth

v1 asserted "a green run must not print `partial`." That was wrong, and the seat
dump proves it:

```
spec_min_premise_reviewer   done
spec_min_proof_auditor      FAILED — "opencode serve busy: port owned by pid 48831"
spec_min_delivery_steward   done
```

`TeamRunJSONMapper.mapOutcomeStatus` (`:368–376`): all non-skipped answers done ⇒
`completed`; some done ⇒ `partial`. Two of three seats delivered, so `partial`
is **exactly correct**. A seat really did die — the `OpenCode_Serve_Attach`
defect, firing inside the review of this packet.

The defect is therefore not that `partial` lied. It is that **`partial` appears
as a bare word with nothing on the first screen naming which seat failed or
why**, so a reader takes it as a verdict on the whole run. A true signal
rendered without its subject is still a readout failure.

There are **three distinct `partial`s** in the codebase, and conflating them is
its own bug:

| `partial` | Meaning | Owner |
| --- | --- | --- |
| `TeamRunJSON.Outcome.Status.partial` | Mechanical: some seats done, some not | `mapOutcomeStatus` |
| `RunStatus.partial` | Internal; projects to public `teamRun.status: done` | `CatalogRunCoordinator:217–225` |
| Lead Call `"Partial"` | Judgment verdict from a review team | `LeadCallParser` / `SkillCatalog` |

### 1.3 The failure path — run `45D454CE` (DeepSeek review, refused at spawn)

Same disease, mirrored. `alln show --json` returned:

```
outcome.status    "failed"
outcome.headline  "model model_opencode_deepseek_v4_pro · lane code · readOnly · queue 413ms · wall 0ms"
errors            []                      ← the field named errors
```

**`errors` is a hardcoded empty literal.** `TeamRunJSONMapper.swift:238` passes
`errors: []` into every payload it builds. It is not conditionally empty and not
a mapping miss — the field has never been wired. `alln show --json` cannot
report a failure reason at top level for *any* run, and never could.

No `errorReason` key. No `errorKind` key. The actual reason —
`"opencode serve busy: port owned by pid 96665"` — was present **four times**:

```
answers[0].error.message
pmTurn.notes[1]
teamRun.attempts[0].reason
teamRun.attempts[0].diagnosticSnippet
```

A caller who reads `errors` on a failed run learns nothing. Worker metadata also
stamped `errorKind = timed_out` on a refusal that took **0 ms** — nothing timed
out; it was refused instantly (§8 OQ4).

### 1.4 The teaching is a co-defendant

`TeachingSnippet.swift:86` ships, verbatim:

> ``2. `running` ≠ progress. Read `observation` on `alln show <id> --json`.``

That line is generated into every host context by `alln bootstrap`. A cold agent
obeying our own instructions reads `observation`, sees `ownerState: "dead"`, and
reports a crash. **Fixing the payload without fixing this line leaves the
incident reproducible**, which is why the cold-agent gate (§3) fails today even
if every field change lands.

### 1.5 The incident

Dispatched `--no-wait`; interrupted mid-`--stream`; returned; ran
`alln show <id> --json`; read `observation` per rule 2; saw `dead`; reported the
run dead and moved on. It had succeeded seven minutes earlier. Recovering the
verdict took **five further calls**.

### 1.6 Why ten previous attempts did not stick

Each prior improvement **added surface**. Five status-bearing fields, three
`partial`s, and a `LeadCallParser` the read path never calls are the accumulated
result. The corrective must be subtractive — §3.

---

## 2. Product law (candidate)

1. **One elected lifecycle answer, on the first screen.** A reader learns
   whether the run worked without descending into `teamRun`, `pmTurn`, or
   `answers`. Prefer **electing the existing `teamRun.status`** over minting a
   new top-level key (§3 math).
2. **Process state never answers "did it work."** `observation.ownerState` is
   the worker pid's state; on a terminal run that is plumbing. It stays in the
   payload — One Run Surface requires all three observation keys — but it is
   demoted: nothing (payload, teaching, or `nextAction`) may steer a reader to
   it for outcome.
3. **`headline` says what happened.** Not model, lane, or write policy —
   identity already has `teamRun.identitySummary`.
4. **A true signal must carry its subject.** Mechanical `partial` is legitimate
   and stays; it may never render as a bare word. It names which seats did not
   deliver, on the same screen. Mechanical `partial` is never presented as "the
   run crashed", and never conflated with a Lead Call `Partial` verdict.
5. **A failed run states its reason where the reason belongs.** `errors` is
   non-empty whenever a failure reason exists anywhere in the payload.
6. **Parse what the writer already emits.** `LeadCallParser` exists; the read
   surface uses it rather than shipping the verdict as prose.
7. **`nextAction` moves the caller forward.** A terminal run never offers the
   command the caller just ran.
8. **Teaching and payload change together.** A readout law that the shipped
   teaching contradicts is not landed.

---

## 3. Acceptance criterion (binding)

> After this packet, `alln show <id> --json` contains **no more** status-bearing
> fields than before, **no** new command, **no** new flag, **no** new daemon,
> and **no** notification system.

**Delete math is per-slice and must be locked before authorization.** A slice
that adds a key names the ≥2 keys it removes, in the same slice. If the delete
list cannot be locked, elect an existing field instead of minting one.

**No shape change to `observation`** without a named companion amendment to
[`One_Run_Surface.md`](One_Run_Surface.md), whose law at `:30–31` is *three
keys, always present, ISO8601 or explicit null*. Silent breakage is prohibited.

**Pre-slice consumer audit is a gate, not a suggestion** — CLI, help topics,
recipes, mapper tests, stream terminal frames, Mac `TeamRunJSONPresenter`, iOS.

### The cold-agent gate

> Can a cold agent answer *"did it work, and what did it say"* from the first
> screen of `alln show --json`, in one call — **where the elected lifecycle
> answer derives from `teamRun.endReason`, which is already correct?**

The derivation clause is load-bearing (DeepSeek): without it the gate tests only
whether a field *exists*, so a cargo-culted `status: "done"` computed from the
wrong source passes while lying.

Grok's ruling also accepted: **as stated this is gameable** — mint a top-level
`status`, leave `ownerState: dead` and an identity `headline`, and a cold agent
following `TeachingSnippet.swift:86` still reports a crash. The gate therefore
requires all three:

1. First screen carries elected lifecycle + non-identity headline + a pointer to
   the answer.
2. Teaching no longer routes terminal "did it work" to `observation`.
3. A **hostile fixture**: a terminal run whose `observation` contradicts the
   elected status must fail the gate. A gate that cannot fail is not a gate
   (`docs/operations/Spec_Review.md` §3).

---

## 4. Slice plan — **none authorized**

Grok: *"No slice should be authorized until edits 5–13 land."* Those edits are
applied in this revision; re-review is pending before authorization.

### RRT-S01 — Elect one lifecycle answer — **BLOCKED, delete math unpayable**

**Implementation attempt 2026-08-08 found no affordable deletion.** Grok
predicted this ("without a locked delete list, S01 fails §3 by construction");
the audit confirms it. Every status-bearing field is load-bearing:

| Field | Can it pay for a new top-level `status`? |
| --- | --- |
| `teamRun.status` / `endReason` | No — the derivation source |
| `outcome.status` | No — truthful multi-seat signal (§1.2) |
| `observation.ownerState` | No — `ContractSchema:73–76` `required`, ORS law |
| `pmTurn.lifecycleStatus` / `reason` | **No** — `LoopCoordinator.swift:2259` sets these from *loop* state for `kind: relay`. Not redundant with a run's status; deleting them breaks the relay path. |

That last row kills both DeepSeek's proposed delete target and this packet's own
v3 OQ7 lean. Both were wrong.

**And the need largely evaporated.** RRT-S03 delivers the founder's actual
question — *did it work, and what did it say* — on the first screen, in a field
that already existed, at zero field cost. Before minting `status`, prove a
reader still cannot answer it from the shipped headline.

**Recommended:** fold into the closeout check. If the cold-agent gate passes
without it, drop S01 entirely; §3 stays intact and the surface stays smaller.

<details><summary>Original S01 scope (superseded)</summary>

Prefer electing `teamRun.status` (already public, already correct) over a new
top-level key. If a top-level `status` is minted anyway, the same slice removes
≥2 status-bearing keys — candidate: `pmTurn.lifecycleStatus` + `pmTurn.reason`,
both redundant.

`outcome.status` **stays**, semantics unchanged (§1.2). It is not the lifecycle
answer and must stop being read as one.

**Works Test:**
```
Given: a run with teamRun.endReason == "completed" and a delivered answer
When:  alln show <id> --json
Then:  one elected field answers did-it-work on the first screen
And:   no field contradicts it
And:   status-bearing field count is <= the pre-slice count (locked inventory)
Mutation: force endReason = "failed" ⇒ the elected field flips.
```
</details>

### RRT-S02 — Demote `ownerState`; do not remove it

**Rescoped from v1.** The three-key `observation` contract is preserved.
Instead: terminal payloads and `TeachingSnippet.swift:86` stop steering readers
to `ownerState` for outcome. Teaching rewrite is *in* this slice, not after it
(law 8), and is co-owned with
[`Agent_Teaching_Surface.md`](Agent_Teaching_Surface.md).

**Works Test:**
```
Given: a completed run and a cold agent following the shipped teaching snippet
When:  it is asked "did this run work?"
Then:  it answers correctly in one call
And:   observation still carries all three keys (ORS :30-31 unbroken)
And:   a running run's observation is unchanged (no live-path regression)
```

### RRT-S03 — `headline` says what happened — **SHIPPED `e7087b0d`**

**OQ1 closed:** parse at the read surface with the existing `LeadCallParser`,
writing into the existing `outcome.headline`. **No new `leadCall` key** — that
would violate §3. Writer-side structured emit is Follow-up (d), not this packet.

For run kinds with no lead-call block, `headline` states outcome + kind, never
identity. For `partial`, it names the non-delivering seats (law 4).

**Works Test:**
```
Given: a specReview run whose answer contains a lead-call block with status Ready
Then:  outcome.headline names the verdict; != teamRun.identitySummary
Given: outcome.status == "partial"
Then:  the first screen names which seats did not deliver, and why
Given: a run kind with no lead-call block
Then:  headline still states an outcome, never an identity string
```

### RRT-S04 — Wire `errors` — **SHIPPED `dbf0f7ce`**

**Promoted in v3 to a first-class slice** — `TeamRunJSONMapper.swift:238` passes
`errors: []` as a hardcoded literal, so no run has ever reported a reason at top
level (§0.1, §1.3). Populate it from `answers[].error` /
`teamRun.attempts[].reason` whenever a reason exists anywhere in the payload.

**Net-negative by construction:** it fills an existing empty array. Zero new
fields, zero new commands.

Also in scope: drop the circular terminal `showRun` entry and
`pmTurn.nextCommands: ["alln show <id> --json"]`. Do **not** invent a new answer
command — `alln artifact show` and export already exist and already lead via
`terminalArtifactNextActions` (`TeamRunJSONMapper.swift:564`).

**Not in scope:** correcting `errorKind` itself. A serve-busy refusal stamped
`timed_out` is an AgentOS classification bug
(`OpenCodeRoutingWorkerRunner.swift:93–94`) owned by
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md). This slice requires
only that whatever kind is chosen *reaches* `errors`.

Also: drop the circular terminal `showRun` entry and
`pmTurn.nextCommands: ["alln show <id> --json"]`. Do **not** invent a new answer
command — `alln artifact show` and export already exist and already lead.

**Works Test:**
```
Given: a run that failed with "opencode serve busy: port owned by pid N"
When:  alln show <id> --json
Then:  errors is non-empty and contains that reason
And:   the first screen states why it failed
And:   no nextAction repeats the command just run
```

### RRT-S05 — Gate + closeout

- [ ] RRT-S01…S04 Works Tests pass
- [ ] Cold-agent gate passes in one call, with the hostile fixture red before
      the fix and green after
- [ ] Locked status-bearing field inventory shows no net growth
- [ ] Teaching snippet and payload agree
- [ ] Promote §2 laws into help + `docs/operations/`; archive

---

## 4.1 Shipped result — dogfooded on the originating run

`FCF51DB2`, the run this packet was written about, read through the rebuilt CLI:

```
outcome.headline: Ready · Fix the lying bench, but expire at projection,
                  not the store · 2 of 3 seats delivered ·
                  model model_gpt_sol · lane code · readOnly
outcome.status  : partial
errors          : ["opencode serve busy: port owned by pid 48831"]
```

Did it work, what did it say, why `partial`, and what broke — one call, first
screen. Before: an identity string, a bare `partial`, and `errors: []`.

Still open before closeout: the cold-agent gate (§3) also requires the teaching
fix (RRT-S02) — `TeachingSnippet.swift:86` still routes readers to
`observation`.

---

## 5. Non-goals

- **A completion signal / push for `--no-wait`.** Follow-up (a). Grok's ruling
  accepted: `--stream` is the ack path, correct pull is the recovery when the
  stream dies, and push would add machinery — reversing this packet's thesis.
- Any new command, subcommand, flag, or daemon.
- Changing run semantics or what makes a run succeed. Only what the read surface
  **says** about a settled run.
- Rewriting the Spec Review writer's output format (Follow-up (d)).
- `--stream` *behavior* and framing — those stay `One_Run_Surface.md`. **But**
  terminal snapshot truth is in scope wherever the same mapper emits it,
  including the stream's terminal frame; the same lies ship through both.

---

## 6. Risks

| Risk | Response |
| --- | --- |
| Breaking the ORS three-key `observation` law | S02 rescoped to demote, not remove. Any shape change needs a named ORS amendment first. |
| Removing `outcome.status` loses multi-seat honesty | It is **not** removed (§1.2). It was right. |
| Parsing a prose fence is brittle | `LeadCallParser` already exists and is already trusted by `ArtifactProjector`. Reuse, don't re-invent. Writer-structured emit stays a follow-up. |
| Field removal breaks agents holding stale instructions | `RetiredVocabulary` exists for exactly this; register anything removed. |
| Teaching and payload drift apart | Law 8 + S02 bundles them. |
| `answer.status` is a sixth voice | The canonical `Answer` struct carries its own `status`, which can disagree with the elected lifecycle on a partial hoist (VSI-S05). Verify agreement before RRT-S01 closes, or fold it in — OQ6. |
| Packet becomes a general run-surface refactor | §3 is the fence: no new commands/flags, no net field growth. |

---

## 7. Follow-ups

| # | Item | Why deferred |
| --- | --- | --- |
| (a) | **No completion signal.** With `--no-wait` every path is pull; `--stream` blocks and polling is forbidden. If the stream is interrupted, nothing reports completion. | Adding push adds machinery. Cheap correct pull first. Co-caused §1.5. |
| (b) | **`warnings` attribution.** `FCF51DB2` emitted *"research-write violation… changed the repository's Git state"* with `changedPaths: []` — HEAD moved because a **different process** committed mid-run. Signal attributed to a source that did not produce it. | Same family as `Probe_Freshness.md` / `Vendor_Signal_Isolation.md`. Founder's call whether to packet or fold. |
| (c) | **`errorKind: timed_out` on a 0 ms refusal.** A serve-busy refusal is not a timeout. | May belong to `Vendor_Signal_Isolation.md` rather than here — OQ4. |
| (d) | **Writer emits Lead Call structured**, ending the prose round-trip. | Larger; RRT-S03 reuses the existing parser instead. |
| (e) | **`ErrorEnvelope.code` derives from `WorkerAnswerStatus`, not `WorkerAnswerErrorKind`.** When AgentOS stamps `status: .failed` + `errorKind: .timedOut`, the public surface reports `AGENT_FAILED` and the misclassification is silently lost in translation (`TeamRunJSONMapper` `errorEnvelope`). | Downstream of the VSI AgentOS `errorKind` fix — fixing it here would encode the upstream bug. |

---

## 8. Open questions

1. ~~Parse the fence vs writer emits structured?~~ **Closed:** reuse
   `LeadCallParser` at the read surface; no new key. Writer-side is Follow-up (d).
2. ~~Does `partial` mean anything?~~ **Closed:** yes — three distinct meanings
   (§1.2). Keep the mechanical one; make it name its subject.
3. Elect `teamRun.status` or mint a top-level `status`? Lean: **elect** — more
   faithful to §3 and avoids a third spelling.
4. Does `errorKind: timed_out` on an instant refusal belong here or in
   `Vendor_Signal_Isolation.md`? Lean: VSI owns classification; this packet only
   requires that whatever kind is chosen reaches `errors`.
5. Which named ORS amendment, if any, does the teaching demotion require?
6. Must `answer.status` agree with the elected lifecycle answer, or is the
   VSI-S05 partial hoist an intentional disagreement? Settle before RRT-S01
   ships.
7. `pmTurn.lifecycleStatus` / `pmTurn.reason`: drop, or keep as explicitly
   subordinate? "Subordinate or drop" is not implementable (DeepSeek edit 4).
   Lean: **drop** — they are redundant with the elected answer and dropping
   them is what makes S01's delete math work.

---

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| A finished run reads as dead/partial; a failed run gives no reason; PM missed a completed run | This packet + `TeamRunJSONMapper`, `LeadCallParser`, `TeachingSnippet.swift:86` |
| The three-key `observation` contract | [`One_Run_Surface.md`](One_Run_Surface.md) `:30–31` — binding |
| `alln bootstrap` teaching text | [`Agent_Teaching_Surface.md`](Agent_Teaching_Surface.md) |
| Outcome meter lying about repo changes | [`Ambient_Dirty_Run_Outcome.md`](Ambient_Dirty_Run_Outcome.md) |
| Selection surfaces lying about seat readiness | [`Probe_Freshness.md`](Probe_Freshness.md) |
