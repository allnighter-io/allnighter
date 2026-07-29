# WTA-S02b — Work Order: `TeamPreset.workerSpecs` → `agentSpecs`

Dev seat: `model_gemini` (Antigravity). PM: lead session.
Packet: `docs/archive/phases/Worker_To_Agent_Migration.md`
Meaning map (already adjudicated — do not re-derive): `docs/archive/phases/Worker_To_Agent_Migration_S00_Map.md`

---

## The one dangerous thing about this slice

There are **FOUR** different properties named `workerSpecs` in this repo. Only
ONE is in scope. They are told apart by their **element type**:

| location | element type | action |
| --- | --- | --- |
| `TeamCatalog.swift:274` | `[TeamAgentSpec]` | **RENAME THIS ONE** |
| `Workflow.swift:130` | `[WorkerSpec]` | **leave alone** |
| `TeamAssembler.swift:13` | `[WorkerSpec]` | **leave alone** |
| `PanelPreset.swift:44` | `[WorkerSpec]` | **leave alone** |

A grep-and-replace across `workerSpecs` would still COMPILE while silently
changing three unrelated persisted JSON keys. Do not grep-and-replace.

## The method that makes this safe — follow it exactly

Let the compiler find the call sites for you:

1. Rename **only the declaration** at `TeamCatalog.swift:274`:
   `public var workerSpecs: [TeamAgentSpec]` → `public var agentSpecs: [TeamAgentSpec]`
   Rename its initializer parameter/label to match.
2. Run `swift build --package-path Packages/AllnighterCore`.
3. **Every resulting error is a `TeamPreset` call site** — those are exactly the
   ones to update. Call sites on `PanelPreset`, `WorkflowPreset`, or
   `TeamAssembler.Assembled` will NOT error, because those declarations are
   untouched. That is the discriminator; trust it, don't second-guess it by eye.
4. Repeat build → fix → build until it compiles.

Do not rename any other declaration. If you are tempted to, stop and report.

## Two compiler-blind edits — the compiler will NOT catch these

`workerSpecs` is a **persisted JSON key** here (`TeamPreset` has no custom
`CodingKeys`, so the property name IS the wire key). Two places hardcode it:

- `Packages/AllnighterCore/Sources/AllnighterCore/Resources/Fixtures/team_preset_default.json`
  → change the key `"workerSpecs"` to `"agentSpecs"`.
- `Packages/AllnighterCore/Tests/AllnighterEngineTests/CatalogCLITests.swift:267`
  → `obj["workerSpecs"]` is a raw string key; update it to `"agentSpecs"`.

No on-disk migration is needed: the lead verified `Catalogs/teams/` does not
exist on this machine and **zero** saved files contain this key. Do not write a
migration.

## Do NOT

- Do NOT rename the `WorkerSpec` type itself (different type, A3, later slice).
- Do NOT touch `Workflow.swift`, `TeamAssembler.swift`, or `PanelPreset.swift`.
- Do NOT touch `TeamAgentSpec`'s own `CodingKeys` — they are the wire format.
- Do NOT add a `CodingKeys` alias or any back-compat shim. Hard cutover.
- Do NOT touch anything named `WarmWorker*` / `ProcessOwnership*` (Layer E).
- Do NOT rename any other `worker*` field anywhere. Later slices, and some of
  them hold model ids rather than seat ids.

## Do NOT run the test suite

Run `swift build` only — you need it to find call sites. Do **not** run
`swift test`, and do **not** run `bash scripts/check.sh`.

This is not a trust issue: `swift test` takes ~2 minutes, and a seat that
launches a long command and waits for it has its turn END mid-wait, losing the
work. The lead runs the suite. Your build loop is fast and safe; the test suite
is not yours.

## Then commit — this is your completion signal

The commit is how the lead knows you are done. Commit even though you have not
run the suite; the lead gates immediately after.

```bash
git add <the files you actually changed>
git commit -m "refactor(wta): TeamPreset.workerSpecs -> agentSpecs (WTA-S02b)"
```

Stage explicit paths only — never `git add -A` or `git add .`. Do not discard,
rewrite, or force-update history; commit forward only.

## Stop conditions

1. **No shims.** If green seems to need a `CodingKeys` alias or a dual-decode
   path — stop and report.
2. **No scope drift.** If the build needs a file outside this rename, stop and
   report which and why.
3. **Never decide meaning.** If you find a `workerSpecs` you cannot confidently
   type-discriminate, stop and report it rather than guessing.

A stopped round is a good outcome. A round that renamed all four is a bad one.

## Report

The final `swift build` result, the commit SHA, how many call sites you fixed,
and explicit confirmation that `Workflow.swift`, `TeamAssembler.swift`, and
`PanelPreset.swift` are untouched.
