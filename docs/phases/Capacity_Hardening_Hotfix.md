# Capacity hardening — hot fix

Status: **SHIPPED (code)** · Proof 2026-07-30T20:32Z · Method: `alln capacity` only  
Code SSOT: `CapacityDisplayAcquisition`, `CapacityHydration`, `CapacityHistoryStore`, `CapacityProbe`.  
Doc review: `code_doc_review` · `model_gpt_terra` · run `752A997F-F0E1-4B2E-895E-FA2D6A704C53`.  
Commits: `2143e9d0` HF-00 · `19b227c3` HF-claude.

### Closeout proof (after HF-00 + HF-claude)

**Full `alln capacity --refresh`:** codex 9% · claude **52% last-known** (live still parse-fails → dump under `Capacity/debug/`) · cursor 72% Ultra · grok 6% · kimi 0% · agy 52% effective / 2 pools.

**Bare `alln capacity` immediately after:** all six seats show numbers + honest ages (tier-3 from history when not re-probed). **NeverSampled lie fixed.**

Open residual: Claude live PTY parse still intermittent (dump + distinct reasons landed); strip correctly falls back to last-known instead of blanking.

## Core promise

`alln capacity` must present the best known capacity for every supported CLI: fresh live acquisition when available, otherwise an honestly aged last-known sample. A failed live probe must be visible as a failed probe, not erase usable capacity into `neverSampled`.

**SSOT today:** live acquisition in `CapacityAcquisition`. `CapacityHistoryStore` is currently write-only; that is the lie this hot fix corrects.

## Dogfood evidence

### Bare `alln capacity --json`

| Source | Result |
| --- | --- |
| codex | **OK** — rem=12 plus; on-disk sample age about two hours |
| grok | **OK** — rem=6 X Premium+ |
| claude_code | **FAIL** — `neverSampled` |
| cursor_agent | **FAIL** — `neverSampled` |
| kimi | **FAIL** — `neverSampled` |
| agy | **FAIL** — `neverSampled` |

### Targeted `alln capacity --refresh --source <id> --json`

| Source | Result |
| --- | --- |
| codex | **OK** — rem=12 weekly plus |
| grok | **OK** — rem=6 weekly |
| claude_code | **FAIL** — `parserFailed` |
| cursor_agent | **OK** — rem=72 monthly Ultra |
| kimi | **OK** — rem=0 weekly |
| agy | **OK** — rem=52.07 effective; two pools |

A full `alln capacity --refresh --json` produces the same five successes and Claude `parserFailed`.

Successful probes write history. Claude’s last successful sample remains on disk; failed parsing does not overwrite it. That fail-soft write behavior is correct. The display’s failure to read it is not.

## Truth owners and required contract

| Concern | Truth owner | Required behavior |
| --- | --- | --- |
| Live acquisition and current probe result | `CapacityAcquisition`, `CapacityProbe` | A refresh reports its actual result: success or a concrete failure reason. |
| Persisted last-known sample | `CapacityHistoryStore` | Successful samples remain readable with their original observation time. Failed probes never overwrite them. |
| CLI projection and targeted-refresh sibling handling | `AllnighterCLI.runCapacity` | Bare output and `--refresh --source` retain usable sibling/last-known state rather than inventing `neverSampled`. |
| Mac strip projection | `CapacityStripModel.loadLive` | Uses the same live-or-last-known contract as CLI; it must not become a second source of truth. |
| Vendor-specific capture and parsing | `ClaudeCapacityLog`, `CursorCapacityLog`, `KimiCapacityLog`, `AgyCapacityLog`, on-disk readers | Preserve vendor semantics and return explicit acquisition/parser failures. |

### Result law

- **Live success:** show the fresh sample and its observation age.
- **Live failure with history:** show the last-known sample and its real age; retain/report the current refresh failure separately where the command’s result format supports it.
- **No live sample and no history:** show `neverSampled`.
- **`parserFailed`:** means the current parse failed. It must never mean history was absent.
- **Age:** is the sample observation time, never the render time.
- **Historical JSON is not a live update stream.** It is fallback state only; do not label it live or synthesize current status from it.

## Ordered build sequence

1. **CAP-HF-00 — hydrate and merge projection.** Establish the shared contract first, including fixture coverage for history-only and failed-refresh states.
2. **CAP-HF-claude — make the present failure diagnosable and reliable.** Do not remove Claude because the probe is intermittent.
3. **CAP-HF-codex and CAP-HF-grok — preserve reliable on-disk acquisition and honest freshness.**
4. **CAP-HF-cursor, CAP-HF-kimi, and CAP-HF-agy — verify each PTY parser through the shared fallback path and preserve its vendor-specific semantics.**
5. Run the complete `alln capacity` proof wall after every slice that changes shared projection or a vendor parser.

No per-CLI slice closes by relying on a terminal receipt alone. It must prove both fresh acquisition and the next bare capacity read.

## CAP-HF-00 — shared hydrate and projection

**Owner:** `CapacityAcquisition`, `CapacityHistoryStore`, `AllnighterCLI.runCapacity`, `CapacityStripModel.loadLive`

**Problem:** successful tier-3 probes write usable history, but bare display reads live-only state and prints `neverSampled`. A targeted CLI refresh also leaves unprobed siblings as `neverSampled`, unlike the Mac path.

**Build:**

- Hydrate last-known samples from `CapacityHistoryStore` for bare reads, `loadLive`, and failed probes.
- Return `neverSampled` only when neither live state nor persisted history exists.
- On `parserFailed`, retain the last-known sample if present and preserve the failed current attempt as a failure, not a replacement sample.
- Make CLI `--refresh --source` merge unprobed siblings consistently with the Mac projection.
- Keep observation age from history; do not refresh timestamps during hydration.

**Acceptance criteria:**

- A successful Cursor, Kimi, or Agy refresh is visible from a subsequent bare `alln capacity --json` without another probe.
- A seeded/known history sample appears with its actual age when live state is absent.
- A failed Claude refresh does not turn its prior good sample into `neverSampled`.
- A target-only refresh does not erase or misreport sibling samples.
- CLI and `CapacityStripModel.loadLive` apply the same live-or-last-known result law.

**Kill tests:**

```text
alln capacity --refresh --source cursor_agent --json
alln capacity --json
alln capacity --refresh --source claude_code --json
alln capacity --json
alln capacity --refresh --source kimi --json
alln capacity --json
alln capacity --refresh --source agy --json
alln capacity --json
```

The bare reads must show actual last-known samples and ages after the successful probes. After the Claude failure, bare output must retain its last-known sample if history exists; it must not claim `neverSampled`.

## CAP-HF-codex — Codex / ChatGPT

**Owner:** Codex reader in `CapacityAcquisition` and its on-disk parsing path

| Item | Requirement |
| --- | --- |
| Tier | 1 — `~/.codex/sessions/**/rollout-*.jsonl` |
| Dogfood | Works; rem=12 plus. The newest usable `token_count` can lag while Codex is idle. |
| Required behavior | Prefer the newest rollout record with `rate_limits`; report its true age. Re-read disk before dispatch without inventing freshness. |
| Do not call a bug | A genuinely older on-disk sample is not the blank-seat bug. |
| Acceptance criteria | Bare output matches the newest usable on-disk `rate_limits`; age is never presented as “now” unless that file was just observed. |

**Kill test:**

```text
alln capacity --refresh --source codex --json
alln capacity --json
```

Both outputs must agree on the newest usable limits and honest age.

## CAP-HF-grok — Grok

**Owner:** Grok reader in `CapacityAcquisition`

| Item | Requirement |
| --- | --- |
| Tier | 1 — `~/.grok/logs/unified.jsonl`, reverse scan |
| Dogfood | Works; rem=6 X Premium+. |
| Required behavior | Preserve reverse scan. If billing-line shape drifts, produce `parserFailed`; never silently convert a stale or malformed line into current capacity. |
| Acceptance criteria | Bare output matches the newest valid weekly billing line and retains plan information without fabricated freshness. |

**Kill test:**

```text
alln capacity --refresh --source grok --json
alln capacity --json
```

## CAP-HF-claude — Claude Code

**Owner:** `ClaudeCapacityLog`, `CapacityProbe`, Claude branch of `CapacityAcquisition`

| Item | Requirement |
| --- | --- |
| Tier | 3 — PTY `/usage` |
| Dogfood | Broken now: targeted and full refresh return `parserFailed`. A prior successful weekly sample exists in history. |
| Concrete lie | Spawn failure, timeout, empty capture, and parse failure collapse into `parserFailed`; builders cannot determine whether Claude was not ready, interactive state interfered, capture was empty, or the fixture drifted. |
| Required reliability work | Persist an inspectable debug capture/dump on failure through an appropriate debug path; split failure reasons into spawn, timeout, empty capture, and parse; re-fixture against the current Usage pane; allow a longer readiness wait/timeout where the TUI requires it; retain history fallback. |
| Non-negotiable | Intermittent success is a reliability problem, not authority to cut Claude support. |
| Acceptance criteria | A current successful probe returns remaining capacity, percent, and reset data. A failed probe identifies its actual class and bare output retains a last-known sample with real age when available. |

**Kill tests:**

```text
alln capacity --refresh --source claude_code --json
alln capacity --json
alln capacity --refresh --json
```

A successful run must emit complete parsed capacity. A failed run must identify spawn, timeout, empty, or parse failure—not only a generic parser failure—and the following bare read must preserve history when it exists.

## CAP-HF-cursor — Cursor Agent

**Owner:** `CursorCapacityLog`, Cursor branch of `CapacityAcquisition`

| Item | Requirement |
| --- | --- |
| Tier | 3 — PTY `/usage` |
| Dogfood | Refresh works: rem=72 Ultra monthly. Bare output is `neverSampled`. |
| Required behavior | Close the shared hydration lie. Preserve Ultra plan tier. Verify parsing retains on-demand/API child pools when the vendor presents them. |
| Acceptance criteria | After successful refresh, bare output shows the monthly sample and honest age without re-probing; any presented child pool survives parsing. |

**Kill test:**

```text
alln capacity --refresh --source cursor_agent --json
alln capacity --json
```

## CAP-HF-kimi — Kimi

**Owner:** `KimiCapacityLog`, Kimi branch of `CapacityAcquisition`

| Item | Requirement |
| --- | --- |
| Tier | 3 — PTY `/usage` |
| Dogfood | Refresh works: rem=0 weekly. Bare output is `neverSampled`. |
| Required behavior | Close the shared hydration lie. Preserve honest zero capacity. When both weekly and five-hour windows are available, project both rather than silently selecting only one. |
| Acceptance criteria | Bare output after a successful refresh reports zero as capacity, not `neverSampled`, with actual age and short-window data when present. |

**Kill test:**

```text
alln capacity --refresh --source kimi --json
alln capacity --json
```

## CAP-HF-agy — Antigravity

**Owner:** `AgyCapacityLog`, Agy branch of `CapacityAcquisition`

| Item | Requirement |
| --- | --- |
| Tier | 3 — PTY `/usage`, remaining polarity |
| Dogfood | Refresh works: effective 52.07 across two pools. Bare output is `neverSampled`. |
| Required behavior | Close the shared hydration lie. Preserve dual-pool rows and describe effective availability as the tightest usable ceiling, not an unexplained replacement for individual pools. |
| Acceptance criteria | Bare output after a successful refresh shows both pools, effective capacity, and actual age. |

**Kill test:**

```text
alln capacity --refresh --source agy --json
alln capacity --json
```

## Risk and lie table

| Risk / lie | Truth owner | Required guard |
| --- | --- | --- |
| History is successfully written but invisible to bare display | `CapacityHistoryStore` + projection owners | Hydrate history before emitting `neverSampled`. |
| Current failed probe erases known capacity | `CapacityAcquisition` + `CapacityHistoryStore` | Preserve last successful sample; surface current failure separately. |
| “Parser failed” hides a slow, blocked, empty, or unspawned Claude probe | `CapacityProbe`, `ClaudeCapacityLog` | Distinct reason codes and inspectable failed capture. |
| Targeted refresh makes healthy sibling seats appear unsampled | `AllnighterCLI.runCapacity` | Merge untouched sibling state using the shared projection contract. |
| Historical fallback is mistaken for live capacity | CLI and strip projection | Label/report real age; never reset historical timestamps. |
| Multi-pool vendor data is reduced to a misleading single number | `AgyCapacityLog`, `KimiCapacityLog`, `CursorCapacityLog` | Preserve component pools and document effective/short-window semantics. |
| A parser drift silently produces plausible stale output | Vendor log readers | Fail closed as an explicit parser failure; retain, but do not relabel, last-known history. |

## What not to do

- Do not cut Claude support because its current PTY probe is intermittent.
- Do not treat historical JSON as a live status stream or synthesize fresh timestamps.
- Do not replace live acquisition with history; history is fallback only.
- Do not add a GUI-only repair or a second capacity state model.
- Do not hide a failed probe behind a successful historical value.
- Do not change capacity semantics, invent percentages, or collapse vendor pools merely to make the strip simpler.
- Do not use proof methods other than `alln capacity` for this hot fix.

## Proof wall

Run after the ordered build sequence completes:

```text
alln capacity --refresh --source codex --json
alln capacity --refresh --source grok --json
alln capacity --refresh --source claude_code --json
alln capacity --refresh --source cursor_agent --json
alln capacity --refresh --source kimi --json
alln capacity --refresh --source agy --json
alln capacity --refresh --json
alln capacity --json
```

Close only when:

- Codex and Grok retain their current successful acquisition behavior and honest ages.
- Cursor, Kimi, and Agy successful refreshes remain visible on the following bare read.
- Claude either succeeds with complete parsed capacity or fails with a concrete reason and preserved last-known fallback.
- `neverSampled` means no live sample and no persisted sample, across CLI and strip projection.
- No output represents historical fallback as live capacity.

## Related

- `docs/archive/phases/CLI_Capacity_TUI_Sampling.md` — last-known and age law
- `docs/phases/closeout/CAP-S08_tier3_probe.md` — probe ship record
- Code: `CapacityAcquisition`, `CapacityProbe`, `CapacityHistoryStore`, `ClaudeCapacityLog`, `CursorCapacityLog`, `KimiCapacityLog`, `AgyCapacityLog`, `AllnighterCLI.runCapacity`, `CapacityStripModel.loadLive`
