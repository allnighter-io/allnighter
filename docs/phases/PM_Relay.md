# PM Relay — automate the copy-paste monkey

Status: **Specced — supersedes up-front slicing as the front door**
Owner: AllnighterCore + CLI/MCP (GUI last)
Updated: 2026-07-15

> Vocabulary follows the locked cutover — **Chat / Delegate / Execute**, **Team**,
> **worker**, one `team.run` primitive. "PM" and "dev" are *role names for the two
> seats in a relay*, not new craft types.

---

## 0. What this is

The founder runs this loop by hand all day, every day:

1. A **PM** model (one CLI) reads the spec doc + the repo, writes a prose handover.
2. The founder **copy-pastes** it to a **dev** model (another CLI).
3. The dev builds, **commits**, and writes a delivery report.
4. The founder **copy-pastes** the report back to the PM with "next round please."
5. The PM reviews the actual commits, approves or flags, writes the next handover.
6. Repeat until the doc is delivered.

The founder contributes **nothing** between turns except transport. The PM Relay is
that transport, mechanized — plus the rails a human relay provides by accident
(eyeballs on danger, knowing when to stop, waking someone up when it's off the rails).

### The evidence (two real transcripts, 2026-07-15)

A real PM→dev→PM exchange (Ikiro Phase 87) proved the load-bearing fact: **the entire
process lives in the PM's prose.** In one round the PM, unprompted:

- chose **batch granularity** itself ("build together, I review after — not gated
  single-slice") — then for the *next*, riskier surface demanded gating ("stop with a
  Slice Packet … for my gated review before you implement");
- ran a **visual review** on rendered screenshots the dev left at repo paths, judged
  against design-system exemplars — not the code;
- verified the dev's claims against **actual commits** ("both items I flagged last
  round were done exactly");
- routed the **next phase of work** (launch-gate reasoning across three phase docs);
- refused to fake-green a check ("don't fake-green the smoke").

None of that needs an Allnighter mechanism. It needs a loop that carries the prose,
holds the safety rails, and never sleeps.

---

## 1. Why not slices? (what this supersedes)

The `WorkSlicePacket` queue (`Pair_Programming_Team.md`) exists because a **weak, free
executor** (GLM, 32K window) chokes on reads — orders had to be pre-decomposed,
pre-resolved, read-bounded *before* dispatch. That was life support for one regime,
and it leaked into the general design as "the planner must compile the doc into a
queue up front."

For the seats actually in use — frontier dev CLIs — decomposition up front is
unnecessary ceremony. **Granularity is a per-round judgment call by the PM**, made in
prose, differently for different surfaces (the same PM batched three slices in one
round, then demanded single-slice gating for the next). A compile step can't do that.

Consequences:

- **PPT-S13 (doc → packet compiler) is DEAD.** The relay makes decomposition lazy and
  conversational; there is nothing to compile.
- **The slice queue survives as the special case** for the weak-executor overnight
  regime (pre-bounded reads, touch allowlists). It is no longer the front door. The
  two can nest later: a PM handover for a big mechanical batch may *be* "run this
  queue" — not in V1.

---

## 2. The loop

```text
alln pair relay --doc <spec.md> --project . --pm-worker <id> --dev-worker <id> --until 07:00

        ┌──────────────────────────────────────────────────────────────┐
        │                    RelayCoordinator.loop                     │
        └──────────────────────────────────────────────────────────────┘
   round N:
     1. pin baseline ── git HEAD via GitObserver (read-only)
     2. PM TURN ────── prompt = doc path + baseline..HEAD + dev report (verbatim)
        (repo root,    PM reads the real diffs/artifacts itself — full repo access
         may mutate)   output = prose review + handover + RelayVerdict JSON tail
     3. parse verdict ─ continue │ done │ escalate      (the ONLY structure)
     4. HandoverGate ── danger scan over the handover text (blocks, or passes)
     5. DEV TURN ────── prompt = handover verbatim (+ standing dev preamble)
        (repo root,    dev builds, commits (its CLI owns git), writes report
         mutating)
     6. persist round ─ durable RelayState + NDJSON progress + thread transcript
     7. ceilings ────── --until / --max-rounds / consecutive-flag counter → stop
   → repeat with the dev's report as round N+1's input
```

- **Turn-based by construction.** Exactly one worker runs at a time; every mutating
  turn runs under the existing `RunService` write-lock path. The one-mutating-worker
  invariant holds because turns are sequential — there is never a concurrent pair.
- **No git watching needed.** Allnighter invoked the dev, so it knows when the turn
  ends. `GitObserver` only *reads* HEAD to pin the exact review range. (A future
  "external dev" mode — human's own CLI session, Allnighter watches commits — is
  named and deferred, §8.)
- **The doc is an anchor, not a payload.** The PM gets the doc *path* and re-reads it
  fresh each turn from the repo — no context-packet staleness, no paste truncation.

## 2.1 Better than the human relay (not just equal)

| Today (founder as transport) | Relay |
| --- | --- |
| PM sees only what got pasted (truncation, misses) | PM gets the dev's full report verbatim + the repo itself |
| PM trusts the dev's claim of what was committed | baseline HEAD pinned per round — PM reviews the exact delta |
| Human eyeballs are the danger gate | mechanical `HandoverGate` scan every round |
| Loop runs at human latency, working hours | zero inter-turn latency, `--until 07:00`, runs while you sleep |
| Loop dies silently if the human walks away | durable `RelayState`, resumable; escalation raises attention |
| Transcript lives in two chat windows | one Work Thread — the whole relay readable in the inbox |

---

## 3. Division of labor — mechanism vs judgment

| Concern | Owner | How |
| --- | --- | --- |
| Review depth, batching, gating, what "done" means for a slice | **PM (prose)** | proven in-band; never an Allnighter feature |
| Fix-it-myself vs send-it-back | **PM** | founder: "does not matter which way" — PM turn may mutate (§4.2) |
| Code, commits, branches, reverts | **dev's CLI** | Allnighter does no git — unchanged law |
| Checks/proof (tests, screenshots, smokes) | **repo**, invoked by whichever seat the PM directs | unchanged law |
| Turn transport, seat spawning (any CLI), warm workers | **Allnighter** | existing `RunService` / AgentOS runner |
| One-mutating-worker safety | **Allnighter** | turn-based loop + write lock |
| Danger stop (credentials, destructive git, signing, TCC) | **Allnighter** | `HandoverGate` (§5) |
| Termination + ceilings + escalation + durability | **Allnighter** | verdict + `--until`/`--max-rounds` + `RelayState` |

---

## 4. `RelayVerdict` — the only structure in the loop

Everything else is prose. The PM ends every turn with one small JSON block
(agent-first: real schema, published; three fields, not the old WorkOrder ceremony):

```text
RelayVerdict
  verdict     : continue | done | escalate
  handover    : String?     // required when continue — the verbatim text for the dev
  note        : String?     // done: closing summary · escalate: what the human must decide
```

### 4.1 Rules

- **Done is declared, never inferred.** Only `verdict: done` ends the relay happily.
  Missing/unparseable tail → one re-ask (same PM turn context), then `escalate`.
- **Escalate is a first-class outcome, not a failure.** The PM asking the founder a
  real question ("76/77 or 88 — say which") is the loop working. Escalation stops the
  relay, persists everything, raises attention on the thread, and `--resume` continues
  with the founder's answer injected as the next PM input.
- The verdict tail is stripped before the handover reaches the dev — the dev sees
  exactly what the founder would have pasted.

### 4.2 The PM may fix things itself

Founder decision (2026-07-15): when review finds small problems, the PM fixing them
directly or bouncing them to the dev are both fine. Mechanically free: the PM turn
already runs in the repo root under the same write-lock discipline, and turns are
sequential. If the PM commits, round N+1's baseline moves with it — the dev's next
review range is still exact. `--pm-read-only` exists for founders who want a
mechanically non-mutating reviewer (answer-shape seat), off by default.

### 4.3 Artifacts

Artifacts travel as **repo paths in prose** (exactly like the real transcript:
`artifacts/s87-stats/desktop-real-traffic.png`). The PM's own CLI reads them —
multimodal seats judge screenshots, text seats read reports. Allnighter adds nothing.

---

## 5. Safety — what replaces the human's accidental rails

1. **`HandoverGate`** — the existing gate shape (`TryFixGate`/`SliceGate`: *danger
   blocks, doubt doesn't*) run over the handover **text** each round: credentials,
   signing/distribution, destructive git, sandbox/TCC. The slice queue got this from
   the touch-allowlist; free prose needs the scan. Danger → `escalate`, never dispatch.
2. **Write lock, always** — every turn through the existing `RunService` path; the
   relay never invents a second dispatch route.
3. **Ceilings are hard caps** — `--until HH:MM`, `--max-rounds N` (default 20), and
   `--max-consecutive-flags N` (default 3: PM flagging the same failure N rounds in a
   row → `escalate`, breaking PM↔dev polite-loop deadlock — the real failure mode).
4. **Stall ≠ compaction** — reuse `SliceTerminalClassifier` + `StalledWorkDetector`
   unchanged; never kill a compacting worker.
5. **Honest reporting** — the relay surfaces what each seat returned; it never marks
   done on its own judgment. (The PM's "don't fake-green the smoke" discipline is the
   PM's; Allnighter's is: verdicts and returns are recorded verbatim, run-truth.)

---

## 6. Implementation slices

Small, contract-first, CLI/MCP before GUI — house rules.

| Slice | Deliverable | Reuses |
| --- | --- | --- |
| R-S01 | `RelayVerdict` + parser (tolerant tail-extraction, one re-ask policy) + published schema + tests | `firstJSONObject` pattern |
| R-S02 | Prompt templates: PM system+turn prompt (doc path, `baseline..HEAD`, dev report verbatim, verdict contract), dev preamble wrapper + tests | `PlannerTakeoverPrompt` shape |
| R-S03 | `HandoverGate.evaluate(handoverText:) -> Decision` + tests | `TryFixGate`/`SliceGate` |
| R-S04 | `RelayCoordinator` loop: turn dispatch via `RunService`, `GitObserver` baseline pinning, `RelayState` durable store (round log, verdicts, run ids), ceilings, stall reuse, NDJSON progress | `PairCoordinator` skeleton, `RunStore` folder pattern |
| R-S05 | `alln pair relay --doc <path> --project <id\|path> --pm-worker <id> --dev-worker <id> [--until HH:MM] [--max-rounds N] [--pm-read-only] [--resume <relayId>] [--json]` + `relay status` | `PairProgrammingCLI` |
| R-S06 | MCP: `pair_relay` / `pair_relay_status` / `pair_relay_resume` — full structured envelopes | `MCPPairHandlers` |
| R-S07 | Relay-as-thread: each relay is a `WorkThread`; rounds are turns; escalation raises `needsAttention` — the inbox shows the loop live for free | `ThreadStore`, threads GUI |
| R-S08 | Composer entry (GUI, last): `@`-link the doc, pick PM seat + dev seat, go — a team-lane preset (`pm_relay`: seat 1 PM, seat 2 dev) | attachments + team picker |

Pre-work (before R-S04): **post-cutover smoke** — the pair path hasn't run since the
AgentOS runner cutover (2026-07-02) and `MCPPairHandlers` is among the known test
failures; fix that first so the relay lands on proven dispatch.

---

## 7. Works Test — the acceptance is *the founder's day, unattended*

```bash
alln pair relay --doc docs/phases/<real-phase>.md --project . \
  --pm-worker <frontier-A> --dev-worker <frontier-B> --until 07:00 --json
```

Acceptance — the manual loop, made literal:

- Runs **round after round with no human relay**: PM reviews the actual commit range,
  writes the handover; dev builds and commits; repeat.
- Ends only on `done`, `escalate`, or a ceiling — never by inference.
- The write lock is never held by two workers; every handover passed the danger gate.
- Output: `{ relayId, rounds: N, verdict, roundLog: [ {baseline, head, pmRunId,
  devRunId, verdict} ] }` — plus the whole exchange readable as one thread.
- The founder **wakes up** to either a delivered doc or one specific question.

If the founder is still pasting, the feature is not done.

---

## 8. Non-goals (V1)

- Up-front decomposition of any kind (that's the PM's call, in prose, per round).
- Parallel dev seats (one mutating worker — inviolable).
- External-dev mode (dev outside Allnighter, git-commit watching as the turn signal) —
  real, named, later.
- Nesting the slice queue under a relay handover — later.
- Allnighter judging correctness, doing git, or authoring checks — unchanged laws.
- Streaming dev tokens to the UI (the value is waking up to results).

---

## 9. Routing

| Work | Read |
| --- | --- |
| Loop skeleton / seats / ceilings | `AllnighterEngine/PairCoordinator.swift` |
| Dispatch + write lock | `AllnighterEngine/RunService.swift`, `RunWriteLock.swift` |
| Baseline pinning | `AllnighterEngine/GitObserver.swift` |
| Gate shape | `AllnighterCore/TryFixGate.swift`, `SliceGate.swift` |
| Stall / compaction | `AllnighterEngine/StalledWorkDetector.swift`, `SliceTerminalClassifier.swift` |
| Verdict-tail extraction pattern | `firstJSONObject` (proposal-engine lineage) |
| Thread projection | `AllnighterEngine/ThreadStore.swift` |
| CLI / MCP | `AllnighterCLI/PairProgrammingCLI.swift`, `MCPPairHandlers.swift` |
| What this supersedes | `Pair_Programming_Team.md` (queue = weak-executor special case; PPT-S13 dead) |
