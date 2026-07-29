# Worker → Agent Migration

Status: **Open — destination locked; execution not started**
Owner: code SSOT for runs (`RunService.swift`, `TeamCatalog` / `TeamWorkerSpec`,
`TeamRunJSON`); standing vocabulary `docs/workflows/Product_Vocabulary.md`
Created: 2026-07-28
Updated: 2026-07-28
Next work order: **WTA-S00** (inventory + id-meaning map) before any rename PR

Process:
`docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`

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
Painful now; dividends if the project succeeds. Go careful and slowly — one file
at a time. No stupid global grep that breaks the floor.

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

**Blocking questions:** None for destination. Pace and slice boundaries are
execution choices below.

---

## Why what we have is wrong

`worker` is a junk drawer for three different identities:

| Need | Today (often) | Should be |
| --- | --- | --- |
| Which roster seat? | `workerId` / `TeamWorkerSpec` | **`agentId`** |
| Which AI actually ran? | also `workerId`, sometimes `modelId` | **`modelId`** (always) |
| Which CLI subprocess / warm pool? | `WarmWorker`, ownership `kind: "worker"` | **`session` / process** — different layer |

One word, three jobs. Agents (coding agents) cannot reason. Humans already got the
clean nouns on the surface; the machine layer still trains the old lie.

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

## Migration law (how we don't break the floor)

1. **One file / one type / one contract surface per PR** when practical. Prefer
   smaller than "rename everything in Core."
2. **No global replace.** Inventory → targeted edits → tests for that slice →
   green wall for touched packages → commit. Next file.
3. **Name by meaning before renaming the string.** If a field today is sometimes
   a model id and sometimes a seat id, **split or document** before the rename
   PR. False precision (`agentId` that is actually a model id) is worse than
   `workerId`.
4. **Hard cutover inside a slice.** No "accept `--worker` and `--model`." User
   flags already retired; machine keys follow the same rule once their slice
   ships.
5. **Regenerate, don't hand-edit** `docs/generated/alln/*` after contract changes
   (`alln dev export-contracts`).
6. **Leave archives / qa snapshots / mvp history alone.** Living docs + code +
   fixtures that still round-trip must move.
7. **Teaching surface in the same slice** that changes agent-visible JSON or
   error codes (`HelpTopicRegistry`, `RetiredVocabulary`, recipes).

---

## Layer map (execute in this order)

### Layer A — Mental map (no rename yet)

Prove we know what each `worker*` occurrence *means* before touching it.

| Bucket | Examples | Destination name |
| --- | --- | --- |
| A1 Roster seat | `TeamWorkerSpec`, `workerSpecs`, team catalog rows | `TeamAgentSpec` / `agents` / `agentId` |
| A2 Run answer identity | `TeamRunJSON.workers`, `workerAnswers`, `AnswerInfo.workerId` | `agents` / `answers` / `agentId` + always-present `modelId` |
| A3 Thread / pending pin | turn `workerId`, pending `preferredWorkerIds` that mean model | `modelId` (pin) — not agent |
| A4 Process / warm pool | `WarmWorker`, ownership `kind: "worker"`, worker dirs under run storage | **keep as session/process** or rename to `session` later — **out of WTA product rename** unless a slice explicitly owns it |
| A5 Error / event codes | `WORKER_FAILED`, NDJSON `workerAnswerDelta` | `AGENT_*` / `agentAnswerDelta` in a **contract major** slice |

### Layer B — Swift roster types (catalog)

Rename in-process types that mean "staffed seat." Persist team JSON with new keys
in the same slice (hard cut; migrate on-disk catalogs in that PR's fixture/data
pass). Start with `TeamCatalog.swift` / `TeamWorkerSpec` → `TeamAgentSpec`, then
call sites **file by file**.

### Layer C — Public run contract (`TeamRunJSON` + schemas)

Contract **major** bump. `workers` → roster projection name that matches product
(`agents` or keep seating under run info + `answers[]` with `agentId`).
`workerAnswers` → `answers` (or `agentAnswers` — pick one in WTA-S00 and stick).
Every answer row carries **both** `agentId` and `modelId`.

### Layer D — Engine / Mac / iOS consumers

Presenters, `ThreadsViewModel`, Floor, Artifact projector, iOS remote mirrors —
consume the new keys only after Layer C. One surface family per PR when possible.

### Layer E — Process layer (optional, separate packet if needed)

`WarmWorker` → `WarmSession` (or leave). Ownership `kind: "worker"` → `"session"`.
**Do not mix with agent rename.** Different concept.

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
- Process (leave for Layer E): `WarmWorker*.swift`, `ProcessOwnership*.swift`

**CLI / teaching**
- `ContractRegistry+Milestone1.swift` (error codes, flag summaries that still say
  "worker" in agent-facing explain text)
- `HelpTopicRegistry.swift`, recipes, `RetiredVocabulary` (extend deny-list as old
  JSON keys stop being taught)

**Apps**
- Mac presenters / Factory Floor / Threads
- iOS conversation / remote models that decode `workerId`

**Generated**
- `docs/generated/alln/*` — regenerate after registry/schema changes

---

## Cutover slices (ordered)

Do not start S01 until S00 is checked in with a meaning-tagged inventory.

- [ ] **WTA-S00 — Inventory + id-meaning map.**  
  Produce a table: path → symbol → bucket (A1–A5) → destination field. Flag every
  `workerId` that is *really* a model pin. No renames. Works Test: the table
  exists in this doc (or a linked appendix) and founder/agent agree ambiguous
  rows are marked **SPLIT BEFORE RENAME**.

- [ ] **WTA-S01 — Split ambiguous pins (pre-rename).**  
  Where pending/thread/run invocation stores a model id under `workerId`, introduce
  or standardize on `modelId` at the **Swift API** boundary for those call sites
  only. Do not rename `TeamRunJSON` yet. Works Test: targeted tests show pin fields
  are model ids; seat fields remain seat ids.

- [ ] **WTA-S02 — Roster type rename (`TeamWorkerSpec` → `TeamAgentSpec`).**  
  One type + persistence keys for team catalogs. File-by-file call-site updates.
  Mac team editor already says AGENTS — align type names. Works Test: catalog
  load/save + `TeamDraft` / BuiltInTeams tests green; no `TeamWorkerSpec` left.

- [ ] **WTA-S03 — `TeamRunJSON` / schema major.**  
  Public contract: agents + answers with `agentId` + `modelId`. Bump
  `contractVersion` appropriately. Export contracts. Hard cut fixtures. Works
  Test: `ContractExportTests`, fixture round-trip, one representative run
  projection test.

- [ ] **WTA-S04 — Engine consumers of TeamRunJSON / run journals.**  
  Mappers, artifact, floor, NDJSON events as owned by this slice's inventory
  rows. Works Test: engine tests for touched files; no dual decode paths left
  for those files.

- [ ] **WTA-S05 — Mac + iOS presenters.**  
  Decode/display new keys only. Works Test: Mac unit tests for presenters;
  iOS compile + relevant decode tests.

- [ ] **WTA-S06 — Error codes + teaching scrub.**  
  Rename agent-facing `WORKER_*` codes that mean seat/run-member failure; update
  help/recipes; extend `RetiredVocabulary` for old JSON key spellings taught as
  grammar. Works Test: `RetiredVocabularyTests`, `HelpTopicRegistryTests`,
  contract error list.

- [ ] **WTA-S07 — Process/session rename (optional / separate).**  
  Only if founder wants ownership JSON / warm pool without the word worker.
  Default: **defer**; product destination does not require it.

- [ ] **WTA-S08 — Closeout.**  
  Promote any keepable law into `Product_Vocabulary.md` (machine layer = same
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

This will take many small PRs. That is intentional. Language_Cutover proved hard
cutover works when slices are ordered and the wall stays green. The failure mode
is one heroic `sed` across `RunService.swift` and journals.

**Simple always wins.** The destination is simple. The path is slow on purpose.
