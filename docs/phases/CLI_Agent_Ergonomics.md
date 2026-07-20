# CLI Agent Ergonomics — stop making agents guess what exists

Status: **Draft — Ready for founder approval (2026-07-20).** Successor to
archived `CLI_Agent_Surface_Fidelity.md` (ASF). ASF made the CLI **honest in
what it says**. This phase makes it **complete in what it reveals** and
**leak-free in what it enforces**.
Owner: AllnighterCLI (`AllnighterCLI.helpText`, `RunCLI`) + AllnighterCore
(`ContractRegistry`, `TeamCatalog.isLabTeam`, error catalog) + AllnighterEngine
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
| 11 | **Two binaries at different SHAs in one workspace** (`.build/debug` at `791d591e`, installed at `ce65caf3`) — almost certainly the source of the false "silent spend" report. | live `--version` comparison |
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
| **AE-S00** (P0, cheap, do first) | **Steal the wheel — prior-art survey before we design anything.** One pass over CLIs that solved this decades ago, producing a decisions table we adopt rather than re-derive: **generation** (Swift ArgumentParser / clap / cobra / oclif — help, usage, completion and validation all rendered from one command declaration); **preflight/apply separation** (`terraform plan`, `kubectl --dry-run=server`, `rsync -n`, `apt --simulate`); **machine output** (`kubectl -o json`, `gh --json`, `git --porcelain`); **did-you-mean** (git, cargo, npm, kubectl); **context resolution** (git repo-root walk, docker context, terraform cwd); **first-run onboarding** (wrangler, vercel, gh auth). Separately survey the AI CLIs we orchestrate (`claude`, `codex`, `cursor-agent`, `opencode`) — their conventions are what agents already expect, so matching them removes surprise for free. Deliverable: a short table of "convention → do we match → adopt/reject + why," and every later slice cites it. |
| **AE-S01** (P0, cheap) | **`--help` generated from `ContractRegistry`.** Replace the hardcoded `helpText()` literal with a grouped rendering of every M1 command. Delete `excludedFromTopLevelHelp`; if a command is genuinely too niche for the banner, the group line must still name the family and the command that lists it. Gate: `testPrintHelpCoversContractRegistryCommands` runs with an **empty** allowlist. |
| **AE-S02** (P0) | **Purge non-shipped teams from the catalog** (founder ruling, supersedes "hide behind `--lab`"). The production `TeamCatalog` contains **only shipped built-ins + the user's own customs** — never Team Lab artifacts. Delete the 14 `lab_*` entries and `code_core`; Team Lab writes champions to lab storage (`docs/team-lab/champions/`) and **never** into the product catalog, per `Team_Lab_Run_Factory.md`'s own law. Gate: catalog contains zero `isLabTeam` entries — enforced at the **write** path, not the read path, so no future lab run can reintroduce them. Match on `typeTags`, **not** id prefix (`code_core` displays as `Code Core · Lab` with no `lab_` prefix and would evade a prefix check). |
| **AE-S03** (P0) | **Close the PO-F10 answer-path leak.** `runAnswer` accepts and honors `workerOverride`, or rejects `--worker` with `WORKER_NOT_AVAILABLE`. Accept-and-drop is banned. Route all explicit-identifier resolution through one choke point (Law 4). Gate: table test — for every command declaring an identifier flag, a bogus value exits non-zero and dispatches nothing. |
| **AE-S04** (P1) | **`alln run --dry-run`.** Resolves project, worker, auth, mutating/shape, and write-lock; returns `canStart`, resolved worker + source counts, and `nextAction.command`; exit 0, no dispatch. Durable half: mark quota-spending commands in `ContractRegistry` and gate that **each one has a free twin** — so future spending verbs cannot ship without a preflight. |
| **AE-S05** (P1, cheap) | **cwd→project for `run`.** When `--project` is omitted, walk up from cwd to the git root and match `normalizedRootPath` (the resolver already exists). Unregistered git root → structured error whose `nextAction.command` is `alln project add <path>`. Reuses the pattern already live in `team`/`ps`/`kill`. |
| **AE-S06** (P1, cheap) | **Lane vocabulary + value-level deny-list.** Fix `build \| design \| copy` → `code \| design \| copy \| signal` at `ContractRegistry+Milestone1.swift:250, 285, 295` (vocabulary change coordinated with `Language_Cutover.md`). Durable half: extend ASF's `RetiredVocabulary` gate from **command names to enumerated flag values**, so generated docs can never again advertise a lane/effort/type that no longer exists. |
| **AE-S07** (P2) | **Error quality: suggestions + next-action correctness.** Unknown-identifier errors carry top-3 near-matches (edit distance over the real catalog). `nextAction.command` must be the discovery command for the noun that failed (unknown team → `alln teams --lane <lane> --json`), never a generic `doctor`. Gate: for each `*_NOT_FOUND` / `*_NOT_AVAILABLE` error, assert `nextAction` is the matching discovery command. |
| **AE-S08** (P2) | **Binary identity you cannot get wrong.** Add resolved binary path to `version --json` (gitSha/buildTime already shipped, ASF-S06). `doctor` compares the on-PATH binary's `gitSha` against workspace `HEAD` and emits `BINARY_STALE` with `alln install-cli` recovery. Motivation: this review found two binaries at different SHAs in one workspace, which produced a false P0 bug report. |
| **AE-S09** (P2) | **Reproducible cold-agent evaluation.** A scripted harness (`scripts/agent_eval.sh` or a `docs/operations/` playbook) that pins a freshly built binary, records its `gitSha`, runs a fixed probe script, and captures the transcript. Future dogfood feedback is then attributable to a known SHA instead of an unknown binary. Prevents another review cycle spent refuting stale-binary claims. |
| **AE-S10** (P3) | **Papercuts.** Reconcile `workerCount` (catalog, 3) with resolved seats (preflight, 4) — advertise one truth. Unknown command exits 2, not 0. `team list` accepted as an alias for `teams` (agents guess it; cheap, no contract churn). Surface `effortAffectsSeats: false` in preflight so "low = smaller team" dies mechanically (Law 7: a fact, not an estimate). |

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

# S12 — no phantom commands
$B config --help    # MUST NOT print `usage: alln config`; unknown command, exit 2

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

scripts/check.sh   # empty help allowlist, spending-command twin gate, value deny-list
```

## Inference bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| CLI banner ↔ ContractRegistry | `ContractRegistry` | "Not in `--help` ⇒ does not exist" | `--help` is generated; allowlist empty | Help-drift test with no exclusions |
| `--worker` ↔ run shape | explicit-worker choke point | "Answer path has no worker, so drop it" | Accept-and-drop banned; honor or fail | Bogus `--worker` on `--team` answer run exits non-zero |
| `teams` ↔ TeamCatalog | `TeamCatalog.isLabTeam` | "Everything listed is shippable" | Lab hidden unless `--lab` | Default list contains zero lab teams |
| Flag values ↔ generated docs | `RetiredVocabulary` | "Enum values need no drift gate" | Value-level deny-list | `docs` free of `build` lane |
| Effort ↔ seat count | `TeamResolver` | "`--effort low` ⇒ fewer/cheaper seats" | Publish `effortAffectsSeats: false` | Preflight seat count identical low/med/high |

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
