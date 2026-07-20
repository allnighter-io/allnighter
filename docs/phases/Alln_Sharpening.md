# Alln Sharpening — from a tool agents can use to a tool agents prefer

Status: **Draft (2026-07-20) — claims verified against live binary, slices not
started.**
Owner: AllnighterCore (`TeamRunJSON`/`TeamRunJSONMapper`, dry-run resolver,
`MenuCatalog`, docs renderer, error catalog) + AllnighterCLI (run/docs/menu
projections)
Updated: 2026-07-20

Successor to archived `Menu_Not_Router.md` (MNR) and
`CLI_Agent_Ergonomics.md` (AE). ASF made the CLI honest in what it says. AE
made it complete in what it reveals. MNR made selection the caller's job with
one bounded menu and one run grammar. **This phase makes using it cheap and
makes every preview true** — the two things still standing between "works"
and "preferred."

Related: archived `Menu_Not_Router.md` (selection laws — do not re-decide) ·
`Unified_Run_Model.md` (write-policy semantics — effects truth defers here) ·
`Team_Depth_Naming.md` (team naming) · `allnighter-latency-warm-workers`
memory / `Warm_Single_Lane_Chat.md` (latency ownership) ·
`docs/workflows/SSOT_Feature_Workflow.md`

## What happened

Four cold agents (post-MNR binary, git `e17fd892`) were given the same task:
use `alln` to get Sonnet 5 to say "success," explain how to build a Bug Hunt
team, and rate the tool. **All four succeeded.** No false-absence reports, no
wrong spends, no invented grammar, no discovery loops. Scores: 7, 7, 8, 8 out
of 10.

That is the MNR bet paying off, and it moves the problem. AE-era feedback was
dominated by *false absence* — agents confidently reporting missing features
we ship (7 of 11 claims false). This round, every agent found the front door,
used `--dry-run` before spending, and extracted the answer. The complaints
that remain are a different class: **the tool is more expensive to use than
it needs to be, and one preview lies.**

Two caveats that shape this whole phase:

1. **One prompt is one sample.** All four reports came from a single prompt
   exercising two paths (one-shot `--worker` ask, team browse/duplicate). That
   over-samples the one-shot path and tells us nothing about lifecycle,
   detach, pending, or recovery. Nothing here may be tuned to that prompt;
   the harness diversifies before we chase the score (SH-S07).
2. **Agent feedback still contains false claims.** Smaller ratio than AE's
   7/11, but present (see Refuted below). The AE law stands: **no claim
   becomes a slice until probed against code or a live binary.** Every claim
   below has been.

## First principles — what makes an agent *prefer* a tool

An agent choosing between `alln` and the vendor CLI one layer down (always
installed, zero discovery — Opus's framing in AE-S00) minimizes total cost
per unit of trusted value:

```text
cost  = calls made + tokens parsed + seconds waited + ceremony (setup, re-verification)
value = a correct answer it can extract and trust without re-checking
```

MNR won the *trust* and *discovery* terms: bounded menu, canonical ids,
fail-closed dispatch, free twins, mechanical outcomes. The verified defects
this round all land on the two remaining terms:

- **Economy** — a 3-token answer arrives inside a multi-KB envelope embedding
  the model catalog, with the answer buried at `workerAnswers[0].markdown` /
  `plan.markdown` depending on shape. Every agent flagged extraction cost.
- **Fidelity** — the pinned-worker dry-run reports the *default team's*
  resolution, not the invocation's. Preview that doesn't match the run
  reintroduces exactly the re-verification tax MNR paid to remove.

Those two terms are the phase. Everything else is either refuted, a founder
decision, or measure-first.

## Verified claims ledger (probed 2026-07-20, binary `e17fd892`)

**Confirmed — this phase owns them:**

| # | Finding | Evidence |
| --- | --- | --- |
| 1 | **Dry-run with pinned `--worker` reports the default team, not the invocation.** `run "probe" --worker model_sonnet --dry-run` returns `teamPresetId: default_chat`, `teamDisplayName: Auto`, `seatCount: 2`, and a warning about `model_cursor_composer_25`→Grok that has nothing to do with the pinned worker. Two of four agents parsed this as "dry-run lied." | live probe |
| 2 | **Dry-run `nextAction.command` drops the `--worker` flag.** The same probe's "Run for real" command is `alln run "<message>" --project prj_8ded5a42 --json` — no worker pin. An agent following the machine-suggested next action verbatim dispatches to Auto, not the model it validated. This is accept-and-drop (MNR Law 7 / AE Law 2) living on the *teaching* surface. **Worst verified finding of the round; none of the four agents caught it.** | live probe |
| 3 | **No top-level answer field.** `TeamRunJSON` exposes answers only via `workerAnswers[].markdown` / `plan.markdown`; which one holds "the answer" depends on run shape. All four agents flagged extraction cost. | `TeamRunJSON.swift:13`, `TeamRunJSONMapper.swift:54,157` |
| 4 | **Every run envelope embeds model infos.** `TeamRunJSONMapper.swift:157` maps `models: modelInfos` into every result — catalog data a one-shot caller already has from `menu`. | code read |
| 5 | **Ref grammar splits between surfaces.** `menu` emits dotted refs (`command:teams.duplicate`); `menu show` resolves them; **`docs` does not** — `alln docs teams.duplicate` → `no docs for topic`, no suggestion, while `alln docs "teams duplicate"` returns the full flag schema. An agent holding a menu ref hits a dead end one surface over. | live probe |
| 6 | **`--effort`/`--lane` values absent from usage line.** `run --help` shows `[--effort <effort>]` with no values. (They *are* enumerated in `docs run`: `low \| med \| high` — so this is a usage-renderer gap, not a docs gap.) | live probe |
| 7 | **`menu.actions` covers 4 of 103 commands.** The fast-path set is `run`, `models`, `teams duplicate`, `teams edit`. Legitimate under MNR law (actions = tagged specs, 1:1), but the tagging is thin relative to observed agent intents. | live probe |
| 8 | **No one-shot team create.** `teams create`/`teams new` don't exist; the only authoring path is duplicate → definition → edit, its id is derived and unpredictable pre-parse, and the round-trip is documented nowhere agents looked. Three of four agents flagged it. | live probe |
| 9 | **`mutating: true` on a pure answer ask.** The dry-run above reports `mutating: true` for a read-only chat question. MNR §3 promised *effective booleans after resolution*; this is a conditional reported as a fact. One agent explicitly hesitated to call `run` inside its own loop because of it. | live probe |

**Refuted — do NOT "fix" these:**

| Claim | Reality |
| --- | --- |
| "`help search` has no `--json`" | It does; returns structured `results` + `catalogRevision`. |
| "Enum flags are undiscoverable" | `docs run` enumerates `low \| med \| high`. Gap is only the usage line (finding 6). |
| "No per-command schema under `docs`" | `docs "teams duplicate"` returns args, flags, and semantics. The defect is the ref grammar (finding 5), not missing content. |
| "Project registration is broken friction" | AE-S05 shipped cwd→project resolve; unregistered root fails closed with `nextAction: alln project add <path>` — which is exactly what the agent then ran, successfully. Working as designed. Whether to soften it is a founder question (Open Q2), not a bug. |
| "~10s latency is a defect" | Unverified as a *defect*: warm lanes shipped (`Warm_Single_Lane_Chat.md`), `ttftMs`/`queueMs` are recorded, and most of a one-shot's wall clock is the vendor CLI itself. Surface the split (SH-S06); do not "optimize" unmeasured. |
| "Needs a global `--no-interactive`" | No interactive prompt exists on any agent path probed. Absence of a flag that guards nothing is correct. |

## Laws

Numbered to extend, not replace, ASF/AE/MNR laws — those all still bind.

1. **Cost of extraction is proportional to the ask.** A one-worker answer run
   returns an envelope an agent can consume without parsing catalog data.
   Catalog facts live in `menu`; run results carry run facts.
2. **The answer is a first-class field.** Every terminal run envelope exposes
   one stable path to "the answer for this run shape." An agent never
   branches on shape to find it.
3. **Preview truth is run truth.** `--dry-run` reports the resolution of
   *this invocation* — resolved team, worker, seats, effects — identical to
   what the real run would use. A warning about state the invocation doesn't
   touch is noise; noise on a trust surface is a lie.
4. **A teaching command carries the whole command.** Every `nextAction`,
   `runTemplate`, and reproduce command preserves every explicit selector
   the caller provided. Dropping a flag in a suggested command is
   accept-and-drop on the teaching surface and is banned like the dispatch
   variant.
5. **One ref grammar.** A ref emitted by any surface resolves on every
   surface that takes refs. If two spellings must exist, each surface
   accepts both or errors with the other as a suggestion.
6. **Effects resolve to booleans before they are reported.** Once target and
   flags are known, `mutating`/`repoWrite` are effective facts, never the
   command-level conditional. (Semantics owned by `Unified_Run_Model.md`;
   this phase owns *reporting* them resolved.)
7. **Feedback is data, not backlog.** Multi-agent dogfood reports enter a
   verified ledger (probe against code + live binary) before any slice
   exists. A single-prompt round may motivate a phase; it may not define the
   pass bar. The pass bar comes from the diversified harness.

## Anti-goals

- **No second run verb.** No `alln ask`/`alln chat`. MNR Law 8 (one grammar)
  stands; the fear that motivated the request dies with Law 6 (truthful
  effects), not with a duplicate entrypoint.
- **No overfitting to the July-20 prompt.** No slice may exist solely to make
  that one transcript prettier; each must trace to a verified finding plus a
  law.
- **No estimates.** Latency work reports observed `ttftMs`/`queueMs`/vendor
  wall clock; never projections of cost, tokens, or duration (no-estimates
  law).
- **No re-deciding MNR.** Menu shape, canonical-id-only dispatch, actions
  as 1:1 tagged specs, bootstrap-as-reflex are settled. SH-S05 *tags more
  specs*; it does not grow a taxonomy.
- **No default-format forks.** Envelope slimming is a schema change or an
  explicit flag, never TTY sniffing (rejected in AE, stays rejected).
- **No auto-registering projects silently.** Ceremony may be reduced only by
  an explicit, visible act (Open Q2). Silent state creation is how trust
  dies.

## Slices

Ordered by leverage. S01 is the safety-adjacent fix; S02 is what every agent
asked for.

| Slice | Deliverable |
| --- | --- |
| **SH-S01 — Dry-run tells the truth about this invocation** | Pinned-worker dry-run resolves and reports the *effective* run: the actual team/worker resolution the real run will use, effective seat count, and warnings only for state this invocation touches. `nextAction.command` round-trips **every** explicit flag (`--worker`, `--team`, `--effort`, `--lane`, `--detach`, …). Gates: (a) table test — for each selector flag, dry-run's `nextAction.command` contains it verbatim; (b) harness step — parse dry-run JSON, execute its `nextAction` shape with the probe message, assert resolved ids identical between preview and run. Fixes findings 1 + 2, Laws 3 + 4. |
| **SH-S02 — Answer-first, catalog-free envelope** | Add a stable top-level `answer` block to terminal `TeamRunJSON` (`markdown`, `workerId`/`modelId`, derivation: which shape rule picked it), defined per `outputKind` so multi-seat runs still have one canonical answer (lead output) with dissent intact underneath. Drop embedded `models` from the default envelope (run-relevant worker facts stay on `workers`/`workerAnswers`; full model records are `menu`'s job — if anything needs them post-hoc, hydrate by ref). Gate: byte budget on the one-shot envelope fixture (mirror the menu's 32 KiB pattern, sized in-slice) + schema test asserting `answer` present on every terminal shape. Fixes findings 3 + 4, Laws 1 + 2. |
| **SH-S03 — One ref grammar across docs/menu/errors** | `docs` accepts the dotted `command:*`/spaced forms `menu` emits (or: unknown-topic error suggests the resolvable spelling — Law 5 permits either, pick one). Durable half: a gate that walks every ref/`nextAction`/template emitted by `menu`, `docs`, and the error catalog and asserts each resolves on its consuming surface. Fixes finding 5. |
| **SH-S04 — Effects resolve before they're reported** | Dry-run (and run acceptance echo) report effective `mutating`/`repoWrite` booleans for the resolved target, per `Unified_Run_Model.md` semantics — a read-only answer resolution says so mechanically; if the read-only guarantee can't be proven for a seat, report `true` honestly (fail-closed stays). Fixes finding 9, Law 6. |
| **SH-S05 — Team authoring is one documented motion** | Founder decision first (Open Q1): either ship `teams new --file <preset.json> [--id <id>]` as a first-class create, or bless duplicate→edit as *the* path. Either way: accept explicit `--id` (predictable scripting), and the `teams duplicate`/`teams edit` docs cards teach the full round-trip (duplicate → definition → edit → restore) with a worked example. Gate: cold-agent harness row "make a custom bug-hunt variant" completes without reading source. Fixes finding 8. |
| **SH-S06 — Observed latency split in the outcome** | `outcome` (and headline) carry the already-recorded facts: `queueMs`, `ttftMs`, vendor wall clock — so "alln is slow" becomes "vendor X spent 8.1s of the 9.7s." Observed facts only; no targets, no estimates. Any actual latency *work* stays owned by the warm-lane phase. Addresses the latency perception without unmeasured optimization. |
| **SH-S07 — Harness v2: diversified prompts + economy scorecard** | Extend `scripts/agent_eval.sh --suite menu-not-router` (or a `--suite sharpening` sibling) beyond the July-20 prompt: one-shot ask, Send-to-team, custom-team authoring, detach + poll, error recovery (bad id, unregistered repo), docs lookup from a menu ref. Score per row: calls-to-answer, bytes parsed to reach the answer, preview/run resolution match, false claims filed by the agent afterward. **This scorecard — not a vibes rating — is the 9/10 definition** (see Done when). Enforces Law 7. |
| **SH-S08 — Papercuts (batch, cheap)** | Usage line enumerates enum values (`--effort <low\|med\|high>`) — generated from the same `FlagSpec` data `docs` already renders, no second authoring surface (finding 6). Tag additional command specs into `menu.actions` for harness-observed intents — 1:1 with public rows per MNR law, no taxonomy (finding 7). Document `--stream` framing in `docs run`. |

## Works test

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
B=Packages/AllnighterCore/.build/release/alln

# SH-S01 — preview truth + whole-command teaching
$B run "probe" --worker model_sonnet --dry-run --json > /tmp/dr.json
/usr/bin/python3 - <<'EOF'
import json; d = json.load(open('/tmp/dr.json'))
assert '--worker model_sonnet' in d['nextAction']['command'], 'pin dropped'
assert d.get('teamPresetId') != 'default_chat' or d.get('workerId') is None, 'default-team leak'
assert all('composer' not in w.lower() for w in d.get('warnings', [])), 'unrelated warning'
print('SH-S01 OK')
EOF

# SH-S02 — answer-first, catalog-free
$B run "Reply with exactly: success" --worker model_sonnet --json > /tmp/run.json
/usr/bin/python3 - <<'EOF'
import json; r = json.load(open('/tmp/run.json'))
assert r['answer']['markdown'].strip() == 'success', 'no first-class answer'
assert 'models' not in r, 'catalog embedded in run envelope'
print('SH-S02 OK')
EOF

# SH-S03 — refs resolve everywhere they are emitted
$B docs teams.duplicate >/dev/null 2>&1 || \
  $B docs teams.duplicate 2>&1 | grep -q 'teams duplicate'   # resolves or suggests
scripts/check.sh   # includes the emitted-ref walker gate

# SH-S04 — effects are effective booleans
/usr/bin/python3 -c "import json; d=json.load(open('/tmp/dr.json')); \
assert d['mutating'] in (True, False) and 'dependsOn' not in str(d['mutating'])"

# SH-S05 — predictable authoring
$B teams duplicate code_bug_hunt --id custom_probe_hunt --json | grep -q custom_probe_hunt
$B teams delete custom_probe_hunt --json

# SH-S06 — latency is observed, split, and never estimated
/usr/bin/python3 -c "import json; o=json.load(open('/tmp/run.json'))['outcome']; \
assert 'ttftMs' in str(o) and 'estimate' not in str(o).lower()"

# SH-S07 — the scorecard is the metric
scripts/agent_eval.sh --suite sharpening --binary "$B"
```

## Inference bans

| Junction | Truth owner | Bad inference | Mechanical ban |
| --- | --- | --- | --- |
| dry-run → real run | run resolver | "preview is approximate" | one resolution path serves both; harness asserts identity |
| nextAction → dispatch | teaching renderer | "the suggested command is close enough" | selector round-trip table test |
| envelope → answer | `TeamRunJSON.answer` | "the caller will find it in workerAnswers" | schema gate: `answer` on every terminal shape |
| run result → catalog | `MenuCatalog` | "embed models, someone might want them" | envelope byte budget + no-catalog gate |
| menu ref → docs | ref resolver | "each surface can own its spelling" | emitted-ref walker gate |
| effects → caller fear | resolved effects | "conditional is safe to report" | dry-run emits booleans only |
| one dogfood round → roadmap | verified ledger + harness | "four transcripts define done" | pass bar computed from diversified suite only |

## Done when

- SH-S01–S08 checked or explicitly waived with a founder note; Works test
  green on a release binary from committed HEAD.
- Preview/run resolution identity holds across the full harness (zero
  mismatches, zero dropped selectors).
- A one-shot answer is extractable from one stable JSON path, envelope within
  budget, no catalog data inside.
- Every ref emitted by any surface resolves (or suggests) on its consumer.
- **The 9/10 is mechanical, not a mood:** on the diversified SH-S07 suite,
  cold agents hit ≥ the pass bar on every row (calls-to-answer within budget,
  preview matches run, answer extracted first try) **and file zero false
  claims about the surface** — because when agents hallucinate defects, the
  surface is the defect. Ratings from future dogfood rounds are recorded as
  corroboration, never as the metric.

## Open questions (founder)

1. **SH-S05 shape:** first-class `teams new --file`, or bless duplicate→edit
   and only add `--id` + docs? (Duplicate→edit is honest about built-ins
   being immutable seeds; `new` is one motion. Either satisfies the law.)
2. **First-contact ceremony:** keep fail-closed `project add` (status quo —
   it worked for the agent that hit it), or add an explicit
   `alln project add --here`-style one-liner in the error's `nextAction`
   with git-root detection? Silent auto-register stays banned either way.
3. **Envelope default:** slim-by-default with `--full` escape hatch, or
   versioned schema cut that simply removes the catalog? (Contract-first
   instinct says the clean cut, per Foundation-first.)

## Routing

| Work | Read first |
| --- | --- |
| Dry-run fidelity / teaching-surface drops | **This doc** SH-S01 + MNR Law 7 |
| Run envelope / answer extraction | **This doc** SH-S02 → `TeamRunJSONMapper.swift` |
| Docs/menu/error ref grammar | **This doc** SH-S03 |
| Effects semantics | `Unified_Run_Model.md` (owner) + SH-S04 (reporting) |
| Team authoring UX | **This doc** SH-S05 (after founder answer to Q1) |
| Latency | `Warm_Single_Lane_Chat.md` (owner) + SH-S06 (reporting only) |
| Selection / menu / bootstrap | archived `Menu_Not_Router.md` — settled, do not reopen |
