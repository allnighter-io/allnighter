# Worker → Agent Migration — Handover

Written 2026-07-29 by the outgoing lead, after a session that produced 47 commits
and wasted most of a night. Read the **Lessons** section before touching anything;
it is the part with actual value.

Packet: `docs/archive/phases/Worker_To_Agent_Migration.md`
Meaning map (adjudicated, trustworthy): `docs/archive/phases/Worker_To_Agent_Migration_S00_Map.md`

---

## 1. STOP — the working tree is broken right now

`HEAD` = `dfcf98b1`. The tree has **28 build errors** and uncommitted work.

```
 M  ThreadSendCLI.swift, WorkThread.swift, AgentChatCoordinator.swift,
    AsyncTeamService.swift, ResolvedRunInvocation.swift, RunService.swift,
    ThreadSendCoordinator.swift, WorkThreadTests.swift
 ?? RetiredWorkerKeysMigration.swift          ← DO NOT RUN. See §5.
 ?? RetiredWorkerKeysMigrationTests.swift
```

Two clean options:

**A. Discard and restart from a green base** (recommended — nothing here is precious):
```bash
git stash push -m "wta-incomplete" -- Packages
# keep the migration drafts:
git stash show -p stash@{0} > /tmp/wta_incomplete.patch   # optional
swift build --build-tests --package-path Packages/AllnighterCore   # must be 0 errors
```

**B. Finish the in-flight rename.** `ResolvedRunInvocation.workerId` →
`pinnedModelId` is half-done. The declaration, `RunService`, and
`AsyncTeamService` are updated; the call sites in
`ResolvedRunInvocationTests.swift` (~101, 109, 125, 141, 172, 175, 184, 337) and
`ReproduceCommandTests.swift` (~131) are not. Fix those, build green, commit.
**Do not touch `ResolvedRunSeat.workerId`** — different thing (see §4).

---

## 2. Where the migration actually stands

**Done and green (47 commits, `c22be3a3..dfcf98b1`):**

| area | state |
| --- | --- |
| `Worker` → `Agent`, `WorkerStage` → `AgentStage` | done |
| `TeamWorkerSpec` → `TeamAgentSpec` | done |
| `WorkerSpec` → `SeatSpec` | done (founder call: N seats pinned to one model) |
| `TeamPreset.workerSpecs` → `agentSpecs` | done, incl. persisted key + Mac |
| `WorkerInfo` → `AgentInfo`, `WorkerChatCoordinator` → `AgentChatCoordinator` | done |
| `WORKER_*` error codes → `AGENT_*` | done |
| Teaching surface (reflex line, flag summaries, help topics, doctor, run identity) | done |
| **`Agent.agentId`** — stable roster-seat id | done, `39ef3ece` |

`Agent.agentId` is the one slice with real design value. Before it, a run had no
stable seat identity: `Agent.id` is `"modelId#index"`, so a model substitution
moved the seat identity with it. `TeamResolver.makeAgent` had the roster row in
scope and dropped `row.id`. Now it carries it, and a test proves `modelId`
changes under substitution while `agentId` holds.

**Not done — this is ~90% of what remains, and it is ONE job:**

```
workerId              793      ← public wire + 827 values in live user files
workerAnswers         229      ← public wire
devWorkerId           291      ← relay.json on disk
pmWorkerId            273      ← relay.json on disk
workerChat            132      ← check: pending JSON enum rawValue?
producedByWorkerId     50      ← public wire
explicitWorkerIds      33
workerSpecs            39      ← legacy PanelPreset/WorkflowPreset only, A3
preferredWorkerIds     21
```

All of it is **persisted wire keys**. It is gated behind one thing: the on-disk
migration for **1,281 live files** under `~/Library/Application Support/Allnighter/`
(Runs 993, Threads 203, Relays 60, Panels 14, Recipes 7, ProjectReadiness 2,
Pending 1).

---

## 3. LESSONS — what not to do

These are the outgoing lead's actual failures, in the order they cost the most.

### 3.1 Don't run the full suite per round

The single biggest waste. `swift test` = ~150s. `swift test --filter <3-4 classes>`
= **~2s**. For a rename the product does not change, so the full suite is ~99%
irrelevant — and worse than useless: nearly every failure diagnosed all night came
from tests unrelated to the change (flaky loopback sockets, a poisoned lane,
orphaned `xctest`). Filtered runs skip all of it.

Full suite **once at closeout**. Never per round.

### 3.2 Don't batch. One symbol, one commit.

Founder, repeatedly: *"do one function / file name etc. at a time. commit
proceed... commit proceed."*

Small commits are not about tidiness — they buy **free attribution**. The lead
burned real time stashing a 33-file diff to prove a crash was pre-existing. With
one symbol per commit that question answers itself and `git bisect` is free.

The lead's recurring failure was **re-expanding scope** every time he "made it
efficient." Default to smaller than feels worthwhile.

### 3.3 An item is a symbol PLUS its call sites — this killed the last run

The final failure, and it wasted an entire Sonnet 4.6 capacity window for **zero
commits**. The lead queued `ResolvedRunInvocation.workerId` as one line. It
cascades into `RunService`, `AsyncTeamService`, and two test files. The seat could
not produce a green build, so it could not commit, so it worked for 15 minutes and
committed nothing.

**Before queueing any item, run:**
```bash
grep -rn "<symbol>" --include='*.swift' . | grep -v '/.build/'
```
That list IS the item. Put it in the handover.

### 3.4 The lead is the bottleneck — automate dispatch

Commit timestamps tell the story: five commits at 04:15, then a **19-minute gap**
because the lead was writing the next handover while the seat idled. Gemini did
5 items in ~1 minute.

Fix: keep a **deep queue** of pre-written handovers and an auto-dispatcher that
fires the next one within seconds of `awaitingPM`. `/tmp/wta_autodispatch.sh` in
this session did that correctly — reproduce it. Never let the seat wait on a human
writing prose.

Also: don't cap `--max-rounds` low. A `--max-rounds 3` cap silently stopped a
relay mid-queue and looked like a stall.

### 3.5 A seat's report is never the completion signal — the commit is

Both agy AND Sonnet end their turn mid-wait if told to run a long command
("I will wait for the build…" → turn over, work lost). Under `pilot` the relay
then restarts it forever.

So: the seat's last instruction is `git commit`. Watch **git**, not the relay
report. This also makes rounds idempotent — a respawned seat sees its own commit
and has nothing to redo.

Corollary: give seats **build**, never **test suite**. Builds are seconds.

### 3.6 Let the seat reason; don't hoard judgment

The lead treated the seat as a pure transcriber and pre-decided everything, which
forced rounds to be big. The seat reasons fine: Gemini independently found
`WORKER_NOT_QUIESCENT` — a code the lead's spec had missed — correctly classified
it as process-context, and stopped to report rather than guessing.

Give it the item, the vocabulary doc, and the rule. Let it decide. One small
commit is cheap to revert if it decides wrong.

### 3.7 Don't do the work yourself with sweeps

`perl -pi` / `sed -i` across files is exactly wrong when you have a fast seat.
The lead did it twice; the second time turned 2 build errors into 28 and had to be
reverted. Hand it over.

(Also: BSD `sed` does not support `\b`. A sweep silently no-op'd while the script
printed "rewrote". Verify diffs, not echo output.)

### 3.8 Gate hygiene, learned the hard way

- **`swift build` does NOT compile test targets.** Use `--build-tests`. A whole
  round was scoped against a discriminator that couldn't see test files.
- **`swift test --package-path Packages/AllnighterCore` never touches
  `Apps/AllnighterMac`.** It is an Xcode target. The Mac app went unverified all
  session, and a Mac test had been failing silently since the vocab cutover. Add
  `xcodebuild build`/`test` to closeout.
- **Sweep orphans before gating.** Abandoned `swift-build`/`swift-test`/`xctest`
  processes hold the SwiftPM lock and present as a slow build, not a hang.
  `pkill -9 -f xctest; pkill -9 -f swift-build; pkill -9 -f swift-test`.
- **Never run two builds concurrently** — they contend on the same lock.

---

## 4. Traps in this codebase (verified — trust these)

- **`worker` means three different things.** Roster seat (→ `agent`), bench model
  (→ `model`), process/warm-pool (→ leave). Decide by the **declared type**, never
  the name. Example, 100 lines apart in `AppModel.swift`:
  `worker: Model` → `model`; `expandedWorkers: [Agent]` → `expandedAgents`;
  `currentWorkerSpecs` → persisted, leave.
- **One wire key, two shapes, one document.** `teamRun.workerId` is a bare model
  id (`"model_sonnet"`); `workerAnswers[].workerId` is a seat composite
  (`"model_sonnet#0"`). A blanket rename files a model id under `agentId`.
- **`ResolvedRunInvocation.workerId` (model pin) vs `ResolvedRunSeat.workerId`
  (run member)** — same token, opposite meaning, produced by the same function
  into the same returned value.
- **Stored vs computed decides safety.** Stored property in a `Codable` type with
  no custom `CodingKeys` → the property name IS the JSON key on disk. Computed
  vars, funcs, type names, parameter labels → never serialized, always safe.
- **Four properties are named `workerSpecs`.** Only `TeamPreset`'s (element type
  `[TeamAgentSpec]`) was in scope; `PanelPreset`/`WorkflowPreset`/
  `TeamAssembler.Assembled` carry `[SeatSpec]` and must not move.
- **`team_preset_default.json` is a `PanelPreset` fixture**, despite the name.
  The lead assumed TeamPreset and broke a round-trip test.
- **Layer E never moves:** `WarmWorker*`, `ProcessOwnership*`, `WorkerRunner`,
  `WorkerInvoking`, `WorkerInvocation`, `WorkerRunResult`, `WorkerStreamEvent`,
  ownership `kind: "worker"`, the on-disk `workers/` artifact directory.

---

## 5. How to finish — the remaining work is one job

### Step 1 — get to a green base
See §1. Do not build on 28 errors.

### Step 2 — review the migration draft (BLOCKING, human judgment)

`RetiredWorkerKeysMigration.swift` (103 lines, uncommitted) rewrites keys across
**1,281 files of real user history**. It was drafted by a seat and has never been
reviewed or run. Requirements before it is allowed near the real directory:

- idempotent (safe to run twice; skips already-migrated files)
- tested against a **temp support root only** — set `ALLNIGHTER_SUPPORT_DIR`
- handles: `workerAnswers`→`answers`, `workerId`→`agentId`,
  `producedByWorkerId`→`producedByAgentId`, `devWorkerId`→`devModelId`,
  `pmWorkerId`→`pmModelId`
- back it up first: `cp -R ~/Library/Application\ Support/Allnighter ~/Desktop/alln-backup`

### Step 3 — additive first, then flip

Order matters. Do NOT rename keys before the migration exists.

1. Add `agentId` to `AnswerInfo` **alongside** `workerId` (additive; nothing breaks).
   Populate from `Agent.agentId`.
2. Write the round-trip test: old-shape fixture still decodes; new shape carries
   `agentId` + `modelId`.
3. Land + run the migration.
4. Then flip, one symbol + call sites per commit:
   `workerAnswers`→`answers`, `AnswerInfo.workerId`→`agentId`,
   `producedByWorkerId`→`producedByAgentId`, `devWorkerId`→`devModelId`,
   `pmWorkerId`→`pmModelId`.
5. `ContractRegistry.contractVersion` is a **MAJOR** bump (its own rule: renaming
   a command/flag/key = major). Then `alln dev export-contracts`.
   `--check` fails with `CONTRACT_DRIFT` / `CONTRACT_VERSION_NOT_BUMPED` if you forget.
6. Extend `RetiredVocabulary` deny-list with the old key spellings — **in the same
   commit** as the prose rewrite, or `HelpTopicRegistryTests` goes red immediately.

### Step 4 — closeout (once)

```bash
pkill -9 -f xctest; pkill -9 -f swift-build; pkill -9 -f swift-test
swift test --package-path Packages/AllnighterCore
xcodebuild build -project Apps/AllnighterMac/AllnighterMac.xcodeproj -scheme AllnighterMac -destination 'platform=macOS'
xcodebuild test  -project Apps/AllnighterMac/AllnighterMac.xcodeproj -scheme AllnighterMac -destination 'platform=macOS'
bash scripts/check.sh
```

Note `scripts/check.sh` is red at the GUI Visual Proof Gate for reasons predating
this work. Pure renames to view files qualify for `scripts/gui_proof_waive.sh`.

---

## 6. Operating the seat (this part worked — copy it)

```bash
# 1. deep queue of pre-written handovers, one item per commit
/tmp/wta_queue/NN_name.md

# 2. relay with a HIGH round cap
alln pair pilot start --doc <packet> --project prj_8ded5a42 \
  --dev-model model_agy_sonnet --max-rounds 40 --json

# 3. auto-dispatcher: fires next queue within 10s of awaitingPM
#    (see /tmp/wta_autodispatch.sh — reproduce it)

# 4. watch GIT, not the relay report
```

**Capacity:** agy has two buckets — Google (`model_gemini`, `model_gemini_pro`)
and non-Google (`model_agy_opus`, `model_agy_sonnet`). When one throttles, reseat
on the other; Sonnet is the economical non-Google choice. Google bucket resets
exactly 5h after the block. Models were re-added in `dfcf98b1`, so
`bash scripts/rebuild_cli.sh` first or `alln` won't list them.

**Every handover must contain:** the item + its grepped call sites, the build
command (never a test suite), the commit message, and "do not wait for me between
items."

---

## 7. Bugs found and fixed en route (unrelated to the rename, all real)

- `eac238ec` — **agy driver discarded every answer.** `AntigravityTranscript.split`
  took the last `PLANNER_RESPONSE`, but agy injects a `SYSTEM_MESSAGE` after the
  model answers and the model politely replies; that pleasantry became the answer
  while the run settled `done`. Same probe: 183s → 6.7s, correct output.
- `57ed2d0b` — `ps` hid identity-alive worker survivors (CLP-S03 regression
  against the documented RLR-S04a requirement).
- `fa0d4ed4` — `RunWriteLockTests` wrote lanes into the **real** support root; one
  interrupted run left a live `xctest` holding `v1:test` and poisoned every later
  run. Also replaced a fatal `first!` that killed all ~2,400 tests on one failure.
- `bfaf95c2` — a Mac test failing silently since the vocab cutover, in a target no
  gate ran.

**Still open, tracked, not done:** ~20 test classes still write to live user data
(`ALLNIGHTER_SUPPORT_DIR` unset); the `xctest` process leak; `scripts/check.sh`
does not invoke `xcodebuild`.
