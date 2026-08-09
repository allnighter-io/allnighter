# Handover — capacity, serve, and what to do next (2026-08-08)

For the next PM. Read this, run §1, then pick from §4. Everything below is
committed; nothing is in flight.

---

## 1. Verify state first (2 minutes)

```bash
alln menu --json | head -c 400        # front door, always first
alln version                          # must match `git log -1 --format=%h`
alln capacity --refresh --json | sed -n '/^{/,$p'   # expect 7 sources with numbers
alln serve --health --json            # expect state: available, ONE pid
ps -eo pid,etime,command | grep "[a]lln serve"      # expect exactly one line
```

Healthy looks like: every PTY source reporting a percentage, full bench in
~7s, one serve daemon whose build matches the binary on PATH.
`bailian_token_plan` reading `neverSampled` is expected — it is not a PTY seat.

---

## 2. What changed today (51 commits)

**Capacity was broken and is fixed.** `alln menu` was hiding paid seats. Root
causes, none of them parser bugs:

| Defect | Fix |
| --- | --- |
| A probe verdict never expired | `ProbeFreshnessGate` (`c817eaba`) |
| A limit no vendor stated was asserted as fact | `84a86e0b`, `19dba3b3` |
| codex MCP-boot guard misspelled (`escrtointerrupt`) — dead since written | `5e1e3728` |
| Generic marker `"tip:"` overrode codex's own "not ready" | `28c67373` |
| codex hung forever on built-in `codex_apps` MCP startup | ESC to interrupt (`48ac9acb`) |
| `"settings"`/`"config"` claimed cursor's composer was a usage pane | `1462087f` |
| Every empty parse blamed the parser | `7775615d` |
| History reported its high-water mark as the current reading | `ad44c681` |
| Capacity only refreshed while the Mac app was open | `CapacityRefreshScheduler` (`038e27a3`) |
| Four `alln serve` daemons, oldest 9 days, on stale builds | singleton + takeover (`ddb5f748`) |
| 103 orphaned vendor CLIs → load 12.75 → probes timing out | ledger + sweep (`31be4833`) |

**The orphan leak was the cause of the "flakiness."** Full bench failed 2 of 6
runs; after reaping the orphans, 6 of 6 passed in 6-7s. It was never
nondeterminism — the machine was starved.

**New capability: model-read of a captured pane** (`e2c5cc76`, `f6658005`).
When the deterministic parser returns nothing, the source's own cheapest model
reads the captured text. Measured 10/10 across six vendors' formats with zero
invented numbers; proven live end-to-end.

---

## 3. Decisions already made — do NOT relitigate

| Rejected / ruled | Where | One-line reason |
| --- | --- | --- |
| "Capacity is a table, not a status" — retire `.rateLimited`, promote `CapacityHistoryStore` | `Probe_Freshness.md` §0.4 | REFUTED by two reviews. The meter and a declared vendor refusal are **different facts**; a meter cannot disprove an invocation result. |
| Reading a vendor's stored credential (Keychain/token) for capacity | `Capacity_Native_Channels.md` §4 | Strictly worse than asking the CLI: same data, plus a Keychain prompt attributed to **our** app on a new user's first run. |
| A local model for pane reading | founder, this session | Most users have neither the plan nor the hardware. Use the vendor's own cheapest seat. |
| Bounding probe fan-out concurrency | `Probe_Freshness` task notes | Measured: no reliability gain, +50% wall-clock. The leak was the cause. |
| `--disable plugins` for codex | `48ac9acb` | Measured, changed nothing. `codex_apps` is built in and has no disable flag. |

---

## 4. Next work, in order

1. **`Capacity_Native_Channels.md` per-source slices.** Five of six sources have
   a verified credential-free structured channel (agy print mode, codex
   app-server, kimi web, claude's `~/.claude.json`, grok's JSONL). Each moves
   independently; the PTY scrape stays as that source's fallback. **Cursor is the
   only permanent screen** — verified four ways, it writes no usage state.
2. **PF-S01** — disclose `checkedAt` / `ageMinutes` / `stale` on `menu`,
   `drivers`, `models`. Ready; it is a contract change so regenerate artifacts.
3. **Shadow-mode the model reader** (proposed, unauthorised). Run it alongside
   the parser and log disagreements before making it the only path. Not because
   accuracy is doubted — it is settled — but because a wrong argv is
   indistinguishable from an unavailable vendor (see §6).
4. **`Crew_Understaffed_Signal.md`** — untouched today, ready to code.
5. **`OpenCode_Serve_Attach.md`** — hit **4 times today**, blocked two reviews.
   Practically higher priority than its board position.
6. **Ollama** — founder gate: *do not start*. Dev builds only when it does.

---

## 5. Open questions for the founder

- **Shadow mode, or cut straight over** to model-read as the only path? Founder
  leans "only path"; §4.3 is the safer sequencing.
- **The probe-record half of PF-S03 is still blocked**: `SourceProbeService`'s
  cheap path persists nothing, so "new `lastProbeAt` with no smoke" is a
  contradiction. Needs a `lastDetectedAt` split or permission to spend smoke.
  (The *capacity* half shipped — different store, no such problem.)
- **grok's original root cause was never established.** It works, but the budget
  hypothesis was disproven by control test. No regression test exists, so it can
  silently return. Failing capture preserved at
  `Capacity/debug/grok-parseFailed.txt`.

---

## 6. Landmines

- **`alln run` defaults to MUTATING.** Use `--read-only` for investigations, or
  reviews serialize on the repo write lock and trip the
  `incomplete_uncommitted` gate. The menu now teaches this (`9c950cee`).
- **OpenCode seats collide on port `:4096`.** Serialize OpenCode-backed runs
  (DeepSeek) until `OpenCode_Serve_Attach` lands. Symptom:
  `opencode serve busy: port owned by pid N`.
- **`LoopCoordinatorTests` wedges intermittently** on the full wall (exit 99).
  Known; `scripts/kill-stale-tests.sh` then re-run **once**. Twice in a row at
  the same test is a different signal — diagnose.
- **The wall has a 45-minute cooldown.** Genuine closeout override:
  `ALLNIGHTER_WALL_REASON="..." bash scripts/check.sh`.
- **A wrong argv looks exactly like an unavailable vendor** in the model reader —
  every failure path returns nil by design. Verify vendor argv by *execution*,
  never assumption. Cursor's flag is `--model`, not `-m`; this cost a debugging
  cycle.
- **Closeout is not done until** `scripts/rebuild_cli.sh` **and** a serve restart
  (`alln serve` now supersedes the old daemon automatically). Before the
  singleton, serve-hosted fixes silently never took effect.

---

## 7. Working rules this session earned

- **Control-test every fix.** Two "fixes" today (grok budget, cursor budget) were
  disproven by reverting them and re-measuring. Both would have shipped a
  meaningless constant and a false claim.
- **Never regex text formatted for humans.** Structured fields → read the field.
  Rendered text → let a model read it. Every capacity bug today was a *matching*
  failure, not a reading failure.
- **A green test over a real defect is the expensive kind.** The codex guard had
  a test that passed through a *different* guard. Fixture must force the path it
  claims to cover.
- **Measure before believing your own fear.** The "models will hallucinate
  numbers" objection was asserted three times and was wrong: 10/10, zero
  invented values across four negative captures.
