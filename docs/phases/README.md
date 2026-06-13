# Allnighter — Build Phases

> **This folder is the single source of execution truth for Allnighter.**
> It is self-contained. Everything needed to build the product — the strategy,
> the entire tech stack, the data contracts, and the ordered build slices — lives
> in `00_Architecture_And_Tech_Stack.md` plus the numbered phase docs here.
>
> The former `Allnighter-Product-Requirements-v0.3.md` PRD and the
> `Allnighter-Local-AI-Worker-Opportunity.md` note have been fully absorbed into
> these docs and archived. The old `docs/phases/*` (CLI Loci) and `docs/product/*`
> contracts are superseded and archived under `docs/archive/`. Do not build from
> them.
>
> **Kept, but explicitly post-v1:** `docs/strategy/Allnighter-Agent-AB-Testing-Extension.md`
> is a deliberate future-extension roadmap (market-tested agent operations). It is
> **not** part of the v1 build. Its only v1 obligation — keep `PreferenceEvent`
> extensible for future market outcomes — is captured in Phase 15.

Status: **Build-ready.** Hand to Opus 4.8 for execution, phase by phase.
Updated: 2026-06-12

---

## 0. One-Page Brief

Allnighter turns the user's Mac into an overnight **agent factory** and the
user's iPhone into the **floor manager** for that factory. It coordinates the AI
coding tools the user already pays for — Claude Code, Codex CLI, Grok, Gemini
CLI, Aider, Cursor, IDE agents — plus local models running on the user's own
hardware.

The central promise:

> **You already pay for the team. Allnighter makes it show up to work.**

It is **not** a model provider, IDE, chat aggregator, cloud coding service, or
terminal viewer. It is an **asynchronous project manager, scheduler, option
factory, and landing line** for solo builders who use AI as their primary
development workforce.

Five compounding loops:

1. **Safe parallel work** — every task runs in its own invisible lane (git
   worktree, branch, ports, logs, preview, artifacts). The user never hears the
   word "worktree."
2. **Option generation** — the same task fans out to several agents that return
   competing strategies, plans, mockups, or running builds.
3. **Pick and execute** — the user selects the best answer, and that selection
   *becomes the work order* that starts implementation in an isolated lane.
4. **Quota harvesting** — the scheduler spends the user's expiring agent capacity
   before reset windows. Idle paid workers are a visible product problem.
5. **Preference compounding** — every pick, rejection, revert, and "implement
   this" tap becomes structured preference data that teaches Allnighter the
   user's taste, risk tolerance, and execution style.

The hidden technical thesis:

> Worktrees make concurrency safe. The scheduler makes it useful. The Mac makes
> it powerful. The iPhone makes it habitual. The picks make it compound.

---

## 1. Category and Differentiation

Allnighter is **agent operations for solo builders**. It owns the missing middle:

```text
intent -> parallel options -> selected direction -> isolated implementation
-> preview/proof -> landing -> learned preference
```

Most products own only one side: chat tools produce options but do not execute
them; IDE agents execute but do not fan out, synthesize, or harvest quota; vendor
tools run one vendor's agents; cloud builders produce previews but do not
coordinate the user's own installed local tools and subscriptions.

### Positioning lines

- Primary: **"You already pay for the team. We make it show up to work."**
- "Your AI team pulls the all-nighter. You don't."
- "Ask your whole bench. Pick the best answer. Ship it."
- "From one idea to three options to implemented work."
- Local-AI line (inside the product): **"Put your Mac Studio on the night shift."**

---

## 2. Strategic Theses (why we build in this order)

These drive prioritization. The substrate (T3) is built first because it is the
moat; the wedge (T4) ships next because it is what makes someone say "I need this
this week."

- **T1 — Utilization arbitrage.** The customer has prepaid capacity that expires.
  The headline metric is *agent-hours converted into reviewable progress*, not
  messages sent.
- **T2 — Neutrality is structural.** A model lab cannot be the neutral manager of
  its competitors. Allnighter can, because it runs on the user's machine and
  coordinates tools the user installed.
- **T3 — The execution substrate is the barrier.** The moat is hard local
  infrastructure: hidden worktrees, branch management, port brokering, preview
  capture, process supervision, agent drivers, artifact storage, landing queues.
  This is not a chat wrapper. **Build the factory before the UI.**
- **T4 — Parallel judgment before execution.** The unlock is not just parallel
  coding; it is parallel *judgment* — three strategies, three plans, three UI
  directions — then "pick this one and implement it." That button is the bridge
  from thinking to doing.
- **T5 — Selection data compounds.** Users think they are choosing drafts. They
  are training a personal judgment model.
- **T6 — Intelligence commoditizes, orchestration endures.** If local models
  become frontier-class on consumer hardware, that is the *strongest* version of
  Allnighter's future, not a threat. As intelligence gets cheap and unlimited,
  human attention becomes the scarce resource; Allnighter spends less human
  attention per unit of shipped work. The serving layers (Ollama, LM Studio,
  llama.cpp, MLX) answer "how do I run a model?" Allnighter answers "what should
  the workers do, how do their outputs converge, and which result should become
  shipped product?"
- **T7 — Mac and iPhone are both first-class.** The iPhone creates the habit; the
  Mac creates the power. Two excellent apps, not "a Mac runner hidden behind iOS."

---

## 3. Product Principles (non-negotiable across all phases)

1. **Hide the plumbing.** Say *lane, draft, worker, landing, preview*. Never say
   *worktree, rebase, detached HEAD, port collision* in core UX.
2. **Prefer artifacts over logs.** Lead with screenshots, previews, recordings,
   tests, summaries, QA results. Diffs are available, never the headline.
3. **Make decisions rewarding.** Picking a winner should feel like unlocking
   progress, not clearing an inbox.
4. **One tap should move the night.** A single decision can dispatch work,
   continue a lane, merge a result, or spawn a generation.
5. **Do not blind-merge by default.** Finished work earns trust through tests,
   previews, conflict status, and risk tiers.
6. **Use agents for what they are good at** — brainstorm, critique, build, test,
   summarize, repair — not only as code writers.
7. **Keep the bench busy, but respect boundaries.** Standing orders, quiet hours,
   protected paths, spend ceilings, and repo enrollment define the safe envelope.
8. **Every pick is data.** Preferences are logged, exportable, deletable, reused.
9. **Design for churn.** Agent CLIs, auth flows, and limits change. Drivers must
   be thin, versioned, smoke-tested, and updateable.
10. **Make the Mac feel magic too.** Large-screen multi-draft comparison, instant
    lane spawning, preview grids, and one-click implementation are core, not
    secondary.

The **core invariant** that overrides everything:

> **No agent ever writes to the user's active working directory.** All work
> happens in isolated lanes (git worktrees outside the active repo).

---

## 4. North-Star Acceptance Demo (the whole product in one flow)

Every phase is in service of making this real. Treat it as the final integration
test.

```text
User opens Allnighter on iPhone (or types on Mac):
  "Give me three different directions for making this dashboard feel premium."

Allnighter:
  - creates three hidden lanes (worktrees) from one pinned base commit;
  - assigns workers (e.g. Claude Code, Codex CLI, a third);
  - runs each attempt in isolation;
  - boots each preview on its own port;
  - captures screenshots;
  - shows three swipeable cards on phone and a comparison grid on Mac.

User:
  - taps the best one;
  - says "but make the header sticky";
  - taps "Implement This."

Allnighter:
  - continues/forks the selected lane, applies the note (picker-as-prompt);
  - runs tests; produces a landing card with screenshot + risk tier;
  - one-tap green-tier land into the target branch, with one-tap revert;
  - records the pick as a preference event that seasons future work orders.
```

This proves: worktree factory, agent orchestration, artifact capture, iOS
decision loop, Mac comparison loop, picker-as-prompt, landing, and preference
logging.

---

## 5. Resolved Decisions (defaults chosen so execution is never blocked)

The PRD left 11 open decisions. To unblock building, these are **resolved with
defaults**. Items marked *(founder/business)* do not block engineering and can be
changed without code rework.

| # | Decision | Resolution for v1 |
| --- | --- | --- |
| 1 | Identity | **Allnighter replaces CLI Loci.** Clean pivot. |
| 2 | First worker set | **Claude Code + shell driver first**, then Codex CLI, then a third (Grok/Gemini/local). |
| 3 | First demo app type | **A bundled sample web app** (Vite + React) for deterministic previews/screenshots. Native-app targets are post-v1. |
| 4 | Relay timing | **Local-first MVP.** Relay/push land in Milestone F (Phase 20). |
| 5 | Auto-land | **Excluded from v1.** One-tap green-tier land only, always user-initiated. |
| 6 | Pricing *(business)* | Assume **flat monthly**; no code depends on this. |
| 7 | Taste storage | **Local-only in v1;** optional encrypted backup later. |
| 8 | IDE integration | **After headless workers.** Cursor/Antigravity treated as lane consumers (handoff), post-MVP. |
| 9 | Mac scope | **Full command center + menu bar from MVP**, not a hidden daemon. |
| 10 | Local workers timing | **Mid-roadmap (Phase 19), read-only first** — earlier than the PRD's end-of-plan slot, as a differentiator, but only after the core factory works. |
| 11 | Name *(business)* | **"Allnighter"** is the working title. No code depends on the name. |

---

## 6. Milestones and Phase Stack

Phase numbers are stable IDs. **Build in the order of the priority stack below**,
not by guessing. Each phase has its own doc with Goal, Non-Goals, Stack notes,
Ordered Slices, a Works Test, and Exit Gates. Read `00` first — it is the
constitution every phase obeys.

> **`00_Architecture_And_Tech_Stack.md`** — Tech stack, repo layout, system
> architecture, all cross-cutting contracts (event envelope, completion
> detection, recovery, concurrency), and the safety/trust model. **Read first.**

### Milestone A — Substrate (the moat). Build the factory before the UI.

| Phase | Purpose |
| --- | --- |
| [01 — AllnighterCore Shared Package](01_AllnighterCore_Shared_Package.md) | Swift package: Codable models, lane state machine, API + event envelope, fixtures, `swift test`. |
| [02 — Mac App Shell + Repo Enrollment](02_Mac_App_Shell_And_Repo_Enrollment.md) | Menu bar + command center window, enroll local git repos, project config + local store. |
| [03 — Lane Manager (Worktree Factory)](03_Lane_Manager_Worktree_Factory.md) | The moat: worktree/branch/port/process lifecycle, recovery, kill switch. |
| [04 — Agent Driver Framework](04_Agent_Driver_Framework.md) | Thin versioned drivers + smoke tests; Claude Code, Codex CLI, shell drivers; normalized events. |
| [05 — Single-Agent Factory](05_Single_Agent_Factory.md) | First end-to-end on Mac: dispatch a task to a lane, run an agent, stream events, mark complete. |

### Milestone B — Proof and previews

| Phase | Purpose |
| --- | --- |
| [06 — Preview & Artifact System](06_Preview_And_Artifact_System.md) | Port broker, preview supervisor, readiness probe, screenshot/video capture, artifact store + API. |
| [07 — Landing Queue (Green Tier)](07_Landing_Queue_Green_Tier.md) | Risk classifier, merge simulation (`git merge-tree`), landing card, one-tap merge + revert. |

### Milestone C — Mobile floor manager

| Phase | Purpose |
| --- | --- |
| [08 — Transport & Pairing](08_Transport_And_Pairing.md) | Bonjour discovery, embedded WebSocket server, device pairing + auth, resumable event stream. |
| [09 — iOS App MVP](09_iOS_App_MVP.md) | iOS shell, pairing, Home, Active Lanes, global kill switch, landing actions. |
| [10 — Capture → Work Order](10_Capture_To_Work_Order.md) | Text/voice/screenshot capture → editable interpretation → backlog → dispatch. |

### Milestone D — Parallel judgment (the wedge)

| Phase | Purpose |
| --- | --- |
| [11 — Draft Race + Comparison](11_Draft_Race_And_Comparison.md) | One task → 2–3 lanes on one base commit; Mac comparison grid; iOS swipeable cards. |
| [12 — Picker-as-Prompt](12_Picker_As_Prompt.md) | "Implement This": selection becomes a work order; lane starts within 5 s. |
| [13 — Council](13_Council.md) | Fan-out → critique → synthesis → verdict + minority report; implement the chosen direction. |
| [14 — Combine & Remix](14_Combine_And_Remix.md) | Synthesize parts of multiple drafts; spawn variations from a winner. |

### Milestone E — Intelligence layer

| Phase | Purpose |
| --- | --- |
| [15 — Preference Ledger & Taste Memory](15_Preference_Ledger_And_Taste_Memory.md) | Log picks/rejections/reverts; synthesize project memory; inject into work orders. |
| [16 — Worker Scorecards & Routing](16_Worker_Scorecards_And_Routing.md) | Outcome metrics per agent/category; scorecard-driven routing; pin worker. |
| [17 — Quota Harvester](17_Quota_Harvester.md) | Honest quota estimation, idle detection, reset-window nudges, ceilings, quiet hours. |
| [18 — QA Worker](18_QA_Worker.md) | Playwright-driven smoke QA of lane previews; plain-language QA summary on landing cards. |
| [19 — Local Workers](19_Local_Workers.md) | Ollama / LM Studio / OpenAI-compatible / llama.cpp drivers; Local Bench; local scheduling + roles. |

### Milestone F — Always-on and ship

| Phase | Purpose |
| --- | --- |
| [20 — Relay & Push](20_Relay_And_Push.md) | Thin relay (no code storage), APNs, Live Activities, remote commands, preview tunnel. |
| [21 — Morning Pull](21_Morning_Pull.md) | Daily digest: landed work, pending picks, agent-hours, quota harvested. |
| [22 — Speculative Builds](22_Speculative_Builds.md) | Opt-in idle-time draft work from TODOs/issues/failed tests, clearly labeled. |
| [23 — Distribution & Dogfood](23_Distribution_And_Dogfood.md) | Notarized Mac DMG, TestFlight iOS, diagnostics/doctor, daily dogfood loop. |

### Priority stack (literal build order)

```text
00  read the constitution
01  AllnighterCore
02  Mac shell + repo enrollment
03  Lane Manager            <- the moat
04  Agent Driver Framework
05  Single-Agent Factory    <- first "wake up to progress" moment
06  Preview & Artifacts
07  Landing Queue (green)
08  Transport & Pairing
09  iOS App MVP
10  Capture -> Work Order
11  Draft Race              <- the wedge / launch story
12  Picker-as-Prompt
13  Council
14  Combine & Remix
15  Preference / Taste
16  Scorecards & Routing
17  Quota Harvester
18  QA Worker
19  Local Workers
20  Relay & Push
21  Morning Pull
22  Speculative Builds
23  Distribution & Dogfood
```

**MVP / smallest lovable demo** = phases 01–12 (substrate → previews → mobile →
race → picker-as-prompt). That is the North-Star demo in §4. Everything from 13
on deepens the product.

---

## 7. How to Execute These Phases (rules for Opus 4.8)

1. **Read `00` before writing any code.** It fixes the stack and the contracts.
   Do not re-decide the stack per phase.
2. **One active phase at a time** unless the phase doc explicitly authorizes
   parallel tracks (Mac / iOS / Core / Relay are designed to parallelize via the
   `AllnighterCore` contract).
3. **Each phase doc owns its scope.** Build the smallest slice that satisfies its
   Works Test, then close the Exit Gates.
4. **Contract-first.** New models, events, API messages, and state transitions
   start in `AllnighterCore` with round-trip tests and fixtures, never only in
   view code or prompt prose.
5. **Prove with the Works Test.** A phase is not done until its Works Test passes
   and `swift test` (+ app builds, where targets exist) is green.
6. **Honor the safety model** (`00` §Safety) in every phase that touches dispatch,
   files, landing, transport, or transcripts — not just Phase 23.
7. **Fill in details freely**, but do not contradict `00` or change a resolved
   decision (§5) without recording the change in `00` and this README.
8. **Archive on closeout.** When a phase completes, note closeout in its doc and
   promote durable truth into `00`. Move finished phase docs to
   `docs/archive/phases/` per repo convention.

---

## 8. Success Metrics

| Metric | Meaning |
| --- | --- |
| Agent-hours worked | Time agents spent doing useful lane work |
| Idle paid capacity | Estimated unused quota in current windows |
| Drafts produced / landed | Completed lanes with artifacts / merged or PR'd |
| First-draft win rate | Taste/routing model quality |
| Race pick rate | How often races produce a clear winner |
| Implement-this rate | How often ideas become execution |
| Landing success / revert rate | Trust in the merge system |
| Time to first artifact | Onboarding "magic" metric |
| Morning Pull opens | Habit formation |

---

## 9. Glossary

| Term | Definition |
| --- | --- |
| **Agent / Worker** | A locally installed or local-network AI coding tool Allnighter can dispatch to or hand off to. "Worker" is the user-facing word. |
| **Agent-hours** | Time spent by workers on lane execution. |
| **Lane** | A hidden, isolated workspace for one task attempt. Maps 1:1 to a git worktree + branch. |
| **Draft** | A candidate answer, plan, mockup, or running implementation produced in a lane. |
| **Race** | One task dispatched to multiple lanes/workers from the same base commit. |
| **Council** | Multi-agent reasoning session with critique, synthesis, verdict, and dissent. |
| **Landing** | Bringing a completed lane back to the target branch (merge) or PR flow. |
| **Picker-as-prompt** | The selection gesture that becomes the implementation work order — no copy/paste, no re-explaining. |
| **Preference event** | Structured record of a pick/reject/split/revert/remix. |
| **Taste model** | Per-project memory derived from preference events; seasons future prompts and routing. |
| **Quota harvester** | Scheduler behavior that spends expiring paid capacity before reset. |
| **Standing order** | Persistent rule constraining or directing autonomous work. |
| **Morning Pull** | Daily digest of overnight work and pending decisions. |
| **Local worker** | A local-model runtime (Ollama, LM Studio, llama.cpp, OpenAI-compatible) used as private capacity. |
| **Driver** | Thin, versioned adapter that translates work orders into an agent's launch command and its output back into normalized events. |
