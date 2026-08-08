# Ambient Dirty Run Outcome

Status: **OPEN — draft. Not coded. Sequenced after
[`Crew_Understaffed_Signal.md`](Crew_Understaffed_Signal.md).**
Owner: Allnighter (`RunService.applyIncompleteUncommitted`,
`GitObserver.repoDelta`, `OpenCodeOutcomeAuthority`); help
`HelpTopicRegistry` (incomplete_uncommitted / answerOnly)
Created: 2026-08-08
Origin: `09E19604` — DeepSeek V4 Pro via OpenCode; prompt `READ ONLY` doc
harden; full assistant answer (~7k); OpenCode `local_idle` + assistant text;
run still `failed` / `incomplete_uncommitted` because the worktree was already
dirty from unrelated WIP.

Related: archived
[`OpenCode_Headless_Completion_And_Session_Scoping.md`](../archive/phases/OpenCode_Headless_Completion_And_Session_Scoping.md)
(S122.3 law); [`OpenCode_Completion_Truth_Followup.md`](OpenCode_Completion_Truth_Followup.md);
[`Crew_Understaffed_Signal.md`](Crew_Understaffed_Signal.md) (prior board row).

Phases are ephemeral. Closeout: promote keepable law into code + help; archive.

---

## If you only read one thing

OpenCode (and the worker) can finish honestly with a full answer and **zero**
run-owned edits, and Allnighter still stamps `incomplete_uncommitted` because
`worktreeDirty` is end-of-run porcelain — including dirt that was already there.
That is a product lie: it blames the seat for ambient WIP.

---

## Defect (proven)

Run `09E19604-F119-4867-A697-28C4DFC24876`:

| Field | Observed |
| --- | --- |
| Prompt | `READ ONLY. Harden docs/phases/Crew_Understaffed_Signal.md…` |
| `writePolicy` / intent | `mutating` (default chat) |
| OpenCode signal | `idleReason: local_idle`, non-empty `assistantText`, no `toolOnlySummary` |
| `OpenCodeOutcomeAuthority` | Would return **done** (assistant-text path) |
| Then S122.3 | `RunService` rewrites complete → failed `incomplete_uncommitted` |
| `repoDelta` | `changed: false`, `files: []`, `commits: []`, `worktreeDirty: true` |

Code path:

```text
OpenCodeOutcomeAuthority.resolve → .done(assistantText)
RunService sets status complete
if mutating && !noCommit && worktreeDirty && commits.isEmpty && status complete
  → applyIncompleteUncommitted  // stamps empty_output + incomplete_uncommitted
```

`GitObserver.repoDelta` always sets `worktreeDirty` from live
`git status --porcelain`. There is **no start-of-run dirty snapshot** for
mutating seats (research runs already have `ResearchSnapshot` porcelain).

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

---

## Suggested slices

### ADR-S01 — Dirty vs start (truth owner: `GitObserver` + `RunService`)

Capture porcelain (or dirty path set) at mutating run **start**. At end, fire
S122.3 `incomplete_uncommitted` only when:

- commits in the run window are empty, **and**
- dirty paths **appeared or changed** vs the start snapshot
  (or intersect worker-touched paths if that signal is cheap later).

If HEAD did not move, `filesChanged == 0`, and dirty ⊆ start dirty → do **not**
fail for ambient dirt.

Reuse the research-snapshot pattern; do not invent a second git truth channel.

### ADR-S02 — Don't relabel a delivered answer as empty

When S122.3 does fail for real run-owned dirt, keep `errorReason:
incomplete_uncommitted` but stop forcing `errorKind: empty_output` when
`assistantText` / `output` is non-empty. `alln show` already surfaces the
answer; the kind must not contradict it.

### ADR-S03 — Teaching / launch footgun (narrow)

Default chat is mutating. Doc-harden / "READ ONLY before code" should land on
judgment / `answerOnly` / `--no-commit`, not ambient-dirty roulette. One help
topic touch + menu `dontUseWhen` if a flag already exists; no new intent router.

---

## Works Test

```text
1. Dirty the repo with an unrelated tracked edit (do not stage/commit).
2. alln run "READ ONLY. Reply with exactly: OK. Edit no files." \
     --model model_opencode_deepseek_v4_pro --json
3. Expect: status complete (or answerOnly/judgment equivalent), answer contains OK,
   errorReason != incomplete_uncommitted, repoDelta.changed == false.
4. Control: same model, mutating prompt that writes a file and skips commit →
   still incomplete_uncommitted.
```

Filter (when coded):
`scripts/swift-test.sh --filter 'RepoDelta|OpenCodeOutcome|IncompleteUncommitted|AmbientDirty'`

---

## Out of scope

- CHS spawn-gate serialize (`Crew_Understaffed_Signal.md`)
- OpenCode SSE / poll completion-truth (S123 / CT follow-up)
- Auto-detecting read-only intent from English prompts
- Cleaning or stashing the user's ambient WIP
