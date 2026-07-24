# CODE RED — Core Infrastructure Repair

Status: **READY FOR IMPLEMENTATION — Code Red remains active; CR-S00 is
complete and CR-S01 is next. All forward execution-path feature work is
blocked until this document is green.**
Owner: AllnighterCore + CLI execution path
Updated: 2026-07-24

## Authority and precedence

This is the binding recovery packet for the current execution failure. It was
derived through `SSOT_Founder_Input_Workflow.md`, `SSOT_Feature_Workflow.md`,
and the T3 Debugger workflow.

Until this phase closes, it supersedes:

- mechanical read-only requirements for research Teams;
- project mirrors, Panel clones, protected-project byte transfer, and any other
  alternate repository representation;
- any resident path that owns run semantics instead of transporting one proven
  foreground run;
- compatibility logic that permits different source builds to cooperate;
- any developer closeout that says “should work,” “tests pass,” or “fixed”
  without the Works Test receipt in this document.

This packet authorizes deletion and repair inside the execution path. It does
**not** authorize destructive Git history changes, deleting user data, moving
repositories, changing macOS permissions, killing unrelated live work, or
changing credentials. Those remain explicit founder stops.

## Decision method — mentor input is evidence, not authority

The mentor reviews were compared against founder intent, current code, the
trusted workflow, and the requirement to reduce concepts. They are not work
orders.

Accepted because they simplify and close a demonstrated seam:

- one canonical repository and one run-semantics owner;
- restore the direct Terminal path before touching resident execution;
- delete mirrors and clone-based read-only enforcement, including Panel’s
  parallel version of the same mistake;
- reuse the existing process-group and stream-draining primitives, then test
  their actual failure seams;
- exact Git SHA equality across a resident handoff;
- no swallowed authoritative handoff errors;
- checked-in live Works Test automation plus deterministic architecture gates.

Not adopted:

- a generic four-operation resident API. Code Red permits one foreground
  `run` handoff only; observe, cancel, health, detach, Panel, Pending, and
  scheduler operations are separate future decisions;
- a new repository integrity, hashing, watcher, or undo service. Git remains
  the owner; Code Red adds only bounded pre/post observation;
- rewriting working process infrastructure merely because it is old. Existing
  spawn, process-group, pipe-drain, journal, and write-lock owners are reused
  where their focused tests prove them;
- treating a line-count target as correctness. The size budget is a tripwire;
  the semantic and live Works Tests remain the proof.

Any later advice is evaluated by the same rule: adopt the smallest part that
restores the trusted workflow without introducing a new truth owner.

## Founder note — make the wrong architecture hard to introduce

The founder did not approve a mirror, a second repository truth, or a parallel
execution system. No agent stopped to ask before creating them. The founder
should not need to reverse-engineer Swift infrastructure to discover that the
product thesis changed.

This is a process and architecture failure, not a founder-technical-depth
failure.

Agent promises are insufficient. Under bug pressure, an agent can optimize for
making one symptom disappear and quietly change the product. Therefore:

1. A bug report authorizes restoration of the existing trusted behavior. It
   does not authorize a new filesystem representation, run owner, permission
   posture, fallback, compatibility path, transport, protocol operation, or
   durable state.
2. Any such new concept is a **Founder Architecture Stop**. Before code, its
   proponent must provide a feature packet naming the user value, prior art,
   new authority, deleted authority, CLI/help impact, risk, and Works Test.
3. Production guardrails must reject the known forbidden concepts and prove
   the positive canonical-root/single-owner invariants.
4. The architecture-policy file and its enforcement test are founder-owned.
   Changing either is an explicit architecture proposal, never incidental bug
   work.
5. CI and local `scripts/check.sh` must fail before lengthy test suites when
   the architecture policy is violated.

Tests cannot prevent a fully authorized developer from deleting the tests.
The enforcement boundary is therefore both technical and procedural:
declarative policy + early local/CI gate + code-owner review for changes to the
policy or its gate. The policy must be plain enough for the founder to review
without understanding the entire implementation.

## Feature packet

### Founder intent

Allnighter is a bench for the CLIs the user already pays for:

- **Team:** several selected CLIs independently research, review, or provide
  input from the real repository.
- **Execution:** one selected CLI performs the requested work in the real
  repository.

When the user asks for research, return the independent answers. When the user
asks for execution, execute. Do not interpose a product approval ritual, turn
execution into a plan, silently downgrade it, or run it against copied bytes.

### Product value

One prompt reaches the intended real CLIs, in the registered repository, with
the same repository context they receive when launched directly. Git supplies
the familiar diff, commit, and recovery model.

### Prior art and adopted convention

- Git owns working-tree truth, diff, commit, and rollback. Allnighter does not
  create a competing filesystem or undo model.
- Mature CLI client/daemon tools keep transport separate from command
  semantics. If Allnighter needs a resident hop, the daemon invokes the same
  run service as the direct CLI; it does not reinterpret the request.
- POSIX process groups own child-process cancellation, and stdout/stderr must
  be drained concurrently while the process runs. Allnighter reuses its
  existing primitives and proves those seams instead of inventing new ones.
- Vendor CLIs own their normal permissions and approval behavior. Allnighter
  adds no blanket read-only permission layer.

Deviation requires a founder-approved feature packet before implementation.

### Trusted workflow slice

```text
registered repository
  -> research Team
  -> two selected authenticated CLIs run in that repository
  -> two independently attributed answers return
  -> execution Team
  -> one selected authenticated CLI runs in that repository
  -> the requested real Git diff exists
```

### User-visible claim

“Team asks the selected CLIs for independent input in your real repository.
Execution uses one selected CLI to do the requested work there.”

### Non-goals

- Mechanical filesystem read-only enforcement.
- Mirrors, snapshots, clones, scratch repositories, hidden worktrees, byte
  transfer, or context packets presented as repository truth.
- Detached execution, automatic resident installation/update, drain/restart,
  parked/wake behavior, Panel routing, Pending routing, or doctor routing.
- A general local RPC framework.
- Mac or iOS presentation work.
- Compatibility with stale coordinator builds.
- Automatic cleanup or reset of unexpected Git changes.
- New lifecycle, process, Git, or permission frameworks.

## Risk classification and founder stops

This is T3 Critical because the repeated fixes crossed permission, filesystem,
cross-process, and durable-run boundaries.

Stop for founder approval before any implementation that would:

- request or change Full Disk Access, Files and Folders, security-scoped
  bookmarks, entitlements, sandbox posture, or another macOS permission;
- require moving repositories out of a protected folder;
- send repository/session data outside the user’s existing selected CLIs;
- delete user mirrors, worktrees, run state, or live processes;
- broaden credential or Keychain access;
- alter distribution, billing, or quota-spend behavior;
- add an alternate repository representation or execution authority.

A normal permission failure is evidence, not permission to work around the
boundary. The run fails honestly and Code Red stops for a product decision.

## Locked product model

### 1. One repository truth

The registered canonical repository root is the working directory for every
project-scoped worker.

No production path may replace it with a mirror, clone, snapshot, scratch
directory, copied checkout, generated context, or isolation worktree. If a
process cannot access the registered repository, the run fails honestly.

### 2. Research Teams are observational, not mechanically read-only

A Team with `mutating == false`:

- resolves to the explicitly selected workers;
- runs those workers in the canonical repository;
- asks for research, review, judgment, or options;
- returns each answer with its real worker/source identity;
- never adds vendor read-only flags or a copied filesystem.

The prompt communicates the task. A bounded Git observation detects obvious
unexpected changes:

- capture canonical root, exact HEAD, porcelain status, and a digest of Git’s
  tracked diff before dispatch;
- capture the same values after terminal settlement;
- compare against the pre-existing state instead of assuming a clean repo;
- if the observed Git state changed, mark a visible research-write violation;
- never silently reset, delete, or “repair” the user’s files.

This is observation, not a new integrity service. The live Code Red fixture is
clean so its assertion is exact. Product code must not hash/copy the whole
repository, monitor arbitrary filesystem bytes, or claim stronger protection
than Git observation provides.

### 3. Execution means execution

A Team with `mutating == true`:

- resolves to exactly one worker before dispatch;
- uses the canonical repository root;
- acquires the existing per-root write lock;
- permits the selected CLI to edit, test, and commit as requested;
- never silently substitutes a worker, returns research instead, or asks
  Allnighter for a redundant approval;
- succeeds only when the requested owner-visible proof succeeds in the real
  repository.

A file in temp, a journal entry, a worker promise, or a copied-tree diff is not
execution success.

### 4. One semantics owner

`RunService.run` is the sole production owner of run resolution, canonical
root selection, Team shape, worker roster, write-lock acquisition, spawn
request, lifecycle settlement, and result projection. A deliberately renamed
replacement is allowed only if the old owner is deleted in the same slice.

The existing worker/process runner remains the sole low-level spawn owner.
`RunCLI` and any later resident adapter may call `RunService`; neither may
duplicate or reinterpret its semantics.

```text
normal Terminal ───────────────┐
                              v
                         RunService.run
                              |
restricted host -> run bytes -┘
                              |
                    existing worker runner
                              |
                selected vendor CLI process(es)
                              |
                  canonical registered repo
```

There are two callers only if the restricted-host harness proves the second
caller is necessary. There is always one execution engine.

### 5. Resident execution is optional transport

CR-S01–CR-S04 do not use resident execution.

If CR-S05 proves a resident hop is necessary, its Code Red surface is exactly
one foreground operation:

```text
run(request) -> accepted + events + terminal result
```

The resident adapter may serialize/deserialize the canonical request/result,
require exact build identity, durably accept one idempotency key, and invoke
`RunService.run`. It may not own Team resolution, root selection, lifecycle
meaning, retries, fallback, or a second journal.

Observe, cancel, health, detach, Panel, Pending, doctor, scheduling, install,
update, drain, re-adoption, and stale-build bridging are outside this repair.
Adding any operation requires its own feature packet and live Works Test.

For a resident request, durable acceptance must exist before a worker spawns.
Retrying the same idempotency key returns the same acceptance/result and never
spawns a second vendor process. Direct Terminal execution needs no resident
receipt or resident idempotency machinery.

Foreground Terminal interruption continues to use the existing process-group
owner. It is not a resident protocol operation. Resident cancellation is
unsupported during Code Red rather than approximated by another control path.

## Current-state audit

### Incident evidence

The 2026-07-24 repair window produced:

- 31 commits in roughly four hours;
- 55 changed files;
- 2,644 inserted lines and 178 deleted lines;
- 11 separate edits to `ResidentExecutionBroker.swift`;
- successive repairs for probe prompts, protected roots, project mirrors,
  coordinator ownership, admission, status, install recovery, and stale
  coordinator compatibility.

Current production evidence includes:

- `ProjectMirror` / `ProjectMirrorPayload`;
- `ProjectMirrorStore` / `ProjectMirrorMaterializer`;
- `ProjectMirrorCapture`;
- `ResidentProjectAccessBoundary`;
- `projectMirrorId` in canonical request types;
- `RunCLI.runForegroundThroughResident`;
- Panel’s separate `PanelSeatIsolation` clone system and `PanelReadOnlyArgs`;
- 14 `ResidentExecutionOperation` cases;
- 2,600 lines across only seven central resident/mirror files, before install,
  probe, reaper, CLI wiring, Panel isolation, models, and tests are counted;
- authoritative broker replies frequently wrapped in `try?`.

The architecture grew under incident pressure while the end-to-end user path
remained red.

### Proven failures

1. A registered project can be replaced with copied bytes before the run is
   resolved as research or execution.
2. The copy omits `.git`, so it cannot satisfy the promised repository context.
3. Execution can succeed against disposable bytes while the real repository is
   unchanged.
4. New and stale source builds can be treated as compatible.
5. Authoritative handoff writes can fail silently while work continues.
6. Unit tests prove components that the founder never asked for, but do not
   prove two real selected CLIs or one real-root edit through the installed
   user path.
7. Panel independently created another copied-repository/read-only system,
   showing that deleting only the symbol `ProjectMirror` would not fix the
   governing mistake.

### Boundary verdict

Resident-backed project execution is **RED**. It is not trusted for dogfood or
eligible for further feature layering.

### Truth owners

| Truth | Sole owner |
| --- | --- |
| Repository bytes, diff, commit, rollback | Registered repository + its Git state |
| Team selection and `mutating` shape | Resolved `TeamPreset` |
| Run resolution and lifecycle semantics | `RunService.run` |
| Worker process | Existing worker/process runner |
| Durable run status/result | Canonical `TeamRun` / run store |
| Concurrent mutation | Existing canonical-root write lock |
| Cross-process build freshness | Exact executable Git SHA |

### Lie-prone layers

- copied files and hashes presented as repository truth;
- separate direct/resident resolution paths;
- broker acceptance presented as completed work;
- journal state presented as live process truth;
- human version or contract version presented as source-build identity;
- generated/help text describing retired behavior;
- mock/component tests presented as dogfood proof.

## Inference bans

| Junction | Forbidden inference | Deterministic negative proof |
| --- | --- | --- |
| Research intent -> filesystem | Research requires read-only flags or a copy | Forbidden-concept gate + real-root Team test |
| Alternate bytes -> repository | Matching content equals the registered repo | Request schema has one `repoRoot`; canonical-root test |
| Broker accepted -> run worked | Acceptance proves worker/result | Live vendor process + terminal result |
| Execution prose -> change | Worker says it edited, therefore it did | Fixture’s real Git diff + sentinel proof |
| Human version -> source identity | Same product version means compatible build | exact-SHA mismatch test |
| Retry -> second attempt | Retrying an accepted request may respawn | resident idempotency kill test |
| Green unit tests -> green product | Component tests prove the founder gesture | checked-in live Works Test receipt |
| Bug fix -> architecture authority | Fixing a symptom permits a new subsystem | policy/Code Owner gate |
| Unexpected Team write -> cleanup | Allnighter may reset the tree | test proves violation is surfaced and files preserved |

## CLI and teaching surface

The only trusted recovery command is:

```text
alln run "<message>" --project <id|path> --team <team-id> [--json]
```

Contract:

- research Team: selected workers return separately attributed answers;
- execution Team: exactly one selected worker executes in the registered root;
- `--json`: projects the canonical `TeamRunJSON`; no resident-specific parallel
  result shape;
- `--dry-run`: resolves selection and clearly says no worker executed;
- unsupported Code Red surfaces fail with a stable nonzero error and one honest
  recovery action; they do not fall back.

Temporarily unsupported/untrusted:

- `--detach`;
- Panel start/round/watch;
- Pending run/wake;
- resident-routed doctor/detect;
- coordinator install/update/drain;
- stale-build compatibility.

Required teaching changes ship with CR-S01 and CR-S02:

- update `team_run_loop` and the directly related error/recovery topics;
- make `help search` find the path using `team research`, `team input`,
  `execute`, `real repository`, `coordinator mismatch`, and `sandbox`;
- remove and deny-list teaching for project mirrors, Panel clones, mechanical
  read-only Teams, stale coordinator bridging, and direct/resident fallback;
- regenerate contract artifacts from `ContractRegistry`;
- assert every named command/flag resolves.

### Implementation impact ledger

| Surface | Code Red impact |
| --- | --- |
| Core models | Remove `projectMirrorId` and mirror/isolation JSON. Preserve canonical `TeamRunJSON`; do not create a Code Red result schema. |
| Engine | Reuse `RunService`, worker/process runner, run store, and write lock. Delete alternate root and duplicate resident semantics. |
| CLI | Make `RunCLI` a thin adapter to `RunService.run`; unsupported surfaces fail closed. |
| Generated contracts | Regenerate from `ContractRegistry` after source changes; no hand edits. |
| Help | Update `team_run_loop` and error recovery; deny-list retired grammar. |
| Mac app | Frozen. No GUI work or new app-owned run semantics during Code Red. |
| iOS app | No impact. Remote control remains parked. |
| Resident protocol | Delete or reduce to one foreground `run` handoff after CR-S05 evidence. |
| Agent drivers | No new per-driver permission flags, filesystem rules, or fallback. Existing invocation manifests remain the owner. |
| Auth/privacy/permissions | No credential movement or permission change. Any TCC/product-location decision is a founder stop. |

## Mechanical architecture policy

CR-S01 adds one declarative policy file and one early gate:

```text
config/architecture-policy.json
scripts/check_architecture_policy.sh
```

`scripts/check.sh` invokes the gate before Swift builds/tests. CI invokes the
same script; it may not implement a parallel policy.

The policy records:

- the production paths it scans;
- forbidden symbols/terms;
- the exact allowed resident operation set;
- the one run-semantics owner;
- the one canonical-root field;
- the resident production line budget;
- founder-owned policy/gate paths.

Initial forbidden concepts include all current spellings:

```text
ProjectMirror
ProjectMirrorPayload
ProjectMirrorStore
ProjectMirrorMaterializer
ProjectMirrorCapture
projectMirrorId
ResidentProjectAccessBoundary
residentSafe
project-mirrors
cli-compatible-resident
PanelSeatIsolation
PanelReadOnlyArgs
--sandbox read-only
--permission-mode plan
```

The gate also rejects obvious alternate-root schema fields and production
filesystem-copy code in the run path. It scans production sources and living
agent teaching surfaces; archives and this incident document are evidence and
are excluded.

The check must be fixture-tested: each policy rule is fed a violating sample,
must exit nonzero, then passes when the sample is absent. A substring sweep
alone is not sufficient. Positive XCTest invariants prove canonical-root
identity and the single run owner.

### Policy ownership

CR-S01 adds Code Owner coverage for:

- `config/architecture-policy.json`;
- `scripts/check_architecture_policy.sh`;
- its fixture tests;
- the CI workflow that requires it;
- this Code Red packet while active.

The repository’s protected branch must require the architecture-policy CI job
and Code Owner review when those paths change. Enabling or changing remote
branch protection is a founder action, not implicitly authorized by this
packet.

**CR-S01 external owner blocker:** this repository has no `CODEOWNERS` file
and no reviewed identity to assign. The policy and gate are checked in here;
the founder must add the protected-branch Code Owner assignment during CR-S07.

## Quantitative tripwires

CR-S01 checks in `scripts/code_red_metrics.sh` and records the exact committed
baseline before deletion. The script, not prose, owns the measured file set.

| Metric | Current evidence | Required before Code Red closes |
| --- | ---: | ---: |
| Alternate repository implementations | at least 2 | 0 |
| Resident operation cases | 14 | 1 (`run`) |
| Run-semantics owners | more than 1 path | 1 (`RunService.run`) |
| Silent authoritative handoff writes | dozens | 0 |
| Central seven-file resident/mirror LOC | 2,600 | mirror files deleted |
| Entire Code Red resident handoff LOC | baseline in CR-S01 | <= 800 |
| Forbidden production concept hits | baseline in CR-S01 | 0 |

The 800-line resident cap includes request/result transport, rendezvous, broker
adapter, and coordinator handoff production code. It excludes shared
`RunService`, shared worker/process primitives, tests, and generated artifacts.
It is deliberately generous, not a target. An increase requires founder
approval and a revised feature packet.

Production code across Code Red must be net-negative. Test/harness code may
grow. A slice may add a small adapter or observation only when it deletes the
superseded owner in the same slice.

## Supporting proof wall

Required wall-reachable checks:

1. `ArchitecturePolicyTests`
   - violating fixtures make the policy script red;
   - changing allowed operations/owner/root fields is visible.
2. `CanonicalRepoRootInvariantTests`
   - resolved root, worker CWD, reported root, `.git`, and fixture filesystem
     identity all match the registered root;
   - no alternate root exists in the request/result schema.
3. `SingleRunOwnerInvariantTests`
   - direct CLI and resident adapter call the same `RunService.run`;
   - CLI/broker contain no Team/root/write-lock resolution.
4. `ResearchGitObservationTests`
   - clean unchanged, pre-existing dirty unchanged, new tracked change, new
     untracked path, and preserved unexpected write.
5. `ExecutionWriteLockTests`
   - one mutating owner per canonical root; research does not take the lock.
6. `ResidentBuildIdentityTests`
   - exact SHA match accepts; mismatch fails before spawn; no compatibility
     rewrite.
7. `ResidentRunSurfaceTests`
   - only `run` decodes; all retired operations fail closed.
8. `AuthoritativeHandoffFailureTests`
   - acceptance persistence failure spawns nothing;
   - result/event persistence failure is terminally visible, never `try?`.
9. Existing process-ownership tests plus a focused large-output test
   - workers own a process group and cancellation targets that group;
   - stdout and stderr each exceed 256 KB and are drained concurrently before
     wait without deadlock or truncation.
10. Contract/help drift tests
    - retired grammar cannot be re-taught;
    - the Code Red command and recovery terms resolve.

Tests should reuse current owners. They must not create a second run service,
process runner, Git service, or resident protocol to make testing convenient.

## Ordered implementation slices

No slice begins until the prior slice’s Works Test is recorded green. Each
slice is deletion-first, committed independently, and leaves the supported
surface runnable.

### CR-S00 — Freeze and semantic cutover — COMPLETE

- Land and route this document.
- Mark the old resident/mirror direction superseded.
- Block “fixed” language without the Code Red receipt.

Proof: active routing reaches this packet first.

### CR-S01 — Remove alternate repositories and restore direct ownership

Do these in one slice so deletion cannot leave the mirror path as the only
working path:

- route foreground `alln run` directly to existing `RunService.run`;
- delete `runForegroundThroughResident` and protected-root mirror capture from
  `RunCLI`;
- fail `--detach` and resident foreground routing as temporarily unsupported;
- delete `ProjectMirror*`, `ResidentProjectAccessBoundary`,
  `projectMirrorId`, `residentSafe`, mirror storage paths/errors/tests/help;
- delete Panel’s `PanelSeatIsolation`, `PanelReadOnlyArgs`, clone lifecycle,
  isolation JSON, tests, and mirror capture wiring; Panel itself remains
  frozen/untrusted;
- add the architecture policy, fixture tests, metrics script, Code Owner entry,
  and early `scripts/check.sh` hook;
- rewrite living run-model/help claims so no active SSOT still requires
  mechanical read-only or alternate repositories.

Works Test:

```text
normal Terminal -> alln run -> one real authenticated CLI
```

The worker reports canonical `pwd`, reads `.git`/HEAD, returns a sourced answer,
and no resident request or alternate repository is created.

### CR-S02 — Establish the single run owner

- make `RunService.run` the only resolution/execution semantic owner;
- make `RunCLI` a parser/project lookup/output adapter only;
- remove duplicate foreground/resident Team/root/write-lock resolution;
- propagate authoritative lifecycle/result failures;
- add canonical-root, single-owner, Git-observation, write-lock, process-group,
  and large-pipe tests;
- keep lifecycle terms limited to the existing canonical run states.

Works Test: the CR-S01 command still passes and its canonical `TeamRunJSON`
identities/statuses match the actual process.

### CR-S03 — Prove the two-CLI research Team

- run exactly two explicitly configured, distinct authenticated CLIs;
- preserve the selected roster with no substitution or collapse;
- run both in the same canonical root;
- return separately attributed non-empty answers;
- record bounded pre/post Git observation and surface any violation.

Works Test: the founder’s exact research gesture returns two real answers and
the clean fixture remains unchanged.

### CR-S04 — Prove execution

- resolve a `mutating` Team to exactly one selected worker;
- acquire the existing canonical-root write lock;
- make one bounded requested edit in the fixture repository;
- run the requested proof;
- return the actual changed path and Git diff;
- prove an execution request is never downgraded to research or a dry run.

Works Test: the sentinel change exists exactly once in the fixture’s real
working tree. A change anywhere else fails.

### CR-S05 — Prove and, only if necessary, add restricted-host transport

First run the existing isolated host/sandbox harness. Record the exact
primitive that fails and the smallest transport that crosses it.

If direct execution from Codex now works, delete resident run routing and close
this slice with no replacement.

Only if the harness proves a resident hop is necessary:

- manually start one execution owner from normal Terminal;
- implement one foreground `run` request/event/result stream;
- require exact client/execution-owner Git SHA equality;
- persist acceptance before spawn;
- make idempotent retry return the same run;
- invoke the same `RunService.run`;
- fail unavailable/mismatch with one manual restart action.

Do not install, update, probe multiple transports, mirror, bridge, drain,
detach, or fall back.

Works Test: the CR-S03 and CR-S04 gestures originate from Codex and produce the
same real-root results with exactly one spawn per selected worker.

If the normally launched owner cannot access the registered protected root,
stop. The choices are a future explicit macOS permission design or a founder
decision about supported project locations. No agent chooses either during
Code Red.

### CR-S06 — Delete the abandoned control plane

- delete all resident operations except the proven foreground `run` operation,
  or delete resident execution entirely if CR-S05 did not need it;
- delete stale-build compatibility, auto-install/update, drain/restart,
  duplicate query/status surfaces, and dead adapters;
- delete dead contracts, generated outputs, fixtures, help, and phase claims;
- enforce the quantitative tripwires;
- run the full local wall and live Code Red harness.

Works Test: all deterministic checks pass and the full live proof succeeds
three consecutive times from unchanged committed HEAD.

### CR-S07 — Lock the gate and close Code Red

- commit the live proof packet;
- confirm `scripts/check.sh` starts with the architecture gate;
- confirm the required CI job is green;
- founder enables/confirms protected-branch and Code Owner enforcement;
- archive the superseded resident plan and this packet’s incident-only detail;
- route active docs to the simplified Unified Run Model.

This is the only remote governance action in the phase and requires the
founder. Until it is confirmed, Code Red may be functionally green but is not
closed against recurrence.

## Checked-in Code Red Works Test

CR-S01 creates `scripts/code_red_works_test.sh`. Structural fixture mode runs
in the wall. Live mode is manual because CI does not possess the founder’s
authenticated vendor sessions.

Required modes:

```text
bash scripts/code_red_works_test.sh structural
bash scripts/code_red_works_test.sh live-direct
bash scripts/code_red_works_test.sh live-resident   # CR-S05 only, if needed
```

The script:

1. refuses a dirty product checkout;
2. builds `alln` from committed HEAD and records the exact Git SHA;
3. creates a disposable clean Git fixture as the registered canonical root;
4. uses exactly two explicitly named, authenticated vendor CLIs in live mode;
5. records selected source IDs and observed process IDs;
6. performs the research and execution gestures below;
7. emits a machine-readable receipt plus a human summary;
8. exits nonzero on any missing assertion;
9. never accepts mocks, fake drivers, or developer prose as live proof.

### Research gesture

```text
alln run "Inspect this repository and independently name its most important infrastructure risk. Research only; return evidence." \
  --project <fixture-project> \
  --team <two-source-research-team> \
  --json
```

Assertions:

- exactly two selected distinct source CLIs spawn;
- both use the canonical root as `cwd`;
- both read `.git`, HEAD, and the committed sentinel;
- both return non-empty, separately attributed answers;
- actual process state matches persisted worker state;
- no substitution, duplication, or roster collapse occurs;
- one canonical run reaches a terminal result;
- the clean fixture’s Git state is unchanged.

### Execution gesture

```text
alln run "Append the exact line CODE_RED_EXECUTION_PROOF to sentinel.txt, then show the git diff." \
  --project <fixture-project> \
  --team <single-worker-execution-team> \
  --json
```

Assertions:

- exactly one selected worker spawns;
- it uses the canonical root;
- `sentinel.txt` there contains the exact line once;
- the returned diff matches that fixture’s real `git diff`;
- no alternate repository exists in the path;
- the proof command passes;
- one canonical run reaches a terminal result.

### Resident-only assertions

When CR-S05 proves resident transport is necessary:

- direct and resident paths report the same exact build Git SHA;
- mismatch fails before a vendor spawn;
- acceptance exists before spawn;
- retrying the same key produces no duplicate spawn;
- the same `RunService.run` owns both calls;
- permission failure is visible and creates no alternate root.

### Trust reset threshold

“GREEN” requires:

1. every applicable assertion above;
2. three consecutive complete live passes from committed HEAD;
3. at least one pass after a clean execution-owner restart if resident
   transport exists;
4. no product code or policy changes between passes;
5. one committed proof packet containing commands, SHAs, source IDs, process
   IDs, run IDs, terminal results, canonical roots, and real Git diffs.

Anything else is **RED** or **PARTIAL**, never “should work.”

## Mandatory slice closeout

Every Code Red slice reports:

```text
Status: RED | PARTIAL | GREEN
Commit:
Production lines added / deleted:
Concepts deleted / added:
Client binary SHA:
Execution-owner binary SHA:
Exact command:
Canonical repo root:
Selected source IDs:
Observed source process IDs:
Run ID:
Git observation before:
Git observation after:
Real changed paths:
Proof command/result:
Architecture policy result:
Missing assertion:
Next deletion:
```

Prohibited without a complete GREEN receipt:

- “should work”;
- “everything is fixed”;
- “tests pass” as a workflow verdict;
- “the broker accepted it”;
- “the mirror is verified”;
- “same version, so it is compatible.”

## Debugger packet and stop rules

```text
Tier: T3 Critical
Fingerprint: resident project run + alternate root / wrong process authority +
             missing real-vendor, real-root end-to-end proof
Attempt count: exhausted for in-place broker/mirror patching
Truth owner: canonical repository + RunService.run
Lie-prone layer: mirror/resident compatibility and component-only proof
Isolation harness: existing TCC host harness; required before CR-S05
Fix boundary: delete alternate truth, restore direct path, then prove one thin hop
Kill test: architecture policy + live Code Red Works Test
```

Stop rules:

- no more in-place repair of mirror/clone paths;
- no third reclassification of this fingerprint;
- one green adjacent component is not seam proof;
- if a slice fails the same Works Test twice, stop and present conflicting
  evidence; do not add a fallback or broaden the protocol;
- if implementation needs a new truth owner or permission posture, stop for a
  founder feature decision;
- every regression answer must state: “What was the agent allowed to do that
  must never be allowed again?” and add the deterministic law to the wall.

## Done when

- alternate repository and mechanical read-only systems are deleted from every
  production path, including Panel;
- research Teams run selected CLIs in the real repository and return
  independently attributed answers;
- execution Teams run exactly one selected CLI in the real repository and
  produce the requested real diff;
- `RunService.run` is the sole semantic owner;
- the normal-Terminal path is green before any resident path;
- resident execution is absent or a single exact-build foreground transport;
- no authoritative handoff error is swallowed;
- no stale coordinator compatibility or hidden fallback remains;
- architecture policy, positive invariants, generated contracts, and live help
  teach only the proven surface;
- `bash scripts/check.sh` passes from clean committed HEAD;
- the live Code Red Works Test passes three consecutive times from unchanged
  committed HEAD;
- the proof packet is committed;
- the founder confirms the protected architecture gate.

## Blocking questions

None block CR-S01–CR-S04.

CR-S05 is conditional on harness evidence. A macOS permission or supported
project-location decision is a Founder Architecture Stop, not an implementation
detail. Remote protected-branch enforcement in CR-S07 also requires the
founder’s explicit action.
