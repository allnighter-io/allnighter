# capacity-strip — layout-watcher verdict (CAP-S10, Mac capacity strip)

Fixtures: `capacity-strip`, `capacity-strip-refreshing`
Command: `bash scripts/gui_proof.sh <fixture>`

Watcher was a separate agent that did not write the code, and was told that two
of three fixtures in an earlier round on this project captured a state that did
not show the feature at all — so it verified presence before judging.

## VERDICT: PASS — P1: none

> Confirmed both captures actually render the "YOUR BENCH" capacity strip table
> (not a blank/placeholder state) — six labeled rows with icons, bars,
> percentages, and age stamps are present in both images.

## Spec checks

| Requirement | Result |
| --- | --- |
| **One row per CLI, never two** | Confirmed. Six sibling rows. **Antigravity is a single row containing two stacked sub-bars** (Gemini 93% 6d 20h / Claude/GPT 60% 2d 3h) inside one row shell, not two table rows. |
| Fixed order | Exact: Codex/ChatGPT, Claude, Cursor, Grok, Kimi, Antigravity. |
| Two columns, **no bar in 5h** | Confirmed. Weekly has bar + % + remaining time; 5H WINDOW is text/numbers only, no bar rendered anywhere in that column. |
| `–` not an empty cell | Confirmed on Codex, Claude, Cursor, Grok. |
| Three colours, **nothing green** | Neutral, amber (Grok), red (Kimi). No green inside the table. No status-dot column. |
| Age on every row; unknown carries a reason | All six show an age. Claude shows `unknown — never sampled`, not a number. |
| **Only the refreshing row spins** | Exactly the Grok row's age slot becomes a spinner; every other row's age text stays **pixel-identical and fully legible**, not dimmed, greyed or blocked. |

## P1 — broken (blocks)

none

## P2 — advisory (named, not blocking)

- Weekly column renders remaining time as numeric text (`6d 3h`) with no literal
  clock glyph. A soft miss only if the spec intended an icon; not a break.
- A green dot by "Models" and an amber dot in the `6/7 ready` pill appear in the
  **global top bar** — pre-existing app chrome, outside the capacity table, not
  part of the row colour system under test.

## Note

The two checks that carried real risk both passed: the dual-pool seat rendering
as one row rather than two, and the refresh isolating to a single row instead of
dimming the bench. Both are easy to get subtly wrong and invisible to unit tests
— only rendered pixels settle them.
