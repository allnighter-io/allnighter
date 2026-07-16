# Panel — session-led blind jury on any target

Status: **SHIPPED — PN-S01–S06 built (piloted delivery #9, relay_17eb0a3d, Grok CLI
dev seat, 6 rounds incl. one works-test fix: --seat alias resolution at start).
Works test PASSED LIVE (panel_c8f410b5): 2 rounds, 3 blind seats on 3 CLIs
(claude RO-mode / grok clone / cursor clone), target-hash change proven between
rounds, 29 structured findings, the memory spec hardened twice by its own jury,
done-by-declaration. Clone proof-of-truth: fake mutating seat, real tree
byte-identical. Bonus finding: HandoverGate blocked the PM's own handover on a
literal mention (danger-not-doubt held; rephrase-and-resubmit worked).**
Owner: AllnighterCore + CLI
Updated: 2026-07-16
Polish follow-up: first-real-use fixes (panel_753613c7) specced in
[`Panel_Polish.md`](Panel_Polish.md) — PP-S01–S03.

> One line: **Panel hardens the judgment, Pilot builds the work, Relay runs the
> night.** Same physics as Pilot: judgment stays in the live session; Allnighter
> contributes blind fan-out, mechanical read-only safety, durable rounds, and the
> thread.

## 0. Identity (widened — the mentor's load-bearing catch)

Panel is NOT a phase-doc tool. It is **"I am always the lead; the seats are always
a blind jury"** — for any target a session judges: a spec, a PR, an architecture
decision, a bug, a kill-or-commit call. Spec hardening (the Spec Review loop) is
the **hero recipe**, not the product's name. `--doc` stays the default target flag;
the identity never hard-codes to `docs/phases/`.

Pilot removed the copy-paste monkey for *building*. Panel removes it for *thinking*.

```text
alln panel start --doc docs/phases/X.md --project .        # zero config: default roster
loop:  alln panel round --panel <id>                        # round 1: built-in brief; BLOCKS
       → N structured finding sets return in-call, blind to each other
       session refutes/synthesizes → edits the target (session's own hands)
       alln panel round --panel <id> --brief focus.md       # round 2+: focus brief
       repeat · alln panel done --panel <id> --note "…"
then:  alln pair pilot start --doc <same>                   # harden → build, one cockpit
```

## 1. Decisions (locked)

1. **The session is the synthesizer.** No spawned merge-brain, no ranking.
   Allnighter stores and returns findings verbatim; the refutation gate is the
   live session's judgment.
2. **Blind fan-out is LAW** (Spec_Review.md): N independent dispatches, no
   shared transcript, seats never see each other's output within a round.
3. **Structured findings — verbatim ≠ unstructured.** Spec Review (né Pressure Test) named the
   failure mode: six walls of text = manual fan-out with nicer chrome. Every seat
   returns a small finding schema: `{claim, severity, evidence (cite file/line or
   quote), proposedChange, }` — and **"no material findings" is a first-class
   valid answer** (an empty findings array with a stated reason, never padding).
   Allnighter validates shape only; content judgment is the session's.
4. **Roster = the team catalog.** No new roster noun. `--team <alias>` resolves a
   TeamPreset (built-in like `code_spec_review` or any user team) into
   seats — DX4-style fuzzy resolution: unique match resolves and IS ECHOED;
   ambiguous errors LIST candidates (display name + seat count); no match lists
   available teams. Remembered last-used panel team per project; zero-config
   `panel start` uses remembered-else-lane-default and says so. `--seat
   <alias>:<lens>` is power mode that overrides/extends.
5. **Lenses:** from the team's seat purposes or `--seat` declarations; optional
   `--lens-file <lens>=<path>` for standing instructions. Per-seat prompt = lens
   instruction + brief verbatim + target path (re-read fresh — anchor, never
   payload).
6. **Briefs: built-in round 1, custom later.** Round 1 default brief:
   "Stress-test this target; structured findings only; no material findings is
   a valid answer." `--brief <md>` (or `--brief -` stdin) for focus rounds. The
   scaffold's suggested sections include a **rejection-carry line** ("Refuted last
   round: … — do not re-litigate") and a **stance line** (`stance: edit-in-place |
   propose-first`) so the founder always knows which synthesis contract the
   session is in. Stances are convention, never modes (the deleted PRJ approval
   gate stays deleted).
7. **Read-only by MECHANISM — N concurrent seats make it real safety.** Drivers
   with true read-only modes use them (claude plan / codex sandbox — the salvaged
   capability table in Unified_Run_Model.md); all other drivers run against an
   **ephemeral APFS clone** (copy-on-write `clonefile`, deleted after the turn; a
   copy, not a git worktree). **"No seat is ever refused" is the law; clonefile is
   sequenced, not skipped** (§3). Panels NEVER take the mutating write lock —
   read-only rounds may run beside a pilot/relay dev turn (documented invariant).
8. **Run-truth anchors:** each round pins the target's **content hash** at
   dispatch (panel's analog of the relay's baseline HEAD) — round N+1 provably
   attacks the CURRENT text, and mid-round edits are detectable. Session edits
   between rounds: expected. During `running`: refused (`PANEL_ROUND_IN_FLIGHT`).
   `panel start` emits an ADVISORY (never a refusal) when the target is
   untracked/dirty: "commit first so edit-in-place synthesis stays one revert
   away" — the founder's undo-safety nudge, mechanical via GitObserver reads.
9. **State machine mirrors pilot:** `awaitingPM | running | done`; parked-unowned
   between rounds (orphan reconcile skips `awaitingPM`); a round with failed/
   timed-out/empty seats still SETTLES with per-seat status + the findings that
   arrived — the session chooses `--seats a,b` rerun; no fake convergence, done
   only by declaration; `--max-rounds` ceiling.
10. **One substrate:** round dispatch = the answer-team run substrate (TeamRun, N
    read-only workers) + one additive capability (per-seat messages). Panel
    session state = `PanelState` + store beside RelayStateStore. No second
    team-run JSON family.
11. **Naming: top-level `alln panel`.** `pair` means the PM↔dev couple (and
    device pairing); a jury is not a pair. Product language everywhere: Pilot =
    session leads a mutating crew · Panel = session leads a read-only jury ·
    Relay = Allnighter leads when you leave. (Retired words like "fan-out" never
    appear in user-facing strings.)
12. **Panel feeds memory.** Findings that survive refutation + seat-behavior
    observations (with receipts) are prime MEMORY.md fodder via the done-note
    convention (Folder_Native_Memory.md owns it). Thread projection for free
    (brief = user turn; each report = worker turn).

## 2. Surface

- `alln panel start --doc <path> --project <id|path> [--team <alias>] [--seat
  <alias>:<lens> …] [--max-rounds N] [--json]` → panelId, roster echo, target-hash,
  dirty-target advisory, scaffolded brief path, exact next command.
- `alln panel round --panel <id> [--brief <md>|-] [--seats a,b] [--no-wait]
  [--json]` → BLOCKS; per-seat structured findings verbatim + per-seat status;
  NDJSON streams seats as they settle (the session starts reading early).
- `alln panel status|watch|scaffold-brief|done` — mirror the pilot verbs,
  including the DX5 recovery semantics (dead-owner → "run panel watch").
- Bootstrap recipe (~6 lines) added to `alln bootstrap`: start → round → refute →
  edit → done → **`alln pair pilot start --doc <same>`** — harden then build
  without leaving the cockpit.

## 3. Slices (sequenced so clonefile never gates first joy)

| Slice | Deliverable |
| --- | --- |
| PN-S01 | `PanelState` + store + state machine (parked/unowned, in-flight refusal, target-hash pinning) + tests |
| PN-S02 | Per-seat blind dispatch on the answer-run path (additive per-seat messages) + finding-schema validation ("no material findings" first-class) — **v0 seats: read-only-enforcing drivers only** (claude/codex) |
| PN-S03 | `PanelCoordinator.runRound` — blocking + NDJSON per-seat settle, partial-failure settlement, `--seats` rerun, ceilings |
| PN-S04 | CLI verbs (`alln panel …` top-level) + team-alias roster resolution + remembered team per project + envelopes/contracts/help + bootstrap recipe |
| PN-S05 | Thread projection + cold-agent works test (below) |
| PN-S06 | **Clonefile isolation** for non-enforcing drivers (+ fake-mutating-seat proof that the real tree is untouched) — "no seat refused" goes live |

## 4. Works test (cold agent, not just the founder)

A FRESH agent session given only the bootstrap snippet: `alln panel start --doc
<real doc> --project .` (zero config — default roster echoed) → round 1 with the
built-in brief returns 3 blind structured finding sets in one blocking call →
the session refutes ≥1 finding, edits the doc, commits → round 2 (focus brief via
stdin, rejection-carry line) provably attacks the new text (hash changed) → done
with a survivors note → `alln pair pilot start --doc <same>` chains into a build
round. Verify: transcripts show no cross-seat leakage; per-seat statuses honest on
an induced seat failure; panel thread readable in the inbox; findings verbatim;
real tree untouched (v0: RO drivers; PN-S06: clone proof). Filters green;
contracts regenerated.

## 5. v1 boundary vs Spec Review (named so builders don't rebuild it)

Panel v1 = transport + blind RO safety + durable rounds + finding schema +
session judgment. Spec Review methodology — impact ledger, (lens,model)
scoreboard, spawned refuter seat, clean-room rival protocols — stays in
`Spec_Review.md` as METHOD the session may apply by hand, and as candidate
future upgrades. Building any of it into Panel v1 is scope creep; shipping walls
of unstructured prose and calling it Panel is the opposite failure. Both are
named so neither happens silently.

## 6. Non-goals

- Auto-synthesis / spawned merge-brain (that would be Relay-for-judgment — a
  separate future decision). Scoring, ranking, leaderboards.
- Mutating panel seats, ever — a panel that edits is a pilot; use the pilot.
- A GUI requirement anywhere in the loop (the app is the observer, as with Pilot).
- V1/V2 "approval modes" — synthesis stance is the session's declared convention
  (decision 6), never product machinery.
