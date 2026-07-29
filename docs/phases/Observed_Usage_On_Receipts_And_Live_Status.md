# Observed Usage on Receipts and Live Status

Status: **OPEN — founder intake packet. Presentation work is gated on AgentOS
capture truth; do not invent token numbers in Alln.**
Owner: AllnighterCore (TeamRunJSON / ArtifactProjector) + AllnighterEngine
(pilot / relay status); AgentOS owns capture
Created: 2026-07-29
Origin: Founder brainstorm — Claude-style `duration · tokens` is high value for
the **execution lane**; multi-CLI reality means tokens only when the driver
reports them; missing tokens must **blame the CLI**, never a blank dash.
**Upstream (required for tokens):** AgentOS
[`docs/phases/Observed_Token_Usage_Capture.md`](../../../AgentOS/docs/phases/Observed_Token_Usage_Capture.md)
(sibling repo path from this machine’s layout:
`/Users/mike/Documents/GitHub/AgentOS/docs/phases/Observed_Token_Usage_Capture.md`).
Related prior art (partial, not SSOT): `docs/phases/threads/04_Observed_Usage.md`
(2026-06 open slices); FR14 / `ReportedTokenUsage` already on outcome + headline
suffix when present.

Phases are ephemeral. At closeout: promote product law into standing ops /
vocabulary / help as needed; code remains SSOT for fields; archive this packet.

---

## Founder intake (SSOT_Founder_Input_Workflow)

```text
Founder intent:
  Once AgentOS delivers reliable per-driver capture, surface observed duration
  always and observed tokens when available on (1) every run receipt / artifact
  and (2) live pilot / relay status — without usage theater. When a CLI is
  silent, state that explicitly and put the blame on the CLI, not Alln.

Product value:
  Execution-lane steering (route vs inline, noisy seats, expensive rounds).
  Receipt as lab notebook: wall time + tokens when real. Live status: alive
  first, cost signal second when the dialect streams or has reported so far.

Trusted workflow slice:
  AgentOS capture green for a driver → map per-seat usage on TeamRunJSON →
  project on artifact chips + outcome rollup → pilot/relay status line carries
  liveness + optional observed usage → help teaches the honesty rule.

Current state:
  Duration: strong — seat durationMs / queueMs / ttftMs, outcome.timing.wallMs,
  floor live elapsed, artifact seat chips show duration.
  Tokens: partial — AgentOS extractors for claude_code / codex / cursor_agent;
  outcome.usage + headline "· 12.4k tok" from first worker only; Grok often nil;
  artifact HTML does not project tokens; no per-seat answer.usage; no pilot
  status tok line. Product law already bans estimates ("no usage theater").

Truth owner:
  Capture: AgentOS ReportedTokenUsage on WorkerRunResult.
  Contract projection: TeamRunJSONMapper / TeamRunJSON.
  Receipt chrome: ArtifactProjector (+ ArtifactCLI).
  Live status: PilotCLI / relay status surfaces + StreamLiveness (alive ≠ tokens).
  Duration clocks: runner timing + Alln status — independent of usage events.

CLI surface (target — refine at implementation):
  - alln artifact show|export — seat chips: duration always; tokens or
    "tokens not reported by <sourceId>"; optional footer wall + partial rollup.
  - alln run / team JSON (TeamRunJSON): answers[]. duration*; answers[].usage?
    or equivalent; outcome.usage rollup only from reported seats; never zero-fill.
  - pair pilot status / relay status (and related ps/status): keep stream-primary
    liveness; append observed usage when non-nil on the active seat.
  Exit codes unchanged for missing usage (not an error).

Help surface (topics / search / recovery):
  - Teach: duration is Alln-measured; tokens only when the CLI reports;
    "not reported by <cli>" means the dialect was silent.
  - Search terms: tokens, usage, tok, cost, duration, receipt, pilot status.
  - No dollar/quota claims. Update HelpTopicRegistry in the same slice as any
    new JSON fields or status lines (ASF closeout questions).
  - Recovery: help search miss → doctor / hello --for / models — not a fake
    usage command.

Proof scenario:
  Multi-seat or single execution run: Claude (or fixture) seat shows duration +
  tok; Grok (or silent fixture) shows duration + "tokens not reported by grok";
  artifact export matches JSON; pilot status while running shows alive + elapsed
  and tok only if already reported (terminal-only dialects get tok at settle).

Blocking questions:
  None on product posture (founder approved). Implementation may need contract
  bump when adding per-seat usage fields.

Next slice (after AgentOS OTU-S00 at least documents the matrix):
  OUR-S01 — per-seat usage on TeamRunJSON + mapper (nil + never zero).
```

---

## Product law (presentation)

**Always**

- Show **observed duration** when Alln measured it (seat and/or wall).
- **Liveness** (alive / stream silence / process) must **not** depend on token
  events — StreamLiveness / process ownership stay primary.

**When tokens exist**

- Show compact observed counts (e.g. `41.2k tok` or in/out if useful).
- Source is the driver-reported ints on the result — never estimate.

**When tokens are missing**

- Do **not** use `—`, blank, or `0`.
- Explicit blame on the CLI/source, e.g.:

```text
Opus    18.4s  ·  41.2k tok
Codex   44.1s  ·  12.1k tok
Grok    31.0s  ·  tokens not reported by grok
```

Shorter chip form is fine: `31.0s · not reported by CLI` with sourceId in
tooltip/JSON.

**Banned (unchanged)**

- Estimated tokens, dollar cost, quota %, preflight tokenizer guesses.
- Faking mid-run token burn when the dialect only reports at exit.

Priority chrome: **execution lane** (mutating runs, pilot/relay workers) first;
judgment seats can share the same fields when cheap.

---

## Dependency on AgentOS

| AgentOS slice | Unblocks Alln |
| --- | --- |
| OTU-S00 matrix | Honest “never” vs “unknown” copy; seat source labels |
| OTU-S01 extractors | Real tokens on more seats without Alln parsers |
| OTU-S02 mid-stream | Live pilot/relay tok updates mid-turn |
| OTU-S03 warm parity | Tokens on warm/serve paths match cold |

Alln may ship **duration + explicit “not reported by …”** for nil usage **before**
every driver is covered. Alln must **not** add local dialect parsers that fork
AgentOS — extend AgentOS instead.

Link (repo-relative from monorepo checkout of both trees):

```text
AgentOS: docs/phases/Observed_Token_Usage_Capture.md
```

---

## Once capture is delivered — how it lands on every run

### 1. Contract (`TeamRunJSON`)

- **Per answer/seat:** keep `durationMs` (and queue/ttft); add optional
  `usage: { inputTokens?, outputTokens? }` (or map existing result field) —
  **absent when unreported**.
- **Outcome:** rollup usage only from seats that reported; document partial
  rollup (do not sum missing seats as zero). Prefer fixing today’s “first worker
  only” mapping.
- **Top-level `usage.cliCalls`:** leave as call count; do not overload with tokens.

### 2. Receipt / artifact (all terminal runs)

- Seat chip: `status · duration · tokens | not reported by <sourceId>`.
- Optional footer: wall clock + “N of M seats reported tokens”.
- Same honesty string rules as today (attested multi-seat, not vendor-signed).
- `alln artifact show|export` and Factory Floor reader share projection truth
  (`ArtifactProjector`).

### 3. Live runs (pilot / relay / floor)

Ideal status line:

```text
alive  ·  stream 12s ago  ·  2m 40s  ·  89.1k tok (claude)
alive  ·  stream 12s ago  ·  2m 40s  ·  tokens not reported by grok
dead   ·  no stream 4m    ·  4m 10s  ·  …
```

| Signal | Meaning | Source |
| --- | --- | --- |
| Alive / stream silence | Still working? | StreamLiveness + process ownership |
| Elapsed / duration | How long? | Alln / runner clocks |
| Tokens | How chatty/expensive so far? | AgentOS reported usage if any |

**Do not** treat rising tokens as the sole heartbeat. Terminal-only dialects:
tok appears at settle (or never + blame line).

### 4. Help + vocabulary

- Same slice as contract/status changes: HelpTopicRegistry + search aliases
  (`tokens`, `usage`, `not reported`).
- Closeout answers for teaching surface (founder workflow).

---

## Ordered slices (Alln — after / alongside AgentOS)

### OUR-S00 — Packet + gates (this doc)

- Founder posture locked; AgentOS link; non-goals; no code.
- **Works test:** docs committed; phases board lists both packets.

### OUR-S01 — Per-seat usage on TeamRunJSON + mapper

- Map `WorkerRunResult.reportedTokenUsage` onto each answer; fix first-worker-only
  outcome rollup to reported seats only.
- Contract regenerate if schema changes; tests for present + absent.
- **Works test:** fixture multi-seat run → JSON has tok on reporting seat, field
  absent on silent seat; outcome.usage partial rules unit-tested.

### OUR-S02 — Artifact / receipt projection

- Seat chips + optional footer; no dash for missing tokens.
- **Works test:** export HTML contains duration and either tok or “not reported
  by …” for silent seat; no invented numbers.

### OUR-S03 — Live pilot / relay status

- Append observed usage when non-nil; always keep stream-primary liveness.
- Mid-stream tok only if AgentOS OTU-S02 delivered for that driver.
- **Works test:** status JSON/text fixtures; silent driver shows blame string;
  hung stream without usage still shows silence age.

### OUR-S04 — Help + teaching closeout

- Topics, search, recovery; no cost theater.
- **Works test:** help search hits; ASF-style closeout questions answered in PR.

---

## Non-goals

- Dollar pricing, quota remaining UI.
- Making liveness depend on usage events.
- Parallel token parsers inside Allnighter.
- Waiting for universal CLI support before shipping honest partial matrix.

---

## Risk

| Risk | Notes |
| --- | --- |
| Partial matrix UX | Users may think Alln “missed” Grok — explicit CLI blame is the mitigation. |
| Contract bump | Per-seat usage is additive; keep null = unreported. |
| Live vs terminal | Document mid-stream vs settle so pilot is not accused of lying. |

---

## Proof commands (implementation slices)

```text
swift test
scripts/check.sh
# artifact / pilot fixtures as added per slice
```

---

## Relationship to older packets

| Doc | Role |
| --- | --- |
| `threads/04_Observed_Usage.md` | Earlier open slices; product law aligned; this packet is the **receipt + live status** execution path after AgentOS capture. Do not treat 04 as conflicting SSOT. |
| Archived Team Run Receipt | Duration on chips already shipped; tokens are the gap. |
| Pilot status liveness hotfixes | Stream-primary alive stays law; usage is additive. |
