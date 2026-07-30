# Observed Usage on Receipts and Live Status

Status: **OPEN** — build terminal receipts first; live status is deferred behind a separate contract gate.

Owner: **AllnighterCore** owns `TeamRunJSON`, `TeamRunJSONMapper`, usage presentation, and `ArtifactProjector`. **AgentOS** owns captured `ReportedTokenUsage` on `WorkerRunResult`.

Version: **v3 (2026-07-30)** — doc review pass 2 (Sol).

Upstream: AgentOS `docs/phases/Observed_Token_Usage_Capture.md`.

Already shipped: optional outcome usage, headline token suffix when present, and seat duration chips. Known bug: outcome usage reads the first answer only.

Phases are ephemeral. At closeout, promote durable contract law to code or standing docs, then archive this packet.

---

## Intent

Surface measured duration and driver-reported token usage on terminal run receipts without estimating, zero-filling, or hiding silent CLIs. Each answer owns its own observation. Mutating runs are the first product path; other Teams inherit the same contract without separate chrome.

Live pilot and relay status remain part of the product direction, but do not ship from this packet until their active-run truth is explicit.

---

## Product law

| State | Presentation |
| --- | --- |
| Measured duration | Show the observed duration. |
| Unmeasured duration | Omit it; never render zero or a dash that implies measurement. |
| Both token fields reported | Show their sum as compact `tok`. |
| Input only | Show compact `input tok`; do not assume output is zero. |
| Output only | Show compact `output tok`; do not assume input is zero. |
| Empty or absent usage at terminal | Show `tokens not reported by <sourceId>`. |
| Unknown source id | Show `tokens not reported by CLI`; never render an empty blame label. |
| Multi-seat run | Present usage per answer only. Do not manufacture a total. |
| Missing usage | Not an error; exit codes and run status stay unchanged. |

Canonical terminal chip:

```text
Opus    done  ·  18.4s  ·  41.2k tok
Grok    done  ·  31.0s  ·  tokens not reported by grok
```

Banned:

- Estimated tokens
- Zero-filled missing fields
- Dollar cost or quota percentages
- Liveness inferred from token events
- A multi-seat total without an explicit future contract
- New dialect parsing in Allnighter

---

## Truth owners

| Concern | Truth owner |
| --- | --- |
| Usage capture and driver dialects | AgentOS `ReportedTokenUsage` and `WorkerRunResult.reportedTokenUsage` |
| Per-answer public contract | AllnighterCore `TeamRunJSON.AnswerInfo` |
| Mapping persisted run truth | `TeamRunJSONMapper` reading each answer result |
| Single-seat outcome compatibility | `TeamRunJSONMapper.mapOutcome` |
| Terminal receipt projection | `ArtifactProjector` |
| Phrase and compact-number formatting | One AllnighterCore usage-presentation helper |
| Source attribution | `TeamRunJSON.agents[].sourceId`, joined by `agentId` |
| Duration | Existing runner timing; independent of usage |
| CLI contract version | `ContractRegistry` |
| Help discovery | `HelpTopicRegistry` |

Existing Allnighter compatibility parsers are not removed by this packet. Do not add another parser or extend a dialect here. New or corrected capture belongs in AgentOS.

---

## Contract

Add optional usage to each `TeamRunJSON.AnswerInfo`:

```text
usage?: {
  inputTokens?: Int
  outputTokens?: Int
}
```

Rules:

- Map only from that answer’s `result.reportedTokenUsage`.
- Treat an empty `ReportedTokenUsage` as absent.
- Omit `usage` from encoded JSON when absent.
- Decode older JSON without the field.
- Do not duplicate `sourceId` inside the usage object; join through `agentId`.
- Keep top-level `usage.cliCalls` as call count.
- Bump the public contract version and update contract fixtures.

`outcome.usage` compatibility:

- Preserve it only for a run with exactly one non-skipped answer and non-empty reported usage.
- Omit it for multi-seat runs.
- Do not sum answers.
- This removes the current first-answer lie without inventing new rollup semantics.

---

## AgentOS dependency

This slice requires the pinned AgentOS dependency to provide:

- `ReportedTokenUsage`
- `WorkerRunResult.reportedTokenUsage`
- Green fixture coverage for any driver described as reporting usage

This slice does not wait for universal driver coverage or the full OTU-S00 matrix. A terminal nil result is enough to render honest CLI-blame copy.

This slice does not authorize new Allnighter dialect parsing.

Future live token updates remain blocked for each driver until AgentOS OTU-S02 proves and exposes mid-stream usage for that driver. Terminal-only capture must not be presented as progressive burn.

---

## Slice

### OUR-S01 — Terminal contract, receipt, and help

Implement the per-answer contract, remove first-answer behavior from multi-seat outcomes, render terminal receipt chips, and update help discovery in one bounded slice.

Out of scope:

- Pilot status
- Relay status
- Floor-specific UI
- Multi-seat totals
- Coverage footer
- AgentOS extractor work

Works tests:

1. Encode a two-seat terminal run:
   - reporting seat contains exact `inputTokens` and `outputTokens`;
   - silent seat has no `usage` key;
   - neither seat receives the other seat’s usage;
   - `outcome.usage` is absent.
2. Encode a one-seat terminal run:
   - `outcome.usage` matches that answer exactly;
   - absent or empty usage omits both answer and outcome usage.
3. Decode a pre-change TeamRunJSON fixture successfully.
4. Render artifact cases for:
   - both token fields;
   - input-only;
   - output-only;
   - silent known source;
   - silent unknown source;
   - unmeasured duration.
5. Assert rendered output contains no invented zero, blank source blame, or multi-seat total.
6. Assert `help search tokens`, `help search usage`, and `help search duration` find the receipt explanation.
7. Assert existing run status and exit-code fixtures are unchanged.

Done when:

- Machine JSON and rendered HTML agree for every fixture.
- The contract version and fixtures are updated.
- AgentOS remains the capture owner.
- Focused tests and the repository green wall pass.

---

## Deferred live-status contract

Live status requires a separate slice or packet after terminal receipts ship.

Before build authorization, it must define:

- How the active PM or dev run is selected from durable relay state.
- What happens when a running relay has no linked run id.
- Whether usage belongs on `RelayJSON`, `PilotStatusJSON`, or a shared status projection.
- Human and JSON shapes for both `pilot status` and `relay-status`.
- Running nil copy: `tokens not yet reported by <sourceId>`.
- Terminal nil copy: `tokens not reported by <sourceId>`.
- Whether settled status shows the latest turn or a round summary.
- Proof that `lastProgressAt`, `silenceAgeSeconds`, process ownership, and recovery advice are unchanged.

No live implementation should begin by reading the first answer or guessing the active phase.

---

## Non-goals

- Dollar pricing
- Quota remaining
- Token estimates
- Multi-seat token totals
- Usage-derived liveness
- New Allnighter parsers
- Universal CLI coverage
- A new `usage` command
- Cost dashboards

---

## Proof wall

```text
swift test --package-path Packages/AllnighterCore
bash scripts/check.sh
```

Required focused proof:

```text
TeamRunJSON mapper and compatibility fixtures
ArtifactProjector usage render golden
HelpTopicRegistry search tests
```

Skeptical demo: one reporting seat and one silent seat finish the same Team run. TeamRunJSON and the exported artifact agree per seat, the silent CLI is named, no zero or aggregate is invented, and existing status/liveness output is unchanged.

---

## Closeout

Promote durable law to:

- `TeamRunJSON` and `TeamRunJSONMapper` for the public contract
- The shared usage-presentation helper for copy and formatting
- `ArtifactProjector` for receipt presentation
- `ContractRegistry` and `HelpTopicRegistry` for discoverability

Then archive this packet. The deferred live-status contract remains separate work and must not be implied complete by the receipt slice.
