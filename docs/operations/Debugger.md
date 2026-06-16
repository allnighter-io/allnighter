# Debugger

Debugger is the front door for bug reports. Its job is to stop symptom patches:
name the truth owner, lie-prone layer, and missing proof before editing.

## Intake

For every non-trivial bug:

1. Search `Docs/operations/debugger/BUG_PATTERNS.json`.
2. Search `Docs/operations/debugger/DEBUGLOG.md`.
3. Inspect current diff for the touched surface before hypothesizing.
4. Classify tier.
5. Write the packet.

For `T3` and repeated bugs, prior art starts at step 1 — not a blank investigation.

### Loop budget

A worker may reclassify a bug at most twice. After that, stop, report conflicting
evidence, and ask for a boundary decision instead of continuing to patch.

After root cause, answer:

```text
What was the agent allowed to do that must never be allowed again?
```

That answer becomes a regression law with a wall-reachable command (see
`Docs/operations/debugger/BUG_PATTERNS.json` and `REGRESSION_LAW_BACKLOG.md`).

Bug fingerprint:

```text
<surface/path> + <symptom> + <likely truth-owner/proof-gap>
```

## Tiers

| Tier | Use when | Required behavior |
| --- | --- | --- |
| `T0 Fast` | Copy, spacing, paint, focus, icon, haptic timing only | Fix surgically. |
| `T1 Boundary` | UI-visible navigation/read-only bug or simple uncertain bug | Name observed layer and likely truth owner. |
| `T2 SSOT` | Session state, connection status, parsed events, diff cards, pairing, persisted data, or cross-layer state | Full packet before code. |
| `T3 Critical` | Data loss, privacy/security, credentials, destructive process kill, permission regressions, or repeated bug | Full packet, regression audit, log entry. |

If unsure, classify higher for analysis; evidence may downgrade.

## Default Debug Law

If a visible bug involves session status, connection state, parsed output, diff
approval state, pairing, permissions, or persisted data, first hypothesis is
SSOT drift.

Disprove SSOT drift with positive evidence from the owner: Swift model, contract,
WebSocket message, persisted reload, parser fixture, or focused test. A view
read is not enough.

## GUI-Visible Bugs — Layout Gate

If the bug is a visible layout failure (clipped, collapsed, overlapping,
off-screen, scrim/z-order, detached, or missing UI), it is not fixed from build
or code confidence. Before closeout:

1. Render the changed surface: `bash scripts/gui_proof.sh <fixture>` (fixtures in
   `Apps/AllnighterMac/Sources/GUIFixture.swift`).
2. Spawn the **layout-watcher** (`.claude/agents/layout-watcher.md`) — a separate
   agent, never the one that wrote the fix — on the render.
3. `fixed` requires a watcher PASS (no P1). A broken render/harness is `blocked`,
   not `fixed`.

The watcher is the eyes the building agent lacks. See
`docs/phases/GUI_Visual_Proof_Gate.md`.

## Debug Packet

```text
Tier:
Symptom / repro:
Bug fingerprint:
Truth owner:
Lie-prone layer:
Regression considered:
Missing kill test / proof:
Fix boundary:
Proof command / founder test:
```

## Forbidden Moves

- Patch SwiftUI because a semantic value looks wrong before naming the owner.
- Add silent fallbacks around required semantic fields.
- Treat connection `connected`, build success, or "it compiled" as durable proof.
- Close a GUI-visible bug without a layout-watcher PASS on a rendered fixture
  (a screenshot the building agent merely produced is not proof; a separate
  watcher looking at it is).
- Combine unrelated cleanup with a bug fix.
- Hide a repeated bug without adding or naming regression proof.

## Closeout

For `T1-T3`, report:

```text
Tier:
Boundary verdict:
Proof gap:
Fix boundary:
RCA:
Proof:
Founder test:
```

Definition of done:

1. Kill test exists: red on pre-fix code, green after.
2. Green wall passes locally (`bash scripts/check.sh` when available).
3. CI green when wired.
4. Founder-found or repeated bug: DEBUGLOG `Proof:` names a wall-reachable test.
5. `T2`/`T3` or repeated: regression law with wall command, or expiring blocker
   in `QUARANTINE.md`.
6. GUI-visible bug: layout-watcher PASS on a rendered fixture (see GUI-Visible
   Bugs above); name the fixture + verdict in the closeout.
7. Founder test = confirmation of feel, never proof of correctness.

Append to `Docs/operations/debugger/DEBUGLOG.md` for every repeated bug and
every `T3`.
