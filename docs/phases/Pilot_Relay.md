# Pilot — your live session is the PM; Allnighter runs the crew

Status: **Specced — sibling mode of the shipped PM Relay (`PM_Relay.md`), same substrate**
Owner: AllnighterCore + CLI (GUI observes for free)
Updated: 2026-07-16

> One sentence: **Pilot** = this session is the PM, Allnighter is the crew chief
> (transport, write lock, danger gate, baseline, durable state, thread). **Relay** =
> Allnighter holds both seats so the clock can run without you. Same rails, one
> state machine — the only question is who holds the PM seat.

---

## 0. Why this exists

The founder (and every future user) often already lives in a Claude Code / Cursor /
Codex session that has deep context on the work. Forcing that user to spawn a *second*
PM brain — and lose the session's context — just to get the relay's rails is a habit
tax. Pilot removes it:

> The session you're already in writes the handovers and judges the reports. Allnighter
> contributes exactly what the session can't: safe dispatch of the dev seat, the danger
> gate, baseline pinning, the write lock, durable round state, and the inbox thread.

The three jobs that were fused in "PM" come apart cleanly:

| Job | Relay (spawned PM) | Pilot |
| --- | --- | --- |
| **Judgment** (what's next) | spawned PM model | **your live session** |
| **Transport + rails** | Allnighter | **Allnighter** (unchanged) |
| **Clock** (advances with nobody there) | Allnighter | **nobody — pull-based by design** |

Pilot deliberately has **no clock**: the loop advances only when the piloting session
submits. That is not a weakness to engineer around — it is the mode's definition. The
upgrade path when you want a clock is §5.

---

## 1. Decisions (locked by this doc)

1. **One substrate, two entries.** No second state machine, no parallel stores. Pilot
   is `RelayState.pmMode: spawned | external` plus one new durable status,
   `awaitingPM`. Everything shipped in PM_Relay — RelayVerdict, HandoverGate, baseline
   pinning, RelayStateStore, ceilings, thread projection, orphan reconcile — is reused
   as-is.
2. **Naming.** Product words: **Pilot** (you drive) / **Relay** (Allnighter drives).
   CLI: a `pilot` verb family under the existing `pair` namespace. Code: `pmMode`
   `spawned|external`. No renames of the shipped relay ("Night Relay" etc. rejected —
   relay stays relay).
3. **Two verb families, not a flag.** `alln pair pilot start|handoff|status|watch`
   beside `alln pair relay ...`. Easier to say out loud; both are thin projections
   over the same coordinator.
4. **CLI is the only agent surface.** MCP is retired (`MCP_Retirement.md`, founder
   call 2026-07-16) — piloting sessions drive the loop by running `alln` directly.
   Every CLI agent has a shell; the integration cost is one context line.
5. **The blocking handoff IS the product.** `alln pair pilot handoff` blocks until
   the dev turn settles and PRINTS the dev's report + round envelope. From a
   Claude/Cursor session the whole loop is: run command → read report in the command
   output → think → run command. No polling ceremony on the happy path
   (`--no-wait` + `watch`/`status` exist for long dev turns).
6. **Verdict format is identical.** The piloting session submits the same 3-field
   RelayVerdict + handover prose the spawned PM emits — a markdown file (or stdin)
   whose tail the existing parser extracts. One schema, one gate, both modes.
7. **Escalate keeps its meaning.** In pilot mode `escalate` = the piloting session
   raising a question to the HUMAN: relay parks (`escalated`), the inbox thread
   raises `needsAttention`, and `resume`/the GUI answer row work unchanged. `done`
   unchanged.
8. **Pilot is the agent-first front door; Relay is the graduation.** Positioning: you
   adopt Allnighter without changing where you work (Pilot from your IDE), and when
   you trust the loop you hand Allnighter the PM seat and sleep (Relay). One story,
   two throttles.
9. **Seat-mode vocabulary reserved for the full matrix.** `pmMode` today; a future
   `devMode: spawned | external` names the deferred external-dev mode (Allnighter is
   PM, your other terminal is dev). Named, not built.

---

## 2. The loop

```text
your session (PM)                        alln (crew chief)
──────────────────────                   ────────────────────────────────
read repo, judge, write     pilot start --doc SPEC.md --dev-worker <id>
handover + verdict      →   creates RelayState(pmMode: external, status: awaitingPM)

                        →   pilot handoff --relay <id> --file round.md   (BLOCKS)
                            parse verdict (same parser) → HandoverGate →
                            pin baselineHead → ONE dev turn under the write
                            lock → capture headAfterDev + dev report →
                            persist round → status back to awaitingPM
read dev report          ←  report + round log returned in the same call
review actual commits,
next handover           →   pilot handoff ...        (repeat)
verdict: done/escalate  →   relay settles / parks exactly like today
```

- **`awaitingPM` is a parked, unowned state.** No process lives between rounds; no
  owner.pid is written for it, and orphan reconciliation MUST ignore it (only
  `running` with a dead owner reconciles). A pilot relay can sit parked for a week.
- **Round log truth:** external rounds have `pmRunId = nil`; the submitted handover
  + verdict are stored verbatim (`handoverSource: external`). The thread projector
  renders the submission as the PM turn — the inbox shows a pilot relay exactly like
  a spawned one, so the Mac app is the observer while the IDE is the cockpit.
- **Ceilings:** `maxRounds` and stagnation apply unchanged; `--until` is meaningless
  without a clock and is rejected on `pilot start`.
- **Read-only PM enforcement is N/A** (there is no PM spawn to constrain, and the
  relay dropped the mechanism entirely — `Relay_ReadOnly_Removal.md`). The dev
  seat's rails are identical in both modes.

## 2.1 The write-lock boundary (the one real hazard)

The piloting session may edit the repo between rounds — that is §4.2's "PM may fix
things itself," externalized, and it lands in the next round's baseline range like
any PM mutation. The rules that keep it safe:

- **`handoff` is the mutation boundary.** While a dev turn is running, `handoff`
  refuses (`RELAY_ROUND_IN_FLIGHT`) — one mutating worker at a time, unchanged law.
- **Baseline pins whatever HEAD is at handoff.** PM-session commits show up honestly
  in the next range; nothing is hidden.
- **Dirty tree at handoff is recorded, not blocked:** GitObserver's `dirtyFiles`
  snapshot is stored on the round and surfaced in status/report — honesty over
  ceremony (the founder's own manual loop has exactly this property today).

---

## 3. What this answers (the founder's open questions)

| Question | Answer |
| --- | --- |
| "Never spawn a PM — my session is the PM" | Pilot mode, exactly. Judgment never leaves your session. |
| Automate while I'm in this IDE? | Yes — one blocking `handoff` call per round; the playbook loop plus Allnighter's rails. |
| Automate after I leave? | Not in pilot (no clock, by definition). Either come back and `handoff` again — state is durable — or **hand the relay to the night shift** (§5). |
| Can't Allnighter push to my chat? | No, and it doesn't try. Pull-based: blocking calls + `watch`/`status`. |
| Two products or one? | One substrate, two entries. Marketing: "Pilot: stay in the cockpit. Relay: go to sleep." |

---

## 4. Implementation slices

| Slice | Deliverable | Reuses |
| --- | --- | --- |
| PL-S01 | `pmMode` on RelayState/Config + `awaitingPM` status + store/reconcile guard (awaitingPM never reconciled, no owner.pid) + tests | RelayState, RelayStateStore |
| PL-S02 | `RelayCoordinator.runExternalRound(relayId:submission:events:)` — parse/validate verdict, gate, pin, ONE dev turn, persist, return report; `RELAY_ROUND_IN_FLIGHT`; dirty-tree snapshot on the round | the whole shipped round machinery |
| PL-S03 | CLI `alln pair pilot start|handoff|status|watch` (+`--file`/stdin verdict-tail input; handoff blocks by default) + RelayJSON additions (pmMode, awaitingPM) + contracts | RelayCLI, RelayVerdictParser |
| PL-S04 | ~~MCP actions~~ **DEAD — MCP retired (`MCP_Retirement.md`); the CLI verbs in PL-S03 are the only agent surface** | — |
| PL-S05 | Thread projection for external PM turns (submission verbatim as the PM turn; awaitingPM renders as a calm parked state, not running) | RelayThreadProjector |
| PL-S06 | **Night-shift handover:** `alln pair relay adopt --relay <id> --pm-worker <id>` converts a parked pilot relay to `pmMode: spawned` mid-flight — same state, same thread; the spawned PM reads the round log and keeps going. (Reverse — relay→pilot — falls out of the same move.) | RelayCoordinator.resume lineage |
| PL-S07 | Works test: drive a real pilot relay from a Claude Code session via the CLI (`pilot start` → 2× `handoff` → `done`), then `adopt` a parked pilot relay and let a spawned PM finish it | — |

## 5. The night-shift handover (PL-S06) is the strategic unlock

"What you cannot get without a spawned PM" stops being a wall and becomes a throttle:
pilot the first rounds from your IDE while context is hot, then `adopt` hands the SAME
relay — state, round log, thread — to a spawned PM for the night. Wake up, read the
thread, take the seat back or let it finish. That is the full "own the bookends"
story in one feature.

## 6. Non-goals

- A push channel into IDE sessions (pull-based, permanently).
- External-dev mode (named as `devMode`, still deferred).
- A second state machine, store, or thread shape for pilot.
- Any PM-session write-locking beyond the handoff boundary (§2.1) — the piloting
  session's own edits are its own business, recorded honestly.

## 7. Routing

| Work | Read |
| --- | --- |
| Round machinery to reuse | `AllnighterEngine/RelayCoordinator.swift` |
| State/status/store | `AllnighterCore/RelayState.swift`, `AllnighterEngine/RelayStateStore.swift` |
| Verdict parse (CLI file path) | `AllnighterCore/RelayVerdict.swift` |
| Gate | `AllnighterCore/HandoverGate.swift` |
| CLI surface | `AllnighterCLI/RelayCLI.swift` |
| Thread projection | `AllnighterEngine/RelayThreadProjector.swift` |
| The shipped sibling | `docs/phases/PM_Relay.md` |
