# Pilot — your live session is the PM; Allnighter runs the crew

Status: **SHIPPED — PL-S01–S07 landed (PL-S04 dead via MCP retirement); works-test evidence in §8**
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

| Slice | Deliverable | Reuses | Status |
| --- | --- | --- | --- |
| PL-S01 | `pmMode` on RelayState/Config + `awaitingPM` status + store/reconcile guard (awaitingPM never reconciled, no owner.pid) + tests | RelayState, RelayStateStore | DONE |
| PL-S02 | `RelayCoordinator.runExternalRound(relayId:submission:events:)` — parse/validate verdict, gate, pin, ONE dev turn, persist, return report; `RELAY_ROUND_IN_FLIGHT`; dirty-tree snapshot on the round | the whole shipped round machinery | DONE |
| PL-S03 | CLI `alln pair pilot start|handoff|status|watch` (+`--file`/stdin verdict-tail input; handoff blocks by default) + RelayJSON additions (pmMode, awaitingPM) + contracts | RelayCLI, RelayVerdictParser | DONE |
| PL-S04 | ~~MCP actions~~ **DEAD — MCP retired (`MCP_Retirement.md`); the CLI verbs in PL-S03 are the only agent surface** | — | DEAD |
| PL-S05 | Thread projection for external PM turns (submission verbatim as the PM turn; awaitingPM renders as a calm parked state, not running) | RelayThreadProjector | DONE |
| PL-S06 | **Night-shift handover:** `alln pair relay adopt --relay <id> --pm-worker <id>` converts a parked pilot relay to `pmMode: spawned` mid-flight — same state, same thread; the spawned PM reads the round log and keeps going. (Reverse — relay→pilot — falls out of the same move.) | RelayCoordinator.resume lineage | DONE |
| PL-S07 | Works test: drive a real pilot relay from a Claude Code session via the CLI (`pilot start` → 2× `handoff` → `done`), then `adopt` a parked pilot relay and let a spawned PM finish it | — | DONE — evidence in §8 |

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

## 8. Works-test evidence (PL-S07, 2026-07-16)

Relay `relay_47acbcce-e6b1-4b99-828b-97ae43de03c6` — scratch repo (tinylib
deliverable + `acceptance_test.py` truth owner), dev seat `model_fable`
(cursor-agent), piloted from a live Claude Code session, then adopted by
`model_sonnet` (claude_code — deliberately a different CLI than the dev seat).

**Round 1 (piloted, external).** `pilot start` parked `awaitingPM`; PM handover
via `pilot handoff --file round1.md` (blocking). Mid-round the piloting agent
session died (session limit) — the detached `handoff` process (owner.pid,
re-parented to launchd) kept running and the round stayed truthful in the store:
the successor session re-established state purely from `pilot status --json` +
the relay dir, no terminal stdout needed. The first dev dispatch stalled and the
coordinator's bounded retry re-dispatched a fresh dev child (~9-min-old child on
a ~45-min-old round when observed). Dev turn settled `awaitingPM` with an honest
report: files implemented, but its own session shell allowlist (`Shell(ls)` only
in `~/.cursor/cli-config.json`) blocked `python3`/`git` — it explicitly refused
to fake-green or claim an unmade commit. Resilience evidence: agent death +
detached handoff survival + bounded retry, all without corrupting the round.

**Round 2 (piloted, external).** PM independently ran the acceptance test
(ALL PASS, exit 0) and handed over a correction: the order required a commit and
nothing was committed; delete the stray `run_check.sh`. Foreground `handoff`
returned the dev report on stdout. Dev remained allowlist-blocked (couldn't even
edit its own config), reported the blocker explicitly with zero fake-green, and
asked for the permission fix — correct honest-failure behavior end to end.

**Round 3 (adopted, spawned) — first live `relay adopt`.** `alln pair relay
adopt --pm-worker model_sonnet --max-rounds 5` converted the parked pilot relay
mid-flight. The spawned PM correctly inherited the piloted story on its first
turn: it knew the code was already verified, knew the dev was environment-blocked
and honest, verified truth itself against the repo (not prior reports), finished
the mechanical remainder (cleaned strays, committed exactly `tinylib.py` +
`tinylib_cli.py` as `6408ea3`), re-ran acceptance against committed HEAD, and
settled `done` in one round with a substantive note.

**Verification (by the piloting seat, post-done):** `python3 acceptance_test.py`
at HEAD `6408ea3` → ALL PASS, exit 0. Round log arc exact: rounds 1–2
`hasExternalSubmission: true` / no `pmRunId` / `devRunId` set; round 3
`hasExternalSubmission: false` / `pmRunId` set. Thread arc exact: user-authored
PM turns (pm1, pm2, no runId) interleaved with `model_fable` dev turns, then a
`model_sonnet` worker PM turn (pm3, runId set). Relay ceiling honored (3 of 5,
piloted rounds counted).

**Defect findings (recorded, not fixed here):** (1) the dev prompt gets the
execution-playbook preamble injected twice (prompt-assembly duplication);
(2) cursor-agent dev turns are subject to the user's global
`~/.cursor/cli-config.json` shell allowlist even under `--trust` — a
`Shell(ls)`-only allowlist silently caps the dev seat (works-test unblocked via
a project-scoped `.cursor/cli.json`); (3) the spawned PM seat has full shell and
may do dev-seat work itself when convenient — acceptable per §6 (no PM
write-locking) but worth knowing.

**Verdict: PASS.**
