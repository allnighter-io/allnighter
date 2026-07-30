# Observed Usage on Receipts and Live Status

Status: **OPEN** — presentation only. **Primary deliverable: live pilot / relay status.**
Tokens come from AgentOS capture; Alln never invents numbers. Liveness stays
stream/process-primary — usage is additive, never a heartbeat.

Owner: **AllnighterCore** (`TeamRunJSON`, `TeamRunJSONMapper`, `ArtifactProjector`,
usage presentation) + **AllnighterEngine** (pilot / relay live status). **AgentOS**
owns capture on `WorkerRunResult`.

Version: **v4 (2026-07-30)** — restore live status as hero; keep v3 bug-fix law.

Upstream: AgentOS `docs/phases/Observed_Token_Usage_Capture.md`.

Already shipped partial: seat duration chips; optional outcome usage + headline tok
suffix when present. **Known bug:** outcome usage maps **first answer only** (must
fix; do not replace with a fake multi-seat total).

Prior art (not SSOT): `docs/phases/threads/04_Observed_Usage.md` — this packet wins
for receipts + live: CLI blame, no omit-as-mystery.

Phases are ephemeral. Closeout: promote law to standing docs; code stays field SSOT;
archive this packet.

---

## Intent

**Why OUR exists:** while a pilot or relay is **running**, an operator or agent can
see **alive + elapsed + observed tokens when the active CLI has reported them** —
without coupling liveness to token events and without faking cost for silent dialects.

Secondary (supporting): terminal run receipts / artifacts show the same honesty per
seat when the run finishes. **Terminal receipt projection is not live updates** and
does not solve the steering problem alone.

Multi-CLI reality: many seats never report tokens. Missing tokens **blame the
CLI/source** — not `—`, blank, zero, or an Alln apology. No usage theater.
Execution lane first (mutating runs, pilot/relay workers).

---

## Product law

| Rule | Detail |
| --- | --- |
| Liveness | Stream / process primary (`StreamLiveness`, process ownership). **Never** infer alive from tokens. |
| Duration | Show when Alln measured it. **Unmeasured** (queued, skipped, failed-before-spawn): omit — no fake zero or dash. |
| Tokens present | Compact observed counts from driver-reported ints only (sum in+out per seat when both exist). |
| Input only | Show `input tok`; do not assume output is zero. |
| Output only | Show `output tok`; do not assume input is zero. |
| Tokens absent (terminal / settled) | `tokens not reported by <sourceId>` (or `CLI` if source unknown). |
| Tokens absent (live, still running) | `tokens not yet reported by <sourceId>` — **not** the same as terminal silence. |
| Multi-seat | Per-answer usage only. **No manufactured total** on `outcome.usage` for multi-seat runs. |
| Missing usage | Not an error; exit codes unchanged. |

**Live status line (hero target):**

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

One presentation helper owns blame/phrasing across live + receipt (no phrase drift).

**Banned:** estimates, dollar/quota UI, zero-filled missing fields, mid-run burn for
terminal-only dialects, new Allnighter dialect parsers, liveness from usage events.

---

## Truth owners

| Concern | Owner |
| --- | --- |
| Capture | AgentOS — `ReportedTokenUsage` on `WorkerRunResult` |
| Per-answer contract | `TeamRunJSON` + `TeamRunJSONMapper` (each answer, not first-worker-only) |
| **Live status projection** | `PilotCLI`, relay status surfaces, `PilotStatusJSON` / `RelayJSON` |
| Active run selection | Relay state (`pmRunId`, `devRunId`, round phase) — must not guess from first answer |
| Liveness | `StreamLiveness` + process ownership (unchanged by this packet) |
| Terminal receipt | `ArtifactProjector` (+ `ArtifactCLI`) |
| Blame / compact tok strings | One usage-presentation helper |
| Help | `HelpTopicRegistry` in the same PR as user-visible lines |

Do not add local dialect parsers in Allnighter; extend AgentOS for new capture.

---

## Dependency on AgentOS (honest)

| AgentOS | Unblocks Alln |
| --- | --- |
| Existing extractors (claude_code / codex / cursor_agent) | Real tok on those seats today |
| OTU-S00 matrix | “Never reports” vs “unknown” copy |
| OTU-S02 mid-stream | **Live** tok updates mid-turn for that driver |
| OTU-S03 warm parity | Warm/serve paths match cold |

Ship **live + terminal** with duration + honest blame for nil without universal
coverage. **Do not** show progressive mid-run tok until OTU-S02 (or proven stream
events) for that driver. Terminal-only dialects: tok at settle or blame at settle.

---

## Contract

**Per answer (`TeamRunJSON.AnswerInfo`):**

```text
usage?: { inputTokens?: Int, outputTokens?: Int }
```

- Map only from that answer’s `result.reportedTokenUsage`.
- Empty `ReportedTokenUsage` → field **absent** (not zero).
- Decode older JSON without the field.

**`outcome.usage` (compatibility — fix the bug):**

- **Single-seat** run with reported usage: mirror that answer (today’s headline path).
- **Multi-seat:** omit `outcome.usage` — do not sum, do not copy first answer.
- Top-level `usage.cliCalls` stays call count only.

**Live status JSON/text (S02 — hero):**

- Keep existing liveness fields (`lastProgressAt`, `silenceStatus`, `progressStale`, …).
- Add optional observed usage for the **active** seat when non-nil.
- Running vs terminal blame strings per product law above.
- Human + JSON parity for `pilot status` and `relay-status` (may share one projection helper; document shapes in slice).

---

## Slices

### OUR-S01 — Per-answer contract + presentation helper

Map usage onto **each** answer; fix first-answer-only outcome lie; one helper for
chip/blame strings used by live + receipt.

**Works test:** two-seat fixture — reporting seat has ints; silent seat has no
`usage` key; `outcome.usage` absent; one-seat fixture preserves compatible
`outcome.usage`; backward decode of pre-change JSON.

**Gate:** existing AgentOS extractors + honest nil. Does not wait on OTU-S00.

### OUR-S02 — Live pilot / relay status (primary — why OUR exists)

Append observed duration + optional usage on **active** pilot/relay status while
non-terminal. Stream-primary liveness unchanged. Mid-stream tok only per OTU-S02
for that driver.

Must define before build:

- How active PM vs dev run is selected from relay state.
- Behavior when relay has no linked run id.
- Running vs settled copy (`not yet reported` vs `not reported`).
- Proof `lastProgressAt` / silence / recovery advice unchanged when usage nil.

**Works test:** status fixtures — alive + elapsed + tok when present; running silent
seat shows `not yet reported` (not zero); hung stream still shows silence age;
terminal settle shows `not reported` when dialect never reported; liveness fields
unchanged.

### OUR-S03 — Terminal receipt + help

Project per-seat chips on artifact export; help search for tokens/usage/duration/pilot
status.

**Works test:** artifact golden — duration, tok or blame, no invented totals;
`help search` hits; status/liveness fixtures unchanged from S02.

---

## Non-goals

- Dollar pricing, quota remaining UI
- Usage-derived liveness
- Multi-seat token totals
- New Allnighter parsers
- Blocking on universal CLI coverage
- Judgment-lane-only chrome programs
- Replacing live status with terminal-only receipts

---

## Risks

| Risk | Mitigation |
| --- | --- |
| User thinks Alln “missed” Grok | Explicit CLI blame; live uses `not yet` while running |
| Accusing CLI while run still going | Running vs terminal copy |
| Pilot/relay shape drift | One projection helper; document both surfaces in S02 |
| Contract bump | Additive optional fields; absent = unreported |

---

## Proof wall

```text
swift test --package-path Packages/AllnighterCore
bash scripts/check.sh
```

Focused: mapper fixtures (S01), pilot/relay status fixtures (S02), artifact golden (S03).

**Skeptical demo:** relay/pilot running — status shows alive + elapsed + tok or honest
`not yet reported`; after settle, receipt matches per-seat JSON; silent CLI named;
no zeros invented; stream liveness unchanged.

---

## Related docs

| Doc | Role |
| --- | --- |
| AgentOS `Observed_Token_Usage_Capture.md` | Capture SSOT |
| `threads/04_Observed_Usage.md` | History; presentation superseded here |
| Pilot liveness hotfixes | Stream-primary alive remains law |
| Team Run Receipt (archived) | Duration chips partial; tokens + live are the gap |
