# Allnighter Deploy Teams Wedge

Status: Strategy draft, companion to Public Signal Wedge
Owner: Founder + product strategy
Created: 2026-06-18
Purpose: Define Deploy Teams as the missing CLI/MCP-first product layer between
Teams/Skills and the user's daily value. GUI presents this contract; it must not
invent a parallel product model.

## One-Sentence Version

Allnighter lets users deploy agent teams to make evidence-backed moves for a
Project.

## Executive Summary

Allnighter already has the expensive part: Teams and Skills.

But Teams and Skills are engine-room concepts. Users do not wake up thinking:

```text
I need to configure a five-worker team with a skeptic and a plan writer.
```

They wake up thinking:

```text
Find me a reply window.
Turn this signal into a thread.
Pressure-test this feature.
Verify whether the agent really finished.
Find what I should build next.
```

The product layer we are missing is a first-class way to discover, deploy, save,
repeat, and expose these team jobs to agents through CLI/MCP.

Public framing:

```text
Deploy a Team
```

Internal/implementation framing may still use a neutral term such as Workflow
where helpful, but only as plumbing:

```text
Workflow = prompt + team + expected output
```

But public product language should lead with Deploy Teams. It sounds active,
agentic, and native to Allnighter. "Workflow" sounds like Zapier forms.

Sharper public spine:

```text
Deploy a team.
Get a move.
Keep the receipt.
```

## Core Definition

Public definition:

```text
Deploy Team = send a team out with a job
```

Implementation-facing definition:

```text
Deployable Team Job
  name
  promise
  prompt template
  team
  lane affinity: signal | build | design | copy | review | project-manager
  expected output
  next actions
  proof bar / receipt expectation
  requirements
```

The product should stay spiritually simple:

```text
Pick what you want done.
Tell the Project Manager any context.
Deploy the team.
```

The danger is turning Deploy Teams into automation forms. Do not do that.

## CLI / MCP First

Deploy Teams is a contract before it is a view.

Order of truth:

```text
Core contract
-> alln CLI
-> MCP tools
-> generated agent docs/help
-> Mac/iOS presenters
```

GUI may browse, filter, launch, and render deployable team jobs. It must not own
hidden behavior, client-only jobs, scheduler-only semantics, or output schemas
that CLI/MCP cannot produce.

## Deploy Teams Are Not Forms

Allnighter should preserve open-ended chat.

A deployable team job may have helpful starter prompts, examples, or suggested
context. It should not require the user to complete a brittle setup ritual before
value appears.

If the user deploys a team and omits important details, the Project Manager can
ask:

```text
Which audience should I optimize this for?
Which competitor should I watch?
Should this become Copy, Fanout, or a Build work order?
```

Clarification is conversational, not form-first.

Rule:

```text
Deployment starts with intent.
The Project Manager gathers missing context only when needed.
```

This keeps Deploy Teams feeling like superpowers, not software setup.

## Deploy Teams Are Not Templates

A static saved prompt is not a moat.

Deployable team jobs should compound through Project judgment:

- what the user picked;
- what the user ignored;
- what the user edited;
- what became Copy, Fanout, Build, Design, or Pending;
- what shipped;
- what passed proof;
- what produced a useful Receipt;
- what the user marked as noise.

The goal is not:

```text
I saved a prompt.
```

The goal is:

```text
My Project team is getting better at knowing which moves I make.
```

Accumulated judgment belongs primarily to the Project, not only to an individual
deployable job. A Reply Window run should improve future Founder Thread,
Receipts Loop, and Hype Decay judgments for the same Project.

## Moves, Receipts, And Timing

Deployments should return structured artifacts, not walls of text.

Definitions:

```text
Move    = recommended action the Project can take now.
Receipt = evidence/proof artifact that makes a move defensible.
Window  = timing status for time-sensitive moves: open | closing | closed.
```

Every serious Move Card should answer:

- what happened;
- why it matters;
- why this is the user's move;
- whether the window is open, closing, or closed;
- what evidence supports it;
- what the next deployable action is;
- what would count as proof or a receipt.

No move is a valid result. A trustworthy deployment may say:

```text
No move today. The signals are saturated, stale, or not yours to make.
```

That is not failure. It is anti-slop.

For time-sensitive Signal jobs, freshness is correctness. A Reply Window that is
stale is worse than silence. If the product cannot verify freshness, the Move
should render as uncertain or refuse to recommend action.

## Why Deploy Teams Matters

Allnighter's value is currently too hidden.

Teams are powerful, but browsing Teams asks the user to reason from machinery:

```text
Build Core
Bug Hunt
Security Review
Premium Polish
Conversion Studio
```

Deploy Teams lets the user reason from jobs:

```text
Catch a signal before it trends.
Draft the founder thread.
Turn public pain into a Build slice.
Run a launch pre-mortem.
Verify an agent completion claim.
Find high-leverage reply targets.
```

This is a 10x packaging shift.

## Relationship To Existing Concepts

```text
Skill       = one worker's expertise
Team        = workers + skills
Deploy Team = send the team out with a prompt/job
Team Run    = one execution of a deployed team
Project     = the floor where deployment truth belongs
Pending     = where Project-scoped team deployments can wait
MCP/CLI     = how external agents deploy teams
```

The hierarchy:

```text
Project Manager decides what matters.
Deployable team jobs are reusable things the team can do.
Teams are how the job gets done.
Skills are worker expertise.
```

## Teams Own Work Shape

Do not add a generic deploy-time Low/Med/High knob that secretly changes worker
count, review posture, output shape, or research depth.

If the shape is different, make it a different Team:

```text
Bug Hunt Lite
Bug Hunt
Bug Hunt Exterminator
Landing Page Team
Landing Page Conversion Team
Signal Reply Window
Signal Receipts Loop
```

Reasoning effort may exist only as model/provider configuration for workers that
support it. It is not the public Deploy Teams control.

This keeps the product simple:

```text
Pick the team.
Add context if needed.
Deploy.
```

## Product Claim

Allnighter should become:

```text
the best place to deploy agent teams for a Project
```

Not:

```text
a team editor with a hidden run action
```

This matters because a strong deployable team library makes Allnighter valuable
even before users customize anything.

## Built-In And User-Created

There are two sources of deployable team jobs:

### Built-In Deployable Team Jobs

Allnighter ships excellent team jobs:

- Signal team jobs;
- Copy team jobs;
- Build team jobs;
- Design team jobs;
- review/verification team jobs;
- Project Manager team jobs.

These prove value quickly.

### User-Created Deployable Team Jobs

The user can save a useful prompt/team combo as a deployable team job.

Examples:

```text
Save this Signal -> Copy run as "Daily AI Agent Founder Thread."
Save this Bug Hunt prompt as "Pre-Release Bug Sweep."
Save this proof pass as "Before I Believe Done."
Save this competitor prompt as "Watch Cursor Positioning."
```

User-created deployable jobs are the compounding layer. The more the user runs
Allnighter, the more their Project develops reusable moves.

## Creation Should Be Cheap

A deployable team job should be cheap to create because Allnighter already has:

- teams;
- skills;
- prompt history;
- Project context;
- prior successful runs;
- output actions.

Creation paths:

```text
Create from scratch.
Duplicate a built-in deployable job.
Save a successful Team Run as deployable.
Ask Project Manager to make this repeatable.
Import from an agent/MCP caller.
```

Do not force users to become automation architects. Let them say:

```text
Make this repeatable.
```

Then the Project Manager can name it, summarize its promise, bind the team, and
ask only the missing questions.

## Agent-First Unlock

This is where Allnighter can avoid competing with OpenClaw, Hermes, cron agents,
or other loop owners.

Allnighter should not own scheduling/run loops in v1.

It needs to expose great deployable team jobs.

Agent-first contract, product language:

```text
team_deployable_list
team_deployable_get
team_deployable_preflight
team_deploy
team_deploy_pending
team_deploy_result
```

CLI shape, product language:

```text
alln team deployables --json
alln team deployable show <id> --json
alln team deployable preflight <id> --project <project> [prompt] --json
alln team deploy <id> --project <project> [prompt] --json
alln team deploy-pending <id> --project <project> [prompt] --json
```

If implementation keeps a lower-level `workflow_*` registry internally, it must
project to Deploy Teams publicly.

Then an external agent can own the loop and call Allnighter:

```text
Every morning, deploy Daily X Pulse for Project Allnighter.
Every Friday, deploy Competitor Conversation Map.
When a watched account posts, deploy Preloaded Response Kit.
```

Allnighter becomes the best place to define and execute deployable team jobs.
Other agents can schedule, monitor, or trigger them.

## Project-Scoped By Default

Deployments should run inside a Project unless explicitly marked
global/read-only.

Rules:

- A team deployment has `projectId`.
- A deployment can read Project context when allowed.
- A deployment can create Project-scoped Pending items.
- A deployment can create Project Manager proposals.
- A deployment can produce Copy/Fanout/Build/Design handoffs.
- A deployment must not mutate or dispatch without the same approval gates as
  any other Project work.

This keeps Deploy Teams from becoming a floating automation system.

## Output Types

Useful team deployments should declare what kind of result they produce.

Examples:

```text
Opportunity Board
Copy Drafts
Reply Options
Fanout Brief
Build Work Order
Design Brief
Audit Findings
Verification Record
Project Proposal
Activity Summary
```

Output type matters because it determines the next actions.

Example:

```text
Opportunity Board -> Draft Copy / Run Fanout / Create Build Work Order / Monitor
Build Work Order  -> Reveal / Dispatch / Add to Pending
Verification      -> Mark verified / Request fix / Ask user
```

## Requirements

Requirements should be visible but not bureaucratic.

Examples:

```text
Needs Grok public-signal worker.
Needs Project root.
Needs Copy team.
Read-only.
Can create Draft/Pending.
Requires approval before dispatch.
```

Requirements exist to set expectations, not to make the user configure a
machine.

## Signal Deployments

The Signal wedge proves why Deploy Teams matters.

Signal deployable jobs can be created mostly from:

```text
prompt + Signal team
```

Examples:

- Velocity Alert;
- Signal to Copy;
- Signal to Fanout;
- Signal to Build: Receipts Loop;
- Reply Window;
- Demand Capture;
- Phrase Velocity Radar;
- Gravity Radar;
- Hype Decay / Don't Post This;
- Fragmentation Synthesis;
- Preloaded Response Kit;
- Visual Signal Board.

These are not new infrastructure-heavy products. They are reusable prompt/team
packages with excellent output actions.

## Build / Design / Copy Deployments

Signal should not be the only deployable family.

Build deployments:

- Bug Hunt;
- GUI Bug Hunt;
- Architecture Pressure Test;
- Release Proof;
- Before I Believe Done;
- Feed-To-Feature Build Slice.

Design deployments:

- Premium Polish;
- Visual Signal Board;
- Screenshot Critique;
- Product Feel Alternatives;
- Landing Page Visual Direction.

Copy deployments:

- Founder Thread;
- Landing Page Rewrite;
- Objection Mining;
- Reply Options;
- Competitor Positioning Response;
- Launch Narrative.

The current Teams already imply many of these. Deploy Teams makes them findable
and repeatable.

## External Loops, Not Native Scheduling

Scheduled or repeated deployments are important, but Allnighter should not build
the loop owner first.

V1 posture:

```text
Allnighter defines and runs deployable team jobs.
Project-scoped Pending can hold deferred team deployments.
MCP/CLI lets external agents schedule, monitor, and trigger them.
```

This makes Allnighter agent-first and avoids competing with OpenClaw/Hermes as
automation hosts.

Native scheduling is explicitly later and not required for the wedge. If it ever
ships, it must be a thin projection over the same Project-scoped CLI/MCP
contract, not a second automation product.

## Why This 10x's Allnighter

Without Deploy Teams:

```text
The user must understand teams, skills, lanes, prompts, and routing.
```

With Deploy Teams:

```text
The user sees useful jobs they can send agent teams to do.
```

This turns Allnighter from an orchestrator for people who already understand the
system into a product people can browse, try, and share.

The same substrate supports:

- creators;
- founder-builders;
- vibe coders;
- agencies;
- internal teams;
- agent-first automation users.

## Naming Decision

Public language:

```text
Deploy Teams
Deploy a Team
Deploy Signal Team
Team Deployment
Deployable Team Job
Team Run
```

Use carefully:

```text
War Room = divergent/fanout-heavy deployment mode
Swarm    = spicy marketing word for heavy multi-agent deployments
Mission  = optional copy noun for a bounded job
Playbook = optional future noun for a chain of deployable jobs
```

Avoid as primary public language:

```text
Workflow
Template
Automation
Recipe
Zap
```

`Workflow` may remain an implementation or registry concept if it prevents
awkward code names, but public copy should say Deploy Teams.

## Non-Goals

- Do not turn Deploy Teams into rigid forms.
- Do not make deployable jobs a separate truth system from Projects, Teams,
  Skills, Runs, and Pending.
- Do not create client-only deployable jobs that CLI/MCP cannot run.
- Do not make scheduling a prerequisite for value.
- Do not build native scheduling/run loops before the CLI/MCP trigger contract
  is strong.
- Do not expose a generic deploy-time effort toggle that changes team shape.
- Do not auto-post, auto-reply, or auto-dispatch mutating work without approval.
- Do not hide the team/worker truth when a team deployment runs.
- Do not let marketing claim model/data access Allnighter does not own.

## Open Questions

These should be answered before implementation:

- Should any public surface use "Workflow" at all, or should it be internal only?
- What is the smallest deployable job contract: prompt + team + output type, or
  prompt + team + output type + receipt expectation?
- Should Chat and Deploy Teams be sibling entry concepts, or should deployment
  be suggested from Project Manager chat first?
- How should a deployment ask follow-up questions without feeling slower than a
  normal chat?
- Which built-in deployable team jobs should be pinned for first-run onboarding?
- Should creation be allowed from any successful Team Run?
- How much Project context does a deployment include by default?
- Should deployable team jobs be global reusable assets, Project-local assets,
  or both?
- How should external MCP agents pass runtime context safely?
- What is the minimal proof that Deploy Teams are discoverable enough before
  interface polish?

## Mentor Questions

Ask mentors:

- Does "Deploy Teams" make Allnighter easier to understand than "Workflows"?
- Which deployable job would make a new user say "I want to try that right now"?
- Is the value surface more compelling as Signal deployments, Copy deployments,
  or Project Manager deployments?
- Does the product still feel simple if deployments can ask clarifying
  questions?
- What should be free versus paid at $9.95/month?
- Would external agent schedulers deploy Allnighter teams if the MCP contract is
  clean?
- What is the right boundary between built-in deployable jobs and user-created
  deployable jobs?

## Strong Recommendation

Make Deploy Teams first-class, but keep the underlying package lightweight and
CLI/MCP-first:

```text
Deployable Team Job = prompt + team + expected output + next actions
```

Receipts, proof bars, timing status, and accumulated judgment are how the output
becomes defensible and compounding. They should be structured artifacts, not
extra setup forms.

The first compelling deployable family should be Signal, because it makes the
value obvious:

```text
public signal
-> deploy Signal Team
-> team run
-> move
-> receipt / memory
```

The aha:

```text
Allnighter is not just a place to configure teams.
It is a place to deploy powerful agent teams for my Projects.
```
