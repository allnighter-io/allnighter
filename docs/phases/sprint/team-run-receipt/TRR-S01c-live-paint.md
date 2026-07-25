# TRR-S01c — Mac live artifact preview

Status: **ready** (requires TRR-S01 done)
SSOT: `docs/phases/Team_Run_Receipt.md` §TRR-S01c + `docs/phases/Live_Team_Board.md` (events)

## Goal

While a team run is running in the Mac app, show a live preview of seat status /
one-liners from existing board events; on terminalization, replace with settled
ArtifactProjector HTML open path (zero glow). CLI stays terminal-only.

## Copy-paste prompt

```text
Implement TRR-S01c ONLY.

Read:
- docs/phases/sprint/team-run-receipt/TRR-S01c-live-paint.md
- docs/phases/Team_Run_Receipt.md §TRR-S01c
- docs/phases/Live_Team_Board.md (workerStatusChanged, workerAnswerDelta)
- Existing live board / Factory Floor live surfaces in Apps/AllnighterMac

Rules:
- Feed ONLY existing RunEvents — do not invent RunEvent kinds or change RunService
- Live preview MAY use board motion/glow; settled artifact remains G5 zero glow via ArtifactProjector
- Do NOT weaken `alln artifact show` non-terminal fail-closed
- No `artifact watch` CLI
- Prefer Floor-adjacent or compact live panel — minimal GUI, docs/gui/GUI_Workflow.md
- On run terminal → regenerate settled artifact (same as S01/S01b path)

Proof: unit/integration where possible for event→preview mapping; document Mac gesture Works Test if UI proof is host-bound.
Commit; mark S01c Done.
```

## Done when

- [ ] live preview uses board events only
- [ ] CLI terminal gate unchanged
- [ ] committed
