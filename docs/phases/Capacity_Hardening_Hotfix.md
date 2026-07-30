# Capacity hardening — hot fix

Status: **OPEN** · Live dogfood 2026-07-30T20:15Z · Method: `alln capacity` only  
Not SSOT. Code is SSOT when closed.

## Answer (one screen)

| Question | Answer |
| --- | --- |
| Can alln **get** the numbers? | **Yes for 5/6.** Codex+Grok from disk. Cursor+Kimi+Agy from PTY `--refresh`. **Claude probe broken now** (`parserFailed`). |
| Why bare `alln capacity` is blank? | **Display never reads history.** Bare invents `neverSampled` for all tier-3 even when `Capacity/*.json` has samples. |
| GUI vs agents? | **Same path.** GUI is not a second liar. Spikes that said “parser works” were right for 5/6. The **strip** lies on bare glance. |
| SSOT today | Live `CapacityAcquisition` only. History is **write-only**. |

## Live matrix (this machine, `alln` only)

### Bare `alln capacity --json`

| source | result |
| --- | --- |
| codex | **OK** rem=12 plus (age ~2h from disk) |
| grok | **OK** rem=6 X Premium+ |
| claude_code | **FAIL neverSampled** |
| cursor_agent | **FAIL neverSampled** |
| kimi | **FAIL neverSampled** |
| agy | **FAIL neverSampled** |

### Per-seat `alln capacity --refresh --source <id> --json` (target seat only)

| source | targeted result |
| --- | --- |
| codex | **OK** rem=12 weekly plus |
| grok | **OK** rem=6 weekly |
| claude_code | **FAIL parserFailed** |
| cursor_agent | **OK** rem=72 monthly Ultra |
| kimi | **OK** rem=0 weekly |
| agy | **OK** rem=52.07 effective (dash 89.98 weekly, 2 pools) |

### Full `alln capacity --refresh --json`

Same as per-seat: 5 OK, **claude_code parserFailed**.  
Side effect of `--source` only: unprobed tier-3 print as `neverSampled` (CLI has no sibling merge; Mac does).

### History after runs (`~/Library/Application Support/Allnighter/Capacity/`)

Write works for successful probes. Claude file still **stale** (last good ~16:56Z, not updated on parserFailed — correct fail-soft on write).

---

## Shared fix (all seats) — CAP-HF-00

**Hydrate last-known from `CapacityHistoryStore` on bare / `loadLive` / failed probe.**

- `neverSampled` only if no live **and** no history.
- `parserFailed` → keep last-known if any.
- CLI `--refresh --source` merge siblings (match Mac).
- Kill test: seed history → bare must show numbers + real age.

Without this, every tier-3 “works on refresh, blank forever after” loop continues.

---

## Per-CLI slices

### CAP-HF-codex — Codex / ChatGPT

| | |
| --- | --- |
| Tier | 1 on-disk (`~/.codex/sessions/**/rollout-*.jsonl`) |
| Live | **Works.** rem=12 plus. |
| Break | Sample age ~2h — newest usable `token_count` may lag if Codex idle. Bare is correct; not the blank-seat bug. |
| Improve | Prefer newest rollout with `rate_limits`; optional short-window if `secondary` ever appears. Surface age honestly (already does). Pre-dispatch re-read disk (free). |
| Done when | Bare always matches freshest on-disk rate_limits; age never “now” unless just read. |

### CAP-HF-grok — Grok

| | |
| --- | --- |
| Tier | 1 on-disk (`~/.grok/logs/unified.jsonl` reverse scan) |
| Live | **Works.** rem=6 X Premium+. Fresh (~minutes). |
| Break | None for acquire. Rem is low — product useful, not a parser bug. |
| Improve | Keep reverse-scan; if billing line shape drifts, fail closed with `parserFailed` not silent stale. Optional planTier stability. |
| Done when | Bare rem matches latest billing weekly line. |

### CAP-HF-claude — Claude Code

| | |
| --- | --- |
| Tier | 3 PTY `/usage` → `ClaudeCapacityLog` |
| Live | **Broken now:** `parserFailed` on targeted + full refresh. History still has older good sample (~52% weekly). |
| Break | Spawn/timeout/empty/parse collapsed to one reason — cannot tell which. Interactive Claude sessions already running may block/confuse one-shot TUI. |
| Improve | 1) Dump last capture on fail (debug path). 2) Split unknown reasons: spawn / timeout / empty / parse. 3) Re-fixture against current Claude Usage pane. 4) Always fall back to history. 5) Longer timeout or readiness wait if TUI slow. |
| Done when | `--refresh --source claude_code` returns rem+% + reset; bare shows last-known when probe fails. |

### CAP-HF-cursor — Cursor Agent

| | |
| --- | --- |
| Tier | 3 PTY `/usage` → `CursorCapacityLog` |
| Live | **Works on refresh.** rem=72 Ultra monthly. |
| Break | Bare = neverSampled (shared hydrate). Only monthly “Included” pool — on-demand dollars may be missing if vendor shows them. |
| Improve | Hydrate (HF-00). Confirm on-demand/API child pools still parse if present. Plan tier “Ultra” keep. |
| Done when | Bare shows ~72% + age after any successful refresh without re-probe. |

### CAP-HF-kimi — Kimi

| | |
| --- | --- |
| Tier | 3 PTY `/usage` → `KimiCapacityLog` |
| Live | **Works on refresh.** rem=0 weekly (honest empty). |
| Break | Bare neverSampled. 5h window in history may not surface on strip if projection picks weekly only. |
| Improve | Hydrate. Ensure 5h short window column paints when present (red weekly + short). planTier if vendor exposes. |
| Done when | Bare shows 0% weekly + short window if open; not “never sampled”. |

### CAP-HF-agy — Antigravity

| | |
| --- | --- |
| Tier | 3 PTY `/usage` → `AgyCapacityLog` (remaining polarity) |
| Live | **Works on refresh.** effective 52.07, 2 pools (Gemini / Claude+GPT). |
| Break | Bare neverSampled. Multi-pool effective availability is correct product; easy to misread as “wrong %”. |
| Improve | Hydrate. Keep dual-pool rows. Label pools in plain CLI clearly. |
| Done when | Bare shows both pools + effective tightest ceiling + age. |

---

## Proof wall (closeout)

```text
alln capacity --refresh --source codex --json
alln capacity --refresh --source grok --json
alln capacity --refresh --source claude_code --json
alln capacity --refresh --source cursor_agent --json
alln capacity --refresh --source kimi --json
alln capacity --refresh --source agy --json
alln capacity --json   # after HF-00: last-known for tier-3, not neverSampled
```

## Related

- `docs/archive/phases/CLI_Capacity_TUI_Sampling.md` — last-known + age law  
- `docs/phases/closeout/CAP-S08_tier3_probe.md` — probe ship  
- Code: `CapacityAcquisition`, `CapacityProbe`, `CapacityHistoryStore`, `*CapacityLog`, `AllnighterCLI.runCapacity`, `CapacityStripModel.loadLive`
