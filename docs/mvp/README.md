# Allnighter MVP — The Council (parallel judgment, zero marginal cost)

> **This folder is the single source of execution truth for the MVP.**
> The full Allnighter roadmap (worktree factory, lanes, previews, landing,
> scheduling, iOS floor manager) is real and intended — it is parked in
> `docs/phases/` and `docs/phases/ON HOLD/`. We are **not** starting there.
>
> We are shipping the one loop the founder already runs by hand every single
> day, and which already produces better results: **one prompt -> fan out to
> several subscription CLIs in parallel -> a chosen synthesizer writes a master
> plan.**
> This is the **Council** slice from the roadmap (`ON HOLD/13_Council.md`),
> distilled first to text-only judgment with no git/worktree machinery. Direct
> CLI dispatch is the next MVP layer; managed execution safety comes later.

Status: **Build-ready.** Mac first. iOS is a designed-for, deferred follow-on.
Updated: 2026-06-14

---

## 0. One-Page Brief

The founder runs a fixed, proven ritual for every non-trivial decision:

1. Take **one prompt**.
2. Send it, unchanged, to a panel of models the founder **already pays for**:
   ChatGPT 5.5, Opus 4.8, Sonnet 4.6, Composer 2.5, Gemini Flash, Grok Build.
3. Ask a configured synthesizer (built-in default: **Opus 4.8**) to synthesize
   all the answers into a single **master plan**.

Today that is ~12 manual copy/paste actions per question. The founder is "a
copy-paste buddy." The MVP deletes that labor:

> **One prompt in. One master plan out. The bench answers in parallel.
> You never touch the clipboard.**

Hard constraints that define this product:

- **Zero marginal cost.** Route only through local CLIs the founder already
  pays for via subscription. **No API keys, no OpenRouter, no extra tokens.**
- **Local and private.** Everything runs on the Mac. Nothing is uploaded.
- **One command / one click.** The whole fan-out + synthesis is a single action.

This is **not** a model provider, a chat aggregator with its own keys, an IDE,
or a coding agent. It is a **panel orchestrator + synthesizer** sitting on top
of CLIs the user installed.

---

## 1. The MVP Loop (v1, the whole product)

```text
type or paste ONE prompt
-> choose the panel (which workers; default = all healthy)
-> Allnighter fans out the same prompt to every worker IN PARALLEL (headless CLI)
-> live per-worker status: queued / running / done / failed / timed-out
-> each worker's answer is captured and shown
-> the configured synthesizer reads the original prompt + all labeled answers
-> the synthesizer produces a single MASTER PLAN in a fixed, editable structure
-> view + copy + save the bundle (master plan + every member answer) as Markdown
```

That is the North-Star acceptance demo for the MVP. Phase 04's Works Test is
literally this loop, end to end, with the founder's real six workers.

---

## 2. Why this order (and why it does not box us in)

- **It is the proven wedge.** The founder already knows the council pattern
  yields better answers. We are automating a daily, high-value habit — not
  betting on an unvalidated feature.
- **It is the cheapest, safest slice.** Text in, text out. No git worktrees, no
  ports, no merge/land, no destructive operations. The riskiest engineering in
  the full roadmap is deferred until the daily driver is loved.
- **It is the same substrate.** Built in Swift on the `AllnighterCore` + Mac app
  shape the constitution (`ON HOLD/00_Architecture_And_Tech_Stack.md`) already
  specifies. The fan-out engine, worker/driver model, and event-stream contract
  are the *exact* primitives the full factory needs. We grow into the roadmap;
  we do not rewrite away from the MVP.

See `00_MVP_Architecture.md` § Growth Seams for the precise attach points of
every deferred capability (execution lanes, races, picker-as-prompt, iOS,
scheduling, preference ledger).

Strategy anchor:
`docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md` defines the product
boundary: Allnighter owns orchestration, synthesis, dispatch, and evaluation;
agents own execution; repos own git/process policy.

---

## 3. In Scope (v1) vs Deferred

**In scope (build this):**

- A configurable **panel of workers**, each backed by a thin **driver manifest**
  (how to invoke its CLI headlessly + how to read its output).
- A **parallel fan-out engine** (Swift Concurrency): one prompt → N subprocesses,
  per-worker timeout, cancel, normalized status + captured output.
- A **synthesis step**: one configured synthesizer call over the original prompt
  + all answers, producing a master plan in a fixed, user-editable structure.
- A **Mac app**: menu bar + window, prompt composer, panel selection, live run
  view, response viewer, master-plan viewer, copy/export to Markdown.
- **Worker health** (smoke test / doctor) so a churned CLI fails loudly, not
  silently — and a **manual-paste fallback** for any CLI that cannot yet be
  driven headlessly (e.g. an IDE-bound Composer).
- **Run history + panel presets** so the daily ritual is one click.

**Deferred (intentionally, not forgotten):**

- Git worktrees, lanes, the "no agent writes to the active repo" execution
  factory, previews/screenshots, landing/merge/revert.
- "Implement This" / picker-as-prompt, races, combine & remix.
- Post-draft advisory review board, final spec, and direct executor dispatch
  (`RB0`-`RB4`), after Phase 05 is dogfooded.
- iOS companion, pairing, relay/push, Live Activities.
- Scheduling, quota harvesting, scorecards/routing, preference ledger/taste.
- Project/repo context injection into prompts.

---

## 4. Vocabulary (user-facing)

| Term | Meaning |
| --- | --- |
| **Panel** | The set of workers a prompt is sent to (user-facing word for the bench). |
| **Worker** | One model reachable via a local subscription CLI (e.g. "Opus 4.8 via Claude Code"). |
| **Council run** | One prompt fanned out to the panel + the synthesis that follows. |
| **Member answer** | One worker's raw response to the prompt. |
| **Synthesizer** | The configured worker (built-in default: Opus 4.8) that produces the master plan. |
| **Master plan** | The single synthesized output: consensus, conflicts, gaps, and a decisive plan. |
| **Driver manifest** | Thin, versioned config describing how to invoke a worker's CLI and read its output. |
| **Doctor** | Health check that detects each CLI and runs its smoke test. |
| **Review lens** | A configurable prompt profile that reviews a draft from one perspective. |
| **Final spec** | A first-principles implementation spec produced after advisory reviews. |

Internal code may reuse the roadmap's `Council` / `Worker` / `Driver` names so
the MVP types are forward-compatible with the full product.

---

## 5. Build Order (phases)

Each phase has its own doc with Goal, Non-Goals, Ordered Slices, a Works Test,
and Exit Gates. Read `00_MVP_Architecture.md` first — it fixes the stack and the
contracts so no phase re-decides them.

```text
00  MVP Architecture (stack, models, manifest, fan-out + synthesis contracts)  <- read first
01  AllnighterCore (MVP subset): models, manifest schema, run state machine, fixtures  [DONE]
02  Worker Drivers + Parallel Fan-Out Engine  <- the heart                              [DONE]
03  Mac App Shell + Run Loop (prompt, panel, live status, response viewer)              [BUILT*]
04  Synthesis + Master Plan (default Opus; configurable in 05)                         [BUILT*]
05  History, Presets, Doctor + Distribution (make it the daily driver)  [S01-S05 DONE; dist deferred]
06  Fusion-Grade Synthesis + Evals (the correct council foundation)      [BUILT]
```

> **06 is a deliberate foundation phase.** OpenRouter's Fusion result publicly
> validated the panel→judge→plan pattern; Allnighter is the local, zero-marginal-
> cost version. Phase 06 captures Fusion's lessons (structured `JudgeAnalysis`,
> self-fusion via `PanelSeat`, budget-panel presets) and lays the correct final
> run model (seats, structured analysis, `StageOutput` sequence) **before** any
> review-board machinery — so RB0–RB5 add stage *kinds*, never a rewrite. No
> OpenRouter, no API keys; zero marginal cost is preserved.

> `*` = code complete and automated gates green (`swift test` 57 + app suite via
> `scripts/check.sh`). Driver headless flags are **verified on-device** (claude,
> grok incl. Composer 2.5, codex=gpt-5.5; gemini→manual). The only thing left is
> the founder clicking "Run council" once on a real prompt (spends quota).

**MVP "lovable demo" = phases 01–04.** Phase 05 makes it the founder's daily
driver and makes the synthesizer configurable. Phase 06 makes the synthesis
itself Fusion-grade and lays the correct council-run foundation. Review Board
begins only after 06's foundation is in and the `RB0` activation gate passes.

Next: the Fusion-grade foundation, then the judgment workflow.

```text
06   Fusion-Grade Synthesis + Evals (PanelSeat, JudgeAnalysis, StageOutput, evals)
RB0  Judgment Workflow Overview (+ activation gate, now incl. synthesis-lift)
RB1  Workflow Presets + Stage Primitives (consume 06's StageOutput / PromptProfile)
RB2  Review Board (lenses consume JudgeAnalysis + raw answers)
RB3  Final Spec (resolve contradictions; preserve/reject unique insights)
RB4  Direct Executor Dispatch (brief carries the analysis decisions)
RB5  Return Review, Outcome Scoring, and Routing (close the control loop)
RB6  Council-as-Tool (local CLI/MCP/HTTP; local Fusion any agent can call — the moat)
```

> **RB6 needs only Phase 06**, so it can ship early — delivering "local Fusion
> any terminal agent can call, at zero marginal cost" as soon as the council
> foundation exists. It is judgment-only (no git, no execution) and recursion-
> guarded; it makes Allnighter the judgment layer the whole machine runs on.

---

## 6. Success Criteria

| Signal | Target |
| --- | --- |
| Copy/paste actions per question | **0** (down from ~12) |
| Clicks from prompt to master plan | **1** (after panel is configured) |
| Marginal cost per run | **$0** (subscription CLIs only) |
| Worker churn handled | A broken/updated CLI surfaces in Doctor, never silently drops |
| Daily use | Founder uses it for real decisions instead of manual copy/paste |
| Forward compatibility | Core types + engine reused (not rewritten) when execution lanes are added |

---

## 7. How to Execute (rules)

1. **Read `00_MVP_Architecture.md` before writing code.** It fixes stack + contracts.
2. **Contract-first.** New models/manifest fields/run states start in
   `AllnighterCore` with round-trip tests and fixtures, never only in view code.
3. **Prove with the Works Test.** A phase is done when its Works Test passes and
   `swift test` (+ app build, where targets exist) is green.
4. **Honor the constitution where it applies.** The MVP obeys
   `ON HOLD/00_Architecture_And_Tech_Stack.md` for stack, event envelope, driver
   manifest, and safety posture — it just builds a smaller slice of it.
5. **Do not build into a box.** Before adding a shortcut that would block a
   deferred capability in § Growth Seams, stop and choose the forward-compatible
   path.
6. **Honesty.** Quota/limit hints are labeled estimates; a worker that did not
   answer is shown as failed, never faked.
