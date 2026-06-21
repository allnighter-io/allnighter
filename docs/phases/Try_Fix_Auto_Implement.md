# Try Fix: Auto-Implement After Bug Hunt

Status: Draft feature packet
Owner: AllnighterCore + CLI/MCP + Mac app
Updated: 2026-06-21

## Why

Bug Hunt is valuable only if the user can act on it. The founder is not trying
to become the human compiler for several model opinions. The product win is:

```text
Find the bug -> choose the best fix packet -> try the fix with one trusted worker.
```

Today the founder can manually run Bug Hunt, read the output, then tell the
default worker to run the Debugger and fix it. If Allnighter stops at diagnosis,
it is not faster for non-developers. The missing capability is an explicit,
safe follow-up from a read-only answer team into a single mutating execution run.

## Founder Intent

- Raw request: add an option on Bug Hunt-style teams so the team can diagnose the
  bug and then the default model immediately tries the recommended fix.
- Product value: turn team diagnosis into working code without asking a
  non-developer to judge the packet manually.
- Trusted workflow slice: `bug report -> Send to team -> Code / Bug Hunt ->
  Try Fix -> one execution worker applies/proves the fix`.
- Non-goals: no parallel writers, no hidden approval ceremony, no prompt-only
  safety, no automatic high-risk changes, no new workflow product noun.

## Product Language

Working feature name: **Auto-Implement**.

Recommended checkbox label: **Try Fix**.

Why `Try Fix`: it is short, honest, and does not overclaim. It says Allnighter
will attempt the team's recommended fix, not guarantee a repair.

Label candidates:

| Candidate | Verdict |
| --- | --- |
| Try Fix | Recommended short label. |
| Fix It | Good button/action copy, slightly bossier as a checkbox. |
| Auto-fix | Familiar, but can sound magical or unsafe. |
| Apply Fix | Too certain unless the packet is already a patch. |
| Auto-Implement | Accurate internal phrase, long for primary UI. |

Suggested UI copy:

```text
[ ] Try Fix
```

Tooltip / accessible description:

```text
After this team returns a safe fix packet, run one execution worker in the repo
to try the recommended fix.
```

## Current State

- `code_bug_hunt` and `code_gui_bug_hunt` already exist as Code answer teams with
  `outputKind == bugPacket`.
- `default_chat` ("Auto") and `execution_playbook` already exist as mutating
  one-worker teams.
- `RunService` already enforces answer vs execution shape through
  `TeamPreset.mutating`, `RunShape`, and `RunWriteLock`.
- `TeamRunJSON.nextActions` and `FloorRun.nextActions` already expose typed
  follow-up actions, but they do not yet include a mutating fix attempt.
- The Debugger operation doc already defines the fix-quality packet:
  tier, symptom/repro, fingerprint, truth owner, lie-prone layer, regression
  considered, missing proof, fix boundary, and proof command.

## SSOT

Truth owner:

```text
AllnighterCore follow-up run policy:
  source answer run
  typed FixPacket
  chosen executor team
  parent/child run link
  gate decision
```

Lie-prone layers:

- SwiftUI checkbox state that starts a mutating run without a Core policy.
- Prompt prose that says "fix it" without a typed packet and deterministic gate.
- Markdown-only Bug Hunt output that cannot be validated before execution.
- A multi-worker Bug Hunt result silently becoming multiple mutating writers.

New semantic rules:

1. `Try Fix` is selected per run, and may later be saved as a team default only
   through the same CLI/MCP/Core contract.
2. `Try Fix` never changes the answer team into a writer. The answer team remains
   mechanically read-only.
3. If the answer run returns a safe `FixPacket`, Allnighter starts exactly one
   child execution run with the selected executor team.
4. If the packet is missing required fields or hits a high-risk stop, Allnighter
   does not execute. It returns an actionable blocked result.
5. The mutating child run uses the same repo root and takes the repo write lock.
6. The parent and child runs are linked durably so the Floor can show:
   diagnosis -> fix attempt -> proof.

Duplicate truth to delete:

- Any GUI-local "auto implement" bool not reflected in the run request.
- Any output parser that treats arbitrary markdown as safe-to-execute intent.
- Any separate JSON shape for the GUI; CLI, MCP, GUI, and iOS must project the
  same follow-up contract.

## Fix Packet

Bug Hunt and GUI Bug Hunt need to produce a structured packet, not just prose.

```text
FixPacket
  schemaVersion
  sourceRunId
  confidence: low | medium | high
  tier: T0 Fast | T1 Boundary | T2 SSOT | T3 Critical
  symptom
  repro
  bugFingerprint
  truthOwner
  lieProneLayer
  recommendedFix
  fixBoundary
  filesLikelyTouched[]
  proofCommand
  riskFlags[]
  stopReason?
```

Required for execution:

- `confidence != low`
- `tier != T3 Critical`
- `truthOwner` non-empty
- `recommendedFix` non-empty
- `fixBoundary` non-empty
- `proofCommand` non-empty, unless the selected executor preset owns proof
  discovery and the packet explicitly says so
- no high-risk `riskFlags`

High-risk stops:

- privacy or session data leaving the user's machines
- credentials, Keychain items, API keys, or auth state
- Full Disk Access or permission posture changes
- destructive process kill, deletion, or git history rewrite
- App Store, notarization, distribution identity, TestFlight release
- billing, entitlement, quota-spend behavior, or production deploy

## CLI/MCP Surface

This must land in the command registry before the GUI checkbox ships.

Preferred forward CLI shape:

```bash
alln run "The history view loses finished runs after restart." \
  --team code_bug_hunt \
  --try-fix \
  --executor execution_playbook \
  --json
```

Equivalent MCP `team_run` arguments:

```json
{
  "message": "The history view loses finished runs after restart.",
  "team": "code_bug_hunt",
  "tryFix": true,
  "executorTeamId": "execution_playbook"
}
```

JSON additions:

```text
TeamRunJSON / FloorRun
  followUpPolicy?
    tryFix: Bool
    executorTeamId
  links[]
    kind: diagnosisOf | fixAttemptFor | proofFor
    runId
  nextActions[]
    kind: tryFix
    command
    mutating: true
    disabledReason?
```

Error codes:

| Code | Meaning |
| --- | --- |
| `TRY_FIX_PACKET_MISSING` | Answer run did not produce a typed fix packet. |
| `TRY_FIX_PACKET_UNSAFE` | Packet had missing proof, low confidence, T3 tier, or high-risk flags. |
| `TRY_FIX_EXECUTOR_INVALID` | Executor team is unknown, non-mutating when mutating is required, or not runnable. |
| `RUN_WRITE_LOCK_BUSY` | Another mutating run is already editing this repo root. |

## Mac App Impact

Primary entry:

```text
Send to team -> Code / Bug Hunt
[ ] Try Fix
Executor: Auto
```

Rules:

- Show the checkbox only for teams that can return `FixPacket` or explicitly
  advertise `supportsTryFix`.
- Default unchecked until the follow-up contract is proven. Later, custom teams
  may save a default through `TeamPreset` / catalog state, not GUI-only state.
- Executor defaults to `Auto` or `Execution Playbook`; advanced users can change
  it to a source-scoped implementation team.
- The running state must show two honest phases:
  `Bug Hunt running` then `Fix attempt running`.
- If blocked, the user sees the missing field or stop reason, not a vague failure.

Floor next actions:

```text
Try Fix
Run fix with Auto
Run fix with Execution Playbook
Save packet to Pending
Send packet to another team
```

## iOS Impact

iOS presents the same contract later:

- show whether `Try Fix` was requested;
- show parent/child run status;
- allow starting the typed next action only when the Mac has the same gate result;
- never create a mobile-only auto-execute rule.

## Driver / Protocol Impact

- No driver runs multiple mutating workers for this feature.
- The executor receives one prompt containing the typed fix packet plus the user's
  original bug report and must run in the repo root.
- Driver permission prompts remain owned by the underlying CLI. Allnighter adds
  the repo write lock and typed follow-up gate, not a second permission layer.

## Inference Bans

| Junction | Owner | Possible bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Checkbox -> run request | Core command registry | GUI-selected checkbox implies execution | Only `tryFix: true` in the run request can start the chain | Toggle UI state without request field; no child run starts |
| Markdown -> execution | FixPacket parser/stage payload | Any markdown recommendation is safe | Require typed `FixPacket` and gate pass | Bug Hunt markdown with no packet returns `TRY_FIX_PACKET_MISSING` |
| Answer team -> writer | RunService | All Bug Hunt workers may patch | Child execution run has exactly one worker | `--try-fix` with mixed-source executor is rejected |
| Risk flags -> proceed | Follow-up gate | Model confidence overrides high-risk stop | High-risk flags block execution | Packet with credentials flag returns `TRY_FIX_PACKET_UNSAFE` |
| Parent -> child root | RunService | Child can pick a different cwd | Child run uses parent repo root | Test parent/child `repoRoot` equality |

## Implementation Slices

### TFX-S00 - Contract Packet

- Add `FixPacket` Core type or structured stage payload.
- Add `tryFix` follow-up policy shape to run request contracts.
- Add `tryFix` next-action kind and error codes to the registry.
- Regenerate `docs/generated/alln/*`.

### TFX-S01 - Gate And Links

- Add deterministic `TryFixGate`.
- Add parent/child run links.
- Prove missing packet, unsafe packet, invalid executor, and write-lock busy cases.

### TFX-S02 - CLI/MCP Execution

- Add `alln run --try-fix --executor <team>` and MCP `team_run.tryFix`.
- Run parent answer team, gate the packet, then start the child execution run.
- Return both run ids and the child status in JSON.

### TFX-S03 - Mac Checkbox

- Add the `Try Fix` checkbox to eligible team sends.
- Add executor selection with `Auto` as the simple default.
- Render parent/child progress and Floor next actions.

### TFX-S04 - Proof Failure Recovery

- If the child proof fails, show the failure and expose a typed next action:
  `Retry fix with proof failure`.
- Do not auto-loop indefinitely. V1 may allow one explicit repair attempt.

## Works Test

Scenario:

```text
Fixture repo has one failing test and one small known bug.
User runs Code / Bug Hunt with Try Fix enabled.
Bug Hunt returns a typed FixPacket.
Allnighter starts one mutating child run with Execution Playbook.
The child changes the file, runs the proof command, and records the result.
```

Exact command target:

```bash
alln run "Fix the failing parser test." \
  --team code_bug_hunt \
  --try-fix \
  --executor execution_playbook \
  --json
```

Assertions:

- parent run is non-mutating and has `teamPresetId == code_bug_hunt`;
- child run is mutating and has exactly one worker;
- parent and child share the same repo root;
- child run is blocked when `RunWriteLock` is held;
- unsafe packet does not start a child run;
- final JSON exposes parent/child links and exact next actions.

Missing proof / waiver:

- No proof exists yet. This doc is a planning artifact only.

## Done When

- `Try Fix` is available through CLI/MCP before the Mac checkbox.
- Bug Hunt-style teams can emit a typed `FixPacket`.
- Unsafe or incomplete packets block without starting a mutating run.
- Safe packets start exactly one child execution run under the repo write lock.
- The Floor shows diagnosis, fix attempt, proof output, and failure recovery.
- Generated contracts and fixture round-trips are updated.
- Works Test passes locally.

## Open Questions

- Should the default executor be `Auto` or `Execution Playbook`?
- Should built-in Bug Hunt default `Try Fix` off forever, or allow the user to
  save it on for custom duplicates?
- Should `confidence == medium` execute by default, or require `high` for the
  first release?
- Is one explicit repair attempt enough for proof failures, or should that wait
  for a later workflow/loop product?
