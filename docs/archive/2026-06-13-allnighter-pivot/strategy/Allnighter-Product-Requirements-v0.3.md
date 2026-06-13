# allnighter.io

## Agent Operations for Solo Builders

**Product and Feature Requirements Document**  
Version 0.3 - Build-Ready Draft  
June 12, 2026

> Status: Pivot packet for mentor review and implementation planning. This
> document intentionally sits beside the current CLI Loci docs until the
> founder decides whether Allnighter replaces or branches from CLI Loci.

---

## 0. One-Page Brief

Allnighter turns the user's Mac into an overnight agent factory and the user's
iPhone into the floor manager for that factory. The product coordinates AI
coding tools the user already pays for, such as Claude Code, Codex CLI, Grok
Build, Gemini CLI, Aider, Cursor, and IDE-based agents where integration
surfaces exist.

The central promise:

> You already pay for the team. Allnighter makes it show up to work.

The old product category is "remote control for coding agents." Allnighter is
different. It is an asynchronous project manager, scheduler, option factory,
and landing line for solo builders who use AI as their primary development
workforce.

The product has five compounding loops:

1. **Safe parallel work:** each task runs in its own invisible lane: a git
   worktree, branch, ports, logs, preview server, and artifact folder. The user
   never needs to know the word "worktree."
2. **Option generation:** the same question or task can be sent to several
   agents at once. They return competing strategies, implementation plans, UI
   mockups, or running builds.
3. **Pick and execute:** the user selects the best answer, draft, or direction.
   That selection is not only a preference event. It can immediately become the
   work order that starts implementation in an isolated lane.
4. **Quota harvesting:** the scheduler tries to spend the user's expiring agent
   capacity before reset windows. Paid workers sitting idle become a visible
   product problem.
5. **Preference compounding:** every pick, split verdict, rejection, revert,
   and "implement this" tap becomes structured preference data. Over time,
   Allnighter learns the user's product judgment, taste, risk tolerance, and
   preferred execution style.

The hidden technical thesis:

> Worktrees make concurrency safe. The scheduler makes it useful. The Mac makes
> it powerful. The iPhone makes it habitual. The picks make it compound.

---

## 1. Product Claim

Allnighter is **agent operations for solo builders**.

It gives one builder the operating model of a small AI product team:

- a backlog;
- a roster of agents;
- parallel lanes of work;
- strategy councils;
- draft races;
- previews and artifacts;
- QA passes;
- a landing queue;
- a daily morning pull;
- memory of past decisions.

Allnighter is not a model provider, IDE, chat aggregator, cloud coding service,
or terminal viewer. It coordinates tools the user already owns and turns their
available agent capacity into finished, reviewable product progress.

---

## 2. Problem Statement

AI-assisted solo builders already behave like managers, but their tools still
make them act like terminal operators.

Today, a serious builder often does this manually:

1. Explain one feature idea to Claude.
2. Explain the same idea to Codex.
3. Explain it again to Grok or Gemini.
4. Read several long answers.
5. Manually synthesize the best parts.
6. Re-explain the chosen direction to an implementation agent.
7. Wait while one agent works in the active repo.
8. Inspect logs, run the app, ask for fixes, and repeat.

This workflow breaks in four ways.

### 2.1 Serial Execution on Parallel-Capable Tools

The user's agents can work in parallel, but the user's repo usually cannot.
Running several agents in the same working directory causes file collisions,
dirty git status, port conflicts, broken dev servers, dependency churn, and
merge confusion.

Most users respond by running one agent at a time. That makes their expensive
agent bench behave like a single synchronous command.

### 2.2 The Human Is Still the Synthesis Layer

Multi-model tools can show several answers side by side, but side by side is
not synthesis. Reading five answers is five times the work unless the system
detects consensus, preserves dissent, and asks the human only for meaningful
decisions.

The user does not want more text. They want:

- one verdict when the models agree;
- a minority report when they do not;
- a button that turns the chosen direction into implementation.

### 2.3 Paid Capacity Expires Unused

Many builders pay for multiple subscriptions and plans. These plans often have
usage windows, caps, quotas, or practical limits. Unused capacity expires. The
builder is paying for a bench of workers, but the workers sit idle because
coordinating them requires attention.

The product opportunity is not only "save time." It is:

> harvest capacity the customer already bought before it resets.

### 2.4 The Best Moment Is Not Captured

When the user chooses between competing drafts, that decision contains enormous
signal:

- what "premium" means to them;
- whether they prefer bold or conservative changes;
- whether they value visual polish over architecture purity;
- which agent they trust for which work;
- which tradeoffs match their product instincts.

Existing tools lose that data. Allnighter should treat every pick as durable
preference data.

---

## 3. Target User

### 3.1 Primary Persona: Solo Vibe Builder

The primary user is an independent builder or tiny team founder who ships real
software with AI agents as their default workforce.

They likely:

- own a Mac that can run local dev environments;
- use an iPhone constantly;
- pay for multiple AI coding tools or subscriptions;
- already ask several models the same important question;
- prefer outcomes, previews, and working software over raw diffs;
- are comfortable installing a Mac app, connecting a repo, and authorizing CLI
  tools;
- want progress while away from the desk.

They are not necessarily a beginner. They may be technical, semi-technical, or
deeply technical. The shared behavior is that they want to manage AI work at a
higher level than "watch this terminal."

### 3.2 Secondary Persona: Power Solo Developer

This user reads code and understands git, but still wants the throughput
multiplier:

- spawn three implementations without preparing three worktrees manually;
- compare running versions on a large Mac screen;
- send a winning direction to implementation;
- land clean branches faster;
- control the bench from phone when away.

For this user, Allnighter is also killer on Mac. The Mac app saves the boring
setup time around worktrees, ports, commands, previews, and branches. Even a
developer with only one Claude subscription benefits because "three lockups
now" is faster than three manual prompts, folders, branches, and preview
servers.

### 3.3 Explicit Non-Goals for v1

- Enterprise procurement.
- Team permissions.
- Compliance-heavy audit requirements.
- Multi-developer merge governance.
- Production deployment automation.
- Windows or Linux runners.
- Hosted model resale.
- General non-coding research as the main category.

---

## 4. Positioning

### 4.1 Primary Line

> You already pay for the team. We make it show up to work.

### 4.2 Supporting Lines

- "Your AI team pulls the all-nighter. You don't."
- "Keep your AI coding team busy."
- "Ask your whole bench. Pick the best answer. Ship it."
- "From one idea to three options to implemented work."
- "Allnighter gives every task its own safe lane, assigns it to the best
  available agent, and brings finished drafts back to your phone."

### 4.3 Category

Agent operations for solo builders.

Not:

- remote terminal;
- chat aggregator;
- IDE clone;
- hosted agent;
- model reseller.

### 4.4 Core Differentiation

Allnighter owns the missing middle:

```text
intent -> parallel options -> selected direction -> isolated implementation
-> preview/proof -> landing -> learned preference
```

Most AI products own only one side:

- chat tools produce options but do not execute them;
- IDE agents execute but do not fan out, synthesize, or harvest quota;
- vendor tools run one vendor's agents;
- cloud app builders produce previews but do not coordinate the user's own
  installed local tools and subscriptions.

---

## 5. Strategic Theses

### T1 - Utilization Arbitrage

The customer has prepaid capacity that expires. Allnighter's job is to make
idle capacity visible and actionable.

The headline metric is not "messages sent" or "sessions connected." It is:

```text
agent-hours converted into reviewable progress
```

### T2 - Neutrality Is Structural

The model labs cannot be the neutral manager. A vendor has no incentive to put
its competitors into the same picker, route work away from itself when it is
quota-constrained, or preserve a cross-provider scorecard.

Allnighter can be neutral because it runs on the user's machine and coordinates
tools the user installed and authenticated.

### T3 - The Execution Substrate Is the Barrier

The moat begins with hard local infrastructure:

- hidden worktrees;
- branch management;
- port brokering;
- preview capture;
- process supervision;
- agent drivers;
- artifact storage;
- landing queues.

This is not a weekend chat wrapper. The simple UI is powered by a local
concurrency factory.

### T4 - Parallel Judgment Before Execution

The biggest unlock is not only parallel coding. It is parallel judgment:

- three product strategies;
- three implementation plans;
- three UI directions;
- three pricing arguments;
- three architecture proposals;
- three code changes.

Then:

```text
Pick this one and implement it.
```

That button is the bridge from thinking to doing.

### T5 - Selection Data Compounds

The user thinks they are choosing drafts. They are actually training a personal
judgment model.

Early product:

- log preference events;
- summarize repeated preferences into project memory;
- inject them into future prompts.

Later product:

- pairwise ranking;
- agent-specific routing;
- speculative builds;
- first-draft win rate optimization.

### T6 - Intelligence Commoditizes, Orchestration Endures

If local models become Sonnet-class on consumer hardware, that is not a threat
to Allnighter. It is the strongest version of the Allnighter future.

As model quality rises and inference cost falls, the bottleneck moves away from
"can the model do useful work?" and toward:

- what should run next;
- which worker should do it;
- which answer should be trusted;
- where models genuinely disagree;
- which draft matches this user's taste;
- when work is ready to land;
- how much human attention should be spent.

Better, cheaper, local, unlimited intelligence makes attention relatively more
scarce. Allnighter is built around spending less human attention per unit of
shipped work.

This reframes local AI. Local models are not merely cheap interns for grunt
work. As they improve, they become the workforce. The durable business is the
operating layer that coordinates that workforce and the taste graph that teaches
it what "good" means for this user.

The serving layers are not the main competitor. Ollama, LM Studio, llama.cpp,
and MLX-style tools answer:

```text
How do I run a model?
```

Allnighter answers:

```text
What should the workers do, how do their outputs converge, and which result
should become shipped product?
```

### T7 - Mac and iPhone Are Both First-Class

The iPhone creates the habit: capture ideas, approve decisions, check morning
progress, keep the team moving while away.

The Mac creates the power: large-screen comparison, local repo access, direct
preview, process control, and deep development context.

The product should not be "Mac runner hidden behind iOS." It should be two
excellent apps:

- **Allnighter Mac:** the factory and command center.
- **Allnighter iOS:** the floor manager and daily ritual.

---

## 6. Product Principles

1. **Hide the plumbing.** Say lane, draft, worker, landing, preview. Do not say
   worktree, rebase, detached head, or port collision in core UX.
2. **Prefer artifacts over logs.** Show screenshots, previews, recordings,
   tests, summaries, and QA results before terminal output.
3. **Make decisions rewarding.** Picking a winner should feel like unlocking
   progress, not clearing an inbox.
4. **One tap should move the night.** A single decision can dispatch work,
   continue a lane, merge a result, or spawn a generation.
5. **Do not blind-merge by default.** Finished work earns trust through tests,
   previews, conflict status, and risk tiers.
6. **Use agents for what they are good at.** Let them brainstorm, critique,
   build, test, summarize, and repair. Do not reduce them to code writers.
7. **Keep the bench busy, but respect boundaries.** Standing orders, quiet
   hours, protected paths, spend ceilings, and repo enrollment define the safe
   operating envelope.
8. **Every pick is data.** Preferences must be logged, exportable, deletable,
   and reused.
9. **Design for churn.** Agent CLIs, auth flows, and limits will change.
   Drivers must be thin, versioned, smoke-tested, and updateable.
10. **Make the Mac feel magic too.** Large-screen multi-draft comparison,
    instant worktree spawning, preview grids, and one-click implementation are
    not secondary. They are core to builder delight.

---

## 7. System Architecture

### 7.1 High-Level Diagram

```text
                    +-----------------------------+
                    |       Allnighter iOS        |
                    | capture, feed, morning pull |
                    +--------------+--------------+
                                   |
                         local network / relay
                                   |
                    +--------------v--------------+
                    |       Allnighter Mac        |
                    | factory, command center     |
                    +--------------+--------------+
                                   |
          +------------------------+------------------------+
          |                        |                        |
 +--------v--------+      +--------v--------+      +--------v--------+
 | Lane A          |      | Lane B          |      | Lane C          |
 | Claude Code     |      | Codex CLI       |      | Grok/Gemini     |
 | branch + port   |      | branch + port   |      | branch + port   |
 +-----------------+      +-----------------+      +-----------------+
```

### 7.2 Allnighter Mac App

The Mac app is not merely a background helper. It is the factory, local source
of truth, and command center.

Responsibilities:

- repo enrollment;
- agent detection and authentication checks;
- lane creation and cleanup;
- git worktree lifecycle;
- process supervision;
- agent driver execution;
- local state store;
- preview servers and port broker;
- artifact capture;
- test/build runner;
- QA worker orchestration;
- landing queue;
- quota estimation;
- local API for iOS;
- optional relay connection;
- large-screen draft comparison;
- diagnostics and recovery tools.

Suggested target:

```text
Apps/AllnighterMac/
```

Distribution:

- direct download, notarized DMG/PKG;
- unsandboxed by design because it must run local developer tools;
- menu bar presence by default;
- full command-center window available anytime.

### 7.3 Allnighter iOS App

The iOS app is the mobile floor manager.

Responsibilities:

- capture ideas by text, voice, screenshots, share sheet, and Siri/App Intents;
- show backlog and active lanes;
- compare races and council outputs;
- let the user pick, combine, challenge, remix, or implement;
- host the landing queue;
- present Morning Pull;
- surface push notifications and Live Activities;
- keep decisions to one or two taps whenever possible.

Suggested target:

```text
Apps/AllnighterIOS/
```

Distribution:

- TestFlight first;
- App Store later;
- connects to the user's Mac directly where possible;
- uses relay only for messaging/push/tunnel when needed.

### 7.4 Shared Package

Shared models, API messages, and state machine types should live in a Swift
package used by both apps.

Suggested target:

```text
Packages/AllnighterCore/
```

Owns:

- project model;
- task model;
- lane model;
- agent model;
- race model;
- council model;
- artifact model;
- landing model;
- preference event model;
- API message schemas;
- status enums;
- risk tier enums;
- driver capability metadata.

### 7.5 Relay

v1 can begin local-first, but the intended product likely needs a thin relay for
mobile usefulness away from home.

Relay responsibilities:

- device pairing metadata;
- push notifications;
- command delivery when direct connection is unavailable;
- optional preview tunneling;
- status heartbeats;
- no code storage by default.

Relay must not become the source of repo truth. The Mac owns execution state.

### 7.6 Parallel Team Execution Contract

The product should be organized so separate Mac and iOS teams can work at the
same time without blocking each other.

The contract between teams is `AllnighterCore`:

- shared models;
- JSON fixtures;
- API message schemas;
- state machines;
- Works Test scenarios.

The Mac team can build against fixture commands from `AllnighterCore` before
the iOS app is ready. The iOS team can build against fixture projects, lanes,
races, councils, and landing cards before the Mac runner is fully operational.

Minimum shared fixtures:

```text
Fixture A: one project, no lanes, three available workers.
Fixture B: one active single-agent lane.
Fixture C: one three-way race with screenshots.
Fixture D: one council verdict with dissent.
Fixture E: one green landing card.
Fixture F: one assisted landing card.
Fixture G: one Morning Pull digest.
```

API surfaces should be contract-first:

- `GET /projects`
- `GET /projects/:id`
- `POST /projects/:id/tasks`
- `POST /tasks/:id/dispatch`
- `POST /tasks/:id/race`
- `POST /tasks/:id/council`
- `POST /races/:id/pick`
- `POST /outputs/:id/implement`
- `POST /lanes/:id/stop`
- `POST /landings/:id/land`
- `GET /events/stream`

The first integration milestone is not visual polish. It is:

```text
iOS sends Dispatch Race -> Mac creates lane records -> iOS receives lane events.
```

---

## 8. Lane System: The Magic in the Background

### 8.1 User-Facing Concept

The user sees:

- "Draft";
- "Lane";
- "Worker";
- "Ready to land";
- "Abandoned";
- "Kept";
- "Remix";
- "Implementing."

The user does not see:

- "git worktree";
- "branch checkout";
- "merge-base";
- "rebase";
- "port collision";
- "detached HEAD."

### 8.2 Technical Concept

Each lane is a complete isolated workspace for one task attempt.

On dispatch, the Mac app creates:

- a git branch;
- a git worktree folder outside the user's active repo;
- a lane metadata record;
- a log directory;
- an artifact directory;
- a unique port allocation;
- a process supervision group;
- a preview URL;
- optional dependency/cache isolation.

Example hidden layout:

```text
~/Library/Application Support/Allnighter/
  Projects/
    project_<id>/
      config.json
      state.sqlite
      Worktrees/
        lane_20260612_231422_claude_dashboard/
        lane_20260612_231427_codex_dashboard/
        lane_20260612_231431_grok_dashboard/
      Artifacts/
        lane_20260612_231422_claude_dashboard/
          screenshot_001.png
          preview_recording.mov
          test_result.json
          summary.md
          transcript.redacted.jsonl
      Logs/
        lane_20260612_231422_claude_dashboard/
          agent.stdout.log
          agent.stderr.log
          supervisor.log
```

Example git command, hidden behind the app:

```bash
git worktree add \
  "$ALLNIGHTER_PROJECT_ROOT/Worktrees/lane_20260612_231422_claude_dashboard" \
  -b "allnighter/lane_20260612_231422_claude_dashboard"
```

The core invariant:

> No agent writes to the user's active working directory.

### 8.3 Lane State Machine

```text
created
-> preparing
-> running
-> awaiting_input
-> building_preview
-> qa_running
-> ready
-> landing
-> landed
```

Failure states:

```text
failed
blocked
conflicted
killed
abandoned
expired
```

### 8.4 Branch Naming

Branch names should be deterministic, readable, and collision-resistant:

```text
allnighter/<task-slug>/<short-lane-id>
allnighter/dashboard-premium/a17f9c
allnighter/auth-rotation/b93d2e
```

### 8.5 Port Broker

Every lane may need one or more ports:

- app preview;
- API server;
- storybook;
- test harness;
- mock server.

The port broker assigns stable ports per lane and exposes a friendly URL:

```text
http://localhost:43120/lane/a17f9c
```

When the phone is local:

```text
http://macbook-pro.local:43120/lane/a17f9c
```

When remote:

```text
https://preview.allnighter.io/p/<paired-device>/<lane-id>
```

The relay/tunnel layer must never require source code upload.

### 8.6 Dependency Strategy

v1 should avoid overengineering dependency isolation. Start with worktree-level
filesystem isolation and document expected behavior:

- each lane can run install/build commands independently;
- node_modules or derived data may be shared only when safe;
- if dependency installs conflict, lane-level caches can be introduced.

Future:

- per-project package-manager cache policies;
- Nix/devcontainer integration;
- Xcode DerivedData per lane;
- lane resource budgeting.

### 8.7 Lane Cleanup

After landing or abandonment:

- keep lane artifacts for retention window;
- remove worktree after user-configurable delay;
- prune git worktree metadata;
- optionally delete local branch after merge;
- preserve preference and outcome data.

Default retention:

- worktree: 7 days;
- artifacts: 30 days;
- summaries/preference events: indefinite until user deletes project data.

---

## 9. Agent Fleet and Integration Levels

Allnighter should support workers by capability, not by equal depth of
integration.

### 9.1 Worker Capability Levels

| Level | Name | Capabilities | Example Targets |
| --- | --- | --- | --- |
| 1 | Headless CLI worker | launch, prompt, stream, stop, detect completion | Claude Code, Codex CLI, Grok Build, Gemini CLI, Aider |
| 2 | Protocol worker | structured protocol, approvals, events, resumable sessions | ACP, app-server, SDK-driven agents |
| 3 | IDE handoff worker | open lane in IDE, optionally receive task context | Cursor, Antigravity, VS Code extensions |
| 4 | UI automation worker | controlled through accessibility or browser automation | experimental only |

v1 should focus on Level 1 and Level 2. Level 3 can still be valuable because
opening a prepared lane in Cursor or Antigravity saves real time even if
Allnighter cannot fully automate the IDE.

### 9.2 Agent Driver Definition

Each driver declares:

```json
{
  "id": "claude_code",
  "display_name": "Claude Code",
  "capability_level": "headless_cli",
  "detect_command": "claude --version",
  "smoke_test_command": "claude -p \"Reply with ALLNIGHTER_READY\"",
  "launch_template": "claude -p {{prompt}}",
  "supports_streaming": true,
  "supports_json_events": false,
  "supports_resume": true,
  "supports_approval_mode": true,
  "supports_quota_estimate": "best_effort",
  "default_categories": ["planning", "refactor", "architecture", "copy"]
}
```

The driver layer must remain thin. It should translate Allnighter work orders
into agent-specific launch commands and translate outputs back into normalized
events.

### 9.3 Agent Scorecard

Allnighter should learn which worker wins for which type of work.

Scorecard dimensions:

- win rate by category;
- first-pass test pass rate;
- preview boot success rate;
- average task duration;
- average number of human interventions;
- landing success rate;
- revert rate;
- user rating/pick rate;
- quota cost where knowable.

Example:

```json
{
  "agent_id": "codex_cli",
  "category_scores": {
    "tests": { "wins": 8, "losses": 2, "avg_minutes": 14 },
    "ui": { "wins": 3, "losses": 7, "avg_minutes": 21 },
    "planning": { "wins": 5, "losses": 4, "avg_minutes": 6 }
  },
  "landing_success_rate": 0.91,
  "revert_rate": 0.03
}
```

### 9.4 Cursor and Antigravity

IDE-first tools should be treated as lane consumers first, not guaranteed
headless workers.

Initial integration:

- create lane;
- open lane in Cursor/Antigravity;
- write a work-order markdown file into the lane;
- copy prompt to clipboard or use extension/deeplink if available;
- track branch/artifacts once changes appear.

Future integration:

- extension bridge;
- command palette integration;
- structured agent run API if vendor exposes one;
- local plugin that calls Allnighter APIs.

The product should not depend on brittle UI automation for core flows.

### 9.5 Local Workers

Local model runtimes should be treated as worker sources, not competitors.

Allnighter should not try to become a local model runner. It should integrate
with local runners and make them useful inside the same operating system as
cloud subscriptions, CLI agents, and IDE agents.

Initial targets:

- Ollama;
- LM Studio;
- llama.cpp server;
- MLX-backed servers or wrappers;
- any OpenAI-compatible local endpoint.

The user-facing idea:

> Put your Mac Studio on the night shift.

Local workers matter in two time horizons.

Near term:

- council participant;
- judge and summarizer;
- QA interpreter;
- backlog miner;
- preference-memory synthesizer;
- low-risk draft worker.

Long term:

- frontier-class local implementation worker;
- always-on speculative builder;
- private repo reasoning engine;
- multi-machine local bench;
- default first-pass worker when quality is sufficient.

Local workers should use the same abstractions as every other worker:

- scorecard;
- capability level;
- task categories;
- lane eligibility;
- risk tier;
- power/thermal constraints;
- privacy badge;
- model/runtime health.

Example local worker config:

```json
{
  "id": "mac_studio_local_qwen",
  "display_name": "Mac Studio Local",
  "driver_id": "openai_compatible_local",
  "base_url": "http://mac-studio.local:1234/v1",
  "model": "qwen-coder-local",
  "capability_level": "local_model",
  "privacy": "local_only",
  "default_roles": ["council", "summarizer", "qa", "memory"],
  "implementation_enabled": false,
  "power_policy": "only_when_idle_or_plugged_in"
}
```

Important distinction:

```text
The runtime runs one model.
Allnighter decides what work should be done, compares outputs, records picks,
lands results, and learns the user's judgment.
```

---

## 10. Work Orders

A work order is the normalized instruction packet sent to a worker.

### 10.1 Work Order Sources

- typed prompt;
- voice note;
- screenshot annotation;
- share sheet item;
- GitHub issue;
- TODO comment;
- failed test;
- Sentry issue;
- App Store review;
- council verdict;
- race winner;
- standing order;
- speculative build suggestion.

### 10.2 Work Order Shape

```json
{
  "id": "wo_01H...",
  "project_id": "project_kansobooks",
  "title": "Make the dashboard feel more premium",
  "category": "ui",
  "intent": "Improve visual polish of the dashboard without changing information architecture.",
  "acceptance_criteria": [
    "Dashboard still shows all existing metrics.",
    "No navigation changes.",
    "Light and dark mode still work.",
    "Provide screenshot before marking ready."
  ],
  "constraints": [
    "Do not touch billing.",
    "Keep copy concise.",
    "Prefer subtle motion."
  ],
  "context_refs": [
    "project_memory",
    "style_preferences",
    "recent_rejections",
    "screenshots/current_dashboard.png"
  ],
  "dispatch_mode": "race",
  "requested_agents": ["claude_code", "codex_cli", "grok_build"],
  "created_from": "ios_voice_capture",
  "created_at": "2026-06-12T22:45:00Z"
}
```

### 10.3 Interpretation Step

Before dispatch, capture should become an editable interpretation:

```text
Here's what I understood:

You want three different directions for making the dashboard feel more premium.
Keep the existing content and navigation. Prefer polished, practical UI over
marketing-style redesign. Each worker should produce a running preview and a
short explanation of the direction.

Dispatch as a 3-way race?
```

Buttons:

- Dispatch;
- Edit;
- Ask council first;
- Save to backlog.

---

## 11. Core Product Loops

### 11.1 Loop A: Single-Agent Night Factory

Use case:

The user has a backlog of small implementation tasks and one available worker.

Flow:

1. User captures or selects task.
2. Mac app creates lane.
3. Router picks available worker.
4. Agent executes in lane.
5. Mac app runs tests/build/preview.
6. QA worker optionally checks result.
7. iOS/Mac shows ready-to-land card.
8. User lands, asks for changes, or abandons.

Value:

- works even with one subscription;
- proves the lane system;
- creates the "wake up to progress" moment.

### 11.2 Loop B: Draft Race

Use case:

The user wants options, not a single answer.

Flow:

1. User asks: "Make the dashboard feel more premium."
2. Allnighter creates three lanes from the same base commit.
3. Router assigns workers.
4. Each worker builds a different implementation.
5. Mac app boots each preview on a separate port.
6. Artifact collector captures screenshots/videos.
7. iPhone shows swipeable cards; Mac shows a comparison grid.
8. User taps:
   - Keep This One;
   - Implement This;
   - Combine;
   - Remix;
   - Challenge;
   - More Like This.

Important:

"Keep This One" can mean several things depending on output type:

- for a running code draft: promote to landing queue;
- for a strategy answer: turn into work order;
- for a mockup: implement the mockup in a lane;
- for a partial plan: ask a worker to complete it.

### 11.3 Loop C: Council Before Build

Use case:

The user has an ambiguous product, architecture, pricing, or feature question.

Flow:

1. User asks: "Should we add team accounts before billing analytics?"
2. Council fans out to several models.
3. Each model answers independently.
4. Critique round: models red-team the other answers.
5. Synthesis round produces:
   - recommended verdict;
   - strongest dissent;
   - decision points;
   - implementation implication.
6. User taps:
   - Accept verdict;
   - Pick dissent;
   - Ask another round;
   - Implement this.

The council is not just chat. It is pre-execution judgment.

### 11.4 Loop D: Picker as Prompt

Use case:

The user chooses an option and wants it built immediately.

Flow:

1. User reviews three strategies or mockups.
2. User taps "Implement This."
3. Allnighter creates or reuses a lane.
4. The selected output becomes the work order.
5. Any voice/text note is appended.
6. Worker starts within 5 seconds.
7. Lane appears immediately in active work.

This is the killer handoff:

```text
thinking -> deciding -> doing
```

No re-explaining. No copy-paste. No second prompt.

### 11.5 Loop E: Combine and Synthesize

Use case:

The user likes parts of several drafts.

Flow:

1. User selects "Claude's layout" and "Grok's animations."
2. Allnighter creates a synthesis work order.
3. A landing/synthesis worker checks out a fresh lane.
4. It applies selected ideas with full context.
5. Result returns as a new draft.

### 11.6 Loop F: Morning Pull

Use case:

The user opens the app in the morning.

Morning Pull includes:

- landed work summary;
- ready-to-land drafts;
- races needing a winner;
- council disagreements;
- failed lanes needing a decision;
- speculative builds;
- quota harvested;
- agent-hours worked.

The emotional goal:

> opening Allnighter should feel like seeing what the team made, not clearing an
> error queue.

### 11.7 Loop G: Speculative Builds

Use case:

Agents are idle and the user has opted into proactive work.

Flow:

1. Scheduler sees idle capacity.
2. Standing orders allow speculation.
3. System scans approved sources:
   - GitHub issues;
   - TODOs;
   - failed tests;
   - Sentry;
   - app reviews;
   - previous user notes.
4. It proposes or builds draft-tier work.
5. Morning Pull says:

```text
I noticed onboarding drop-off and drafted two lighter signup flows on spec.
Keep either?
```

Speculative builds must always be clearly labeled and easy to discard.

---

## 12. Mac App Requirements

The Mac app should be a full product, not only a daemon.

### 12.1 Mac App Surfaces

#### Menu Bar

Shows:

- factory status;
- active lanes count;
- idle workers;
- current quota window;
- quick capture;
- pause/resume all;
- open command center.

#### Command Center Window

Primary Mac app.

Tabs:

1. Projects
2. Backlog
3. Active Lanes
4. Races
5. Councils
6. Landing Queue
7. Workers
8. Preferences
9. Diagnostics

#### Project Detail

Shows:

- repo status;
- enrolled agents;
- current branch;
- active lanes;
- recent artifacts;
- protected paths;
- standing orders;
- preview commands;
- test commands.

#### Race Comparison Grid

Mac-specific magic:

- large screen grid of drafts;
- synchronized preview windows;
- screenshot/video comparison;
- summary and test status;
- keyboard shortcuts:
  - 1/2/3 to select;
  - C to combine;
  - I to implement;
  - L to land;
  - R to remix;
  - Space to open preview.

This view is a product wedge by itself. Today, even a strong builder with a
single Claude subscription has to manually create branches, copy prompts, run
preview servers, and compare browser tabs to get several design lockups. The
Mac app should reduce that to one command:

```text
Make three directions for the dashboard.
```

Then:

- create the lanes;
- run the attempts;
- boot the previews;
- arrange the comparison grid;
- let the user select, combine, implement, or land.

#### Lane Inspector

Advanced view:

- status timeline;
- process logs;
- transcript;
- generated summary;
- artifacts;
- git diff;
- test results;
- branch details;
- kill/retry controls.

### 12.2 Mac Functional Requirements

| ID | Requirement |
| --- | --- |
| MAC-1 | Enroll local git repositories explicitly. |
| MAC-2 | Detect dirty main working tree and explain that lanes will not touch it. |
| MAC-3 | Create, track, and clean up hidden worktree lanes. |
| MAC-4 | Launch agent drivers in lane working directories. |
| MAC-5 | Stream normalized lane events into local state. |
| MAC-6 | Run project-specific setup, build, test, and preview commands. |
| MAC-7 | Capture screenshots/videos of previews. |
| MAC-8 | Allocate unique ports per lane. |
| MAC-9 | Expose local API for iOS and relay. |
| MAC-10 | Show race comparisons natively on Mac. |
| MAC-11 | Support "Implement This" from Mac-side council or race outputs. |
| MAC-12 | Support landing queue and one-tap revert. |
| MAC-13 | Support global pause/kill switch. |
| MAC-14 | Maintain worker scorecards. |
| MAC-15 | Maintain preference ledger and project memory. |
| MAC-16 | Run driver smoke tests and show worker health. |
| MAC-17 | Communicate quota estimates honestly as estimates. |
| MAC-18 | Keep code local unless a user enables a relay/tunnel feature that requires metadata transfer. |

### 12.3 Mac Works Test

```text
Given a local repo with a simple web app
and one authenticated agent
when the user asks for "three dashboard lockups"
then Allnighter creates three lanes,
runs three agent attempts,
boots three previews on different ports,
captures screenshots,
shows them in a Mac comparison grid,
and lets the user choose one and send it to landing.
```

### 12.4 Mac-First Killer Workflows

These are valuable even before the iPhone app is polished.

#### Three Lockups Now

```text
User types in the Mac app:
"Give me three different dashboard lockups."

Allnighter:
- creates three lanes;
- runs available workers sequentially or concurrently;
- starts previews;
- captures screenshots;
- shows a comparison grid.

User:
- clicks the winner;
- clicks Implement This or Keep and Land.
```

This is faster than today's manual workflow even with one worker, because the
app handles lane creation, branch naming, preview ports, artifact capture, and
comparison.

#### Strategy to Build

```text
User asks:
"What is the best onboarding change to reduce drop-off?"

Allnighter:
- runs a council;
- returns verdict plus dissent;
- user clicks Implement This;
- chosen direction becomes a work order;
- a lane starts building immediately.
```

#### Cursor/IDE Handoff

```text
User asks:
"Try a more playful settings screen in Cursor."

Allnighter:
- creates a lane;
- writes the work order into the lane;
- opens the lane in Cursor;
- tracks branch, artifacts, and landing separately from main.
```

The Mac app should make this feel native even when the downstream IDE is doing
part of the work.

---

## 13. iOS App Requirements

The iOS app should feel like managing a capable team from anywhere.

### 13.1 iOS App Surfaces

#### Capture

Input modes:

- text;
- voice;
- screenshot;
- Share Sheet;
- camera/photo;
- Siri/App Intent;
- pasted URL or issue.

Capture converts raw intent into a structured work order.

#### Home

Shows:

- active agent-hours today;
- workers idle/busy;
- top pending decisions;
- next quota reset;
- Morning Pull entry point;
- quick dispatch.

#### Backlog

Shows:

- pending tasks;
- suggested tasks;
- standing-order tasks;
- source labels;
- priority;
- dispatch mode.

Actions:

- dispatch;
- race;
- council;
- schedule overnight;
- pin worker;
- delete.

#### Active Lanes

Shows:

- worker;
- task;
- status;
- elapsed time;
- current phase;
- latest artifact;
- stop/retry/nudge controls.

#### Race Review

Phone-native comparison:

- swipeable drafts;
- screenshots first;
- live preview button;
- one-paragraph summary;
- test status;
- QA note;
- key actions.

Actions:

- Keep This One;
- Implement This;
- Combine;
- Remix;
- Challenge;
- More Like This;
- Discard All.

#### Council Verdict

Shows:

- recommended answer;
- confidence/consensus;
- strongest dissent;
- decision cards;
- "Implement This" button;
- "Ask one more round" button.

#### Landing Queue

Shows:

- green land;
- assisted land;
- draft only;
- risk explanation;
- preview;
- tests;
- summary.

Actions:

- land;
- ask for changes;
- open on Mac;
- create PR;
- revert.

#### Morning Pull

Daily digest:

- agent-hours worked;
- finished drafts;
- races awaiting verdict;
- councils resolved;
- speculative suggestions;
- idle capacity warning;
- one-tap next actions.

### 13.2 iOS Functional Requirements

| ID | Requirement |
| --- | --- |
| IOS-1 | Pair with Mac app via local network or relay. |
| IOS-2 | Capture voice and text into editable work-order interpretation. |
| IOS-3 | Show project backlog and dispatch actions. |
| IOS-4 | Show active lanes with plain-language statuses. |
| IOS-5 | Render race drafts as swipeable cards with screenshots and preview links. |
| IOS-6 | Let the user choose, combine, remix, challenge, or implement. |
| IOS-7 | Let a selection immediately dispatch implementation. |
| IOS-8 | Show landing queue with risk tiers. |
| IOS-9 | Provide one-tap global pause/kill. |
| IOS-10 | Provide push notifications and Live Activities for long-running lanes. |
| IOS-11 | Batch notifications during quiet hours. |
| IOS-12 | Show Morning Pull as a rewarding daily ritual. |
| IOS-13 | Keep typing optional in core flows. |
| IOS-14 | Support Share Sheet capture from screenshots, notes, GitHub, browser, and app reviews. |
| IOS-15 | Never store agent secrets on device. |

### 13.3 iOS Works Test

```text
Given the Mac app is paired and online
when the user dictates "make three different premium dashboard directions"
and taps Dispatch Race
then the phone shows three active lanes,
later shows three draft cards with screenshots,
lets the user tap "Implement This" on one,
and shows that selected implementation continuing in the active lane list.
```

---

## 14. Shared State Model

### 14.1 Project

```json
{
  "id": "project_kansobooks",
  "name": "KansoBooks",
  "repo_path": "/Users/mike/Documents/GitHub/KansoBooks",
  "default_branch": "main",
  "enrolled_at": "2026-06-12T20:00:00Z",
  "protected_paths": ["Billing/", "Secrets/", ".env"],
  "standing_orders": [
    "Never touch billing without explicit approval.",
    "Always produce screenshots for UI changes.",
    "Prefer small reversible branches."
  ],
  "preview_command": "npm run dev -- --port {{PORT}}",
  "test_command": "npm test"
}
```

### 14.2 Task

```json
{
  "id": "task_dashboard_premium",
  "project_id": "project_kansobooks",
  "title": "Make dashboard feel more premium",
  "category": "ui",
  "status": "ready_to_dispatch",
  "priority": 3,
  "source": "ios_voice_capture",
  "dispatch_mode": "race",
  "acceptance_criteria": [],
  "created_at": "2026-06-12T22:45:00Z"
}
```

### 14.3 Lane

```json
{
  "id": "lane_a17f9c",
  "project_id": "project_kansobooks",
  "task_id": "task_dashboard_premium",
  "agent_id": "claude_code",
  "branch": "allnighter/dashboard-premium/a17f9c",
  "worktree_path": "~/Library/Application Support/Allnighter/Projects/project_kansobooks/Worktrees/lane_a17f9c",
  "base_commit": "abc123",
  "status": "ready",
  "ports": { "web": 43120 },
  "preview_url": "http://localhost:43120/lane/a17f9c",
  "artifact_ids": ["artifact_screenshot_001", "artifact_summary_001"],
  "risk_tier": "green_land"
}
```

### 14.4 Agent

```json
{
  "id": "claude_code",
  "display_name": "Claude Code",
  "driver_id": "claude_code_driver",
  "status": "available",
  "capability_level": "headless_cli",
  "last_smoke_test": "passed",
  "quota": {
    "kind": "estimated_window",
    "remaining": 0.61,
    "reset_at": "2026-06-13T02:00:00Z"
  }
}
```

### 14.5 Race

```json
{
  "id": "race_dashboard_premium",
  "task_id": "task_dashboard_premium",
  "lane_ids": ["lane_a17f9c", "lane_b93d2e", "lane_c44a11"],
  "status": "awaiting_pick",
  "winner_lane_id": null,
  "created_at": "2026-06-12T23:00:00Z"
}
```

### 14.6 Council Session

```json
{
  "id": "council_pricing_v1",
  "prompt": "Should we charge per connected agent or flat monthly?",
  "participants": ["claude_code", "codex_cli", "grok_build"],
  "status": "verdict_ready",
  "verdict": {
    "recommendation": "Flat monthly for v1; avoid pricing that punishes usage.",
    "consensus": 0.72,
    "minority_report": "Usage-based tiers may better map infrastructure costs if relay preview tunneling becomes expensive."
  }
}
```

### 14.7 Preference Event

```json
{
  "id": "pref_01H...",
  "project_id": "project_kansobooks",
  "event_type": "picked_winner",
  "context_type": "race",
  "chosen_lane_id": "lane_a17f9c",
  "rejected_lane_ids": ["lane_b93d2e", "lane_c44a11"],
  "user_note": "Best balance of polish and density.",
  "derived_memory": [
    "User prefers premium UI that preserves information density.",
    "Avoid oversized marketing-style dashboard redesigns."
  ],
  "created_at": "2026-06-13T07:15:00Z"
}
```

---

## 15. Landing Queue

### 15.1 Landing Tiers

| Tier | Meaning | Default Action |
| --- | --- | --- |
| Green land | tests pass, no conflicts, preview booted, no protected paths touched | one-tap land |
| Assisted land | conflicts, flaky tests, or uncertain preview | landing agent repairs and resubmits |
| Draft only | broad/risky change, protected paths, schema/billing/secrets, speculative work | branch/PR only |

### 15.2 Landing Card

Each landing card leads with:

- outcome summary;
- screenshot/preview;
- test result;
- QA result;
- risk tier;
- touched area summary;
- revert availability.

Diff is available but not the headline.

### 15.3 Landing Flow

```text
ready lane
-> classify risk
-> run merge simulation
-> run tests/build where configured
-> show landing card
-> user lands or asks for changes
-> merge selected branch into target branch
-> run post-merge check
-> create rollback metadata
```

### 15.4 Revert

Every land creates a reversible marker:

- merge commit SHA;
- branch name;
- task id;
- lane id;
- artifacts;
- summary.

One-tap revert creates a clean rollback commit. It must not silently reset or
delete user work.

---

## 16. Council, Races, and "Implement This"

### 16.1 Output Types

Allnighter should support multiple output types:

| Output Type | Example | Can Implement? |
| --- | --- | --- |
| Strategy | "Launch with flat pricing" | yes, by creating work orders |
| Plan | "Implement auth rotation in 4 steps" | yes |
| UI mockup | "Premium dashboard direction" | yes |
| Running code draft | "Dashboard v2 in lane A" | already implemented; land/remix |
| Copy | "Onboarding copy options" | yes |
| Architecture proposal | "Use local SQLite state store" | yes, if scoped |

### 16.2 Buttons

Core decision buttons:

- **Pick This:** record preference and mark as selected.
- **Implement This:** turn selected output into a work order or continue the
  existing lane.
- **Keep and Land:** for code drafts that are already complete.
- **Combine:** select parts of several outputs and synthesize.
- **Remix:** spawn variations from selected output.
- **Challenge:** ask another worker to critique the selected output.
- **More Like This:** record preference and spawn similar options.
- **Remember This:** store as durable project memory without dispatch.

### 16.3 Picker-As-Prompt Semantics

When the user taps "Implement This," Allnighter attaches:

- original prompt;
- selected output;
- rejected outputs when useful;
- user preference notes;
- project memory;
- acceptance criteria;
- lane context if already built;
- source artifacts;
- standing orders;
- protected paths.

The user should never need to copy/paste the chosen answer into a new prompt.

### 16.4 Latency Target

Tap to confirmed dispatch:

```text
under 5 seconds
```

If agent startup is slow, the UI still immediately creates the lane record and
shows "preparing."

---

## 17. Taste and Judgment Model

The first version is not a custom ML model. It is a preference ledger plus
memory synthesis.

### 17.1 Preference Inputs

- picks;
- rejections;
- split verdicts;
- remixes;
- "more like this";
- reverts;
- manual ratings;
- notes attached to selections;
- repeated edits after landing;
- agent win/loss outcomes.

### 17.2 Derived Memory

Periodically summarize preference data into project memory:

```text
For KansoBooks, the user prefers:
- dense operational screens over sparse marketing layouts;
- restrained motion;
- small reversible changes;
- practical copy;
- screenshots before long summaries;
- tests for calculation logic before UI polish.
```

### 17.3 Uses

Preference memory influences:

- prompt seasoning;
- council judge weighting;
- race participant selection;
- route planning;
- speculative task ranking;
- risk classification;
- first-draft attempts.

### 17.4 User Control

The user can:

- inspect memory;
- edit memory;
- delete memory;
- export preference data;
- disable preference learning per project.

---

## 18. Quota Harvester

### 18.1 Purpose

The scheduler exists to prevent paid agent capacity from expiring unused.

### 18.2 Inputs

- agent availability;
- estimated quota remaining;
- reset time;
- user spend ceiling;
- quiet hours;
- machine power state;
- backlog;
- task size estimate;
- standing orders;
- user priority.

### 18.3 Behaviors

- show idle workers;
- suggest dispatches;
- auto-dispatch only when explicitly enabled;
- prefer small tasks near reset windows;
- avoid starting long tasks when the machine is likely to sleep;
- avoid waking the user unless a task is explicitly configured to interrupt.

### 18.4 Honest Estimation

Many vendors may not expose exact quota APIs. UI copy must say "estimated" when
the value is estimated.

Bad:

```text
Claude has 42% remaining.
```

Better:

```text
Claude looks about 40% unused in this window.
```

---

## 19. Safety and Trust

### 19.1 Protected Paths

Per project:

- secrets;
- env files;
- billing;
- auth;
- migrations;
- production deploy config;
- legal/compliance text;
- user-selected paths.

If touched:

- halt lane or downgrade to draft-only;
- explain why;
- require explicit approval to continue.

### 19.2 Standing Orders

Examples:

- "When idle, write tests."
- "Never touch billing."
- "Always screenshot UI changes."
- "Do not change database schema without asking."
- "Prefer small branches."
- "Use feature flags for risky changes."

Standing orders are applied:

- before dispatch;
- during prompt construction;
- before landing.

### 19.3 Kill Switch

The phone and Mac must both have a global stop:

```text
Stop all work
```

It should:

- send termination to all supervised processes;
- mark lanes as killed;
- keep worktrees intact for inspection;
- never touch main branch.

### 19.4 Secrets

Rules:

- iOS never stores agent credentials;
- relay never stores code by default;
- transcripts are redacted before phone display;
- env files are protected by default;
- artifacts are scanned for obvious secrets before sync/tunnel.

---

## 20. Phasing and Build Plan

The product should be built as parallel Mac, iOS, Shared Core, and Relay tracks
so two or more teams can execute at the same time.

### Phase 0 - Product Pivot Lock

Goal:

Define Allnighter as separate product direction.

Slices:

1. Decide whether Allnighter replaces CLI Loci or becomes a branch.
2. Rename product vocabulary in SSOT if pivot is accepted.
3. Create build folders:
   - `Packages/AllnighterCore/`
   - `Apps/AllnighterMac/`
   - `Apps/AllnighterIOS/`
4. Define first Works Test.

### Phase 1 - Shared Core Spine

Owner: Shared Core team.

Slices:

1. Define Codable models for Project, Task, Lane, Agent, Race, Council,
   Artifact, Landing, PreferenceEvent.
2. Define lane state machine.
3. Define API envelope and event stream.
4. Define fixture examples for one race and one landing.
5. Add unit tests for state transitions.

Proof:

```text
swift test
```

### Phase 2 - Mac Repo Enrollment

Owner: Mac team.

Slices:

1. Create Mac app shell.
2. Add menu bar item.
3. Add repo picker/enrollment.
4. Detect git repo/default branch/status.
5. Store project config locally.
6. Show project detail page.

Works Test:

Enroll a local repo and show default branch, dirty status, and configured
commands.

### Phase 3 - Lane Manager

Owner: Mac team.

Slices:

1. Create hidden Allnighter project root.
2. Implement branch naming.
3. Implement `git worktree add`.
4. Implement lane cleanup.
5. Implement lane state persistence.
6. Add diagnostics for failed worktree creation.

Works Test:

Create three lanes from one repo without modifying the active working tree.

### Phase 4 - Agent Driver MVP

Owner: Mac team.

Slices:

1. Driver interface.
2. Shell command driver.
3. Claude Code driver.
4. Codex CLI driver.
5. Driver smoke tests.
6. Normalized event stream.

Works Test:

Run a trivial prompt in a lane and capture output as lane events.

### Phase 5 - iOS Pairing and Home

Owner: iOS team.

Slices:

1. iOS app shell.
2. Pair with Mac over local network.
3. Show Mac online/offline.
4. Show project list.
5. Show active lane list from fixtures/live API.
6. Add global stop button.

Works Test:

iPhone sees paired Mac and live lane status.

### Phase 6 - Capture to Work Order

Owner: iOS + Shared Core.

Slices:

1. Text capture.
2. Voice transcription hook.
3. Screenshot attachment.
4. Interpretation view.
5. Save to backlog.
6. Dispatch single task.

Works Test:

Dictate a task, confirm interpretation, and see it appear in Mac backlog.

### Phase 7 - Single-Agent Factory

Owner: Mac + iOS.

Slices:

1. Dispatch task to lane.
2. Run agent.
3. Capture logs.
4. Mark complete.
5. Show progress on iOS.
6. Show progress on Mac.

Works Test:

From iPhone, dispatch one task to one agent and see it finish in a lane.

### Phase 8 - Preview and Artifact System

Owner: Mac team.

Slices:

1. Project preview command config.
2. Port broker.
3. Preview process supervisor.
4. Screenshot capture.
5. Artifact storage.
6. Artifact API.

Works Test:

Lane boots preview on unique port and produces screenshot visible on Mac and
iOS.

### Phase 9 - Landing Queue Green Tier

Owner: Mac + Shared Core.

Slices:

1. Diff summary.
2. Test command execution.
3. Merge simulation.
4. Risk classifier v0.
5. Landing queue card.
6. One-tap merge.
7. Revert metadata.

Works Test:

Completed lane becomes green-tier card and lands into target branch with a
revert option.

### Phase 10 - Draft Race MVP

Owner: Mac + iOS.

Slices:

1. Dispatch one task to 2-3 lanes.
2. Assign one agent per lane.
3. Ensure identical base commit.
4. Collect artifacts per lane.
5. iOS swipeable race review.
6. Mac comparison grid.
7. Pick winner.

Works Test:

Ask for three dashboard lockups and receive three comparable drafts.

### Phase 11 - Picker as Prompt

Owner: Shared Core + Mac + iOS.

Slices:

1. Define selection event.
2. Define implement-this command.
3. Convert selected output to work order.
4. Attach user note.
5. Start or continue lane.
6. Record preference event.

Works Test:

Pick a strategy or draft and tap "Implement This"; a lane begins within 5
seconds.

### Phase 12 - Council MVP

Owner: Mac + Shared Core + iOS.

Slices:

1. Council prompt fan-out.
2. Critique round.
3. Synthesis round.
4. Verdict model.
5. Minority report.
6. iOS verdict card.
7. Mac council view.

Works Test:

Ask a feature strategy question, receive verdict plus dissent, and implement
the chosen direction.

### Phase 13 - Combine and Remix

Owner: Mac + iOS.

Slices:

1. Select elements from multiple drafts.
2. Create synthesis work order.
3. Spawn fresh lane.
4. Produce combined result.
5. Spawn variations from winner.

Works Test:

Choose "A's layout, B's animation" and receive a synthesized lane.

### Phase 14 - Worker Scorecards

Owner: Shared Core + Mac.

Slices:

1. Capture outcome metrics.
2. Calculate category scores.
3. Show worker roster.
4. Use scorecard in routing.
5. Let user pin worker.

Works Test:

Agent selection changes based on historical win/test/landing metrics.

### Phase 15 - Quota Harvester v1

Owner: Mac + iOS.

Slices:

1. Manual quota window config.
2. Estimated usage tracking.
3. Idle worker detection.
4. Reset-time nudge.
5. User ceilings.
6. Quiet hours.

Works Test:

As reset nears, Allnighter suggests backlog tasks sized to use idle capacity.

### Phase 16 - Preference Ledger and Memory

Owner: Shared Core + Mac + iOS.

Slices:

1. Log picks/rejections/splits/reverts.
2. Show preference history.
3. Summarize into project memory.
4. Let user edit/delete memory.
5. Inject memory into work orders.

Works Test:

After several picks, future work orders include user-approved preference
memory.

### Phase 17 - QA Worker

Owner: Mac team.

Slices:

1. Define QA work order.
2. Use Playwright or equivalent for web apps.
3. Click through lane preview.
4. Produce plain-language QA summary.
5. Attach QA result to landing card.

Works Test:

Completed UI lane includes "login works; settings fails on rotate" style QA
summary.

### Phase 18 - Relay and Push

Owner: Relay + iOS + Mac.

Slices:

1. Device identity.
2. Message queue.
3. Push notifications.
4. Remote command delivery.
5. Preview tunnel v0.
6. Relay privacy controls.

Works Test:

Phone away from LAN receives lane completion push and can send landing command
back to Mac.

### Phase 19 - Morning Pull

Owner: iOS + Mac.

Slices:

1. Daily digest generator.
2. Prioritization rules.
3. Rewarding card order.
4. Agent-hours summary.
5. Pending decisions.
6. Speculative suggestions placeholder.

Works Test:

Opening app in morning shows finished work, pending picks, and next actions in
one digest.

### Phase 20 - Speculative Builds v0

Owner: Mac + iOS.

Slices:

1. Toggle speculation per project.
2. Standing orders enforcement.
3. Source: TODO comments.
4. Source: GitHub issues.
5. Draft-only classification.
6. Morning Pull presentation.

Works Test:

When enabled and idle, Allnighter drafts a small test or TODO fix on spec and
labels it clearly.

### Phase 21 - Local Workers v0

Owner: Mac + Shared Core + iOS.

Goal:

Add local model runtimes as private workers in the same bench without making
Allnighter a model runner.

Slices:

1. Define local worker capability metadata.
2. Add OpenAI-compatible local server driver.
3. Detect Ollama or LM Studio where possible.
4. List available local models.
5. Run smoke prompt.
6. Add Local/private badge in Mac Workers.
7. Show local workers in iOS roster.
8. Use local worker for council summary or preference-memory synthesis.
9. Keep implementation disabled by default.

Works Test:

```text
Given Ollama or LM Studio is running on the user's Mac or Mac Studio
when the user opens Allnighter Mac Workers
then the app detects a local model server,
lists available models,
runs a smoke prompt,
and marks one model available as a private read-only worker.

When a council finishes,
then the local worker summarizes the verdict and dissent without sending that
summary job to a cloud model.
```

---

## 21. MVP Recommendation

The smallest lovable demo is not the full workforce manager. It is:

```text
one repo
one Mac
one iPhone
two or three agents if available
hidden lanes
three-way race
preview screenshots
pick one
implement or land it
```

The exact demo:

```text
User opens Allnighter on iPhone:
"Give me three different directions for making this dashboard feel premium."

Allnighter:
- creates three hidden lanes;
- assigns workers;
- runs each attempt;
- boots each preview;
- captures screenshots;
- shows three cards on phone and a grid on Mac.

User:
- taps the best one;
- says "but make the header sticky";
- taps Implement This.

Allnighter:
- continues selected lane or creates implementation lane;
- applies the note;
- runs tests;
- returns a landing card.
```

This proves:

- worktree factory;
- agent orchestration;
- artifact capture;
- iOS decision loop;
- Mac comparison loop;
- picker-as-prompt;
- preference logging.

---

## 22. Metrics

| Metric | Meaning |
| --- | --- |
| Agent-hours worked | Time agents spent doing useful lane work |
| Idle paid capacity | Estimated unused quota in current windows |
| Drafts produced | Number of completed lanes with artifacts |
| Drafts landed | Number of lanes merged or PR'd |
| First-draft win rate | Taste/routing model quality |
| Race pick rate | How often races produce a clear winner |
| Implement-this rate | How often ideas become execution |
| Landing success rate | Trust in merge system |
| Revert rate | Negative trust signal |
| Morning Pull opens | Habit formation |
| Time to first artifact | Onboarding magic metric |

---

## 23. Risks and Mitigations

| Risk | Severity | Mitigation |
| --- | --- | --- |
| Vendor ToS changes around subscription automation | High | Support driver substitutability, keep no resale model, add API-key modes, monitor terms |
| Agent CLIs churn | High | Versioned drivers, smoke tests, updateable driver manifests |
| One bad landing destroys trust | High | One-tap landing before auto-land, conservative tiers, protected paths, revert |
| Worktree cleanup deletes useful work | High | Retention windows, explicit abandon, no destructive git commands without metadata |
| Mac sleeps/offline | Medium | Power state warnings, resume lanes, clear offline state |
| Preview setup varies wildly | Medium | Per-project commands, templates, manual override |
| Quota estimates are wrong | Medium | Honest "estimated" UI, user ceilings |
| Too much UI before core factory works | Medium | Build lane manager and artifact loop first |
| Relay privacy concerns | Medium | Local-first default, no code storage, explicit toggles |
| Cold-start taste model is generic | Low | Lead with races and explicit picks |

---

## 24. Open Decisions

1. Product identity: does Allnighter replace CLI Loci or become a new product?
2. First worker pair: Claude + Codex, Claude + Grok, or Claude only plus shell
   driver?
3. First app type for demos: web app repo, SwiftUI app, or both?
4. Relay timing: local-only MVP first, or push/tunnel early?
5. Auto-land: exclude from v1 or make opt-in green-tier only?
6. Pricing: flat monthly, connected-agent tiers, or pro unlock?
7. Taste model storage: local-only v1 or optional encrypted cloud backup?
8. IDE integrations: Cursor/Antigravity handoff in v1 or after headless agents?
9. Mac app scope: full command center in MVP or menu bar plus comparison grid?
10. Local workers: Phase 21 is the right timing, or should Ollama/LM Studio
    read-only workers appear earlier as a differentiator?
11. Name: Allnighter final, or working title while validating?

---

## 25. Mentor Review Questions

1. Is the wedge "three options, pick one, implement it" stronger than the
   broader "agent operations" story for launch?
2. Should the first demo focus on UI draft races, strategy councils, or a mix?
3. Is worktree multiplexing enough of a technical wedge, or is preview/artifact
   capture the real differentiator?
4. How much should the product lead with quota harvesting vs creative
   parallelism?
5. Is Allnighter a strong name for daytime council/race use, or too
   night-specific?
6. What is the highest-risk part: vendor ToS, merge trust, driver churn, or
   onboarding?
7. Would you trust one-tap landing from a phone if tests and preview pass?
8. Which first persona is sharper: vibe coder with multiple subscriptions or
   technical indie dev who already knows worktrees are painful?
9. Should Mac be marketed as a full app from day one, or should the phone remain
   the hero?
10. Does the "intelligence commoditizes, orchestration endures" thesis make the
    local AI path feel like a core strategy rather than a side feature?
11. What would make you say "I need this this week"?

---

## 26. Glossary

| Term | Definition |
| --- | --- |
| Agent | A locally installed AI coding tool Allnighter can dispatch or hand off to |
| Agent-hours | Time spent by workers on lane execution |
| Council | Multi-agent reasoning session with critique, synthesis, verdict, and dissent |
| Draft | A candidate answer, plan, mockup, or implementation |
| Lane | Hidden isolated workspace for one task attempt |
| Landing | Bringing a completed lane back to the target branch or PR flow |
| Morning Pull | Daily digest of overnight work and pending decisions |
| Picker-as-prompt | Selection gesture that becomes the implementation work order |
| Preference event | Structured record of pick/reject/split/revert behavior |
| Quota harvester | Scheduler behavior that uses expiring paid capacity |
| Race | Same task dispatched to multiple lanes/workers |
| Standing order | Persistent rule constraining or directing autonomous work |
| Taste model | User/project-specific memory derived from preference events |
| Worker | User-facing name for an agent assigned to a lane |

---

## 27. Build Truth Summary

If this pivot is accepted, the implementation should begin with these truths:

- The Mac owns execution state.
- The iPhone owns mobile capture and decision UX.
- Shared Core owns semantic models and API contracts.
- Each task attempt runs in a lane.
- A lane maps to a git worktree and branch.
- No agent writes to the user's active working directory.
- Every selection can become both preference data and an implementation command.
- Finished work enters a landing queue before touching the target branch.
- User subscriptions are treated as user-owned capacity, never resold capacity.
- Agent integrations are drivers with capability levels, not hardcoded product
  assumptions.
- Local model runtimes are worker sources, not competitors; Allnighter owns
  orchestration, output convergence, selection memory, and landing.

*allnighter.io - Draft v0.3 - Confidential - Open for mentor review*
