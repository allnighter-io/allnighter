# Model Catalog & Team Schema — Quick Fixes (Reviewed)

Status: **Backlog — reviewed and hardened. MCV-S03 ratified for
implementation (founder, 2026-07-25); everything else still unauthorized.**
**Unblocked 2026-07-25:** `Sandbox_Handoff_Hotfix.md` closed and archived
(`docs/archive/phases/Sandbox_Handoff_Hotfix.md`). MCV-S03 is first up.
Owner: AllnighterCore (`ModelCatalog.swift`, `TeamCatalog.swift`) +
AgentOS (`BundledDefaults.swift`) — cross-repo, MCV-S04b additionally touches
XTerminal.
Updated: 2026-07-25 (v3 — S03 fix ratified by founder after pressure-test; see
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
- **MCV-S03** — kept as the highest-value item. v2 set the reviewers'
  DTO-shape-swap aside on a re-litigation worry; **v3 reverses that.** The
  founder pressure-tested v2's caution (2026-07-25), a third independent
  review reached the same conclusion, and a careful re-read of the archived
  ruling shows it never protected the return shape. The swap is now the
  ratified fix — see the section for the full record.
- **MCV-S04** — split into **S04a** (new: a small, local, Allnighter-only
  disclosure fix both reviewers proposed independently) and **S04b** (the
  original cross-repo item, unchanged, still deferred behind XTerminal).

## Priority order (once authorized)

1. **MCV-S03** — swap `teams duplicate`'s output to the editable `TeamPreset`
   shape (founder-ratified 2026-07-25). Highest confidence, broadest value.
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

## MCV-S03 — `teams duplicate` returns the wrong shape; swap it to `TeamPreset` (RATIFIED)

**Files:** `AllnighterCLI.swift` — `runTeamsDuplicate` (line 770) prints
`teamShowJSONString` = `TeamShowJSON.project(...)` (`CatalogJSON.swift:265`,
struct at line 151: `crew`/`scout`/`seatCount`/`contractVersion`, `lead: LeadSeat`).
`runTeamsDefinition` (line 673) prints the editable `TeamPreset` shape
(`workerSpecs`, `lead: TeamLeadSpec`, no `seatCount`) — the only shape
`teams edit` accepts.

**Effect observed:** creating any custom team is `duplicate` → `definition` →
hand-build JSON → `edit`, four calls minimum, because `duplicate`'s output
can't be fed straight back into `edit`. This is the most durable, most broadly
applicable finding of the five — it hits every future custom-team creation by
any caller, and this CLI's callers are predominantly cold agents assembling
JSON (agent-first-schemas law).

**Ruling record (founder, 2026-07-25) — supersedes v2's caution.** v2 held
back the shape swap because the archived `Agent_Dogfood_Papercuts.md`
rejected-ledger line reads *"duplicate → definition → edit is the deliberate
authoring path (D1)."* Re-read carefully — by this session, by the founder,
and by a third independent review that traced `runTeamsDuplicate` in code —
what D1 actually rejected was **inline per-seat override grammar**
(`--seat X=model`); the "deliberate path" phrase was its justification
pointing at manifest-based authoring, not a ruling on `duplicate`'s return
shape. The show-projection output was incidental reuse of the `show` printer,
never policy. First principles then decide it: a command whose own help text
says "then definition → edit" must return the shape that step consumes; the
intermediate `definition` call exists only to re-fetch the same object in a
different serialization, and carries nothing the editing caller needs.

**The fix (final):**
1. `teams duplicate` returns the round-trippable `TeamPreset` shape — byte-
   compatible with what `teams definition` returns and what `teams edit`
   consumes. The authoring path becomes `duplicate → edit`. Two calls, no
   hand-conversion, no new grammar — D1's actual substance (manifest-based
   authoring, no inline seat flags) is fully preserved.
2. Clean cut, no compatibility machinery: no dual-shape readers, no aliases,
   no migration shims — there are zero users (standing foundation-first
   directive). `teams edit` keeps accepting exactly one shape; if handed a
   show-projection payload its refusal should name the expected shape, which
   is disclosure, not compat.
3. Keep a `nextAction` on `duplicate`'s output naming the
   `teams edit <id> --file <path>` follow-up — the house transactional
   nextAction pattern, now pointing at the right next call instead of
   compensating for a wrong shape.
4. `teams definition` survives unchanged as the read-for-edit of any
   *existing* team.
5. **DTO rule, stated so this class can't recur:** mutation/duplication
   commands speak the editable spec; inspection commands (`show`, `teams`,
   `menu`) speak display projections. `duplicate` was the one command on the
   wrong side of its own rule.
6. Contract surface: this changes a public command's output schema — update
   the registry's `teams duplicate` output schema
   (`teamShowJSON` → `teamPreset`), regenerate exported contracts, and
   version per the existing schema-governance law.

**Rejected from mentor feedback:** a lenient `edit` reader accepting both
shapes (one reviewer's belt-and-braces suggestion). Feeding the show
projection to `edit` has never worked, so there is no flow to keep working —
a second accepted schema is permanent complexity buying zero coverage, and
with zero users there is nothing to migrate anyway.

**Gate (when implemented):** round-trip test — `duplicate` output fed to
`edit` unmodified succeeds; a modified round-trip persists and `show` reflects
it; the cold-agent creation flow is ≤2 calls; `edit` given a show-projection
payload refuses with an error naming the expected shape.

**Effort:** small — swap one printer call, registry schema update, round-trip
gate.

**Status:** **ratified for implementation** (founder, 2026-07-25). The hot fix
packet it was queued behind closed and archived on 2026-07-25, so this is first up.

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

The hot fix packet this was queued behind closed and archived on 2026-07-25.
Within this doc: MCV-S03 is ratified and first up; MCV-S00 and MCV-S04a
still need founder authorization; MCV-S04b is additionally gated on
XTerminal's `YM7` seal; MCV-S01 requires no implementation; MCV-S02 is
rejected.

## Rejection / deferral ledger

| # | Deferred / rejected | Why |
| --- | --- | --- |
| D1 | Pulling the AgentOS verification extraction forward | Mirrors XTerminal's own R4 — the pattern isn't proven in production yet |
| D2 | Promoting Allnighter's roster/diversity/bench/seat logic to AgentOS | Mirrors XTerminal's own R5 — that's product policy, not shared infrastructure |
| D3 | Any implementation before founder approval | Founder is still brainstorming (2026-07-25); this doc records findings, not authorization |
| D4 | MCV-S02's `startDelaySeconds` fix (rejected, not deferred) | Persisted schema field for a one-session debug need; collides with the inviolable lane-execution invariants; the real production-need version (`maxConcurrentSpawns`) already exists |
| D5 | Dual-shape lenient `edit` reader alongside the S03 swap | Compat machinery for a flow that never worked and a user base of zero; one editable spec, one accepted shape — clean cut per the foundation-first directive |
| D6 | Any migration/alias/back-compat machinery anywhere in this batch | Founder ruling 2026-07-25: zero users; everything clean, no migration, no aliases — matches the standing foundation-first directive |

## Review method (for trust — verify in code, not this banner)

This revision was produced by: (1) an independent adversarial read of v1 by
Opus 5 and by Gemini 3.6 Flash, each run via
`alln run --team code_plan --worker <modelId>` — a single existing team with
the model overridden, no custom team required; (2) two of their claims
spot-checked directly against source rather than taken on faith —
`workerAnswers` existing on every `TeamRunJSON` (confirmed,
`TeamRunJSONMapper.swift:58,175`, which downgrades S01) and whether S03's
DTO-swap fix was already ruled on elsewhere (confirmed a citation exists,
`docs/archive/phases/Agent_Dogfood_Papercuts.md` lines 66-67 — v2 read that
citation as protecting the call sequence and held the swap back; v3 corrected
the reading after founder pressure-test plus a third independent review: D1
rejected inline seat grammar, not the return shape); (3) reviewer
disagreements resolved here, with pieces rejected in both directions —
reviewer output is advisory input, not authorization, and no review's
recommendation was adopted wholesale (e.g. the lenient dual-shape reader was
rejected, D5). The v2→v3 arc is itself the lesson: an archived ruling was
almost allowed to veto the right fix on a misread of its scope — cite rulings
by what they actually rejected, not by the prose around them.
