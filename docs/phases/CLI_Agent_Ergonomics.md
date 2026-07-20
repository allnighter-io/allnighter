# CLI Agent Ergonomics — stop making agents guess what exists

Status: **Implementation Complete (2026-07-20) — pending deslop / code audit / archive.**
All slices AE-S00…S15 shipped on `feat/design-chain` (contractVersion `1.6.0`).
Parent owns deslop, Code Audit, and archive; do not archive from this closeout.
Hardened by three passes: code verification of all 11 original claims (7 refuted),
a six-vendor harness study (AE-S00, executed), and founder rulings on catalog
purge + SSOT-generated help. Every finding below is verified against code or a
live binary; refuted claims are kept visible so they are not "fixed" later.
Successor to archived `CLI_Agent_Surface_Fidelity.md` (ASF). ASF made the CLI
**honest in what it says**. This phase makes it **complete in what it reveals**
and **leak-free in what it enforces**.
Owner: AllnighterCLI (`AllnighterCLI.helpText`, `Options` parser, `RunCLI`) +
AllnighterCore (`ContractRegistry`, contract lock, `TeamCatalog.isLabTeam`,
error catalog) + AllnighterEngine
(`RunService` explicit-worker choke point)
Updated: 2026-07-20

Related: archived `CLI_Agent_Surface_Fidelity.md` (the teaching-surface fix and
the origin of Laws 5/7/8) · `Team_Depth_Naming.md` (owns Min/bare/Max naming —
**do not re-decide here**) · archived `Team_Catalog_Normalization.md` ·
`Team_Lab_Run_Factory.md` (§"No silent champion flip into production
TeamCatalog") · `Language_Cutover.md` (owns lane vocabulary) ·
`docs/workflows/SSOT_Feature_Workflow.md` §Teaching Surface Rule

## What happened (and the finding that matters most)

Three AI agents were asked to build and test `alln` cold. Two produced detailed
adoption feedback in which **seven claims are factually wrong**, including the
most severe one — and they *missed* a real bug.

**The third agent succeeded, and the difference is the entire phase.**

Mentor 3 read the `bootstrap` snippet first, found `alln team hello --for`, and
ran `alln team hello --for "ask sonnet 5 a question"`. It resolved the intent to
`model_sonnet` (Sonnet 5 via `claude_code`), returned a runnable command, and
**proactively flagged the name collision** with Antigravity's "Claude Sonnet
4.6" as a loud alternate. Verdict: *"genuinely impressive."*

Agent 2, given the identical task, concluded **"Sonnet 5 does not resolve, no
fuzzy suggestions"** and filed it as a high-severity gap.

Same product. Same machine. Same intent. One agent found the front door; two
did not. The capability Agent 2 declared missing is not merely present — it is
the best thing we ship. It is simply **invisible from `alln --help`**.

That is the whole thesis in one experiment: **we are not missing features, we
are failing discovery.** Mentor 3 independently confirmed the mechanism —
*"the bootstrap snippet mentions `alln team hello --for` and `alln help search`,
but the top-level help doesn't show these."*

The same pattern repeats across the feedback. Agent 2 accused the CLI of silent
model substitution; we ship a recipe card literally titled
**"use-a-specific-model-without-silent-substitution"** — which Agent 2 never saw.

That is not a knock on the agents. It is the finding. Two capable models,
reading the CLI's own surfaces, built a materially false map of the product.
**When agents hallucinate absence, the surface — not the model — is the defect.**

Every wrong claim traces to one of three surface defects:

| They concluded | Because |
| --- | --- |
| "No `--version`" | It is absent from the hand-written `--help` banner |
| "No preflight for `run`" | `team preflight` is absent from `--help` too |
| "Min Bug Hunt is not first-class" | 8 identically-named `Bug Hunt · Lab` rows drown it |
| "`--worker` silently substitutes and spends" | Probed a **stale binary** at a different git SHA |

So the highest-leverage work is not new features. It is making the CLI's own
surface **describe the product truthfully and completely**. Fix that, and a
whole class of downstream agent errors disappears at once — including agents
"working around" capabilities that already exist.

> ASF: *stop teaching a CLI we no longer ship.*
> This phase: *stop making agents guess what exists.*

## Verified findings (probed against code + a live binary, 2026-07-20)

**Real problems — this phase owns them:**

| # | Finding | Evidence |
| --- | --- | --- |
| 1 | **`--help` is a hardcoded 31-line string literal**, not generated. Registry declares ~100 commands. Missing: `teams`, `team hello`, `team preflight`, `help search/get/topics`, all `project` (11), `thread` (5), `skills` (5), `pending` (9), `stalled`, `floor show`, `spec`, `defaults`. | `AllnighterCLI.swift:1755+` `helpText()` |
| 2 | **The completeness gate exists and is neutered by a ~70-command allowlist** — including the entire golden path. `team hello` is excluded because it is *"surfaced via `alln team hello`"*. | `CLIHelpDriftTests.swift:10-48` |
| 3 | **PO-F10 leaks on the answer path.** `runAnswer` has **no `workerOverride` parameter**; the call site never passes one. So for a non-mutating team, `--worker` is accepted, echoed into the idempotency payload, and **silently dropped**. The execution path enforces it correctly. | `RunService.swift:1715-1733` vs `:912-919`; enforced at `:1009-1015` |
| 4 | **No free way to validate a `run`.** No `--dry-run`/`--preflight`/`--validate`; registry has only `run` + `run resume`. `team preflight` cannot substitute — it has **no `--worker` or `--project` flag**, the two things `run` requires. | `RunCLI.swift` flags; `ContractRegistry+Milestone1.swift:282-290` |
| 5 | **No cwd→project for `run`**, though the pattern exists everywhere else (`team`, `ps`, `kill` all use `currentDirectoryPath`) and resolve-by-path already works. | `RunCLI.swift:44-46` vs `AllnighterCLI.swift:1172, 1338, 1542-1546` |
| 6 | **`teams` never calls the lab filter that already exists.** `TeamCatalog.isLabTeam` has exactly **one** consumer (`AgentIntentRouter`). Result: 31 teams in lane `code`, 14 `lab_*`, 8 sharing the display name `Bug Hunt · Lab`. | `TeamCatalog.swift:338-340`; `AgentIntentRouter.swift:295` |
| 7 | **Generated docs teach a lane that does not exist** — `"build \| design \| copy"` on `skills new`, `team preflight`, `team start`. Real lanes: `code\|design\|copy\|signal`. ASF's deny-list guards *commands*, not *enumerated flag values*. | `ContractRegistry+Milestone1.swift:250, 285, 295` |
| 8 | **`nextAction` is runnable but wrong.** Unknown team in preflight returns `blockedReason: "unknown team … run alln teams"` while `nextAction.command` says `alln doctor --json`. The machine field contradicts the prose. No "did you mean" for an id one token off. | live probe: `team preflight --team code_bug_hunt_typo` |
| 9 | **Seat count disagrees with itself.** `teams` reports `workerCount: 3` for `code_bug_hunt_min`; `team preflight` resolves **4** ready workers (catalog count omits the lead row). | live probe; `TeamResolver.swift:233` |
| 10 | **`--effort` does not change seat count** — agents reasonably assume "low = smaller/cheaper team" and pay full. | `TeamResolver.swift:98` |
| 11 | **Two binaries at different SHAs in one workspace** (`.build/debug` at `791d591e`, installed at `ce65caf3`). ~~Almost certainly the source of the false "silent spend" report.~~ **Superseded 2026-07-20:** finding 14 is the better explanation. Still a real identity defect (AE-S08). | live `--version` comparison |
| 14 | **Unknown flags are silently swallowed; exit 0.** No `UNKNOWN_FLAG` code exists in the source. `--totally-bogus-flag`, `--jsonn`, `--bogus-flag` all exit 0 with the flag discarded. **Safety consequence: `alln run "…" --dry-run` discards the flag and dispatches a real spending run** — a nonexistent safety flag is a live dispatch, which explains Agent 2's "accidental run while probing shapes" without needing the stale-binary theory. | `AllnighterCLI.swift:1912`; verified live |
| 12 | **Phantom command: help invents a surface that does not exist.** `alln config --help` prints `usage: alln config` — implying the command is real — while `alln config` returns `unknown command: config`. The inverse of finding 1: where `--help` under-reports what exists, the `--help` *handler* over-reports it. Any `alln <anything> --help` likely fabricates a usage line. | Mentor 3 transcript |
| 13 | **The catalog ships non-product.** 14 `lab_*` teams plus `code_core` are Team Lab artifacts living in the production `TeamCatalog`, violating `Team_Lab_Run_Factory.md` §"No silent champion flip into production TeamCatalog." Founder ruling 2026-07-20: **we do not have 31 teams — delete them.** | live `teams --lane code --json` |

**Refuted — do NOT "fix" these:**

| Claim | Reality |
| --- | --- |
| `--worker <bad-id>` silently substitutes and dispatches | **Fails closed**: exit 1, `WORKER_NOT_AVAILABLE`, no dispatch. PO-F10 enforced (`RunService.swift:1009-1015, 238-249`). Claim is inverted — a non-empty worker id **skips** Auto. |
| No `--version` / no build identity | Both `alln --version` and `alln version --json` work, with `gitSha` + `buildTime` (ASF-S06, `BuildInfo.swift`). |
| `alln mcp` should print serve/install recipe | MCP is **retired**. No `mcp` command exists; absence is correct. Printing MCP recipes would re-violate ASF. |
| Ship a `code_bug_hunt_min` | Already a built-in: `builtIn: true`, **row 2** of `teams --lane code`; all built-ins sort before all lab teams. Discovery failure, not a missing object. |
| `team preflight --help` returns a JSON error | Prints proper usage, exit 0. |
| `project --help` dumps root help | Prints correct subcommand usage. |
| `team hello` dumps lab clones | Returns 3 teams, **zero** lab teams — it already calls the filter. |

## Vendor harness study — AE-S00 executed 2026-07-20

The same 7-question probe was sent to six vendor CLIs through `alln run --worker`
(Opus 4.8, Grok 4.5, Cursor Composer 2.5, Gemini 3.5 Flash, GLM 5.2, ChatGPT 5.6
Sol), each asked to introspect **its own tool-selection layer** — the mechanism
by which a model picks the right capability from an unfamiliar surface with no
human in the loop. Raw transcripts: session scratchpad `probe_*.json`.

This is the prior art that matters. These harnesses solve *agent* capability
selection at production scale; kubectl and terraform solve *human* ergonomics.

**Unanimous findings (6/6, independently):**

1. **`hello` is the wrong name.** Every vendor flagged it unprompted. "Reads as
   a greeting/health-check" (Opus). "Anti-discoverable name for intent
   resolution" (Grok). "Metaphorical — I would read it as onboarding,
   connectivity testing, or greeting the configured team" (ChatGPT). A name that
   misleads is worse than no name, because agents skip it *after* seeing it.
2. **A partial list that does not announce its partiality is the root cause.**
   "Under-disclosure doesn't produce hesitant agents. It produces confidently
   wrong ones" (Opus). "Incomplete-but-confident docs cause false negatives more
   than missing docs" (Grok). "I treat top-level listings as exhaustive unless
   told otherwise" (Cursor).
3. **The failure mode at scale is false absence, not wrong-tool.** "Recall
   breaks first" (Opus). "Confident omission, not random thrashing" (Grok).
   "False absence — 'this capability doesn't exist' — your 2/3 failure mode"
   (Cursor, naming our exact bug unprompted).
4. **Every harness solves scale with two-tier disclosure plus a completeness
   guarantee** — a complete list of *names* (cheap) and a hydrate step for
   schemas (on demand). Opus: *"the deferred list is complete. It is not 'the 19
   most common of 40.' If a tool isn't listed, it does not exist, and I can rely
   on that. `alln --help` breaks exactly this invariant."*
5. **Trigger text phrased as a situation beats capability description.** Ranked
   #1 or #2 by five of six. The winning shape is `Use when the user says X` /
   `TRIGGER — whenever…`, not "Intent phrase to route."
6. **Anti-examples are top-3 for every vendor and omitted by almost every CLI.**
   "Do NOT use this when…" is the cheapest unclaimed win on the board.
7. **Parameter schemas drive correct invocation, not selection** (5/6 explicit).
   We have invested in schemas; selection is where we are thin.
8. **The scale cliff is ~20–40 flat items.** Estimates: 20–30 (Opus), 15–40
   (Grok), 20–40 (Cursor), ~15 (Gemini), 20–30 (GLM). **`alln` exposes 108.**
   Opus adds the sharper variable: *near-neighbor density* beats raw count —
   "fifteen tools that all sort of run something — `run`, `team run`,
   `team start`, `pair`, `panel`, `serve` — is hard, and alln is that shape."
9. **Errors must route, not report.** One-turn recovery = error naming the
   nearest valid candidates + the exact next command. Worst possible outcome,
   named independently by Opus and Grok: **silent success**.
10. **Patience is ~2–3 discovery attempts**, then agents route around us to the
    vendor CLI directly. Strategic framing (Opus): *"alln's competitor is not
    another orchestrator. It's the vendor CLI one layer down, always installed,
    always in PATH, needing zero discovery. You get about two commands of
    patience before I route around you."*

**Two predictions that landed:**

- ChatGPT, without seeing Agent 2's transcript, predicted its exact path:
  *"'Sonnet 5' sounds like model selection, so I would look under `models`, not
  under the metaphorical `team hello`."* Agent 2 ran `alln models --json`,
  found no Sonnet 5, and filed the false report. `models` must therefore carry
  intent-aware recovery pointing at the resolver.
- GLM explained the phantom-command class: *"Absence of evidence is not evidence
  of absence to me — I pattern-match by default. If every CLI in my training
  data has `init`, `status`, `list`, I will assume `alln init` exists unless
  `--help` explicitly tells me otherwise."* Cursor confirmed finding 12 from the
  other direction: *"I'll assume `config` exists because `config --help` printed
  usage."*

**Severe bug surfaced by the study (verified independently):** Opus found that
`Options` (`AllnighterCLI.swift:1912`) **swallows every unknown flag** — no
`UNKNOWN_FLAG` code exists anywhere in the source. Confirmed live:
`alln teams --lane code --totally-bogus-flag`, `--jsonn`, and
`alln version --bogus-flag` all exit **0**. Opus's assessment: *"the single
worst property an agent-facing CLI can have… a wrong exit-0 manufactures false
beliefs about behavior, which I then report to you as fact."*

**This retires the stale-binary theory for Agent 2's accidental run.** Any
safety flag an agent reasonably assumes exists — `--dry-run`, `--validate`,
`--no-execute` — is today **silently discarded, and the run executes for real**.
A nonexistent safety flag is not an error; it is a live dispatch. That is a P0
safety defect independent of everything else in this phase.

**Already-built halves the study identified:** `CLIUsage.usageTextForPrefix`
(`CLIUsage.swift:53`) already projects command subtrees; `alln dev
export-contracts` already emits the full 108-command manifest to
`docs/generated/alln/alln-contract.json`; `HelpCLI.swift:50` already prints
`did you mean:` from `closeMatches` — but wired to help *topics*, not commands.
Opus's summary: *"The 108-entry registry is your deferred-tool list. You built
it, then hid it behind a hand-written banner that shows a quarter of it."*

## Root patterns (why this recurs)

**Pattern A — The allowlist is where gates go to die.** Third instance of one
failure mode. ASF found (1) a frozen MCP vocabulary that made a gate *require*
dead grammar and (2) a hardcoded 4-word retired-vocab list. Now (3) a 70-entry
`excludedFromTopLevelHelp`. Each began as a reasonable accommodation with a
tidy comment. Each ended up encoding the drift as intended behavior. ASF Law 8
said *fix the code, never narrow the gate*; the allowlist is how a gate gets
narrowed without anyone feeling like they narrowed it.

**Pattern B — A law enforced at N call sites leaks at N−1 of them.** PO-F10 is
correct on the execution path and absent on the answer path. `isLabTeam` is
called by 1 of 2 list surfaces. Lane vocabulary is right in 2 places and wrong
in 3. The recurring defect is not ignorance of the law — it is that the law
lives in the callers instead of in one choke point.

**Pattern C — Hand-authored surfaces drift; generated ones cannot.** `--help`
is a string literal maintained by hand, so it will drift again next week no
matter how carefully we fix it today. ASF already proved this for help prose.
The same medicine applies: generate from `ContractRegistry`, or gate with no
allowlist.

**Pattern E — We re-derive solved problems under incident pressure.** Every
recent phase was triggered by a dogfood incident and scoped to that incident,
which reliably produces a local fix and never a standard. The tell is
`helpText()`: a hand-maintained string literal in a codebase that already owns a
complete command tree (`ContractRegistry`). No mature CLI hand-writes help —
clap, cobra, oclif, and Swift's own ArgumentParser all render help, usage,
validation, and completion *from the declaration*. We built the declaration and
then hand-wrote every rendering of it, so each rendering became an independent
drift surface. That is the mechanical reason drift keeps recurring under
different names. Root process gap: `SSOT_Feature_Workflow.md`'s planning order
never once said "check how this is already solved elsewhere" — so we didn't.
(Fixed 2026-07-20: Prior Art is now step 2 of the planning order.)

**Pattern D — Absence is inferred, and inference is expensive.** Agents treat
an incomplete listing as an exhaustive one. Under-reporting does not merely slow
an agent down; it makes the agent confidently report the product is missing
features it ships — and then build workarounds. This is the mechanism that
turned real capability into "pathetic" first-contact feedback.

## Laws

1. **The surface is exhaustive or explicitly says it is not.** Every contracted
   command appears in `--help`, or `--help` names the family and points at the
   command that lists the rest. No silent omissions.
2. **Absence means "you choose"; a value means "this or fail."** An omitted
   identifier flag may resolve to Auto/default. A *provided* identifier that
   does not resolve is always an error with suggestions — never a substitution,
   never accepted-and-dropped. (Generalizes PO-F10 to `--worker`, `--team`,
   `--project`, `--skill`, `--lane`, `--model`, and every future id flag.)
3. **Probing is free; spending is explicit.** Every quota-spending command has a
   free, read-only twin that resolves the same identifiers and returns the same
   facts. Agents learn by executing — so exploration must never cost.
4. **One choke point per law.** A rule enforced in callers is a rule that leaks.
   Explicit-identifier resolution, lab filtering, and lane validation each get a
   single enforcement point that every surface routes through.
5. **Every allowlist entry carries a reason and an expiry, and is reviewed at
   Done-When.** An allowlist that can grow silently is a gate that can die
   silently. (Extends ASF Law 8.)
6. **Errors are the documentation agents actually read.** An error names what
   was wrong, the top-3 near-matches, and the one command that lists valid
   values — and its structured `nextAction` must match its own prose.
7. **The catalog is product, not workspace.** `TeamCatalog` contains only what
   we ship plus what the user made. Experiments, lab champions, and candidates
   live in lab storage and never appear in a product list. Enforced at the write
   path — a read-side filter is a workaround, not a law.
8. **Never invent a surface in an error or help path.** A `--help` handler must
   not print usage for a command that does not exist (`alln config`). Help is
   generated from the registry or it is not printed.
9. **Adopt before you invent.** If a mature CLI has solved a problem, the
   default is to match its convention and record the decision; deviating
   requires a written reason. (See AE-S00.)
10. **Observed facts, never projections.** Preflight may report resolved seat
   count, source count, and effort — never token or cost estimates
   (no-estimates law, `Cost_Advisor` parked scope).

## Anti-goals

- Do not add a second way to do anything that already works. Seven refuted
  claims are seven invitations to build a duplicate; refuse all seven.
- Do not "fix" fail-closed on the default route — it is correct today. Fix the
  **answer-path leak** only.
- Do not re-decide team naming (`Team_Depth_Naming.md` owns Min/bare/Max) or
  lane vocabulary (`Language_Cutover.md` owns it). This phase owns the **gate**
  that keeps generated docs from teaching a dead lane, not the vocabulary.
- Do not auto-resolve fuzzy model aliases (`sonnet` → `model_sonnet`).
  Auto-resolution of an ambiguous name is silent substitution wearing a friendly
  hat — the exact class Law 2 forbids. Suggest; never substitute.
- Do not make output format depend on TTY detection (see Rejected).
- Do not delete lab teams or change Team Lab semantics — only stop listing them
  by default.

## Slices

Ordered by leverage. S01/S02/S06 are near-free and fix the largest share of the
false-map problem.

| Slice | Deliverable |
| --- | --- |
| **AE-S00 ✅ DONE (2026-07-20)** | **Steal the wheel — prior-art survey.** Executed: six vendor harnesses probed via `alln run --worker` on their own tool-selection layers; findings in §Vendor harness study above, and they reshaped this phase (new S12–S15, revised S01/S13). Remaining optional tail: the infra-CLI conventions below, now lower priority than the harness findings. One pass over CLIs that solved this decades ago, producing a decisions table we adopt rather than re-derive: **generation** (Swift ArgumentParser / clap / cobra / oclif — help, usage, completion and validation all rendered from one command declaration); **preflight/apply separation** (`terraform plan`, `kubectl --dry-run=server`, `rsync -n`, `apt --simulate`); **machine output** (`kubectl -o json`, `gh --json`, `git --porcelain`); **did-you-mean** (git, cargo, npm, kubectl); **context resolution** (git repo-root walk, docker context, terraform cwd); **first-run onboarding** (wrangler, vercel, gh auth). Separately survey the AI CLIs we orchestrate (`claude`, `codex`, `cursor-agent`, `opencode`) — their conventions are what agents already expect, so matching them removes surprise for free. Deliverable: a short table of "convention → do we match → adopt/reject + why," and every later slice cites it. |
| **AE-S01 ✅ DONE** | **One declaration, many renderings — zero hand-written surface.** `ContractRegistry` is already the command tree; every rendering becomes a pure function of it. Delete the `helpText()` literal and render `alln --help` from the registry, grouped by family. Render `alln <cmd> --help` from that command's `CommandSpec` — which structurally kills the phantom-command bug (finding 12), because usage cannot be rendered for a spec that does not exist. Delete `excludedFromTopLevelHelp` entirely. Shell completion falls out for free once help is rendered. **Acceptance invariant: zero hand-written usage/help string literals in the codebase** — a grep gate, not a review habit. |
| **AE-S12 ✅ DONE** | **Fail closed on unknown flags.** `Options` (`AllnighterCLI.swift:1912`) swallows unrecognized flags and exits 0. Validate every parsed flag against the resolved command's `FlagSpec` list; unknown flag → new `UNKNOWN_FLAG` error with nearest-match suggestions, exit non-zero. **Safety rationale, not ergonomics:** today `alln run "…" --dry-run` discards the flag and dispatches a real spending run. Until AE-S04 ships, every agent that assumes a standard safety flag is silently charged. Gate: table test — a bogus flag on every command exits non-zero. |
| **AE-S13 ✅ DONE** | **Two-tier disclosure with a completeness guarantee** (the unanimous vendor pattern). `alln --help` lists **all 108 command names**, one line each, grouped by family, no flags — a few hundred tokens — and ends with an explicit completeness marker (`108 commands · alln docs <cmd> for schema · alln help search "<intent>" to find one`). Hydrate step: `alln docs <command> --schema`. Plus a single guaranteed machine front door, `alln commands --json`, emitting the full manifest (name, when-to-use trigger, args, examples, anti-examples) — `dev export-contracts` already produces this content; it just is not reachable as a first-class agent command. **The invariant that matters is not brevity, it is that incompleteness is never implied.** |
| **AE-S14 ✅ DONE** | **Rename/alias the front door and rewrite its trigger text.** All six vendors independently rejected `hello`. Add `alln route --for` / `alln resolve --for` as first-class aliases (keep `team hello` working; `Team_Depth_Naming`/`Language_Cutover` own any hard rename). Rewrite the `ContractRegistry` summary from capability-shaped ("Intent phrase to route") to trigger-shaped: *"Resolve a natural-language intent — including a model or vendor name — to a ready model plus a runnable command. USE THIS FIRST when you know what you want but not which `alln` command runs it. Examples: `--for \"ask Sonnet 5 a question\"`."* Add intent-aware recovery to `models` and `teams` (ChatGPT's predicted wrong-entry path): a failed model lookup must point at the resolver, never end at "not found." |
| **AE-S15 ✅ DONE** | **Description authoring standard, enforced.** Every `CommandSpec` summary carries, in this order: trigger phrased as a *situation*, one anti-example (`Do NOT use this when…`), and one worked invocation with real values. Ranked by the vendor study as the top-3 selection drivers; anti-examples are the cheapest unclaimed win. Gate: test asserting every M1 command's summary contains a trigger clause and an example — mechanical, since summaries live in the registry. |
| **AE-S11 ✅ DONE** | **Make surface drift mechanically impossible to ship (the founder's SSOT ask).** Three parts. **(a) Widen the hash:** `contractHash` today is a SHA over contract version + sorted command *names* (`ContractRegistry.swift:47-51`), so adding a flag or changing a summary does **not** flip it. Hash the full canonical serialization — commands, flags, value types, summaries, errors, schemas — so *any* surface change flips it. **(b) Lock file:** check in `docs/generated/alln/contract.lock.json` = `{contractVersion, contractHash}` (the `package-lock`/`terraform.lock` pattern). **(c) Forced bump:** extend `alln dev export-contracts --check` (already in `check.sh` via ASF-S08) — if the computed hash differs from the lock and `contractVersion` was **not** bumped, fail with `CONTRACT_VERSION_NOT_BUMPED`. A surface change then cannot land without a version bump and regenerated artifacts. No discipline required; the build refuses. Also fix the number semantics: `contractVersion` is the **agent-facing compatibility number** (removing/renaming a command or flag = major, adding = minor), `binaryVersion` stays the human release label, `gitSha`/`buildTime` stay build identity. |
| **AE-S02 ✅ DONE** | **Purge non-shipped teams from the catalog** (founder ruling, supersedes "hide behind `--lab`"). The production `TeamCatalog` contains **only shipped built-ins + the user's own customs** — never Team Lab artifacts. Delete the 14 `lab_*` entries and `code_core`; Team Lab writes champions to lab storage (`docs/team-lab/champions/`) and **never** into the product catalog, per `Team_Lab_Run_Factory.md`'s own law. Gate: catalog contains zero `isLabTeam` entries — enforced at the **write** path, not the read path, so no future lab run can reintroduce them. Match on `typeTags`, **not** id prefix (`code_core` displays as `Code Core · Lab` with no `lab_` prefix and would evade a prefix check). |
| **AE-S03 ✅ DONE** | **Close the PO-F10 answer-path leak.** `runAnswer` accepts and honors `workerOverride`, or rejects `--worker` with `WORKER_NOT_AVAILABLE`. Accept-and-drop is banned. Route all explicit-identifier resolution through one choke point (Law 4). Gate: table test — for every command declaring an identifier flag, a bogus value exits non-zero and dispatches nothing. |
| **AE-S04 ✅ DONE** | **`alln run --dry-run`.** Resolves project, worker, auth, mutating/shape, and write-lock; returns `canStart`, resolved worker + source counts, and `nextAction.command`; exit 0, no dispatch. Durable half: mark quota-spending commands in `ContractRegistry` and gate that **each one has a free twin** — so future spending verbs cannot ship without a preflight. |
| **AE-S05 ✅ DONE** | **cwd→project for `run`.** When `--project` is omitted, walk up from cwd to the git root and match `normalizedRootPath` (the resolver already exists). Unregistered git root → structured error whose `nextAction.command` is `alln project add <path>`. Reuses the pattern already live in `team`/`ps`/`kill`. |
| **AE-S06 ✅ DONE** | **Lane vocabulary + value-level deny-list.** Fix `build \| design \| copy` → `code \| design \| copy \| signal` at `ContractRegistry+Milestone1.swift:250, 285, 295` (vocabulary change coordinated with `Language_Cutover.md`). Durable half: extend ASF's `RetiredVocabulary` gate from **command names to enumerated flag values**, so generated docs can never again advertise a lane/effort/type that no longer exists. |
| **AE-S07 ✅ DONE** | **Error quality: suggestions + next-action correctness.** Unknown-identifier errors carry top-3 near-matches (edit distance over the real catalog). `nextAction.command` must be the discovery command for the noun that failed (unknown team → `alln teams --lane <lane> --json`), never a generic `doctor`. Gate: for each `*_NOT_FOUND` / `*_NOT_AVAILABLE` error, assert `nextAction` is the matching discovery command. |
| **AE-S08 ✅ DONE** | **Binary identity you cannot get wrong.** Add resolved binary path to `version --json` (gitSha/buildTime already shipped, ASF-S06). `doctor` compares the on-PATH binary's `gitSha` against workspace `HEAD` and emits `BINARY_STALE` with `alln install-cli` recovery. Motivation: this review found two binaries at different SHAs in one workspace, which produced a false P0 bug report. |
| **AE-S09 ✅ DONE** | **Reproducible cold-agent evaluation.** A scripted harness (`scripts/agent_eval.sh` or a `docs/operations/` playbook) that pins a freshly built binary, records its `gitSha`, runs a fixed probe script, and captures the transcript. Future dogfood feedback is then attributable to a known SHA instead of an unknown binary. Prevents another review cycle spent refuting stale-binary claims. |
| **AE-S10 ✅ DONE** | **Papercuts.** Reconcile `workerCount` (catalog, 3) with resolved seats (preflight, 4) — advertise one truth. Unknown command exits 2, not 0. `team list` accepted as an alias for `teams` (agents guess it; cheap, no contract churn). Surface `effortAffectsSeats: false` in preflight so "low = smaller team" dies mechanically (Law 7: a fact, not an estimate). |

## Execution order

Slice IDs are stable (they appear in commit history); this is the order to
**build** them, not the order they are numbered.

| Wave | Slices | Why this order |
| --- | --- | --- |
| **1 — Stop the bleeding** | **S12** (unknown flags fail closed) | Pure safety, no dependencies. Until this lands, every agent that assumes `--dry-run` exists is silently charged. Ship it alone if nothing else ships. |
| **2 — One truth, many renderings** | **S01** (generated help) → **S11** (contract lock + forced bump) → **S13** (two-tier disclosure + `commands --json`) | S01 makes help a projection; S11 makes drift unshippable; S13 gives the projection its completeness guarantee. Doing S13 before S01 would mean hand-writing a 108-line banner — the exact anti-pattern. |
| **3 — Findability** | **S14** (front-door alias + trigger text) → **S15** (description standard) → **S06** (catalog purge) | S14 is the single highest-leverage change per the vendor study; S15 generalizes its lesson to all 108 commands; S06 removes the noise competing with it. |
| **4 — Behavior matches the promise** | **S03** (PO-F10 answer-path leak) → **S04** (`run --dry-run`) → **S05** (cwd→project) | S04 depends on S12 — a dry-run flag is worthless while unknown flags are swallowed. |
| **5 — Quality** | **S07** (error routing) · **S02** (lane vocabulary + value deny-list) · **S08** (binary identity) · **S09** (cold-agent eval) · **S10** (papercuts) | S09 is the regression harness for the whole phase — it re-runs the 1-of-3 measurement. |

Wave 1 is shippable today and independently valuable. Waves 2–3 are where the
1-in-3 → 3-in-3 movement comes from.

## Rejected from the feedback (with reasons)

- **Auto-default to `--json` when stdout is not a TTY.** Rejected. It makes the
  output contract depend on invocation environment, silently breaks human
  pipelines (`alln teams | grep`), and every agent is already taught `--json` by
  bootstrap. If ever wanted, an explicit `ALLN_JSON=1` opt-in is the safe shape.
- **Fuzzy model aliases that auto-resolve.** Rejected as stated — see Anti-goals.
  Delivered instead as *suggestions* in AE-S07.
- **Cost estimates in preflight.** Rejected (no-estimates law). Delivered instead
  as observed resolved counts in AE-S04/S10.
- **Rename `teams` → `team list` for noun consistency.** Not worth contract
  churn; noun/verb split is conventional. Alias only, AE-S10.
- **Print an `alln mcp serve|install` recipe.** Rejected outright — MCP is
  retired and its absence is the correct behavior.

## Works test

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
B=Packages/AllnighterCore/.build/release/alln

# S01 — surface completeness
$B --help | grep -qE 'team hello' && $B --help | grep -qE 'team preflight' && echo OK
$B --help | grep -qE '\bteams\b|help search' && echo OK

# S02 — catalog is product only
$B teams --lane code --json | grep -q '"lab_' && echo FAIL || echo OK
$B teams --lane code --json   # shipped built-ins + user customs only; Bug Hunt Min visible

# S01 — no phantom commands (per-command help rendered from the spec)
$B config --help    # MUST NOT print `usage: alln config`; unknown command, exit 2
rg -n 'usage: alln' --glob '!*Tests*' Packages/ | grep -v CLIUsage.swift && echo FAIL || echo OK
# ^ zero hand-written usage literals outside the renderer

# S12 — unknown flags fail closed (SAFETY — run this first, it is the spend guard)
$B teams --lane code --totally-bogus-flag; test $? -ne 0 && echo OK || echo FAIL
$B version --jsonn;                        test $? -ne 0 && echo OK || echo FAIL
$B docs --errors | grep -q UNKNOWN_FLAG && echo OK

# S13 — completeness guarantee
$B --help | grep -cE '^\s+alln |^\s+[a-z]' # all 108 command names present
$B --help | tail -3                        # MUST carry an explicit completeness marker
$B commands --json | /usr/bin/python3 -c 'import json,sys; print(len(json.load(sys.stdin)["commands"]))'
# ^ 108; every entry carries trigger + args + example

# S14 — front door is findable under the words agents actually use
for q in sonnet "ask a model" "which model" resolve intent; do
  $B help search "$q" --json | grep -q 'team hello\|alln route' || echo "MISS: $q"
done
$B route --for "ask Sonnet 5 a question" --json   # alias resolves

# S15 — description standard is enforced, not aspirational
$B commands --json | /usr/bin/python3 -c '
import json,sys
bad=[c["name"] for c in json.load(sys.stdin)["commands"]
     if not c.get("trigger") or not c.get("example")]
print("FAIL:",bad) if bad else print("OK")'

# S11 — surface change cannot ship without a version bump
# (edit any FlagSpec summary, then:)
$B dev export-contracts --check   # MUST fail CONTRACT_VERSION_NOT_BUMPED

# S03 — no accept-and-drop on the answer path
$B run "probe" --project "$PWD" --team code_bug_hunt --worker model_bogus_id --json
# MUST exit non-zero with WORKER_NOT_AVAILABLE and dispatch nothing

# S04 — free validation
$B run "probe" --project "$PWD" --dry-run --json   # canStart + counts, exit 0, no run created
$B history "probe" --json                          # confirms no run was created

# S05 — cwd project
cd <registered-project-root> && $B run "probe" --dry-run --json   # resolves project without --project

# S06 — no dead lane in generated docs
$B docs | grep -q 'build | design | copy' && echo FAIL || echo OK

# S07 — error quality
$B team preflight --lane code --team code_bug_hunt_typo --json
# suggestions include code_bug_hunt; nextAction.command is `alln teams …`, not doctor

# S08 — binary identity / staleness
$B version --json | grep -q binaryPath && echo OK
$B doctor --json | grep -q BINARY_STALE   # only when on-PATH gitSha != workspace HEAD

# S10 — papercuts
$B nonexistent-command; test $? -eq 2 && echo OK   # exit 2, not 0
$B team list --json >/dev/null && echo OK          # alias for `teams`
$B team preflight --team code_bug_hunt_min --json | grep -q effortAffectsSeats && echo OK

# S09 — the regression harness for this whole phase
scripts/agent_eval.sh   # re-runs the 1-of-3 measurement on a pinned gitSha;
                        # target: 3 of 3 agents reach `run --dry-run` unaided

scripts/check.sh   # empty help allowlist, spending-command twin gate, value deny-list,
                   # contract lock, unknown-flag table test, description standard
```

## Inference bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| CLI banner ↔ ContractRegistry | `ContractRegistry` | "Not in `--help` ⇒ does not exist" | `--help` is generated; allowlist empty | Help-drift test with no exclusions |
| `--worker` ↔ run shape | explicit-worker choke point | "Answer path has no worker, so drop it" | Accept-and-drop banned; honor or fail | Bogus `--worker` on `--team` answer run exits non-zero |
| `teams` ↔ TeamCatalog | `TeamCatalog.isLabTeam` | "Everything listed is shippable" | Lab hidden unless `--lab` | Default list contains zero lab teams |
| Flag values ↔ generated docs | `RetiredVocabulary` | "Enum values need no drift gate" | Value-level deny-list | `docs` free of `build` lane |
| Effort ↔ seat count | `TeamResolver` | "`--effort low` ⇒ fewer/cheaper seats" | Publish `effortAffectsSeats: false` | Preflight seat count identical low/med/high |
| Flag parsing ↔ intent | `Options` parser | "Exit 0 ⇒ my flags were understood" | Unknown flag is an error, never a no-op | Bogus flag on every command exits non-zero |
| Banner ↔ catalog size | rendered help | "The list I see is the whole product" | Help carries an explicit completeness marker | `--help` tail asserts total count + hydrate path |
| Registry ↔ shipped binary | contract lock | "Docs regenerate themselves later" | Hash change without version bump fails the build | Edit a FlagSpec summary → `export-contracts --check` fails |

## Done when

- AE-S01–S10 checked or explicitly waived with a founder note.
- Works test green on a release binary built from committed HEAD.
- No contracted command is invisible to `--help`; the exclusion allowlist is
  empty (Law 1 + Law 5).
- No surface accepts an explicit identifier it does not honor (Law 2).
- Every quota-spending command has a free twin, enforced by a registry-derived
  gate (Law 3).
- A cold agent, given only `alln --help`, can reach `team hello` → `preflight` →
  `run --dry-run` without reading any doc in this repo.
- **The Mentor 3 replication test:** three fresh agents, told only "use alln to
  ask Sonnet 5 a question," all three find `team hello --for` and none reports a
  missing capability. Today one of three succeeds; that ratio is the metric this
  phase moves.
- The product catalog contains zero lab artifacts, enforced at the write path.
- No `--help` path prints usage for a command `ContractRegistry` cannot resolve.

## Open questions

1. Should `--help` print all ~100 commands grouped, or a family-level banner
   plus `alln help topics` for the tail? (Law 1 permits either; the banner must
   name every family and never imply completeness it lacks.)
2. Does `run --dry-run` acquire the write-lock to prove it is obtainable, or
   only report lock state? Acquiring is more truthful and more invasive.
3. Should `BINARY_STALE` (AE-S08) be a `doctor` warning only, or a loud banner
   on every command when the on-PATH SHA differs from workspace HEAD?

## Routing

| Work | Read first |
| --- | --- |
| Missing commands / help completeness | **This doc** AE-S01 → `AllnighterCLI.helpText`, `CLIHelpDriftTests` |
| Explicit-id handling / silent drops | **This doc** AE-S03 + Law 2 → `RunService.swift:1009-1015` (correct pattern), `:1715-1733` (leak) |
| Validation before spending | **This doc** AE-S04 + Law 3 |
| Lab/catalog noise | **This doc** AE-S02 → `TeamCatalog.isLabTeam`; naming owned by `Team_Depth_Naming.md` |
| Lane vocabulary | `Language_Cutover.md` (vocabulary) + **this doc** AE-S06 (the gate) |
| Teaching-surface drift | archived `CLI_Agent_Surface_Fidelity.md` |
