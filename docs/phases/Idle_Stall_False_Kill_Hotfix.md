# Idle Stall False Kill — Hotfix

Status: **AUTHORIZED hot fix** — bleed stop first; truth + posture follow
Owner: AllnighterEngine + driver manifests + CLI teaching
Updated: 2026-07-25
Incident date: 2026-07-25

## Origin

Founder incident (design run on Opus 5 / Claude Code):

```text
The design run timed out — Opus 5 read the brief and the existing mockups,
started building, then hit the driver's default idle-stall budget. Writing a
large HTML file in one shot produces no streaming progress, so the runner
reads it as a stall. Nothing was written — full paid turn wasted.

300s is also NOT good enough for K3 reviews. They can take longer. What is
the point of killing something in flight if we know it is otherwise healthy?
This will make users furious.
```

Same disease as archived PO-F5 (`docs/archive/phases/Process_Ownership.md`):
warm workers that do legitimate silent work (tool reads, long Write, long
review) emit **zero stdout/stderr bytes** for longer than the idle budget and
get killed as `timed_out` / idle while identity-alive.

Operator workarounds (`--idle-timeout`, "write incrementally") are bandaids.
They must not become product law. Fix `alln`.

## Product lie

Idle progress-truth today effectively means **stream bytes** (plus external
`recordProgress` heartbeat touches). Help text claims resets on
"tool-call/reasoning/stderr/child activity" — stream bytes cover tool JSON
when the vendor emits them; **silent internal work and one-shot large Writes
do not**. Killing an identity-alive healthy worker mid-flight wastes tokens
the user already paid for and destroys trust.

## Current defaults (verify in code before editing)

| Source | Idle | Notes |
| --- | --- | --- |
| `kimi`, `grok` manifests | **1800s** | Already honest for long seats |
| `claude_code` App Drivers | **600s** | Still too short for Opus design |
| `DefaultConfig` embedded `claude_code` | **300s** | Drift vs App Drivers — fix both |
| `codex`, `cursor_agent`, `antigravity` | **300s** | Too short |
| Wall (`RunClockDefaults.wallTimeoutSeconds`) | **3600s** | Hard ceiling — keep unless design/review prove otherwise |
| Help / `ContractRegistry` idle flag summary | "typically 300" | Stale — rewrite |

Code SSOT pointers:

- Idle budget: driver `invoke.timeoutSeconds` → `RunRequest.workerTimeoutSeconds` / `ProcessGroupCommandRunner` stall watchdog
- Progress: `ProcessGroupCommandRunner` + `ProcessOwnership.classifyProgressStall` / `recordProgress`
- Wall / clocks: `RunClockDefaults`, `RunClockEnforcer`
- Override flag: `alln run --idle-timeout` / `--wall-timeout` (PO-F5 / RLR-L8) — remains override, not primary UX
- Teaching: `ContractRegistry+Milestone1.swift` FlagSpec for `idle-timeout`; regenerate `docs/generated/alln/*`

## Non-goals

- Do not ban Opus (or any seat) from design because of false stalls.
- Do not require agents to "write incrementally so the watchdog is happy."
- Do not make `--idle-timeout` the primary UX for design/review.
- Do not disable idle detection entirely (true hangs must still die).
- Do not mix broad RLR refactors into the bleed-stop slice.

## Ship order

### IDLE-HF-S01 — Bleed stop: raise idle floors + sync + teach

**Authorized now. Ship first.**

1. Raise short-driver idle defaults to **1800s** (match kimi/grok):
   - `claude_code`, `codex`, `cursor_agent`, `antigravity`
2. Sync **both** truth owners so they cannot disagree:
   - `Apps/AllnighterMac/Resources/Drivers/*.json`
   - `Packages/AllnighterCore/Sources/AllnighterEngine/DefaultConfig.swift` embedded manifests
3. Keep wall at **3600s** unless a later slice proves design/review need more.
4. Fix teaching in the same slice:
   - Drop "typically 300"
   - Say idle = per-driver manifest (now commonly 1800s for agent CLIs); wall = hard ceiling
   - Regenerate contracts (`alln dev export-contracts`) so help + generated docs match
5. Tests: existing idle / clock suites still pass; add/adjust any fixture that hard-codes 300 as the product default for these drivers.

**Works Test:** dispatch a long silent-capable seat (or a fixture that holds identity-alive with no stream bytes) under the new default without requiring `--idle-timeout`; genuine total silence past 1800s still times out; wall still caps the run.

**Done when:** no healthy Opus design / K3 review needs a hero flag just to survive five minutes of quiet tool work under default dispatch.

### IDLE-HF-S02 — Truth fix: count real work as progress

**Next slice after S01.**

Idle must reset on signals silent healthy runs actually produce:

1. **Repo / cwd filesystem activity** under the run working directory (mtime / new writes) — the large-HTML Write case
2. **Real process-tree / child activity** (CPU, IO, or new children) — make the help text true
3. Keep stream bytes as the fast path for chatty workers

Guard: do not invent fake progress prose for the GUI. This is watchdog truth only.

**Works Test:** worker writes a large file under cwd with no stdout for > old budget → not reaped; frozen process with no fs/child/stream activity → still reaped near budget.

### IDLE-HF-S03 — Posture / team floors

**After S02 (or parallel if S01 alone is insufficient in field).**

Bake floors into posture/team so chat ≠ design/review/execute:

| Posture / job | Idle floor | Wall floor |
| --- | --- | --- |
| Chat / quick | driver default OK | 3600s |
| Design / review / mutating execute | ≥ 1800s | ≥ 3600s |

Same lesson CR packets already learned (`stallTimeoutSeconds: 3600`). Flags remain overrides.

### IDLE-HF-S04 — Kill policy (optional follow-on)

Prefer surfacing "identity-alive, no stream for Ns" in `alln ps` / GUI before idle kill when fs/child progress is also quiet. Wall remains the true hard stop. Idle kill stays last resort for black-box silence after S02 signals are exhausted.

## Explicitly rejected

| Idea | Why reject |
| --- | --- |
| Standing rule: never retry Opus design; fall back to Cursor Grok only | Operator trauma policy, not a product fix. Removes after S01+S02 land. |
| Prompt law: always write files incrementally | Papers over a false stall; hurts craft quality. |
| Only document `--idle-timeout` louder | Users will still forget; agents will still burn turns. |

## Related

- Archived diagnosis: `docs/archive/phases/Process_Ownership.md` (PO-F5)
- Clocks: archived `docs/archive/phases/Run_Lifecycle_Reliability.md` + code `RunClockEnforcer.swift`
- Prior slow-review threshold work: `docs/phases/sprint/watchdog/WATCHDOG-S01-slow-glm-threshold.md` (pair/advisory detector — different layer; do not conflate)

## Closeout

When S01 ships, update this status line and the phases board. When S02–S03 ship, archive this doc and leave code + driver manifests as SSOT.
