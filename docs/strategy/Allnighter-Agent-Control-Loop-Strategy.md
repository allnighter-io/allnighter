# Allnighter Agent Control Loop Strategy

**Status:** Strategy anchor — host-agent dogfood (2026-07-20)
**Owner:** Founder + CTO
**Created:** 2026-06-14
**Updated:** 2026-07-20
**Purpose:** Keep Allnighter out of the IDE/coding-agent trap and focused on the
highest-value wedge: a local control loop that coordinates, dispatches, and
evaluates the agents the user already uses — without forcing a new daily-driver
shell.

---

## 0. One-Page Brief

Allnighter is not an IDE, coding agent, git client, terminal viewer, Jira, or
model provider.

Allnighter is the **local agent-control loop** for a Project:

```text
know the Project floor
-> answer or orient from current truth
-> ask the right agents when judgment is useful
-> synthesize what came back
-> shape one bounded work order
-> dispatch to the chosen agent/CLI
-> capture the return
-> verify proof before calling it done
-> recommend the next move
```

The strategic claim:

```text
Cursor, Claude, Codex, Gemini, Grok, Aider, and local models do the work.
Allnighter manages the work.
```

### Dogfood bar (power users)

The dogfood bar is intentionally severe — and it is **not** “open Allnighter first.”

```text
A serious multi-CLI power user stays in Claude, Codex, Grok, Cursor, or
whatever host they already live in. They tell that agent to use alln
(pilot, relay, panel, team, menu). Cognitive load drops before and after
execution without switching home base.

Success = alln is in the muscle memory of their agents,
not that the human’s home screen is Allnighter.
```

Founder signal (2026-07): more `alln` usage than ever, almost never “starting in
the Allnighter app.” That is product–market fit for agent-native users, not a
regression.

### Surface ranking

| Rank | Surface | Role |
| --- | --- | --- |
| 1 | Host CLIs + `alln` verbs | Primary invocation for power users |
| 2 | Mac app | Floor board, attention, threads, health — optional keyboard |
| 3 | iOS | Remote floor manager when away from a CLI |

The **loop** is the product. The Allnighter window is one client of that loop —
valuable for visibility and remote steer, not required as the daily workplace.

If Allnighter becomes another place to code, review diffs, watch terminals, or
manage branches, it is competing on the wrong axis. If it becomes the rails that
know the repo, run team judgment, shape handoffs, relay overnight work, and
verify what came back — callable from the agents the user already trusts — it
has a real wedge.

---

## 1. The Product Boundary

Allnighter owns:

- Project truth orientation;
- prompt/work-order assembly;
- Project-scoped Pending and queue visibility;
- model/team selection;
- parallel fanout (panel / team judgment);
- synthesis and dissent preservation;
- proposal creation;
- direct dispatch to configured agents;
- PM↔dev relay and pilot loops;
- return capture;
- proof/verification review;
- next-step routing;
- CLI as the agent-facing product surface (`alln`);
- Mac/iOS command surfaces over the same local contract.

Agents own:

- the daily conversational workplace (Claude Code, Codex, Grok, Cursor, …);
- code editing;
- file diffs;
- local reasoning inside their execution session;
- tool use inside their permissions (including calling `alln`);
- implementation attempts;
- self-reported completion, which Allnighter treats as an input, not proof.

Repos own:

- git history;
- branch policy;
- commit policy;
- tests and proof commands;
- durable docs;
- CI and release gates.

Strategic boundary:

```text
Allnighter owns orchestration, synthesis, dispatch, and verification.
Host agents own the daily workplace and execution sessions.
Repos own durable process truth.
```

---

## 2. Why This Still Matters

The founder pain is not:

```text
I need a worse Cursor.
I need another chat window.
I need a branch manager.
I need to relocate my entire workflow into a fourth app.
```

The founder pain is:

```text
I am using several strong agents.
They come back with different plans, diffs, suggestions, and claims.
I need local rails that know the Project and keep the loop moving.
I need the next best prompt or work order without copy/paste archaeology.
I need team judgment and overnight relay without becoming the traffic cop.
I need proof before I believe "done."
I want to steer this from a host CLI now, Mac floor when useful, phone later.
```

That is the product.

The useful emotional response is:

```text
Oh good — my agent can call alln and it knows what is going on.
```

Not:

```text
Oh no, another workflow / home base to maintain.
```

Habit preservation is a feature. Power users win when Allnighter rides the
attention they already give Claude, Codex, and Grok — not when it fights those
tools for a new default shell.

---

## 3. The Winning Loop

The control loop is the star. Surfaces are how humans and host agents enter it.

Default hierarchy (substance, not UI):

```text
Project
-> control loop (orient / judge / shape / dispatch / verify / next)
-> team / panel when judgment is useful
-> synthesis
-> work order or relay round
-> dispatch to a chosen agent/CLI
-> return review
-> verified next move
```

How power users typically enter:

```text
Host agent session (Claude / Codex / Grok / …)
-> alln bootstrap / menu / pilot / panel / relay / team
-> same loop, same Project truth, same proof bar
```

How humans optionally enter:

```text
Mac app or iOS
-> floor visibility, attention, approve/steer, kick overnight work
-> same loop over the same local contract
```

Team runs (panel, fanout, synthesis) are capabilities the loop uses, not the
main product noun. They matter because they improve judgment, proposals, and
verification — whether invoked by a host agent or a human UI.

The loop is complete only when someone (human or host agent reading `alln`
output) can see:

- what was asked;
- who answered;
- what was decided;
- what work was approved;
- where it ran;
- what came back;
- what proof passed or failed;
- what is recommended next.

---

## 4. What The Control Loop Must Be Great At

Whether the caller is a human in the Mac app or a host agent using `alln`, the
loop must excel at the same jobs. “Project Manager” names the **role** of the
loop, not a requirement that the human live in an Allnighter chat window.

### Project Truth

The loop knows the selected Project's local root, git state, active branch,
durable docs entrypoints, relevant threads, recent runs, pending work, approved
proposals, proof commands, and known blockers.

It does not invent truth. When docs, git, proof, and worker claims disagree, it
names the disagreement and refuses to flatten it into fake certainty.

### Next Move Selection

The loop answers "what should I do next?" with one bounded next move or one
reason it cannot safely choose.

It may offer alternates only when the decision is genuinely a product judgment,
not because the system is uncertain about its own state.

### Fanout / Panel As Judgment

Fanout and panel are used when judgment, options, review, or dissent is needed.
They are not ceremony around obvious work.

Good outputs:

- agreement;
- disagreement;
- assumptions;
- risks;
- candidate work orders;
- recommended pick/remix/rerun.

Fanout is discovery, not proof.

### Work-Order Shaping

Fuzzy intent becomes a bounded work order:

- goal;
- current truth;
- scope;
- non-goals;
- files/areas likely involved;
- exact constraints;
- proof command or waiver;
- expected return format;
- chosen agent/worker target.

Work orders must be editable before dispatch when a human is in the loop;
agent-driven paths still need an inspectable, structured order.

### Relay And Pilot

For multi-round or overnight work, relay (PM seat ↔ dev seat) and pilot are
first-class loop modes — especially when the human is not sitting in any UI.
They are how Allnighter shows up to work while the user stays in a host CLI or
is offline.

### Return Review

Worker completion claims are untrusted until verified.

Return review answers:

- what changed;
- what proof ran;
- what proof failed or was missing;
- whether the work matches the approved order;
- whether docs/proposals/pending state should advance;
- whether another agent should audit, fix, or continue.

---

## 5. Stay In Your Host — Invoke The Rails

The product should fit the user's existing tools:

```text
Live in the host agent/CLI you already use.
Call alln (pilot, relay, panel, team, menu) when judgment, dispatch,
overnight loop, or proof rails are needed.
Use the Mac app or phone when you want the floor — not because you must
type every prompt there.
```

This is not a demotion of the Mac app. It is the power-user wedge.

**Obsolete bar (retired 2026-07-20):**

```text
Start in Allnighter to decide and shape the work.
Execute in the user's chosen agent/CLI.
Return to Allnighter to understand and verify the result.
```

That path remains **valid and optional** for human-first users. It is no longer
the success test for multi-CLI power users.

Allnighter only wins for power users if calling `alln` from inside Claude,
Codex, or Grok is faster and calmer than manual multi-tool coordination — and
if the human is **not** forced to adopt a new home base to get that value.

Agent-surface fidelity (bootstrap teaching, live `alln menu --json`, honest
help, structured JSON, next actions) is product quality, not polish.

---

## 6. Hard Non-Goals

Do not prioritize:

- code editor surfaces;
- diff review as a primary product surface;
- Allnighter-managed commits;
- Allnighter-managed branches/worktrees;
- global Pending/queue state as product truth;
- landing queues;
- terminal multiplexing;
- chat aggregation for its own sake;
- generic task/project management;
- cloud coding service behavior;
- model-provider behavior;
- autonomous unapproved execution;
- self-attested "done" states;
- forcing the Allnighter app as the only or primary daily driver.

These may appear later only as narrow support features if the control loop
proves demand. They must not displace the loop or the host-agent invocation path.

---

## 7. Levels Of Execution Support

Allnighter can grow without changing identity:

```text
Level 1 - Reveal/copy an exact handoff prompt.
Level 2 - Direct CLI dispatch in the selected Project root.
Level 3 - Return capture and comparison.
Level 4 - Proof-aware return review.
Level 5 - Optional managed execution safety.
```

### Level 1 - Reveal/Copy

Fallback for manual workers, unsupported tools, unhealthy CLIs, or user review.
The value is still real if the loop writes the exact handoff better than the
user would from memory.

### Level 2 - Direct CLI Dispatch

MVP requirement for the control loop. Allnighter invokes the selected healthy
worker with the assembled work order in the configured Project root and captures
output where the driver supports capture. Host agents reach this through `alln`.

### Level 3 - Return Capture And Comparison

Allnighter records what came back, attaches it to the Project thread/proposal,
and summarizes differences when multiple workers return.

### Level 4 - Proof-Aware Return Review

Allnighter checks proof artifacts, commands, git state, and docs drift before
advancing work to verified/done.

### Level 5 - Managed Execution Safety

Branch/worktree policy, landing, revert, preview gates, and protected-path
enforcement can come later only if dogfood proves users need Allnighter to own
those claims. This layer is not required for the wedge.

---

## 8. Dogfood Survival Slice

### Primary path (power user / agent-native)

```text
work inside a preferred host CLI (Claude, Codex, Grok, …)
-> host is taught alln (bootstrap / menu)
-> call alln pilot, panel, relay, or team for a real Project need
-> loop uses Project truth (docs/git/threads/runs)
-> judgment or multi-seat work runs without human clipboard traffic
-> capture returns; verify proof or name missing proof
-> next move is clear in alln output and/or floor (app/thread)
```

The human may never open the Allnighter app for this slice. That is allowed and
often preferred.

### Secondary path (human-first / floor)

```text
open Allnighter (or iOS) on a Project
-> ask "what should we do next?"
-> receive scoped orientation and one bounded proposal
-> approve or edit
-> dispatch or reveal handoff
-> capture return; verify proof
-> next move recommended
```

Both paths share one contract. Neither path invents parallel product truth.

### Always visible (no hidden magic)

Whether the caller is human UI or host agent:

- selected Project;
- source truth used;
- proposal / round kind;
- approval or seat state where applicable;
- dispatch target;
- proof expectation;
- verification result.

Passing the **primary** path is more important than Mac chrome polish. Agent
surface fidelity and relay/pilot reliability beat “start in app” adoption metrics.

---

## 9. Product Tests

Allnighter is worth continuing when dogfood shows:

- a multi-CLI power user completes real Project work by invoking `alln` from a
  host agent **without** being forced to start in the Allnighter app;
- `alln` usage rises even when app-open / “start in Allnighter” does not;
- orientation and “what next?” answers use real Project truth without fake work
  orders;
- panel / team judgment and pilot / relay produce usable bounded next steps;
- handoffs and structured orders are good enough for host or worker agents with
  little editing;
- return review catches missing proof, scope drift, or stale docs;
- the next move is clearer after the loop than before it;
- bootstrap / menu / help keep host agents from inventing dead verbs.

Allnighter is drifting when:

- the user spends more time managing Allnighter than the agents;
- success is measured mainly by “opened the app first”;
- the loop cannot explain which Project truth it used;
- fanout/panel produces more ambiguity without a recommendation;
- proposals are broad, vague, or untestable;
- "done" relies on a worker saying it is done;
- host agents cannot discover or correctly call `alln` (surface fidelity fails);
- the team adds IDE/git/project-board features before the loop and agent surface
  are reliable.

---

## 10. Mobile Strategy

Mobile becomes valuable once the **same local control loop** works from `alln`
and the Mac floor — not only after a Mac “PM chat as home” habit is proven.

The iOS app is a remote floor manager for the control loop:

```text
from phone:
read Project state
ask the loop / PM role
approve/edit/postpone proposals
dispatch bounded work to the Mac
watch returns / relay attention
verify or request follow-up
```

The phone is not a remote terminal and not a mobile IDE. The Mac owns execution
and run truth. The phone steers the loop when the user is away from a host CLI.

For agent-native users, phone and Mac app are **optional attention surfaces**.
They do not have to replace Claude/Codex as the keyboard.

---

## 11. Near-Term Roadmap Decision

Prioritize:

```text
Projects as durable local floors
alln as the agent-facing product surface (bootstrap, menu, help fidelity)
pilot / relay / panel / team as first-class loop entries
Project context packets and honest Project truth
one-next-move proposals and inspectable work orders
direct dispatch with capture
proof-aware verification
fanout/synthesis when judgment is needed
Mac floor: attention, threads, health, overnight visibility
iOS remote steer over the same contract
```

Do not prioritize:

```text
Allnighter-as-mandatory home base
Allnighter-managed worktrees
Allnighter-managed commits
landing queues
global Pending queue as product truth
repo safety guarantees as the wedge
branch/revert ownership
generic project boards
terminal viewing
diff/editor surfaces
competing with host CLIs for daily chat attention
```

The narrow bet:

```text
The best way to use many powerful coding agents is not another coding agent
and not a forced new shell.

It is local control-loop rails — callable from the agents the user already
lives in — that keep judgment, dispatch, relay, and proof honest.
```
