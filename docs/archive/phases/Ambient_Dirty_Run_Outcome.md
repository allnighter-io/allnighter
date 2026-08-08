# Ambient Dirty Run Outcome

Status: **CLOSED 2026-08-08 — ADR-S01/S02/S03 all shipped
(`b06e67ad`, `5dbfc130`). Law promoted to help `opencode_headless_completion`;
code SSOT `RunService`. ARCHIVED.**
Owner: Allnighter (`RunService.applyIncompleteUncommitted`,
`GitObserver.dirtyFiles`, `OpenCodeOutcomeAuthority`); help
`HelpTopicRegistry` (`incomplete_uncommitted` / `answerOnly`)
Created: 2026-08-08
Last revised: 2026-08-08 (v2 — defect hunt + strategy lock)
Origin: `09E19604` — DeepSeek V4 Pro via OpenCode; prompt `READ ONLY` doc
harden; full assistant answer (~7k); OpenCode `local_idle` + assistant text;
run still `failed` / `incomplete_uncommitted` because the worktree was already
dirty from unrelated WIP.
Review run: `B8818101` (Pro `--read-only`; prior attempt `89417ED3` refused
`portOwnedByForeignProcess` — see [`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md)).

Related: archived
[`OpenCode_Headless_Completion_And_Session_Scoping.md`](../archive/phases/OpenCode_Headless_Completion_And_Session_Scoping.md)
(S122.3 law); [`OpenCode_Completion_Truth_Followup.md`](OpenCode_Completion_Truth_Followup.md);
[`Crew_Understaffed_Signal.md`](Crew_Understaffed_Signal.md) (prior board row);
[`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md) (leftover `:4096` refuse).

Phases are ephemeral. Closeout: promote keepable law into code + help; archive.

---

## Closeout (2026-08-08)

| Slice | Result |
| --- | --- |
| ADR-S01 dirty-vs-start | **Shipped** `b06e67ad` — `startDirtyPaths` snapshot beside `baselineHead`; gate fires only on paths this run introduced |
| ADR-S02 delivered ≠ empty | **Shipped** `b06e67ad` — `errorKind` nil when output exists; tool-only-no-text still `.emptyOutput` |
| ADR-S03 teaching | **Shipped** `5dbfc130` — help only; no menu `dontUseWhen`, no prompt sniffing |

**Works Test — the packet's own script, as real git-repo tests**
(`RunRepoDeltaTests`, 9 pass):

| Case | Result |
| --- | --- |
| Ambient dirty + zero seat edits | **not** `incomplete_uncommitted`, run complete |
| Control A: clean start, seat dirties, no commit | still `incomplete_uncommitted` |
| Control B: start dirty, seat writes a NEW file | still `incomplete_uncommitted` |
| Delivered answer under the gate | `errorKind` nil, text preserved |

Mutation check: reverting either slice turns 3 assertions red.

**Promoted:** help topic `opencode_headless_completion` now states that
`incomplete_uncommitted` means work the seat itself created, measured against
the tree at dispatch, and that a delivered answer keeps its text. Code SSOT:
`RunService` (`startDirtyPaths` capture, S122.3 gate, `applyIncompleteUncommitted`).

**Carried forward, unchanged from §"Out of scope":** the v1 limitation stands —
a seat that only further-edits a path already dirty at start is not detected by
set-subtract. Content-hash / porcelain-line diff remains deferred, and failing
open on ambient paths is the deliberate trade.

---

## If you only read one thing

OpenCode (and the worker) can finish honestly with a full answer and **zero**
run-owned edits, and Allnighter still stamps `incomplete_uncommitted` because
`worktreeDirty` is end-of-run porcelain — including dirt that was already there
before the run started. That is a product lie: it blames the seat for ambient
WIP it did not create.

---

## Defect (proven)

Run `09E19604-F119-4867-A697-28C4DFC24876`:

| Field | Observed |
| --- | --- |
| Prompt | `READ ONLY. Harden docs/phases/Crew_Understaffed_Signal.md…` |
| `writePolicy` / intent | `mutating` (default chat) |
| OpenCode signal | `idleReason: local_idle`, non-empty `assistantText`, no `toolOnlySummary` |
| `OpenCodeOutcomeAuthority` | Would return **done** (assistant-text path, ~lines 83–84) |
| Then S122.3 gate | `RunService` rewrites complete → failed `incomplete_uncommitted` (~2152–2157) |
| `repoDelta` | `changed: false`, `files: []`, `commits: []`, `worktreeDirty: true` |

Code path:

```text
OpenCodeOutcomeAuthority.resolve → .done(assistantText)    // ~83–84
RunService sets status complete                              // ~2146–2150
if mutating && !noCommit && worktreeDirty && commits.isEmpty && status complete
  → applyIncompleteUncommitted                              // ~2156
    → stamps emptyOutput + incomplete_uncommitted           // ~2567–2568
```

`GitObserver.dirtyFiles(rootPath:)` (~56–77) always queries **live**
`git status --porcelain -uall`. There is **no start-of-run dirty-path snapshot**
for mutating seats. Research runs already have `ResearchSnapshot` (HEAD +
porcelain + tracked diff) captured pre-dispatch (~2407) and compared
post-run (~2421–2422) — ambient dirt is correctly excluded for research.

---

## Product promise

```text
incomplete_uncommitted means this mutating seat left uncommitted work it owns —
not "the repo was dirty for other reasons when the run ended."
A delivered answer on a zero-delta run is not empty_output.
```

---

## Rejected

| Idea | Why |
| --- | --- |
| Delete S122.3 entirely | Real tool-only + dirty + no-commit fake-success must stay fail-closed |
| Treat any assistant text as success and skip dirty gate always | Hides true incomplete mutating tool runs that touched files |
| Infer "READ ONLY" from prompt prose | Prompt is not the write-policy owner |
| Blame OpenCode completion / stream | `09E19604` completed cleanly; failure is Allnighter outcome rewrite |
| Capture full `ResearchSnapshot` for mutating and reuse `researchObservation` | Research also compares HEAD + tracked-diff content — overkill for S122.3, which needs dirty-path-set diff only |

---

## Chosen strategy: dirty-path-set diff at S122.3 gate

**Locked data path:**

1. **Capture at mutating run start** (pre-`coordinator.run`, sibling to research
   `researchBaseline` ~2407): `gitObserver.dirtyFiles(rootPath:)` → `[String]`
   root-relative paths. Store as local `let startDirtyPaths` in the settle
   path. Do **not** persist on `TeamRun` — transient gate input only (same
   pattern as `baselineHead`).

2. **At S122.3 gate** (~2152–2157), re-query `dirtyFiles` → `endDirtyPaths`.
   Gate fires only when:
   - `delta.commits.isEmpty` (unchanged), **and**
   - `Set(endDirtyPaths).subtracting(startDirtyPaths)` is non-empty.

3. If every end-dirty path was already dirty at start → do **not** fail.
   Ambient dirt excluded. New dirty paths still trigger `incomplete_uncommitted`.

4. Reuses proven `GitObserver.dirtyFiles` (also feeds `uncommittedFileCount`
   ~2133). No new Git CLI, no new struct, no new persisted field.

**v1 limitation (accepted):** a seat that only further-edits a path already
dirty at start is not detected by set-subtract. Prefer fail-open on ambient
paths over false-failing honest zero-delta answers. Content-hash / porcelain
line diff is deferred — not this packet.

**Authority scope:** `OpenCodeOutcomeAuthority.resolve` (~91–96) also reads
`repoDelta?.worktreeDirty` for `toolOnlySummary` + dirty. **Out of scope for
ADR-S01.** A tool-only worker with zero assistant text and zero commits is a
true incomplete run; this packet only gates `applyIncompleteUncommitted`, which
fires after authority already ruled `.done`.

---

## Suggested slices

### ADR-S01 — Dirty-vs-start for S122.3 gate

Truth owner: `GitObserver.dirtyFiles` + `RunService` settle path.

| What | Where |
| --- | --- |
| Capture `startDirtyPaths` | Mutating settle entry (~2407 sibling) — before `coordinator.run` |
| Compare at gate | ~2153 condition gains set-subtract vs `startDirtyPaths` |
| `applyIncompleteUncommitted` body | Unchanged — this slice only controls *whether* it is called |

### ADR-S02 — Don't relabel a delivered answer as empty

Truth owner: `applyIncompleteUncommitted` only.

When S122.3 fires for real run-owned dirt, keep `errorReason:
incomplete_uncommitted`. Do **not** force `errorKind: .emptyOutput` when
`result.output` (or signal `assistantText`) is non-empty — leave kind nil or
use an existing non-contradictory kind. Do **not** invent
`.incompleteUncommitted` unless the WorkerAnswerErrorKind contract already
needs a new case for GUI/CLI mapping.

Do **not** change `OpenCodeOutcomeAuthority.apply` (~114) — tool-only + dirty
with no assistant text correctly keeps `.emptyOutput`.

### ADR-S03 — Teaching / launch footgun (narrow)

Default chat is mutating. Doc-harden / "READ ONLY before code" should use
`--read-only` (requires `--model`), judgment / `answerOnly`, or `--no-commit` —
not ambient-dirty roulette on mutating default chat.

**Exact scope:**
- Help topic (or topic section) on `incomplete_uncommitted`: seat left
  uncommitted work **it created**; on a zero-edit run the repo was already
  dirty — use `--read-only` / judgment / `--no-commit`.
- Bootstrap teaching may link that topic when the reason is named.
- No menu `dontUseWhen`, no intent router, no English-prompt detection.

---

## Works Test

```text
1. Dirty the repo with an unrelated tracked edit (do not stage/commit).
2. alln run "READ ONLY. Reply with exactly: OK. Edit no files." \
     --model model_opencode_deepseek_v4_pro --json
   (mutating default chat — proves ADR-S01, not --read-only bypass)
3. Expect: status complete, answer contains "OK",
   errorReason != incomplete_uncommitted, repoDelta.changed == false.
4. Control A: mutating prompt that writes a NEW file and skips commit →
   still incomplete_uncommitted.
5. Control B: start dirty, worker writes a NEW file and skips commit →
   still incomplete_uncommitted (incremental path detection).
```

Dogfood note until [`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md): if
`:4096` is a healthy leftover, current AgentOS refuses
`portOwnedByForeignProcess` — free the port or wait for OSA attach; do not
SIGTERM a live foreign serve as product law.

Filter (when coded):
`scripts/swift-test.sh --filter 'RepoDelta|OpenCodeOutcome|IncompleteUncommitted|AmbientDirty|DirtyStart'`

---

## Out of scope

- CHS spawn-gate serialize (`Crew_Understaffed_Signal.md`)
- OpenCode SSE / poll completion-truth (S123 / CT follow-up)
- OpenCode serve attach (`OpenCode_Serve_Attach.md`)
- Auto-detecting read-only intent from English prompts
- Cleaning or stashing the user's ambient WIP
- Dirty-vs-start inside `OpenCodeOutcomeAuthority` toolOnlySummary path (~91–96)
- Content-hash of already-dirty paths further edited in-window (v1 limitation)

---

## Review delta (v2 / `B8818101`)

| Change | Why |
| --- | --- |
| Locked dirty-path-set diff via `dirtyFiles` | Ended dual strategy (porcelain vs ResearchSnapshot) |
| Rejected full ResearchSnapshot reuse | Wrong comparison surface for S122.3 |
| Scoped ADR-S01 to `applyIncompleteUncommitted` only | Authority tool-only path stays fail-closed |
| Scoped ADR-S02 away from inventing errorKind casually | Kind must not contradict delivered output |
| Narrowed ADR-S03 to help/bootstrap | Dropped undefined menu `dontUseWhen` |
| Works Test Control B | Proves new-path detection under ambient dirt |
| Noted OSA port refuse | Live blocker on Pro dogfood without attach |
