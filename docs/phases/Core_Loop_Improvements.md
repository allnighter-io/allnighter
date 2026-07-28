# Core Loop Improvements — honest status, zero archaeology

Status: **Authorized — one PR** (CLP-S01 + S02/S07 + S03) + passengers (S05
teaching, S08 notification wire-up). Phase doc, not SSOT.
Owner: AllnighterCLI + AllnighterEngine
Created: 2026-07-28
Finalized: 2026-07-28 (founder + review convergence)
Origin: post-PLS dogfood + Gemini relay smoke; sharpened after first-principles
review (nine slices → one ship).

Companions:

- Strategy anchor: `docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md`
- Product vocabulary: `docs/workflows/Product_Vocabulary.md`
- Closed liveness hotfix (partial): `docs/archive/phases/Pilot_Status_Liveness_Lie_Hotfix.md`
- Ownership / reconcile law: `docs/archive/phases/Process_Ownership.md`
- Notifications: archived `Unattended_Round_Notification.md` (URN — S08 extends)

## Founder intake (SSOT)

```text
Founder intent:
  Fix the control loop for good — honest liveness, no ghost running state, ps that
  shows the floor. Strip bloat (intent flags, verify linter, doctor modes).

Product value:
  Operators and host agents trust status on first poll; no kill/reconcile
  archaeology before every session.

Trusted workflow slice:
  Unattended: pair relay → relay-status / notification → terminal verdict.
  Attended: menu → team run / run → artifact show.

Current state:
  PLS-S01/S02 shipped for pilot status only (stream-primary + early devRunId).
  Other surfaces and reconcile-on-read still open. Default ps is noisy.

Truth owner:
  Run journal (`run.lastActivityAt`) = PRIMARY liveness;
  `ProcessOwnership` + reconcile = terminal state;
  `RelayCoordinator` round log = correlation IDs.

CLI surface (this PR):
  Behavior changes only — no new nouns. Touches: alln ps, pair pilot status,
  pair relay-status. Default ps filter; --all for history (verify flag exists or add).

Help surface (same PR closeout):
  Update pair/pilot/ps teaching in ContractRegistry — stream-primary liveness
  everywhere; reconcile-on-read (no manual team reconcile on happy path); default
  ps = alive + needs-action, --all = history. help search "liveness", "stuck",
  "ghost running" → those topics.

Proof scenario:
  1. Fixture: advancing heartbeat + frozen run.lastActivityAt → all status surfaces
     report stream silence (contract test).
  2. kill -9 relay owner → next pilot status / relay-status terminal, no manual
     reconcile.
  3. After 10 completed relays, default ps ≤ alive + needs-action rows; --all
     shows museum.

Blocking questions:
  None — authorized.

Next slice:
  Ship CLP-S01 + S02/S07 + S03 in one PR; S05 teaching + S08 wire-up same merge
  or immediate follow-up.
```

## One-sentence version

One PR makes **liveness honest everywhere**, **dead owners terminal on read**,
and **`ps` show the floor** — plus teaching and a notification hook.

## Product bar

```text
Human:     delegates a round, walks away, gets honest terminal + notification
Agent:     polls status once; stream silence is silence; no hand-merge ps + heartbeat
Operator:  zero archaeology (no manual reconcile on happy path)
```

## The single ship (one PR)

All code work below ships together. Code SSOT: `PilotCLI.swift`,
`ProcessOwnership` / `ProcessOwnershipSurface`, `RelayCLI`, `RelayCoordinator`
(correlation tests only if not already covered by PLS-S02).

### CLP-S01 — Honest liveness everywhere

**Delivers:** Audit all progress readers (`alln ps`, `pair pilot status`,
`pair relay-status`) so `run.lastActivityAt` (stream / journal events) is the
**only** PRIMARY liveness metric. Heartbeat, pgid CPU, `commitsSinceBaseline`,
and tree mtimes may appear as **supplementary** fields — never merged into
`silenceAgeSeconds` or `lastProgressAt`.

**Already shipped (PLS):** `PilotCLI.resolveLastProgressAt` — stream only.
**Still open:** every other reader; contract tests that forbid heartbeat merge;
`ContractRegistry` teaching parity across surfaces.

**Proof:** Machine test — advancing `heartbeat.json` + frozen
`run.lastActivityAt` → all status surfaces report stream silence.

---

### CLP-S02 + CLP-S07 — Reconcile-on-read + mid-flight IDs

**Delivers:**

1. Hook `ProcessOwnership` identity check into **all** status read paths (`ps`,
   `relay-status`, `pilot status`). If owner is identity-dead, eagerly reconcile
   to terminal (`stopped` / `reconciledOrphan`) in that same response.
2. Verify `devRunId` (and `pmRunId` where applicable) is **non-null** across all
   mid-flight states — including the window between `persistDeliveredDevRun` and
   run completion (extends PLS-S02).

**Proof:**

- `kill -9` relay owner mid-round → first status poll returns terminal + reason;
  zero manual `team reconcile`.
- Coordinator test — status between early persist and `runService.run` completion
  returns non-null `devRunId`.

---

### CLP-S03 — Honest default `alln ps`

**Delivers:** Default `alln ps` lists **alive + needs-action** only:

- running (identity alive)
- awaiting PM / escalated / parked (actionable non-terminal)

Historical terminal rows (done, stopped, reconciled orphan, identity-dead museum)
behind **`--all`**. Do not hide actionable parked states.

**Proof:** After 10 completed relays, default `ps` row count bounded; `--all`
shows full history.

---

## Passengers (zero-to-low code)

Ship with the PR or immediate follow-up in the same merge window.

### CLP-S05 — Golden path (0 LOC)

Teaching and prompt snippets only — no new commands.

```text
Attended:   menu → team run / run → artifact show → done
Unattended: pair relay --doc … → pair relay-status (or notification) → done
```

Escalation verbs (`pilot watch`, `relay adopt`, harness proof tickets) stay out
of day-one teaching. Optional: `scripts/agent_eval.sh` case using golden path only.

### CLP-S08 — Silence notification (~5 LOC)

Wire existing `streamSilenceWarning` from pilot status into URN notification
candidates (`NotificationCandidateDetection` / `NotificationScheduler`). Humans
get a macOS banner when stream stalls; agents keep polling JSON.

Depends on CLP-S01 (warning must mean stream silence, not heartbeat).

---

## Killed (do not build)

| Slice | Idea | Why killed |
| --- | --- | --- |
| **CLP-S04** | `--intent smoke\|dry-run` on dispatch | Flag sprawl; branch policy + work order own mutation |
| **CLP-S06** | PM verify linter (`wrangler tail`, etc.) | Fragile regex over prose; teach in envelopes |
| **CLP-S09** | `doctor --for relay` sub-modes | Doctor stays one fast host diagnostic |

## Deferred (v2 — does not block ship)

| Item | Notes |
| --- | --- |
| **Unified status projector** | One JSON schema for ps / pilot / relay-status. High value for host agents; refactor slice after v1 semantics align. |
| GUI live board as default floor | Strategy: CLI + notifications first |
| Mandatory `--idle-timeout` | Rejected in PLS — optional + `streamSilenceWarning` |
| Repo mtime as liveness | Rejected in IDLE-HF |
| Multi-tenant / hosted relay | Out of scope |

## Overfitting check (historical)

Sparked by one Gemini smoke relay + PLS incident. Recommendations justified by
**incident class** (PLS, IDLE-HF, Process Ownership, RLR) and **agent poll
scale**, not cohort analytics. Pre-launch founder dogfood only.

Smoke-test overfits removed with CLP-S04 kill — git policy is work-order scope.

## Closeout checklist

- [ ] CLP-S01 contract tests green
- [ ] CLP-S02 reconcile-on-read on ps, relay-status, pilot status
- [ ] CLP-S03 default ps filter + `--all` documented
- [ ] CLP-S07 mid-flight `devRunId` tests green
- [ ] `ContractRegistry` teaching updated (help closeout law)
- [ ] `alln dev export-contracts --check`
- [ ] CLP-S05 teaching snippets (0 LOC)
- [ ] CLP-S08 `streamSilenceWarning` → URN (optional same PR)
- [ ] Works test: kill -9 owner → status terminal without manual reconcile
- [ ] Archive this packet when merged; promote standing ops note if needed

## What would falsify v1

- Reconcile-on-read causes measurable lock contention (benchmark; unlikely).
- Default `ps` hides actionable parked/escalated relays (fix filter, not revert).

---

*Ephemeral packet — archive to `docs/archive/phases/` when the PR merges;
promote durable law to `docs/operations/` or code contracts as needed.*
