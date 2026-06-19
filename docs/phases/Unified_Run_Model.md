# Unified Run Model — Chat, Execute, and Teams as One

Status: Decision doc (supersedes the separate Project Manager + Chat/Execute modes)
Owner: AllnighterCore + Mac app + CLI/MCP
Updated: 2026-06-19

## Why this doc

First dogfood on the Allnighter repo failed, and it exposed that we over-built.
Three things were wrong:

1. We invented a **"Project Manager"** as a separate surface (its own view, sidebar
   row, composer, service, cards). It is not a thing. Asking "where are we / what's
   next" is just **chat** — answered by an agent that can see the repo.
2. The Manager (and chat) ran in a **scratch dir with a hand-built ~10-line context
   packet** — no filesystem access. So the model was blind and gave a useless "I
   don't have ground truth" answer. An agent that doesn't read the repo cannot manage
   the repo.
3. We added **gates** (Chat vs Execute mode, propose → approve → dispatch → verify,
   an execution lane the user clicks through). In Cursor/Claude/Codex the agent just
   *does the thing*. A gate between "I see a tiny bug" and "fix it" sends users back
   to their CLI in seconds.

From first principles: **Cursor/Claude/Codex never ask "do you want to execute?"**
You open a repo, you chat, the agent reads and writes as the message implies. That is
the bar. Allnighter's value is not adding ceremony on top — it's putting the CLIs you
already pay for on one bench, in your repo, with reusable presets.

## The core decision

Everything collapses into one primitive:

```text
A run = your message + (optional saved preset prompt) + a model, in the repo root.
```

There is no "Chat mode" and no "Execute mode." There is a model and an optional
preset. The agent runs in the repo with full access and does what the message asks —
answer, explain, fix, build, run. Read vs write is the agent's call, not a mode the
user toggles.

### A "Team" is just a preset

A worker is a prompt + a model. A team is a configured way to run the bench on a
message. So a team is a **preset**, and there are exactly two shapes, by intent:

| Shape | Workers | Direction | Writes repo? | Use |
| --- | --- | --- | --- | --- |
| **Answer team** | many | parallel | no (read-only) | breadth — N models answer the same prompt → a board to compare & pick. Any CLI mix is safe because nobody writes. |
| **Execution team** | one | n/a (single agent) | yes (mutating) | depth/discipline — one prompt + one model runs in the repo and makes the change. |

An **execution team is a team of one** with a (usually longer) preset prompt. Flip the
existing **Mutating team** flag on → the lead + N workers collapse into **one prompt +
one model**. Single-CLI falls out automatically (one worker = one CLI), so the
`ExecutionTeamSourceGate` "single source" rule is satisfied by construction, and there
is **no execution lane to manage** — it's one agent on one repo.

### Default chat = the Default Team

The one feature genuinely missing: **the user picks their go-to chat model.** And it
needs no special case — the default chat is *just a Default Team*:

- It is a team of one (your go-to CLI/model).
- It may carry a preset prompt you customize, or leave blank.
- It is allowed to mutate (same as any execution team — talk *or* build).

So default chat, an execution team, and an answer team are **the same object** with
different settings. Consistency by construction. The user can leave the Default Team's
preset blank (raw chat) or pre-fill it (every chat starts disciplined). Their call.

### Ship the Execution Playbook as a preset

`docs/operations/Execution-Playbook.md` is a sophisticated prompt that turns a raw
agent into a disciplined senior engineer (slice → narrow edits → proof → deslop →
audit → commit). That discipline **is** the product. Allnighter ships it as the
**built-in default execution preset** — editable, bring-your-own-`AGENTS.md`. A user
who never wrote a playbook runs yours for free; a power user drops in their own. No
raw CLI gives you that.

A single CLI agent is already an agentic loop, so **one worker + a rich preset does
the whole disciplined sequence itself, in order** — we do not need multiple agents to
get multi-step execution.

## What changes

### Kept / repurposed
- **Teams + Skills + ModelCatalog/Bench** — the substrate; now "presets."
- **Mutating team flag** — now means: single executor, may write the repo. Turning it
  on collapses workers → one prompt + one model.
- **Single-source rule** — kept, but satisfied automatically (one worker).
- **Run the agent in the repo root** — dispatch already does this
  (`workerCwd = project root`); chat must do the same instead of a scratch dir.
- **Answer board (send-to-team parallel)** — unchanged; this is the Answer team.
- **Projects rail / project = repo / thread→project binding** — unchanged; the repo is
  the working directory for every run in that project.
- **Set a default model** — newly added as the Default Team's model.

### Deprecated (remove from the user-facing flow)
- The separate **Project Manager** surface: `ProjectManagerView`,
  `ProjectManagerViewModel`, the sidebar "Project Manager" row, the PM cards as a
  *flow*, `ProjectManagerService` (thin-packet), `ProjectManagerTurnStore`.
- The **propose → approve → edit → postpone → dispatch → verify ceremony** as a
  user-facing path. (Verification/proof can still exist as something a preset prompt
  instructs the agent to run — but it is not a gate the user clicks through.)
- The **Chat / Send-to-team / Execute** three-mode composer → becomes "pick a team
  (preset) + model"; the default is your Default Team.
- The **execution lane as user-facing ceremony.** (Concurrency only matters if two
  agents write one repo at once — which the model avoids: answer teams don't write,
  execution teams are one agent.)

## Non-goals / inference bans

- **No gate between intent and action.** If the user asks an in-repo agent to make a
  change, it makes the change. We never insert an approval step the user must clear to
  do what they already asked.
- **No second permission layer.** Allnighter inherits each CLI's own permission/diff/
  undo model; it does not add its own confirmation ceremony on top.
- **No agent runs blind.** Every run's working directory is the project repo root; the
  agent reads real files, not a hand-assembled summary. A context packet, if used at
  all, is a hint — never the source of truth.
- **No parallel writers.** Answer teams are read-only; execution teams are one agent.
  Multi-writer orchestration is not a thing.

## Open questions / future

- **Default Team preset: raw or lightly disciplined by default?** Lean: raw by default
  (just your message + model), one tap to attach a preset. User-configurable either way.
- **Sequential multi-agent chains** (different model per step — e.g. implement with
  Codex, audit with Claude): a clean *future* extension — an execution preset that is
  an **ordered list of single-executor steps**, run one after another. Not v1; one
  worker + a rich preset covers ~95%.
- **Where the default-model setting lives** — the CLI setup screen ("make this my
  default") vs a one-line global preference.

## Done when

- There is no separate "Project Manager." Default chat in a project is an agent in the
  repo, on a model the user chose, that answers and builds with no mode switch.
- A run is `message + optional preset + model`, executed in the repo root.
- "Teams" are presets: answer (many, parallel, read) or execution (one, write).
- The Default Team carries the user's go-to model and an optional, editable preset.
- The Execution Playbook ships as the built-in default execution preset.
- No approval gates, no Execute mode, no execution-lane ceremony in the user flow.
