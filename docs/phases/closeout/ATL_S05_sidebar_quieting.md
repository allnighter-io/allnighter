# ATL-S05 — sidebar attention quieting (optional)

Last open item from the archived Agent Team Loop packet
(`docs/archive/phases/Agent_Team_Loop.md`), where it was one line:

> Prefer one project-level "N loops need you" over amber on every historical
> `PM Relay: SPEC` row.

That is a hint, not a spec. This doc supplies the missing acceptance criteria so
it can be implemented without inventing product meaning.

## Problem

Every historical relay thread keeps an amber unread dot forever. The founder's
sidebar shows a column of amber against `PM Relay: SPEC` rows from weeks ago.
Amber therefore means "old" far more often than it means "act", so the signal is
worthless exactly when it should matter.

## Product rule

**Amber is reserved for a loop that is actually waiting on the human.**

| Relay state | Rail treatment |
| --- | --- |
| `escalated` — awaiting a founder answer | **amber**, this is the only "needs you" |
| `awaitingPM` — parked for an external PM | amber |
| `running` | no attention colour; running is not a request |
| `done` / `stopped` (incl. `founder stopped`) | **no attention colour, ever**, regardless of unread turns |

A terminal relay can still show plain unread styling if the rail already does
that for ordinary threads — it must not show the *attention* colour.

Roll-up: show one project-level count of genuinely-waiting loops rather than
per-row noise. Copy: `N loops need you` (singular `1 loop needs you`). Zero →
render nothing, not "0 loops".

## Truth owner

Relay lifecycle is `RelayState.status`, read through the store — same source the
ATL-S04 chrome uses (`RelayStatusLoader`). **Do not infer lifecycle from thread
turn prose or from turn counts**; that is a standing inference ban in the packet
and there is now a precedent bug from breaking it.

Attention derivation lives with the existing unread logic
(`UnreadDerivation` / `ThreadsPresenter.unreadNeedsAttention`,
`ThreadRailComponents`). Extend it; do not fork a parallel rule.

## Out of scope

- Redesigning unread for non-relay threads. Ordinary chat/team threads keep
  today's behaviour exactly.
- Any change to relay start/stop/status behaviour.
- The `6/7 ready` pill or capacity surfaces.

## Works Test

- Core/presenter unit tests: escalated → attention; running → none; done →
  none; `stopped` with unread turns → none. The last one is the actual bug.
- Roll-up count matches the number of escalated/awaitingPM relays; zero renders
  nothing.
- Non-relay thread behaviour is unchanged (regression test).

## Visual proof — REQUIRED

This is a visible surface, so `docs/gui/Visual_Proof_Gate.md` applies and
closeout language is `implemented, visually unverified` until a **separate**
layout-watcher passes it. The implementing agent may not be its own watcher.

Add a fixture rendering a rail with a mix: one escalated relay (amber), one
running, one founder-stopped with unread turns (must NOT be amber), plus
ordinary threads.

**The fixture must actually show the thing being proved.** Two of three ATL
fixtures failed on precisely this — a capture that does not exercise the state
manufactures false confidence. Verify your own render before handing it over.

```bash
bash scripts/gui_proof.sh <fixture>
```

Baseline that must not regress: 2544 tests / 0 failures,
`alln dev export-contracts --check` clean, `bash scripts/check_gui_proof.sh` ok.

## Rules

Explicit-path commits. Leave the two pre-existing dirty files alone. Never
`git reset --hard`, never rewrite history on `feat/design-chain`. Do not weaken
or skip any existing assertion to reach green.
