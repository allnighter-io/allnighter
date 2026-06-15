# Allnighter Agent Control Loop Strategy

**Status:** Strategy anchor  
**Owner:** Founder + CTO  
**Created:** 2026-06-14  
**Purpose:** Preserve the product boundary so Allnighter stays focused on the
highest-value wedge: orchestrating, synthesizing, dispatching, and evaluating AI
agent work across the user's existing CLIs.

---

## 0. One-Page Brief

Allnighter is not a git management product.

Allnighter is the **agent control loop**:

```text
ask many agents
-> synthesize what came back
-> pressure-test the plan
-> dispatch to chosen agents
-> collect what came back
-> compare/evaluate outputs
-> let the human choose, remix, or send another round
```

The user's CLIs and repo process already execute work. Allnighter's job is to
remove the high-friction coordination layer around them: copy/paste, prompt
assembly, model selection, parallel dispatch, result collection, synthesis,
review, and next-step routing.

The strategic boundary:

```text
Allnighter owns orchestration, synthesis, dispatch, and evaluation.
Agents own execution.
Repos own git/process policy.
```

---

## 1. Why This Matters

The founder pain is not:

```text
I need a branch manager.
```

The founder pain is:

```text
I asked several agents.
They came back with different plans, diffs, and suggestions.
I need to understand the tradeoffs quickly.
I need to send the next best prompt without copy/paste.
I want to steer this from Mac and mobile.
```

That is the product.

Direct dispatch is core because otherwise Allnighter stops at "nice planning
tool" and hands the time-saving moment back to the terminal. If the user already
trusts Claude Code, Codex, Grok, Aider, Cursor, or another CLI to edit a repo,
Allnighter should be able to send the final spec to that CLI as configured.

---

## 2. Product Thesis

Allnighter should make a developer feel like they have a bench of agents and a
floor manager:

```text
one prompt
-> multiple expert reads
-> one synthesized plan
-> optional review pods
-> final spec
-> direct dispatch
-> returned outputs summarized and compared
-> next dispatch
```

This is especially valuable for vibe coding because the human is not trying to
manually operate four terminals. The human is steering judgment:

- Which agent had the best idea?
- Which implementation is simplest?
- Which output is most aligned with the desired UX?
- What did the security/maintainer/design lenses catch?
- Should we pick one, remix two, or ask another round?
- Which agent should execute the next step?

Allnighter should compress that loop.

---

## 3. What Allnighter Should Be Best At

Allnighter should be excellent at:

1. **Fanout** - send one prompt/spec to several configured workers in parallel.
2. **Synthesis** - produce a decisive plan or final spec from multiple outputs.
3. **Role review** - send the draft/final work through configurable lenses such
   as security, design, maintainer, customer, proof/QA, and dissent-preserver.
4. **Direct dispatch** - send the selected spec to the chosen CLI/model without
   copy/paste.
5. **Return review** - capture outputs/transcripts and help the human evaluate
   what came back.
6. **Mobile command** - let the user run the same control loop from the phone.
7. **Process guidance** - recommend repo instructions and agent playbooks without
   owning the repo lifecycle.

The core loop is not complete until results come back and the human can compare
them quickly.

---

## 4. What Allnighter Should Not Own First

Allnighter should not take on git/worktree/commit management in the MVP.

The upside is currently low relative to the complexity. It pulls the product
into:

- dirty worktree state;
- branch naming and cleanup;
- commit policy;
- protected paths;
- merge conflicts;
- landing queues;
- revert semantics;
- preview/test gates;
- CI interpretation;
- trust claims around repo safety.

Those are real problems, but they are not the wedge. They are also already being
worked on by CLIs, IDE agents, repo tooling, and developer workflows.

The MVP claim should be narrower and more useful:

```text
Allnighter dispatches to the CLI you selected in the working directory you chose.
The selected CLI may edit files.
Git behavior is controlled by that CLI, its configuration, and the prompt.
Allnighter is not creating a worktree or managing commits.
```

That is honest, useful, and shippable.

---

## 5. Levels Of Execution Support

Allnighter can grow through levels without confusing the core product:

```text
Level 1 - Copy/reveal prompt
Level 2 - Direct CLI dispatch
Level 3 - Recommended repo process
Level 4 - Return review and output comparison
Level 5 - Managed execution safety
```

### Level 1 - Copy/Reveal Prompt

Fallback for manual workers, unhealthy CLIs, or unsupported tools.

### Level 2 - Direct CLI Dispatch

MVP requirement. Allnighter invokes the selected healthy worker with the assembled
prompt/spec in the configured working directory and captures output where the
driver supports capture.

### Level 3 - Recommended Repo Process

Allnighter can provide optional process kits:

```text
AGENTS.md template
Execution-Playbook.md template
CLAUDE.md / CODEX.md style agent instructions
recommended proof commands
repo standing orders
closeout checklist
commit/PR guidance
```

These are recommendations and copyable files. They help users make their repos
agent-friendly without Allnighter owning git state.

### Level 4 - Return Review And Output Comparison

This is the higher-value next layer:

```text
four agents return
-> Allnighter captures outputs/transcripts
-> evaluator summarizes each result
-> design/security/maintainer lenses review the results
-> final synthesizer recommends pick, remix, reject, or rerun
```

This keeps Allnighter focused on judgment and iteration, where the differentiation
is strongest.

### Level 5 - Managed Execution Safety

Worktrees, branch policy, protected paths, landing, preview, test gates, and
revert can come later if user demand proves that Allnighter should own those
claims. This should not block the MVP.

---

## 6. Mobile Strategy

Mobile becomes obvious when Allnighter owns the control loop:

```text
from phone:
ask the council
read synthesis
dispatch implementation
watch agents return
compare results
send another round
```

The mobile app is not just a remote terminal. It is a command surface for agent
judgment and dispatch.

The magic is that the user does not need to sit at the Mac babysitting CLIs. The
Mac owns execution; the phone steers the loop.

---

## 7. Strategic Position

Allnighter should avoid competing with every agent and IDE on repo automation.

The durable wedge is:

```text
the best way to coordinate, judge, dispatch, and evaluate a bench of agents
you already use
```

That path compounds as more CLIs appear. Every new CLI makes Allnighter more
useful as the control layer above them.

The product should stay opinionated:

- Use the tools users already trust.
- Make parallel judgment cheap.
- Make direct dispatch immediate.
- Make returned outputs easy to understand.
- Make another round effortless.
- Offer process kits, but do not require Allnighter to own git.

---

## 8. Decision

The MVP and near-term roadmap should prioritize:

```text
configurable synthesis
review lenses / design pods
final spec
direct executor dispatch
return review / comparison
mobile control loop
optional repo process kits
```

The MVP and near-term roadmap should not prioritize:

```text
Allnighter-managed worktrees
Allnighter-managed commits
landing queues
repo safety guarantees
branch/revert ownership
```

Those can return later as a managed-execution layer if they become a proven user
pain. They should not displace the agent control loop.

