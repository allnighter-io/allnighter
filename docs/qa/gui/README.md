# GUI Proof Packets

Status: Active
Owner: `docs/gui/Visual_Proof_Gate.md`
Updated: 2026-06-16

A visible GUI fix is not `fixed` until a **layout-watcher** has looked at a real
render of the changed surface and returned no P1 breakage. This folder holds the
renders and verdicts.

## The loop

```text
bash scripts/gui_proof.sh <fixture>            # build + render a deterministic state → PNG
→ spawn .claude/agents/layout-watcher.md on the PNG → PASS/FAIL verdict
bash scripts/gui_proof_seal.sh <surface> <slug> <fixture>...   # after PASS: seal the packet
```

Fixtures live in `Apps/AllnighterMac/Sources/GUIFixture.swift`. The watcher judges
LAYOUT only (visible, aligned, on-screen, stacked right). Content and data truth
are owned by CLI/Core tests — not this gate.

## Paths

- `_captures/<fixture>.png` — transient, overwritten each run, git-ignored.
- `<surface>/<YYYY-MM-DD>-<slug>/` — durable packet, sealed by `gui_proof_seal.sh`:
  - `native.png` (or `native-<fixture>.png`) — the passing render(s)
  - `proof.manifest` — binds each proven view to its git blob hash + `watcher: PASS`
  - `watcher.md` — the verdict (PASS, P1=none, P2 notes)
  - `mockup.png` — optional, only if a rendered visual target exists
- `WAIVERS.manifest` — content-bound waivers for non-visible view changes
  (`gui_proof_waive.sh`).

## Why content-bound

`scripts/check_gui_proof.sh` requires every *currently changed* view's *current*
git blob hash to appear in some `proof.manifest`/`WAIVERS.manifest`. So old proof
goes stale the moment a view is re-edited, and an unrelated packet can't satisfy a
different surface. Render and seal the surface you actually touched — not every
screen.

## Closeout rule

If a GUI agent cannot produce a render + watcher PASS, it says `visually
unverified` or `blocked` — never `fixed`. See `docs/gui/Visual_Proof_Gate.md`.
