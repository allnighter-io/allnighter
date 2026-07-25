# Model Catalog & Team Schema — Quick Fixes (Reviewed)

Status: **Backlog — reviewed and hardened, still not authorized to implement.**
Queued behind `Sandbox_Handoff_Hotfix.md` (the current active work) — do not
start until that packet closes.
Owner: AllnighterCore (`ModelCatalog.swift`, `TeamCatalog.swift`) +
AgentOS (`BundledDefaults.swift`) — cross-repo, MCV-S04b additionally touches
XTerminal.
Updated: 2026-07-25 (v2 — cross-reviewed, integrated first-principles; see
"What changed in this revision" below).
Companion: XTerminal `docs/phases/Your_AI_Model_Picker.md` §5 (the founder
ruling MCV-S04b tracks — do not restate or fork that decision here, only cite it).

## Origin

Founder asked for a throwaway 3-worker "TEST" team (Haiku / Cursor Composer
2.5 / Antigravity Gemini, min effort, staggered response timing) to sanity-test
the run pipe before running anything. Building it by hand surfaced five
findings in the CLI's model/team surface. v1 of this doc treated all five as
"real gaps, all worth fixing." That framing was wrong — see below.

None of the items below are authorized. This is the list, not a plan.

## What changed in this revision (v1 → v2)

v1 was reviewed adversarially by two independent models — Opus 5 and Gemini
3.6 Flash — each asked the same question: for each finding, is it durable and
broad, or an artifact of one session? Is the proposed fix the simplest robust
one, or the wrong layer? Both reviews are **advisory input, not orders** —
integrated here selectively, with two of their claims spot-checked directly
against source rather than taken on faith (see "Review method" at the bottom).
Net result:

- **MCV-S00** — kept, with two preconditions added (link to S04b; smoke-test
  the label before landing it).
- **MCV-S01** — downgraded from "schema change candidate" to **effectively
  resolved, no code change needed** — verified directly against source that
  the capability it asks for already exists.
- **MCV-S02** — **rejected outright**, moved to the ledger. Both reviewers and
  a direct check against this repo's execution-lane invariants agree the
  proposed fix is actively a bad idea, not just low-priority.
- **MCV-S03** — kept as the highest-value item, but the proposed fix changed:
  the reviewers' DTO-shape-swap idea was set aside after finding a
  founder-adjacent ruling on the record that names the exact call sequence
  "deliberate." A safer, additive fix is recommended instead.
- **MCV-S04** — split into **S04a** (new: a small, local, Allnighter-only
  disclosure fix both reviewers proposed independently) and **S04b** (the
  original cross-repo item, unchanged, still deferred behind XTerminal).

## Priority order (once authorized)

1. **MCV-S03** — teach the follow-up call on `teams duplicate`. Highest
   confidence, lowest risk, broadest value.
2. **MCV-S00** — two-repo Haiku patch. Still gated on founder go-ahead.
3. **MCV-S04a** — stamp hand-typed models as unverified.
4. **MCV-S01** — no code action; optional documentation note only.
5. **MCV-S02** — rejected, do not implement.
6. **MCV-S04b** — deferred behind XTerminal's `YM7` seal, unchanged.

## MCV-S00 — Haiku missing from the `claude_code` catalog, in both repos

**Files:**
- `Packages/AllnighterCore/Sources/AllnighterCore/ModelCatalog.swift:185-187` —
  `ModelCatalog.builtIns` lists only `model_fable`, `model_opus`, `model_sonnet`
  for driver `claude_code`.
- Same file, `modelFamily(_:)` switch at line 53, and the `builtInCapabilities`
  dict starting line 76 — both would need a `model_haiku` entry alongside the
  new `def(...)` line.
- `AgentOS` — `Sources/AgentOSCLI/BundledDefaults.swift`, `claudeModels`
  (~lines 158-182) — an independently-maintained copy of the same three-model
  list. Parity requires editing both repos.

**Before implementing (both reviewers flagged this, independently):**
1. **Smoke-test the exact wire label** (`claude-haiku-4-5-20251001`) against
   the real `claude_code` driver CLI before landing it anywhere. It was typed
   from memory this session and has never been confirmed against the actual
   vendor CLI — the same unverified-label problem MCV-S04 exists to fix, about
   to be baked into two repos by this very item if skipped.
2. **Rule out deliberate exclusion.** No evidence was found either way that
   Haiku's absence was intentional (e.g. a minimum-capability bar for seat
   eligibility). If an implementer finds it was deliberate, close this item
   instead of implementing it.

**Why not the deeper fix:** the durable defect underneath this instance is
that adding one model touches three parallel structures in one file plus an
independently-maintained copy in a second repo, with no gate holding them in
sync. A single-source-of-truth refactor + cross-repo parity test would fix the
mechanism, not just the instance — but that consolidation **is** the AgentOS
catalog work already deliberately deferred behind XTerminal's `YM7` seal (see
S04b: "AgentOS answers what exists and what works"). Building a parity gate
for one model addition now is scope creep on a single data patch. If a third
model triggers the same drift, that recurrence is the trigger to revisit this
— not this one.

**Effort:** trivial in each repo (a few lines), but two repos, not one, plus
the smoke-test precondition above.

**Status:** founder said "add in both, but not yet — still brainstorming."
No action until explicitly approved.

## MCV-S01 — raw per-worker answers already exist; no schema change needed

**Original claim (v1):** `lead` is mandatory on every team, so there's no way
to build a true N-worker team that returns raw answers without paying for
synthesis.

**Verified false as stated.** `TeamRunJSONMapper.swift:58` and `:175` show
every `TeamRunJSON` already carries `workerAnswers`: one raw, unsynthesized
markdown entry per crew worker, independent of whatever the lead's `answer`
field contains. This was confirmed directly against a real run's JSON in this
session (`workerAnswers` populated with each crew member's own text, separate
from the lead's synthesis) — it is true for every team today, not a
hypothetical. A caller who wants "what did each of my N workers say" already
gets it, for free, from the existing contract.

**What's actually left:** the lead still executes and spends one model call
even when a caller only wants `workerAnswers` and ignores `answer`. Real, but
minor — one extra model call per run, not "the team can't do this."

**If that residual cost ever matters, it's already solvable with zero schema
or code change:** point the team's `lead.skillId` at a trivial
"relay the crew's outputs verbatim" skill and pin `lead.preferredModelId` to
the cheapest available model. This is the exact shape used successfully in the
founder's original TEST team (`custom_test_pipe`, lead skill
`custom_code_pipe_test_lead`, pinned to a custom Haiku entry). It collapses the
lead's cost to one cheap call instead of one expensive one; it does not
eliminate the call, and does not need to.

**Rejected:** making `TeamLeadSpec` optional (the v1 proposal). It would touch
`SeatReseat.swift`, `TeamResolver.swift`, `SkillCatalog.swift`, serialization,
and `TeamShowJSON` — for a benefit (skip the lead call entirely) that a
cheap-model relay skill already gets most of the way to, with zero code
change. Revisit only if a second, independent, real use case demonstrates the
remaining gap actually matters.

**Status:** closed as a non-issue for schema purposes. The only thing left is
a documentation/awareness gap — a caller might not know `workerAnswers` is the
field to read for per-worker raw output. If that recurs as real confusion, the
fix is a help-topic mention, not code.

## MCV-S02 — rejected: no per-worker delay field (see ledger D4)

**Checked:** `WorkerSpec` (`Worker.swift:82-104` — only `modelId`/`count`/
`skillId`), `TeamPreset`/`TeamWorkerSpec` (`TeamCatalog.swift`), and a repo-wide
grep for delay/wait/sleep/timing/schedule near worker execution. Everything
that exists is either lane-concurrency plumbing (`ExecutionLaneFlock.swift`),
async poll/backoff (`AsyncTeamService.swift`), or post-hoc timestamps
(`result.timing.startedAt/finishedAt`) — nothing configurable per worker
before it runs. This factual absence is real and stands.

**Effect observed:** the only way to test "does staggered timing actually come
through the pipe" was prompt-injecting "please sleep 30s" into a skill's
instruction text — which only works if the underlying vendor CLI happens to
have shell access. Not a structural guarantee, just a hopeful instruction.

**Verdict: reject the proposed fix (v1: `startDelaySeconds` on `WorkerSpec`).**
It would ship a debug/test-harness concern into the durable team-definition
schema that every future team and every agent-facing schema consumer would
carry — to serve a need that, on inspection, was one pipe-sanity session, not
a production pattern. It also collides with a real constraint: this
codebase's execution-lane FIFO + one-Running-per-lane guarantee is marked
inviolable elsewhere in this repo. A worker that sleeps before dispatch either
holds its lane slot idle or forces dispatch reordering — "small effort" was
the wrong estimate; the wiring lands exactly where that invariant lives.

**What already covers the real production need:** per-driver
`maxConcurrentSpawns` already staggers dispatch for a real reason (some
drivers can't run concurrent headless instances) — that is the legitimate
version of "workers start at different times," and it already exists.

**If deterministic pipe-timing testing is ever genuinely needed again:** that
is a test-harness/CLI-only concern (e.g. a run-scoped `--stagger-ms` flag, or
simply picking models with naturally different latencies, as the founder's
TEST team already does implicitly) — never a field persisted in `WorkerSpec`.
Don't build even that unless it recurs; one throwaway sanity check does not
justify new grammar.

**Status:** rejected. See ledger D4.

## MCV-S03 — `teams duplicate` doesn't return the editable shape

**Files:** `AllnighterCLI.swift` — `runTeamsDuplicate` (line 770) prints
`teamShowJSONString` = `TeamShowJSON.project(...)` (`CatalogJSON.swift:265`,
struct at line 151: `crew`/`scout`/`seatCount`/`contractVersion`, `lead: LeadSeat`).
`runTeamsDefinition` (line 673) prints the different, editable `TeamPreset`
shape (`workerSpecs`, `lead: TeamLeadSpec`, no `seatCount`). The DTO split
itself is intentional — one is a display/inspection DTO, the other is the
round-trippable edit DTO.

**Effect observed:** creating any custom team is `duplicate` → `definition` →
hand-build JSON → `edit`, four calls minimum, because `duplicate`'s output
can't be fed straight back into `edit`. This is the most durable, most broadly
applicable finding of the five — it hits every future custom-team creation by
any caller, and this CLI's callers are predominantly cold agents assembling
JSON (agent-first-schemas law).

**Original proposed fix (v1, and both reviewers' pick): set aside, not
adopted.** The archived `docs/archive/phases/Agent_Dogfood_Papercuts.md`
(2026-07-21, status "Done") records in its rejected ledger: *"Inline per-seat
overrides (`--seat X=model`) — no-new-grammar; duplicate → definition → edit
is the deliberate authoring path (D1)."* That names the three-call
`duplicate → definition → edit` sequence itself as a deliberate,
founder-adjacent ruling. The citation `(D1)` doesn't resolve to anything else
findable in this repo's docs, so the full reasoning isn't recoverable from
here — but the ruling is real and on the record, and it is specifically about
this authoring path. Swapping what `duplicate` returns risks re-litigating
that from inside a backlog doc. **Do not swap the DTO shape without first
locating whatever "(D1)" actually refers to.**

**Adopted instead — additive, same house pattern already shipped elsewhere:**
`ADP-S02` (same archived doc) already shipped an additive `alternatives`
field on `run --dry-run` naming the correct follow-up command, with no shape
change and no write-policy change ("teach at the decision point"). The
equivalent fix here: add a `nextAction` (or `alternatives`) entry to
`duplicate`'s existing `TeamShowJSON` output, naming the exact
`teams definition <id>` call needed to get the editable shape. This:
- Doesn't touch the DTO shape at all — no consumer breakage. Confirm whether
  `TeamShowJSON` is hash-locked before implementing; `ADP-S02`'s precedent
  needed no `contractVersion` bump for an additive teaching field on
  non-hash-locked JSON.
- Doesn't re-litigate D1 — the three-call path stays exactly as ruled; this
  only makes the second call discoverable from the first call's own output.
- Solves the actual pain without inventing anything new.

**Effort:** small — one additive field, same shape as `ADP-S02`'s.

**Status:** recommended first, once authorized.

## MCV-S04a — stamp hand-typed models as unverified (new, Allnighter-only)

Both reviewers proposed the same shape independently, without seeing each
other's answer — a signal this is a real, not session-specific, gap: `alln
models add` should stamp any hand-typed/custom model entry with a provenance
flag (e.g. `origin: user_added_unverified`) that `models list` and any
run-time failure against that model surface honestly. This is **not** model
verification — no CLI probe, no smoke test, no dependency on the XTerminal
extraction below. It is honest labeling of what is already true: the label
was typed by a caller and never checked against anything. It matches this
CLI's own established pattern of disclosing rather than reconstructing —
`alln models --json` already emits `MODEL_ROSTER_STALE_ID` diagnostics for a
related class of roster honesty problem.

**Effort:** small — one new field on the custom-model record, surfaced in
`models list` output and in the error path when a run against that model
fails.

**Status:** candidate, not gated behind XTerminal. Independent of S04b;
searched the archived ADP rejected-ledger and found no prior ruling against
it.

## MCV-S04b — cross-repo model smoke-verification (unchanged, XTerminal-owned)

**Observed friction:** `alln models add` accepts any hand-typed model label
with zero validation against what the driver's CLI actually supports. The
Haiku model added this session (`claude-haiku-4-5-20251001`) was typed from
memory. **Correction from review:** v1 said this "fails silently at run
time" — that was never actually observed; the typed label happened to be
accepted without incident. The honest claim is narrower: an unverified
label's failure mode (silent vs. a loud vendor-CLI error) is untested and
should not be assumed either way.

**This already has an owner and a plan — XTerminal's, not Allnighter's.**
`docs/phases/Your_AI_Model_Picker.md` §5 in the XTerminal repo (founder-ruled
2026-07-24) already earmarks exactly this for promotion to AgentOS once
XTerminal's phase ships:

> "AgentOS answers *what exists and what works*. Apps answer *what should we
> use*." Two pieces qualify: **installed-driver detection**, and **model
> smoke-verification** (XTerminal's `ModelOverrideVerifier` — "the only
> working 'is this model real' mechanism in the portfolio; Allnighter lacks
> it"). Explicitly **not** qualified: Allnighter's roster/diversity/bench/seat
> logic — that stays app-specific policy.

That doc's own rejection ledger (R4) also already rejects doing the extraction
*now*: "payoff is deferred drift-avoidance; risk is immediate destabilization
[of the app that already works]." Their `YM7` seal is the trigger, not this
doc.

**Effort:** N/A here — this is a pointer, not a spec. If/when `YM7` seals in
XTerminal, re-open this item to scope the AgentOS-side promotion and
Allnighter's consumption of it.

**Status:** deferred, tracked. Do not duplicate the XTerminal ruling here; if
it changes, this section should be updated to match, not re-argued.

## Ordering

This entire doc remains backlog behind `Sandbox_Handoff_Hotfix.md`. Within it:
MCV-S04b is additionally gated on XTerminal's `YM7` seal; MCV-S03, MCV-S00,
and MCV-S04a have no gate beyond founder authorization once the hotfix closes;
MCV-S01 requires no implementation; MCV-S02 is rejected.

## Rejection / deferral ledger

| # | Deferred / rejected | Why |
| --- | --- | --- |
| D1 | Pulling the AgentOS verification extraction forward | Mirrors XTerminal's own R4 — the pattern isn't proven in production yet |
| D2 | Promoting Allnighter's roster/diversity/bench/seat logic to AgentOS | Mirrors XTerminal's own R5 — that's product policy, not shared infrastructure |
| D3 | Any implementation before founder approval | Founder is still brainstorming (2026-07-25); this doc records findings, not authorization |
| D4 | MCV-S02's `startDelaySeconds` fix (rejected, not deferred) | Persisted schema field for a one-session debug need; collides with the inviolable lane-execution invariants; the real production-need version (`maxConcurrentSpawns`) already exists |

## Review method (for trust — verify in code, not this banner)

This revision was produced by: (1) an independent adversarial read of v1 by
Opus 5 and by Gemini 3.6 Flash, each run via
`alln run --team code_plan --worker <modelId>` — a single existing team with
the model overridden, no custom team required; (2) two of their claims
spot-checked directly against source rather than taken on faith —
`workerAnswers` existing on every `TeamRunJSON` (confirmed,
`TeamRunJSONMapper.swift:58,175`, which downgrades S01) and whether S03's
DTO-swap fix was already ruled on elsewhere (confirmed a citation exists,
`docs/archive/phases/Agent_Dogfood_Papercuts.md` lines 66-67, which redirects
S03's fix to a safer alternative); (3) reviewer disagreements, and places
where this session overrode both reviewers (S03's fix shape) or extended past
what either proposed (S01's full resolution), resolved here — reviewer output
is advisory input, not authorization, and neither review's recommendation was
adopted wholesale.
