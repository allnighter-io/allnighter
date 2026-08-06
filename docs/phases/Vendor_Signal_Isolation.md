# Vendor Signal Isolation

Status: **Open — VSI-S01/S02 implementation-ready as one landing unit; VSI-S04
and VSI-S05 implementation-ready; VSI-S03 requires the §10.1 founder ruling.**
Priority: **Above `Agent_Teaching_Surface.md`.** That packet teaches agents to
delegate; this one stops the bench lying about why delegation failed. Teaching a
caller to trust a surface that misreports vendor state is worse than not teaching
it at all. Land VSI-S01/S02 first.

Owner: unassigned — primarily AgentOS
(`Sources/AgentOSCLI/CapacityClassifier.swift`, `DriverManifest.swift`), with
Allnighter work in VSI-S03 and VSI-S05.
Created: 2026-08-06
Origin: A 25-minute Qwen 3.8 Max run was reported as
`capacity: accountRateLimit` with a fabricated one-hour wake time. Qwen has no
hourly window — weekly only (founder, 2026-08-06). The run had produced 26,418
characters of correct work; `alln export` returned the prompt and nothing else.
Both the diagnosis and the loss were false.

Phases are ephemeral. At closeout: promote durable product law into routed docs;
code remains SSOT; archive this packet.

> AgentOS is a shared package with consumers beyond Allnighter. Every AgentOS
> slice changes somebody else's runtime. §4 is the deletion bar.

---

## 1. Founder intake

Intake per `docs/workflows/SSOT_Founder_Input_Workflow.md`.

- **Intent.** Stop one vendor's parser from answering for another vendor, stop
  the bench inventing numbers it did not observe, and stop losing completed work
  when a run terminates badly.
- **Value.** A false capacity signal parks a healthy run, can make it eligible
  for substitution, and can display a fabricated wake time as structured fact.
- **Trusted workflow.** `alln run --model <seat>` → the selected seat works →
  it finishes or fails → the reason is true and produced work remains retrievable.
- **Current state.** §2. The ownership defect is certain; the exact offending
  bytes are not recoverable.
- **Truth owners.** AgentOS `CapacityClassifier`, `CapacityObservation`,
  `DriverManifest`, `DriverManifest.validate()` and `Catalog/catalog.json`;
  Allnighter `VendorBackoffPolicy`, `VendorBackoffWakePlanner`, `RunStore`,
  `RunService.runExecution`, and `TeamRunJSONMapper`.
- **CLI surface.** No new commands. `alln show` and `alln export` gain truthful
  partial content in VSI-S05. `alln doctor explain` retains its existing codes.
- **Risk class.** Capacity routing touches quota-spend and vendor selection, so
  VSI-S03 requires the High-Risk Stop recorded in §10.1.
- **Next slice.** VSI-S01/S02.

## 2. Incident

Recorded observation from run `A6A06D63`, verbatim:

```json
{ "kind": "accountRateLimit", "source": "qwen", "sourceConfidence": "structured",
  "rawSnippet": "turn.failed", "retryAfterSeconds": 3600,
  "observedAt": "2026-08-06T18:36:52Z", "wakeAfter": "2026-08-06T19:36:52Z" }
```

Three independent signatures identify the producing branch:

| Recorded value | Producing code |
| --- | --- |
| `rawSnippet: "turn.failed"` | `codexMessage()` default |
| `retryAfterSeconds: 3600` | `unknownBackoffSeconds` |
| `sourceConfidence: "structured"` | `classifyGrokJSON` payment branch |

Claude requires `type: rate_limit_error`. Codex derives its reset rather than
using that constant. These values belong to Grok's payment branch even though
`sourceId` was Qwen. Grok's parser answered for Qwen.

The branch combines a resolved message with the entire JSON event and performs
bare substring matching. Its `paymentPatterns` are:

```text
"402", "payment required", "payment_required", "balance exhausted",
"usage balance"
```

A token count, duration, byte offset, line number, or identifier containing
`402` can therefore become a billing failure.

The exact trigger in this incident — integer status 402 versus a `402`
substring — cannot now be established. Raw stdout and stderr exist transiently
inside `CommandResult`, but `WorkerRunResult` retains only normalized output,
failure facts, diagnostics, and `CapacityObservation`. The journal retained the
classification, not the deciding bytes.

The second failure:

```text
alln export A6A06D63 --format md   →  2,657 chars (the echoed prompt)
answer seen by the stream watcher  → 26,418 chars
alln show --json                   → answer: null
```

The watcher buffer was the only surviving copy.

## 3. Root causes

### 3.1 Parser ownership is ignored

`CapacityClassifier.Input` already carries `sourceId`, but structured
classification currently tries Claude, Codex, and Grok parsers sequentially
against every driver's JSON. The result is order-dependent and O(vendors²).

The immediate fix is source dispatch: a driver may evaluate only its own
structured rules and source-scoped residuals. Unknown sources do not inherit a
capacity parser or a global capacity-text fallback.

Auth/manual blocker handling is outside the capacity manifest and remains
stderr-only. It must still be source-safe; VSI-S02 removes numeric auth
substrings rather than moving auth into this packet.

### 3.2 Confidence and reset fields overclaim

`CapacityObservation` says confidence describes derivation, not provider truth,
and that retry fields exist only when the CLI/API supplied them. Current code
violates both statements:

- whole-line substring matches can return `structured`;
- Grok payment matches receive an invented 3,600 seconds;
- Claude overload receives an invented 60 seconds;
- generic capacity/payment fallbacks receive invented delay values.

Nil is already representable. Missing vendor reset evidence must leave
`observedResetAt`, `retryAfterSeconds`, and vendor-derived `wakeAfter` nil.

### 3.3 False positives are more expensive

| Failure | Cost |
| --- | --- |
| Miss a real limit | The run fails loudly; the owner can inspect and retry. |
| Invent a limit | A healthy run parks or reseats and displays false structured state. |

Classification therefore fails closed: no owned, declared signal means no
capacity observation.

## 4. Shared-package deletion bar

1. **Freeze available evidence.** Copy existing AgentOS classifier cases into
   named sanitized fixtures before changing behavior. Add the recorded Qwen
   observation as a regression expectation, not as a raw-output fixture.
2. **Do not require unavailable history.** The raw bytes for `A6A06D63` were not
   retained and cannot be reconstructed. A new real vendor-limit capture would
   spend quota or require temporary diagnostic retention; either needs separate
   approval and is not a gate for VSI-S01/S02.
3. **Exact equivalence with an allowlist.** For owned fixtures, pre/post
   `CapacityObservation` encoding must be byte-identical except for these
   intended deletions:
   - cross-source matches;
   - matches against an entire raw JSON line;
   - numeric-code substring matches;
   - locally invented retry/wake values;
   - unscoped generic capacity-text matches.
4. **Additive manifest decoding.** `capacity` is optional and
   `manifestVersion` remains `1`. Absence decodes successfully and emits no
   manifest capacity observation.
5. **Boundary validation.** `DriverManifest.validate()` in
   `DriverManifestValidation.swift` rejects malformed predicates, paths, kinds,
   resolvers, and windows at catalog load.
6. **State the behavioral contraction.** The AgentOS changelog says the
   classifier intentionally emits fewer observations.
7. **No raw-output retention is added here.** That would create a new privacy,
   redaction, retention, and persisted-schema decision.

## 5. Capacity manifest contract

### 5.1 Schema

The original `path`/`equals` proposal is insufficient for Codex and part of
Grok. The minimal complete block is:

```json
"capacity": {
  "signals": [
    {
      "when": {
        "all": [
          { "paths": ["type"], "oneOf": ["error", "turn.failed"] },
          {
            "paths": ["message", "error", "error.message", "error.code"],
            "containsAny": ["credits", "spend cap"]
          }
        ]
      },
      "kind": "accountRateLimit",
      "retryAfter": {
        "paths": [
          "retry_after", "retryAfter",
          "retry_after_seconds", "retryAfterSeconds"
        ],
        "format": "seconds"
      },
      "resetAt": {
        "paths": ["resetsAt", "error.resetsAt"],
        "format": "iso8601"
      },
      "snippet": {
        "paths": ["message", "error", "error.message", "error.code"]
      }
    }
  ],
  "windows": [
    { "kind": "weekly" }
  ]
}
```

`Signal.when` is either one leaf or exactly one `all`/`any` array. Nesting groups
one level deep is sufficient for the four drivers and is the v1 validation
limit.

A leaf contains `paths` and exactly one operator:

- `equals`: one JSON scalar;
- `oneOf`: a non-empty array of same-typed JSON scalars;
- `containsAny`: non-empty strings, compared case-insensitively against a
  declared string field only.

`containsAny` never examines serialized JSON, an entire event line, a number, an
object, or an array. Numeric strings such as `"4021"` never equal numeric `402`.

### 5.2 Path syntax

Paths are dot-separated object keys relative to the parsed event root:

```text
type
error.type
error.retry_after_seconds
```

No `$`, array indexing, wildcard, escaping, recursive descent, or implicit
search is supported. Every segment must be non-empty. A missing segment, a
non-object intermediate value, or an incompatible terminal type makes that path
unresolved.

For `paths`, paths are tried in declared order. A matcher succeeds on the first
resolved value of the required type that satisfies its operator. A resolver
uses the first value that parses successfully.

### 5.3 Value typing

- `equals` and `oneOf` use strict JSON scalar types. Boolean `true`, number `1`,
  and string `"1"` are distinct.
- Numeric equality compares finite JSON numbers by value; it does not truncate.
- `retryAfter.format: "seconds"` accepts a non-negative integral JSON number or
  a base-10 non-negative integer string, preserving current retry-field
  compatibility. Fractions, negatives, overflow, booleans, and other strings
  resolve to nil.
- `resetAt.format: "iso8601"` accepts only an ISO-8601 string parseable by the
  existing formatter.
- `snippet.paths` accepts the first string value, then applies
  `CapacityObservationSanitizer`. If none resolves, the snippet is the matched
  leaf's scalar rendered as text. It never falls back to the raw event line.

`retryAfter` and `resetAt` may both resolve. `resetAt` is the observed reset
instant; `retryAfterSeconds` retains the provided duration. Existing
`makeObservation` behavior derives `wakeAfter` only from those vendor values.

### 5.4 Evaluation order

1. Select exactly one manifest by exact `input.sourceId`.
2. Examine stderr records in byte order, then stdout records in byte order.
3. In each channel, parse each non-empty line that is a JSON object. If no line
   is a JSON object and the whole channel is one JSON object, evaluate it once.
4. Evaluate that driver's `signals` in manifest order.
5. The first matching signal in the first matching record wins.
6. Resolver failure does not cancel a matched signal; optional output fields are
   nil.
7. No block or no match returns no manifest capacity observation.

Manifest order is therefore observable and must be fixture-tested. Validation
cannot prove predicates non-overlapping.

### 5.5 Windows

`windows` is descriptive vendor metadata only in this packet. Each entry
contains one non-empty `kind`. It does not manufacture reset times, retry
durations, schedules, or wake times.

Populate only documented facts:

- Qwen: `weekly`;
- Claude: its documented five-hour window;
- Codex and Grok: absent unless documented evidence exists.

A window without a matching signal still emits no observation. No Allnighter
runtime consumes `windows` in VSI-S04.

## 6. Expressiveness audit

### 6.1 Claude (`claude_code`)

Current structured detections:

- `error.type` or root `type` equals `rate_limit_error`;
- `error.type` or root `type` equals `overloaded_error`.

These are expressible as duplicated signals or `paths` plus `equals`.

The original proposal could not express:

- alternate root/error envelopes without duplicating whole signals;
- the four retry keys and their Int/Double/numeric-string compatibility;
- `retry after N` and `wait N seconds` extraction from `message`;
- `observedResetAt`;
- ordered snippet selection and fallback;
- the hardcoded 60-second overload delay.

The extended schema expresses the structured fields. The existing
`retryAfterSeconds(fromMessage:)` regex remains a named, source-scoped Claude
resolver exception until a real Claude fixture proves it is required. It may
populate retry only after the manifest's exact Claude type predicate matched.
The 60-second overload default is intentionally not expressible and is deleted.

`classifyClaudeSessionLimit` remains a named source-scoped textual exception
because its date-less local-time parsing is behavior, not JSON field matching.
It must run only for `sourceId == "claude_code"` and retain
`messageFallback` confidence.

### 6.2 Codex (`codex`)

Current detection requires:

```text
type is "error" or "turn.failed"
AND
(
  message contains "usage" AND one of "limit", "reached", "cap"
  OR message contains "spend cap"
  OR message contains "credits"
)
```

Message resolution checks `message`, string `error`, `error.message`, then
`error.code`. Reset resolution checks root `resetsAt`, nested
`error.resetsAt`, and the four retry keys.

The original proposal could express the type equality but none of the compound
message predicate, alternate message paths, reset timestamp, retry coalescing,
or snippet selection. `all`, `any`, `paths`, `oneOf`, `containsAny`,
`resetAt`, and `snippet` make the behavior declarative. The exact compound
predicate must be preserved; broadening it to any single `"usage"` or `"cap"`
match fails the equivalence gate.

### 6.3 Grok (`grok`)

Current structured detection accepts:

- numeric 402 at `http_status`, `status`, or `code`;
- any payment pattern in the resolved message;
- any payment pattern, including bare `"402"`, anywhere in the raw event line.

The three numeric fields are expressible through `paths` plus numeric
`equals: 402`. The original proposal could not express scoped payment text,
alternate message paths, snippet selection, or the default 3,600 seconds.

`containsAny` expresses the four textual phrases on declared message fields.
Bare `"402"` is not a text predicate; numeric 402 is field equality only.
Raw-line matching and the 3,600-second default are intentionally deleted.

### 6.4 Qwen (`qwen`)

Qwen has no dedicated hardcoded JSON parser. Today it can be misclassified by
all three foreign parsers and by the unscoped generic retry, payment, capacity,
and overload fallbacks.

Its initial block is therefore:

```json
"capacity": {
  "signals": [],
  "windows": [
    { "kind": "weekly" }
  ]
}
```

An empty signal list is valid. It records known window metadata but emits no
capacity observation until a real Qwen machine-readable signal is captured and
declared. Qwen must not inherit Claude, Codex, Grok, or global text rules.

### 6.5 Residual code exceptions

After VSI-S04, these may remain code, always source-dispatched:

- Claude date-less session-limit parsing:
  `classifyClaudeSessionLimit`;
- Claude message-duration extraction, only after an exact manifest type match;
- AGY cooldown/SSE behavior: `classifyAGYCooldown`;
- stderr-only auth/manual blockers, outside this capacity schema.

The deleted surface is `classifyClaudeJSON`, `classifyCodexJSON`,
`classifyGrokJSON`, whole-line payment matching, and unscoped generic capacity
fallback. The packet must not claim “all signals are manifest data” while these
named residuals exist.

## 7. Persisted and public contracts

`CapacityObservation` is Codable inside AgentOS `WorkerRunResult`. Allnighter
persists it in attempts and vendor blockers. `TeamRunJSONMapper` projects it at:

- `teamRun.blocker.capacityObservation`;
- `teamRun.attempts[].capacityObservation`.

VSI-S01/S02/S04 change whether future optional observations exist; they do not
remove or rename fields. `TeamRunJSON.schemaVersion` remains `2`, and historical
journal observations remain decodable. Contract tests must prove both present
and absent values decode.

Historical observations are not automatically trustworthy merely because they
decode. In particular, the current Qwen park already contains the fabricated
wake and remains visible until VSI-S03 explicitly repairs or preserves it under
the §10.1 ruling. Future-classifier correctness alone does not fix persisted
lies.

VSI-S05 changes the semantics of an already-optional `answer`: failed,
interrupted, cancelled, timed-out, or parked single-worker runs may now carry an
answer whose `status` is that terminal/non-success status and whose markdown is
the durable partial. It does not add a new status or JSON field. Consumers that
assumed `answer != null` implies `status == done` need a regression test.

## 8. Slices and gates

### VSI-S01/S02 — Source isolation hotfix

Land these identifiers as one AgentOS change.

Change:

- `Sources/AgentOSCLI/CapacityClassifier.swift`
  - `CapacityClassifier.classify`
  - `classifyStructured`
  - `classifyGrokJSON`
  - `classifyMessageFallback`
  - `paymentPatterns`
- `Tests/AgentOSCLITests/CapacityClassifierTests.swift`

Required behavior:

- structured dispatch is selected by exact `Input.sourceId`;
- unknown/Qwen sources cannot run Claude, Codex, or Grok structured parsers;
- Grok numeric status uses integer field equality;
- payment text examines resolved message fields only;
- generic capacity/payment/overload fallback does not answer for undeclared
  sources;
- auth `"401"` and capacity `"402"` are not bare numeric substrings.

Gate symbols to add:

- `testQwenCannotUseGrokStructuredParser`
- `testUnknownSourceHasNoCapacityFallback`
- `testGrokNumeric402FieldMatches`
- `testGrokDuration4021DoesNotMatch`
- `testAuthNumericSubstringDoesNotMatch`

Mutation gates:

- restoring sequential parser calls makes the Qwen test fail;
- restoring raw-line `"402"` matching makes the duration test fail;
- restoring global capacity fallback makes the unknown-source test fail.

### VSI-S03 — No invented backoff and persisted-park disposition

AgentOS changes:

- `Sources/AgentOSCLI/CapacityClassifier.swift`
  - `providerBusyBackoffSeconds`
  - `unknownBackoffSeconds`
  - `classifyClaudeJSON`
  - `classifyGrokJSON`
  - `classifyMessageFallback`
  - `makeObservation`
- `Tests/AgentOSCLITests/CapacityClassifierTests.swift`

Allnighter symbols that must be audited after §10.1 is answered:

- `Packages/AllnighterCore/Sources/AllnighterCore/VendorBackoffPolicy.swift`
  - `shouldPark`
  - `computeWakeAfter`
  - `unknownResetWakeAfter`
- `Packages/AllnighterCore/Sources/AllnighterEngine/VendorBackoffReconciler.swift`
  - `VendorBackoffWakePlanner.plan`
  - `VendorBackoffReconciler.reconcileDueOnce`
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunStore.swift`
  - `claimVendorWake`
  - `reconcileRunDetailed`
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/VendorBackoffReconcilerTests.swift`

Gate symbols:

- AgentOS `testStructuredLimitWithoutResetHasNilRetryAndWake`
- AgentOS `testOverloadWithoutVendorRetryHasNilRetryAndWake`
- Allnighter `testNilVendorResetDoesNotDisplayAsVendorWake`
- Allnighter `testPersistedFabricatedQwenParkFollowsFounderDisposition`

Mutation gates:

- restoring either default constant fails the nil test;
- restoring `blocker.wakeAfter ?? unknownResetWakeAfter(...)` as displayed vendor
  truth fails the display test;
- leaving the recorded Qwen fixture in `waitingForVendor` after the chosen
  migration fails the persisted-park test.

Closeout gate:

```text
scripts/swift-test.sh --filter VendorBackoffReconcilerTests
```

VSI-S03 must not close while `alln ps` still reports the known fabricated Qwen
wake. It cannot implement the persisted-state transition until §10.1 is ruled.

### VSI-S04 — Manifest-declared capacity

AgentOS changes:

- `Sources/AgentOSCLI/DriverManifest.swift`
  - add `DriverManifest.capacity` and its nested Codable types;
- `Sources/AgentOSCLI/DriverManifestValidation.swift`
  - extend `DriverManifest.validate()`;
- `Sources/AgentOSCLI/CapacityClassifier.swift`
  - manifest evaluator in `classifyStructured`;
  - delete the three vendor JSON parser functions after equivalence;
- `Sources/AgentOSCLI/Catalog/catalog.json`
  - add blocks for `claude_code`, `codex`, `grok`, and `qwen`;
- `Tests/AgentOSCLITests/DriverManifestValidationTests.swift`;
- `Tests/AgentOSCLITests/CapacityClassifierTests.swift`;
- `Tests/AgentOSCLITests/CatalogLoaderTests.swift`.

Gate symbols:

- `testCapacityBlockIsOptional`
- `testCapacityValidationRejectsMalformedPredicate`
- `testCapacityValidationRejectsMalformedPathAndResolver`
- `testCapacityEvaluationIsManifestOrdered`
- `testCapacityEvaluationUsesStderrThenStdout`
- `testBundledCapacityBlocksDecode`
- `testClaudeManifestFixtureEquivalence`
- `testCodexManifestFixtureEquivalence`
- `testGrokManifestFixtureEquivalence`
- `testQwenManifestEmitsNothing`

The equivalence assertions encode `CapacityObservation` and compare bytes after
applying only §4.3's explicit deletion allowlist. Deleting any manifest signal
or changing order makes a fixture test fail. Adding fallback inheritance makes
the Qwen test fail.

### VSI-S05 — Partial-answer durability

Allnighter changes:

- `Packages/AllnighterCore/Sources/AllnighterEngine/RunService.swift`
  - `RunService.runExecution`: each coalesced answer flush updates the durable
    running `TeamAnswer.result.output`, not only the event journal;
- `Packages/AllnighterCore/Sources/AllnighterEngine/RunStore.swift`
  - add one locked, terminal-safe partial-answer update boundary; it re-reads
    `run.json`, updates only the named worker's output/activity, and cannot
    resurrect a terminal run;
- `Packages/AllnighterCore/Sources/AllnighterCore/TeamRunJSONMapper.swift`
  - `deriveAnswer`: hoist a non-empty single-worker partial even when run status
    is not `done`, using the existing mapped status and clearing duplicate seat
    markdown;
- `Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift`
  - `humanAnswer` and `runExport`: return the durable partial and label markdown
    output `Partial answer`;
- `Packages/AllnighterCore/Sources/AllnighterCore/ArtifactProjector.swift`
  - `project`: render the hoisted partial without presenting a ready verdict;
- corresponding `RunServiceTests`, `TeamRunJSONMapperTests`, CLI export tests,
  and `ArtifactProjectorTests`.

Required persistence order:

1. append parsed answer delta in memory;
2. on the existing coalescing boundary, atomically persist the accumulated
   visible text;
3. emit the stream delta;
4. terminal settlement may change status but must not erase non-empty output.

Gate symbols:

- `RunServiceTests.testKillAfterDeltaPreservesDurablePartial`
- `RunServiceTests.testLatePartialFlushCannotResurrectTerminalRun`
- `TeamRunJSONMapperTests.testFailedSingleWorkerHoistsPartialWithFailedStatus`
- `TeamRunJSONMapperTests.testPartialMarkdownAppearsExactlyOnce`
- CLI `testExportLabelsAndReturnsPartialAnswer`
- `ArtifactProjectorTests.testFailedRunRendersPartialWithoutReadyVerdict`

Closeout gates:

```text
scripts/swift-test.sh --filter RunServiceTests
scripts/swift-test.sh --filter TeamRunJSONMapperTests
scripts/swift-test.sh --filter ArtifactProjectorTests
```

Mutation gates:

- removing the mid-stream journal update loses the partial after kill;
- allowing a late flush to overwrite terminal state resurrects the run;
- restoring `deriveAnswer`'s `runStatus == .done` guard makes JSON answer null;
- restoring success-only export loses or mislabels the partial.

## 9. Inference bans

| Junction | Ban |
| --- | --- |
| Parser can parse output → parser owns it | Exact `sourceId` dispatch first |
| Branch says `structured` → fact is structured | Confidence derives from declared field matching |
| Unknown failure → probably capacity | No declared owned signal means no observation |
| Need a wake time → choose a cadence | Vendor observation fields remain nil unless supplied |
| Window metadata exists → reset is known | `windows` never creates a wake |
| Fewer observations → regression | Compare owned fixtures and the explicit deletion allowlist |
| Qwen incident → Qwen-specific parser fix | Qwen was the victim; ownership was defective |
| Classified observation persisted → permanently true | Historical values retain provenance defects |
| Stream watcher saw text → journal has text | VSI-S05 must persist text before terminal settlement |

## 10. Open questions and reviewer dissent

### 10.1 Founder stop: existing fabricated parks

There is already a killed run displaying:

```text
Waiting for Qwen — resumes around 12:43 PM
```

The stored observation lacks enough provenance to safely distinguish every
historical invented wake from a legitimate vendor-supplied 3,600-second retry.
A blanket rewrite would silently alter persisted run history. Leaving it alone
ships a known lie. This packet cannot choose the terminal state on the founder's
behalf.

Founder ruling required before VSI-S03:

1. repair only the known incident signature/run and preserve all other history;
   or
2. migrate every parked observation matching an approved legacy-signature
   predicate; or
3. preserve historical observations but clear their active blockers and choose
   the resulting run status/end reason.

Whichever ruling lands must be encoded in
`testPersistedFabricatedQwenParkFollowsFounderDisposition`. No new CLI is needed.

### 10.2 Local recheck cadence versus explicit-only retry

`VendorBackoffPolicy.unknownResetWakeAfter` deliberately implements a local
cadence for structured account limits without reset truth.
`VendorBackoffWakePlanner.plan` and `RunStore.claimVendorWake` fall back to it.

The earlier draft recommended “next explicit request only.” That is a
quota-spend and continuity policy change, not a mechanical consequence of
removing fabricated observation fields. It must not be silently bundled into
VSI-S03. The founder must confirm whether local rechecks remain allowed and, if
so, how the UI distinguishes a local recheck from a vendor-stated reset.

### 10.3 Fixture capture

“Capture real vendor error output before touching the classifier” is not
currently achievable for the historical incident because raw worker stdout and
stderr were not retained. Intentionally provoking four vendor failures can
spend quota and still may not reproduce the desired state.

Therefore:

- existing sanitized tests are the S01/S02 baseline;
- author-supplied sanitized real captures may be added when available;
- a new live capture requires explicit quota approval;
- durable raw-output capture is out of scope and requires a separate privacy
  decision.

This limitation must be stated in closeout; it must not be disguised as a
completed real-driver fixture gate.

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| Wrong/invented capacity verdict | This packet §2–§6; AgentOS `CapacityClassifier` |
| Adding a CLI capacity signal | §5; declare it in that driver's manifest |
| Nil reset or stale vendor park | §7, VSI-S03, and §10.1–§10.2 |
| Failed/killed work missing from show/export | VSI-S05 |
| AgentOS behavior deletion | §4 equivalence and deletion allowlist |
| Raw vendor fixture capture | §4.2 and §10.3; do not assume journals retain it |
