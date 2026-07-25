# Model Catalog & Team Schema — Quick Fixes, and the AgentOS Verification Question

Status: **Backlog — brainstorming, nothing authorized yet.** Queued behind
`Sandbox_Handoff_Hotfix.md` (the current active work) — do not start until that
packet closes.
Owner: AllnighterCore (`ModelCatalog.swift`, `TeamCatalog.swift`) +
AgentOS (`BundledDefaults.swift`) — cross-repo, MCV-S04 additionally touches
XTerminal.
Updated: 2026-07-25
Companion: XTerminal `docs/phases/Your_AI_Model_Picker.md` §5 (the founder
ruling MCV-S04 tracks — do not restate or fork that decision here, only cite it).

## Origin

Founder asked for a throwaway 3-worker "TEST" team (Haiku / Cursor Composer
2.5 / Antigravity Gemini, min effort, staggered response timing) to sanity-test
the run pipe before running anything. Building it by hand surfaced five real
gaps in the CLI's model/team surface — none blocking, all worth fixing. This
doc is the backlog for those five, plus the one item (MCV-S04) that isn't
Allnighter's to decide alone.

None of the five below are authorized. This is the list, not a plan.

## MCV-S00 — Haiku is missing from the `claude_code` catalog, in both repos

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

**Effort:** trivial in each repo (a few lines), but two repos, not one.

**Status:** founder said "add in both, but not yet — still brainstorming."
No action until explicitly approved.

## MCV-S01 — `lead` is non-optional on every team; there's no way to build a true N-worker team

**Files:**
- `TeamCatalog.swift:276` — `public var lead: TeamLeadSpec` (doc comment:
  "The mandatory Team Lead (synthesizer). Exactly one.")
- `CatalogJSON.swift:241` — `TeamShowJSON.lead: LeadSeat`, same constraint on
  the read-projection side.
- Direct dereferences of `team.lead` exist in `SeatReseat.swift`,
  `TeamResolver.swift`, and `SkillCatalog.swift` — making `lead` optional
  touches all of them, not just the struct.

**Effect observed:** a "3-worker" team is structurally 4 seats/4 model calls,
because every team pays for a synthesizer whether or not the caller wants
synthesis. A raw "run N workers, hand back what each said" team shape does not
exist today.

**Effort:** small/medium — real schema + resolver change, not a one-liner.

**Status:** undecided. Worth it only if leaderless probe/test teams turn out
to be a recurring need, not a one-off.

## MCV-S02 — no per-worker delay/timing field anywhere in the run schema

**Checked:** `WorkerSpec` (`Worker.swift:82-104` — only `modelId`/`count`/
`skillId`), `TeamPreset`/`TeamWorkerSpec` (`TeamCatalog.swift`), and a repo-wide
grep for delay/wait/sleep/timing/schedule near worker execution. Everything
that exists is either lane-concurrency plumbing (`ExecutionLaneFlock.swift`),
async poll/backoff (`AsyncTeamService.swift`), or post-hoc timestamps
(`result.timing.startedAt/finishedAt`) — nothing configurable per worker
before it runs.

**Effect observed:** the only way to test "does staggered timing actually come
through the pipe" was prompt-injecting "please sleep 30s" into a skill's
instruction text — which only works if the underlying vendor CLI happens to
have shell access. Not a structural guarantee, just a hopeful instruction.

**Fix shape:** an optional `startDelaySeconds` on `WorkerSpec`, honored by the
executor before dispatch (not by the model).

**Effort:** small — one new optional field + executor wiring.

**Status:** undecided. Low urgency; only matters for pipe-sanity testing, not
production team runs.

## MCV-S03 — `teams duplicate` returns a read-only projection, not the editable shape

**Files:** `AllnighterCLI.swift` — `runTeamsDuplicate` (line 770) prints
`teamShowJSONString` = `TeamShowJSON.project(...)` (`CatalogJSON.swift:265`,
struct at line 151: `crew`/`scout`/`seatCount`/`contractVersion`, `lead: LeadSeat`).
`runTeamsDefinition` (line 673) prints the different, editable `TeamPreset`
shape (`workerSpecs`, `lead: TeamLeadSpec`, no `seatCount`). This split is
intentional — one is a display/inspection DTO, the other is the round-trippable
edit DTO — confirmed not a bug.

**Effect observed:** creating any custom team is `duplicate` → `definition` →
hand-build JSON → `edit`, four calls minimum, because `duplicate`'s output
can't be fed straight back into `edit`.

**Effort:** small — API ergonomics only; `duplicate` could return the
`TeamPreset` shape (like `definition` does) instead of the show-projection.

**Status:** undecided.

## MCV-S04 — no model-label verification against the real vendor CLI (AgentOS candidate — not Allnighter's call alone)

**Observed friction:** `alln models add` accepts any hand-typed model label
with zero validation against what the driver's CLI actually supports. The
Haiku model added this session (`claude-haiku-4-5-20251001`) was typed from
memory with no verification it's the exact wire label the `claude_code` driver
expects — a typo here fails silently at run time, not at creation time.

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

This entire doc is backlog behind `Sandbox_Handoff_Hotfix.md`. MCV-S04 is
additionally gated on XTerminal's `YM7` seal regardless of when the other four
items get picked up.

## Rejection / deferral ledger

| # | Deferred | Why |
| --- | --- | --- |
| D1 | Pulling the AgentOS verification extraction forward | Mirrors XTerminal's own R4 — the pattern isn't proven in production yet |
| D2 | Promoting Allnighter's roster/diversity/bench/seat logic to AgentOS | Mirrors XTerminal's own R5 — that's product policy, not shared infrastructure |
| D3 | Any implementation before founder approval | Founder is still brainstorming (2026-07-25); this doc records findings, not authorization |
