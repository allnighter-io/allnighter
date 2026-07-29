# WTA-S02a — Work Order: rename `TeamWorkerSpec` → `TeamAgentSpec`

Dev seat: `model_gemini` (Antigravity). PM: lead session.
Packet: `docs/archive/phases/Worker_To_Agent_Migration.md`
Meaning map (already adjudicated — do not re-derive): `docs/archive/phases/Worker_To_Agent_Migration_S00_Map.md`

This is a **pure compiler-verified type rename**. Every decision has already been
made. Your job is transcription, not inference.

---

## Do exactly this

Rename two Swift **type names**, and every reference to them, repo-wide:

```text
TeamWorkerSpec     →  TeamAgentSpec
TeamWorkerPurpose  →  TeamAgentPurpose
```

That is the entire scope. ~101 references to the first, ~8 to the second.

Both are Swift type names. Swift type names are **never serialized** — the
structs carry explicit `CodingKeys` (`TeamCatalog.swift:190-194`) and enum
`rawValue`s (`"answer"` / `"review"`) that must stay **byte-identical**. So this
rename cannot change any on-disk or wire format. Verify that stays true.

---

## Do NOT touch — these are traps, each verified

| Do not rename | Why |
| --- | --- |
| `TeamPreset.workerSpecs` (the property) | It is a **persisted JSON key** — `TeamPreset` has no custom `CodingKeys`, so the property name IS the wire key in `Catalogs/teams/*.json` and `Resources/Fixtures/team_preset_default.json`. Renaming it silently breaks every saved team. That is slice S02b, and it needs a migration the lead will write. |
| `WorkerSpec` (no `Team` prefix) | A **completely different type** (`Worker.swift:87`), legacy bench/panel row, `modelId`-only, ~125 call sites. Two types, one grep. Renaming it here would conflate a seat definition with a model pin. |
| The `CodingKeys` cases inside `TeamWorkerSpec` | `id`, `skillId`, `purpose`, `preferredModelId`, `fallbackModelIds`, … are the wire format. Leave every one byte-identical. |
| `TeamWorkerPurpose` raw values | `"answer"` / `"review"` are persisted. Rename the type, never the strings. |
| `preferredModelId`, `fallbackModelIds`, `allowedModelIds`, `triangulatePreferenceIds` | Already correctly named. They are model catalog ids and are **not** part of this migration. |
| Anything named `WarmWorker*`, `ProcessOwnership*`, ownership `kind: "worker"`, run-storage `workers/` dirs | Layer E — process/session, a different concept. Explicitly out of scope forever. |
| Any other `worker` / `workerId` / `workerAnswers` anywhere | Later slices. Renaming them now would be actively harmful — some of them hold model ids, not seat ids. |

If you find yourself renaming anything not in the "Do exactly this" box: **stop and report.**

---

## Acceptance gate

All three must pass. Nothing less counts, and there is no partial credit:

```bash
cd /Users/mike/Documents/GitHub/Allnighter
swift build --package-path Packages/AllnighterCore
swift test  --package-path Packages/AllnighterCore
grep -rE '\bTeamWorkerSpec\b|\bTeamWorkerPurpose\b' --include='*.swift' . | grep -v '/.build/' | wc -l   # must print 0
```

Baseline for comparison: the suite is currently **2380 tests, 0 failures, 6
skipped**. Those 6 skips are live-integration tests gated behind env vars and are
expected — do not try to make them run.

Do **not** run `bash scripts/check.sh`. It is red for an unrelated pre-existing
reason (GUI visual proof gate, from an earlier commit). It is not your gate and
you cannot fix it.

---

## Three rules that override any instinct to be helpful

1. **No shims.** If green seems to need a `typealias TeamWorkerSpec = TeamAgentSpec`,
   a compatibility alias, a dual-decode path, or keeping the old name "just in
   case" — **stop and report**. This is a hard cutover. A shim silently converts
   it into a permanent two-vocabulary codebase, which is the exact thing this
   work exists to delete.
2. **No scope drift.** If green needs a file outside this rename, **stop and
   report** the file and why. Do not fix it. Do not tidy anything nearby. Do not
   reformat.
3. **Never decide meaning.** Every "is this a seat or a model?" question is
   already answered in the meaning map and reproduced above. If you hit an
   occurrence the table does not cover, **stop and report** it.

## If you stop

Report: the file, the line, what green would have required, and nothing else.
Do not proceed on an assumption. A stopped round is a good outcome; a round that
invented a shim is a bad one.

## When green

Commit with explicit paths only — never `git add -A` or `git add .`:

```bash
git add <the files you actually changed>
git commit -m "refactor(wta): TeamWorkerSpec -> TeamAgentSpec (WTA-S02a)"
```

Then report: the three gate results verbatim, the commit SHA, and the file count
you touched.
