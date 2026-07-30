# CAP-S08 — tier-3 PTY probe (the 4 blank seats)

**This is the critical path.** `alln capacity` covers 2 of 6 seats. The other
four read `unknown — never sampled` because the probe that would feed them does
not exist.

We already ship tested parsers for three of the four —
`AgyCapacityLog`, `KimiCapacityLog`, `CursorCapacityLog` — and they are
**referenced by nothing but their own tests**. This slice connects them to real
vendor output. It writes almost no parsing logic; it writes the thing that
*gets* the text.

## Founder ruling — the blocking question is closed

> "If probing begins a 5-hour tap nobody cares. It consumes basically no tokens.
> We just have to be able to grab the data. Capacity of what is left is what
> users are sensitive about." — founder, 2026-07-30

The long-open CAP-S00 question ("does opening the usage pane start the window it
reports?") is **resolved by decision, not measurement**. Starting a window costs
wall-clock, not quota — and the window would have started on the user's next real
message anyway. **Do not build a spike for this. Do not gate the probe on it.**

## Ship

A per-driver `CapacityProbe` that, for one source:

1. spawns the vendor CLI in a **PTY** (never Terminal.app, never `osascript`)
2. sends the usage command
3. captures the rendered screen text
4. hands that text to the existing parser for that driver
5. terminates the child, always, including on timeout

| Driver | Command | Parser | Notes |
| --- | --- | --- | --- |
| agy | `/usage` | `AgyCapacityLog` | two pools, remaining-polarity |
| Kimi | `/usage` | `KimiCapacityLog` | also on `/status` |
| Cursor | `/usage` | `CursorCapacityLog` | monthly + on-demand dollars |
| Claude | `/status` → **Usage tab** | none yet | tabbed TUI; needs tab navigation. **Do this one LAST** and if tab navigation proves unreliable, ship the other three and report Claude honestly rather than faking it. |

### Non-negotiables

- **Fail closed.** Spawn failure, timeout, empty capture, or parse failure →
  `unknown` with the right reason (`parserFailed(observedAt:)` for a capture we
  could not read, `neverSampled` if we never got to run). **Never a number,
  never a zero.** A probe that cannot read must not degrade the tier-1 seats.
- **Per-probe timeout**, short (start at 20s). One slow CLI must never hang the
  strip. Render per-row: a probe still running must not block seats already known.
- **No idle background probing.** Probes run only on explicit refresh — add
  `alln capacity --refresh`. A bare `alln capacity` stays tier-1 only and instant.
  Nothing else may trigger acquisition; events record from what is already known.
- **Never claim `vendorExposesNothing`** for a seat we ship a parser for. That
  bug was just fixed in `11936aa6`; there is a test asserting it cannot return.
- Purity stays: `CapacityWindow`, `CapacityBenchProjection` and
  `CapacityStripRenderer` take no IO and no clock reads. The probe lives at the
  acquisition boundary.

## Works Test

- Each parser is fed a **captured real render** (fixture) and produces windows —
  proving the parser/probe seam, not just the parser.
- Spawn failure → `unknown` + reason; tier-1 seats in the same run still report
  their real numbers.
- Timeout → `unknown`, child terminated, no zombie left behind.
- A bare `alln capacity` performs **no** spawn (assert it).
- `alln capacity --refresh` performs a spawn per tier-3 seat.

## Proof

Each fenced line is one complete command. Run it exactly as written; append
nothing to a command line.

```
swift build --package-path Packages/AllnighterCore --product alln --scratch-path /tmp/caps08
```

```
./Packages/AllnighterCore/.build/debug/alln capacity --refresh
```

```
swift test --package-path Packages/AllnighterCore --scratch-path /tmp/caps08
```

Run the test command in the FOREGROUND and wait. Do not background it. Do not
pass `--skip` or `--filter` to the wall.

**The owner-visible proof is the strip itself:** paste the full
`alln capacity --refresh` output. Success is agy, Kimi and Cursor showing real
percentages and reset clocks instead of `never sampled`. If a seat still cannot
be read, say which and why — an honest 5/6 beats a fabricated 6/6.

## Commit

Explicit paths. Trailer `Co-Authored-By: <your seat> via Allnighter`. Leave the
two pre-existing dirty files alone. Never `git reset --hard`. Do not touch
`Apps/AllnighterMac`.
