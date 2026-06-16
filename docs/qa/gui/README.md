# GUI Proof Packets

Status: Active
Owner: `docs/phases/GUI_Visual_Proof_Gate.md`
Updated: 2026-06-16

A visible GUI fix is not `fixed` until a **layout-watcher** has looked at a real
render of the changed surface and returned no P1 breakage. This folder holds the
renders and verdicts.

## The loop

```text
bash scripts/gui_proof.sh <fixture>     # build + render a deterministic state → PNG
→ spawn .claude/agents/layout-watcher.md on the PNG → PASS/FAIL verdict
```

Fixtures live in `Apps/AllnighterMac/Sources/GUIFixture.swift`. The watcher judges
LAYOUT only (visible, aligned, on-screen, stacked right). Content and data truth
are owned by CLI/Core tests — not this gate.

## Paths

- `_captures/<fixture>.png` — transient, overwritten each run, git-ignored.
- `<surface>/<YYYY-MM-DD>-<slug>/` — durable packet for a recorded closeout:
  - `native.png` — the passing render
  - `watcher.md` — the verdict (PASS, P1=none, P2 notes)
  - `mockup.png` — optional, only if a rendered visual target exists

## Closeout rule

If a GUI agent cannot produce a render + watcher PASS, it says `visually
unverified` or `blocked` — never `fixed`. See `docs/phases/GUI_Visual_Proof_Gate.md`.
