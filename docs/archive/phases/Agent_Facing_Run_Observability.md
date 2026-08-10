# Agent-Facing Run Observability

Status: **SUPERSEDED before implementation (2026-08-01)** by
[`One_Run_Surface.md`](One_Run_Surface.md). Historical incident and
rejected incremental approach only; do not resume OBS-S00–S04.
Owner: Founder ruling pending; implementer TBD
Updated: 2026-08-01

Founder intent: an agent supervising `alln` work could not tell whether a
delegated seat was advancing, stalled, or dead. It fell back to `pgrep`.

> **v2 warning to the implementer.** v1 of this packet was **wrong on its central
> claim** and would have shipped green as attempt #5. A review (Sonnet 5,
> 2026-07-30) verified it against code and killed two headline items. Read §2
> before §3 — the *diagnosis* changed, not just the wording. This is a family of
> packets with a 4-for-4 record of shipping green and failing in the field.

Product value: the PM seat is increasingly an **agent**, not the founder.
`NotificationScheduler` + `ServeAutoLaunch` (shipped 2026-07-27) wake a *human*
with a macOS banner. There is no agent-facing equivalent, so an agent PM can only
poll — and polling is what failed.

Trusted workflow slice: an agent dispatches a mutating run, blocks once on a
bounded wait, and is returned to the moment anything changes. No polling loop, no
blind 7200-second wait.

Non-goals: no new daemon, no push transport, no change to run semantics, no
notification redesign. Three bounded fixes to surfaces that already exist.

---

## 1. The incident (2026-07-30, loop-verb cutover)

A supervising agent dispatched five mutating slices via `alln run --no-wait` and
had to determine, repeatedly, whether the seat was still working.

| Attempt | Result |
| --- | --- |
| `alln team status <id> --wait-for terminal --timeout 7200` | Blind for 10 minutes. Auto-backgrounded by the harness. No progress signal at all. |
| `alln ps --json` → `streamAge` | `None` on every row. **The field does not exist** — see §2 R2. The supervisor invented the name and never checked the schema. |
| `alln ps --json` → filter `status ∈ {running, live}` | Matched **nothing** while the run was demonstrably alive. Concluded the work was finished. It was not. |
| `pgrep -f "alln run"` | **Correct.** A raw OS call was the only reliable signal. |

Cost: one slice was declared dead while still running; another finished and sat
uncommitted because the supervisor had stopped watching. The supervisor also
missed that a *second* session was mutating the same working tree, because
`alln ps` never surfaced it either.

**That a raw `pgrep` outperformed `ps`, `status`, and the journal is the finding.**

**Correction (v2).** One of those four rows is the supervisor's own fault, and
naming it matters more than defending the packet: `streamAge` is not a field.
The real field is **`heartbeatAgeSeconds`** (`OwnershipJSON.swift:49`). A
dictionary lookup on a key that never existed returned `None`, and v1 wrote that
up as "the field is null, that's a bug." **v1 diagnosed a typo as a product
defect.** The schema was discoverable the whole time (`alln docs --schema`).

That is itself a finding, and it belongs in the fix set: an agent that asks for
a field that does not exist gets `None`, indistinguishable from a real null. See
OBS-S04.

---

## 2. Root cause — three separate defects, ranked

### R1 — There is no "wake me on change" primitive

Only two waiting modes exist: `--wait-for terminal` (blind until done) or manual
polling. Nothing returns on *progress*. So a supervising agent must choose
between a long blackout and a poll spin, and both failed here.

### R2 — activity is **structurally nil for silent work, by design** — not a bug

v1 said "`streamAge` is null, that is a bug, fix the population path." **Verified
false.** `heartbeatAgeSeconds` derives from `run.json.lastActivityAt`, and
`RunActivity.activityKind(for:)` (`RunActivity.swift:45-74`) deliberately maps
spawn, queued, and `running` transitions to `nil`. Stage events that would seed
`.child` only fire **after** the worker completes (`RunService.swift:1998-2013`),
and a driver with no incremental parser "degrades to a terminal-only stream"
(`RunService.swift:1580-1586`).

So for a worker doing a long silent stretch — heavy tool use, one big write, a
non-streaming driver — `lastActivityAt` stays nil for the **entire turn**, from
spawn to exit. `OwnershipJSON.swift:49` even documents it: *"nil when no activity
yet."*

**There is no bug to fix here.** Handing an implementer "find and fix the
population path" produces one of two bad outcomes:

1. They find nothing and paper it over with a fixture that has activity events —
   i.e. not the incident's shape — and it ships green.
2. They reach for the one signal that *is* non-null during silent work: pgid /
   process-group sampling (`ProcessOwnership.swift:918-922`), already wired into
   `silenceStatus`. **That is the exact merge PLS-S01 banned**, reintroduced under
   a new field name. This is the highest-probability way attempt #5 fails.

### R3 — the live row was crowded out of the default view

`alln ps` returned **28 rows**, nearly all durable loop records in `awaitingPM` /
`escalated`, mixed in one array with in-flight run rows that use a different
status vocabulary (`running`). The live run was not distinguishable — and at
times not present — in the default view.

> **This corrects the first-pass diagnosis.** The obvious-looking fix was a
> kind-agnostic `live: bool`. **That fix would not have worked**: a boolean cannot
> help on a row that is not in the output. Worse, defining `live` from process
> existence would re-create the exact defect closed by
> `docs/archive/phases/Pilot_Status_Liveness_Lie_Hotfix.md` — a pgid heartbeat
> reporting alive while the stream is dead. R3 is a real defect; see OBS-S03.

---

## 2b. This is the FIFTH attempt — why the first four did not hold

Founder, 2026-07-30: *"We have tried to fix this 10 times and agents like you
STILL stall."* That is the most important sentence in this packet. Lineage:

| Packet | What it did | Why it did not end the problem |
| --- | --- | --- |
| `Pilot_Long_Turn_Survival` (PLT-S02) | Taught agents `silenceAgeSeconds` is **PRIMARY** liveness | Named a field authoritative without constraining what feeds it |
| `Idle_Stall_False_Kill_Hotfix` (IDLE-HF-S02) | `pgid_activity` (child CPU/spawn) refreshes the turn heartbeat | Defensible alone; made "progress" mean "a process moved," not "work advanced" |
| `Pilot_Status_Liveness_Lie_Hotfix` (PLS-S01/S02) | PRIMARY = stream **only**; stopped `max(journal, heartbeat)` | Fixed *which source is authoritative*. Did not require the source to ever be **non-null** |
| `Core_Loop_Improvements` (CLP-S01/S02) | Stream liveness on `ps`/status, reconcile-on-read | Same: correctness of the value, not presence of the value |

**The pattern.** Every prior attempt answered *"which source is the truth?"* Not
one asked *"what does a supervising agent do when the field is empty?"*

PLS made `pilot status` honest by refusing to merge in the pgid heartbeat. That
was right. But the failure mode it left behind is the one that bit on 2026-07-30:
`streamAge` came back **null on every row of every poll for two hours**, and a
supervisor cannot distinguish *"not advancing"* from *"we did not measure."*

> **An honest `null` and a fresh lie fail the agent identically.** Both end with
> a supervisor guessing. PLS traded a lie for a silence and the incident rate did
> not change.

### The FIFTH failure mode — named here for the first time

The §2b thesis ("nobody asked what happens when the field is empty") survived
review, but it is **not the whole story**, and v1 stopped one step short:

> **For an entire common class of legitimate work, no stream signal will ever
> exist — by design — and the one attributable signal that does exist during that
> window is banned from the field by law.**

Silent tool execution, one-shot writes, degraded/non-streaming drivers: these
produce zero activity events for minutes at a time and that is correct behavior,
not a defect. Meanwhile pgid activity is non-null throughout and PLS-S01 rightly
forbids it from feeding liveness, because "a process moved" is not "work
advanced."

This is why v1's binding consequence #2 ("unknown must be loud, not empty") does
**not** save the packet: an explicit `unknown` emitted continuously for the whole
duration of every silent turn is no more actionable than the null was. It
relabels the blind stretch instead of ending it.

`Idle_Stall_False_Kill_Hotfix.md:17-25` already diagnosed this exact shape at the
watchdog layer ("writing a large HTML file in one shot produces no streaming
progress"). Five packets in, the observability layer is still treating it as an
accident.

**The real question — a product ruling, not an implementation detail:**

> Should `ps`/`status` report anything at all for a worker that is alive and
> **legitimately silent** — and if so, from what source, under what name, and how
> is it kept structurally separate from any kill decision?

Until that is answered, every slice below is decoration.

**Binding consequences for this packet:**

1. **Never reintroduce the merge.** `pgid_activity` / owner-tree busyness must
   never appear under `streamAge` / `lastProgressAt` / `silenceAgeSeconds`. PLS-S01
   is law; OBS-S02 fixes population **without** re-widening the source.
2. **Unknown must be loud, not empty.** If liveness genuinely cannot be measured,
   say so in a way an agent must handle — an explicit unknown state with a reason,
   never a bare null the caller silently coerces to "fine."
3. **Presence is a gate, not a nicety.** A test asserting `streamAge` is non-null
   on a live run is the regression this family has never had. Every prior packet
   tested *correctness of a value that was present*.
4. **The real test is behavioral.** Four packets shipped green and agents kept
   stalling, so shape tests are not evidence. The proof must be: a supervisor that
   uses only these surfaces observes every transition from dispatch to terminal —
   **including a turn with a genuinely silent stretch.** A fixture that emits
   activity events is not the incident and proves nothing.
5. **Silence is not information — teach that, do not hide it.** For a silent turn
   the correct supervisory behavior is *not* to poll harder. It is to wait on a
   durable completion signal (the commit / terminal state) and to know that
   silence is expected for this run shape. A supervisor that believes silence
   means "probably dead" will keep killing live work no matter what fields exist.

## 3. Slices — reordered by v2 review

**Ship order is now S00 → S03 → S04 → S01. S02 as written is deleted.**

### OBS-S00 — the ruling: what does an alive-but-silent worker report?

**RULED 2026-07-30 (agent ruling under the standing delegation of technical
calls; founder may overturn, an implementer may not).** Blocking the packet on a
question already delegated would be report-and-stop. The ruling:

- **Keep `heartbeatAgeSeconds` stream-only and nil-when-nil.** PLS-S01 is law. Do
  not widen it. Do not merge pgid. Do not invent a substitute that quietly means
  the same thing.
- **Add a distinct, honestly-named field for the run's activity *expectation***,
  not its activity: does this run shape stream incrementally, or is it
  terminal-only? That is knowable at dispatch from the driver's parser
  capability (`RunService.swift:1580-1586`). A supervisor seeing
  *"terminal-only: no incremental activity expected"* stops treating silence as
  evidence of death — which is the actual failure.
- **Tree/owner busyness may be reported under its own name** (`silenceStatus`
  already exists) and must never be called liveness or progress, and must never
  feed a kill decision. IDLE-HF-S04 kill policy is untouched.

**Why the expectation field is the crux.** The incident was not "the supervisor
lacked a number." It was "the supervisor could not tell whether silence was
normal." A run that is terminal-only by construction *should* be silent, and an
agent told so will wait correctly. An agent not told so will keep killing live
work no matter how many liveness fields exist — which is the 4-for-4 record this
family already has.

This slice adds no new source of truth. It surfaces a fact already known at
dispatch (driver parser capability, `RunService.swift:1580-1586`) that was never
exposed to the caller.

### OBS-S03 — make the live row findable *(strongest slice, ship early)*

Unchanged from v1 and the least risky work here. `alln ps` returned 28 rows,
mostly settled loop records in `awaitingPM`/`escalated`, mixed with in-flight run
rows using a different status vocabulary.

1. **Order live rows first.** This alone fixes the visibility half of the incident.
2. **`--kind run|loop`** so a caller need not know each kind's status enum.

Review caveat: `--kind` must be honored everywhere `ps` output is consumed, or a
caller that omits it is back in the 28-row soup.

The rejected `live: bool` reasoning from v1 stands — a boolean cannot help a row
that is absent, and sourcing it from pgid recreates the shipped lie.

### OBS-S04 — an unknown field must not answer like a null *(new; cheap)*

The supervisor asked for `streamAge`, a field that does not exist, and got the
same `None` a real null gives. Field-name drift is indistinguishable from
"no data" at the call site.

`alln ps --json --strict-fields`, or a documented field list in the payload, so a
caller can detect that it asked for something that is not in the schema. Cheap,
and it removes an entire class of self-inflicted blindness — the one that
actually produced this packet's wrong v1 diagnosis.

### OBS-S01 — `alln ps --wait-for-change --timeout <seconds>` *(demoted)*

**v1 called this "the fix." Review verified it is not, for the incident's shape.**

Waking on a "stream-liveness bucket crossing" derives from `progressStale`
(`RunActivity.swift:79-86`), a function of `lastActivityAt` — which per §2 R2 is
nil for the whole of a silent turn. No first activity means no `nil→false`
transition and no staleness crossing, so the waiter has nothing to fire on and
**degrades to exactly the `--wait-for terminal` that already went blind**
(`AllnighterCLI.swift:1222-1241`, which already polls internally and matches on
lifecycle status only, `AsyncTeamContracts.swift:394-398`).

It is still worth building — it genuinely helps runs that *do* stream, and it
turns a poller into a listener for that majority. But it is not the fix for the
incident, and shipping it as though it were is how attempt #5 fails.

Two corrections to v1's scoping:
- **It is not a "reuse."** The existing waiter is single-run, single-target,
  lifecycle-only. Watching *any* owned run across mixed kinds is new multi-row
  diff logic. A rushed port will define "change" as lifecycle-status-only —
  silently dropping the one case v1 called "why this one matters most."
- Must be quota-free and worker-free, scoped to the caller's project root, and
  declare effects in `ContractRegistry`.

### ~~OBS-S02 — populate `heartbeatAgeSeconds`~~ — **DELETED**

There is no bug. The field is nil by design for silent turns (§2 R2). This slice
existed only because v1 misread a typo as a defect, and leaving it in the packet
is an active hazard: an implementer told to "fix the population path" who cannot
find a bug will wire in the pgid signal sitting right there, recreating PLS-S01's
incident under a new name. **Do not resurrect this slice.**

### Reopen: PLS-S03 (mid-round partial pointer)

`Pilot_Status_Liveness_Lie_Hotfix.md` deferred S03 behind an explicit gate: *one
more dogfood hang where agents still cannot diagnose without attaching to the
worker process.* **2026-07-30 is that gate tripping.** A bounded pointer to what
the worker has actually produced mid-round is a more direct answer to "is this
alive" for a silent turn than any amount of new liveness machinery — you stop
inferring and look. Evaluate it against OBS-S00 rather than building around it.

## 4. Truth owner and lie-prone layers

Truth owner: `ProcessOwnershipSurface.list` for the row set, `StreamLiveness` for
advancement, `ContractRegistry` for the verb surface.

Lie-prone layers:
- Any liveness answer sourced from pgid/process existence rather than the stream
  (the shipped defect this packet must not reintroduce).
- A default `ps` view whose row budget is spent on settled history.
- `--wait-for-change` returning on a *self-inflicted* change (its own read
  reconciling a row) and reporting phantom progress.

Implementation impact: `ProcessOwnershipSurface`, `StreamLiveness`,
`ContractRegistry`, CLI arg parsing. Mac/iOS impact: none. Driver impact: none.
Auth/privacy impact: none.

---

## 5. Proof

**A shape test is not evidence here.** Four packets shipped green. The proof must
include a turn that is *genuinely silent* — no `workerAnswerDelta`, no
`workerOutput`, no `stageOutput` for the observation window. A fixture that emits
activity events reproduces the easy case and proves nothing about this incident.

Works Test:

1. Dispatch a mutating run whose worker is silent for ≥60s (one-shot write or a
   terminal-only driver). A supervisor using **only** documented surfaces can
   state, correctly, that it is alive and expected to be silent — without
   `pgrep`, and without concluding it is dead.
2. With ≥20 settled loops on disk, the live run is visible in the **default**
   `ps` view without `--all`.
3. Asking for a field that is not in the schema is **distinguishable** from a
   field that is present and null.
4. On a run that *does* stream, `--wait-for-change --timeout 600` returns within
   seconds of a transition, not at timeout.
5. Kill the worker mid-flight: the waiter returns promptly with terminal state.
6. **Non-regression:** `heartbeatAgeSeconds` is still stream-only. Assert that a
   hot pgid with a cold stream reports silence — the PLS-S01 test, re-run.

```text
swift test --package-path Packages/AllnighterCore --filter Ownership
swift test --package-path Packages/AllnighterCore --filter RunActivity
swift test --package-path Packages/AllnighterCore --filter ContractRegistry
bash scripts/check.sh
```

**Named proof gap, not waived.** The codebase has no integration pattern that
dispatches a real subprocess and drives it through a full transition sequence;
existing tests are fixture-driven (`AsyncTeamLifecycleTests.swift:220-295`). Test
1 above therefore needs either a new harness or an honest manual works-test on the
founder's Mac. **Do not substitute a single-transition fixture test and call it
behavioral** — that substitution is precisely how attempts #1–4 shipped green.

Done when: OBS-S00 is ruled; a supervisor can distinguish *silent-and-expected*
from *stalled* from *dead* without `pgrep`; a live run is visible among settled
history; an unknown field name cannot masquerade as a null; and
`heartbeatAgeSeconds` remains stream-only.

## 6. Open questions

- **OBS-S00 is the blocking ruling** (§2b). Everything else is decoration until
  it is answered.
- **Is `--wait-for-change` on `ps`, or its own verb?** `ps` is a snapshot noun and
  this makes it blocking. Recommendation: keep it on `ps` — the caller already
  knows `ps` means "what is happening" — but the alternative is a `watch` verb.
- **Does reopening PLS-S03 replace OBS-S01 rather than complement it?** A partial
  output pointer may make the change-waiter unnecessary for the hard case.
- **Should it also cover foreign mutators?** The incident included a second
  session committing into the same tree unnoticed. Surfacing *other* owners'
  live runs is arguably the same fix; scoping it is a founder call.
