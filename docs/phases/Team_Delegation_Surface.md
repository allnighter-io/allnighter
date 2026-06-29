# Team Delegation Surface

Status: Draft product/implementation spec
Owner: Founder + AllnighterCore + CLI/MCP + Mac app
Updated: 2026-06-18

## Authority

Read with:

- `docs/phases/Language_Cutover.md`
- `docs/phases/Project_Spine_And_Project_Manager.md`
- `docs/phases/Team_And_Skill_Catalogs.md`
- `docs/phases/CLI_Product_Spine.md`
- `docs/phases/CLI_Implementation_Contract.md`
- `docs/strategy/Allnighter_Deploy_Teams_Wedge.md`
- `docs/strategy/Allnighter_Public_Signal_Wedge.md`

`Language_Cutover.md` owns the vocabulary. This doc owns the product surface
that makes "Send to team" discoverable and useful.

## Founder Intent

Raw request:

```text
Allnighter's high-value moment is not a blank prompt box. The user should be able
to see useful teams they can send right now: Signal, Code, Design, Copy. This is
where the product becomes obvious. Do not make the user understand fanout,
workflows, or internal routing.
```

Product value:

```text
The user can talk to the Project Manager, then delegate to the right team without
learning the machinery.
```

Trusted workflow slice:

```text
open Project
-> ask Project Manager or choose Send to team
-> browse/recommend one team
-> send team with prompt/context
-> receive Insights, options, proposal, board, or work order draft
-> optionally Execute an approved mutating move
```

## Product Model

The user does two everyday things:

```text
Chat with the Project Manager.
Send to team.
```

`Execute` is not a browse mode. It is the approval that green-lights a mutating
make-real run after a proposal, Insight, returned team result, or work order is in
front of the user.

Public words:

```text
Chat            default Project Manager surface
Send to team    UI label for delegation
Delegate        model verb in docs/copy
Team            the actor noun
Signal          teams that scout outside-world change and return Insights
Code            teams that plan, fix, review, or make product/code work real
Design          teams that explore product/visual direction
Copy            teams that shape words, positioning, and narrative
Execute         approval for mutating work
```

Avoid:

```text
Fan out
Workflow
Template
Automation
Execute mode
Build-as-craft
```

`Workflow` is reserved for future loops. In v1, external loop owners such as
Hermes/OpenClaw may call Allnighter through CLI/MCP, but Allnighter does not own
native scheduling.

## Why This Surface Exists

Teams are the product value but are currently hidden behind machinery.

A blank composer asks the user to know what they want. A team map shows what
Allnighter can do:

```text
Signal: Find what matters outside the repo.
Code: Decide or make the product/code move.
Design: Explore how it should feel.
Copy: Shape what to say.
```

The surface should answer:

```text
What can I send a team to do right now?
Which team should I use for this prompt?
What will I get back?
Will it mutate anything?
What proof or receipt will come with it?
```

## Surface Placement

There are two entry paths.

### Project Manager Recommendation

The best default path is chat-first:

```text
User: What should I work on next?
Project Manager: I can answer from Project truth, or send a Signal team to scout
what changed outside the repo. Recommended: Signal / What should we build next.
```

The Manager may recommend a team, but it must not silently run one.

### Direct Send To Team

The user can bypass chat when intent is obvious:

```text
paste X post -> Send to team -> Signal / Post-to-Project Signal
bug report -> Send to team -> Code / Bug Hunt
screenshot -> Send to team -> Design / Premium Polish
launch thought -> Send to team -> Copy / Founder Thread
```

Direct send is still a team run. If it would mutate Project files or external
state, it requires Execute approval.

## Team Families

The browse surface has four public families:

```text
Signal
Code
Design
Copy
```

Signal is first-class because its starting point is outside-world change. It is
not a social-listening product, not an X API proxy, and not a scheduler.

Signal teams return **Insights**: Project-aware interpretation of public signal,
with source receipts, freshness, fit, risk, and recommended next actions.

Code/Design/Copy teams may return plans, boards, proposals, drafts, audits,
proof packets, or work orders depending on team posture and output kind.

## Team Card Contract

The Mac surface renders Team Cards. The card is a projection of Core truth, not
GUI-local content.

Minimum Core projection:

```text
TeamCard
  id
  displayName
  family: signal | code | design | copy
  promise
  teamId
  posture: scout | propose | review | execute
  mutating: Bool
  outputKind
  starterPrompts[]
  requirements[]
  recommendedFor[]
  pinned: Bool
  pinnedReason?
  projectFitReason?
  lastRunAt?
  nextActions[]
```

Rules:

- Every Team Card links to exactly one Team definition.
- `mutating == true` means the card cannot complete without Execute approval.
- Cards may provide starter prompts, but the user can always type ordinary
  language.
- Cards are not workflows. They do not own loops, schedules, or hidden state.
- Team lineup, worker skills, model bindings, and prompt templates belong to the
  Team/Skill catalogs and run snapshot.
- The Project Manager may add a `projectFitReason`, but that reason is derived
  from the current Project Context Packet and stored as a recommendation receipt.

## Recommended Built-In Cards

Launch with a small, opinionated set. Do not ship an 18-card buffet.

Pinned starter cards:

```text
Signal / Post-to-Project Signal
Signal / What should we build next?
Code / Bug Hunt
Code / Before I Believe Done
Design / Premium Polish
Copy / Founder Thread
```

Strong Signal candidates:

```text
Post-to-Project Signal
What should we build next?
Reply Window
Velocity Alert
Hype Decay
Receipts Loop
Daily Pulse
```

Strong Code candidates:

```text
Code Core
Bug Hunt
Spec Review
Before I Believe Done
Release Proof
```

Strong Design candidates:

```text
Design Core
Premium Polish
Radical Directions
Usability Triage
Visual Signal Board
```

Strong Copy candidates:

```text
Copy Core
Founder Thread
Landing Page Team
Reply Options
Launch Narrative
```

## Signal Intake

Signal needs one atomic card before daily monitoring:

```text
Post-to-Project Signal
```

Input:

```text
X post/thread URL, pasted public post text, article link, model release note, or
plain-language public signal.
```

Output:

```text
Insight
  sourceReceipt
  freshness
  whatHappened
  whyItMatters
  whyThisProject
  internalLessons
  externalProductIdeas
  recommendedNextActions
  skepticPass
```

Next actions:

```text
Draft Copy
Send another team
Create Code proposal
Create Design brief
Save Pending
Ignore
```

## Project Manager Selection

The Project Manager may recommend teams based on:

- user message;
- selected attachments;
- current Project Context Packet;
- recent ignored/accepted team results;
- worker readiness;
- mutating risk;
- freshness requirements for Signal.

The Manager must show the recommendation as an option, not as hidden execution:

```text
Recommended: Signal / Post-to-Project Signal
Why: this starts from a public X post and asks how it applies to this Project.
```

## Non-Goals

- No `Workflow` user noun.
- No native scheduling or recurring loops.
- No X API proxy, raw search API, auto-posting, or reply automation.
- No GUI-only Team Cards.
- No effort control that changes team size.
- No Execute browse tab.
- No auto-running recommended teams without explicit user send.
- No mutating work without Execute approval.

## Current State

Existing useful substrate:

- `Language_Cutover.md` locks Chat / Delegate ("Send to team") / Execute.
- `TeamCatalog` and `SkillCatalog` exist for built-in/custom teams and skills.
- `TeamRunJSON` exists as the public team-run output contract.
- CLI/MCP docs already name future deployable-team discovery and run tools.
- Signal strategy exists in `Allnighter_Public_Signal_Wedge.md`.
- GUI surface brief exists at `docs/gui/surfaces/send-to-team/brief.md`.

Current gaps:

- No Core `TeamCard`/delegation projection.
- No `signal` family/craft in the active team catalog.
- No Mac production implementation for the browseable Send to team view.
- No Project Manager team recommendation contract.
- No typed next actions for Signal outcomes in the public run result.

## Truth Owner

Core owns the Team Card projection and team-run contracts.

```text
AllnighterCore
  TeamCatalog / SkillCatalog
  TeamCard projection
  Project Context Packet
  Project Manager recommendation receipt
  TeamRunJSON / future team.run result
```

Mac, CLI, MCP, and iOS render and trigger those contracts. They do not invent
cards, recommendations, requirements, or mutating state.

## Implementation Impact

Core:

- Add Team Card projection over team definitions.
- Add Signal family/craft once the cutover creates the final enum shape.
- Add card requirements, posture, mutating flag, starter prompts, and output kind.
- Add Project Manager recommendation receipt.
- Add typed next actions for common team outputs.

CLI/MCP:

- Prefer the final `team.run` primitive from `Language_Cutover.md`.
- Provide list/get/preflight/run equivalents for Team Cards if the final MCP
  contract still exposes discovery.
- Report `mutating` and approval requirements before run start.

Mac:

- Build Send to team browse surface.
- Allow Project Manager recommendations inline in chat.
- Use the same card projection as CLI/MCP.
- Route mutating cards into Execute approval instead of running immediately.

iOS:

- Later remote Project Manager can render the same recommended Team Cards.

## Works Tests

### WT-TDS01 - Browse and send non-mutating Signal team

Setup:

```text
Project exists.
Signal / Post-to-Project Signal card exists.
At least one public-signal-capable worker is ready or readiness blocker is visible.
```

Gesture:

```text
Open Send to team, choose Signal, paste an X post URL, send the team.
```

Assertions:

- Card data comes from Core projection.
- Preflight shows requirements before run.
- Team run records `family: signal`, `posture: scout`, `mutating: false`.
- Result contains an Insight with source receipt and next actions.

### WT-TDS02 - Project Manager recommends a team without auto-running

Gesture:

```text
User asks: How does this post apply to Allnighter?
```

Assertions:

- Project Manager may recommend `Signal / Post-to-Project Signal`.
- Recommendation includes why this team fits.
- No team run starts until the user chooses Send.

### WT-TDS03 - Mutating team requires Execute approval

Gesture:

```text
User chooses a Code card whose posture can make repo changes.
```

Assertions:

- Preflight labels the card mutating.
- User can inspect/reveal the proposed work.
- Execute approval is required before mutating dispatch.

### WT-TDS04 - Empty Project readiness is honest

Gesture:

```text
Open Send to team in a Project with no ready workers.
```

Assertions:

- Cards remain browseable.
- Run buttons are blocked with sourced readiness state.
- UI offers repair/recheck, not fake availability.

## Proof Command

Contract proof will depend on the implementation slice. Minimum expected wall:

```bash
swift test --package-path Packages/AllnighterCore
xcodebuild test -scheme AllnighterMac -destination 'platform=macOS'
```

GUI implementation must also pass the visual proof gate for the Send to team
surface.

## Done When

- A user can discover useful Signal/Code/Design/Copy teams without knowing
  internal machinery.
- Project Manager can recommend one team and explain why.
- Direct Send to team can start a non-mutating team run.
- Mutating cards require Execute approval.
- No public surface says Fan out, Workflow, Template, or Execute mode.
- All card labels, requirements, and next actions come from Core contracts.
