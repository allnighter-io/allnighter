# Agent-Facing Run Observability

Status: **Draft — incident-derived 2026-07-30, not started**
Owner: Founder ruling pending; implementer TBD
Updated: 2026-07-30

Founder intent: an agent supervising `alln` work could not tell whether a
delegated seat was advancing, stalled, or dead. It fell back to `pgrep`. Three
small fixes, no new subsystem.

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
| `alln ps --json` → `streamAge` | **`None` on every row, every poll.** The one field whose job is "is this advancing" was null. |
| `alln ps --json` → filter `status ∈ {running, live}` | Matched **nothing** while the run was demonstrably alive. Concluded the work was finished. It was not. |
| `pgrep -f "alln run"` | **Correct.** A raw OS call was the only reliable signal. |

Cost: one slice was declared dead while still running; another finished and sat
uncommitted because the supervisor had stopped watching. The supervisor also
missed that a *second* session was mutating the same working tree, because
`alln ps` never surfaced it either.

**That a raw `pgrep` outperformed `ps`, `status`, and the journal is the finding.**

---

## 2. Root cause — three separate defects, ranked

### R1 — There is no "wake me on change" primitive

Only two waiting modes exist: `--wait-for terminal` (blind until done) or manual
polling. Nothing returns on *progress*. So a supervising agent must choose
between a long blackout and a poll spin, and both failed here.

### R2 — `streamAge` is null

Every row, every call, across two hours. Whatever populates it did not. Every
downstream judgment was therefore a guess.

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
> reporting alive while the stream is dead. R3 is the real defect; see OBS-S03.

---

## 3. Slices

### OBS-S01 — `alln ps --wait-for-change --timeout <seconds>` *(the fix)*

Blocks until the **first state transition of any run owned by this caller**, then
returns the changed rows and exits. On timeout, returns the unchanged set and a
`timedOut: true` — never an error, never a hang.

"State transition" is deliberately coarse and cheap — status change, a new round,
or a stream-liveness bucket crossing. It does **not** need to be a general event
bus; it needs to be the difference between a listener and a poller.

- Scope to the caller's canonical project root by default, consistent with
  `ProcessOwnershipSurface.list`'s existing reconcile-on-read scoping.
- Reuse the waiter machinery behind `team status --wait-for`; do not build a
  second one.
- Must be **quota-free and worker-free** — it observes, it never dispatches.
- Free twin obligation does not apply (it starts nothing), but it must declare
  effects in `ContractRegistry` like every other verb.

**Why this one matters most:** it replaces both failure modes with one call, and
it is the agent-facing counterpart to the human notification spine that already
exists. It is the difference between a PM that listens and a PM that guesses.

### OBS-S02 — populate `streamAge`

It is null. That is a bug, not a design question. Code SSOT is `StreamLiveness`
(archived `Core_Loop_Improvements.md` / `Pilot_Status_Liveness_Lie_Hotfix.md`),
which already computes this for `pilot status`; `ps` rows are not getting it.

Fix the population path. **Do not** substitute process existence when the stream
value is unavailable — an unknown age must read unknown, never zero, never fresh.
That substitution is precisely the shipped liveness lie.

### OBS-S03 — the live row must be findable in the default view

Supersedes the `live: bool` idea (§2). Two changes, either or both:

1. **Order live rows first.** A run that is advancing outranks 28 settled loop
   records. This alone fixes the incident.
2. **`--kind run|loop`.** Let a caller ask for one object type instead of
   filtering a mixed array on a status vocabulary it must already know.

**If a `live` boolean is added anyway**, it must be derived from the same source
as `streamAge` (OBS-S02), never from pgid or process existence. A `live: true` on
a dead stream is a worse lie than a missing field, and this repo has already paid
for that once.

---

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

Works Test — reproduce the incident and show it cannot recur:

1. Start a long mutating run with `--no-wait`.
2. `alln ps --wait-for-change --timeout 600` returns **within seconds** of the run
   changing state, not at timeout.
3. `alln ps --json` shows a **non-null** `streamAge` for that run on every call.
4. With ≥20 settled loops on disk, the live run is **visible in the default view**
   without `--all`.
5. Kill the worker mid-flight: the next `--wait-for-change` returns promptly with
   the terminal state — it does not hang to timeout.

```text
swift test --package-path Packages/AllnighterCore --filter Ownership
swift test --package-path Packages/AllnighterCore --filter StreamLiveness
swift test --package-path Packages/AllnighterCore --filter ContractRegistry
bash scripts/check.sh
```

Missing proof / waiver: the honest regression test is a **supervision** test, not
a shape test — assert that a caller which only ever calls `--wait-for-change`
observes every state transition of a run from dispatch to terminal. A test that
merely proves the flag parses would not have caught this incident.

Done when: a supervising agent can dispatch, block once, and be woken on every
transition; `streamAge` is never null on a live row; and a live run is visible in
the default `ps` view with dozens of settled loops on disk.

## 6. Open questions

- **Is `--wait-for-change` on `ps`, or its own verb?** `ps` is a snapshot noun and
  this makes it blocking. Recommendation: keep it on `ps` — the caller already
  knows `ps` means "what is happening" — but the alternative is a `watch` verb.
- **Should it also cover foreign mutators?** The incident included a second
  session committing into the same tree unnoticed. Surfacing *other* owners'
  live runs is arguably the same fix; scoping it is a founder call.
