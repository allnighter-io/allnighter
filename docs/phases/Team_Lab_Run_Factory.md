# Team Lab Run Factory

## Premise re-base (2026-07-16)

MCP was retired (`MCP_Retirement.md`); this doc was renamed from
`MCP_Run_Factory_Team_Lab.md`. The harness is CLI-native: it drives Teams through
the `alln` CLI only.

Status: Draft feature packet
Owner: Founder + Shared Core + CLI + Team Quality
Updated: 2026-07-16

## Founder Intent

Allnighter is agent-first through the CLI. The fastest path to better Teams is not
more app clicking. It is to run Allnighter through the same agent-facing `alln`
surface we expect OpenClaw, Hermes, Codex, Claude, and other agents to use.

The goal is to make every default Team measurably excellent:

```text
default Team starts as 4/10          # narrative only; never written to experiment.json
-> CLI-only factory runs many cases
-> every worker, prompt, artifact, timeout, and result is logged
-> run-contract checks prove whether the run told the truth
-> outcome anchors (decisive facts) prove judges track reality
-> blind A/B judges compare candidate output against the champion
-> team shape / prompts / model routing improve
-> fresh comparable inputs prove the Team is actually getting better
-> human-gated promotion until outcome oracles are green
```

**v1 stance — Oracle-anchored Run Factory (Option C, Spec Review 2026-07-16):**
decisive-fact outcome anchors are the Done When bar. Judges are retained and
measured against those anchors. Shipping/promotion stays human-gated until oracles
are green. See § Outcome Anchors and § Contrarian Dissent (preserved).

This is product dogfooding at the contract layer. The Mac app is not in the
loop. If the factory discovers CLI, run-journal, artifact, prompt, or status
bugs, those bugs are fixed before the Team quality conclusions are trusted.

## Product Value

Great default Teams are the product. A user should not need to understand which
worker was useful, which model timed out, or whether the writer averaged a bad
majority. Allnighter should learn that internally and ship better lineups.

The Team Lab turns subjective Team tuning into an experimental loop:

- benchmark cases instead of one-off anecdotes;
- full CLI JSON envelope / stream transcripts instead of GUI state;
- per-worker blind comparison instead of only final-answer taste;
- run-system bug capture instead of silent harness failure;
- before/after proof when prompts, roles, writers, or model routing change.

The product promise:

```text
Every default Team earns its seat.
```

**Post–Slice 1 composition work** (seat economics, cost ledger, VNRC, forward
selection, named team variants, necessity suite) is specified in
[`Team_Lab_Composition_And_Seat_Economics.md`](Team_Lab_Composition_And_Seat_Economics.md).
Slice 1's per-worker prompt loop remains built; that packet adds the **macro** loop
with asymmetric ADD/REMOVE gates so the factory does not assume the roster is
already right or optimize uniqueness theater.

## Trusted Workflow Slice

Primary slice:

```text
developer starts Team Lab Run Factory
-> factory invokes `alln` (team / run / floor / docs / doctor) with `--json`
-> factory calls `alln team hello --json` (optional readiness / front door)
-> factory selects a benchmark suite and Team
-> factory calls `alln team preflight ... --json`
-> factory calls `alln team start ... --json` with an idempotency key
-> factory polls `alln team status <run-id> --json` (or follows `--stream` NDJSON)
-> factory fetches `alln team result <run-id> --json`
-> factory fetches Floor/artifact views through `alln floor show ... --json`
-> factory writes a complete local lab record
-> truth evaluator gates CLI/run-system health
-> blind judges compare workers and writer against the champion
-> batch report recommends Team changes or substrate fixes
```

Bug-stop slice:

```text
factory cannot retrieve prompt/artifact/status truth through the CLI contract
-> mark experiment blocked
-> create Debugger packet
-> fix CLI/run contract (JSON envelopes, error catalog, `alln docs`)
-> rerun same case before changing Team prompts
```

Calibration slice:

```text
baseline suite for Bug Hunt
-> generate one fresh input
-> run champion and candidate on that exact same input
-> blind A/B compare per-worker output and final deliverable
-> bank only unanimous per-worker wins without hiding failures
```

## Non-goals

- No Mac app dependency. The factory must not start, click, scrape, or inspect
  SwiftUI surfaces.
- No private Core shortcut. The factory must not import `AllnighterCore` or call
  `TeamService` directly.
- No one-off prompt tasting as proof. Human notes are allowed, but benchmark
  reports need structured judge records and truth gates, not numeric quality scores.
- No automatic mutation of built-in Teams from a single run.
- No hiding failed workers because the final writer produced a useful answer.
- No broad Pending drain or scheduler semantics. Runs are explicitly triggered
  by the factory/client.
- No cloud service requirement. This is local-first and repo/app independent.

## Current State

Useful substrate already exists:

- `alln` exposes the agent-facing CLI surface (`alln team`, `alln run`, `alln floor`,
  `alln docs`, `alln doctor`, `alln help`).
- Team lifecycle verbs: `alln team hello`, `alln team preflight`, `alln team start`,
  `alln team status`, `alln team result`, `alln team cancel`, plus synchronous
  `alln team --json` where appropriate.
- Catalog write/read verbs (live; not greenfield): `alln teams definition`,
  `alln teams edit`, `alln teams duplicate`, `alln teams show`,
  `alln teams set-default`, `alln teams delete`, `alln teams restore`;
  `alln skills show`, `alln skills duplicate`, `alln skills new`,
  `alln skills edit`, `alln skills delete`.
- Floor / inspect: `alln floor show <run-id|latest> --json`.
- Help and contract surfaces: `alln docs`, `alln help`, error catalog, generated
  schemas; discovery without a second wire format.
- `AsyncTeamService` starts CLI-origin team runs, writes a durable run journal,
  persists progress, and returns a start envelope with run id.
- `RunStore` persists `run.json`, `bundle.md`, worker prompts, worker answers,
  stage artifacts, return artifacts, and metadata.
- `TeamRunJSON` and Floor projections are the machine-readable run result
  contracts.
- `--json` returns one complete structured object; `--stream` returns NDJSON
  events on stdout (progress on stderr). See `CLI_Product_Spine.md` and
  `CLI_Implementation_Contract.md`.
- `TeamCatalog` and `SkillCatalog` own default Team and Skill definitions.
- Agent front door: `alln bootstrap`, `alln team hello` (`Agent_Front_Door.md`).
- Depth rename already landed in Swift/catalog: bare `code_bug_hunt` is default
  send; Max is `code_bug_hunt_max` (`Team_Depth_Naming.md`). Lab artifacts that
  still hardcode `code_bug_hunt_lite` are **rot** (PRE-S0 / slice 1).

**Harness status (plain):** the v1 Python harness under `scripts/team_lab/` is
**dead code on the wire today**. `run.py` still opens
`alln mcp serve --stdio` (retired; command is unknown). ~8k lines of orchestration
exist and must be **mechanically re-based** to CLI argv — not rewritten greenfield.
Do not treat the harness as landed or production-ready until PRE-S0 is green on
pure CLI (`fsBypass=false`, no MCP process).

Local scratch records: `REPO/.lab/<experiment-id>/` (fiat; see § Experiment Record).

Known gaps still open:

- Harness still speaks MCP transport; mechanical CLI re-base is the next build slice.
- Depth-rename artifact rot: `champions/`, `candidates/`, `beta_campaign.jsonl`,
  `macro_overlay.py` may still reference dead `code_bug_hunt_lite` ids.
- Deterministic `lab_*` team id seed + full overlay round-trip through
  `teams edit --file` unproven (PRE-S0).
- Frozen suite refresh: two MCP-era cases need historical provenance (see
  § Historical suite cases).
- Live two-judge CLI path still needs validation; mock judges only prove orchestration.
- Outcome-anchored cases not yet seeded as the Done When bar.
- Corpus retention (input + both arms + verdicts) not wired — `used_inputs` stores
  hashes only today.
- Judge pair not process-pinned despite intent; re-baseline must fire on
  judge-version change.
- Stage artifact inline retrieval may still require FS diff-oracle.
- Team admission can fail before model work if the harness process cannot create or
  lock Allnighter's support-path governor slots. This must be reported as slot
  store unavailable, not as a fake "busy" capacity state.
- Readiness cache can lie when the factory runs under a different host,
  sandbox, support root, shell, or credential scope than the detector that wrote
  `SetupStore`. For lab purposes, "ready" means runnable by this `alln` process,
  not merely present in an old cache.

**Async ownership (pinned v1):** subprocess ownership only. Resident `alln serve`
is **v2**. Do not half-build both.

### Vocabulary debt (law — writer-first rename)

MCP-era field names remain in scoring until the re-base slice renames them.
**Direction is law for implementers** (script rename is a later slice; pin tests
in `test_scoring.py`):

| Debt | Trap | Rename direction |
| --- | --- | --- |
| `scoringSource: "mcp"` | Identity of pure-CLI path | Prefer `"cli"` / `"envelope"` once writers emit it |
| `pure_mcp_scoring` check name | Name lies after MCP death | Rename with writer |
| `mcp-transcript.jsonl` / `mcp_worker_*` | Paths and check ids | CLI transcript names |
| `fs_bypass = scoring_source != "mcp"` (`scoring.py:175-176`) | **Fails open** if the comparison string is renamed before the writer | **Writer-first:** new writers emit the new source value, then flip the gate to fail-safe (`fs_bypass` true unless pure CLI source), then rename the constant. Never rename the string first. |

### Historical suite cases (MCP-era provenance)

These cases cite deleted MCP surface (`MCPServer.swift` / `alln mcp serve`). They
are **historical replays**, not live CLI-era acceptance criteria, until a suite
refresh rewrites them:

| Case id | Provenance | Status |
| --- | --- | --- |
| `floor_show_wrong_run_v1` | MCP-era floor-arg regression; suite still lists it | Historical replay — keep with this label or drop on suite refresh |
| `mcp_fs_bypass_scoring_v1` | MCP-era pure-scoring gate; name is MCP-era | Historical replay — keep with this label or drop on suite refresh |

Do not treat either as a green PRE-S0 pure-CLI proof without re-authoring.

## Confirmed Substrate Bugs (Bug Hunt baseline r1, 2026-06-21)

Found by the lab, owned by `AllnighterCore`. The lab now gates on what it can
detect; these are for the substrate dev. Fix before any team-quality number from
an affected run is interpreted.

| ID | Severity | Truth | Owner (file:line) |
| --- | --- | --- | --- |
| SUB-1 | P2 | `teamRun.completedAt` is `run.workerAnswers.compactMap(\.finishedAt).max()` — the last **answer** worker's finish, stamped *before* synthesis. Run completion must be after the plan/synthesis stage finishes. | `TeamRunJSONMapper.swift:74-86` |
| SUB-2 | P2 | `team result` stages (`StageInfo`) omit `markdown`, `startedAt`, `finishedAt`; `plan.status` is hard-coded `.done`. Stage payload/timestamps exist internally but are not projected, so the lab cannot independently verify completion ordering (SUB-1) over the CLI envelope. | `TeamRunJSON.swift:184-194`, `TeamRunJSONMapper.swift:168-180` |
| SUB-3 | P3 | `workerAnswers[].finishedAt` is not serialized (only `durationMs`, `markdown`, `modelId`, `status`, `workerId`). Serialize it so completion ordering is checkable from the CLI JSON payload. | `TeamRunJSONMapper.swift` worker-answer mapping |
| SUB-4 | P3 | Floor `summaryMarkdown` is empty (0 chars) on a completed run; the packet body is only in `team result` `plan.markdown`. Either populate the floor summary or document it as never the packet source. | `FloorProjector` / floor projection |

Note on the earlier "writer shows `queued` / all worker status null" report: `workers[]`
metadata does **not** carry `status` by design (`TeamRunJSON.WorkerInfo`,
`TeamRunJSON.swift:149-165`). Terminal status for answer/review workers lives in
`workerAnswers[].status` (all `done` in the baseline). Writer status is only
representable via `plan.status`. The lab's worker-status check asserts every
non-plan worker has a `workerAnswers` status and that writer status is present.

## First-Principles Decision

The Team Lab is not a GUI QA harness. It is a CLI contract stress test plus a
Team-quality calibration loop.

The lab must answer two questions separately:

```text
Did Allnighter's run system tell the truth?
Did this Team produce excellent work?
```

If the run system did not tell the truth, Team quality is not judged. Fix the
substrate first.

## SSOT

Truth owners:

| Truth | Owner |
| --- | --- |
| CLI verbs, args, errors, schemas, JSON envelopes | `ContractRegistry` projected to generated CLI docs (`alln docs`, export-contracts) |
| Team definitions | `TeamCatalog` |
| Skill prompts | `SkillCatalog` |
| Models and ready Bench | `ModelCatalog`, `SetupStore`, source detector output |
| Run lifecycle | `AsyncTeamService` / `RunService` |
| Durable run truth | `RunStore` + `TeamRun` |
| Machine result contract | `TeamRunJSON` |
| Inspectable worker/artifact surface | `FloorRun` / Floor projection |
| Lab experiment truth | New `TeamLabExperiment` records, stored outside app GUI state |
| Evaluation rubric truth | New `TeamLabRubric` records by lane/team |

Lie-prone layers:

- The final synthesized answer can look good while individual workers are wrong,
  redundant, or timed out.
- A completed run can hide missing worker prompts, missing artifacts, or partial
  status truth.
- A GUI-visible result can mask CLI contract gaps.
- A majority theory can be weaker than a minority dissent.
- A cheap final score can flatten root-cause, evidence, proof, and usefulness
  into one misleading number.
- An empty lab support root can make readiness look optimistic unless the
  factory treats missing detection as unknown and runs doctor/preflight truth
  checks first.
- A provider CLI can be "ready" in the Mac app but fail from a harness
  subprocess because auth/session stores are unavailable to that process.

## CLI-Only Law

The factory must create, control, and retrieve runs only through the `alln` CLI.

Allowed:

```text
invoke: alln <verb> ... --json
stream: alln <verb> ... --stream   # NDJSON events when supported
call: alln team hello --json
call: alln help / alln docs / alln docs --errors / --schema
# Lifecycle
call: alln team preflight ... --json
call: alln team start ... --json
call: alln team status <run-id> --json
call: alln team result <run-id> --json
call: alln team cancel <run-id> --json
call: alln floor show <run-id|latest> --json
call: alln doctor / alln doctor explain <code> --json when blocked
# Catalog deploy / round-trip (six-verb acceptance matrix for re-base)
call: alln teams definition ... --json
call: alln teams edit ... --json
call: alln teams duplicate ... --json
call: alln teams show ... --json
call: alln skills duplicate ... --json
call: alln skills edit ... --json
# Also live when needed (not the re-base matrix spine):
#   teams set-default / delete / restore
#   skills show / new / delete
```

**Singular vs plural — do not "work around" with a file write:**

| Verb | Meaning |
| --- | --- |
| `alln team show` | Default team **per lane** (runtime default), not full definition dump |
| `alln teams show` / `alln teams definition` | Catalog listing / full `TeamPreset` definition round-trip |

Overlay deploy and champion banking use the **plural** `teams *` / `skills *`
registry verbs. Never bypass the CLI by writing catalog files under Application
Support or repo paths because `team show` looked incomplete.

Not allowed:

```text
start the Mac app
use SwiftUI/AppModel as an oracle
import AllnighterCore into the factory
call TeamService or RunStore directly for run creation
patch run files by hand
infer missing CLI truth from app-only behavior
resurrect MCP transport (alln mcp serve is gone)
```

Artifact capture rule:

```text
The CLI JSON envelope (and NDJSON stream) is the retrieval owner.
```

If the lab cannot retrieve worker prompts, worker answers, stage outputs, Floor
data, or final packets through CLI-returned structures or CLI artifact surfaces, the
answer is not "read the app state." The answer is "add the missing CLI retrieval
surface."

Final packet retrieval rule (pinned 2026-06-21):

```text
Canonical packet body  = team result (detail=full).plan.markdown
Answer/review bodies    = team result (detail=full).workerAnswers[].markdown
Worker prompt snapshots = team result (detail=full).workers[].resolvedWorkerPromptSnapshot
Terminal worker status  = workerAnswers[].status (answer/review); plan.status (writer)
floor show summaryMarkdown is NOT the packet source (empty on completed runs — SUB-4).
```

The harness reads the packet from `alln team result ... --json`, never from
`alln floor show` text or the copied journal. The journal copy under
`.lab/<exp>/run/` stays diff-oracle only.

Support-root rule:

```text
The factory records the exact Allnighter support root used by the alln process.
If the root is overridden for eval/sandbox work, the run record says so.
No experiment may compare results from two support roots as if they shared
readiness, idempotency, run history, or source credentials.
```

Admission truth rule:

```text
TEAM_GOVERNOR_BUSY = slots are actually locked by live team work.
TEAM_GOVERNOR_UNAVAILABLE = the alln process cannot create/open/lock the slot store.
```

The factory must stop on `TEAM_GOVERNOR_UNAVAILABLE`, call `alln doctor explain`
or `alln doctor --json`, and classify the experiment as a run-system issue. It must
not retry as if waiting would free capacity.

## CLI Surface

The lab itself is a development and product-quality tool. V1 is a repo tool that
spawns `alln` subprocesses and consumes `--json` / `--stream` envelopes. If
productized, it may expose a dev-facing CLI surface without bypassing `alln`.

Proposed dev CLI:

```bash
alln dev team-lab suites --json
alln dev team-lab run --suite <suite-id> --team <team-id> [--case <case-id>] --json
alln dev team-lab report <experiment-id> --json
alln dev team-lab compare <baseline-id> <candidate-id> --json
```

Important implementation rule:

```text
`alln dev team-lab run` spawns `alln team …` / `alln floor …` / `alln docs …`
with `--json` (and `--stream` when polling). It does not call Core/Engine run
APIs directly.
```

No new public CLI verb is required for the re-base / PRE-S0 path because the lab
is testing the existing team/run/floor/catalog contract. Add new CLI surfaces only
when a real retrieval or artifact gap is found, such as:

```text
alln run artifact get
alln run transcript get
alln lab report get
```

Those verbs must be registry-backed, schema-backed, and parity-tested before the
factory depends on them.

## Experiment Record

Every case run creates one local immutable lab record.

**Storage fiat (2026-07-16):** all lab experiment records live under the repo:

```text
REPO/.lab/<experiment-id>/
  experiment.json
  cli-transcript.jsonl
  run/
    team-result.json
    floor.json
    run.json
    bundle.md
    workers/
    stages/
  evaluation/
    run-contract-score.json
    worker-facts.json
    evaluator-record.json
    compare-record.json
    compare.md
    notes.md
  report.md
```

No Application Support lab root. Scripts already use `.lab/`; the spec matches them.

Committed benchmark definitions may live in:

```text
docs/team-lab/suites/
```

Large run logs, private prompts, model outputs, and user/project data stay local
unless explicitly exported for a report. Export must redact credentials, API
keys, home-directory secrets, and private source snippets unless the developer
chooses a repo-local dogfood suite.

## Experiment JSON

Draft shape:

```json
{
  "experimentId": "lab_2026_06_21_bug_hunt_baseline_001",
  "suiteId": "bug_hunt_repo_regressions_v1",
  "caseId": "composer_paste_dead_v1",
  "teamId": "code_bug_hunt",
  "teamDisplayName": "Bug Hunt",
  "variant": "baseline",
  "startedAt": "2026-06-21T00:00:00Z",
  "completedAt": "2026-06-21T00:06:00Z",
  "allnVersion": "0.6",
  "contractHash": "sha256:...",
  "gitHead": "acf8b3df",
  "cliSurface": {
    "binary": "alln",
    "invocation": "subprocess --json / --stream",
    "docsHash": "sha256:..."
  },
  "request": {
    "prompt": "...",
    "lane": "code",
    "team": "code_bug_hunt",
    "effort": "high",
    "contextRefs": [],
    "idempotencyKey": "..."
  },
  "run": {
    "runId": "3BF1481D-56CD-4E10-AE52-EAFB00D5174C",
    "status": "completed",
    "resultAvailable": true,
    "durationMs": 300000
  },
  "evaluation": {
    "runContract": 0.94,
    "fsBypass": false,
    "judgePending": true,
    "teamQualityScore": null,
    "compareRecord": null
  }
}
```

## Benchmark Case

Draft shape:

```json
{
  "caseId": "composer_paste_dead_v1",
  "teamFamily": "bug_hunt",
  "lane": "code",
  "title": "Composer paste appears dead after repeated fixes",
  "prompt": "We have tried and failed to fix the copy paste bug...",
  "contextPolicy": {
    "repoRoot": "/Users/mike/Documents/GitHub/Allnighter",
    "includeGitStatus": true,
    "includeGitDiff": true,
    "includeDebugLogs": true,
    "maxBytes": 120000
  },
  "humanNotes": [
    "classifies repeated bug as T3",
    "inspects current diff before root-cause confidence",
    "preserves dissent",
    "rejects weak majority theories with evidence",
    "names missing proof"
  ],
  "decisiveFacts": [],
  "knownTraps": [
    "stale-binding theory overfit",
    "isolated text-view tests treated as proof",
    "uncommitted paste override ignored"
  ],
  "scoringRubricId": "bug_hunt_v1"
}
```

## Logging Requirements

Each run must log:

- exact CLI argv, stdout/stderr, exit codes, and timestamps for every `alln`
  invocation (full JSON envelope / stream transcripts);
- `alln docs` / contract snapshot hash when used for readiness;
- `alln team hello --json` readiness result when used;
- Allnighter support root, relevant process environment, and whether the
  support root was overridden for lab/sandbox execution;
- first-start facts: binary path, binary version, git head, contract hash,
  support root, current working directory, PATH source, process pid, and client
  identity;
- `alln team preflight` result;
- `alln team start` request and start-response envelope;
- every `alln team status` response and polling interval (or NDJSON stream events);
- `alln team result` response, including not-ready envelopes;
- Floor/artifact retrieval responses (`alln floor show`);
- all error envelopes and `alln doctor explain` output when used;
- run id, origin metadata, idempotency key, lane, team, effort, and context hash;
- full worker lineup: model, source, skill, purpose, status, duration, exit code;
- source readiness provenance: cached detector record, live doctor/probe record,
  or explicit "unknown";
- spawn plan per worker: source id, invocation type (`direct`, `shim`,
  `loginShell`, or bare command), resolved executable path, sanitized argv shape,
  working directory, timeout budget, streaming mode, output capture mode, and
  whether a detected invocation was used;
- full worker prompt snapshots;
- full worker outputs;
- writer prompt, spawn plan, terminal status, and output;
- timeouts, cancellations, interruptions, hidden partials, last stdout/stderr
  activity timestamp, stdout/stderr byte counts, and whether the watchdog was
  idle-timeout or wall-clock-timeout;
- raw terminal classification before synthesis: launch failure, auth/manual
  prompt, provider capacity, local permission denial, parser failure,
  empty-output, timeout, cancelled, or nonzero exit;
- retry/fallback facts: streaming attempted, streaming terminal state,
  non-streaming fallback attempted, fallback result, and reason for fallback;
- run-store artifact refs returned through CLI envelopes;
- blind judge prompts, judge outputs, compare records, and non-voting hypotheses;
- human notes, if any, as separate commentary, never as hidden score truth.

Failure aggregation:

```text
first start failed
worker launch failed
worker auth/manual blocked
worker provider-capacity blocked
worker local-permission failed
worker timed out
worker parser/output failed
writer failed
CLI retrieval failed
```

Every category must be countable by Team, source, model, skill, host process,
support root, and Allnighter version. Timeout is presumed to be an Allnighter
spawn/streaming/watchdog problem until the log proves the provider returned no
events under the same invocation path a human can run successfully.

The lab report must distinguish:

```text
observed fact
model inference
human note
deterministic check
```

## Judge Loop (v2, authoritative)

Quality is judged, never scored. There is no deterministic number for judgment —
deterministic scoring of judgment optimizes for stupid things (saying the magic
words a heuristic likes). The only deterministic lane is **truth** (run contract +
"did a worker return content" + writer consistency).

The loop:

```text
0. Substrate gate: both runs must be run-contract green (compare.py refuses otherwise).
1. Outcome-anchor gate (when case has decisiveFacts): both arms scored against the
   oracle; judges that invert the oracle ordering are under calibration, not shipping.
2. Pick a FRESH input (scenario.py for transfer rounds; frozen for anchor cases);
   run champion and candidate on that SAME input with the SAME evidence packet.
3. BLIND output A/B: each judge sees only the two outputs (anonymized, order seeded),
   never the prompts, model names, or which side is the candidate.
4. Per WORKER: two different-family judges each pick A/B/tie. Bank the candidate's
   prompt for that role iff BOTH pick the candidate. Tie/split/baseline -> incumbent.
5. DELIVERABLE A/B (same blind method): banking is per-role; promotion/shipping is
   blocked by deliverable regression (interactionWarning / baseline deliverable).
6. Un-blind: the idea-engine reads the prompt diffs + verdicts and proposes the next
   single-variable changes. It is NON-VOTING — it never decides keep/discard.
7. Retain the corpus (input + both arms' outputs + verdicts). Mark input burned for
   reuse as a fresh generator seed, but never forget the labeled pair.
```

Why this is more valid than judging prompts: the prompt is the method, the output
is the result. A prompt that looks ridiculous but whose output two blind judges
prefer, repeatedly, on fresh inputs, is working — **and** must not invert a
decisive-fact oracle on frozen anchor cases. Optimize for results, anchored to truth.

Roles:

| Thing | Role | Decides? |
| --- | --- | --- |
| Outcome anchor (`decisiveFacts`) | Done When bar — packet naming F must beat one missing it | Calibration gate |
| Per-worker blind A/B | unit of optimization — **bank** each role independently | YES (unanimous bank) |
| Deliverable blind A/B | **blocks promotion** on regression; does not unbank per-role wins | YES (promote gate) |
| Idea-engine (un-blind) | propose next-round single-variable changes | No (advisory) |
| Run contract (deterministic) | truth gate — may the run even be judged | Gate |
| Human gate (v1) | shipping until oracles are green on anchor suite | YES (ship) |

Bias controls (the reason this is run in orchestration/isolation):

- Two **different model families**, **pinned + version-stamped**; same model twice is
  a correlated echo, not a vote. **Genesis re-baseline fires on judge-version change**
  (not "periodically") — the multi-round transfer chain assumes a stable instrument.
- **Isolated, parallel, sealed** verdicts — no judge sees another's before committing.
- **Blind + order-seeded** — the judge cannot tell which output is the new one.
- **Incumbent wins ties** — the `AND` gate trades false-negatives for near-zero
  false-positives; correct asymmetry for editing production prompts.
- **Don't let a model judge its own family's output** as a deciding vote.
- The input generator must not be the same model that judges that round.

Honest limit: judges evaluate **artifacts, not outcomes**. Two judges preferring a
packet is shared taste, not proof the diagnosis is right. **Outcome Anchors**
(§ below) make that falsifiable.

Harness:

```bash
python3 scripts/team_lab/scenario.py <suite-id> > /tmp/team-lab-case.json  # fresh input + burn ledger
python3 scripts/team_lab/run.py --suite <suite-id> --case-json /tmp/team-lab-case.json ...
python3 scripts/team_lab/compare.py <baseline_dir> <candidate_dir> [--hypotheses]
# judges: export ALLN_JUDGE1_CMD / ALLN_JUDGE2_CMD to two DIFFERENT provider CLIs
# (--mock runs deterministic judges for pipeline smoke only; records are not evidence)
python3 scripts/team_lab/promote.py --compare-record <candidate>/evaluation/compare-record.json \
  --baseline-lab <champion_dir> --candidate-lab <candidate_dir> \
  --suite <suite-id> --team <team-id> --round <N+1>
python3 scripts/team_lab/advance.py --suite <suite-id> --team <team-id> --round <N> \
  --champion-overlay docs/team-lab/champions/<suite>/<team>.json
```

### Banking vs promotion policy (human-gated until oracles green)

**Banking is per-role.** A clean unanimous per-worker win banks that role's
candidate prompt into the working candidate overlay.

**Promotion / shipping is a separate gate.** Deliverable regression blocks
promotion (`promote.py` already escalates on `interactionWarning` and deliverable
`baseline` — code is right; this prose matches it). Until outcome anchors on the
frozen suite are green and judges do not invert them, **shipping stays human-gated**.
No silent champion flip into production TeamCatalog.

**Machine-propose promote when** (`promote.py` gate, still subject to human ship):
`judgeMode=live`, `evidenceValid=true`, `sameInput=true`, `interactionWarning=false`,
no unmatched roles, `bankedRoles` non-empty,
`championConfigHash != candidateConfigHash` (material candidate delta),
`deliverableOutcome` is `candidate` (or a narrow tie with few banks), and
outcome-anchor calibration has not failed on the suite's anchor cases.

**HOLD** when: `championConfigHash == candidateConfigHash` → `no material candidate delta`.
R3-style identical-config rounds are automation smoke, not quality improvement.

**Escalate (exit non-zero, no promote)** when: judges split repeatedly on
deliverable while many roles bank; deliverable regresses to baseline; run-contract
not green; mock judges; structural role mismatch; model/source failures make
evidence suspect; overlay declares template changes but CLI cannot wire lab skills
into team rows; outcome anchor inverted; or the change would touch privacy,
credentials, billing, destructive actions, or distribution.

**Quality rounds** (`advance.py`): require `--hypotheses-from` or `--candidate-overlay`
so the candidate arm differs (hypothesis patch, skill fork, etc.). Use
`--calibration-smoke` only for automation calibration (skips promotion).

**Teams definition surface:** full `TeamPreset` JSON (including `workerSpecs`,
skill refs, effort) must round-trip byte-faithfully through
`alln teams definition` / `alln teams edit --file` / `alln teams show`. Summary-only
views stay summary-only. Do not use singular `team show` as the definition path.

**SkillCatalog shipping:** after enough clean fresh-input wins with material deltas,
`promote.py` writes a reviewable patch under `docs/team-lab/patches/` (only roles
whose template differs from built-in). Human reviews before catalog merge.

**Champion key:** `docs/team-lab/champions/<suite>/<team>.json` — banked role
provenance + templates. **Reserve a scope dimension** in the key path (e.g. future
`champions/<suite>/<scope>/<team>.json` for per-user / per-root learning). Name the
axis; do **not** wire per-user learning in v1. `run.py --champion-overlay` deploys
a lab team via CLI before `alln team start`.

**Catalog refresh semantics:** each `alln team start` is a **fresh process**. Unlike
the retired MCP harness (which snapshotted the catalog at `mcp serve` init and
needed a restart after save), CLI-native deploy does not require process restart
for the next start to see `teams edit` / `teams duplicate` results. Spec must
state this; harness must not invent a restart ritual.

### Pinned judge pair

| Seat | Family (pinned) | How |
| --- | --- | --- |
| Judge 1 | Anthropic Claude family via provider CLI | `ALLN_JUDGE1_CMD` |
| Judge 2 | OpenAI / Codex family via provider CLI | `ALLN_JUDGE2_CMD` |

Both commands are **version-stamped into every compare record**. When either
judge binary/version changes, **force genesis re-baseline** before banking or
shipping further champion deltas. Silent provider updates without re-baseline are
a measurement bug.

## Evaluation Rubrics

Only the **Run Contract Score** below is deterministic (it measures truth). The
Worker / Writer / Team Quality criteria are **judge guidance for the blind A/B in
the Judge Loop** — things a judge should weigh — NOT checklists that produce a
score. Do not turn them back into deterministic counts. There is **no lab score-band
artifact**; founder `4/10 → 9/10` language lives only in Founder Intent (narrative).

### Run Contract Score (checklist)

Measures whether Allnighter told the truth. PRE-S0 / harness must also cover the
items under **Contract & proof checklist** in Implementation Slices.

- preflight blocked bad runs before quota;
- `alln team start` returned a run id only after journal creation;
- status changed honestly;
- polling cadence was respected;
- terminal state matched artifacts;
- every assigned answer/review worker had a visible terminal status in
  `workerAnswers[].status`, and writer status was present (worker-status
  check: `statusedAnswerCount == nonPlanWorkerCount` and `writerStatusPresent`);
  a dropped/hidden worker fails this check and withholds team quality;
- failed/timed-out workers were not hidden;
- prompts and outputs were retrievable via pure CLI envelopes (`fsBypass=false`);
- writer/stage outputs were retrievable;
- `TeamRunJSON` matched Floor/artifact truth;
- idempotency behaved correctly;
- interrupted/orphaned runs recovered honestly;
- CLI schemas matched generated contract docs (`alln docs` / export-contracts);
- **SUB-1 withhold:** `completedAt` still derives from last worker-answer finish
  (`TeamRunJSONMapper`) — do not treat it as post-synthesis completion until fixed;
- **SUB-2 withhold:** `StageInfo` still omits markdown/timestamps — stage temporal
  truth is not CLI-proven until fixed.

### Worker Judge guidance

Measures each worker independently:

- followed its role prompt;
- inspected the right evidence;
- produced novel useful facts;
- avoided unsupported certainty;
- named falsifiers or missing observations;
- avoided duplicating another worker's generic answer;
- preserved boundaries and blast radius;
- returned within time;
- produced output the writer actually used;
- caused harm through wrong confidence or broad fix advice.

### Writer Judge guidance

Measures synthesis:

- did not average weak answers;
- ranked hypotheses;
- preserved dissent;
- rejected bad majority theories with reason;
- named the smallest next observation/test;
- separated live hypotheses from rejected ones;
- exposed worker failures and timeouts;
- produced the requested output kind;
- returned a typed packet when the Team contract requires one;
- made next actions executable by a human or Try Fix gate.

### Team Quality Judge guidance

Measures the final result against the Team's job. **v1 lab focus is Bug Hunt**;
other lanes are deferred (LAB-S06+) and listed only as guidance when those teams
enter the factory.

Bug Hunt:

- reproduces or narrows the symptom;
- classifies tier correctly;
- names truth owner and lie-prone layer;
- inspects current diff, logs, prior attempts, and proof gaps;
- distinguishes observed facts from inference;
- gives the cheapest discriminator;
- avoids symptom patching;
- names smallest correct fix boundary;
- names regression proof;
- produces a high-confidence `FixPacket` only when justified.

Deferred lane guidance (not v1 acceptance): code planning, design, copy, signal —
same judge-guidance pattern when those teams enter the factory; do not expand
rubric surface in v1.

## Default Team Calibration Loop

For each default Team:

1. Run baseline suite.
2. Produce per-case and batch reports.
3. Identify weak roles, missing roles, prompt failures, model-routing failures,
   writer failures, and CLI/run-system bugs.
4. Stop and fix any run-system bug that invalidates evaluation.
5. Change one Team variable at a time:
   - role removed;
   - role added;
   - role prompt changed;
   - model preference changed;
   - writer prompt changed;
   - evidence packet added;
   - structured packet requirement added.
6. Rerun the same suite.
7. Compare baseline and candidate.
8. Keep the change only if quality improves without hiding failures or increasing
   run-contract defects.
9. Update Team/Skill source truth.
10. Add the benchmark as a regression guard.

## Bug Hunt First

Bug Hunt is the first lab specimen because a recent run showed the exact shape
this lab is designed to improve:

- the final packet was strong;
- several answer workers missed the decisive current-diff fact;
- the majority theory was likely wrong;
- the contrarian worker was highly valuable;
- the writer did the right thing by rejecting the weak majority;
- multiple workers timed out;
- some roles overlapped or ran at the wrong phase;
- the system did not present a run-quality scorecard by default.

Initial Bug Hunt experiments (**micro / prompt loop only** — roster shape changes
belong to the composition macro packet, not this table):

| Experiment | Variable |
| --- | --- |
| Baseline | current built-in bare Bug Hunt (`code_bug_hunt`) |
| Evidence Packet | same CLI-collected packet held constant across arms |
| Model Routing | reserve Opus for Contrarian + Writer, use faster code-local workers for answer roles |
| Discriminator Role | add explicit cheap-test splitter |
| Writer Contract | require rank/reject/dissent/next-observation fields |
| Typed Return | require `BugPacket`/`FixPacket` eligibility fields |
| Outcome Anchor | frozen case with known decisive fact F (see § Outcome Anchors) |

**Not in the micro loop:** Reduced Team / Phase-Split / seat add-remove — those are
macro composition experiments (`Team_Lab_Composition_And_Seat_Economics.md`).

Depth note (see `Team_Depth_Naming.md`): bare `code_bug_hunt` / "Bug Hunt" and
bare `code_spec_review` / "Spec Review" are the default sends. Escalation depth
is `*_max`. Spec Review Min/Default/Max already ship as curated product teams
(2026-07-18); Lab validates and tunes them — it does **not** invent, delete, or
collapse those IDs. Bug Hunt Min remains optional until necessity proves it.
**Nothing may say default → Min.**

## Lab model policy

**SSOT:** `scripts/team_lab/model_policy.py` — applied on every lab experiment via
`overlay.ensure_model_policy_team` unless `ALLN_LAB_MODEL_POLICY=0`.

**Lab-only — never product rewrite.** This policy remaps seats **inside lab
overlays / experiments**. It must not permanently edit `BuiltInTeams` Spec Review
preferreds or ordered fallback chains (Fable lead, Sol strategic, Kimi/Grok-first
workers). If a Spec Review lab run needs a temporary policy remap, keep it in the
overlay and restore product truth afterward.

**Do not use Antigravity / Gemini (`model_gemini`, `model_gemini_pro`, any
`model_agy_*`) on lab worker seats.** Product teams may still roster those
drivers (Spec Review Default/Max Contrarian prefers Gemini); the lab excludes
them after R6 (wrong-cwd fixed in product; agy still hit wall-clock / vendor
timeouts and poisoned contract scores). Re-add only with an explicit policy
change in `model_policy.py` plus a green calibration round — not ad-hoc overlay
overrides.

| Seat class | Allowed |
| --- | --- |
| Lead / synthesis / writer | `model_opus` only *(lab remap; product Spec Review Lead prefers Fable)* |
| Rotating workers | `model_grok`, `model_cursor_composer_25`, `model_chatgpt`, `model_cursor_auto` |
| Diversity (≤1 per run) | `model_sonnet` at worker index 2 |

**Design lane lab fanouts** (future design-team rounds): `model_grok` + `model_chatgpt`
only — no Gemini/AGY in lab even though product mockup engines include Gemini Flash.
Duplicate Grok/GPT seats are allowed.

`overlay._verify_model_policy_definition` rejects champion/candidate overlays that
assign blocked models to worker seats.

### Seat assignment vs runtime resolution

Each worker seat gets a **preferred** catalog id from the rotation (Sonnet once at
index 2). The same id may appear on multiple seats after **bounded-pool fallback**:
when a preferred model is unavailable, `exactOnly` with `allowedModelIds` = the full
worker pool keeps resolution inside the no-AGY pool (strongest ready alternative).
R6 showed `model_cursor_auto` → `model_chatgpt` on two seats — valid lab behavior,
not a broken `exactOnly` implementation.

**Reproducibility:** `experiment.json` → `preflight.warnings` records each
preferred→resolved substitution. For strict “preferred or fail,” set
`ALLN_LAB_STRICT_MODEL_SEATS=1` before `run.py` / `advance.py` (aborts when
preflight warns about unavailable preferred models).

**Duplicates:** multiple GPT 5.5 (or any pool model) seats in one run are allowed.
Diversity is a goal, not a hard invariant, when fallback or rotation collides.

## Evidence Packet

Many Team failures are upstream context failures. For bug and code teams, the
factory creates a shared evidence packet before workers start.

**Held constant across arms.** Champion and candidate in the same round receive
the **same** evidence packet bytes. The factory does **not** "max context" for one
arm. Seat wins that come from context inflation are invalid.

For Bug Hunt, the evidence packet includes:

- repo root;
- `git status --short`;
- current branch and HEAD;
- `git diff --stat`;
- relevant `git diff` excerpts;
- recent commits touching the surface;
- matching `DEBUGLOG.md` entries;
- matching `BUG_PATTERNS.json` entries;
- matching regression law backlog entries;
- relevant source snippets;
- known founder observations;
- blocked proof commands.

The evidence packet is not a model answer. It is observed context. Worker prompts
must cite which evidence they used and which evidence would falsify their theory.

## Prompt Contract Changes

Every worker prompt in a lab-calibrated Team should require:

```text
Evidence inspected:
Key claim:
Confidence:
What would falsify this:
What I reject and why:
Missing observation:
Output:
```

Additional Bug Hunt rule:

```text
No high-confidence root cause unless current diff/log/prior attempts were
inspected or the worker explicitly says that evidence was unavailable.
```

Writer rule:

```text
Do not average. Decide. Preserve dissent. Prefer the mechanically checkable
minority over a confident majority when the evidence is stronger.
```

## Run-System Bug Ladder

The factory is allowed to discover product bugs. It must not paper over them.

| Severity | Example | Required action |
| --- | --- | --- |
| P0 | CLI cannot start a run, loses run id, corrupts result | Stop batch, Debugger packet, fix before continuing |
| P1 | Worker failure hidden, prompt missing, status lies, artifact unreachable | Stop affected suite, fix retrieval/status contract |
| P1 | `fsBypass=true` (scoring relied on copied journal, not pure CLI envelopes) | Team quality judgment **withheld**; fix CLI retrieval or harness |
| P2 | Report incomplete, evaluator unclear, schema awkward | Record and continue only if the compare record remains interpretable |
| P3 | Report polish or convenience issue | Backlog |

For P0/P1, the batch report must say:

```text
Team quality judgment withheld because run contract failed.
```

## Privacy, Security, and Cost

The lab can spend real model quota and may send benchmark context to external
CLI providers exactly like normal Team runs.

Rules:

- Use explicit suites. Do not silently sweep arbitrary private projects.
- Redact secrets in CLI transcripts and exported reports.
- Keep raw run logs local by default.
- Mark suites that contain private source code.
- Record which models/sources were invoked.
- Respect the same entitlement, source, and mutating gates as normal CLI runs.
- Never let an evaluator mutate a repo unless routed through an execution Team
  with the normal write lock and approval semantics.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Final packet -> worker quality | Team Lab evaluator | Good final answer means all workers worked | Score workers independently | Batch with good final output and timed-out workers still flags worker failures |
| GUI run -> CLI readiness | CLI contract | App can run it, so CLI can run it | Lab must use CLI only | Harness test fails if Core/App APIs are imported |
| `completed` status -> complete artifacts | RunStore/Floor | Terminal run means prompts and outputs are retrievable | Artifact completeness is separate | Completed fixture missing worker prompt fails run-contract score |
| Majority agreement -> correctness | Writer/evaluator | More workers said it, so it wins | Writer must rank evidence, not votes | Case where minority has decisive diff evidence must score majority-following writer low |
| Human taste -> benchmark proof | Team Lab rubric | Founder liked one answer, so Team is fixed | Keep human notes separate from scores | Report schema separates `humanNotes` from rubric fields |
| CLI gap -> local file workaround | CLI contract | Just read the file directly | Add/revise CLI retrieval surface | Harness marks direct run-store read as contract violation unless from CLI artifact ref |
| CLI gap -> local file workaround | CLI contract | Just read the file directly | FS copy is diff-oracle only; scoring must use CLI payloads | Harness pure-CLI scoring fails when `fsBypass=true`; team quality withheld |

## Measurement Validity (v1)

The `4/10 -> 9/10` headline is **founder narrative only** (see Founder Intent) until
these rules bind — never a field on `experiment.json`:

- Run-contract lane must be green (`fsBypass=false`, `runContractScore >= 0.95`) before
  any Team-quality judgment is interpreted.
- Compare **logical workers once** (not duplicate artifact paths).
- Fresh inputs across rounds; within one round both arms must share the exact same
  input **and the same evidence packet**.
- Built-in Team mutations require **>= 3 clean live compare rounds** on fresh inputs
  with live judge preference, no run-contract regression, **human ship gate**, and
  **no outcome-anchor inversion**.
- Writer consistency: discard worker claims contradicted by `experiment.json` and
  run-contract artifacts.

There is **no deterministic quality score** (removed 2026-06-21 — see § Judge Loop).
Keyword/structure scoring rewarded the template words the prompts already mandate
(Goodhart), so it optimized for theater. Quality is decided by the two-judge
blind A/B in `compare.py`, **calibrated against outcome anchors**. What stays
deterministic is **truth**: the run-contract lane, the worker "did it return content"
/ writer-consistency checks, and decisive-fact oracles on frozen anchor cases
(`test_scoring.py`, `test_judge.py`).

## Outcome Anchors

**Done When bar (v1):** the suite ships with **≥1 outcome-anchored case** where a
known decisive fact **F** exists. A packet that **names F** (and uses it correctly)
must beat a packet that **misses F**, under both (a) the deterministic oracle check
and (b) the pinned judge pair. If judges systematically invert that ordering, the
**judges are under test** — stop shipping prompt banks until calibration recovers.

Schema (case-level, optional):

```json
{
  "decisiveFacts": [
    {
      "id": "paste_override_uncommitted",
      "mustMention": ["uncommitted", "paste", "override"],
      "humanNote": "current diff shows the uncommitted paste override"
    }
  ]
}
```

- Frozen for the anchor case; `scenario.py` generation is for **transfer** rounds only.
- Oracles are coarse by design — they do not replace synthesis judgment (writer
  demoting a weak majority). They stop the closed taste loop from being the only
  instrument.
- New champions must not regress the outcome-anchor bank (see § Burn Ledger / Corpus).

## Burn Ledger / Corpus Retention

Burn discipline means **remember, then refuse reuse as a "fresh" generator seed** —
not forget.

Each round already produces a labeled preference pair no competitor can reconstruct.
Retain permanently (keyed for replay under `.lab/` and/or `docs/team-lab/corpus/`):

- input prompt + case id + content hash;
- evidence packet hash;
- both arms' worker outputs + deliverable markdown;
- compare record / verdicts / judge versions;
- banked roles and promote decision.

`used_inputs/*.jsonl` hash-only entries are insufficient alone. Wire corpus
retention **before the first live quality round** after re-base — retroactive
capture is impossible. New champions must not regress the corpus bank on
outcome-anchored cases.

## Lab Budget

The lab is a quota product. One quality round ≈ 2 full team runs + ~16 per-worker
judge calls + 2 deliverable judges (+ ~8 idea-engine calls). Policy:

| Rule | v1 |
| --- | --- |
| Pinned judge pair | Claude-family + OpenAI/Codex-family only (§ Judge Loop) |
| Concurrent rounds | Cap concurrent lab rounds in `run.py` / `advance.py` (default 1 live quality round) |
| Mock default for orchestration | `--mock` for harness/orchestration CI; mock never supports banking or ship |
| Macro suite | Necessity / composition suite **never** runs on the micro prompt loop |
| Campaign spend | Explicit budget or founder cap before multi-round campaigns; record spend proxy in experiment metadata |

## Experiment Design (v1)

No team mutation is proposed without a pre-registered design. Each calibration
experiment declares, before running:

```text
Hypothesis:        one sentence; what the change should improve and why.
Changed variable:  one OR MORE worker prompts. Per-worker blind A/B gives clean
                   per-role attribution, so you are NOT limited to one variable for
                   role-local prompt changes — change several, see which banked.
                   (Structural changes — add/remove a worker — break 1:1 role
                   mapping and fall back to the deliverable A/B; those are macro.)
Input discipline:  WITHIN a round both arms run the SAME input + SAME evidence
                   packet. BETWEEN rounds the input is FRESH (scenario.py + burn
                   ledger). Reusing one input across rounds is overfitting.
                   Power comes from input DIVERSITY across rounds.
                   compare.py refuses sameInput=false.
N:                 1 run per arm per round is acceptable — a test of 1 beats a test
                   of 0, and diversity across rounds accumulates the signal. Replay
                   the same input >=3x only to MEASURE variance, never to claim a win.
Decision rule:     bank a worker's candidate prompt iff BOTH blind judges pick the
                   candidate for that role; any tie/split/baseline keeps incumbent.
                   Banking is per-role. Promotion is blocked by deliverable
                   regression. Human-gated ship until outcome oracles are green.
                   No deterministic quality score decides banking.
Mock rule:         --mock validates orchestration only. Mock compare records are marked
                   evidenceValid=false and must never support a Team mutation.
Transfer guard:    a banked change must keep winning on FRESH inputs over rounds;
                   re-baseline against GENESIS on judge-version change (and when
                   drift is suspected), not only last champion; re-challenge banked
                   workers occasionally.
Negative results:  recorded, not discarded; corpus retains the pair.
```

The two judges are different model families, pinned + version-stamped, run in
isolation. See § Judge Loop for the full mechanism.

## Implementation Slices

**These are spec slices — do not execute them in a docs-only pass.**

**Wire / full package note:** [`Team_Lab_Slice_1_Full_Package.md`](Team_Lab_Slice_1_Full_Package.md)
is superseded **for wire format** (MCP dead). This doc owns the CLI wire.
Historical micro-loop intent in that packet still informs scope.

**Post–micro composition / seat economics:**
[`Team_Lab_Composition_And_Seat_Economics.md`](Team_Lab_Composition_And_Seat_Economics.md)

### PRE-S0 gates (blocking — above everything)

Hard gates before any quality claim is trusted:

1. **Depth rename landed (artifact rot).** `code_bug_hunt_lite` must not remain as a
   live champion/candidate/daemon id. Migrate `champions/`, `candidates/`,
   `beta_campaign.jsonl`, `macro_overlay.py`. Check `run_lab_daemon.sh` history —
   if a daemon still calls the dead id, it is an outage, not fixture rot.
2. **Pure CLI.** No MCP process. `fsBypass=false`, `runContractScore >= 0.95` on a
   real Bug Hunt case.
3. **Deterministic `lab_*` id seed.** Deploy a team with a predictable
   `lab_<team>_r<N>_<arm>` id (not only opaque `custom_*` from bare duplicate).
4. **Full overlay round-trip.** `TeamPreset` with `workerSpecs`, skill refs, and
   effort through `teams edit --file` → `teams definition` / `teams show`,
   **diffed** byte-faithfully.
5. **Retrieval.** `alln team result … --json` (detail=full) returns worker prompt
   snapshots + answer markdown + plan; `alln floor show <run-id>` returns the
   requested run (not latest-by-accident). Journal under `.lab/run/` is
   diff-oracle only — zero score weight.
6. **Contract withholds named.** SUB-1 (`completedAt`) and SUB-2 (`StageInfo`
   missing markdown/timestamps) remain explicit withholds — do not claim temporal
   stage truth over CLI until fixed.
7. **Catalog refresh stated.** Next `alln team start` after `teams edit` sees new
   definition without MCP restart ritual (fresh process each start).
8. **Async ownership.** Subprocess-only v1; `alln serve` is v2.

Proof sketch:

```bash
# after mechanical re-base (slice 2)
python3 scripts/team_lab/run.py --suite bug_hunt_repo_regressions_v1 --round 1 --variant baseline
python3 scripts/team_lab/evaluate.py .lab/<experiment-dir> --rescore-contract
# expect: pure CLI scoring ok (fsBypass=false), no mcp process, team quality not withheld for wire reasons
```

### Recommended slice order (v1)

Replace greenfield LAB-S00–S04. The harness is an 8k-line transport swap, not a
rewrite.

| # | Slice | Acceptance |
| --- | --- | --- |
| **1** | **Fix artifact rot** | No live `code_bug_hunt_lite` in champions/candidates/campaign/macro_overlay; daemon history checked |
| **2** | **Mechanical CLI re-base** | `run.py` / `overlay.py` / `scoring.py` use the **six-verb map** as acceptance matrix (`teams definition/edit/duplicate/show`, `skills duplicate/edit`). Rename `scoringSource` **writer-first** so `fs_bypass` fails safe |
| **3** | **PRE-S0 green** | Real Bug Hunt case, `fsBypass=false`, pure CLI, deterministic `lab_*` seed + full overlay round-trip |
| **4** | **Frozen suite refresh + one outcome-anchored case** | MCP-era cases labeled historical or rewritten; ≥1 decisive-fact anchor |
| **5** | **Corpus retention** | Input + both arms + verdicts retained before first live quality round |
| **6** | **Judges pinned + genesis re-baseline on version change** | First live quality round; human-gated promotion only |
| **7** | **Macro / composition / autopromote-to-overlay** | Only after 5–6 are boring |

### MCP-tool → CLI-verb acceptance matrix (re-base)

| Retired MCP-era intent | CLI verb (argv) |
| --- | --- |
| Read team definition | `alln teams definition … --json` |
| Write / patch team | `alln teams edit --file … --json` |
| Clone team for lab arm | `alln teams duplicate … --json` |
| List / inspect teams | `alln teams show … --json` |
| Clone skill template | `alln skills duplicate … --json` |
| Patch skill body | `alln skills edit … --json` |
| Run lifecycle | `alln team preflight/start/status/result/cancel --json` |
| Floor / artifacts | `alln floor show … --json` |

**Warning:** `alln team show` ≠ `alln teams show`. Definition round-trip is plural.

### Deferred (v2)

- Default-Team sweep beyond Bug Hunt.
- Cheap mock smoke gate in normal CI; nightly quota-heavy suites.
- `alln serve` ownership for overnight batches.
- Per-user / scope-keyed champions (axis reserved; unwired).
- `alln dev team-lab` Swift wrapper (rejected as v1; Python harness is canonical).

## Works Test

End-to-end, no app:

```text
Given the Mac app is closed
And `alln` is on PATH (or ALLN_BIN points at a built binary)
When the factory runs one Bug Hunt benchmark case through the CLI
Then it creates a real run
And logs every CLI request/response envelope (and stream events when used)
And retrieves team result + Floor artifacts
And records worker/writer truth facts
And produces a batch report
And any missing CLI/run truth is surfaced as a product bug, not hidden
```

## Done When (v1)

- Team Lab Run Factory runs at least one benchmark case without the Mac app,
  pure CLI (`fsBypass=false`), no MCP process.
- Every run has a complete local lab record under `.lab/`.
- Worker prompts and outputs are retrievable via CLI envelopes.
- Timed-out/failed workers are visible, not hidden.
- Run-contract truth is checked separately from Team quality; P0/P1 failures
  withhold Team quality judgment. SUB-1/SUB-2 remain explicit withholds.
- **Outcome Anchors:** ≥1 frozen case with decisive fact F; a packet naming F
  must beat one missing F — if judges invert that ordering, judges fail
  calibration and shipping stops.
- Spec Review / Bug Hunt dogfood completes with `runContractScore >= 0.95` and
  honest judge / compare records on pinned judges.
- Corpus retention is on before live quality rounds.
- Promotion remains human-gated until anchors are green.
- Bug Hunt has a baseline on 2–3 known regressions and at least one proven
  improvement that does not invert anchors.
- Any CLI contract gaps found by the lab have Debugger packets and either fixes or
  explicit blockers.
- The app remains only a presenter; it is not part of the lab's proof path.

Deferred to v2: default-Team sweep, full regression gates, `alln serve` ownership,
`alln dev team-lab` Swift wrapper, per-user scope wiring.

## Contrarian Dissent (preserved)

Spec Review (2026-07-16) preserved this dissent in substance:

The Contrarian would **cut live judges and `scenario.py` from v1 entirely**,
shipping only a Contract Regression Oracle (frozen suite + `decisiveFacts[]`)
and re-introducing judges only if oracles fail to discriminate gold packets from
eloquent-wrong packets on the three repo regressions.

**Falsification test (binds the Option C compromise):** if decisive-fact oracles
discriminate cleanly on the frozen anchor suite **and** live judges add no
separation beyond the oracle, **the judge tax dies** — switch to oracle-primary
and drop dual-judge cost from the micro loop. Slice 4 (frozen suite + one
outcome-anchored case) produces the evidence that settles this. Do not re-litigate
the diagnosis without that evidence.

## Open Questions

Resolved by this packet (do not re-open without new evidence):

- Lab storage → **`.lab/`** only.
- Judge families → **pinned** Claude-family + OpenAI/Codex-family; re-baseline on
  version change.
- Async ownership → **subprocess v1**; `alln serve` is v2.

Still open:

- What is the minimum benchmark count before changing a built-in Team?
- Should `alln floor show` be enough for artifact retrieval, or do we need a
  dedicated `alln run artifact get` verb?
- Should selected sanitized reports be committed under `docs/team-lab/reports/`?

## Review ledger (2026-07-16)

Accepted gems (source seat):

| Gem | Source |
| --- | --- |
| Outcome-verifiable cases as hard Done When bar; judges under test if they invert | First Principles; Contrarian (`decisiveFacts[]`) |
| Retain burnt inputs + both arms + verdicts as permanent regression corpus | First Principles |
| Fix CLI-Only allowlist to plural `teams *` / `skills *`; warn `team show` vs `teams show` | First Principles; Contract Auditor; Doc Hygiene |
| Genesis re-baseline on **judge-version change**, not "periodically" | First Principles |
| Depth rename as blocking PRE-S0; artifact rot around `code_bug_hunt_lite` | Proof Planner; First Principles |
| Re-base as mechanical transport swap with MCP→CLI acceptance matrix | First Principles; Contract Auditor |
| Banking per-role; promotion blocked by deliverable regression (prose matches `promote.py`) | Contract Auditor; Proof Planner |
| Evidence packet held constant across arms | Outside Scout |
| Option C — Oracle-anchored Run Factory (oracles Done When; judges retained; human-gated ship) | Synthesis / PM |
| Contrarian falsification test preserved (if oracles discriminate and judges add nothing, judge tax dies) | Contrarian |
| Storage fiat `.lab/`; verb hygiene; suite historical provenance; scoringSource writer-first; Lab Budget | Doc Hygiene |
| Contract gaps folded into PRE-S0 (lab_* seed, overlay round-trip, catalog refresh, SUB-1/2, async pin) | Contract Auditor |

### Rejects (do not re-litigate)

| Reject | Why |
| --- | --- |
| "No CLI catalog write path exists" → Debugger packet (Outside Scout's headline hole) | Falsified. `teams duplicate` → real team → `teams delete` round-tripped live. The scout reasoned from the abbreviated `alln --help`, which omits these verbs. It's a re-base task, not a product gap. |
| Resurrecting MCP "temporarily" | Nothing to resurrect — `MCPServer.swift` and the `mcp` verb are gone from source. `alln mcp serve --stdio` returns `unknown command`. |
| Greenfield rewrite of LAB-S00–S04 | 8k lines exist; only the transport is wrong. |
| Numeric quality band tables as a lab artifact | Sits far from "there is no deterministic quality score." Someone will implement `teamQualityScore = 8.2` and be textually correct. Keep `4/10 → 9/10` as founder narrative in Intent only. |
| `expectedQualities` in the machine case schema | A keyword-scoring surface aimed at a loop that just deleted keyword scoring. Demote to human notes. |
| Design/Copy/Signal/Code-planning rubrics in v1 | ~50 lines of guidance for lanes the default-team sweep explicitly defers. |
| Reduced Team / Phase-Split inside Bug Hunt First | Roster changes are the composition packet's macro loop, not a prompt A/B. |
| Per-user learning in v1 | Right instinct, wrong slice. Reserve the scope axis in the champion key; don't wire it. |
| Importing SWE-bench/Arena-class public benchmarks as v1 SSOT | Wrong surface — the product is the `alln` contract over Allnighter teams. |
| `alln dev team-lab` Swift wrapper | Wrapper on a broken wire. |
| 40-bullet Logging Requirements as v1 acceptance | Keep contract-critical + spawn/failure taxonomy; the rest is polish. |
| Contrarian's full deferral of live judges and `scenario.py` in v1 | Diagnosis right; amputation too broad — Option C anchors judges instead of killing them (falsification test preserved above). |
