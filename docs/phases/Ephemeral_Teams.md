# Runtime Seat Overrides

Status: **Ready** — Option C locked; no interim

Owner: `RunService` via `RunInvocationResolver`

Created: 2026-07-28

Updated: 2026-07-28 (hardened against code)

Process: `docs/workflows/SSOT_Founder_Input_Workflow.md` →
`docs/workflows/SSOT_Feature_Workflow.md`

---

## Founder intent

Dogfood request:

```text
Run Spec Review Min on this doc with ChatGPT 5.6 Sol from Codex,
Grok 4.5 from Grok, and Composer 2.5 from Cursor.
```

This is one run with a chosen crew. It is not a request to save another Team.

## Problem

`alln run` can select a Team with `--team` and pin one model with `--worker`.
It cannot supply the crew of a multi-seat judgment Team inline. Agents therefore
use the only taught customization path:

```text
teams duplicate → edit the copy → run the copy
```

That path writes `custom_*.json` under the durable Team catalog. One-off pilot,
relay, and direct-run staffing has produced 50+ permanent picker entries.

## User-visible claim

An agent can run any saved or built-in judgment Team once with an exact crew in
one command. The Team keeps its job, skills, lead, scout, posture, and synthesis
rules. The run writes no Team or skill catalog files.

Prior art: repeatable options are normal CLI grammar for ordered lists. Use one
repeatable scalar flag; do not introduce JSON argv, temporary entities, TTL, or a
second run verb.

## Locked CLI

```bash
alln run "Review docs/phases/Ephemeral_Teams.md" \
  --team code_spec_review_min \
  --seat model_chatgpt \
  --seat model_grok \
  --seat model_cursor_composer_25
```

`--seat <model_id>` is repeatable. Its occurrence order is the crew order.

Three intents, three gestures:

| Intent | CLI |
| --- | --- |
| Use the Team's normal lineup | `alln run "<message>" --team <team_id>` |
| Choose this run's crew | add repeated `--seat <model_id>` |
| Save a reusable Team | `alln teams duplicate <team_id>` → edit/save |

No alias, `--seats` JSON form, `--ephemeral` flag, temporary Team, or implicit
save.

## Runtime contract

### Scope and mapping

1. `--seat` **requires an explicit `--team`** and is mutually exclusive with
   `--worker`. Invalid combinations fail before dry-run, journal creation, or
   worker spawn with `CLI_USAGE_ERROR` (process exit 2).
2. The override covers **crew rows only** (`TeamPreset.workerSpecs`). The
   Team-owned scout and lead resolve normally and are not counted or replaced.
3. Expand crew rows in declaration order. A row with `count: N` contributes N
   adjacent slots. The number of `--seat` values must equal:

   ```text
   Σ max(1, workerSpec.count)
   ```

   Wrong count fails with `CLI_USAGE_ERROR` and reports expected and received
   counts. Never truncate, pad, or fall back to the normal lineup.
4. Slot `i` keeps row `i`'s skill, purpose, and required capability/lane rules;
   only its model identity changes. An incompatible model fails loud.
5. Duplicate model ids are allowed. They create distinct worker instances, as
   ordinary row multiplicity already does.

### Exact selection

6. Each value must be a canonical model id. Display names, unknown ids, disabled
   models, and not-ready models fail through the existing honor-or-fail model
   discovery path (`WORKER_NOT_AVAILABLE`); the error names the seat index and
   offers `alln menu --json`.
7. An explicit seat is exact. Initial resolution and mid-run capacity recovery
   must not substitute another model for it. Failure is recorded honestly.
8. Team write policy does not change. The execution-source gate still runs
   after the override; a mutating Team that no longer resolves to exactly one
   source fails closed.

### Persistence and replay

9. `RunService` receives the ordered ids as request data. It does not create,
   duplicate, edit, hide, or delete catalog entities.
10. Persist the accepted ordered selection separately from resolved workers
    (for example, additive `TeamRun.explicitSeatModelIds`). Resolved workers
    alone cannot distinguish an explicit override from the Team's normal
    resolution or later recovery. Legacy journals decode missing data as `nil`.
11. The ordered ids participate in the idempotency payload. Changing any
    `--seat` under the same key is an idempotency conflict, not a replay.
12. Dry-run `argvTemplate`, persisted `reproduceCommand` surfaces, artifact
    replay, detached `--no-wait`, and sandbox handoff preserve every accepted
    `--seat` in order. Dry-run's `seats[]` shows the effective crew plus
    unchanged scout/lead.

## Truth and inference bans

| Junction | Owner | Forbidden inference | Negative proof |
| --- | --- | --- | --- |
| argv → request | `Options` / `RunCLI` | Last repeated value wins | Three flags arrive as three ordered ids |
| request → seats | `RunInvocationResolver` | Count mismatch uses defaults | Mismatch refuses with no run/spawn |
| explicit id → model | `ExactIdResolver` + readiness gate | Display name or fallback is close enough | Unknown/not-ready id refuses |
| resolved run → journal | `RunService` / `TeamRun` | Resolved workers prove which ids were explicit | Explicit ordered ids round-trip |
| run → catalog | `RunService` | Runtime customization needs a saved Team | Catalog directory is byte-identical |
| explicit seat → recovery | capacity/substitution policy | A failed exact seat may be silently reseated | Failure keeps the requested model identity |

## Implementation

### RSO-S01 — flag, resolution, and durable replay

Truth owner: `RunInvocationResolver`, called only through `RunService`.

- Make the shared CLI parser preserve ordered repeated values; retain current
  single-value behavior for ordinary flags.
- Add ordered seat ids to `RunRequest`, `RunInvocationNormalizedFlags`, and the
  resolved invocation.
- Validate flag relationships, count, exact readiness, row compatibility, and
  execution source before acceptance.
- Resolve explicit crew workers without Team fallback or diversity selection;
  resolve unchanged scout and lead through the Team.
- Persist explicit seat ids, include them in idempotency, and round-trip them
  through replay, dry-run templates, `--no-wait`, and sandbox handoff.
- Register `--seat` and its existing error families in `ContractRegistry`; bump
  the contract version and regenerate artifacts from the registry.

Likely touchpoints:

`RunCLI.swift`, the shared `Options` parser, `RunService.swift`,
`ResolvedRunInvocation.swift`, `TeamRun.swift`, `TeamRunReplayCommand.swift`,
`ContractRegistry`, `ContractSchema`, `CatalogRunCoordinator` /
`VendorSubstitutionPolicy`, and focused engine/CLI tests.

### RSO-S02 — agent teaching cutover

This lands with S01; the capability is not done while agents are still taught
to duplicate Teams for one-off staffing.

- `MenuSelectionCopy` / `MenuCatalog`: `run` covers “staff these models once”;
  `teams duplicate` says not to use it for one-off staffing.
- `HelpTopicRegistry` (`teams_and_workers` and run help): teach the three-gesture
  table and the crew-only lead/scout rule.
- `Bootstrap` / teaching snippets: one short `--seat` recipe.
- Help search must find the recipe for `custom seats`, `staff models once`,
  `one-off team`, and `temporary team`.
- Contract/help tests reject invented `--prompt`, stale model ids, and any return
  of ephemeral/TTL teaching.

## Existing catalog cleanup

Cleanup is recovery, not architecture, and does not block `--seat`.

Use the existing exact-id `alln teams delete <team_id>` for known throwaways.
Do **not** add `teams purge --unused` in this packet: current Team files do not
carry a safe “throwaway” marker, and “not in retained run history” does not mean
the user does not want the Team. A bulk-delete feature needs its own explicit,
preview-first contract rather than a heuristic hidden inside runtime seating.

## Non-goals

- Ephemeral catalog entities, tags, hiding, promotion, TTL, or auto-prune
- Resuming Team Lab or changing built-in Team definitions
- Changing relay/pilot PM and dev pins (`pmWorkerId` / `devWorkerId`)
- Choosing a different lead or scout for one run
- GUI reseating in v1
- Per-seat skill edits or a JSON `--seats` blob

## Works Test

Use a real registered repo and ready models:

```bash
alln run "Review docs/phases/Ephemeral_Teams.md" \
  --project . \
  --team code_spec_review_min \
  --seat model_chatgpt \
  --seat model_grok \
  --seat model_cursor_composer_25 \
  --dry-run --json
```

The Works Test passes only when:

1. Dry-run reports the three chosen crew models in order, plus the unchanged
   Team lead, and its `argvTemplate` contains all three ordered flags.
2. The foreground form starts those exact crew models and records the ordered
   explicit selection.
3. TeamRunJSON and artifact reproduce commands emit the same three flags.
4. The Team catalog directory has the same paths and file hashes before and
   after dry-run and foreground run.
5. Wrong count, `--worker` + `--seat`, missing `--team`, unknown/not-ready id,
   incompatible row, and mixed-source mutation all refuse before spawn.
6. A capacity failure on an explicit crew seat does not silently substitute.
7. `alln help search "staff models once"` returns the `--seat` recipe, while
   `teams duplicate` teaches durable saves only.
8. Focused tests pass, followed by:

   ```bash
   bash scripts/check.sh
   ```

## Done when

- One atomic `alln run` gesture performs one-off crew staffing.
- No runtime path writes the Team or skill catalogs.
- Every execution/replay/handoff path preserves the ordered exact selection.
- Agent teaching makes duplication the durable-save gesture only.
- Contract artifacts are regenerated, the Works Test is recorded, and the
  packet is promoted to code/standing vocabulary then archived.
