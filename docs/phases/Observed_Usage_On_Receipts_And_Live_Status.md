# Observed Usage on Receipts and Live Status

Status: **OPEN** — presentation only. Tokens come from AgentOS capture; Alln
never invents numbers. Duration and liveness stay Alln-owned clocks.
Owner: **AllnighterCore** (TeamRunJSON / mapper / ArtifactProjector) +
**AllnighterEngine** (pilot / relay status). **AgentOS** owns capture.
Version: **v2 (2026-07-30)** — doc review: same product law, tighter slices,
sharper ownership. Origin: founder brainstorm (2026-07-29).
Upstream (tokens): AgentOS
`docs/phases/Observed_Token_Usage_Capture.md`
(local: `/Users/mike/Documents/GitHub/AgentOS/docs/phases/Observed_Token_Usage_Capture.md`).
Prior art (not SSOT for this path): `docs/phases/threads/04_Observed_Usage.md`.
Already shipped partial: FR14 / `ReportedTokenUsage` on outcome + headline
suffix when present; seat duration chips; **bug:** outcome usage maps
**first worker only**.

Phases are ephemeral. Closeout: promote law into standing docs if needed;
code stays field SSOT; archive this packet.

---

## Intent (one paragraph)

After AgentOS reports real per-driver usage (or honest nil), surface **observed
duration always** and **observed tokens when present** on (1) every run receipt /
artifact and (2) live pilot / relay status. Multi-CLI reality: many seats stay
silent. Missing tokens **blame the CLI/source**, never a blank dash, zero, or
Alln apology. No usage theater. Execution lane first.

---

## Product law

| Rule | Detail |
| --- | --- |
| Duration | Always show when Alln measured it (seat and/or wall). |
| Liveness | Stream / process primary. **Never** depend on token events. |
| Tokens present | Compact observed counts from driver-reported ints only. |
| Tokens absent | Explicit CLI blame. **Not** `—`, blank, omit-as-mystery, or `0`. |
| Rollup | Sum / show only seats that reported. Partial rollup is honest; zero-fill is a lie. |
| Estimates | Banned: token guesses, dollars, quota %, mid-run burn for terminal-only dialects. |

Canonical chip shape (presentation owner must keep one form):

```text
Opus    18.4s  ·  41.2k tok
Grok    31.0s  ·  tokens not reported by grok
```

Shorter OK (`31.0s · not reported by CLI`) if `sourceId` lives in tooltip/JSON.
Priority: **execution** (mutating runs, pilot/relay). Judgment seats may reuse
the same fields when free — no second chrome program.

**Cutover vs `threads/04`:** that doc allowed “usage unavailable” / omit. For
receipts + live status, **this packet wins**: CLI blame, no omit-as-mystery.

---

## Truth owners

| Concern | Owner |
| --- | --- |
| Capture / extractors | AgentOS — `ReportedTokenUsage` on `WorkerRunResult` |
| Per-seat + outcome contract | Alln — `TeamRunJSON` + `TeamRunJSONMapper` |
| Receipt chrome | Alln — `ArtifactProjector` (+ ArtifactCLI); Floor reads same projection |
| Live status line | Alln — PilotCLI / relay status; liveness: `StreamLiveness` + process ownership |
| Duration clocks | Runner timing + Alln status (independent of usage events) |
| Blame / chip string form | One presentation helper (pick at S01/S02; do not fork phrases) |
| Help copy | `HelpTopicRegistry` in the same PR as user-visible fields/lines |

Alln **must not** add local dialect parsers. Silent seat → extend AgentOS.

---

## Dependency on AgentOS (honest)

| AgentOS | Unblocks Alln |
| --- | --- |
| **Existing extractors** (claude_code / codex / cursor_agent) | Real tok on those seats **today** |
| OTU-S00 matrix | Honest “never reports” vs “unknown / not probed” copy |
| OTU-S01 more extractors | More seats with real ints, still no Alln parsers |
| OTU-S02 mid-stream | Live tok updates mid-turn (only then) |
| OTU-S03 warm parity | Warm/serve paths match cold |

**Ship without full AgentOS:** duration + explicit “not reported by …” for nil
usage. **Do not ship:** mid-run tok for a driver until OTU-S02 (or proven
streaming events) for that driver. Terminal-only dialects: tok at settle or
blame forever.

---

## Target surfaces (once)

**Contract (`TeamRunJSON`)**

- Per answer: keep duration fields; optional `usage` mirroring
  `ReportedTokenUsage` (`inputTokens?`, `outputTokens?`) — **field absent when
  unreported** (not zero).
- Outcome: rollup **only reported seats**; document partial. **Fix**
  first-worker-only mapping.
- Top-level `usage.cliCalls` stays call count — do not overload with tokens.

**Receipt / artifact (terminal)**

- Seat chip: `status · duration · tokens | not reported by <sourceId>`.
- Optional footer: wall + “N of M seats reported tokens”.
- `alln artifact show|export` and Floor share `ArtifactProjector`.

**Live (pilot / relay / status)**

- Keep stream-primary liveness + elapsed.
- Append observed usage **only when non-nil**.
- Nil usage: omit tok **or** show blame when the active seat is known silent —
  never fake burn. Mid-stream only if AgentOS delivered it for that driver.

**CLI / exit**

- Missing usage is **not** an error. Exit codes unchanged.

**Help**

- Teach: duration = Alln; tokens = CLI when reported; silence = CLI, not Alln.
- Search: tokens, usage, tok, duration, receipt, pilot status.
- No dollar/quota commands. No fake “usage” verb.

---

## Slices (Alln only)

### OUR-S01 — Contract + mapper (do first)

Map `WorkerRunResult.reportedTokenUsage` onto **each** answer; fix outcome
rollup to reported seats only; shared presentation helper for headline/chip
strings if cheap. Contract regen if schema changes.

**Works test:** multi-seat fixture → reporting seat has ints; silent seat has
**no** usage field; outcome partial rules unit-tested; no first-worker-only.

**Gate:** existing AgentOS extractors + honest nil. Does **not** wait on OTU-S00
completion.

### OUR-S02 — Artifact / receipt + help

Project seat chips + optional footer; wire help topics/aliases in the same PR.

**Works test:** export contains duration and either tok or `not reported by
<sourceId>`; no invented numbers; `help search` hits for tokens/usage.

### OUR-S03 — Live pilot / relay status

Append non-nil usage; liveness stays stream/process-primary. Mid-stream tok only
per AgentOS OTU-S02 for that driver.

**Works test:** status fixtures — silent active seat shows blame or no tok (not
zero); hung stream still shows silence age with nil usage; non-nil appends when
present.

No OUR-S00 (packet is this file). No solo help slice.

---

## Non-goals

- Dollar pricing, quota remaining UI
- Liveness from usage events
- Parallel token parsers in Allnighter
- Blocking ship on universal CLI coverage
- Judgment-lane-only chrome or cost dashboards

---

## Risks

| Risk | Mitigation |
| --- | --- |
| User thinks Alln “missed” Grok | Explicit CLI blame string |
| Contract bump noise | Additive optional fields; null/absent = unreported |
| Pilot accused of lying on mid-run tok | Terminal-only dialects: settle or never; document |
| Phrase drift across surfaces | One presentation helper |

---

## Proof (implementation)

```text
swift test
scripts/check.sh
# + mapper multi-seat fixture (present / absent / partial outcome)
# + artifact export golden (tok vs blame)
# + pilot/relay status fixtures (liveness ≠ tokens)
```

Skeptical demo: one reporting seat + one silent seat; TeamRunJSON, artifact, and
status agree; no zeros invented.

---

## Related docs

| Doc | Role |
| --- | --- |
| AgentOS `Observed_Token_Usage_Capture.md` | Capture SSOT; this packet consumes it |
| `threads/04_Observed_Usage.md` | History; presentation path superseded here |
| Team Run Receipt (archived) | Duration chips shipped; tokens are the gap |
| Pilot liveness hotfixes | Stream-primary alive remains law; usage additive |