# Allnighter Agent Control Loop Strategy

**Status:** Strategy anchor, hardened after Project Manager dogfood review
**Owner:** Founder + CTO
**Created:** 2026-06-14
**Updated:** 2026-06-17
**Purpose:** Keep Allnighter out of the IDE/coding-agent trap and focused on the
highest-value wedge: a local Project Manager that coordinates, dispatches, and
evaluates the agents the user already uses.

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

The dogfood bar is intentionally severe:

```text
A serious Cursor + Claude power user should still start in Allnighter because
the Project Manager reduces the cognitive load before and after execution.
```

If Allnighter becomes another place to code, review diffs, watch terminals, or
manage branches, it is competing on the wrong axis. If it becomes the thing that
knows the repo, remembers the plan, asks the right agents, produces a narrow
handoff, and verifies what came back, it has a real wedge.

---

## 1. The Product Boundary

Allnighter owns:

- Project truth orientation;
- prompt/work-order assembly;
- Project-scoped Pending and queue visibility;
- model/team selection;
- parallel fanout;
- synthesis and dissent preservation;
- proposal creation;
- direct dispatch to configured agents;
- return capture;
- proof/verification review;
- next-step routing;
- Mac/iOS command surfaces over the same local contract.

Agents own:

- code editing;
- file diffs;
- local reasoning inside their execution session;
- tool use inside their permissions;
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
Agents own execution.
Repos own durable process truth.
```

---

## 2. Why This Still Matters

The founder pain is not:

```text
I need a worse Cursor.
I need another chat window.
I need a branch manager.
```

The founder pain is:

```text
I am using several strong agents.
They come back with different plans, diffs, suggestions, and claims.
I need one local place that knows the Project and keeps the loop moving.
I need the next best prompt or work order without copy/paste archaeology.
I need proof before I believe "done."
I want to steer this from Mac now and phone later.
```

That is the product.

The useful emotional response is:

```text
Oh good, it knows what is going on.
```

Not:

```text
Oh no, another workflow to maintain.
```

---

## 3. The Winning Loop

The default product hierarchy is:

```text
Project
-> Project Manager chat
-> fanout when useful
-> synthesis
-> work order
-> dispatch
-> return review
-> verified next move
```

The Project Manager is the star. Team runs are a capability it uses, not the
main product noun. A team run matters because it helps the Project Manager answer
better, propose better, or verify better.

The loop is complete only when the user can see:

- what was asked;
- who answered;
- what was decided;
- what work was approved;
- where it ran;
- what came back;
- what proof passed or failed;
- what the Project Manager recommends next.

---

## 4. What The Project Manager Must Be Great At

### Project Truth

The Project Manager knows the selected Project's local root, git state, active
branch, durable docs entrypoints, relevant threads, recent runs, pending work,
approved proposals, proof commands, and known blockers.

It does not invent truth. When docs, git, proof, and worker claims disagree, it
names the disagreement and refuses to flatten it into fake certainty.

### Next Move Selection

The Project Manager answers "what should I do next?" with one bounded next move
or one reason it cannot safely choose.

It may offer alternates only when the decision is genuinely a product judgment,
not because the system is uncertain about its own state.

### Fanout As Judgment

Fanout is used when the Project Manager needs judgment, options, review, or
dissent. It is not used as ceremony around obvious work.

Good fanout outputs:

- agreement;
- disagreement;
- assumptions;
- risks;
- candidate work orders;
- recommended pick/remix/rerun.

Fanout is discovery, not proof.

### Work-Order Shaping

The Project Manager turns fuzzy intent into a bounded work order:

- goal;
- current truth;
- scope;
- non-goals;
- files/areas likely involved;
- exact constraints;
- proof command or waiver;
- expected return format;
- chosen agent/worker target.

Work orders must be editable before dispatch.

### Return Review

The Project Manager treats worker completion claims as untrusted until verified.

Return review answers:

- what changed;
- what proof ran;
- what proof failed or was missing;
- whether the work matches the approved order;
- whether docs/proposals/pending state should advance;
- whether another agent should audit, fix, or continue.

---

## 5. Start Here, Execute Elsewhere

The product should fit the user's existing tools:

```text
Start in Allnighter to decide and shape the work.
Execute in the user's chosen agent/CLI.
Return to Allnighter to understand and verify the result.
```

This is not a demotion. It is the wedge.

Allnighter only wins if this is faster and calmer than staying inside one agent
session and manually carrying context between windows.

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
- self-attested "done" states.

These may appear later only as narrow support features if the Project Manager
loop proves demand. They must not displace the control loop.

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
The value is still real if the Project Manager writes the exact handoff better
than the user would from memory.

### Level 2 - Direct CLI Dispatch

MVP requirement for the control loop. Allnighter invokes the selected healthy
worker with the assembled work order in the configured Project root and captures
output where the driver supports capture.

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

The first dogfoodable loop should be:

```text
add/open Allnighter as a Project
-> ask Project Manager "what should we do next to make you useful?"
-> receive scoped orientation from docs/git/thread truth
-> receive one bounded proposal
-> approve or edit it
-> dispatch to a chosen agent/CLI or reveal the handoff
-> capture the return
-> verify proof or name missing proof
-> Project Manager recommends the next move
```

This loop must avoid hidden magic. The user should always see:

- selected Project;
- source truth used;
- proposal kind;
- approval state;
- dispatch target;
- proof expectation;
- verification result.

Passing this loop is more important than adding more teams, settings, or visual
polish.

---

## 9. Product Tests

Allnighter is worth continuing when dogfood shows:

- the user starts in Allnighter before opening an execution agent for at least
  one real Project task;
- the Project Manager can answer orientation questions without producing fake
  work orders;
- "what next?" returns one usable bounded proposal;
- the handoff is good enough to send to Claude/Codex/Cursor with little editing;
- the return review catches missing proof, scope drift, or stale docs;
- the next move is clearer after the loop than before it.

Allnighter is drifting when:

- the user spends more time managing Allnighter than the agents;
- the Project Manager cannot explain which Project truth it used;
- fanout produces more ambiguity without a recommendation;
- proposals are broad, vague, or untestable;
- "done" relies on a worker saying it is done;
- the team adds IDE/git/project-board features before the loop is reliable.

---

## 10. Mobile Strategy

Mobile becomes obvious only after the Mac Project Manager loop works.

The iOS app is a remote Project Manager:

```text
from phone:
read Project state
ask the Project Manager
approve/edit/postpone proposals
dispatch bounded work to the Mac
watch returns
verify or request follow-up
```

The phone is not a remote terminal and not a mobile IDE. The Mac owns execution
and run truth. The phone steers the control loop.

---

## 11. Near-Term Roadmap Decision

Prioritize:

```text
Projects as durable local floors
Project Manager chat
Project context packets
Project-scoped Pending with explicit user/CLI/MCP/external-agent triggers
one-next-move proposals
editable work orders
direct dispatch or reveal
return capture
proof-aware verification
fanout/synthesis when judgment is needed
CLI/MCP contracts that expose the same loop
```

Do not prioritize:

```text
Allnighter-managed worktrees
Allnighter-managed commits
landing queues
global Pending queue as product truth
repo safety guarantees
branch/revert ownership
generic project boards
terminal viewing
diff/editor surfaces
```

The narrow bet:

```text
The best way to use many powerful coding agents is not another coding agent.
It is a local Project Manager that keeps the control loop honest.
```
