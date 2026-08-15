# layout-watcher verdict — LOCAL RUNTIME section (LR-S05)

Surface: `Apps/AllnighterMac/Sources/LocalRuntimeSectionView.swift`
Reviewed: 2026-08-15 · all nine fixtures named in
`docs/gui/surfaces/local-runtime/brief.md`

## VERDICT: PASS — no P1 across all nine required fixtures

Per-file: `local-runtime-both`, `-opencode-only`, `-claude-only`, `-neither`,
`-advisories`, `-unobserved`, `-pointer-host`, `-pointer-other`,
`-selector-open` — **PASS**, nine of nine.

**P1: none.**

**P2 (advisory, non-blocking):** on the Qwen3 8B row in `-advisories` the
advisory sentence shares a line with the raw tag and wraps, reading tighter
against the toggle column than the single-line rows above it. Not clipped, not
overlapping — looser rhythm only.

## Contracts verified

| Contract | Result |
| --- | --- |
| LOCAL RUNTIME is its own class, never a READY body row | CONFIRMED, all states |
| Runtime dot (blue = Ollama reachable) distinct from green READY dots | CONFIRMED |
| `-neither`: no ready dot, visible install action | CONFIRMED ("Copy install") |
| Ruling 5 — pointer row, never roster chips | CONFIRMED: `-pointer-host` shows one non-selectable `Ollama · 3 models →`; `-pointer-other` shows **nothing** on the non-hosting body |
| Advisory copy plain English | CONFIRMED — no `G1`, `provenance`, `served window`, `tool_calls`, `/api/ps`, "Not a fail", or literal backticks |
| Context sizes render `32K`/`64K`, never raw integers | CONFIRMED in `-advisories` |
| Nothing on by default | Consistent with populated-state; content truth owned by Mac A/D tests, not layout |

## Fixes confirmed landed

1. Possessive corrected — "this model's context size" everywhere; no instance
   of the old form.
2. Derived display names on every row (`GPT-OSS 20B` / `ollama/gpt-oss:20b`),
   no row titled by a raw tag, no dependence on a hand-passed `--name`.
3. Toggle ON is uniformly accent in every state; the earlier white-vs-amber
   split is gone.
4. Repeated advisory collapsed — `-advisories` shows three distinct
   model-specific sentences instead of one repeated three times.

## The state that mattered most

`local-runtime-selector-open` is the native `alPopover`. This project has
already shipped a P1 in that exact class (a Team dropdown that clipped and
detached). Cropped inspection: popover fully on-screen, anchored under the
`via OpenCode ▾` control with a caret, both options legible and unclipped,
correctly layered in front of the row beneath. **No recurrence.**

Independently re-verified by the PM against the same capture.

## Provenance

Reviewer: `.claude/agents/layout-watcher.md` (Sonnet), adversarial pass, two
rounds. The first round covered only four fixtures and **refused to close the
gate** because the brief requires nine — the remaining five, including
`-selector-open` and `-advisories`, were captured and reviewed before this
PASS was issued.
