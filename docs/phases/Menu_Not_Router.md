# Menu, Not Router — the caller is the brain; `alln` is the tool menu

Status: **READY FOR IMPLEMENTATION — final hardened contract (2026-07-20).**
Founder-ordered clean replacement for the retired intent-router architecture.
No users; this cut carries no migration, compatibility aliases/readers, or dead
selection paths.
Owner: AllnighterCore (`ContractRegistry`, `MenuCatalog`, `TeamCatalog`,
`ModelCatalog`, `RecipeCatalog`, error catalog) + AllnighterCLI (`menu`, `run`,
`bootstrap`, help/search projections)
Updated: 2026-07-20 (v3, final hardening pass)

Supersedes the selection architecture in archived `Agent_Intent_Router.md` and
the `team hello` / `route` / `resolve` conclusions in
`CLI_Agent_Ergonomics.md`. It is subordinate to `Language_Cutover.md` and
`Unified_Run_Model.md`: **Team** is the noun, **Send to team** is the human
action, and direct model/team work uses the one `alln run` primitive.

## Verdict

**Yes: “menu, not router” is the right architecture. The v2 draft was not yet a
great agent interface.** It deleted the wrong brain but left the right brain to
assemble a fragmented, oversized menu from several commands. That is still slow,
easy to forget, and unlike selecting a native tool in Codex.

Measured against the 2026-07-20 release dogfood binary:

| Read | Rows | Bytes |
| --- | ---: | ---: |
| `alln commands --json` | 109 commands | 140,580 |
| `alln models --json` | 22 models | 16,283 |
| `alln teams --json` | 25 teams | 7,667 |
| **Total before recipes or detail** | **156 rows** | **164,530** |

That is a contract dump, not a usable menu. The final design is one compact live
read, one optional detail read, one quota-free validation, then one run:

```bash
alln menu --json
alln run "Review the release plan" --worker model_sonnet --dry-run --json
alln run "Review the release plan" --worker model_sonnet --json

alln run "Find three launch options" --team code_growth --dry-run --json
alln run "Find three launch options" --team code_growth --json
```

If the caller already has a current canonical id, it skips discovery. For the
common ask-one-model or Send-to-team path, `menu` must contain enough information
to reach `run --dry-run` without another help call.

## Founder intent translated into a product claim

> A cold frontier agent can discover every public `alln` capability and every
> selectable model, team, and recipe in one bounded machine read; choose using
> its own conversation context; validate without spending quota; and invoke one
> exact run command. `alln` never guesses the intent, silently substitutes a
> target, or exposes two commands for the same direct run.

This phase owns the selection and invocation path. It does not claim that run
lifecycle, answer envelopes, or every composition workflow is already great.

## Why the caller owns selection

The calling agent already has the user's words, the conversation, repo context,
and a frontier model. Allnighter has the authoritative live facts: commands,
models, drivers, readiness, teams, mutability, and exact invocation grammar.
The clean boundary is therefore:

```text
caller: understands intent and chooses
alln:   discloses facts, validates exact ids, previews effects, executes
```

A keyword or embedded-model router reverses that boundary. It discards context,
creates a second intent model, adds latency or quota, and can turn a weak guess
into a real spend. Delete it rather than improving it.

Lexical retrieval is allowed. `help search` may return zero or many matching
menu records, including their normal templates. It may not emit a selected
winner, confidence score, “recommended” target, or sole next action.

## The end-state interface

### 1. One live menu

`alln menu --json` is the stable agent front door. It is a Core projection, not
hand-authored help. One atomic response contains:

- `actions`: a short fast-path set for common jobs, generated from tagged command
  specs; each has an exact grammar template and free validation template;
- `commands`: the exhaustive accepted public grammar as compact rows;
- `teams`: every effective built-in and custom team, including inactive teams
  with an explicit blocked reason;
- `models`: every configured model, including disabled/off-Bench/unready models
  with explicit state;
- `recipes`: every shipped recipe card;
- `effectProfiles`: deduplicated command-level effect records referenced by
  compact command rows;
- `defaults`: the one effective Default Team ref and resolved default worker id;
- completeness counts and booleans for every collection;
- `contractVersion`, `contractHash`, and a `catalogRevision` covering the dynamic
  team/model/recipe snapshot.

The complete compact index is Tier 1. Tier 2 is one uniform hydrate command:

```bash
alln menu show command:run --json
alln menu show team:code_growth --json
alln menu show model:model_sonnet --json
alln menu show recipe:ask-several-models-and-compare --json
```

Typed refs make noun ambiguity impossible. An unknown ref fails with structured
same-kind suggestions. Refs never contain whitespace (`command:teams.duplicate`,
not `command:teams duplicate`). `menu show` is read-only and quota-free.

`alln --help` remains complete human grammar. `docs` remains the full schema and
reference renderer. `teams --json` and `models --json` may remain useful domain
views, but they must project the same `MenuCatalog` records; they are not separate
selection truth. The oversized `commands --json` surface is replaced by `menu`
and deleted, with no alias.

`menu` reads local registry/catalog/readiness state only. It never launches a
smoke probe or worker and never spends provider quota.

### 2. Compact does not mean incomplete

Tier-1 rows omit full flag schemas and prompt bodies, never identities or state.
The shapes are deliberately small:

| Kind | Required Tier-1 fields |
| --- | --- |
| action | `id`, `useWhen`, `dontUseWhen`, `effects`, `example`, `validateExample` |
| command | `ref`, `name`, `effectsRef` |
| team | `ref`, `id`, `displayName`, `useWhen`, `dontUseWhen`, `shape`, `mutating`, `workerCount`, `isDefault`, `active`, `blockedReason`, `runTemplate`, `validateTemplate` |
| model | `ref`, `id`, `displayName`, `driverId`, `enabled`, `ready`, `blockedReason`, `capabilities`, `runTemplate`, `validateTemplate` |
| recipe | `ref`, `id`, `title`, `useWhen`, `dontUseWhen` |

One top-level `detailTemplate` (`alln menu show <ref> --json`) hydrates every
kind; repeating it in every row is forbidden. `effectProfiles` removes another
large repeated object without asking the caller to infer semantics. Template
variables use one declared syntax (for example `{message}`); target-specific
templates bind the canonical team/model id and never contain an `<id>` guess.

Every public command accepted by the parser appears in `commands`. Every parser
path has a registry-owned `public | developer | internal` visibility; unregistered
parser branches are forbidden. Developer/internal commands do not pollute the
public menu. Every effective catalog object appears even when it cannot currently
run. Deferred, lab-only, retired, and parser-inaccessible records appear nowhere.
The response states `truncated: false`; pagination and hidden tails are forbidden
on the default menu.

The built-in fixture must encode to **≤32 KiB**. Custom records stay linear and
use the same bounded row fields; prompt templates, full flag descriptions,
transcripts, diagnostics, and prose counsel belong in Tier 2. A byte-size
regression test guards the built-in fixture. Creation/edit validation bounds
custom selection metadata per row so one record cannot explode the result. If
the schema cannot meet the budget, simplify the schema—do not truncate truth.

### 3. Effects are facts, not adjectives

Every action and command record carries registry-owned effects, directly or via
`effectsRef`. Command-level values are enums because flags or target selection
can change the result:

```json
{
  "workerStart": "dependsOnFlags",
  "quotaSpend": "dependsOnFlags",
  "repoWrite": "dependsOnSelection",
  "destructive": "never",
  "humanInteraction": "never"
}
```

Allowed values are `never | always | dependsOnFlags | dependsOnSelection`.
After target and flags resolve, `run --dry-run` returns effective booleans, not
conditional prose.

These fields derive from command semantics and the effective team/worker
selection. Text such as “safe,” “cheap,” or “read-only” cannot own behavior.
No estimates of money, tokens, duration, or future quota are emitted.

For teams, `shape` and `mutating` come from the effective `TeamPreset`. Answer
teams may say `repoWrite: false` only when Unified Run Model's mechanical
read-only guarantee exists for every selected worker. Otherwise the team is
blocked, not optimistically described.

### 4. IDs execute; display names explain

Canonical ids are the only executable selector values:

```text
--worker model_sonnet
--team code_growth
```

Display names are selection text for the caller, not aliases accepted by a
spending command. This matches native tool calling: the model reads a friendly
description, then invokes an exact stable name. It also deletes ambiguity rules,
normalization policy, and mutable-name coupling from the spend path.

An unknown id fails before dispatch and returns:

- stable error code, command, flag, and provided value;
- zero or more same-kind candidates with canonical id, display name, driver, and
  state;
- a ready-to-paste **discovery or validation** command;
- no auto-selected candidate and no spending command based on edit distance.

Suggestions repair spelling; they never authorize substitution. All explicit
team/model ids pass through one resolver choke point and are either honored or
rejected. Accept-and-drop is impossible.

### 5. One direct-run grammar

Direct work with the Default Team, a named worker, or a Team uses `alln run`.
`alln team "…"` and `alln team start "…"` are duplicate spending grammars and
are deleted, not aliased. Team management remains under `teams …`; run lifecycle
commands may remain under their owning lifecycle nouns until that contract is
separately simplified.

Foreground vs detached execution is a flag, not a second verb:

```bash
alln run "Review this" --team code_spec_review --json
alln run "Review this overnight" --team code_spec_review --detach --json
```

`--detach` returns the durably accepted run id and preserves the async capability
currently hidden behind `team start`.

Every worker-starting path has a quota-free twin. For direct runs it is the same
grammar plus `--dry-run`. Dry-run resolves the project, canonical ids, effective
team shape, readiness, auth knowledge, write policy, and lock state; it creates
no `RunRecord`, starts no worker, and spends no provider quota. Its JSON returns
the exact resolved ids and effects the real run will use. It is not a reservation:
the real run repeats live readiness, catalog, write-policy, and lock validation
and fails closed if state changed.

Distinct workflow commands may eventually create runs, but they must represent a
real product operation—not an alias for direct `run`—and must declare effects and
a free twin in `ContractRegistry`.

### 6. Bootstrap teaches a reflex, not a catalog

`alln bootstrap` contains only stable rules:

1. Before first Allnighter use in a session, read `alln menu --json`.
2. Choose from `useWhen` / `dontUseWhen`; pass canonical ids only.
3. Before an unfamiliar worker-starting action, run its validation template.
4. Re-read the live menu in a new session; never trust a pasted catalog.

It does not embed models, teams, recipes, or command rows. Static host context is
for the protocol; the live binary owns the catalog.

## Laws

1. **The caller chooses.** No Allnighter policy maps unstructured intent to one
   selected command, team, model, or recipe.
2. **One menu owns discovery.** `MenuCatalog` is the source for `menu`, domain
   listings, help search, and generated selection docs. Bootstrap teaches the
   stable `menu` command from `ContractRegistry`; it never copies menu rows.
3. **Complete means executable truth.** The menu lists every public
   parser-accepted command and every effective catalog object, including blocked
   objects with reasons; it lists no deferred or unreachable fiction.
4. **Common work is one read away.** Ask-one-worker and Send-to-team reach
   `run --dry-run` from the default menu without hydration or search.
5. **Only canonical ids cross the dispatch boundary.** Names and fuzzy matches
   can aid selection but never execute.
6. **Effects are structured and registry-owned.** Every worker-starting action
   declares quota and mutation behavior plus a free twin.
7. **Nothing fuzzy, stale, dropped, or ambiguous spends.** Validation fails
   closed before a run record or provider process exists.
8. **One semantic act has one grammar.** No aliases or alternate direct-run
   entrypoints survive the clean cut.

## Anti-goals

- No deterministic, regex, keyword, embedding, or model-assisted intent router.
- No hidden model call or API key inside `alln` for selection.
- No `team hello`, `route`, `resolve`, `--for`, or compatibility wrappers.
- No `team list`, `team show`, or `team preflight` selection aliases; `menu`,
  `teams show <id>`, and `run --dry-run` own those jobs.
- No display-name aliases on `--worker` or `--team`.
- No static catalog copied into bootstrap or host instructions.
- No hand-authored menu beside `ContractRegistry` and the live catalogs.
- No default recommendation, confidence score, or “best” row from search.
- No second confirmation after the caller invokes a normal run; dry-run is an
  inspection tool, not an approval ceremony. Separate high-risk operations keep
  their owning safety policy.
- No broad cleanup of unrelated lifecycle, Pending, Pilot, or GUI contracts.

## Implementation slices

Slices are deletion-forward and must leave the binary runnable. Surface changes
advance `contractVersion` under AE-S11; the completed phase is one clean major
contract cut, not a compatibility release.

| Slice | Deliverable |
| --- | --- |
| **MR-S01 — Build the real menu** | Add Core-owned `MenuCatalog`, typed refs, effects, compact/detail schemas, `alln menu --json`, and `alln menu show <ref> --json`. Give every parser path a registry-owned visibility and reject unregistered branches. Project public command specs, effective teams, configured models, and recipes atomically. Add completeness, reachability, deterministic ordering, snapshot revision, duplicate-ref, per-row bound, and ≤32 KiB built-in-fixture gates. `actions` are generated from tagged command specs, never a second registry. |
| **MR-S02 — Clean-cut the wrong and duplicate grammars** | Delete `AgentIntentRouter.swift`, `AgentHello.swift`, all router tests/errors/help/recipes, `team hello`, `route`, `resolve`, `--for`, and the `team list` alias. Replace/delete `commands --json`. Delete selection duplicates `team show` and `team preflight`; `menu`, `teams show <id>`, and `run --dry-run` own those facts. Delete direct-run aliases `alln team [prompt]` and `alln team start [prompt]`; preserve async work as `alln run --detach` and route the product contract to `alln run`. Add every retired path/token to `RetiredVocabulary`; regenerate all derived contracts; perform the required major version cut. Preserve readiness facts through `menu`, `doctor`, and `run --dry-run`, not an oracle-shaped replacement. |
| **MR-S03 — Make every row selection-grade** | Author bounded `useWhen` and `dontUseWhen` for every team/model/recipe and every fast-path action. Spending actions name adjacent management intents and their exact commands. Add structured effects and direct validation/run templates. Gate declared template variables, target-bound canonical ids, valid command refs, and cross-verb anti-examples. Derived generic prose does not satisfy the gate for fast-path actions or selectable targets. |
| **MR-S04 — Exact-id dispatch and one-shot repair** | Route every explicit worker/team selector through one exact-id resolver. Remove display-name matching and all silent/default substitution. Unknown ids return same-kind candidates and exact discovery/validation commands; ambiguity is structurally impossible because ids are unique. Table-test every identifier flag for honor-or-fail and every dispatch path for no process/run creation on failure. |
| **MR-S05 — Teach and retrieve from the same truth** | Rewrite bootstrap to the four-rule live-menu reflex. Project `teams`, `models`, generated docs, and `help search` from `MenuCatalog`. Search returns zero/many menu cards and no selection/recommendation fields. Delete every static or router-era teaching copy from Core, CLI, active docs, generated artifacts, recipes, and host snippets. Tombstone the archived router doc and update active routing docs in the same slice. |
| **MR-S06 — Cold-agent proof** | Replace the router-era harness with pinned-binary, out-of-distribution tests. Record binary SHA, menu bytes/counts, every command attempted, dry-run JSON, whether a run/provider process was created, and final exact command. Fail on stale binary, invented grammar, discovery loops, wrong spend, display-name execution, catalog incompleteness, or a common path requiring hydration. |

## Cold-agent acceptance matrix

Each row starts with only the bootstrap snippet and the user ask. The evaluator
must not mention `menu`, `run`, ids, or flags in the prompt.

| Ask shape | Required outcome before any spend |
| --- | --- |
| “Ask Sonnet 5 to review this” | one menu read → exact `model_*` id → `run --worker … --dry-run` |
| “Ask several models for launch options” | one menu read → appropriate answer-team id → `run --team … --dry-run` |
| “Use the growth team” | one menu read → exact team id → dry-run; no name passed as id |
| “Duplicate the growth team so I can edit seats” | `teams duplicate`; zero worker starts |
| “Edit the growth team” | `teams edit`; zero worker starts |
| “Fix this with the execution team” | exact mutating team id; dry-run reports `repoWrite: true` and lock state |
| bare “Sonnet 5” | ask/clarify or prepare a named-worker dry-run; never execute the display name |
| unknown model/team name | explicit cannot-fulfill or candidate presentation; zero worker starts |
| rare administrative intent | menu → at most one `menu show` → exact command |

Pass bar:

- common named-worker, Send-to-team, and team-management rows: **one discovery
  call maximum** before the free validation or exact non-spending command;
- rare rows: **two discovery calls maximum** (`menu`, then `menu show`);
- 100% correct command family and canonical id across the permanent matrix;
- zero wrong worker starts, quota spends, repo writes, invented flags, aliases,
  or repeated discovery loops.

“No wrong spend” alone is not a pass. The caller must reach the right executable
command or an honest cannot-fulfill result within the budget.

## Works test

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
B=Packages/AllnighterCore/.build/release/alln

# One bounded, complete menu
$B menu --json > /tmp/alln-menu.json
/usr/bin/python3 scripts/verify_menu_contract.py /tmp/alln-menu.json \
  --max-built-in-bytes 32768 --require-complete --require-unique-refs
$B menu show command:run --json >/dev/null
$B menu show team:code_growth --json >/dev/null
$B menu show model:model_sonnet --json >/dev/null

# The wrong brain and duplicate direct-run grammar are gone
$B team hello --for anything >/dev/null 2>&1; test $? -ne 0
$B route --for anything >/dev/null 2>&1; test $? -ne 0
$B resolve --for anything >/dev/null 2>&1; test $? -ne 0
$B commands --json >/dev/null 2>&1; test $? -ne 0
$B team list --json >/dev/null 2>&1; test $? -ne 0
$B team show --json >/dev/null 2>&1; test $? -ne 0
$B team preflight --team code_growth --json >/dev/null 2>&1; test $? -ne 0
test ! -e Packages/AllnighterCore/Sources/AllnighterCore/AgentIntentRouter.swift
test ! -e Packages/AllnighterCore/Sources/AllnighterCore/AgentHello.swift

# Canonical ids only; suggestions never dispatch
$B run "probe" --worker model_sonnet --dry-run --json
$B run "probe" --worker 'Sonnet 5' --dry-run --json; test $? -ne 0
$B run "probe" --worker model_sonet --json; test $? -ne 0
$B history "probe" --json  # no run created by the two rejected selectors

# One direct-run grammar and a free twin
$B run "probe" --team code_growth --dry-run --json
$B run "probe" --team code_growth --detach --dry-run --json
$B team "probe" --json; test $? -ne 0
$B team start "probe" --json; test $? -ne 0

# Static teaching points to live truth and contains no retired catalog/router
$B bootstrap | grep -q 'alln menu --json'
$B bootstrap | grep -qE 'team hello|route --for|resolve --for' && echo FAIL || echo OK

# Generated contract, deterministic gates, and cold-agent proof
$B dev export-contracts --check
scripts/agent_eval.sh --suite menu-not-router --binary "$B"
scripts/check.sh
```

## Inference bans

| Junction | Truth owner | Bad inference | Mechanical ban |
| --- | --- | --- | --- |
| user prose → selection | caller | “Allnighter should guess the winner” | no unstructured-intent selector in Core/CLI |
| menu → parser | `ContractRegistry` | “menu rows can drift from commands” | every command row resolves; counts match; generated projection only |
| menu → catalogs | `MenuCatalog` | “inactive means nonexistent” | list all effective records with explicit state/blocker |
| display name → dispatch | exact-id resolver | “unique-looking name is safe enough” | selector flags accept canonical ids only |
| suggestion → authorization | error catalog | “nearest candidate may run” | suggestions contain no auto-selected spending action |
| team label → write safety | `TeamPreset` + run resolver | “answer implies read-only” | effects derive mechanically; unsafe answer teams block |
| search rank → decision | `MenuCatalog` search projection | “top lexical hit is recommended” | no selected/confidence/recommended fields |
| bootstrap → catalog | live `menu` | “pasted ids stay current” | static snippet contains protocol only |
| direct work → grammar | `run` command spec | “aliases are harmless” | retired-vocabulary + parser tests reject duplicate entrypoints |

## Out of scope and next bottlenecks

- **Run lifecycle trust:** durable admission, activity, blocker, kill, retry, and
  progress truth remain owned by archived `Run_Lifecycle_Reliability.md` (code is
  the current SSOT).
- **Skinny answer output:** a short question still needs a compact answer view and
  honest read/write posture. Give that its own phase after selection is correct.
- **Multi-step composition:** recipes are discoverable here; richer Growth → phase
  doc → Pilot chains remain separate workflow work.
- **Broad CLI taxonomy cleanup:** this phase deletes selection/router residue and
  duplicate direct-run grammar. It does not rename unrelated Pending, Pilot,
  lifecycle, or administration commands.

## Done when

- MR-S01–S06 are complete on committed HEAD and the release-binary Works Test is
  green.
- `alln menu --json` is complete, untruncated, deterministic, bounded, and the
  only selection truth; all projections share `MenuCatalog`.
- Common model/team work reaches exact `run --dry-run` after one menu read; rare
  work needs at most one hydrate read.
- Direct work has one grammar: `alln run`. Router commands, duplicate direct-run
  entrypoints, display-name dispatch, and `commands --json` do not parse.
- Every worker-starting action declares effects and has a proven quota-free twin.
- The permanent cold-agent matrix reaches the correct command or honest stop with
  zero wrong spends, writes, invented grammar, or loops.
- Active routing/teaching docs point here; archived router material is visibly
  tombstoned; generated contracts contain no retired grammar.

## Routing

| Work | Read first |
| --- | --- |
| Selection, discovery, menus, router removal | **This doc** |
| Canonical product vocabulary | `Language_Cutover.md` |
| One run primitive, answer/execution safety, write lock | `Unified_Run_Model.md` |
| Registry, JSON/errors/generated artifacts | `CLI_Implementation_Contract.md` |
| Run stuck/status/activity/kill/retry | archived `Run_Lifecycle_Reliability.md` |
| Bootstrap and help teaching updates | this doc MR-S05 + `SSOT_Feature_Workflow.md` |
| Implementation/commit/closeout | `docs/operations/Execution-Playbook.md` |
