# Worker → Agent Migration

Status: **Open — destination locked; method locked; execution starting at WTA-S00**
Owner: code SSOT for runs (`RunService.swift`, `TeamCatalog` / `TeamWorkerSpec`,
`TeamRunJSON`); standing vocabulary `docs/workflows/Product_Vocabulary.md`
Created: 2026-07-28
Updated: 2026-07-28
Next work order: **WTA-S00** (inventory + id-meaning map) before any rename PR

Process:
`docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md` →
`docs/operations/Execution-Playbook.md` (Orchestrated mode)

Related:
- Standing nouns: `docs/workflows/Product_Vocabulary.md`
- User-facing retirement already shipped (GUI / `--model` / `RetiredVocabulary`):
  commit history on `feat/design-chain` (vocab cutover)
- Prior hard cutover pattern: `docs/archive/phases/Language_Cutover.md`
- Shared skills context: `docs/phases/Worker_Skill_Sharing.md`

---

## Founder Intake

**Raw request:** The bilingual fence (humans say **agent**, machines say
**worker**) is not an end state. Messy means wrong. Rebuild toward one language.
Painful now; dividends if the project succeeds. Go careful and slowly. No stupid
global grep that breaks the floor.

**Product value:** Agents and humans share one mental model. Reading
`TeamRunJSON`, writing a seat, pinning a model, and editing a skill stop
requiring a translation table. Fewer lies in help, fewer false-precision renames,
less "is this `modelId` or `agentId`?" thrash.

**Trusted workflow slice (end state):**

```text
staff Team → agents[] = { id, modelId, skillId }
→ alln run --model <modelId>  (pin only)
→ TeamRunJSON.answers[] report agentId + modelId
→ count = N agents; never workers; never "N models" for seat count
```

**Current truth owner (until cutover):** `TeamWorkerSpec`, `workers[]` /
`workerId` in `TeamRunJSON` and journals — machine layer only; never teach to
humans (`Product_Vocabulary.md`).

**Risk:** Schema / on-disk journals / NDJSON / iOS mirrors / fixtures. Zero
external users today → prefer **hard cutover** (no forever aliases) *within each
slice*, but **never** one mega-PR. No privacy/credentials change.

**Blocking questions:** None. Destination, method, and role split are all locked
below.

---

## Why what we have is wrong

`worker` is a junk drawer for three different identities:

| Need | Today (often) | Should be |
| --- | --- | --- |
| Which roster seat? | `workerId` / `TeamWorkerSpec` | **`agentId`** |
| Which AI actually ran? | also `workerId`, sometimes `modelId` | **`modelId`** (always) |
| Which CLI subprocess / warm pool? | `WarmWorker`, ownership `kind: "worker"` | **`session` / process** — different layer |

One word, three jobs.

**The sharpest reason to do this at all:** this product's primary reader is a
coding agent. The whole thesis behind `alln menu --json`, agent-first schemas,
and help fidelity is that the machine surface *is* the readable surface. A
machine layer that teaches a noun the human layer already retired is not
cosmetic debt — it is a fidelity bug in the thing we sell. The bilingual fence
imposes a permanent translation table on the reader we most care about.

**The second reason:** cost is monotonically increasing and external users are
zero. Doing this later is strictly worse. Never doing it means the translation
table is forever.

The user-facing retirement (`--model`, "N agents", Edit skill) was the right
*fence*. It is not the destination. Keeping overloaded `workerId` forever is
scaffolding, not design.

---

## Destination (locked — first principles)

Four product nouns. Nothing else.

```text
Team     = named lineup you send to
Model    = which AI mind          (catalog id; CLI --model)
Skill    = which instructions     (skillId; skill.md body)
Agent    = one staffed seat       (model + skill on a Team)
```

**Machine JSON mirrors product nouns.** No bilingual fence at end state.

```text
Team {
  agents: [{ id, modelId, skillId, … }]
}

Run {
  answers: [{ agentId, modelId, status, output, … }]
  // agentId = which roster seat was supposed to run
  // modelId = which model actually thought (after fallback / triangulation)
}

CLI pin:   --model <modelId>     only
Count:     N agents
Edit:      Edit skill
Process:   Session / ProcessOwnership — never "agent", never "worker"
```

### Explicit non-goals

- Do **not** rename `WarmWorker` → `Agent*` (wrong layer; increases confusion).
- Do **not** invent a third id that is neither agent nor model ("member id" without
  a mapping).
- Do **not** keep decode-forever aliases after a slice's hard cut (zero users →
  cut clean *per slice*; temporary `CodingKeys` only while a single PR is in
  flight if needed, then delete).
- Do **not** global-grep `worker` → `agent`. Context decides; process/session
  stays process/session.

Shortcut (unchanged): *Model at rest. Agent at work (model + skill).*

---

## Value ordering (read before picking up any slice)

The defect is **not the word**. The defect is that one field carries three
meanings. That is an *identity* defect, not a *naming* defect.

Therefore:

> **S00 + S01 carry substantially all of the value. S02–S06 are the cheap
> cosmetic tail.**

- If we only ever ship S00 and S01, the real problem is fixed.
- If we ship S02 before S01, we make the codebase **confidently wrong**:
  an `agentId` that still sometimes holds a model id is *worse* than `workerId`,
  because it reads as authoritative. False precision beats honest vagueness only
  in slide decks.

**This ordering is not negotiable by an implementing agent.** Do not reorder to
"get the big mechanical win first." The mechanical win is the part that is safe
*because* the meaning work already happened.

---

## Migration law (how we don't break the floor)

### Law 1 — The unit of work is one **symbol**, not one file

"One file at a time" is the wrong unit for a statically-typed compiled language.
Rename `TeamWorkerSpec` in one file and the build is red until every call site
moves (101 occurrences as of 2026-07-28). A file-sized slice cannot compile, so
it cannot be verified, so it cannot be committed.

The correct unit:

```text
one symbol  →  all call sites  →  build + focused tests green  →  commit
```

The **compiler is the safety net**, not the file boundary. Slow-and-careful
means *few symbols per PR*, not *partial symbols per PR*.

### Law 2 — Two classes of edit, two different levels of care

| Class | Examples | Safety net | Who may do it |
| --- | --- | --- | --- |
| **Compiler-verified** | Swift type names, property names, enum cases, function params, call sites | `swift build` — a miss is a red build | Delegable to a cheap executor |
| **Compiler-blind** | `CodingKeys`, JSON string keys, fixtures, on-disk journals, NDJSON event names, `WORKER_*` code strings, help text, docs | **Nothing, by default** — a miss compiles and ships a silent wire break | Lead writes the round-trip test *first*; only then may an executor edit |

This is where "go slowly, one at a time" actually earns its keep. Never let an
executor touch a compiler-blind surface that has no failing-first test guarding
it.

### Law 3 — No global replace

Inventory → targeted edits → tests for that slice → green for touched packages →
commit. Context decides; `sed -i 's/worker/agent/g'` is the named failure mode of
this packet.

### Law 4 — Name by meaning before renaming the string

If a field today is sometimes a model id and sometimes a seat id, **split or
document** before the rename PR. See Value ordering above.

### Law 5 — Hard cutover inside a slice

No "accept `--worker` and `--model`." No compatibility shim. No dual-decode. User
flags already retired; machine keys follow the same rule once their slice ships.

### Law 6 — Regenerate, don't hand-edit

`docs/generated/alln/*` after contract changes (`alln dev export-contracts`).

### Law 7 — Leave archives alone

Archives / qa snapshots / mvp history stay as written. Living docs + code +
fixtures that still round-trip must move.

### Law 8 — Teaching surface ships in the same slice

Any slice that changes agent-visible JSON or error codes also updates
`HelpTopicRegistry`, `RetiredVocabulary`, and recipes. A renamed key that help
still teaches by its old name is a new lie, not a smaller one.

### Law 9 — WIP limit: one open slice

The real risk in a migration this size is not a broken floor. It is the packet
sitting **half-migrated for weeks** while feature work lands in the same files.
Half-migrated is worse than either end state — it doubles the vocabulary instead
of replacing it.

- Exactly **one** WTA slice may be open at a time.
- A slice that cannot land in a single working session is too big — split it.
- Do not start feature work in a surface with an open WTA slice.

---

## Orchestration (who does what)

Execution-Playbook **Orchestrated** mode. Three roles, assigned by whether the
work requires *judgment about meaning* or *transcription under a checker*.

| Role | Seat | Owns |
| --- | --- | --- |
| **Lead** | Opus (this session) | Slice boundaries, all meaning calls, schema shape, writing compiler-blind guard tests first, accepting/rejecting every executor round, commits |
| **Hard initial work** | Sonnet (`model_sonnet`) | S00 evidence gathering and S01 implementation against a lead-written spec — the parts that need real code comprehension but not product authority |
| **Volume execution** | Gemini (`model_gemini`, `agy`) via `alln run` | Compiler-verified symbol renames and call-site propagation from a lead-supplied destination table |

### Slice → seat map

| Slice | Seat | Why |
| --- | --- | --- |
| S00 inventory | Sonnet gathers evidence, **lead adjudicates** | It can enumerate every occurrence with context; it must not decide the bucket. A wrong bucket here gets baked into ~900 renames and nobody sees it. |
| S01 split pins | Sonnet, lead-specified | Real design: new fields, new semantics. |
| S02 roster rename | **Gemini** | Compiler-verified, high volume, zero judgment. Ideal executor work. |
| S03 contract major | **Split** — lead designs schema + writes round-trip test; Gemini propagates | Compiler-blind surface (fixtures, `CodingKeys`). |
| S04 engine consumers | **Gemini** | Compiler-verified. |
| S05 Mac + iOS presenters | **Gemini**, but see GUI note below | Compiler-verified, with an extra gate. |
| S06 teaching scrub | Sonnet drafts, **lead verifies** | String-keyed; "is this agent-facing?" is a judgment call. |

### The acceptance gate (why delegation is safe here)

This migration is unusual: it has an **objective oracle**. Most refactors don't.
Every executor round is accepted or rejected by a deterministic check, with no
agent judgment in the verdict — which is exactly the project law about preferring
deterministic checks over recurring agent judgment.

Per round, all three must hold:

```bash
swift build --package-path Packages/AllnighterCore          # compiles
swift test  --package-path Packages/AllnighterCore          # focused tests green
grep -roE '<OldSymbol>' --include='*.swift' . | grep -v '/.build/' | wc -l   # == 0
```

Anything less than all three = round rejected, no partial credit.

### The seat's report is NEVER the completion signal — for any seat

Originally filed as an agy quirk. It is not. **Sonnet hit the identical failure
mode** on WTA-S01a: it backgrounded `swift test`, said it was waiting for the
result, and its turn ended there — work done, nothing confirmed, nothing
committed.

The difference is only in how the failure presents:

| seat | what you see |
| --- | --- |
| agy (relay-driven) | turn ends → relay restarts it → infinite loop, visible as burned sessions |
| a subagent | turn just stops, quietly, with the work uncommitted |

Both leave the same state: correct edits, no proof, no commit. So the rule is not
"work around agy". The rule is:

> A delegated seat's *report* is never the completion signal. **The commit is.**
> The lead always runs the gate.

Apply the commit-as-signal protocol below to every delegated seat regardless of
vendor or tier.

### Seats get edits only — the lead runs the gate

**An agy (Gemini) seat cannot run the acceptance gate itself.** agy launches a
long command (`swift build`, `swift test`) as a background task, emits "I will
wait for it to complete", and the turn then ENDS — agy has nothing further to
stream. Under `alln pair pilot` the relay restarts the dev turn from scratch,
forever.

Measured on WTA-S02a (2026-07-28): one round burned **4 agy sessions on a
5-minute restart cadence**, 1182s elapsed, `commitsSinceBaseline: 0` — while the
code edits themselves had been completed correctly in the first few minutes. The
seat could never reach its own verify-and-commit step.

Symptom to recognise fast: repeated new session dirs under
`~/.gemini/antigravity-cli/brain/` at a fixed interval, all starting from the
same prompt, with `commitsSinceBaseline` stuck at 0.

#### The fix: one task, commit as the completion signal, watcher on git

Do **not** solve this by having the executor produce edits and leaving the lead
to poll a dirty working tree — that leaves no completion signal at all, and a
paused seat is indistinguishable from a finished one.

Instead (founder, 2026-07-28):

```text
1. Give the agy seat exactly ONE task, with no verification burden.
2. Its last instruction is: git add <explicit paths> && git commit.
3. A watcher watches git. The COMMIT is the completion signal.
4. On commit, the LEAD runs the gate: swift build + swift test + grep count.
```

Why this works: `git commit` is instantaneous, so nothing long-running is left in
the seat's critical path and the turn completes naturally instead of dying
mid-wait. The commit is durable, atomic, and observable without the seat
reporting anything — which matters precisely because the seat's reporting is the
unreliable part.

Committing before verification is normally wrong; here it is correct, because the
seat *cannot* verify, this is a feature branch, and the lead gates within
minutes. A broken commit caught immediately beats an unobservable working tree.

Watcher (one notification, ends on its own):

```bash
BASE=$(git rev-parse HEAD)
until [ "$(git rev-parse HEAD)" != "$BASE" ]; do sleep 10; done
```

Consequences for every delegated order:

- The work order must **not** ask the executor to run the build, the suite, or
  any multi-minute command.
- The executor's final step is the commit, and nothing after it.
- The acceptance gate stays lead-owned — enforced structurally, not by asking.

#### Third failure mode: orphaned builds deadlock the SwiftPM lock

Each restarted agy turn left its background `swift build`/`swift test` running.
Those orphans (`ppid 1`) survive the seat and **hold the SwiftPM lock**, so the
lead's own gate run then blocks indefinitely at 0% CPU — looking exactly like a
slow build rather than a deadlock. Measured: 7 swift processes, all 0.0% CPU,
oldest 21m52s, blocking a gate that should take ~4 minutes.

Before gating any agy round, sweep orphans first:

```bash
ps -eo pid,ppid,etime,%cpu,comm | grep swift    # orphans = ppid 1, 0.0% CPU
pkill -9 -f swift-build; pkill -9 -f swift-test
```

This is the third distinct failure mode from one root cause (agy's async
background-task model), after the discarded answer (`eac238ec`) and the infinite
restart loop. Treat "agy launched something in the background" as always leaving
debris.

### Executor guardrails (state these verbatim in every delegated order)

A cheap model told "make it green" will find a way to make it green. Three of
those ways are unacceptable:

1. **No shims.** If green appears to require an alias, a dual-decode path, a
   fallback `CodingKeys`, or keeping the old name "for compatibility" — **stop and
   report**. That silently converts a hard cutover into a permanent bilingual
   fence, which is the exact thing this packet exists to delete.
2. **No scope drift.** If green requires editing a file outside the named list —
   **stop and report** the file and the reason. Do not fix it.
3. **Never decide meaning.** Every "is this a seat id or a model pin?" call
   belongs to the lead. The executor receives a table with the destination already
   filled in. Its job is transcription, not inference. If the table does not
   cover an occurrence, **stop and report** it.

Report format for a stopped round: the file, the line, what green would have
required, and nothing else. Do not proceed on assumption.

### Known wall constraint (as of 2026-07-28)

`bash scripts/check.sh` is **already red before this packet starts**, at the GUI
Visual Proof Gate, for five Mac views touched by the prior vocab cutover
(`FactoryFloorView`, `RoutingComposer`, `TeamEditorView`, `TeamsLauncherView`,
`TeamStudioView`). That debt belongs to the vocab cutover, not here.

Consequences:

- The **executor gate is the three commands above**, not the full wall. Do not
  ask an executor to turn the full wall green; it cannot, and it will try.
- Any WTA slice that edits a Mac view inherits the GUI proof requirement
  (`docs/gui/Visual_Proof_Gate.md`). Route those edits so they land with a proof
  packet or an explicit waiver — this is a lead responsibility, not an executor
  one.

---

## Layer map (execute in this order)

### Layer A — Mental map (no rename yet)

Prove we know what each `worker*` occurrence *means* before touching it.

| Bucket | Examples | Destination name |
| --- | --- | --- |
| A1 Roster seat | `TeamWorkerSpec`, `workerSpecs`, team catalog rows | `TeamAgentSpec` / `agents` / `agentId` |
| A2 Run answer identity | `TeamRunJSON.workers`, `workerAnswers`, `AnswerInfo.workerId` | `agents` / `answers` / `agentId` + always-present `modelId` |
| A3 Thread / pending pin | turn `workerId`, pending `preferredWorkerIds` that mean model | `modelId` (pin) — not agent |
| A4 Process / warm pool | `WarmWorker`, ownership `kind: "worker"`, worker dirs under run storage | **keep as session/process** — out of WTA product rename unless a slice explicitly owns it |
| A5 Error / event codes | `WORKER_FAILED`, NDJSON `workerAnswerDelta` | `AGENT_*` / `agentAnswerDelta` in a **contract major** slice |

### Layer B — Swift roster types (catalog)

Rename in-process types that mean "staffed seat." Persist team JSON with new keys
in the same slice (hard cut; migrate on-disk catalogs in that PR's fixture/data
pass). `TeamCatalog.swift` / `TeamWorkerSpec` → `TeamAgentSpec`, then all call
sites **in the same commit** (Law 1).

### Layer C — Public run contract (`TeamRunJSON` + schemas)

Contract **major** bump. `workers` → roster projection name that matches product.
`workerAnswers` → `answers` (pick one in WTA-S00 and stick). Every answer row
carries **both** `agentId` and `modelId`.

### Layer D — Engine / Mac / iOS consumers

Presenters, `ThreadsViewModel`, Floor, Artifact projector, iOS remote mirrors —
consume the new keys only after Layer C. One surface family per PR.

### Layer E — Process layer (deferred, separate packet if ever)

`WarmWorker` → `WarmSession`. Ownership `kind: "worker"` → `"session"`.
**Do not mix with the agent rename.** Different concept. Default: never.

---

## Measured scale (2026-07-28 baseline — re-measure at S00)

```text
442    Swift files containing "worker" (case-insensitive)
7462   total occurrences in Swift
925    workerId
443    workers
217    workerAnswers
164    workerSpecs
101    TeamWorkerSpec
 44    workerIds
 42    WORKER_*  (error / event codes)
 32    WarmWorker        ← Layer E, stays
 22    workerAnswerDelta
 21    preferredWorkerIds
~240   living non-Swift files (json/md, excluding docs/archive)
```

This is weeks of small commits. That is the expected shape, not a problem to
optimize away.

---

## Surface inventory (starting points — expand in WTA-S00)

Not exhaustive. WTA-S00 turns this into a checklist with **meaning tags** (A1–A5).

**Roster / catalog**
- `TeamCatalog.swift` (`TeamWorkerSpec`, `workerSpecs`)
- `BuiltInTeams.swift`, `TeamResolver.swift`, `TeamExplicitSeats.swift`
- Mac: `TeamEditorView.swift`, `TeamStudioView.swift`, `TeamDraft*`

**Run contract / projection**
- `TeamRunJSON.swift`, `TeamRunJSONMapper.swift`, `ContractSchema.swift`
- `NDJSONStreamProjector.swift`, `FloorProjector.swift`, `ArtifactProjector.swift`
- Fixtures: `Resources/Fixtures/team_run.json`

**Engine**
- `RunService.swift`, `ResolvedRunInvocation.swift`, `CatalogRunCoordinator.swift`
- `ThreadSendCoordinator.swift`, `PendingService.swift` / pending JSON
- Process (Layer E, do not touch): `WarmWorker*.swift`, `ProcessOwnership*.swift`

**CLI / teaching**
- `ContractRegistry+Milestone1.swift` (error codes, flag summaries that still say
  "worker" in agent-facing explain text — including `alln run --help` itself)
- `HelpTopicRegistry.swift`, recipes, `RetiredVocabulary` (extend deny-list as old
  JSON keys stop being taught)

**Apps**
- Mac presenters / Factory Floor / Threads
- iOS conversation / remote models that decode `workerId`

**Generated**
- `docs/generated/alln/*` — regenerate after registry/schema changes

---

## Cutover slices (ordered)

Do not start S01 until S00 is checked in with a meaning-tagged inventory. Do not
reorder (see Value ordering). One open at a time (Law 9).

- [ ] **WTA-S00 — Inventory + id-meaning map.** *(Sonnet gathers, lead adjudicates)*
  Produce a table: path → symbol → bucket (A1–A5) → destination field, with the
  evidence for each call (what is actually assigned to it). Flag every `workerId`
  that is *really* a model pin. No renames. Works Test: the table exists as a
  linked appendix and every ambiguous row is marked **SPLIT BEFORE RENAME**.

- [ ] **WTA-S01 — Split ambiguous pins (pre-rename).** *(Sonnet, lead-specified)*
  Where pending/thread/run invocation stores a model id under `workerId`,
  standardize on `modelId` at the **Swift API** boundary for those call sites
  only. Do not rename `TeamRunJSON` yet. Works Test: targeted tests show pin
  fields are model ids; seat fields remain seat ids.

- [ ] **WTA-S02 — Roster type rename (`TeamWorkerSpec` → `TeamAgentSpec`).** *(Gemini)*
  One type + persistence keys for team catalogs, all call sites in one commit.
  Mac team editor already says AGENTS — align type names. Works Test: catalog
  load/save + `TeamDraft` / BuiltInTeams tests green; `grep -c TeamWorkerSpec` == 0.

- [ ] **WTA-S03 — `TeamRunJSON` / schema major.** *(lead designs + guards, Gemini propagates)*
  Public contract: agents + answers with `agentId` + `modelId`. Bump
  `contractVersion`. Export contracts. Hard cut fixtures. Works Test:
  `ContractExportTests`, fixture round-trip written **before** the edit, one
  representative run projection test.

- [ ] **WTA-S04 — Engine consumers of TeamRunJSON / run journals.** *(Gemini)*
  Mappers, artifact, floor, NDJSON events per this slice's inventory rows. Works
  Test: engine tests for touched files; no dual decode paths left.

- [ ] **WTA-S05 — Mac + iOS presenters.** *(Gemini + lead GUI proof)*
  Decode/display new keys only. Works Test: Mac unit tests for presenters; iOS
  compile + relevant decode tests; GUI proof packet or waiver for any touched
  visible view.

- [ ] **WTA-S06 — Error codes + teaching scrub.** *(Sonnet drafts, lead verifies)*
  Rename agent-facing `WORKER_*` codes that mean seat/run-member failure; update
  help/recipes (`alln run --help` still says worker today); extend
  `RetiredVocabulary` for old JSON key spellings. Works Test:
  `RetiredVocabularyTests`, `HelpTopicRegistryTests`, contract error list.

- [ ] **WTA-S07 — Process/session rename.** **Deferred by default.**
  Only on explicit founder instruction. Product destination does not require it.

- [ ] **WTA-S08 — Closeout.**
  Promote the keepable law into `Product_Vocabulary.md` (machine layer = same
  nouns as human layer). Strike "may remain in machine JSON" language. Archive
  this packet. Works Test: living-doc grep / deny-list proves `workers[]` /
  `workerId` are not taught; code search for user-facing worker is empty.

---

## Works Test (packet-level)

Packet is done when:

1. Product and machine nouns match: **Team / Agent / Model / Skill**.
2. Every run answer exposes **`agentId` + `modelId`** with distinct meanings.
3. Seat counts are **agents**; CLI pins are **`--model`**; skill edit is **Edit skill**.
4. `worker` / `workers[]` / `workerId` are gone from **living** contracts and
   teaching — or remain only in Layer E process/session names that are *not*
   product seats (documented exception).
5. No bilingual fence paragraph left in `Product_Vocabulary.md`.

---

## Pace note

This will take many small commits. That is intentional. Language_Cutover proved
hard cutover works when slices are ordered and the wall stays green. The failure
mode is one heroic `sed` across `RunService.swift` and journals — or, just as
bad, a packet left half-landed for a month.

**Simple always wins.** The destination is simple. The path is slow on purpose,
but never idle.
