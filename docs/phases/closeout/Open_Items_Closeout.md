# Open items closeout — capacity CLI, store wiring, ATL promotion

Unattended relay brief. **PM: Sonnet 5. Dev: Grok 4.5.** Read `AGENTS.md` and
`MEMORY.md` (repo root) first; cite honored memory lines.

Three independent slices, in this order. **One commit per slice minimum.**
Baseline that must not regress: **2544 tests, 0 failures**;
`alln dev export-contracts --check` clean; `bash scripts/check_gui_proof.sh` ok.

Run the wall in the **foreground** and wait (~2 min). Do not background it — a
previous seat's turn ended before its background suite reported and three
failures slipped through.

---

## Slice 1 — CAP-S06: wire the `alln capacity` verb

Everything underneath is built, tested and green. This slice only exposes it.

Already shipped (do **not** rebuild):

| Type | Role |
| --- | --- |
| `CapacityWindow` | normalized model, polarity + reset precision + buckets |
| `CodexCapacityLog`, `GrokCapacityLog`, `AgyCapacityLog`, `KimiCapacityLog`, `CursorCapacityLog` | five driver extractors, all emitting `CapacityWindow` |
| `CapacityBenchProjection` | one row per source, effective availability, hero eligibility |
| `CapacityAcquisition` | tier-1 disk reads (codex + grok), tier-3 seats → `vendorExposesNothing` |
| `CapacityStripRenderer` | TTY / plain-ASCII / JSON rendering, fixed display order |

**Ship:** an `alln capacity` command that calls `CapacityAcquisition`, projects
via `CapacityBenchProjection`, and prints through `CapacityStripRenderer`.

- `alln capacity` — the strip
- `alln capacity --json` — the agent contract (register the output schema)

Hard requirements, all already enforced by the types — do not re-implement or
weaken them:

- **Non-TTY output must contain zero ANSI escapes.** This output gets captured
  into other agents' context windows. Add a test asserting no `\u{1B}`.
- **Unknown never blocks.** A missing sample is `unknown` + reason, exit 0.
  Never an error, never a fabricated 0%.
- Every row shows its `observedAt` age.
- `-` for seats with no short-window limit; that is a real fact, not missing data.

The contract is currently **clean at 6.7.0**. This adds a command, so bump minor
(6.7.0 → 6.8.0) and regenerate:

```bash
swift build --package-path Packages/AllnighterCore --product alln
./Packages/AllnighterCore/.build/debug/alln dev export-contracts
```

Never hand-edit `docs/generated/`. Bumping breaks four pinned assertions — the
`team_run.json` fixture, `ContractRegistryTests` (literal **and** the M1 command
boundary set if the verb belongs to M1), and `FixtureRoundTripTests` (literal +
a comment line documenting the bump, as that file does for every prior bump).

**Also update the help surface in this slice** (`HelpTopicRegistry`): teach that
capacity is vendor-printed when acquired, that `unknown` means the vendor exposes
no surface / not sampled recently / parser failed, and that per-run token usage on
receipts is a **different system**. Search terms: capacity, quota, usage, weekly
limit, 5 hour, reset, headroom.

**Proof — paste real output:**

```bash
./Packages/AllnighterCore/.build/debug/alln capacity
./Packages/AllnighterCore/.build/debug/alln capacity --json
./Packages/AllnighterCore/.build/debug/alln capacity | cat    # non-TTY: no escapes
```

Right now on this machine the real answer is roughly: codex and grok read from
disk with live numbers, and claude / cursor / kimi / agy report
`vendorExposesNothing`. If your output disagrees with that, say so — that is a
finding, not a failure.

---

## Slice 2 — CAP-S07: record acquisitions into the history store

`CapacityHistoryStore` (Engine) is built and tested but **nothing calls it**.

**Ship:** after a successful acquisition, record the observed windows via
`CapacityHistoryStore.record(_:now:)`.

**The inviolable rule:** recording must **never trigger acquisition**. No probe,
no spawn, no scan of a vendor directory, no fan-out to other seats on a limit
event. Events record from what is already known; they never go and ask. The app
may be closed and the machine asleep. This is a standing founder ruling — if a
design tempts you toward "just check the other seats when X happens", stop.

Keep the store call out of the pure types: `CapacityWindow`,
`CapacityBenchProjection` and `CapacityStripRenderer` must stay pure with no IO
and no clock reads. Wire at the acquisition/CLI boundary.

Add a test proving that a record call performs no acquisition.

---

## Slice 3 — Agent Team Loop promotion + archive

The packet `docs/phases/Agent_Team_Loop.md` is complete (S01–S04 shipped; only
optional S05 remains). Per `docs/operations/Execution-Playbook.md` § Phase
Archive, promote durable truth **before** moving the file.

1. Add a **Loop** row to `docs/workflows/Product_Vocabulary.md`: Loop is the Mac
   noun for an unattended **Relay**; the CLI stays `pair relay*` and is **not**
   renamed; **Pilot stays CLI-only** and the Mac app is never the PM seat.
   Do not create an alias that renames the CLI.
2. Add / extend the **Agent Team Loop** help topic: Mac Loop = unattended Relay,
   kickoff brief, `pair relay stop` vs `alln kill`. Never teach `pair loop`.
3. Move the packet to `docs/archive/phases/Agent_Team_Loop.md`, remove its row
   from the active table in `docs/phases/README.md`, and add it to
   `docs/archive/phases/README.md` with status, date, proof, and successor owner
   (code SSOT: `RelayCoordinator.stop`, `RelayState.kickoffMessage`,
   `RelayThreadChrome`, `RelayDetachedLauncher`).
4. `rg "phases/Agent_Team_Loop"` and fix any stale live route.

**ATL-S05 is explicitly out of scope** — it is Mac GUI and needs the Visual Proof
Gate, which an unattended relay cannot satisfy. Leave it open.

---

## Rules

- Explicit paths on every commit. The tree has two pre-existing dirty files
  (`docs/phases/Work_Recovery_And_PM_Continuity.md`, `.relay-smoke-spec.md`) —
  leave both alone.
- Never `git reset --hard`, never rewrite history on `feat/design-chain`.
- Do not touch `Apps/AllnighterMac` — GUI changes need the visual gate.
- Do not weaken, skip, or narrow any existing assertion to get green. An honest
  red is worth more than a green that hides drift.
- Isolated `--scratch-path` per workstream.

## Stop conditions

- A slice needs a Mac GUI change → stop, out of scope.
- Recording history would require triggering acquisition → stop and report; that
  is a standing ruling, not a trade-off.
- The wall regresses below 2544/0 and the cause is not obvious → stop and report.
