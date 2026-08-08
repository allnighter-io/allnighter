# Run Readout Truth — one screen, one status, no plumbing

Status: **Draft v1 — reviews dispatched (Grok 4.5 + DeepSeek V4 Pro). No slice authorized.**
Owner: AllnighterCore (`TeamRunJSONMapper`, `RunService` settle path,
`ContractRegistry` / CLI `show`)
Created: 2026-08-08
Origin: PM incident 2026-08-08 — a completed Spec Review with a **Ready** verdict
was read as a crashed run, because `alln show <id> --json` answers "who ran this"
five different ways and "did it work" none of them. Founder: *"why were you just
sitting there and doing nothing… I have tried to improve alln 10 times and this
still happens."*

Companion packets:
[`One_Run_Surface.md`](One_Run_Surface.md) (owns *that there is one* read
surface — `alln show --json|--stream`; this packet owns *what that surface says
at terminal*), [`Probe_Freshness.md`](Probe_Freshness.md) (sibling truth defect
on the selection surfaces), [`Ambient_Dirty_Run_Outcome.md`](Ambient_Dirty_Run_Outcome.md)
(a third outcome-meter lie: `incomplete_uncommitted` on ambient dirt).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## If you only read one thing

The payload is not missing the truth. **The truth is outvoted.**

`alln show <id> --json` on a run that finished cleanly with a Ready verdict
carries **five status-bearing fields**. Three say it succeeded. One says it was
partial. One says it is dead. The two a reader is actually steered toward — by
`CLAUDE.md` rule 2 and by the field literally named `headline` — are the two
that lie.

The fix is therefore not another field. It is electing one and deleting the
rest. **This packet must reduce the number of status-bearing fields in
`alln show --json`, never increase it.**

---

## 1. Defect

Run `FCF51DB2-AC6D-4B5D-923F-AF6328D79740` — Spec Review Min, completed,
verdict **Ready**, 426s wall. Verbatim from `alln show <id> --json`:

| Field | Says | Truth? |
| --- | --- | --- |
| `teamRun.status` | `"done"` | ✅ |
| `teamRun.endReason` | `"completed"` | ✅ |
| `pmTurn.lifecycleStatus` / `pmTurn.reason` | `"done"` | ✅ |
| `outcome.status` | **`"partial"`** | ❌ |
| `observation.ownerState` | **`"dead"`** | ❌ |
| *top-level `status`* | **absent** | — |

Nineteen top-level keys — `agents`, `answer`, `answers`, `artifact`, `audit`,
`contractVersion`, `errors`, `nextActions`, `notes`, `observation`, `outcome`,
`plan`, `pmTurn`, `researchGitObservation`, `schemaVersion`, `stages`,
`teamRun`, `usage`, `warnings` — and not one of them answers *did it work*.

Three further defects on the same screen:

**`outcome.headline` is an identity string.** It reads
`"model model_gpt_sol · lane code · readOnly"` — byte-identical to
`teamRun.identitySummary`. The field named `headline` never says what happened.

**The verdict is buried.** The entire reason the run existed lives at
`answer.markdown`: 14,573 characters, status line ~40 lines in. The run *does*
emit a machine-readable verdict — a fenced ` ```lead-call ` block containing
`"status": "Ready"` and a one-line `"title"` — but it is **not parsed**: no
`leadCall` key exists anywhere in the payload. Structured truth is present and
left as prose.

**`nextActions` are circular.** On a *terminal* run they offer "Show run"
(`alln show <id>`) — from inside `alln show <id>` — plus artifact and export.
`pmTurn.nextCommands` is `["alln show <id> --json"]`: the command already being
executed. Nothing says *the answer is ready, read it*.

### 1.1 The incident

The PM dispatched with `--no-wait`, was interrupted mid-`--stream`, returned,
ran `alln show <id> --json`, and read `observation` — exactly as
`CLAUDE.md` rule 2 instructs: *"`running` ≠ progress. Read `observation` on
`alln show <id> --json`."*

`observation` said `ownerState: "dead"`. The PM reported the run as dead and
moved to other work. It had succeeded seven minutes earlier. Recovering the
verdict took **five further calls** — `--json` again, a key dump, an `answer`
type probe, a structure probe, and finally a 14.5 KB markdown print.

A cold agent following the documented rule lands on `dead`. The tool makes the
wrong read the default one.

### 1.2 Why ten previous attempts did not stick

Each prior improvement **added surface** — another field, another command,
another `nextAction`. Every addition increased the number of places a reader
must consult and the number of ways they can disagree. Five status fields is
the accumulated result, not an accident.

The corrective is subtractive, and it is the acceptance criterion in §3.

---

## 2. Product law (candidate)

1. **One status, at the top, first.** `alln show --json` carries a top-level
   `status` derived from `teamRun.endReason`. Every other status-bearing field
   either agrees with it or is removed.
2. **A terminal run reports history, not process state.** Once a run ends,
   `observation.ownerState` is plumbing — the worker process exited, which is
   what exiting looks like. AGENTS.md: *hide the plumbing*. Terminal runs stop
   emitting it.
3. **`headline` says what happened.** Not who ran it, not the lane, not the
   write policy. Identity already has a field (`teamRun.identitySummary`).
4. **A green run never prints `partial`.** Two fields describing one run may not
   disagree. If `partial` has a real meaning, it needs a definition that
   excludes this run; if it does not, it goes.
5. **A structured verdict is never left as prose.** If the writer emits a
   machine-readable block, the read surface parses it.
6. **`nextAction` moves the caller forward.** A terminal run never offers the
   command the caller just ran.

---

## 3. Acceptance criterion (binding, and the point of the packet)

> After this packet, `alln show <id> --json` contains **fewer** status-bearing
> fields than before, **no** new command, **no** new flag, **no** new daemon,
> and **no** notification system.

A slice that adds a field must delete at least two. If a proposed fix cannot
meet that, it is the wrong fix for this packet.

**The cold-agent gate — durable, cheap, no judgment required:**

> Can a cold agent answer *"did it work, and what did it say"* from the first
> screen of `alln show --json`, in one call?

Today: no. This gate should outlive the packet and be applied to every future
change to the run read surface.

---

## 4. Slice plan

### RRT-S01 — One status, and only one

**Scope:** Add top-level `status`, derived from `teamRun.endReason` (already
computed, already correct). Then reconcile the contradictors:

| Field | Disposition |
| --- | --- |
| `outcome.status: "partial"` on `endReason: completed` | Define `partial` so it excludes this run, or remove it. A green run must not print it. |
| `pmTurn.lifecycleStatus` / `pmTurn.reason` | Redundant with top-level `status` — subordinate or drop. |
| `teamRun.status` | Keep as the derivation source; not a second answer. |

Net field count must go down (§3).

**Works Test:**
```
Given: a run with teamRun.endReason == "completed" and a delivered answer
When:  alln show <id> --json
Then:  top-level status reads a single success value
And:   no field in the payload contradicts it
And:   the count of status-bearing fields is lower than before the slice
Mutation: force endReason = "failed" ⇒ top-level status flips; still no contradiction.
```

### RRT-S02 — Terminal runs stop emitting `ownerState`

**Scope:** Once a run is terminal, `observation` describes what happened, not
whether a pid is alive. Drop `ownerState` from terminal payloads. Non-terminal
runs keep it — that is where it is load-bearing.

**Works Test:**
```
Given: a completed run
When:  alln show <id> --json
Then:  observation carries no ownerState
And:   a still-running run DOES carry ownerState (no regression on the live path)
```

### RRT-S03 — `headline` says what happened

**Scope:** Parse the ` ```lead-call ` fence the writer already emits and lift
`status` + `title` into `outcome.headline` (e.g. *"Spec Review Min · Ready ·
Fix the lying bench, but expire at projection"*). Identity stays in
`teamRun.identitySummary`.

**Honest cost:** this is the one slice that is not free. The verdict is
currently prose-only — no `leadCall` key exists. Either the read surface parses
the fence, or the writer emits it structured. Parsing a fence the writer already
guarantees is the smaller change; emitting it structured is the more honest one.
**Open question 1.**

For run kinds with no lead-call block, `headline` states outcome + kind, never
identity.

**Works Test:**
```
Given: a specReview run whose answer contains a lead-call block with status Ready
When:  alln show <id> --json
Then:  outcome.headline names the verdict, not the model/lane/writePolicy
And:   outcome.headline != teamRun.identitySummary
Given: a run kind with no lead-call block
Then:  headline still states an outcome, never an identity string
```

### RRT-S04 — `nextAction` moves the caller forward

**Scope:** On a terminal run, the first `nextAction` reads the answer. Remove
self-referential entries — `alln show <id>` offered by `alln show <id>`, and
`pmTurn.nextCommands: ["alln show <id> --json"]`.

**Works Test:**
```
Given: a terminal run
When:  alln show <id> --json
Then:  nextActions[0] retrieves the answer
And:   no nextAction (or pmTurn.nextCommands entry) repeats the command just run
```

### RRT-S05 — Cold-agent gate + closeout

- [ ] RRT-S01…S04 Works Tests pass
- [ ] The §3 cold-agent gate passes in one call, verified against a real run
- [ ] Status-bearing field count is provably lower than at v1
- [ ] Promote §2 laws into help + `docs/operations/`; add the gate to the
      run-read-surface routing row
- [ ] Archive this packet

---

## 5. Non-goals

- **A completion signal / push notification for `--no-wait`.** Real gap (§7 (a)),
  and deliberately not solved here — it would add machinery, which is the
  failure mode this packet exists to reverse. Making the pull cheap and correct
  is the prerequisite; whether a push is also wanted is a separate decision.
- Any new command, subcommand, or flag.
- Any new daemon or resident process.
- Changing run semantics, settle logic, or what makes a run succeed. This packet
  changes only what the read surface **says** about a run that already settled.
- Reworking `answer.markdown` content or the Spec Review writer's format.
- Streaming / `--stream` behavior. `One_Run_Surface.md` owns the surface's
  existence; this packet owns its terminal readout.

---

## 6. Risks

| Risk | Response |
| --- | --- |
| Removing `outcome.status` / `ownerState` breaks a GUI or iOS consumer | One coordinated contract change with a `contractVersion` bump; CLI/GUI/iOS share the contract and move together. Audit consumers before deleting, not after. |
| `partial` has a real meaning someone depends on | RRT-S01 must find its definition first. If it is meaningful, keep it and fix the classification; if nothing defines it, delete it. Do not guess. |
| Parsing a prose fence is brittle | Exactly why Open question 1 exists. A writer-side structured emit is more robust; parse only if the fence is contractually guaranteed. |
| Field removal is a breaking change for agents holding stale instructions | `RetiredVocabulary` already exists for exactly this; register removed fields there. |
| This packet becomes a general run-surface refactor | §3 is the fence. No new commands, no new flags, net-negative fields. Anything larger is a different packet. |

---

## 7. Follow-ups (named, not silenced)

| # | Item | Why deferred |
| --- | --- | --- |
| (a) | **No completion signal.** With `--no-wait`, every path to "is it done" is pull; `--stream` blocks and `CLAUDE.md` forbids polling. If a stream is interrupted, nothing ever reports completion. | Fixing it adds machinery. Cheap correct pull first; then decide if push is wanted. This is the defect that caused §1.1 as much as the readout was. |
| (b) | **`warnings` attribution.** The same run emitted `research-write violation: this read-only research run changed the repository's Git state` with `changedPaths: []` — HEAD moved because a *different process* committed mid-run. A signal attributed to a source that did not produce it; same family as `Probe_Freshness.md` and `Vendor_Signal_Isolation.md`. | Distinct defect, distinct owner. Packet or fold into VSI — founder's call. |

---

## 8. Open questions

1. **RRT-S03 mechanism:** parse the ` ```lead-call ` fence at the read surface,
   or have the writer emit it structured and stop round-tripping through prose?
   Lean: **writer emits structured** — a parser over prose is the exact shape of
   fragility this repo has paid for before — unless the fence is already a
   contract the writer cannot break.
2. **Does `partial` mean anything?** Needs its definition found before RRT-S01
   can decide keep-and-fix vs delete.
3. Should top-level `status` reuse an existing vocabulary (`done` / `completed`
   / `failed`) rather than mint a third spelling? Lean: reuse `teamRun.status`
   spelling exactly; a new spelling is a new surface.

---

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| A finished run reads as dead/partial; PM missed a completed run; `alln show --json` doesn't say whether it worked | This packet + `TeamRunJSONMapper`, `RunService` settle path |
| Whether there is one run read surface at all | [`One_Run_Surface.md`](One_Run_Surface.md) |
| Outcome meter lying about repo changes | [`Ambient_Dirty_Run_Outcome.md`](Ambient_Dirty_Run_Outcome.md) |
| Selection surfaces lying about seat readiness | [`Probe_Freshness.md`](Probe_Freshness.md) |
