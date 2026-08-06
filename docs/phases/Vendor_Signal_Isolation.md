# Vendor Signal Isolation

Status: **Open — VSI-S01/S02 implementation-ready; S03–S05 designed.**
Priority: **Above `Agent_Teaching_Surface.md`.** That packet's DEL slices teach
agents to delegate; this one stops the bench lying about why delegation failed.
Teaching a caller to trust a surface that misreports vendor state is worse than
not teaching it at all. Land VSI-S01/S02 first.

Owner: unassigned — **primarily AgentOS** (`Sources/AgentOSCLI/CapacityClassifier.swift`,
`DriverManifest.swift`), with one Allnighter slice (VSI-S05).
Created: 2026-08-06
Origin: A 25-minute Qwen 3.8 Max run was reported as `capacity: accountRateLimit`
with a fabricated one-hour wake time. **Qwen has no hourly window — weekly
only** (founder, 2026-08-06). The run had produced 26,418 characters of correct
work; `alln export` returned the prompt and nothing else. Both the diagnosis and
the loss were false.

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

> **AgentOS is a shared package with consumers beyond Allnighter.** Every slice
> here is a change to somebody else's runtime. §4 sets the bar that follows from
> that; no slice closes without meeting it.

---

## 1. Founder intake

Intake per `docs/workflows/SSOT_Founder_Input_Workflow.md`.

- **Intent.** Stop one vendor's parser from answering for another vendor, stop
  the bench inventing numbers it did not observe, and stop losing completed work
  when a run terminates badly.
- **Value.** A misclassified capacity signal does not merely mislabel — it parks
  a healthy run and makes it eligible for substitution to a different vendor,
  while reporting `confidence: structured`. Wrong, expensive, and confident.
- **Trusted workflow.** `alln run --model <seat>` → seat works → seat finishes
  or fails → the reported reason is true and the produced work is retrievable.
- **Current state.** §2. One incident, fully evidenced; the code defect is
  certain from reading it.
- **Truth owners.** AgentOS `CapacityClassifier.swift`, `CapacityObservation.swift`,
  `DriverManifest.swift`, `Catalog/catalog.json`; Allnighter
  `VendorBackoffPolicy.swift`, `SeatReseat.swift`, `TeamRunJSONMapper.swift`.
- **CLI surface.** No new commands. `alln show` / `alln export` gain truthful
  content (VSI-S05); `alln doctor explain` keeps working on the same codes.
- **Risk class.** Touches quota-spend behaviour and vendor selection — a
  High-Risk Stop under `AGENTS.md`. It also removes machinery, which is why §4
  demands equivalence proof before deletion.
- **Next slice.** VSI-S01.

## 2. What happened

Recorded observation from run `A6A06D63`, verbatim:

```json
{ "kind": "accountRateLimit", "source": "qwen", "sourceConfidence": "structured",
  "rawSnippet": "turn.failed", "retryAfterSeconds": 3600,
  "observedAt": "2026-08-06T18:36:52Z", "wakeAfter": "2026-08-06T19:36:52Z" }
```

Three independent signatures identify the branch that produced it:

| Recorded value | Only source in code |
| --- | --- |
| `rawSnippet: "turn.failed"` | `codexMessage()` default return, `CapacityClassifier.swift:151` |
| `retryAfterSeconds: 3600` | `unknownBackoffSeconds`, used in this shape only at `:138` |
| `sourceConfidence: "structured"` | set at `:136` |

All three belong to **`classifyGrokJSON`'s payment branch**. The Claude branch
requires `type: rate_limit_error`; the Codex branch derives retry from
`resetsAt`, never a flat constant. **Grok's parser answered for a Qwen run.**

The branch:

```swift
let lower = (message + " " + line).lowercased()   // `line` = the ENTIRE raw JSON event
if status == 402 || matchesAny(lower, patterns: paymentPatterns) { → .accountRateLimit }

private static let paymentPatterns = ["402", "payment required", ...]
private static func matchesAny(_ t: String, patterns: [String]) -> Bool {
    patterns.contains { t.contains($0) }          // bare substring
}
```

The literal `"402"` is substring-matched against whole raw event lines. A token
count, duration in milliseconds, byte offset, line number, or id fragment
containing those three digits classifies as a billing failure.

**Proven vs inferred.** The code defect is certain — read directly. The exact
trigger (`status == 402` versus a `"402"` substring) is **inference**: raw worker
stdout is not retained, only the classified observation. VSI-S01's fixture work
settles it, and retaining the deciding input is itself part of the fix.

**Second failure, arguably worse.** After termination:

```text
alln export A6A06D63 --format md   →  2,657 chars  (the prompt, echoed back)
answer present in the run journal  →  26,418 chars
```

The completed work was recoverable only because a `--stream` watcher happened to
be attached and flushed its buffer on kill. `alln show --json` reported
`answer: null`. No supported command surfaces it.

## 3. The defect, from first principles

### 3.1 The shape is O(n²), and every new CLI makes it worse

`classify` runs every vendor parser against every vendor's output, in sequence:

```swift
if let obs = classifyClaudeJSON(...) { return obs }
if let obs = classifyCodexJSON(...)  { return obs }
if let obs = classifyGrokJSON(...)   { return obs }
```

With *n* vendors that is *n* parsers × *n* output formats. Adding the eighth CLI
does not add a module; it adds a new victim of the other seven. First-pattern-wins
also means the failure is order-dependent and silent.

**The fix is an ignored field, not a missing capability.** `Input` already
carries what is needed:

```swift
public struct Input: Sendable {
    public var workerId: String
    public var sourceId: String      // CapacityClassifier.swift:7 — never consulted
```

Dispatching on `sourceId` collapses n² to n. That alone ends this class of
incident.

### 3.2 The right design already ships, one file away

Qwen's own manifest block declares its auth signals as **data, owned by that
vendor**:

```json
"loginFlow": { "authErrorPatterns": ["api key", "not authenticated", "401", …] }
```

Auth detection: manifest-declared, per-driver, scoped. Capacity detection:
hardcoded Swift, global, unscoped. Same problem class, opposite designs, same
package. `DriverManifest.swift` contains **zero** occurrences of `capacity`.

This is the whole argument for §5. We are not inventing an architecture; we are
applying the one already in use to the one signal that was left out.

### 3.3 Confidence is asserted by the branch, not earned by the mechanism

`CapacityObservation.swift:14` documents the enum as:

> *"How the observation was derived — not provider quota truth."*

A bare-substring match returning `.structured` violates that on its face.
Confidence must be a function of **how** the fact was obtained: a value read at
a declared path is structured; anything inferred from free text is not. Today a
branch simply declares its own trustworthiness, and downstream believes it.

### 3.4 The error costs are wildly asymmetric, and the code is biased the wrong way

| | Cost |
| --- | --- |
| **False negative** (missed real limit) | One run fails and says so. Owner retries. Loud, honest, cheap. |
| **False positive** (invented limit) | Healthy run parked; eligible for reseat to another vendor; a fabricated wake time; reported as `structured`. Silent and confidently wrong. |

A classifier facing this asymmetry must be biased toward **silence**. Today it is
biased toward guessing: unknown vendors fall through to text heuristics rather
than returning nothing. Under Allnighter's standing law that sensors *inform,
never block*, an unclassified failure is fully safe — it surfaces as a plain
failure. **Silence is the correct default, and it is currently unreachable.**

### 3.5 The invented number violates the field's own contract

`unknownBackoffSeconds = 3_600` populates a field documented at
`CapacityObservation.swift:28` as:

> *"Present only when the CLI/API provided a reset time or duration."*

`retryAfterSeconds` is already `Int?`. Nil is representable and correct. The
constant converts "we do not know" into "one hour" — a projection presented as an
observation, which is precisely the no-estimates law
(`Scarcity_Aware_Routing.md` §3.4). For Qwen it is doubly wrong: the vendor's
only window is weekly, so both the number and its unit are fiction.

### 3.6 The cross-cutting root cause

`TeachingSnippet.swift:24` states *"Protocol only — never embed … command rows"*
and is violated seven times. `CapacityObservation.swift:14` and `:28` state the
confidence and reset-time laws and are violated by the classifier that fills
them. **This codebase writes the correct invariant in a comment and does not gate
it.** Both packets are instances of that pattern; both fixes are "make the
already-written rule executable." Nothing here is a new policy.

## 4. What "extremely well" requires of a shared package

AgentOS has consumers beyond Allnighter. Three of these slices *delete* behaviour.
The bar:

1. **Capture before change.** Record real vendor error output as fixtures for
   Claude, Codex, Grok and Qwen *before* touching the classifier. Without them
   there is no equivalence baseline and no way to settle §2's open inference.
2. **Equivalence before deletion.** Porting a hardcoded parser to a manifest must
   produce a byte-identical `CapacityObservation` on every recorded fixture.
   Prove first, delete second — never the reverse.
3. **Additive schema only.** `capacity` is an optional manifest block.
   `manifestVersion` stays `1`; a driver without the block is valid and simply
   emits no capacity observation. No consumer is forced to migrate.
4. **Behaviour change is one-directional and stated.** After VSI-S01/S02 the
   classifier emits *strictly fewer* observations. A consumer depending on a
   removed one was depending on a cross-vendor false positive; say so in the
   AgentOS changelog rather than preserving it.
5. **Validated at the boundary.** New manifest fields are checked by the existing
   `DriverManifestValidation.validate()`, so a malformed block fails at load for
   every consumer, not at classification time for one.

## 5. The design — capacity as declared data

A driver declares its own capacity signals in its manifest block, beside
`loginFlow`:

```json
"capacity": {
  "signals": [
    { "when":  { "path": "error.type", "equals": "rate_limit_error" },
      "kind":  "accountRateLimit",
      "retryAfter": { "path": "error.retry_after_seconds" } },
    { "when":  { "path": "http_status", "equals": 402 },
      "kind":  "accountRateLimit" }
  ],
  "windows": [ { "kind": "weekly" } ]
}
```

Four rules, and they are the whole design:

1. **Path-and-value matching only.** A signal names a JSON path and an expected
   value. No substring matching, ever, and never against a raw line.
2. **No block, no observation.** A driver that declares nothing emits nothing.
   Silence, not inheritance from a neighbour.
3. **Numbers come from the vendor or not at all.** `retryAfter` resolves from a
   declared path; absent path means `retryAfterSeconds = nil`, `wakeAfter = nil`.
   No constants.
4. **Confidence derives from mechanism.** Path-matched → `structured`. Nothing
   else may claim it.

**What this deletes:** `classifyClaudeJSON`, `classifyCodexJSON`,
`classifyGrokJSON`, `paymentPatterns`, and the entire `message + " " + line`
substring surface — replaced by four manifest blocks.

**What it makes cheap:** adding CLI #8 is one manifest block, zero Swift, and it
cannot be misclassified by CLIs #1–7. `windows` also gives per-vendor limit
semantics (Qwen weekly, Claude 5h) a home, replacing one shared constant that is
wrong for everybody.

## 6. Slices

**VSI-S01 — Ownership dispatch.** `classify` selects the parser by
`input.sourceId`; a vendor parser runs only for its own source. Unknown sources
reach the text fallback only, never `.structured`. Small, self-contained, ends
the incident class today. *(AgentOS.)*

**VSI-S02 — Kill substring status matching.** `"402"` (and `"401"` in
`loginFlow.authErrorPatterns`) become field comparisons, never substrings.
Pattern matching runs against `message`, never `message + " " + line`. *(AgentOS.)*

**VSI-S03 — No invented backoff.** Remove `unknownBackoffSeconds` as a default.
`retryAfterSeconds` / `wakeAfter` are nil unless the vendor said. Allnighter's
park path must treat nil as "recheck on the next explicit request" — never a
scheduled wake, never a block. *(AgentOS + Allnighter; see §9 Q1.)*

**VSI-S04 — Manifest-declared capacity signals.** Add the optional `capacity`
block, port all four drivers, prove fixture equivalence per §4.2, then delete the
hardcoded branches. *(AgentOS.)*

**VSI-S05 — Partial-answer durability.** A run's accumulated answer must be
durable at the moment it is produced, not at the moment the run succeeds.
`alln show` / `alln export` must return it for failed, killed, and parked runs,
clearly labelled partial. *(Allnighter.)* Independent of S01–S04 and parallelisable.

Order rationale: S01 and S02 are hours of work and stop the bleeding. S04 is the
scalable end state and needs S01's fixtures. S05 is orthogonal and arguably the
highest user-visible value — 26KB of correct work was one buffer flush from gone.

## 7. Proof scenarios

| Slice | Gate | Mutation that must turn it red |
| --- | --- | --- |
| VSI-S01 | Grok fixture fed with `sourceId: "qwen"` classifies as nothing | Restore sequential all-parser dispatch |
| VSI-S02 | Benign event containing `"402"` (e.g. `durationMs: 4021`) classifies as nothing | Re-add `"402"` to a substring list |
| VSI-S03 | Vendor output with no reset info → `retryAfterSeconds == nil` | Re-introduce a default constant |
| VSI-S04 | Each recorded fixture yields a byte-identical observation before/after the port | Change any ported field; drop a manifest signal |
| VSI-S04 | A driver with no `capacity` block emits no observation | Add an inheritance fallback |
| VSI-S05 | Kill a run mid-answer; `alln export` returns the partial text | Revert to answer-on-success-only |

Per `docs/operations/Spec_Review.md` §3, a check that cannot be made to fail is
decoration. Every row above is a mutation, not an assertion of current behaviour.

## 8. Inference bans

| Junction | Bad inference | Ban |
| --- | --- | --- |
| Parser matched → vendor emitted it | A parser is presumed to own any output it can parse | A parser answers only for its own `sourceId` (§3.1) |
| `sourceConfidence: structured` → the fact is reliable | Branch-asserted trust | Confidence describes derivation mechanism only (§3.3) |
| Unknown failure → probably capacity | Guessing beats silence | No declared signal → no observation; a plain failure is safe (§3.4) |
| Need a wake time → pick a plausible one | Projection recorded as observation | Nil unless the vendor said (§3.5) |
| Fewer observations after the fix → regression | Removed false positives read as lost coverage | Equivalence is proven on fixtures, not on incident counts (§4.2) |
| Qwen was the culprit → Qwen-specific fix | Vendor blamed for a shared-classifier defect | The defect is ownership; Qwen was the victim |
| Manifest can express it → move everything to manifest | Data-driven taken past its use | Genuine per-vendor *behaviour* (OpenCode SSE) stays code; *signals* become data |

## 9. Open questions

1. **What does the park path do with a nil wake time?** VSI-S03 removes the
   fabricated hour, and `VendorBackoffReconciler` currently schedules from it.
   **Recommendation:** nil means no scheduled wake — the run parks and is
   rechecked on the next explicit request. This matches the standing law that
   sensors inform and never block, and it fails loudly rather than sleeping on a
   guess. Needs confirming against `VendorBackoffReconciler` before S03 lands.
2. **Do other AgentOS consumers depend on the current parsers?** Unknown from
   this repo. **Recommendation:** treat §4.2 fixture equivalence as the contract
   — if behaviour is identical on recorded vendor output, no consumer can
   observe the refactor, and the only removed behaviour is cross-vendor false
   positives, which are stated as a fix in the changelog.
3. **Should `windows` land in S04 or wait?** It is the natural home for
   per-vendor limit semantics but is not needed to fix this incident.
   **Recommendation:** ship the field in S04, populate it only where the vendor's
   window is documented, and leave it absent otherwise — absent beats guessed.

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| Wrong/invented capacity or rate-limit verdict; a run parked for a limit that did not happen | This packet §2–§3; code SSOT AgentOS `CapacityClassifier.swift` |
| Adding a new CLI's capacity/limit detection | §5 — declare it in the driver manifest; never add a vendor branch to the classifier |
| A failed or killed run's work is missing from `alln show` / `alln export` | §6 VSI-S05 |
| Changing AgentOS behaviour that other consumers rely on | §4 — capture fixtures, prove equivalence, delete second |
