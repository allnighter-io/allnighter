# CLI Product Spine

Status: Draft for mentor feedback
Owner: Founder + Shared Core + CLI + Mac
Updated: 2026-06-15

## Founder Intent

Allnighter should not be trapped inside a menu bar app. The product coordinates
CLIs, so the CLI should be a first-class product surface rather than a debug
sidecar.

The Mac app still matters. It is the visual floor manager. But the command line
should be the spine: scriptable, testable, agent-callable, and semantically
identical to what the GUI renders.

## Thesis

```text
Product: Allnighter
Daily command: alln
Primary operation: alln team
Mac app: visual floor manager over the same command model
iOS app: remote floor manager over the same command model
```

`allnighter` is too long for a daily command. `nite` is cute but non-obvious.
`nt` is short but already collides in package ecosystems. `alln` is short,
brand-linked, available enough in the checks run so far, and easy for agents and
humans to type.

## Why CLI First

1. **Native habitat.** Allnighter orchestrates the CLIs the user already pays
   for. A great CLI is not a lesser GUI; it is the native control surface.
2. **Forces clean architecture.** If the CLI is first-class, product truth cannot
   hide in SwiftUI state or menu-bar affordances.
3. **Makes agents better users.** Codex, Claude Code, Aider, Cursor, and other
   tools can call `alln` directly instead of reading a GUI.
4. **Makes proof easier.** CLI commands produce deterministic output, fixtures,
   and Works Tests before polished UI exists.
5. **Clarifies background mode.** Foreground CLI commands can be ephemeral; long
   runs, iOS, and overnight work can opt into a resident coordinator.

## Command Grammar

The default command should read like the product promise. `team` asks models to
show up as workers:

```bash
alln team "Pressure-test this launch plan."
alln team --file prompt.md
alln team --lane build --effort deep "Plan this feature."
alln team --lane copy --type landing-page "Rewrite this page."
alln team --lane design --image screen.png --brief "Make this calmer."
```

Core commands:

```bash
alln team [prompt]                 # ask the default team
alln team show                     # show current default team
alln team edit                     # edit team lineup
alln models                        # list ready/known models on the Bench
alln models add                    # add/configure a model
alln skills                        # list reusable skills
alln doctor                        # check local CLIs and auth
alln work [prompt]                 # create a work order
alln work from latest              # promote a plan/result into a work order
alln history                       # list recent runs
alln show latest                   # show one run
alln export latest --format md     # export result bundle
alln dispatch latest --to codex    # send a work order/spec to an execution target
alln pair approve <device-id>      # approve iOS/Mac pairing
```

Do not use `alln prompt` as the primary work-order command. A prompt is the input
object. The product object is a work order, so the command is `alln work`.

Lane shortcuts may exist later:

```bash
alln build "Implement this feature."
alln design screen.png --brief "Improve this screen."
alln copy "Write a launch email."
```

But the canonical primitive remains `team`: one prompt, selected worker lineup,
worker answers, synthesized plan/result.

Vocabulary:

```text
Source = how Allnighter reaches a model
Model  = Opus, Sonnet, Grok, Gemini, etc.
Skill  = the hat/instruction
Worker = model + skill for this run
Team   = workers selected for this job
Bench  = available models
```

CLI surfaces:

```text
Bench/setup: alln models
Run/customize: alln team
Work-order creation: alln work
```

## Output Contract

Default human output should be compact and useful:

```text
Run run_20260615_2214
Team: 4 workers · Build · Deep

✓ Opus / First Principles      1m42s
✓ Sonnet / Skeptic             1m10s
✓ Codex / Maintainer           2m04s
✗ Gemini / Proof Skeptic       auth expired

Plan written by Opus.

Next:
  alln show run_20260615_2214
  alln export run_20260615_2214 --format md
  alln dispatch run_20260615_2214 --to codex --cwd .
```

Machine output should be explicit:

```bash
alln team --json "..."
alln show latest --json
```

JSON is for agents, GUI tests, and external tooling. Markdown is for humans.

## App Shell Implication

The GUI should render and send the same typed instructions the CLI exposes.

Preferred implementation shape:

```text
AllnighterCore command model
-> alln CLI
-> Mac app presenter/actions
-> optional local coordinator for long-running/resumable work
-> iOS remote client
```

The Mac app should not invent GUI-only semantics. It should issue the same
operations a CLI user could issue: ask team, customize team, stop run, show run,
export, dispatch, pair, revoke.

Implementation detail to decide with mentors:

| Option | Upside | Risk |
| --- | --- | --- |
| GUI shells out to `alln` | Total parity; easy dogfood | Process overhead, brittle parsing, harder live state |
| CLI and GUI share `AllnighterCore` command handlers | Fast, testable, native | Requires discipline to keep parity visible |
| CLI and GUI both talk to local coordinator | Best for iOS/overnight/resume | More daemon complexity early |

Recommended posture: build shared command handlers first; add a local
coordinator when long-running and remote workflows require it. Keep the CLI as
the golden grammar and proof surface either way.

## Foreground vs Resident Mode

Not every use requires a background process.

Foreground:

```bash
alln team "..."
```

Runs directly, streams status, writes the run journal, exits when done.

Resident:

```bash
alln serve
```

or an app-installed login/background helper handles:

- iOS remote commands;
- long runs after GUI windows close;
- overnight utilization;
- notifications;
- resumable event streams.

The product should not pretend the Mac can be controlled while Allnighter is not
running. If resident mode is off, iOS says the Mac is offline.

## Naming Decision Proposal

Adopt:

```text
Product/app: Allnighter
CLI binary: alln
Primary command: alln team
Bench command: alln models
Work-order command: alln work
Background service: defer public name; internal helper is fine
URL scheme: allnighter:// for app links, with universal links where needed
```

Do not ship public `alln council` or `alln panel` aliases.

## Mentor Feedback Needed

1. Should `alln team "prompt"` be the primary command, or should `alln ask`
   exist as the top-level happy path?
2. Should the Mac app invoke shared command handlers directly, shell out to
   `alln`, or talk to a resident coordinator from day one?
3. Should resident mode ship in the first CLI milestone, or wait for iOS/overnight
   workflows?
4. Are lane shortcuts (`alln build`, `alln design`, `alln copy`) helpful, or do
   they dilute the Team primitive too early?
5. Is `alln` acceptable as the binary name despite being aesthetically rougher
   than `nt` / `nite`?
6. Is `alln work` the right command for creating/promoting work orders, or is a
   longer `alln work-order` worth the clarity?

## First Milestone

Build the CLI before more GUI wiring:

1. `alln doctor`
2. `alln models`
3. `alln team show`
4. `alln team "prompt"` using the current default team
5. `alln show latest`
6. `alln export latest --format md`

Works Test:

```bash
alln doctor
alln team "Give me three ways to simplify the Allnighter CLI."
alln show latest
alln export latest --format md
```

The same run must appear in the Mac app without translation or renamed fields.
