# Resident Execution Broker — One Spawn Path for Every CLI

Status: **Implementation in progress — REB-S01 landed; REB-S02 routes `alln run`, `alln run --detach`, streamed run events, and `alln team status/result` through the resident authority. REB-S03 routes the complete Panel lifecycle (start/round/status/watch/done) and all `alln doctor` probes through it, removing caller-cache self-fusion and restricted-host vendor spawning. REB-S04 provides explicit user-consented `alln serve install`, identity-verified activation, and durable drain/restart on update; `scripts/rebuild_cli.sh` rebuilds outside a protected checkout and refreshes the service in one command. Try Fix follow-up routing and the host matrix remain.**
Owner: AllnighterCore + `alln serve` + CLI
Updated: 2026-07-23 (REB-S04 installation path landed; activation requires explicit user consent)
Supersedes: the resident execution boundary in archived
`Mac_Standalone_App_And_Background_Coordinator.md`; its Mac app shell history
remains historical.

## Problem and proposed direction

Allnighter Panel works when it is launched from ordinary terminals and from host
agents whose command runners give child processes normal user-level filesystem
access. It fails when launched from a restricted Codex session because every
vendor CLI inherits the parent Codex sandbox. Claude Code, Codex CLI, Cursor
Agent, Grok Build CLI, Kimi Code CLI, and OpenCode then cannot write their own
session, state, alias, or project directories under the user's home directory.

This is not fundamentally six driver bugs. It is one process-boundary bug:

```text
sandboxed host agent
  -> foreground alln
    -> vendor CLI inherits the host sandbox
      -> vendor CLI cannot use its normal authenticated user environment
```

The failed Phase 72 dogfood run proved that per-driver workarounds are the wrong
direction. Readiness filtering made the failure more honest, but collapsing a
multi-source Panel onto repeated calls to the only source that happened to work
inside the sandbox did not make the Panel valid. Adding fake `HOME` values,
redirecting state directories, copying credentials, or accumulating
vendor-specific environment exceptions would be fragile, unsafe, and more
complex with every source Allnighter adds.

The proposed durable solution is one resident execution path:

```text
Allnighter CLI / Mac app / any host agent
  -> typed local request
    -> resident `alln serve` outside the caller's sandbox
      -> existing Core run machinery
        -> any configured vendor CLI in its normal user environment
```

Every vendor process launched by Allnighter should ultimately be spawned by the
resident coordinator. That is simpler than deciding which callers or drivers
need exceptions. Codex exposed the requirement first, but the boundary also
protects Allnighter from future host sandboxes, IDE restrictions, short-lived
agent processes, and terminal closure. The solution is source-agnostic: a new
driver receives the same execution boundary through its existing manifest and
worker runner.

This is not a proposal to weaken Codex security or ask users for Full Access.
The coordinator is a normal user-level Allnighter process. It receives typed
Allnighter operations, never arbitrary remote shell, and it uses only the
permissions the user's logged-in CLIs already use.

## Founder intent

- **Raw request:** Users should not need to know that a calling agent's sandbox
  can break child CLIs, grant that agent Full Access, or remember a per-source
  workaround. Prefer one `alln serve` execution path for every CLI over custom
  state-directory handling per driver.
- **Product value:** "Run a Team" means the configured Team runs, independent of
  whether the request came from Codex, Claude, Cursor, Grok, the Allnighter app,
  or a normal terminal.
- **Trusted workflow slice:** enable background execution once -> invoke any
  existing `alln` run/Panel command from a restricted host -> resident
  coordinator accepts it -> intended distinct sources run -> the existing
  command streams and returns the canonical result.
- **Non-goals:** bypass a vendor's own authentication or permissions; add Full
  Disk Access; run as root; copy credentials; create a cloud execution service;
  expose arbitrary shell over a local API; silently substitute a different
  source or collapse a roster.

## Prior art

Mature local tools separate a constrained client from a trusted local execution
owner: Docker uses a client/daemon boundary, build systems use resident build
services, and editor language servers outlive individual editor commands. The
useful convention is not their wire format; it is the ownership split:

- client parses intent, submits a typed request, and presents progress;
- resident service owns process lifetime, concurrency, and durable execution;
- request identity makes retries safe;
- one engine serves every caller instead of embedding execution in each client.

Allnighter already chose this process shape for long-running work and iOS. The
missing step is to make it the sole vendor-spawn path rather than an optional
health/background skeleton.

## Current state

### What exists

- `ResidentCoordinator` and `alln serve` already run as a resident user-level
  process.
- `alln serve --health --json` records coordinator identity, PID, versions, and
  loopback health.
- `RunService`, `CatalogRunCoordinator`, `WorkerInvokerFactory`,
  `DriverRegistry`, `RunStore`, process ownership, idempotency, write locks, and
  per-driver concurrency gates already own most execution semantics.
- Incremental run and Panel journals exist.
- The coordinator already hosts wake, backoff, and remote-agent loops.
- The archived
  `Mac_Standalone_App_And_Background_Coordinator.md` selected `alln serve` as
  the resident process, but its first slice explicitly excluded automatic
  routing of ordinary foreground commands.

### What is missing

- The current loopback listener serves only `GET /health`.
- There is no sandbox-compatible local command inbox.
- Foreground CLI paths construct worker runners and spawn sources inside the
  calling process.
- Panel lifecycle and Panel state are owned by the foreground command.
- `alln ps` cannot consistently name source processes launched by Panel.
- Per-driver concurrency can say every seat is `running` while most are queued.
- Readiness filtering can silently reduce a multi-source roster to repeated
  calls to one source.
- Setup/doctor smoke probes still run under the caller's sandbox.
- No hostile-parent acceptance test launches Allnighter from a restricted
  environment and proves multiple real sources.

### Incident evidence

In Codex workspace-write mode, full doctor observed:

- Codex CLI could not create PATH aliases and failed app-server initialization;
- Cursor Agent received `EPERM` creating `~/.cursor/projects/...`;
- Grok received `FS_PERMISSION_DENIED` creating a session;
- Kimi received `EPERM` creating `~/.kimi-code/sessions/...`;
- Claude smoke exited non-zero;
- OpenCode was not runnable;
- Antigravity alone passed its smoke probe.

The subsequent Panel mapped seven lenses to one Antigravity model. Because the
driver permits one concurrent spawn, all seven seats appeared `running` while
six were actually queued. `alln ps` did not expose the source child. This was
honest enough to avoid the earlier empty-result ghost, but it was not a valid
multi-source review.

The same dogfood pass also found untracked `.env.local` files inside Panel
isolation copies. The execution broker does not by itself fix snapshot safety;
secret-safe answer isolation is therefore an explicit gate in this phase.

## Why this was not completed earlier

The resident coordinator was considered, but for a narrower reason. Its phase
was framed around long-running work, window lifetime, iOS access, and
notifications. Serve0 intentionally shipped health and wake/recovery plumbing
while declaring ordinary foreground command routing out of scope.

That left an untested assumption: a foreground `alln` process could safely spawn
vendor CLIs in whatever host launched it. The assumption held in normal
terminals and in Claude, Cursor, and Grok dogfood, so source-specific tests did
not expose the missing boundary. There was no acceptance fixture where a
restricted parent launched two or more independently authenticated CLIs.

When Codex exposed the gap, investigation stayed too close to each symptom:
binary drift, journal location, empty Panel results, and readiness state. Those
fixes improved truthfulness but did not challenge foreground process ownership.
The active route also continued pointing to a coordinator document after that
document had been archived, making the unfinished execution slice easier to
miss.

The durable lesson is that host compatibility is an execution-boundary
property, not a driver-readiness property. The hostile-parent Works Test in this
phase prevents that assumption from returning.

## Product decision

### One execution authority

When Allnighter invokes a vendor source, `alln serve` is the sole process
allowed to spawn it. This applies to:

- single-worker runs;
- answer Teams;
- Panel rounds;
- setup/auth smoke probes and full doctor checks;
- warm sessions and source servers;
- pending/wake/resume execution;
- Mac and future iOS-originated runs.

The foreground `alln` process is a client. It may read local catalogs, validate
syntax, submit a request, stream events, and render canonical JSON/human output.
It must not build a second vendor-spawn path.

Direct foreground vendor execution is deleted after broker cutover. A hidden
fallback would recreate the exact split-brain behavior this phase removes.
Developer-only test runners may inject an in-process executor, but production
commands have one authority.

### No silent roster degradation

Source readiness is observed by the resident process in the same environment
that will run the source. A caller sandbox is not source readiness.

If a selected Team cannot run as selected, Allnighter fails with actionable
per-source truth. It must not:

- mark a source unavailable because the client sandbox blocked it;
- replace distinct sources with repeated calls to one source;
- cross a user-selected model shelf without authorization;
- describe a degraded single-source result as a completed Panel.

### Queue truth

A worker is:

- `queued` after the coordinator accepts it but before its source process owns a
  concurrency slot;
- `running` only after the source process is spawned and identity-owned;
- terminal only from a persisted worker result.

Every spawned source process must appear under the accepted run in `alln ps`.
Panel status projects these same states; it does not invent parallel liveness.

## Truth ownership

There are four truths and no duplicate execution state:

1. **Request acceptance:** the resident broker store owns whether a request ID
   was accepted and which canonical run/Panel ID it created.
2. **Run semantics:** existing AllnighterCore run and Panel contracts own Team,
   worker, write-policy, result, and lifecycle meaning.
3. **Process lifetime:** the resident coordinator owns source spawn, concurrency,
   process identity, cancellation, and recovery.
4. **Durable result:** existing run/Panel journals own progress and terminal
   output.

The client owns none of these after acceptance. Client death must not cancel or
orphan coordinator-owned work.

One coordinator serves every project of the user concurrently, so isolation
between concurrently-submitting projects is request-level, not process-level:
every accepted request is scoped to its canonical project root, reconcile and
cancel operate only within that scope, and no coordinator maintenance sweep may
reap work belonging to a different project's run (the concurrent-invocation
isolation rules apply unchanged inside the coordinator).

## Local broker contract

### Request envelope

The source contract is a versioned Codable type in AllnighterCore, not HTTP
handler dictionaries or prompt prose:

```text
ResidentExecutionRequest
  schemaVersion
  requestId
  idempotencyKey
  submittedAt
  client
    binaryVersion
    contractVersion
    pid
    origin
  operation            # one tagged union: each case carries its own typed payload
    teamRun
    panelStart
    panelRound
    panelDone
    sourceProbe
    query              # typed read: runStatus | panelStatus | processSnapshot
    cancel
  projectId / canonicalProjectRoot
```

Replies and progress share one typed envelope, `ResidentExecutionEvent`: a
cursor-ordered, request-correlated Codable carrying progress, a terminal
boundary, or a typed error — the `eventCursor` in the receipt indexes this
stream. Reply files in the rendezvous are named by request ID and cursor so a
client can correlate and resume without guessing. Both transports carry these
same event types; neither invents its own.

The operation is a single tagged-union Codable: the case carries the payload,
so a kind and a payload can never disagree. Each case states whether the
project root is required (run/Panel dispatch) or forbidden
(cancel-by-canonical-object-id); there is no optional root.

Observe/control verbs that remain on the CLI surface (`panel status`, `panel
watch`, `ps`, `kill`, doctor probes) are not a second contract: mutating verbs
(`kill`, cancel) are typed operations in the union above; read verbs are the
`query` case, answered from the durable journals and broker store and returned
to a restricted client as `ResidentExecutionEvent` replies over the rendezvous.
Live-vs-journal semantics are explicit: a query answers from current
coordinator state plus the journal, and a watch is a query with a cursor that
follows the event stream.

The acceptance receipt contains:

```text
ResidentExecutionReceipt
  requestId
  acceptedAt
  coordinatorId
  canonicalObjectId       # runId or panelId
  journalRef
  eventCursor
```

Submitting the same idempotency key and canonical payload returns the same
receipt. Reusing it with a different payload fails deterministically.

### Transport

The transport must work when the caller has no network permission and cannot
write the user's normal application-support directories.

The first implementation uses an atomic local inbox under a per-user,
permission-restricted temporary rendezvous directory:

```text
/private/tmp/alln-<uid>/broker-v1/
  inbox/
  accepted/
  replies/
```

- coordinator creates the root with mode `0700` using exclusive-creation
  semantics: it never follows a symlink at the rendezvous path, verifies the
  resolved directory is owned by its own uid with no wider permissions, and
  fails closed if the path pre-exists with wrong ownership, wrong mode, or as a
  symlink — the rendezvous lives under a world-writable parent, so pre-creation
  and symlink hijack by another local user are in the threat model;
- client writes a temporary request and atomically renames it into `inbox`;
- coordinator atomically claims it before validation;
- an accepted request is persisted into the durable broker store before the
  receipt appears;
- replies contain no credentials or source environment;
- boot/temp cleanup cannot erase an accepted run because the durable journal is
  already authoritative;
- after acceptance, progress and terminal results reach a sandboxed client
  through the rendezvous `replies/` channel — that channel is normative for
  restricted clients, because the normal journal location under the user's
  application-support directory may be unreadable from the caller's sandbox.
  `journalRef` names coordinator-side authority; it is never a client
  filesystem dependency. Unrestricted clients may read the journal directly as
  an optimization, but every projection a restricted client needs (round and
  status JSON included) must be servable over the rendezvous;
- coordinator reachability has a sandbox-safe form over the same channel: a
  ping request answered through `replies/`. Doctor and
  `COORDINATOR_UNAVAILABLE` classification use this path when loopback is
  blocked, so a blocked loopback is never reported as a missing coordinator.

The concrete rendezvous root is resolved, not hardcoded: a per-uid directory
derived from the platform temporary-directory convention (honoring a
sandbox-relocated `TMPDIR` when the coordinator and client can both resolve the
same path), with `/private/tmp/alln-<uid>/` as the Darwin fallback. This phase
specifies Darwin behavior only; non-Darwin rendezvous is out of scope and must
not be improvised per driver.

Loopback HTTP/WS may later provide a faster app/iOS presentation path, but it is
not the only CLI handoff because restricted hosts may block network and
loopback access. There is no second semantic contract: both transports encode
the same Core request/receipt/event types.

### Authentication and local trust

- local-only, one macOS user; no remote listener;
- request and reply directories are user-only;
- requests carry a per-install client proof and coordinator nonce — the
  concrete proof mechanism is **not yet decided**; it is Open question 1 and a
  hard gate on REB-S01. Until that ruling, this bullet is a requirement shape,
  not a contract;
- coordinator validates command kind, project registration/root, contract
  version, request size, and payload schema;
- no arbitrary executable, environment map, shell command, or credential may
  cross the broker contract;
- the coordinator resolves models, manifests, commands, environment, and
  credentials from its own installed truth;
- every request records its origin.

This boundary prevents the broker from becoming a general sandbox escape.

## Coordinator lifecycle

Enablement is app-independent, because the CLI is the product and the Mac app
is optional. `alln serve install` (final name decided in REB-S04) registers the
user-level LaunchAgent/login item from a plain terminal; the Mac app setup path
calls the same mechanism. Setup explains that background execution lets any
installed agent send work to the user's CLI Team without granting that agent
broad machine access.

- No root daemon and no Full Disk Access.
- One coordinator per logged-in user.
- launchd restarts it after crashes.
- **Clients never start the coordinator.** A coordinator spawned by a caller
  would inherit that caller's sandbox — the exact defect this phase removes —
  while reporting healthy. Only the launchd/login-item registration owns
  coordinator start; the coordinator records its launch origin, and a cold
  start from a client is answered by `COORDINATOR_UNAVAILABLE` with the one
  enablement action, never by auto-start.
- The coordinator may remain idle with a tiny footprint; eliminating the
  foreground spawn path is more important than demand-start cleverness.
- Client/coordinator version handshake is mandatory.
- On compatible patch drift, the coordinator drains and restarts on the current
  installed binary. Drain means: accepted work either runs to its terminal
  journal state before restart or is re-adopted by the new coordinator from
  the durable broker store and journals; in-flight source processes are never
  silently orphaned or killed by a version restart.
- On incompatible contract drift, no dispatch occurs; the client reports
  `COORDINATOR_VERSION_MISMATCH` with one repair action.
- An accepted run survives client exit, terminal closure, or host-agent
  cancellation.

The app presents this as "Keep Allnighter ready," not as daemon administration.

## CLI surface

Existing user commands remain the product surface:

- `alln run ...`
- `alln panel start|round|status|watch|done ...`
- `alln doctor [--full] [--json]`
- setup/detect commands that touch a source
- `alln ps|kill ...`
- `alln serve [--health --json]`
- `alln serve install` — register/enable the user-level coordinator without the
  Mac app (exact verb finalized in REB-S04; the Works Test uses this command
  verbatim)

There is no public `broker exec` command. Routing through the resident execution
authority is an implementation invariant, not a second way to run work.

Changed machine output:

- `version --json` and health expose compatible coordinator identity/version;
- run/Panel acceptance exposes coordinator ID and journal reference;
- worker states distinguish `queued` from `running`;
- doctor distinguishes client reachability, coordinator readiness, and
  coordinator-observed source readiness.

New errors:

- `COORDINATOR_UNAVAILABLE`
- `COORDINATOR_VERSION_MISMATCH`
- `RESIDENT_REQUEST_REJECTED`
- `RESIDENT_REQUEST_CONFLICT`
- `RESIDENT_ACCEPT_TIMEOUT`

Every error is added to `ContractRegistry` with an agent action, retryability,
and a deterministic exit code. Generated contracts are regenerated from the
registry. The existing `COORDINATOR_UNAVAILABLE` entry is rewritten in the same
pass: its agent action today suggests using the foreground CLI, which after
cutover would recommend the exact fallback this phase deletes. The regenerated
action points only to the one enablement path (`alln serve install` / the Mac
app equivalent) and is non-retryable for spawn attempts.

## Teaching surface

The implementation slices update these existing help topics:

- `team_run_loop`
- `panel`
- `setup_and_auth`
- `current_setup`
- `errors`

Search terms include `sandbox`, `background execution`, `coordinator`,
`resident`, `child CLI`, `permission denied`, `EPERM`, and `Full Access`.

Teaching rules:

- normal recipes do not ask the user to diagnose a host sandbox;
- setup teaches the one background-execution enablement;
- doctor reports whether the resident host is reachable and whether sources are
  ready there;
- help never recommends fake `HOME`, copied credentials, or per-driver state
  redirection;
- `COORDINATOR_UNAVAILABLE` points to one supported recovery path;
- no retired MCP grammar is reintroduced.

## Auth, privacy, and permissions

- Vendor login state remains in each vendor's existing user directory.
- Allnighter neither copies nor rewrites vendor credentials.
- The calling agent receives results and progress, never the coordinator's
  environment or credential material.
- The coordinator uses normal user permissions only.
- Answer-team isolation materializes a tracked, secret-safe source snapshot.
  Untracked/ignored files and `.env*` are excluded unless a future explicit,
  typed attachment contract names a safe file.
- Project registration does not authorize arbitrary roots; every request root
  is canonicalized and matched against registered project truth. A restricted
  client submits the workspace-visible canonical root it is running in; the
  coordinator — not the client — resolves and validates registration.
  Registering a project remains an unrestricted-host prerequisite; there is no
  broker operation for project add.
- Mutating-run write locks remain keyed by canonical repo root and are enforced
  inside the coordinator.
- Cancel/kill remains typed, scoped, identity-checked, and auditable.

## Implementation impact

Version impact: the new request/receipt/operation contracts and the five new
registry errors are additive — no existing contract shape changes meaning — so
this phase is a binary `+0.0.1` bump per shipped slice (one definition:
`AllnighterVersionIdentity.binaryVersion`), not a contractVersion major cut.
If a later slice is forced to break an existing contract shape, that slice
performs the major cut explicitly.

### AllnighterCore

- Add the request, receipt, operation, rejection, and coordinator-compatibility
  contracts.
- Reuse canonical TeamRun/Panel payload types; do not invent parallel result
  JSON.
- Add `queued` where current Panel projections collapse queued and running.

### Engine

- Add durable resident request store and inbox claimer.
- Host generic run and Panel command handlers inside `ResidentCoordinator`.
- Make process ownership originate at coordinator acceptance.
- Reuse `WorkerInvokerFactory`, driver gates, journals, idempotency, and write
  locks.
- Add secret-safe answer snapshot materialization.

### CLI

- Replace production source spawning with broker submission/watch.
- Keep syntax validation and output projection thin.
- Route full doctor/source probes through the coordinator.
- Remove Panel's readiness-based single-source self-fusion containment.
- Fail closed when the coordinator is unavailable; never fall back to direct
  spawn.

### Mac app

- Install/enable the user-level coordinator during setup.
- Present reachability, restart, and version mismatch without exposing plumbing
  during normal use.
- Route app-originated runs through the same request contract.

### iOS

- No new run semantics. Future iOS requests enter the same resident authority
  through the existing Mac-agent transport.

### Drivers

- No sandbox-specific state-directory overrides.
- No change to vendor auth formats.
- Existing manifests and worker runners remain the source-specific boundary.
- New sources receive resident execution automatically.

## Duplicate truth and containment to delete

After cutover:

- delete production foreground worker-spawn assembly;
- delete Panel's "use only readiness-proven models and repeat one model across
  missing seats" containment;
- delete any per-host or per-driver fake-home/state-directory workaround;
- remove client-owned Panel round execution;
- remove status projections that infer `running` before process ownership;
- keep one `alln serve` health/execution state, not separate GUI and CLI daemon
  truth.

## Inference bans

| Junction | Owner | Possible bad inference | Ban | Negative proof |
| --- | --- | --- | --- | --- |
| Client sandbox -> source readiness | Resident source probe | Client receives `EPERM`, therefore source is unavailable | Only coordinator-observed probes determine source readiness | Restricted client + resident source probe remains ready |
| Team resolution -> degraded roster | Team contract | Repeat one ready source to fill unavailable seats | Never change source/model identity without the existing explicit substitution contract | Multi-source Team with one source down fails; roster is unchanged |
| Request file -> accepted work | Broker store | Inbox presence means accepted | Only durable receipt after validation is acceptance | Kill coordinator between inbox write and claim; retry is safe |
| Accepted request -> duplicate run | Idempotency store | Client timeout permits resubmit as new work | Same key + payload returns same canonical ID | Drop first receipt; retry creates no second run |
| Concurrency wait -> running | Process ownership | Task exists, therefore worker runs | `running` requires spawned owned identity | One-slot source with three workers shows one running, two queued |
| Coordinator -> shell | Typed operation registry | Local caller may pass executable/env | Broker accepts only registered typed operations | Arbitrary command/env fields fail schema validation |
| Isolation copy -> safe snapshot | Answer snapshot owner | Repo copy is safe because workers are read-only | Ignored/untracked secrets never enter answer snapshots | Fixture `.env.local` is absent from every seat snapshot |
| Client death -> run death | Resident coordinator | Foreground process lifetime owns work | Accepted work survives client death | Kill submitting CLI; run reaches terminal journal state |
| Client auto-start -> clean environment | Coordinator launch origin | Client may start a missing coordinator | A client-spawned coordinator is never trusted; start is owned by launchd/login-item registration and launch origin is recorded | Coordinator started from a restricted client refuses dispatch; client reports `COORDINATOR_UNAVAILABLE` with the enablement action |
| Catalog presence -> source readiness | Spawn-time observation | Model is listed, therefore it can run now | Readiness is only established by a spawn in the execution environment; catalog listing and past probes are not spawnability | Seat whose vendor is at capacity fails (or is re-resolved under the substitution contract) with a classified capacity reason, never reported as ready |
| Coordinator restart -> in-flight loss | Drain/re-adopt contract | Version restart may drop running work | Accepted work is drained to terminal state or re-adopted from durable stores across coordinator restart | Restart coordinator mid-run; run reaches terminal journal state with no orphaned source process |

## Ordered slices

### REB-S00 — Contract and route

- Land this feature packet and route it from `AGENTS.md` and the phase board.
- Record the Codex incident and the one-authority decision.
- No runtime claim.

### REB-S01 — Broker envelope and atomic inbox

- Add Core request/receipt/error types.
- Add permission-restricted rendezvous and durable acceptance store.
- Prove claim, retry, conflict, crash-before-accept, and size/schema rejection.
- Prove hostile-rendezvous behavior: pre-created wrong-owner directory,
  symlinked path, and wrong-mode root each fail closed.
- **Prove restricted-client writability:** a Codex workspace-write client can
  create a request and atomically rename it into the rendezvous inbox, and can
  read its receipt and replies. If it cannot, the fallback channel becomes an
  Open question and later slices do not delete direct spawn.
- Extend `alln serve --health --json` with broker readiness, including the
  rendezvous ping path.

### REB-S02 — Generic resident Team execution

- Move production Team worker execution behind resident acceptance.
- Make `alln run` submit, stream, and render the existing TeamRunJSON.
  **Landed:** the resident projects `RunEvent` values into a cursor-ordered,
  client-readable rendezvous channel; `alln run --stream` renders those NDJSON
  events and the terminal TeamRunJSON without client-owned source execution.
- Make coordinator process ownership and per-source queues authoritative.
- Delete the direct-spawn path **for the Team-run surface only**, gated on the
  REB-S01 restricted-client writability proof. Panel rounds and doctor/setup
  probes still spawn foreground until REB-S03; the global "no second spawn
  path" invariant is asserted at the end of REB-S03, not here.
- Interim ship gate: no release is described as broker-ready between S02 and
  S03. During that window, Panel and doctor invoked from a restricted client
  fail closed with the documented sandbox truth instead of foreground-spawning
  into the known failure mode.

### REB-S03 — Panel and source probes

- Move Panel round ownership into the coordinator.
- Route full doctor/setup probes through the coordinator. **Landed:** `alln doctor`
  submits a typed source-probe request; only the resident Engine service can
  resolve or smoke vendor CLIs and persist the resulting readiness record.
- **Landed:** `alln detect` is the same typed resident source-probe path. The
  coordinator persists the detection cache and assembled Team before returning
  the legacy command's presentation records to the client.
- **Landed:** Panel start, round, status, watch, and done submit/query the
  resident authority. Client hosts no longer read or reconcile the panel
  journal, and `panel done` cannot mutate PanelState outside its owner.
- **Landed:** `alln ps` reads the coordinator-owned process snapshot over the
  typed query channel, including the caller's existing project scope.
- **Landed:** `alln kill` submits a typed cancel to the coordinator, including
  its existing scoped `--all` semantics; only the coordinator signals an owned
  process tree and writes its terminal truth.
- Remove readiness self-fusion containment.
- Add queued/running truth and per-seat process ownership.
- Fix answer snapshots to exclude ignored/untracked secrets.
- Assert the global one-authority invariant: after this slice, no production
  code path outside the coordinator can spawn a vendor source.

### REB-S04 — Installation and version lifecycle

- Finalize and ship `alln serve install` as the app-independent enablement
  path; the Mac setup path calls the same mechanism. **Landed:** it writes and
  bootstraps only `com.allnighter.resident-coordinator`, invokes the installed
  `alln serve` binary, preserves the installer's PATH for vendor CLI discovery,
  and performs no implicit registration from any other command. It returns
  success only after the live coordinator reports the matching binary release,
  exact build Git SHA, and contract identity. When durable work is active it writes a drain request,
  stops new broker dispatch, waits for terminal journals, then exits for
  launchd to load the refreshed installed image. It never terminates active
  work merely to refresh code. `scripts/rebuild_cli.sh` is the one normal
  development refresh command: it builds under
  `~/Library/Developer/Allnighter/CLI`, updates the PATH install, refreshes the
  coordinator, and reports health without leaving the resident executable in a
  checkout under `~/Documents`.
- Add launchd restart and client/coordinator compatibility handshake.
- **Landed:** every signed request carries its client binary release, exact
  build Git SHA, and contract identity. The resident rejects any mismatch
  before dispatch with the existing
  `COORDINATOR_VERSION_MISMATCH` contract error and one repair action.
- **Landed:** drain/restart behavior for binary updates. Accepted work remains
  represented by its durable run or Panel journal until terminal; not-yet-
  accepted inbox work stays recoverable for the replacement coordinator.
- Make unavailable/mismatch recovery one action and agent-readable.

### REB-S05 — Host matrix and closeout

- Run the same acceptance suite from Codex workspace-write, Claude, Cursor,
  Grok, a normal terminal, and the Mac app.
- Include a CLI-only arm: enable and run the coordinator on a machine with no
  Mac app installed.
- Prove no host requires Full Access for Allnighter source execution.
- Prove distinct sources stay distinct.
- Update help, generated contracts, doctor, setup, and GUI presentation.
- Remove obsolete foreground execution and incident containment code.

## Works Test

Setup:

1. Enable the coordinator with `alln serve install` (the same command named in
   §CLI surface), then verify with `alln serve --health --json`.
2. Configure at least three distinct authenticated source CLIs.
3. Start Codex in its ordinary workspace-write sandbox with no Full Access.
4. Select a Panel whose roster names those distinct sources.

Gesture:

```text
alln panel start --doc <spec> --project <project>
alln panel round --panel <id> --json
```

Assertions:

- client reaches the resident coordinator without sandbox escalation;
- roster identities are unchanged from selection through terminal results;
- at least three distinct source CLIs actually spawn outside the Codex sandbox;
- queued workers are queued and only owned processes are running;
- every source child appears in `alln ps`;
- each seat persists progress and a terminal report/reason;
- client termination after acceptance does not terminate the Panel;
- round and status JSON return to the sandboxed client without reading the
  user's application-support directories;
- no vendor credential or state directory is copied or remapped;
- no `.env*` or ignored/untracked secret enters a seat snapshot;
- the same commands still work from Claude, Cursor, Grok, terminal, and app;
- Phase target remains unmodified by answer workers.

Negative assertions (fail-closed proof):

- a request with an invalid or missing client proof is rejected;
- a request whose root is not a registered project is rejected;
- a second mutating run on the same canonical repo root fails on the write
  lock, not by queueing silently;
- a pre-created wrong-owner or symlinked rendezvous root causes the
  coordinator to refuse the rendezvous, not adopt it.

Proof commands after implementation:

```text
swift test --package-path Packages/AllnighterCore --filter ResidentExecution
swift test --package-path Packages/AllnighterCore --filter Panel
bash scripts/check.sh
```

Two proof obligations exceed `swift test`'s single-process reach and are
scripted (in `scripts/check.sh` or a dedicated harness):

- **client-death survival:** SIGKILL the submitting CLI after acceptance and
  assert the run reaches its terminal journal state;
- **CI arm:** the full hostile-host matrix needs real authenticated vendor
  CLIs and runs on a dogfood machine, not CI. CI covers the broker itself
  (claim, retry, conflict, hostile rendezvous, client-kill survival) with a
  mock source driver; the mock driver never ships in a release binary.

Missing proof today: no resident command broker or hostile-host harness exists.
The phase is not Ready for Implementation until REB-S01 request authentication
and the macOS background enablement mechanism are reviewed.

## Done when

- All production vendor invocations originate from the resident coordinator.
- No calling agent needs Full Access to run configured Allnighter Teams.
- Foreground CLI, Mac app, and future remote clients share one typed execution
  contract and canonical result projections.
- Source readiness is measured in the execution environment.
- Selected source identity is never silently collapsed or substituted.
- Process ownership, queue state, cancellation, and recovery are truthful.
- Answer isolation excludes ignored/untracked secrets.
- Coordinator setup and recovery require no sandbox diagnosis from the user.
- The hostile-host Works Test and normal-host regression matrix are green.
- Generated contracts and teaching surfaces describe only shipped behavior.

## Decisions made at implementation review

The following decisions close the pre-REB-S01 trust and lifecycle gates. They
are deliberately narrow and fail closed; a later revision may widen them only
with a Works Test that preserves these boundaries.

1. **Client proof:** coordinator bootstrap creates one random 256-bit,
   per-install broker secret in the hardened rendezvous root (mode `0600`).
   A foreground `alln` client reads it only while signing its canonical typed
   request with HMAC-SHA256; it is never copied into a project, passed to a
   vendor CLI, or used as a vendor credential. A coordinator-start nonce is
   also signed, so a request for an earlier coordinator cannot be replayed at a
   later one. The local-user account is the trust boundary; this proof protects
   the broker protocol from malformed/stale/unauthenticated request files, not
   from another process already trusted as the same macOS user.
2. **Enablement:** background readiness requires the one explicit
   `alln serve install` action (or the Mac app action that calls the exact same
   implementation). Clients never auto-start a coordinator.
3. **Compatibility:** the initial shipped range is exact binary release, build
   Git SHA, and contract equality. The build SHA matters because several source
   commits can legitimately share a human release label. A mismatch rejects
   dispatch with a typed error and one
   recovery action. Automatic drain/restart is deferred until it has a
   re-adoption Works Test; it is not silently attempted in the first broker
   release.

## Open question

Should the coordinator auto-substitute a **resolver-chosen** seat on a
   capacity-classified spawn failure (fail fast, re-resolve, record
   `original -> substitute (capacity)` provenance in the roster), instead of
   tracking vendor availability between runs? Availability is time-windowed
   state alln cannot observe except at spawn, so tracked state rots; spawn-time
   fallback is self-healing. Constraints if adopted: user-pinned models never
   auto-substitute; a substitute may not duplicate an already-seated model
   while distinct sources remain; substitution is always disclosed in the
   result. Policy mechanics belong to Rate Limit Continuity (which owns
   capacity classification); this phase only requires that spawn failures be
   capacity-classified and that the broker is the single place a future
   substitution policy would live.

Questions 1–3 affect local trust and permission posture. They must be decided
before REB-S01 implementation; they do not change the one-authority decision.
Question 4 is a product-policy ruling that can land any time before REB-S03.
