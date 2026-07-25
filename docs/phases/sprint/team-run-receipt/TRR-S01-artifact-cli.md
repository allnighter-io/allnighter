# TRR-S01 — Terminal HTML artifact + CLI

Status: **ready**
SSOT: `docs/phases/Team_Run_Receipt.md` §§TRR-S01, Must-specify, Card field ledger, Design authority G1–G13

## Goal

Ship `alln artifact show` that regenerates a private HTML team artifact from a
terminal run and opens it (or prints the path).

## Copy-paste prompt

```text
You are implementing TRR-S01 ONLY (Team Run Receipt core).

Read:
- docs/phases/sprint/team-run-receipt/TRR-S01-artifact-cli.md
- docs/phases/Team_Run_Receipt.md (§TRR-S01, Must-specify, Card field ledger, G1–G13)
- Packages/AllnighterCore/Sources/AllnighterCore/FloorProjector.swift
- Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift (runFloorShow + dispatch)
- Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift (floor show prior art)
- docs/design-system/tokens/colors.css (+ base/spacing as needed)
- docs/operations/Execution-Playbook.md §Commits

Implement:
1. ArtifactProjector (AllnighterCore) — pure projection TeamRun (+ optional lead-call parse from answer markdown) → HTML string + field model. Honor field ledger + Must-specify exactly. Honesty string EXACT: `alln-attested multi-seat artifact · not vendor-signed`. Seat-set share helper with FloorProjector; anti-drift unit test. Law-2 single-seat hoist. Reproduce elision 96. Question/one-liner caps 120. G1–G13 in HTML using design-system CSS tokens (inline or linked copy under artifact/; no invented status colors). Content-intrinsic; desktop+mobile friendly. Zero glow/motion on settled card.
2. Write regenerable `artifact/index.html` under RunStore runDirectory for the run.
3. CLI: `alln artifact show <run-id|latest> [--no-open] [--json]` — fail closed RUN_NOT_TERMINAL for non-terminal; print path; default `/usr/bin/open` the HTML on macOS unless --no-open; --json = path + run id + honesty only.
4. ContractRegistry: register `artifact.show`; bump contractVersion 4.0.3 → 4.0.4; run `alln dev export-contracts` (or build alln then export) so generated docs update.
5. HelpTopicRegistry: topic `artifact`; search terms report/card/receipt/team artifact → this command; note continuity receipt is unrelated.
6. Tests: substring honesty fixtures; non-terminal negative; seat helper anti-drift vs Floor; lead-call prefer path.
7. Visual proof: if no layout-watcher HTML gate exists, add a short WAIVERS.manifest entry naming dual-viewport (desktop≥1280, mobile≤430) + G13 as deferred host proof — do not invent a huge visual harness in this slice.
8. Mac/iOS: NO Floor button, NO SwiftUI webview.
9. Commit when Works Test green: explicit paths only.

Out of scope: S01b Floor embed, S01c live paint, S03 export, signing, Buzz, Mac app.

Proof:
swift test --package-path Packages/AllnighterCore --filter Artifact
# plus build alln and smoke:
# .build/debug/alln artifact show latest --no-open   (if a terminal run exists)
bash scripts/check.sh   # if feasible; else Core tests + export-contracts --check

Done when: command works, tests green, contract+help shipped, committed.
```

## Read only (minimum)

- SSOT sections above
- FloorProjector / runFloorShow / ContractRegistry+Milestone1 / tokens

## Touch allowlist

- `Packages/AllnighterCore/Sources/AllnighterCore/ArtifactProjector.swift` (new)
- `Packages/AllnighterCore/Sources/AllnighterCore/FloorProjector.swift` (extract shared seat-set helper only if needed)
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift`
- `Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift`
- `Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift` (and small CLI helper file if cleaner)
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/*Artifact*` (new)
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/ContractRegistryTests.swift` (version pin)
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/FixtureRoundTripTests.swift` (version pin if needed)
- `docs/generated/alln/*` (via export-contracts)
- `docs/design-system/components/product/WorkerChip.*` and/or tokens — compact + dot pill **only if** HTML cannot reuse existing chip CSS without a one-off
- `WAIVERS.manifest` (visual proof deferral only)
- This sprint doc status → `done` on closeout
- `docs/phases/Team_Run_Receipt.md` — mark S01 status Done when shipping (one line)

## Do not touch

- Mac app Floor / live board (S01b/S01c)
- RunService / team grammar
- `export` md path
- Buzz docs

## Works Test

```bash
swift test --package-path Packages/AllnighterCore --filter Artifact
swift test --package-path Packages/AllnighterCore --filter ContractRegistry
```

## Done when

- [ ] `alln artifact show` registered and implemented
- [ ] Projector honesty + terminal gate proven by tests
- [ ] contractVersion 4.0.4 + generated docs
- [ ] help topic `artifact`
- [ ] committed
