# Allnighter MVP — The Council (parallel judgment, zero marginal cost)

> **This folder is the source of truth for the built MVP foundation.**
> New post-MVP work now starts in `docs/phases/`; this folder preserves the
> Council and Design Council contracts that shipped.
>
> We are shipping the one loop the founder already runs by hand every single
> day, and which already produces better results: **one prompt -> fan out to
> several subscription CLIs in parallel -> a chosen synthesizer writes a master
> plan.**
> This is the **Council** slice: text-first parallel judgment over local
> subscription CLIs, distilled without managed repo/lane machinery.

Status: **Build-ready.** Mac first. iOS is a designed-for, deferred follow-on.
Updated: 2026-06-14

---

## 0. One-Page Brief

The founder runs a fixed, proven ritual for every non-trivial decision:

1. Take **one prompt**.
2. Send it, unchanged, to a panel of models the founder **already pays for**:
   ChatGPT 5.5, Opus 4.8, Sonnet 4.6, Composer 2.5, Gemini Flash, Grok Build.
3. Ask a configured synthesizer (built-in default: **Opus 4.8**) to synthesize
   all the answers into a single **plan**.

Today that is ~12 manual copy/paste actions per question. The founder is "a
copy-paste buddy." The MVP deletes that labor:

> **One prompt in. One plan out. The bench answers in parallel.
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
-> view + copy + save the bundle (plan + every member answer) as Markdown
```

That is the North-Star acceptance demo for the MVP. Phase 04's Works Test is
literally this loop, end to end, with the founder's real six workers.

---

## 2. Why this order (and why it does not box us in)

- **It is the proven wedge.** The founder already knows the council pattern
  yields better answers. We are automating a daily, high-value habit — not
  betting on an unvalidated feature.
- **It is the smallest, safest slice.** Text in, text out. No git worktrees, no
  ports, no merge/land, no destructive operations. The riskiest engineering in
  the full roadmap is deferred until the daily driver is loved.
- **It is the same substrate.** Built in Swift on the `AllnighterCore` + Mac app
  shape that post-MVP phases continue to use. The fan-out engine,
  worker/driver model, and event-stream contract are the primitives future
  phases build on. We grow from the MVP; we do not rewrite away from it.

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
  + all answers, producing a plan in a fixed, user-editable structure.
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
| **PlanWriter** | The configured worker (built-in default: Opus 4.8) that produces the plan. |
| **Plan** | The single synthesized output: consensus, conflicts, gaps, and a decisive plan. |
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
02  Model Drivers + Parallel Fan-Out Engine  <- the heart                              [DONE]
03  Mac App Shell + Run Loop (prompt, panel, live status, response viewer)              [BUILT*]
04  Synthesis + Plan (default Opus; configurable in 05)                         [BUILT*]
05  History, Presets, Doctor + Distribution (make it the daily driver)  [S01-S05 DONE; dist deferred]
06  Fusion-Grade Synthesis + Evals (the correct council foundation)      [BUILT]
```

> **06 is a deliberate foundation phase.** OpenRouter's Fusion result publicly
> validated the panel→judge→plan pattern; Allnighter is the local, zero-marginal-
> cost version. Phase 06 captures Fusion's lessons (structured `PlanAnalysis`,
> self-fusion via `Worker`, budget-panel presets) and lays the correct final
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
06   Fusion-Grade Synthesis + Evals (Worker, PlanAnalysis, StageOutput, evals)
RB0  Judgment Workflow Overview (+ activation gate, now incl. synthesis-lift)
RB1  Workflow Presets + Stage Primitives (consume 06's StageOutput / PromptProfile)
RB2  Review Board (lenses consume PlanAnalysis + raw answers)
RB3  Final Spec (resolve contradictions; preserve/reject unique insights)
RB4  Direct Executor Dispatch (brief carries the analysis decisions)
RB5  Return Review, Outcome Scoring, and Routing (close the control loop)
RB6  Council-as-Tool (local CLI/MCP/HTTP; local Fusion any agent can call — the moat)
```

> **The second spine — the Design Council (Design0–Design2), image-first. BUILT 2026-06-15.** Lane 1
> (RB) answers *technical* prompts ("make this correct"). At least half of real
> prompts are *design* ("improve this screen", "give me a few mockups"). The design
> path is deliberately small: attach a screenshot, fan out to the **image engines
> you already pay for** (Grok Imagine, Gemini Nano Banana Pro, ChatGPT image) ×
> design personas, get a **board of real design options**, pick the one you love,
> then **"Build this"** — choosing which CLI implements it, exactly like the build
> council (RB4). Image engines design; coding agents build; you decide.

```text
Design0  Design Council Overview (charter; incl. why OCR + HTML rendering are DEAD)  <- read first
Design1  The Image Council (screenshot → image-engine × persona fan-out → board → pick)
Design2  Build This (chosen image → pick the implementer CLI → the agent builds it; reuses RB4)
```

> **DEAD, do not revive (Design0 § "What is DEAD"):** OCR (the multimodal models
> *see* — LLM image recognition replaces it) and the HTML render pipeline
> (WKWebView / self-contained-HTML contract / content fixture / pHash divergence /
> hermetic gates — all gone). Your subscriptions already include **image engines**
> that emit finished designs directly, for free, and design better than a coding
> agent writing Tailwind. The unit is a **generated image**; **code comes from the
> build step**. The only new engineering is capturing an image output from a CLI +
> a gallery board. Gated on a Design Activation Gate (does a CLI generate images
> headlessly at $0).

> **RB6 needs only Phase 06**, so it can ship early — delivering "local Fusion
> any terminal agent can call, at zero marginal cost" as soon as the council
> foundation exists. It is judgment-only (no git, no execution) and recursion-
> guarded; it makes Allnighter the judgment layer the whole machine runs on.

---

## 6. Success Criteria

| Signal | Target |
| --- | --- |
| Copy/paste actions per question | **0** (down from ~12) |
| Clicks from prompt to plan | **1** (after panel is configured) |
| Marginal cost per run | **$0** (subscription CLIs only) |
| Model churn handled | A broken/updated CLI surfaces in Doctor, never silently drops |
| Daily use | Founder uses it for real decisions instead of manual copy/paste |
| Forward compatibility | Core types + engine reused (not rewritten) when execution lanes are added |

---

## 7. How to Execute (rules)

1. **Read `00_MVP_Architecture.md` before writing code.** It fixes stack + contracts.
2. **Contract-first.** New models/manifest fields/run states start in
   `AllnighterCore` with round-trip tests and fixtures, never only in view code.
3. **Prove with the Works Test.** A phase is done when its Works Test passes and
   `swift test` (+ app build, where targets exist) is green.
4. **Honor the built foundation where it applies.** The MVP fixed the stack,
   event envelope, driver manifest, and safety posture for later phases.
5. **Do not build into a box.** Before adding a shortcut that would block a
   deferred capability in § Growth Seams, stop and choose the forward-compatible
   path.
6. **Honesty.** Quota/limit hints are observed and sourced; a worker that did not
   answer is shown as failed, never faked.
