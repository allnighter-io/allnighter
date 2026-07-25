# TRR-S00 — Growth measure scorecard scaffold

Status: **awaiting founder disposition** (scaffold Done; does not block product)
SSOT: `docs/phases/Team_Run_Receipt.md` §TRR-S00

## Goal

Scaffold the N=20 growth scorecard + 3 hand-render placeholders from recent
terminal multi-seat runs so the founder can dispose growth packaging.

## Copy-paste prompt

```text
Implement TRR-S00 scaffold ONLY (docs + optional hand HTML stubs). No product runtime.

Read Team_Run_Receipt §TRR-S00.

1. List recent terminal multi-seat runs (prefer plan/review outputKind) via alln history / team result — up to 20.
2. Create docs/phases/sprint/team-run-receipt/TRR-S00-scorecard.md with N rows: run id, team, outputKind, rubric class guess (a/b/c/none), stranger-worthy Y/N blank for founder.
3. Create docs/phases/sprint/team-run-receipt/hand-renders/ with 3 minimal HTML stubs using docs/design-system/tokens CSS variables — throwaway, NOT the projector.
4. Add disposition stub: kill growth packaging | proceed with series — FOUNDER FILLS.
5. Do NOT mark phase S00 Done until founder writes disposition — leave Status: awaiting founder disposition.
6. Commit the scaffold.

No ContractRegistry, no Mac, no ArtifactProjector changes.
```

## Done when

- [ ] scorecard + 3 hand stubs committed
- [ ] founder disposition still open (explicit)
