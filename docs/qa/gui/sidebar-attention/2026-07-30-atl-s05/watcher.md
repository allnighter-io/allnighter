# sidebar-attention — layout-watcher verdict (ATL-S05)

Fixture: `home-rail-loops-attention`
Command: `bash scripts/gui_proof.sh home-rail-loops-attention`

Separate agent; did not write the code. Told that fixtures twice earlier in this
project captured a state that did not exercise the feature, so it verified the
states were genuinely present before judging.

## VERDICT: PASS — P1: none, P2: none

## The regression case this slice exists to fix

> The finished/stopped loop row is "PM Relay: SPEC (stopped)". I checked it
> closely — it carries **no dot whatsoever**, amber or otherwise. This is the
> exact regression case the fix targets, and it renders correctly.

Previously every historical finished loop kept an amber dot forever, so the rail
was a wall of stale amber and the colour meant nothing.

## All four states, side by side in one capture

| Row | State | Rendering |
| --- | --- | --- |
| `PM Relay: SPEC` | escalated | **amber dot** — the only "needs you" |
| `PM Relay: Agent Team Loop` | running | **blue** dot, correctly not amber |
| `PM Relay: SPEC (stopped)` | terminal | **no dot at all** |
| `Unread worker reply` | ordinary thread | amber, unchanged behaviour — not a loop |

> Capture genuinely exercises the three required loop states side by side — this
> is not a repeat of the earlier false-capture problem.

## Roll-up

> Header roll-up "1 loop needs you" appears next to the project label, fully
> legible, not clipped, in amber to match the dot colour it is counting. Count of
> 1 is consistent with the single amber-dotted loop row; the second amber dot is
> an ordinary thread, not a loop, so it correctly falls outside this count.

The roll-up counting loops rather than amber pixels is the subtle part, and it is
right.

## P1 — broken (blocks)

none

## P2 — advisory

none. The stopped row's text starts flush where a dot would sit, which reads as
intentional placeholder alignment rather than a defect.
