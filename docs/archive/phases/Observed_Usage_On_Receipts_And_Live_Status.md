# Observed Usage on Receipts and Live Status

Status: **Complete (2026-07-30)** — OUR-S01/S02/S03 shipped. **Primary deliverable: live pilot / relay
status** (duration + optional observed tokens while the turn is in flight).
Tokens come from AgentOS capture; Alln never invents numbers. Liveness stays
stream/process-primary — usage is additive, never a heartbeat.  
Archived: **2026-07-30**

Owner: **AllnighterCore** (contract + presentation + terminal projection) +
**AllnighterCLI** (`PilotCLI` / `RelayCLI` live status surfaces). **AgentOS**
owns capture on `WorkerRunResult.reportedTokenUsage`.

Version: **v5 (2026-07-30)** — doc review pass 3 (Grok, fixed doc_reviewer
skill). Tech-gap pass: same product law; live status remains primary.

Upstream: AgentOS `docs/phases/Observed_Token_Usage_Capture.md` (OTU).

Already shipped partial: seat **duration** chips; optional `outcome.usage` +
headline tok suffix when present — both **first-answer only** (bug). Live
`pilot status` / `relay-status` have stream liveness fields but **no usage
segment and no human long-job line**.

Prior art (not SSOT): `docs/phases/threads/04_Observed_Usage.md` — this packet
wins for receipts + live: CLI blame, no omit-as-mystery.

Phases are ephemeral. Closeout: promote law to standing docs; code stays field
SSOT; archive this packet.

---

## Intent

**Why OUR exists:** while a pilot or relay is **running**, an operator or agent
can see **alive + elapsed + observed tokens when the active CLI has reported
them** — without coupling liveness to token events and without faking cost for
silent dialects.

Secondary (supporting): terminal run receipts / artifacts show the same honesty
per seat when the run finishes. **Terminal receipt projection is not live
updates** and does not solve the steering problem alone.

Multi-CLI reality: many seats never report tokens. Missing tokens **blame the
CLI/source** — not `—`, blank, zero, or an Alln apology. No usage theater.
Execution lane first (mutating runs, pilot/relay workers).

---

## Product law

| Rule | Detail |
| --- | --- |
| Liveness | Stream / process primary (`StreamLiveness`, process ownership). **Never** infer alive from tokens. |
| Duration | Show when Alln measured it. **Unmeasured** (queued, skipped, failed-before-spawn): omit — no fake zero or dash. |
| Tokens present | Compact observed counts from driver-reported ints only. Prefer sum(in+out) as `N tok` when both sides exist. |
| Input only | Show `input tok` (or `↓ N tok`); do **not** assume output is zero. |
| Output only | Show `output tok` (or `↑ N tok`); do **not** assume input is zero. |
| Tokens absent (terminal / settled) | `tokens not reported by <sourceId>` (or `CLI` if source unknown). |
| Tokens absent (live, still running) | `tokens not yet reported by <sourceId>` — **not** the same as terminal silence. |
| No linked run (live) | Omit usage segment — **do not** invent CLI blame when there is no journal to read. |
| Multi-seat | Per-answer usage only. **No manufactured total** on `outcome.usage` for multi-seat runs. |
| Missing usage | Not an error; exit codes unchanged. |

**Live status line (hero target)** — human + JSON must both carry this signal:

```text
alive  ·  stream 12s ago  ·  2m 40s  ·  89.1k tok
alive  ·  stream 12s ago  ·  2m 40s  ·  tokens not yet reported by grok
dead   ·  no stream 4m    ·  4m 10s  ·  tokens not reported by grok
```

**Terminal receipt chip (supporting):**

```text
Opus    done  ·  18.4s  ·  41.2k tok
Grok    done  ·  31.0s  ·  tokens not reported by grok
```

One presentation helper owns blame/phrasing across live + receipt (no phrase
drift). Compact formatting may reuse `ReportedTokenUsage.formatCompact` /
`headlineSuffix` ideas, but the helper must also emit **running vs terminal
blame** and **input-only / output-only** labels (total-only is not enough).

**Banned:** estimates, dollar/quota UI, zero-filled missing fields, mid-run burn
for terminal-only dialects, new Allnighter dialect parsers, liveness from usage
events, multi-seat token totals, treating artifact export as a substitute for
live status.

---

## Bugs in today's code (must fix — not paper over)

| Lie / gap | Truth owner | Required fix |
| --- | --- | --- |
| `outcome.usage` copies **first answer only** | `TeamRunJSONMapper.mapOutcome` | Single-seat: mirror that seat. Multi-seat: **omit** `outcome.usage` (no sum, no first-answer copy). |
| Headline tok suffix is first-answer only | `RunIdentity.outcomeHeadline` | Same rule as `outcome.usage` — single-seat only, else no tok suffix. |
| Per-answer wire has **no** `usage` field | `TeamRunJSON.AnswerInfo` + mapper | Map each answer from `result.reportedTokenUsage`; empty → field **absent**. |
| Seat chips show duration, never tokens/blame | `ArtifactProjector` | Per-seat chip: duration + tok or CLI blame (S03). |
| Live status has no usage fields | `PilotStatusJSON` (+ relay status path) | Optional observed usage for **active** linked run; human line parity (S02). |
| Human `pilot status` ignores long-job fields | `PilotCLI.emitStatusResult` | Today JSON carries `elapsedSeconds` / `lastProgressAt` / … but human path only prints relay summary + recovery. **Hero line must appear in human output**, not JSON-only. |
| Long-job fields only when `handoffAlive` | `PilotCLI.longJobStatusFields` | Gate is `status == .running && recovery == .handoffAlive`. Product "dead · no stream" needs liveness/usage segments while still `.running` with a **dead owner** or silent stream — define emit rules in S02 (do not drop the whole long-job block solely because recovery ≠ handoffAlive if a linked `devRunId` exists). |
| Progressive mid-run tok not journaled | Engine warm path + AgentOS OTU-S02 | Warm path accumulates `warmReportedUsage` in memory and attaches only at settle. Do **not** show progressive mid-run tok until usage is durable on the run journal (or proven stream events). Terminal-only dialects: tok/blame at settle. |

Do not "fix" multi-seat honesty by inventing a rollup total. Do not demote live
status to "later" because receipts are easier.

---

## Truth owners

| Concern | Owner |
| --- | --- |
| Capture | AgentOS — `ReportedTokenUsage` on `WorkerRunResult` / answer `result` |
| Per-answer contract | `TeamRunJSON` + `TeamRunJSONMapper` (each answer, not first-worker-only) |
| Outcome / headline compatibility | `TeamRunJSONMapper.mapOutcome`, `RunIdentity.outcomeHeadline` |
| **Live status projection (hero)** | `PilotCLI.makeStatusJSON` / `emitStatusResult`, relay-status surfaces; wire: `PilotStatusJSON` (+ shared projection helper) |
| Active run selection | Last relay round: stream + usage from **`devRunId`** journal (`StreamLiveness.relayStreamLastActivityAt` already). Do not guess from `answers.first` of an unrelated run. |
| Liveness | `StreamLiveness` + process ownership / `InFlightRecovery` (unchanged semantics; usage additive only) |
| Terminal receipt | `ArtifactProjector` (+ `ArtifactCLI`) |
| Blame / compact tok strings | One usage-presentation helper in AllnighterCore (extend beyond total-only `headlineSuffix`) |
| Help | `HelpTopicRegistry` in the same PR as the first user-visible line (S02 and/or S03) |

Do not add local dialect parsers in Allnighter; extend AgentOS for new capture.

**Field names that already exist on live pilot JSON** (do not invent parallel ones):
`elapsedSeconds`, `ownerAlive`, `lastProgressAt`, `silenceAgeSeconds`,
`streamSilenceWarning`, `waitHintSeconds`, `commitsSinceBaseline` (supplementary).
There is **no** `silenceStatus` / `progressStale` on `PilotStatusJSON` today —
do not document them as if present. Usage fields are additive optional keys.

---

## Dependency on AgentOS (honest)

| AgentOS | Unblocks Alln |
| --- | --- |
| Existing extractors (claude_code / codex / cursor_agent) | Real tok on those seats **at settle** today |
| OTU-S00 matrix | "Never reports" vs "unknown" product copy accuracy |
| OTU-S02 mid-stream **and durable journal of partial usage** | Progressive live tok mid-turn for that driver |
| OTU-S03 warm parity | Warm/serve paths match cold extractors |

Ship **live + terminal** with duration + honest blame for nil without universal
CLI coverage. **Do not** show progressive mid-run tok until OTU-S02 (or proven
stream events) **and** the running journal exposes non-nil usage for the active
seat. Terminal-only dialects: tok at settle or blame at settle / while running
use `not yet reported`.

Allnighter presentation is **not** blocked on OTU-S00 inventory to ship S01–S03
with honest nil + duration.

---

## Contract

### Per answer (`TeamRunJSON.AnswerInfo`) — S01

```text
usage?: { inputTokens?: Int, outputTokens?: Int }
```

- Map only from that answer’s `result.reportedTokenUsage`.
- Empty `ReportedTokenUsage` → field **absent** (not zero object).
- Decode older JSON without the field (backward compatible).

### `outcome.usage` (compatibility — fix the bug)

- **Single non-skipped seat** with reported usage: mirror that answer (headline path).
- **Multi-seat:** omit `outcome.usage` — do not sum, do not copy first answer.
- Top-level `usage.cliCalls` stays **call count only** (not tokens).

### Live status JSON/text (S02 — hero)

Keep existing liveness fields. Add optional observed usage for the **active**
linked seat when non-nil.

**Active seat selection (must implement exactly):**

1. While relay/pilot `status == running` and last round has `devRunId`, load that
   run from `RunStore` (same journal `StreamLiveness` uses).
2. Usage = that run’s active worker answer `result.reportedTokenUsage` when
   non-empty; sourceId from that seat’s model/driver mapping.
3. If `devRunId` is nil: omit usage segment (no fake CLI blame).
4. Do **not** use `pmRunId` for stream-primary live tok unless product later
   defines a PM-in-flight status surface; pilot PM is external — hero is the
   **dev turn** in flight.
5. Multi-answer journals (should be rare on mutating pilot/relay): still
   per-seat only; live line shows the in-flight worker, never a manufactured sum.

**Running vs terminal blame:**

| State | Missing tokens copy |
| --- | --- |
| Non-terminal, linked run, no usage yet | `tokens not yet reported by <sourceId>` |
| Terminal settle / receipt, never reported | `tokens not reported by <sourceId>` |
| No linked run id | omit usage segment |

**Human + JSON parity** for `pilot status` and `relay-status` (shared projection
helper). JSON may expose structured fields (e.g. optional
`observedUsage` / `usagePresentation` string); human must not be a silent subset
of long-job truth.

Document exact JSON keys in the S02 PR; additive only.

---

## Slices

### OUR-S01 — Per-answer contract + presentation helper + outcome lie

Map usage onto **each** answer; fix first-answer-only `outcome.usage` **and**
headline suffix; one helper for chip/blame/partial-side strings used by live +
receipt.

**Works test:** two-seat fixture — reporting seat has ints; silent seat has no
`usage` key; `outcome.usage` absent; one-seat fixture preserves compatible
`outcome.usage` + headline tok; empty usage → absent; backward decode of
pre-change JSON; input-only and output-only formatting (no assumed zero).

**Gate:** existing AgentOS extractors + honest nil. Does not wait on OTU-S00.

### OUR-S02 — Live pilot / relay status (**primary** — why OUR exists)

Append observed duration + optional usage on **active** pilot/relay status while
non-terminal. Stream-primary liveness unchanged. Mid-stream progressive tok only
per AgentOS OTU-S02 + durable journal (see bugs table).

Must define **before build** (acceptance blockers, not prose hedges):

- Active seat = last round `devRunId` journal (see Contract).
- Behavior when `devRunId` is nil (omit usage; keep recovery advice).
- Running vs settled copy (`not yet reported` vs `not reported`).
- When long-job / usage segments emit for dead-owner or silent-stream cases
  (product hero lines with `dead` / `no stream` must be reachable without
  inventing liveness from tokens).
- Human path prints the hero signal (not JSON-only).
- Proof `lastProgressAt` / `silenceAgeSeconds` / `streamSilenceWarning` /
  recovery advice unchanged when usage is nil.

**Works test:** status fixtures —

- alive + elapsed + tok when journal has usage;
- running silent seat → `not yet reported` (not zero, not terminal wording);
- no `devRunId` → no usage segment;
- hung/silent stream still shows silence age; liveness fields unchanged with nil usage;
- human and `--json` both expose the usage/blame signal;
- after settle, do not pretend live status replaces the receipt.

### OUR-S03 — Terminal receipt + help

Project per-seat chips on artifact export; help search for tokens / usage /
duration / pilot status.

**Works test:** artifact golden — duration, tok or blame, no invented totals;
`help search` hits; live fixtures from S02 still green.

---

## Non-goals

- Dollar pricing, quota remaining UI
- Usage-derived liveness
- Multi-seat token totals / rollup theater
- New Allnighter parsers
- Blocking on universal CLI coverage
- Judgment-lane-only chrome programs
- Replacing live status with terminal-only receipts
- Mac-only or iOS-only private usage chrome that diverges from CLI JSON

---

## Risks

| Risk | Mitigation |
| --- | --- |
| User thinks Alln “missed” Grok | Explicit CLI blame; live uses `not yet` while running |
| Accusing CLI while run still going | Running vs terminal copy |
| Pilot/relay shape drift | One projection helper; document both surfaces in S02 |
| JSON-only long-job truth | Human emit path must print hero segments (bug table) |
| Progressive tok before journal truth | Gate on OTU-S02 + durable partial usage; else settle-only |
| Contract bump | Additive optional fields; absent = unreported |
| First-answer lie survives via headline | Fix mapper **and** `RunIdentity` in S01 |

---

## Proof wall

```text
swift test --package-path Packages/AllnighterCore
bash scripts/check.sh
```

Focused:

- S01 — mapper fixtures (multi-seat omit outcome.usage; single-seat preserve;
  per-answer usage; decode old JSON; partial-side formatting).
- S02 — pilot/relay status fixtures (human + JSON); liveness regression when
  usage nil; no-linked-run; running blame wording.
- S03 — artifact golden; help search hits.

**Skeptical demo (hero):** relay/pilot **running** — `pilot status` (human and
`--json`) shows alive/stream/elapsed + tok **or** honest `not yet reported` for
the active CLI; silence age still moves with the stream; after settle, artifact
receipt matches per-seat JSON; silent CLI named; no zeros invented; no multi-seat
total; stream liveness still process/stream-primary.

---

## Related docs

| Doc | Role |
| --- | --- |
| AgentOS `Observed_Token_Usage_Capture.md` | Capture SSOT (OTU-S00–S04) |
| `threads/04_Observed_Usage.md` | History; presentation superseded here |
| Pilot liveness hotfixes / `StreamLiveness` | Stream-primary alive remains law |
| Team Run Receipt (archived) | Duration chips partial; tokens + live are the gap |
```