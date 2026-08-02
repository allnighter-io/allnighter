# Capacity Phase 1 recovery (CLI trust path)

Status: **SHIPPED (code)** · 2026-08-02  
Scope: CLI/Core/Engine capacity only — **Mac app out of scope**.  
Code SSOT: `CapacityAcquisition`, `CapacityProbe`, `CapacityDisplayAcquisition`,
`CapacityHydration`, `AllnighterCLI.runCapacity`.

## Founder law

Capacity is trust-critical. One canonical adapter per source. Bare is instant
no-spawn. Live refresh is explicit. Failed refresh never paints history as live.

## One-path adapters

| Source | Sole mechanism |
| --- | --- |
| `codex` | Disk — `~/.codex/sessions/**/rollout-*.jsonl` |
| `grok` | Disk — `~/.grok/logs/unified.jsonl` reverse-scan |
| `claude_code` | PTY `/usage` (one adapter; hard deadline) |
| `cursor_agent` | PTY `/usage` |
| `kimi` | PTY `/usage` |
| `agy` | PTY `/usage` |

No disk+PTY dual path. No silent fallback that can disagree with the adapter.

## CLI

```text
alln capacity                 # instant six-row snapshot (no spawn)
alln capacity --json          # same, agent contract
alln capacity --refresh       # live; progress on stderr; full table on stdout
alln capacity --refresh --source <id>
```

`--source` without `--refresh` is a usage error.

## Claude trust fix

ProbeScratch launches hit Claude's workspace-trust dialog. Real captures strip
spaces (`Yes,Itrustthisfolder`). Matcher now collapses whitespace and inspects
the **recent paint window** so stale trust text in the buffer head cannot mask
the welcome/`/usage` surface. Failed attempts return explicit unknown reasons
(`emptyCapture` / `parserFailed` / …) — never stale-as-live.

## Dogfood (founder Mac, 2026-08-02)

| Command | Result |
| --- | --- |
| bare human / JSON | **0.03s**, 6 rows, honest ages |
| `--refresh --source codex` | **0.03s** disk re-read, rem=80 plus |
| `--refresh --source grok` | **0.03s** disk re-read, rem=26 |
| `--refresh --source claude_code` | **~5s** live after trust fix, rem=4 Max, age=0 |
| `--refresh --source cursor_agent` | **~4s** rem=69 Ultra, age=0 |
| `--refresh --source kimi` | **~4s** rem=64, age=0 |
| `--refresh --source agy` | **~5s** rem=82.64, age=0 |
| full `--refresh` | **~5s** concurrent PTY; 6 rows |

No probe descendants left after each command (only pre-existing interactive CLIs).

## Unsupported / residual

None of the six seats are intentionally unsupported. Intermittent Claude trust
timing can still fail closed as `emptyCapture` — that is honest unknown, not a
history paint. Re-run `--refresh --source claude_code` to retry.
