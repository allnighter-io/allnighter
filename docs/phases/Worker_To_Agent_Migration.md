# Worker → Agent Migration

**Status: SHIP LINE COMPLETE — optional hygiene only**

Do **not** start WTA work by default. This packet is **closed for product
purposes**. Remaining slices are **optional cleanup** — do them only when the
founder explicitly allocates extra time and resources. Dogfood, feature packets,
and floor reliability always win.

**Standing law (SSOT):** `docs/workflows/Product_Vocabulary.md`  
**Historical execution record (S00–S08):** `docs/archive/phases/Worker_To_Agent_Migration.md`  
**Meaning map (adjudicated):** `docs/archive/phases/Worker_To_Agent_Migration.md` → appendix S00 map  
**Code SSOT:** `TeamRunJSON`, `TeamAgentSpec` / `TeamPreset.agentSpecs`,
`RetiredVocabulary`, `RunService.swift`

Updated: 2026-07-29

---

## What shipped (done — do not re-litigate)

The **agent-facing contract** and **teaching surface** use one vocabulary:

| Noun | Machine layer |
| --- | --- |
| **Agent** | Roster seat — `TeamRunJSON.agents[]`, `agentId` on answers |
| **Model** | Catalog id — CLI `--model`, `modelId` on answers |
| **Skill** | `skillId` |
| **Team** | Named lineup |

Proof at closeout (2026-07-29): `swift test` green; `alln dev export-contracts --check`
green (contract 6.0.0).

**Intentional bilingual exceptions** (not bugs, not blockers):

- Internal run journal: `TeamRun.workers`, `workerAnswer(workerId:)`
- Run events / NDJSON payloads: `"workerId"` on `RunEvent` (Layer E)
- Process layer: `WarmWorker*`, `ProcessOwnership`, artifact `workers/` dirs
- Some pending/remote fields: `workerToken`, `resolvedWorkerIds` (wire compat)

These are documented in `Product_Vocabulary.md`. Agents must not “fix” them
opportunistically during feature work.

---

## How optional work must be continued

Only when the founder explicitly opens a backlog row below. Then follow this
loop — same laws as the original packet (`docs/archive/phases/Worker_To_Agent_Migration.md`
§ Migration law). **Read the archive section before editing.**

### 0. Founder gate

- No WTA work during an active feature packet in the same files.
- Exactly **one** optional slice open at a time.
- If the slice cannot land in one session → split it smaller or stop.

### 1. Classify before rename (mandatory)

Every symbol is **model pin** (catalog id) or **seat id** (composite `model_x#0`)
or **Layer E** (process/journal wire — do not touch). Use the S00 meaning map;
if ambiguous, **stop and ask** — do not guess.

| Means | Rename toward | Examples |
| --- | --- | --- |
| Catalog / CLI `--model` pin | `modelId` | `selectedWorkerId` on composer, `pinnedModelId`, `workerToken` |
| Roster / run seat | `agentId` | `memberId`, `TeamRunJSON.agents[].id`, `workerAnswer(workerId:)` arg |
| Process / session / warm pool | **leave** | `WarmWorker*`, `ProcessOwnership.$currentWorkerId` |

**Never ship:** `run.workerAnswer(agentId:)` — label/semantics mismatch; always a bug.

### 2. One symbol per commit

```text
one symbol  →  all call sites  →  build + tests green  →  commit
```

Not one file. Not a grep sweep. Not “while I’m here.”

### 3. Proof wall (every commit)

| Change touches | Required proof |
| --- | --- |
| `Packages/AllnighterCore` only | `swift test` (or `--filter` on touched test classes for speed, then full suite before closeout) |
| Mac app (`Apps/AllnighterMac`) | **`allapp`** — `swift test` does **not** compile the Mac target |
| Contract / registry / teaching | `alln dev export-contracts --check` |
| GUI-visible Mac view | `docs/gui/Visual_Proof_Gate.md` or explicit waiver |

A green `swift test` alone **missed** Mac-only breaks (e.g. `LiveArtifactPreviewView`
using `\.modelId` after `SeatState` became `agentId`).

### 4. Compiler-blind surfaces

JSON keys, `CodingKeys`, fixtures, on-disk journals, NDJSON event names,
`RetiredWorkerKeysMigration` paths, help text — **write or run the failing test
first**, then edit. `RetiredWorkerKeysMigration` is path-aware; never bulk-rename
keys without reading it.

### 5. Correct bilingual boundary (keep during optional work)

```swift
for agent in run.workers {                              // journal key: Layer E until OPT-B
    let answer = run.workerAnswer(workerId: agent.id) // API label unchanged
    EventData(agentId: agent.id, modelId: agent.modelId, ...)
}
```

Do **not** chip `for agent in run.workers` across many commits — that is the
awkward half-state. Either leave `worker` as the loop var or do **WTA-OPT-B**
(journal rename) atomically.

### 6. Closeout per slice

Stage explicit paths, commit, note proof in the commit message. Do not `git add -A`.

---

## Failure modes — do not repeat

These happened in this migration. **Grep count is not progress.**

| Mistake | Why it hurts | What to do instead |
| --- | --- | --- |
| **Global `sed` / replace-all on `workerId`** | Broke `workerAnswer(workerId:)`, mixed model vs seat semantics | Context per occurrence; one symbol + call sites |
| **Grep `worker` → zero as a goal** | ~7k hits; most are Layer E or legitimate | Ignore count; fix lying names only |
| **`for agent in run.workers` without OPT-B** | Collection still lies; cognitive friction | Leave loop var or do atomic journal slice |
| **`workerAnswer(agentId:)`** | API requires `workerId:` label for seat id | Never rename that label without OPT-B |
| **Bulk rename `workerSpecs`** | Four different types (`TeamPreset`, `PanelPreset`, `Workflow`, …) | Type-discriminate; one owner per commit |
| **`swift test` only after Mac edits** | Mac app did not build; errors shipped | Run `allapp` when `Apps/AllnighterMac` touched |
| **Renaming wire keys opportunistically** | Breaks iOS mirrors, pending queue, migration | OPT-D only with founder + contract bump |
| **Teaching/help lag** | Agents learn retired keys from help | Same slice updates `RetiredVocabulary` / help |
| **Half-migrated packet for weeks** | Doubles vocabulary | One slice open; land or abandon |

**Banned commands / patterns:**

```bash
# NEVER
sed -i '' 's/worker/agent/g' ...
sed -i '' 's/workerId/agentId/g' ...
rg 'workerId' | xargs # bulk replace
```

**Discovery greps (inventory only — not replace lists):**

```bash
rg 'workerId|workerSpecs|run\.workers|workerAnswer' --glob '*.swift'
rg 'selectedWorkerId|continuationWorkerId|pinnedWorker' --glob '*.swift'
```

---

## What we are **not** doing now

- Grep `worker` → zero
- `for agent in run.workers` loop-var churn without OPT-B
- Global `sed` on `workerId` or `worker`
- S07 process/session rename unless founder reopens explicitly
- Resuming stale work orders under `docs/phases/wta/` without opening a backlog row

---

## Optional future slices (backlog only)

Skip entirely unless founder says go. Pick **one row**, follow **How optional work
must be continued** above.

| Id | Slice | Scope | ROI | Effort |
| --- | --- | --- | --- | --- |
| **WTA-OPT-A** | High-value lying locals | Params/locals where name contradicts type (`workerToken` holding model id, `resolveWorkerId` returning model, etc.) | Medium | Small commits |
| **WTA-OPT-B** | Journal rename | `TeamRun.workers` → `agents`, `workerAnswer` → `agentAnswer`, on-disk migration, **single atomic PR** | High coherence | Large |
| **WTA-OPT-C** | Panel/workflow `workerSpecs` | `PanelPreset` / `Workflow` only (not `TeamPreset.agentSpecs`) | Low unless editing those surfaces | Medium |
| **WTA-OPT-D** | Wire compat keys | `workerToken`, `resolvedWorkerIds`, pending JSON — only if external clients need it | Low today | Medium |
| **WTA-S07** | Process/session rename | `WarmWorker` → session, ownership `kind` — **separate packet** | Low; different concept | Large; founder-only |

---

## If you must touch worker/agent naming during feature work

1. Read `Product_Vocabulary.md` first.
2. Never rename Layer E in a drive-by.
3. One symbol + all call sites; proof wall per table above.
4. When in doubt: **leave it** and note in the feature packet.

---

## Archive

Full founder intake, layer map (A1–A5), slice checklist, orchestration, and pace
notes: `docs/archive/phases/Worker_To_Agent_Migration.md`. This file is the
**router + optional backlog + anti-patterns** only.
