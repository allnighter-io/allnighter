# MCP Run Factory and Team Lab

Status: Draft feature packet
Owner: Founder + Shared Core + CLI/MCP + Team Quality
Updated: 2026-06-21

## Founder Intent

Allnighter says MCP first. That means the fastest path to better Teams is not
more app clicking. It is to run Allnighter through the same agent-facing MCP
surface we expect OpenClaw, Hermes, Codex, Claude, and other agents to use.

The goal is to make every default Team measurably excellent:

```text
default Team starts as 4/10
-> MCP-only factory runs many cases
-> every worker, prompt, artifact, timeout, and result is logged
-> run-contract checks prove whether the run told the truth
-> blind A/B judges compare candidate output against the champion
-> team shape / prompts / model routing improve
-> fresh comparable inputs prove the Team is actually getting better
```

This is product dogfooding at the contract layer. The Mac app is not in the
loop. If the factory discovers MCP, run-journal, artifact, prompt, or status
bugs, those bugs are fixed before the Team quality conclusions are trusted.

## Product Value

Great default Teams are the product. A user should not need to understand which
worker was useful, which model timed out, or whether the writer averaged a bad
majority. Allnighter should learn that internally and ship better lineups.

The Team Lab turns subjective Team tuning into an experimental loop:

- benchmark cases instead of one-off anecdotes;
- MCP request/response transcripts instead of GUI state;
- per-worker blind comparison instead of only final-answer taste;
- run-system bug capture instead of silent harness failure;
- before/after proof when prompts, roles, writers, or model routing change.

The product promise:

```text
Every default Team earns its seat.
```

## Trusted Workflow Slice

Primary slice:

```text
developer starts MCP Run Factory
-> factory launches or connects to `alln mcp serve --stdio`
-> factory calls `mcp_hello`
-> factory selects a benchmark suite and Team
-> factory calls `team_preflight`
-> factory calls `team_start` with an idempotency key
-> factory polls `team_status`
-> factory fetches `team_result`
-> factory fetches Floor/artifact views through MCP
-> factory writes a complete local lab record
-> truth evaluator gates MCP/run-system health
-> blind judges compare workers and writer against the champion
-> batch report recommends Team changes or substrate fixes
```

Bug-stop slice:

```text
factory cannot retrieve prompt/artifact/status truth through MCP
-> mark experiment blocked
-> create Debugger packet
-> fix MCP/run contract
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

- `alln mcp serve --stdio` exposes the agent-facing MCP server.
- MCP dispatch includes `mcp_hello`, `team_preflight`, `team_start`,
  `team_status`, `team_result`, `team_cancel`, `team_run`, `floor_show`,
  `help_search`, `help_get`, Project tools, Pending tools, and stalled-work
  tools.
- `AsyncTeamService` starts MCP-origin team runs, writes a durable run journal,
  persists progress, and returns `TeamStartResponse`.
- `RunStore` persists `run.json`, `bundle.md`, worker prompts, worker answers,
  stage artifacts, return artifacts, and metadata.
- `TeamRunJSON` and Floor projections are the machine-readable run result
  contracts.
- `TeamCatalog` and `SkillCatalog` own default Team and Skill definitions.
- `docs/phases/Agent_First_MCP_And_Messaging_Workflows.md` already states the
  intended headless flow: `team_preflight -> team_start -> team_status ->
  team_result`.

Landed in v1 harness (2026-06-21 dogfood):

- `scripts/team_lab/` MCP-only factory (`run.py`, `evaluate.py`, `scoring.py`).
- `team_status` carries `workersDone` / `workersTotal` and `nextPollAfterMs`.
- `team_result(detail=full)` embeds worker prompt snapshots and answer markdown.
- `floor_show` / `spec_get` accept the canonical `run` argument.
- MCP-first scoring with `fsBypass` gate and team-quality withholding.
- Local scratch records: `REPO/.lab/<experiment-id>/`.

Known gaps still open:

- No Bug Hunt regression benchmark suite with seeded known failures yet.
- Live two-judge CLI path still needs validation; mock judges only prove orchestration.
- `alln dev team-lab` Swift wrapper not built (Python is canonical v1).
- Stage artifact inline retrieval may still require FS diff-oracle.
- Async run ownership still depends on a living process. MCP stdio can own a run
  while connected; durable overnight use should route through resident
  `alln serve` when that coordinator is the owner.
- Team admission can fail before model work if the MCP process cannot create or
  lock Allnighter's support-path governor slots. This must be reported as slot
  store unavailable, not as a fake "busy" capacity state.
- Readiness cache can lie when the factory runs under a different host,
  sandbox, support root, shell, or credential scope than the detector that wrote
  `SetupStore`. For lab purposes, "ready" means runnable by this MCP process,
  not merely present in an old cache.

## Confirmed Substrate Bugs (Bug Hunt baseline r1, 2026-06-21)

Found by the lab, owned by `AllnighterCore`. The lab now gates on what it can
detect; these are for the substrate dev. Fix before any team-quality number from
an affected run is interpreted.

| ID | Severity | Truth | Owner (file:line) |
| --- | --- | --- | --- |
| SUB-1 | P2 | `teamRun.completedAt` is `run.workerAnswers.compactMap(\.finishedAt).max()` — the last **answer** worker's finish, stamped *before* synthesis. Run completion must be after the plan/synthesis stage finishes. | `TeamRunJSONMapper.swift:74-86` |
| SUB-2 | P2 | `team_result.stages[]` (`StageInfo`) omits `markdown`, `startedAt`, `finishedAt`; `plan.status` is hard-coded `.done`. Stage payload/timestamps exist internally but are not projected, so the lab cannot independently verify completion ordering (SUB-1) over MCP. | `TeamRunJSON.swift:184-194`, `TeamRunJSONMapper.swift:168-180` |
| SUB-3 | P3 | `workerAnswers[].finishedAt` is not serialized (only `durationMs`, `markdown`, `modelId`, `status`, `workerId`). Serialize it so completion ordering is checkable from the MCP payload. | `TeamRunJSONMapper.swift` worker-answer mapping |
| SUB-4 | P3 | `floor_show.summaryMarkdown` is empty (0 chars) on a completed run; the packet body is only in `team_result.plan.markdown`. Either populate the floor summary or document it as never the packet source. | `FloorProjector` / floor projection |

Note on the earlier "writer shows `queued` / all worker status null" report: `workers[]`
metadata does **not** carry `status` by design (`TeamRunJSON.WorkerInfo`,
`TeamRunJSON.swift:149-165`). Terminal status for answer/review workers lives in
`workerAnswers[].status` (all `done` in the baseline). Writer status is only
representable via `plan.status`. The lab's `mcp_worker_status` check asserts every
non-plan worker has a `workerAnswers` status and that writer status is present.

## First-Principles Decision

The Team Lab is not a GUI QA harness. It is an MCP contract pressure test plus a
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
| MCP tool names, args, errors, schemas | `ContractRegistry` projected to generated MCP descriptors |
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
- A GUI-visible result can mask MCP contract gaps.
- A majority theory can be weaker than a minority dissent.
- A cheap final score can flatten root-cause, evidence, proof, and usefulness
  into one misleading number.
- An empty lab support root can make readiness look optimistic unless the
  factory treats missing detection as unknown and runs doctor/preflight truth
  checks first.
- A provider CLI can be "ready" in the Mac app but fail from an MCP subprocess
  because auth/session stores are unavailable to that process.

## MCP-Only Law

The factory must create, control, and retrieve runs only through MCP.

Allowed:

```text
spawn/connect: alln mcp serve --stdio
call: initialize
call: tools/list
call: mcp_hello
call: help_search / help_get
call: teams_list / teams_show
call: team_preflight
call: team_start
call: team_status
call: team_result
call: team_cancel
call: floor_show
call: spec_get / export-style tools when available
call: doctor / error_explain when blocked
```

Not allowed:

```text
start the Mac app
use SwiftUI/AppModel as an oracle
import AllnighterCore into the factory
call TeamService or RunStore directly for run creation
patch run files by hand
infer missing MCP truth from app-only behavior
```

Artifact capture rule:

```text
MCP is the retrieval owner.
```

If the lab cannot retrieve worker prompts, worker answers, stage outputs, Floor
data, or final packets through MCP-returned structures or MCP artifact tools, the
answer is not "read the app state." The answer is "add the missing MCP retrieval
surface."

Final packet retrieval rule (pinned 2026-06-21):

```text
Canonical packet body  = team_result(detail=full).plan.markdown
Answer/review bodies    = team_result(detail=full).workerAnswers[].markdown
Worker prompt snapshots = team_result(detail=full).workers[].resolvedWorkerPromptSnapshot
Terminal worker status  = workerAnswers[].status (answer/review); plan.status (writer)
floor_show.summaryMarkdown is NOT the packet source (empty on completed runs — SUB-4).
```

The harness reads the packet from `team_result`, never from `floor_show` text or
the copied journal. The journal copy under `.lab/<exp>/run/` stays diff-oracle only.

Support-root rule:

```text
The factory records the exact Allnighter support root used by the MCP server.
If the root is overridden for eval/sandbox work, the run record says so.
No experiment may compare results from two support roots as if they shared
readiness, idempotency, run history, or source credentials.
```

Admission truth rule:

```text
TEAM_GOVERNOR_BUSY = slots are actually locked by live team work.
TEAM_GOVERNOR_UNAVAILABLE = the MCP process cannot create/open/lock the slot store.
```

The factory must stop on `TEAM_GOVERNOR_UNAVAILABLE`, call `error_explain` or
`doctor`, and classify the experiment as a run-system issue. It must not retry as
if waiting would free capacity.

## CLI/MCP Surface

The lab itself is a development and product-quality tool. V1 can be implemented
as a repo tool that speaks MCP over stdio. If productized, it must expose a
dev-facing CLI surface without bypassing MCP.

Proposed dev CLI:

```bash
alln dev team-lab suites --json
alln dev team-lab run --suite <suite-id> --team <team-id> [--case <case-id>] --json
alln dev team-lab report <experiment-id> --json
alln dev team-lab compare <baseline-id> <candidate-id> --json
```

Important implementation rule:

```text
`alln dev team-lab run` launches/connects to `alln mcp serve --stdio` and uses
JSON-RPC tools. It does not call Core/Engine run APIs directly.
```

No new public MCP tool is required for S00-S04 because the lab is testing the
existing MCP tool surface. Add new MCP tools only when a real retrieval or
artifact gap is found, such as:

```text
run_artifact_get
run_transcript_get
lab_report_get
```

Those tools must be registry-backed, schema-backed, and parity-tested before the
factory depends on them.

## Experiment Record

Every case run creates one local immutable lab record.

Suggested path:

```text
~/Library/Application Support/Allnighter/Labs/<experiment-id>/
  experiment.json
  mcp-transcript.jsonl
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
  "mcpServer": {
    "command": "alln mcp serve --stdio",
    "protocolVersion": "2024-11-05",
    "toolsListHash": "sha256:..."
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
  "expectedQualities": [
    "classifies repeated bug as T3",
    "inspects current diff before root-cause confidence",
    "preserves dissent",
    "rejects weak majority theories with evidence",
    "names missing proof"
  ],
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

- exact MCP JSON-RPC frames, request and response, with timestamps;
- `tools/list` result and hash;
- `mcp_hello` readiness result;
- Allnighter support root, relevant MCP process environment, and whether the
  support root was overridden for lab/sandbox execution;
- first-start facts: binary path, binary version, git head, contract hash,
  support root, current working directory, PATH source, process pid, and MCP
  client identity;
- `team_preflight` result;
- `team_start` request and `TeamStartResponse`;
- every `team_status` response and polling interval;
- `team_result` response, including not-ready envelopes;
- Floor/artifact retrieval responses;
- all error envelopes and `error_explain` output when used;
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
- run-store artifact refs returned through MCP;
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
MCP retrieval failed
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
1. Pick a FRESH input (scenario.py); run champion and candidate on that SAME input.
2. BLIND output A/B: each judge sees only the two outputs (anonymized, order seeded),
   never the prompts, model names, or which side is the candidate.
3. Per WORKER: two different-family judges each pick A/B/tie. Bank the candidate's
   prompt for that role iff BOTH pick the candidate. Tie/split/baseline -> incumbent.
4. DELIVERABLE A/B (same blind method): the unit of suspicion. If a worker was banked
   but the deliverable regressed, raise an interaction warning — do NOT unbank.
5. Un-blind: the idea-engine reads the prompt diffs + verdicts and proposes the next
   single-variable changes. It is NON-VOTING — it never decides keep/discard.
6. Burn the input. Next round uses a new one.
```

Why this is more valid than judging prompts: the prompt is the method, the output
is the result. A prompt that looks ridiculous but whose output two blind judges
prefer, repeatedly, on fresh inputs, is working. Optimize for results.

Roles:

| Thing | Role | Decides? |
| --- | --- | --- |
| Per-worker blind A/B | unit of optimization — bank each role independently | YES (unanimous) |
| Deliverable blind A/B | unit of suspicion — audit for interaction regressions | No (audit only) |
| Idea-engine (un-blind) | propose next-round single-variable changes | No (advisory) |
| Run contract (deterministic) | truth gate — may the run even be judged | Gate |

Bias controls (the reason this is run in orchestration/isolation):

- Two **different model families**; same model twice is a correlated echo, not a vote.
- **Isolated, parallel, sealed** verdicts — no judge sees another's before committing.
- **Blind + order-seeded** — the judge cannot tell which output is the new one.
- **Incumbent wins ties** — the `AND` gate trades false-negatives for near-zero
  false-positives; correct asymmetry for editing production prompts.
- **Don't let a model judge its own family's output** as a deciding vote.
- The input generator must not be the same model that judges that round.

Honest limit: judges evaluate **artifacts, not outcomes**. Two judges preferring a
packet is shared taste, not proof the diagnosis is right. Seed a few **verifiable
cases** (known bug, known kill-test) to confirm "judges' better" tracks reality.

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

### Autopromote policy (no founder gate for routine wins)

The lab promotes champions from compare evidence automatically. Founder review is
async — the loop never stops to wait.

**Promote when** (`promote.py` gate): `judgeMode=live`, `evidenceValid=true`,
`sameInput=true`, `interactionWarning=false`, no unmatched roles, `bankedRoles`
non-empty, `championConfigHash != candidateConfigHash` (material candidate delta),
and `deliverableOutcome` is `candidate` (or a narrow tie with few banks).

**HOLD** when: `championConfigHash == candidateConfigHash` → `no material candidate delta`.
R3-style identical-config rounds are automation smoke, not quality improvement.

**Escalate (exit non-zero, no promote)** when: judges split repeatedly on
deliverable while many roles bank; deliverable regresses to baseline; run-contract
not green; mock judges; structural role mismatch; model/source failures make
evidence suspect; overlay declares template changes but MCP cannot wire lab skills
into team rows; or the change would touch privacy, credentials, billing,
destructive actions, or distribution.

**Quality rounds** (`advance.py`): require `--hypotheses-from` or `--candidate-overlay`
so the candidate arm differs (hypothesis patch, skill fork, etc.). Use
`--calibration-smoke` only for automation calibration (skips promotion).

**MCP**: `teams_definition` returns full `TeamPreset` JSON round-trippable through
`teams_save`. `teams_show` remains summary-only.

**SkillCatalog shipping**: after enough clean fresh-input wins with material deltas,
`promote.py` writes a reviewable patch under `docs/team-lab/patches/` (only roles
whose template differs from built-in). Not hand-picked by founder.

Champion overlay: `docs/team-lab/champions/<suite>/<team>.json` — banked role
provenance + templates. `run.py --champion-overlay` deploys a lab team via MCP
before `team_start`.

## Evaluation Rubrics

Only the **Run Contract Score** below is deterministic (it measures truth). The
Worker / Writer / Team Quality criteria are **judge guidance for the blind A/B in
the Judge Loop** — things a judge should weigh — NOT checklists that produce a
score. Do not turn them back into deterministic counts.

### Run Contract Score

Measures whether Allnighter told the truth:

- preflight blocked bad runs before quota;
- `team_start` returned a run id only after journal creation;
- status changed honestly;
- polling cadence was respected;
- terminal state matched artifacts;
- every assigned answer/review worker had a visible terminal status in
  `workerAnswers[].status`, and writer status was present (`mcp_worker_status`
  check: `statusedAnswerCount == nonPlanWorkerCount` and `writerStatusPresent`);
  a dropped/hidden worker fails this check and withholds team quality;
- failed/timed-out workers were not hidden;
- prompts and outputs were retrievable;
- writer/stage outputs were retrievable;
- `TeamRunJSON` matched Floor/artifact truth;
- idempotency behaved correctly;
- interrupted/orphaned runs recovered honestly;
- MCP schemas matched generated contract docs.

### Worker Score

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

### Writer Score

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

### Team Quality Score

Measures the final result against the Team's job.

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

Code planning:

- scopes the slice tightly;
- matches repo architecture;
- names truth owners;
- identifies risks;
- sequences implementation;
- names proof;
- avoids broad cleanup.

Design:

- critiques the actual surface;
- honors the design system;
- distinguishes taste, usability, and implementation constraints;
- gives concrete revisions;
- requires visual proof when needed.

Copy:

- fits audience and brand voice;
- improves specificity;
- preserves factual constraints;
- produces usable final copy;
- avoids generic marketing filler.

Signal:

- uses source-labeled receipts;
- separates observation from inference;
- assesses freshness;
- produces actionable insight;
- avoids unsupported trend claims.

## Score Bands

```text
0-3  unusable or misleading
4    useful fragments, unsafe to trust
5-6  helpful but inconsistent
7    good enough with expert review
8    strong, with visible remaining gaps
9    excellent default Team behavior
10   reserved for narrow benchmark perfection
```

The target for default Teams is not a perfect 10. The target is repeatable 9/10
behavior on the benchmark suite, with known residual risks named.

## Default Team Calibration Loop

For each default Team:

1. Run baseline suite.
2. Produce per-case and batch reports.
3. Identify weak roles, missing roles, prompt failures, model-routing failures,
   writer failures, and MCP/run-system bugs.
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

Initial Bug Hunt experiments:

| Experiment | Variable |
| --- | --- |
| Baseline | current built-in Bug Hunt |
| Evidence Packet | add MCP-collected `git status`, diff, logs, prior attempts before workers |
| Reduced Team | keep Reproducer, Truth Owner, Trace, Regression, Contrarian, Writer |
| Phase-Split | run Correct Fix Planner and Change Impact only after root-cause ranking |
| Model Routing | reserve Opus for Contrarian + Writer, use faster code-local workers for answer roles |
| Discriminator Role | add explicit cheap-test splitter |
| Writer Contract | require rank/reject/dissent/next-observation fields |
| Typed Return | require `BugPacket`/`FixPacket` eligibility fields |

## Lab model policy

**SSOT:** `scripts/team_lab/model_policy.py` — applied on every lab experiment via
`overlay.ensure_model_policy_team` unless `ALLN_LAB_MODEL_POLICY=0`.

**Do not use Antigravity / Gemini (`model_gemini`, `model_gemini_pro`, any
`model_agy_*`) on lab worker seats.** Product teams may still roster those
drivers; the lab excludes them after R6 (wrong-cwd fixed in product; agy still
hit wall-clock / vendor timeouts and poisoned contract scores). Re-add only with
an explicit policy change in `model_policy.py` plus a green calibration round —
not ad-hoc overlay overrides.

| Seat class | Allowed |
| --- | --- |
| Lead / synthesis / writer | `model_opus` only |
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
factory should be able to create a shared evidence packet before workers start.

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
| P0 | MCP cannot start a run, loses run id, corrupts result | Stop batch, Debugger packet, fix before continuing |
| P1 | Worker failure hidden, prompt missing, status lies, artifact unreachable | Stop affected suite, fix retrieval/status contract |
| P1 | `fsBypass=true` (scoring relied on copied journal, not pure MCP) | Team quality judgment **withheld**; fix MCP retrieval or harness |
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
- Redact secrets in MCP transcripts and exported reports.
- Keep raw run logs local by default.
- Mark suites that contain private source code.
- Record which models/sources were invoked.
- Respect the same entitlement, source, and mutating gates as normal MCP runs.
- Never let an evaluator mutate a repo unless routed through an execution Team
  with the normal write lock and approval semantics.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Final packet -> worker quality | Team Lab evaluator | Good final answer means all workers worked | Score workers independently | Batch with good final output and timed-out workers still flags worker failures |
| GUI run -> MCP readiness | MCP contract | App can run it, so MCP can run it | Lab must use MCP only | Harness test fails if Core/App APIs are imported |
| `completed` status -> complete artifacts | RunStore/Floor | Terminal run means prompts and outputs are retrievable | Artifact completeness is separate | Completed fixture missing worker prompt fails run-contract score |
| Majority agreement -> correctness | Writer/evaluator | More workers said it, so it wins | Writer must rank evidence, not votes | Case where minority has decisive diff evidence must score majority-following writer low |
| Human taste -> benchmark proof | Team Lab rubric | Founder liked one answer, so Team is fixed | Keep human notes separate from scores | Report schema separates `humanNotes` from rubric fields |
| MCP gap -> local file workaround | MCP contract | Just read the file directly | Add/revise MCP retrieval surface | Harness marks direct run-store read as contract violation unless from MCP artifact ref |

| MCP gap -> local file workaround | MCP contract | Just read the file directly | FS copy is diff-oracle only; scoring must use MCP payloads | Harness `pure_mcp_scoring` fails when `fsBypass=true`; team quality withheld |

## Measurement Validity (v1)

The `4/10 -> 9/10` headline is aspiration until these rules bind:

- Run-contract lane must be green (`fsBypass=false`, `runContractScore >= 0.95`) before
  any Team-quality judgment is interpreted.
- Compare **logical workers once** (not duplicate artifact paths).
- Fresh inputs across rounds; within one round both arms must share the exact same input.
- Built-in Team mutations require **>= 3 clean live compare rounds** on fresh inputs
  with live judge preference and no run-contract regression.
- Writer consistency: discard worker claims contradicted by `experiment.json` and
  run-contract artifacts.

There is **no deterministic quality score** (removed 2026-06-21 — see § Judge Loop).
Keyword/structure scoring rewarded the template words the prompts already mandate
(Goodhart), so it optimized for theater. Quality is decided only by the two-judge
blind A/B in `compare.py`. What stays deterministic is **truth**: the run-contract
lane and the worker "did it return content" / writer-consistency checks, with their
own kill tests (`test_scoring.py`, `test_judge.py`).

## Experiment Design (v1)

No team mutation is proposed without a pre-registered design. Each calibration
experiment declares, before running:

```text
Hypothesis:        one sentence; what the change should improve and why.
Changed variable:  one OR MORE worker prompts. Per-worker blind A/B gives clean
                   per-role attribution, so you are NOT limited to one variable for
                   role-local prompt changes — change several, see which banked.
                   (Structural changes — add/remove a worker — break 1:1 role
                   mapping and fall back to the deliverable A/B.)
Input discipline:  WITHIN a round both arms run the SAME input. BETWEEN rounds the
                   input is FRESH and never reused (scenario.py + burn ledger).
                   Reusing one input across rounds is overfitting (the Spec Upgrade
                   mistake). Power comes from input DIVERSITY across rounds.
                   compare.py refuses sameInput=false.
N:                 1 run per arm per round is acceptable — a test of 1 beats a test
                   of 0, and diversity across rounds accumulates the signal. Replay
                   the same input >=3x only to MEASURE variance, never to claim a win.
Decision rule:     bank a worker's candidate prompt iff BOTH blind judges pick the
                   candidate for that role; any tie/split/baseline keeps incumbent.
                   The deliverable A/B AUDITS (interaction warning) but never vetoes
                   a clean per-worker win. No deterministic score decides anything.
Mock rule:         --mock validates orchestration only. Mock compare records are marked
                   evidenceValid=false and must never support a Team mutation.
Transfer guard:    a banked change must keep winning on FRESH inputs over rounds;
                   re-baseline periodically against GENESIS (not just last champion)
                   to catch slow drift, and re-challenge banked workers occasionally.
Negative results:  recorded, not discarded.
```

The two judges are different model families, pinned + version-stamped, run in
isolation. See § Judge Loop for the full mechanism.

## Implementation Slices

**Full Slice 1 execution spec (whole v1 package + good-to-great roadmap):**
[`Team_Lab_Slice_1_Full_Package.md`](Team_Lab_Slice_1_Full_Package.md)

### PRE-S0 - Pure-MCP Reconstruction Proof (blocking)

Before LAB-S03+ truth and compare records are trusted:

```text
team_result(detail=full) returns worker prompt snapshots + answer markdown + plan
floor_show({runId}) returns the requested run (not latest-by-accident)
journal copy under .lab/run/ is diff-oracle only — zero score weight
fsBypass=false and runContractScore >= 0.95
```

Proof:

```bash
python3 scripts/team_lab/run.py --suite spec_upgrade_mcp_lab_v1 --round 1 --variant baseline
python3 scripts/team_lab/evaluate.py .lab/<experiment-dir> --rescore-contract
# expect: pure_mcp_scoring ok, team quality not withheld
```

### LAB-S00 - Lab Constitution and Fixtures

- Add this phase doc.
- Define suite/case/rubric JSON shapes.
- Add one tiny synthetic suite and one Bug Hunt dogfood suite definition.
- Decide local storage path and redaction rules.

Proof:

```bash
python3 scripts/team_lab/run.py --suite smoke_mcp_v1 --round 1
# planned: alln dev team-lab suites --json
```

### LAB-S01 - MCP Transcript Harness

- Build a small harness that spawns `alln mcp serve --stdio`.
- Implement JSON-RPC initialize, `tools/list`, and `mcp_hello`.
- Write raw transcript JSONL.
- Hash tools list.
- Fail if required MCP tools are absent.

Proof:

```bash
python3 scripts/team_lab/run.py --suite smoke_mcp_v1 --case hello --round 1
# planned: alln dev team-lab run --suite smoke_mcp_v1 --case hello --json
```

### LAB-S02 - Run Factory Driver

- Add `team_preflight`, `team_start`, `team_status`, `team_result`, and
  `team_cancel` calls.
- Generate idempotency keys.
- Respect `nextPollAfterMs`.
- Record every status response.
- Mark timeout/cancel/interrupted honestly.

Proof:

```bash
python3 scripts/team_lab/run.py --suite smoke_team_start_v1 --team code_bug_hunt --round 1
```

### LAB-S03 - Artifact Collector

- Retrieve Floor and artifact refs through MCP.
- Persist worker prompts, worker answers, stage outputs, final packet, and
  metadata into lab record.
- If any required artifact cannot be reached through MCP, emit a P1 run-contract
  bug and block Team scoring.

Proof:

```bash
python3 scripts/team_lab/evaluate.py .lab/<experiment-dir> --rescore-contract
ls .lab/<experiment-dir>/evaluation/
```

### LAB-S04 - Evaluator and Report Model

- Deterministic run-contract checks (`evaluation/run-contract-score.json`).
- Deterministic worker facts only (`evaluation/worker-facts.json`): content present,
  writer present, writer consistency. No quality score.
- Blind A/B compare records (`evaluation/compare-record.json`, `compare.md`).
- Persist evaluator record (`evaluation/evaluator-record.json`).
- Writer consistency check against `experiment.json`.
- Produce `report.md`.

Proof:

```bash
python3 scripts/team_lab/evaluate.py .lab/<experiment-dir>
python3 scripts/team_lab/compare.py <baseline> <candidate> --mock
# planned: alln dev team-lab compare <baseline> <candidate> --json
```

### LAB-S05 - Bug Hunt Calibration

- Create Bug Hunt benchmark suite from known Allnighter regressions.
- Run current Bug Hunt baseline.
- Test evidence packet, reduced lineup, phase-split planner, model routing, and
  writer contract variants.
- Update `TeamCatalog`/`SkillCatalog` only after repeated wins.

Proof:

```bash
python3 scripts/team_lab/run.py --suite bug_hunt_repo_regressions_v1 --team code_bug_hunt --round 1
```

### LAB-S06 - Default Team Sweep (deferred v2)

Deferred until one Team (Bug Hunt) proves the loop with `fsBypass=false` and
repeatable live judge wins on fresh inputs. Do not sweep all built-in Teams before that.

### LAB-S07 - Regression Gates (deferred v2)

- Add a cheap MCP smoke gate that runs in normal checks without spending real
  quota, using mock/fake workers where possible.
- Keep quota-heavy benchmark suites manual or nightly.
- Gate generated MCP schema drift.
- Gate artifact completeness.

Proof:

```bash
swift test --filter MCPAsyncTeamTests
alln dev team-lab run --suite smoke_mcp_mock_v1 --json
```

## Works Test

End-to-end, no app:

```text
Given the Mac app is closed
And `alln mcp serve --stdio` is reachable
When the factory runs one Bug Hunt benchmark case through MCP
Then it creates a real run
And logs every MCP request/response
And retrieves team result + Floor artifacts
And records worker/writer truth facts
And produces a batch report
And any missing MCP/run truth is surfaced as a product bug, not hidden
```

## Done When (v1)

- MCP Run Factory runs at least one benchmark case without the Mac app.
- Every run has a complete local lab record under `.lab/`.
- Worker prompts and outputs are retrievable via MCP (`fsBypass=false`).
- Timed-out/failed workers are visible, not hidden.
- Run-contract truth is checked separately from Team quality; P0/P1 failures
  withhold Team quality judgment.
- Spec Upgrade self-dogfood completes with `runContractScore >= 0.95` and honest
  judge-pending / compare records.
- Bug Hunt has a baseline on 2–3 known regressions and at least one proven
  improvement.

Deferred to v2: default-Team sweep (LAB-S06), full regression gates (LAB-S07),
`alln dev team-lab` Swift wrapper.
- Any MCP gaps found by the lab have Debugger packets and either fixes or
  explicit blockers.
- The app remains only a presenter; it is not part of the lab's proof path.

## Open Questions

- Should lab records live only in Application Support, or should selected
  sanitized reports be committed under `docs/team-lab/reports/`?
- Which live judge model families should be pinned for comparison consistency?
- What is the minimum benchmark count before changing a built-in Team?
- Should `floor_show` be enough for artifact retrieval, or do we need a
  dedicated `run_artifact_get` MCP tool?
- Should long-running factory batches require resident `alln serve`, or is MCP
  stdio ownership sufficient for v1 manual experiments?
