# CODE RED — Core Infrastructure Repair

Status: **CODE RED — ACTIVE. Blocks all forward feature work and all claims that
resident-backed Team execution is fixed.**
Owner: AllnighterCore + CLI execution path
Updated: 2026-07-24

## Authority and precedence

This is the binding recovery document for the current execution failure.

Until this phase closes, it supersedes:

- the mechanical read-only requirement for answer Teams in
  `Unified_Run_Model.md`;
- the project-mirror / protected-project-byte direction in
  `Resident_Execution_Broker.md` CPH-3;
- any current code, help, test, or phase status that implies a verified mirror
  is equivalent to the registered repository;
- any claim that matching release or contract numbers make different source
  builds safe to mix;
- any developer closeout that says “should work,” “tests pass,” or “fixed”
  without the Works Tests in this document.

This document does **not** authorize destructive rollback, history rewriting,
permission changes, moving repositories, killing live user work, or deleting
user data. Those remain explicit human stops.

## Code Red order

Stop expanding the current architecture.

1. Freeze forward Mac, iOS, Panel, Pending, doctor, background-lifecycle, and
   new-source work that touches the execution path.
2. Do not add another mirror, snapshot, compatibility bridge, fallback,
   transport, lifecycle state, or permission workaround.
3. Recover one direct, real-repository Team path before repairing any adjacent
   surface.
4. Delete failed infrastructure before adding replacement infrastructure.
5. A slice may not advance because unit tests are green. It advances only when
   its owner-visible Works Test is green.

The recovery must be net-negative in execution-path concepts and production
code. Any slice that adds more infrastructure than it deletes requires a
founder boundary decision before implementation continues.

## Founder intent

### Raw request

Allnighter has gone off track by turning ordinary Team research into a
mechanically read-only filesystem problem and then building mirrors, transfer,
hashing, compatibility, and permission machinery around that invented
requirement.

The intended product is:

- **Team:** ask several CLIs for research, review, judgment, or input;
- **Execution:** ask one CLI to perform the requested work in the actual
  repository.

The founder did not request project mirrors, disposable repositories, hidden
copies, or a second filesystem truth. Git and the underlying CLI provide the
normal diff, commit, and undo workflow.

### Product value

One prompt reaches the CLIs the user already pays for. Research Teams return
independent answers. Execution makes the requested change. Both happen in the
registered repository, using the same context a directly launched CLI sees.

### Trusted workflow slice

```text
registered repository
  -> alln run with a research Team
  -> two distinct authenticated CLIs read the real repository
  -> both answers return
  -> alln run with an execution Team
  -> one authenticated CLI changes the real repository
  -> the real git diff proves the change
```

### Non-goals during repair

- Mechanical read-only enforcement for research Teams.
- Project mirrors, snapshots, worktree copies, secret-filtered byte transfer,
  or a second repository representation.
- Detached execution, automatic resident installation/update, drain/restart,
  parked work, wake/resume, Panel routing, Pending routing, or doctor routing.
- Mac or iOS presentation work.
- Compatibility with stale coordinator builds.
- New transport abstractions or a general local RPC framework.
- Hiding a failed worker, permission failure, dirty-tree change, or stale
  binary behind a fallback.

## Locked product model

### 1. One repository truth

The registered canonical repository root is the working directory for every
project-scoped worker.

No production execution path may replace it with:

- a mirror;
- a snapshot;
- a scratch directory;
- a copied checkout;
- a worktree created only to simulate read-only behavior;
- a context packet presented as repository truth.

If a process cannot access the registered repository, the run fails honestly.
It must not silently run somewhere else.

### 2. Team means research and input

A non-execution Team:

- runs its selected workers against the real repository;
- asks for analysis, review, options, or judgment;
- returns each worker’s answer;
- does not promise mechanical filesystem immutability;
- does not create a separate filesystem for safety.

The Team prompt may clearly say that the task is research-only. That is worker
guidance, not a new infrastructure contract.

Allnighter records the repository’s pre-run and post-run git status. If a
research worker writes unexpectedly, Allnighter:

- reports the unexpected diff as a run violation;
- preserves the evidence;
- does not claim success;
- never silently reverts or deletes the user’s files.

Git remains owned by the repository and the user’s CLI workflow. Allnighter
does not invent another undo system.

### 3. Execution means execution

An execution Team:

- resolves to exactly one worker;
- runs that worker in the real registered repository;
- permits the worker to edit, test, and commit as requested;
- uses the existing per-root write lock to prevent concurrent Allnighter
  execution workers;
- returns the real changed paths, git diff/proof, and terminal worker result.

Success is impossible unless the requested outcome exists in the registered
repository. A change in scratch, temp, mirror, journal, or generated output is
not execution success.

### 4. One run primitive

Both shapes use the same run record and worker adapter:

```text
message + optional Team + worker selection + canonical repo root
```

The Team shape changes worker count and expected output. It does not select a
different filesystem architecture.

### 5. The broker is plumbing only

If a resident broker is required so vendor CLIs do not inherit a restricted
host’s sandbox, it may only move the typed request to a normally authorized
process. It may not change:

- repository root;
- Team membership;
- worker identity;
- prompt;
- research versus execution meaning;
- result contract.

The broker is not a repository service, snapshot service, permission
workaround, scheduler product, compatibility layer, or second run owner.

## Current-state audit

### Incident window

The 2026-07-24 repair window produced:

- 31 commits in roughly four hours;
- 55 changed files;
- 2,644 inserted lines and 178 deleted lines;
- 11 separate changes to `ResidentExecutionBroker.swift`;
- successive repairs for probe prompts, protected roots, project mirrors,
  coordinator ownership, admission, status, install recovery, and stale
  coordinator compatibility.

This is expansion under incident pressure, not convergence.

### Proven structural failures

1. Protected project requests are replaced with a mirror before the Team is
   resolved as research or execution. Execution can therefore modify a
   disposable directory instead of the registered repository.
2. The mirror omits `.git`, so it is not equivalent to the repository context
   promised by the run model.
3. Mirror capture copies all tracked bytes before resident validation, has no
   active lifecycle cleanup, and can accumulate a full repository copy per run.
4. Mirror capture waits for `git` to exit before draining its output pipe. The
   Allnighter checkout already emits more than 140 KB from `git ls-files -z`,
   so the capture path has an unproved blocking seam.
5. The compatibility path allows a new client to submit using a stale
   coordinator’s Git SHA while the human binary version remains unchanged
   across materially different builds.
6. Broker acceptance/result writes are frequently wrapped in `try?`. A worker
   can continue while the client never receives the authoritative reply.
7. Focused unit tests prove materialization, validation, and broker-adjacent
   facts. They do not spawn two real CLIs through the installed path, prove the
   real repository CWD, or prove a requested edit reaches the real repository.
8. The active resident phase still names the hostile-host/no-prompt Works Test
   as red. A “fixed” claim therefore contradicts the phase’s own proof state.

### Boundary verdict

The current resident-backed project path is **RED**. It is not eligible for
dogfood trust, release claims, or further feature layering.

### Truth owners

| Truth | Sole owner |
| --- | --- |
| Project bytes and changes | Registered repository root |
| Diff, commit, rollback | Repository Git state and the worker/user CLI |
| Team selection and shape | Resolved `TeamPreset` |
| Durable run status/result | Canonical `TeamRun` / run journal |
| Live worker ownership | The process that actually spawned the vendor CLI |
| Build freshness | Exact executable build Git SHA |

### Lie-prone layers

- mirror manifests and content hashes;
- broker receipts written after work begins;
- client-side health inferred from an identity file;
- matching human version / contract version with different source builds;
- unit tests that stop before a real vendor spawn;
- journal state presented as live process truth;
- “the request was accepted” presented as “the user workflow works.”

## Inference bans

| Junction | Owner | Forbidden inference | Required negative proof |
| --- | --- | --- | --- |
| Research prompt -> filesystem policy | Team contract | “Research” requires a copied or mechanically read-only repository | Research Team runs in the canonical root and returns answers |
| Mirror verified -> repository context | Registered root | Matching file hashes mean a mirror is the repository | Worker reports canonical `pwd`, `.git`, and HEAD from the real root |
| Broker accepted -> work succeeded | Run journal + worker result | A receipt proves a CLI ran or produced a result | Distinct vendor process receipt plus terminal answer |
| Tests green -> dogfood green | Works Test | Mock/unit coverage proves the cross-process user path | Exact founder command with two authenticated CLIs |
| Matching release -> matching code | Build identity | Same `binaryVersion`/contract means different SHAs are compatible | Mismatch fails before dispatch |
| Execution output -> repository changed | Registered root | Worker prose or temp files prove execution | Requested real-root diff and proof command |
| Unexpected Team write -> automatic cleanup | User Git state | Allnighter may silently reset research changes | Diff is surfaced; no automatic destructive action occurs |

## Recovery architecture

The target path is deliberately small:

```text
alln run
  -> resolve registered project and Team once
  -> use canonical project root once
  -> spawn selected vendor CLI(s)
  -> persist sourced worker transitions
  -> return worker answers / real execution result
```

For the first green slice:

- the caller is a normal macOS Terminal;
- execution is foreground;
- no resident broker is involved;
- two explicitly selected, authenticated CLIs are the only Team matrix;
- no Panel, synthesis chain, detach, retry substitution, or background
  lifecycle participates.

Only after that path is green may a restricted Codex client be connected to the
same executor through a thin resident handoff.

## CLI surface during Code Red

The supported recovery surface is one command:

```text
alln run "<message>" --project <id|path> --team <team-id>
```

Required behavior:

- Research Team: selected workers run and return independent answers.
- Execution Team: exactly one selected worker changes the registered repo.
- `--json` projects the same canonical Team run, worker identities, statuses,
  output, repo root, and proof facts.
- `--dry-run` resolves selection only and must say it did not execute.

Temporarily out of the trusted recovery surface:

- `--detach`;
- Panel start/round/watch;
- pending run;
- broker-routed doctor/detect;
- automatic coordinator installation/update;
- stale-build compatibility;
- background drain/re-adoption.

Existing commands outside the trusted surface must fail honestly or remain
clearly marked unverified. They may not call the recovered path “green.”

## Ordered recovery slices

No slice begins until the prior slice’s Works Test is recorded green.

### CR-S00 — Freeze and semantic cutover

- Land and route this document.
- Mark the resident/mirror direction frozen and superseded.
- Ban “fixed” language without the Code Red proof receipt.
- Make the current RED status visible in active routing.

Proof: documentation links resolve; no active router sends core-repair work
directly to the old resident plan.

### CR-S01 — Delete false repository truth

- Delete `ProjectMirror`, `ProjectMirrorPayload`, `ProjectMirrorStore`,
  `ProjectMirrorMaterializer`, `ProjectMirrorCapture`, and
  `ResidentProjectAccessBoundary`.
- Delete `projectMirrorId` from public/internal run requests.
- Delete broker `residentSafe` root substitution.
- Delete mirror-specific errors, generated contract entries, tests, temp
  directories, and help.
- Preserve unrelated user data; removal of existing temp mirrors requires an
  explicit, bounded cleanup action and must be reported.

Proof: a repository-wide sweep finds no production project-mirror execution
path; project-scoped runs either use the canonical root or fail.

### CR-S02 — Restore the direct golden path

- Restore one foreground `alln run` executor callable from normal Terminal.
- Resolve the Team and repository once.
- Spawn one real authenticated CLI in the canonical repo root.
- Keep lifecycle state minimal: accepted, running, terminal.
- Propagate every acceptance/result write error; no `try?` at the authoritative
  handoff.

Works Test: one selected CLI reads the real repo, reports canonical `pwd`, reads
HEAD through `.git`, and returns a sourced answer.

### CR-S03 — Prove the two-CLI research Team

- Run exactly two distinct authenticated CLIs from one Team.
- Preserve selected identities; no substitution or roster collapse.
- Run both against the same canonical repo root.
- Persist each worker’s actual queued/running/terminal transition and failure.
- Capture pre/post git status and surface unexpected writes.

Works Test: the founder’s exact research prompt returns two distinct answers,
both workers prove real-root context, and the run settles without hidden
failures.

### CR-S04 — Prove execution

- Resolve an execution Team to exactly one worker.
- Acquire the existing canonical-root write lock.
- Make one bounded requested edit in a disposable fixture repository.
- Run the requested proof.
- Return the actual changed path and git diff.

Works Test: the sentinel change exists in the fixture’s real working tree. A
change anywhere else fails the test.

### CR-S05 — Add the thinnest restricted-host handoff

- First build an isolation harness that proves which single local transport a
  restricted Codex client can use.
- Start the execution owner manually from a normal Terminal for dogfood.
- Route only `alln run` through it.
- Require exact build Git SHA equality.
- On mismatch or unavailable coordinator, fail with one restart action.
- Do not auto-install, auto-update, bridge, mirror, drain, or fall back.

Works Test: the same CR-S03 and CR-S04 commands originate from Codex and produce
the same real-root results with no duplicate vendor spawn.

If the normal execution owner cannot access a protected project root, stop and
report the permission boundary. Do not build a mirror. Any product permission
or repository-location decision is a separate founder-approved phase.

### CR-S06 — Delete the abandoned control plane

- Remove broker operation cases not required by the proven `alln run` path.
- Remove stale-build impersonation and compatibility branches.
- Remove duplicate foreground/resident run owners.
- Remove dead generated contracts, help, fixtures, and phase claims.
- Re-count execution concepts and production lines; the repaired path must be
  materially smaller than the Code Red starting point.

Proof: banned-path sweep, focused tests, full green wall, and the complete
Code Red Works Test.

## Code Red Works Test

### Setup

1. Build `alln` from committed HEAD.
2. Record the exact binary Git SHA.
3. Use a disposable registered fixture repository with a committed sentinel
   file and clean git status.
4. Configure exactly two distinct authenticated CLIs.
5. Record worker/source identities before dispatch.

### Research gesture

```text
alln run "Inspect this repository and independently name its most important infrastructure risk. Research only; return evidence." \
  --project <fixture-project> \
  --team <two-source-research-team> \
  --json
```

### Research assertions

- exactly two selected source CLIs spawn;
- both run with `cwd` equal to the registered canonical root;
- both can read `.git` and the committed sentinel;
- both return non-empty, separately attributed answers;
- worker status reflects real process state;
- no selected source is silently substituted or duplicated;
- the run reaches one terminal result;
- pre/post git status is shown;
- any unexpected write makes the run a visible violation, not fake success.

### Execution gesture

```text
alln run "Append the exact line CODE_RED_EXECUTION_PROOF to sentinel.txt, then show the git diff." \
  --project <fixture-project> \
  --team <single-worker-execution-team> \
  --json
```

### Execution assertions

- exactly one worker spawns;
- it runs in the registered canonical root;
- `sentinel.txt` in that root contains the exact line once;
- the returned diff matches the fixture repository’s real `git diff`;
- no mirror, snapshot, scratch repo, or alternate checkout exists in the path;
- the run reaches one terminal result.

### Restricted-host assertions

After CR-S05:

- the same gestures can originate from Codex;
- client and execution owner report the same exact build Git SHA;
- dropping or retrying one accepted request does not create a second vendor
  run;
- no stale coordinator is treated as compatible;
- no permission prompt is hidden or transformed into mirror execution.

### Trust reset threshold

“GREEN” requires:

1. all assertions above;
2. three consecutive complete Works Test passes from committed HEAD;
3. at least one pass after a clean execution-owner restart;
4. no code changes between those three passes;
5. a saved proof packet with commands, SHAs, source identities, run IDs,
   terminal results, and real git diffs.

Anything less is **RED** or **PARTIAL**, never “should work.”

## Mandatory developer closeout

Every Code Red slice reports:

```text
Status: RED | PARTIAL | GREEN
Commit:
Client binary SHA:
Execution-owner binary SHA:
Exact command:
Canonical repo root:
Selected source IDs:
Observed source process IDs:
Run ID:
Git status before:
Git status after:
Real changed paths:
Proof command/result:
Missing assertion:
Next deletion:
```

Prohibited closeout language without the completed receipt:

- “should work”;
- “everything is fixed”;
- “tests pass” as a workflow verdict;
- “the broker accepted it”;
- “the mirror is verified”;
- “same version, so it is compatible.”

## Debugger stop rules

- This incident is T3 Critical and repeated.
- The attempt count is exhausted for in-place resident/mirror patching.
- A repeated fingerprint may not receive another product patch without the
  required isolation harness.
- One true adjacent layer is not seam proof.
- If a slice fails the same Works Test twice, stop. Do not reclassify, add a
  fallback, or broaden scope. Produce the conflicting evidence and request a
  boundary decision.

## Done when

- Project mirrors and root substitution are deleted.
- Research Teams run selected CLIs against the real repository and return
  independently sourced answers.
- Execution Teams run one worker against the real repository and produce the
  requested real diff.
- The normal-Terminal golden path is green before the resident path.
- The restricted-host handoff is thin, exact-build, and routes only the proven
  run primitive.
- No authoritative reply error is silently swallowed.
- No stale coordinator compatibility or hidden foreground fallback remains.
- The Code Red Works Test passes three consecutive times from unchanged,
  committed HEAD, including one clean execution-owner restart.
- `bash scripts/check.sh` passes.
- Generated contracts and agent-facing help teach only the proven surface.
- The audit proof packet is committed.

## Open questions

None block CR-S00–CR-S04.

Any later decision to request macOS protected-folder permission, move project
locations, auto-install a resident service, restore detached execution, or add
mechanical answer-team isolation requires a new founder-approved feature
packet. It may not be smuggled into Code Red repair.
