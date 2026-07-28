# Pilot Status Liveness Lie — Hotfix

Status: **Ready for Implementation**
Owner: AllnighterCLI (`PilotCLI`) + AllnighterEngine (`ProcessGroupCommandRunner` /
`RelayCoordinator` touch only as needed)
Updated: 2026-07-28
Incident date: 2026-07-28
Related (do not reopen; this packet amends their product junction):

- archived [`Pilot_Long_Turn_Survival.md`](../archive/phases/Pilot_Long_Turn_Survival.md)
  (PLT-S02 taught agents `silenceAgeSeconds` = PRIMARY liveness)
- archived [`Idle_Stall_False_Kill_Hotfix.md`](../archive/phases/Idle_Stall_False_Kill_Hotfix.md)
  (IDLE-HF-S02 `pgid_activity` refreshes turn heartbeat; IDLE-HF-S04 stall =
  detect-only, wall hard-kills)

## Origin

External PM agent on pilot mode (Composer 2.5 / `cursor_agent`) dispatched a
round whose verify step ran `npx wrangler tail …` — a non-terminating stream.
That is a bad work order. It exposed an Allnighter product lie:

```text
$ alln ps
… alive, no stream for 1858s

$ alln pair pilot status --relay relay_cd0e7b26-… --json
silenceAgeSeconds: 1
lastProgressAt:    <now>
```

Same run, same second. Docs tell agents to prefer `pilot status` and treat
progress as PRIMARY liveness. Polling correctly kept a hung round "healthy"
for 30+ minutes. Wall (3600s) was the only hard stop.

## Product lie

`pair pilot status` documents `lastProgressAt` / `silenceAgeSeconds` as
**PRIMARY liveness** meaning "the dev seat is progressing."

Code computes them as the **freshest of**:

1. `run.json.lastActivityAt` (RLR-L6 — real stream / message / stdout events)
2. relay-dir `heartbeat.json.lastProgressAt` (turn ProgressTracker — includes
   `pgid_activity` from child CPU / spawn under the worker process group)

`alln ps` for the run row already uses (1) only and correctly reported stream
silence. Status merged in (2) and lied.

## Evidence (verified 2026-07-28 on founder Mac)

Relay `relay_cd0e7b26-bc5a-4c48-b3d7-6873d6418cad`, run
`A88F7133-7E83-454D-B16B-BDAFBF5D5323`:

| Fact | Value |
| --- | --- |
| Relay dir files advancing mid-hang | **only** `heartbeat.json` |
| Heartbeat `phase` | `pgid_activity` |
| Heartbeat `sequence` | 2024 (thousands of "progress" writes) |
| `run.json.lastActivityAt` | `2026-07-28T21:39:19Z` (~4 min after start) |
| `lastActivityKind` | `message` |
| Run `clockBudgets.idleTimeoutSeconds` | **absent** (no `--idle-timeout`) |
| Run `clockBudgets.wallTimeoutSeconds` | 3600 |
| Relay round `devRunId` mid-flight | **null** (status could not even prefer the journal) |
| Mid-round worker transcript in relay / run workers dir | **none** (only `*.owner.json`) |

Root cause stack (each piece defensible alone; together catastrophic for agents):

1. **PLT-S02** — teach `silenceAgeSeconds` as PRIMARY; poll hint 45s.
2. **IDLE-HF-S02** — sample recorded pgid; on child CPU/spawn call
   `progress.note("pgid_activity")` → `recordProgress` into turn heartbeat.
3. **PilotCLI.resolveLastProgressAt** — `max(journal, relay heartbeat)`.
4. **IDLE-HF-S04** — identity-alive stall is detect/surface only; wall kills.
5. **Pilot without `--idle-timeout`** — journal idle budget stays `nil`.

A blocked `wrangler tail` under cursor-agent keeps the pgid "busy," refreshes
PRIMARY liveness forever, and never trips an idle reap.

## Founder intent

Agents polling `pilot status` must answer "is the **dev seat stream** moving?"
without hand-correlating `alln ps`. Owner/tree aliveness may still be reported —
under **different names**. Do not reverse IDLE-HF-S04 kill policy in this packet.

## Non-goals

- Do not re-open IDLE-HF kill-on-stall (S04). Wall stays hard stop unless a
  **new** founder ruling changes kill policy.
- Do not treat repo/cwd mtimes as progress (IDLE-HF ban stands).
- Do not make `--idle-timeout` mandatory UX for every pilot start.
- Do not build a full live transcript UI / GUI board (see deferred S03).
- Do not fix bad work orders (unbounded `wrangler tail`) in Allnighter — teach
  agents that stream silence is the signal; PMs own bounded verify steps.

## Ship order (locked)

```text
PLS-S01  Bleed stop — honest PRIMARY = stream only          ← ship first
PLS-S02  Link + warn — stamp devRunId early; silence warn   ← same PR ok if small
PLS-S03  Mid-round partial pointer                          ← DEFERRED
```

---

### PLS-S01 — Bleed stop: PRIMARY liveness = stream silence

**Goal:** An agent following docs cannot be told a zero-stream hung round is
freshly progressing.

#### Truth owner

- PRIMARY stream liveness: `TeamRun.lastActivityAt` / `lastActivityKind`
  (RLR-L6) via `RunStore`.
- SUPPLEMENTARY tree/owner busyness (optional): relay-dir heartbeat /
  `pgid_activity` — **never** under the names `silenceAgeSeconds` /
  `lastProgressAt` once this slice lands.
- `ownerAlive` stays owner-identity liveness (unchanged meaning).

#### Touch

- `Packages/AllnighterCore/Sources/AllnighterCLI/PilotCLI.swift`
  (`resolveLastProgressAt`, `longJobStatusFields`, `PilotStatusJSON`,
  recovery/nextAction prose that says "progress is primary liveness")
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift`
  (`pair pilot status` FlagSpec / summary)
- Generated: `docs/generated/alln/*` via `alln dev export-contracts`
- Help topics that name `silenceAgeSeconds` / PRIMARY liveness (same slice)
- Tests: `PilotCLITests` (extend / replace the "fresh progress" case so a
  stale journal + hot relay heartbeat cannot look fresh)

#### Steps

1. **Stop the merge lie.** `resolveLastProgressAt` (or replacement) must use
   **only** `runStore.load(devRunId)?.lastActivityAt` for PRIMARY fields.
   Do **not** `max()` with `ProcessOwnership.lastProgressAt(in: relayDir)`.
2. **Rename or dual-emit (hard cut preferred):**
   - Keep `lastProgressAt` / `silenceAgeSeconds` = stream only (breaking
     semantics fix; same field names, honest meaning — matches `ps`).
   - If tree busyness is still useful, add optional
     `treeActivityAt` / `treeSilenceAgeSeconds` (or `pgidActivityAgeSeconds`)
     sourced from relay heartbeat — labeled **SUPPLEMENTARY / not liveness**
     in contract + JSON comments/docs the same way `commitsSinceBaseline` is.
3. **Teaching (same slice):** rewrite `pair pilot status` summary and any
   `nextAction` / bootstrap / help prose that says "progress is primary
   liveness" to mean **worker stream / `lastActivityAt`**, and to say tree/CPU
   activity is supplementary if exposed. Sweep retired contradictory wording.
4. **Inference ban (test):**  
   `pgid_activity` / relay `heartbeat.json` refresh ↛ PRIMARY
   `silenceAgeSeconds` near zero when `run.lastActivityAt` is stale.

#### Proof (S01)

```bash
swift test --package-path Packages/AllnighterCore \
  --filter 'PilotCLITests|ContractRegistry'

# Works Test (unit seam):
# - relay heartbeat lastProgressAt = now, phase pgid_activity
# - linked run lastActivityAt = now - 1800s
# - longJobStatusFields → silenceAgeSeconds ≈ 1800 (not ≈ 0)
# - if treeSilenceAgeSeconds present → small; contract labels it not-primary
```

**Done when:** the incident contradiction cannot reproduce under the unit seam;
contract/help no longer teach heartbeat/pgid as PRIMARY.

---

### PLS-S02 — Stamp `devRunId` early + stream-silence warning

**Goal:** Status can always read the journal while running, and agents get an
explicit warning once stream age blows past the poll hint — without needing
`alln ps`.

#### Touch

- `RelayCoordinator` (ensure `round.devRunId` is persisted **before** the
  long wait / detach; incident had `devRunId: null` mid-flight)
- `PilotCLI` / `PilotStatusJSON`: emit `devRunId` (or rely on existing
  `relay.roundLog[].devRunId` once stamped — verify agents can see it on
  `pilot status --json` without digging `relay.json` by hand)
- Optional fields: `streamSilenceWarning: Bool` and/or reuse
  `OwnershipSilencePresentation`-style one-liner on status
- Threshold: warn when `silenceAgeSeconds > k * waitHintSeconds` (default
  `k = 6` → 270s at hint 45; tune in slice, document in FlagSpec). Warning
  only — **no kill** (S04 stands).

#### Steps

1. Find why incident round lacked `devRunId` mid-flight; fix the write path so
   every `.running` pilot round has a durable `devRunId` as soon as the run is
   minted / accepted.
2. Status while running: if journal missing/`lastActivityAt` nil, PRIMARY
   silence is "no stream yet" / omit freshness claim — never fall back to
   heartbeat as primary.
3. When stream silence exceeds threshold, set warning flag and bias
   `nextActions` / `recovery` copy toward inspect (`alln ps`, run id) —
   still not "healthy, keep waiting" only.
4. Teaching: document the warn threshold; keep `waitHintSeconds: 45`.

#### Proof (S02)

- Unit: after mock dispatch accept, `RelayState.rounds.last.devRunId` non-nil
  before any wait.
- Unit: silenceAge 300s + hint 45 → `streamSilenceWarning == true` (or
  equivalent named field).
- Contract export check green.

**Done when:** a PM agent can see stream silence + warning from
`pilot status --json` alone, with a linked run id.

---

### PLS-S03 — Mid-round partial pointer (DEFERRED)

**Not in the bleed-stop PR.** Cursor-agent already runs with stream-partial
output; nothing in the relay dir captured it during the hang.

Candidate (re-scope later):

- Coalesced partial answer / last N stream events under the run dir (not
  relay), and/or `pilot status` field `partialRef` / `devPartialPreview`
  bounded to a few KB.
- Must not thrash disk (reuse RLR-L6 coalesce). Must not invent progress from
  partial presence alone.

Gate to open S03: S01+S02 shipped + one more dogfood hang where agents still
cannot diagnose without attaching to the worker process.

---

## Inference bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Turn heartbeat → pilot PRIMARY | `PilotCLI.resolveLastProgressAt` | `pgid_activity` / heartbeat refresh ⇒ worker progressing | PRIMARY fields read **only** `run.lastActivityAt` | Stale journal + hot heartbeat ⇒ large `silenceAgeSeconds` |
| Child CPU → stream liveness | IDLE-HF-S02 vs PLT-S02 | Process-group CPU ⇒ stream not silent | Tree busyness ≠ `silenceAgeSeconds` | Same as above |
| `ownerAlive` → work moving | `PilotStatusJSON` | Live handoff pid ⇒ output flowing | `ownerAlive` is identity only | Alive owner + stale stream still warns |
| Missing `devRunId` → use heartbeat | `RelayCoordinator` / status | No journal link ⇒ heartbeat is fine as primary | Never substitute heartbeat for stream | Nil `devRunId` ⇒ PRIMARY omitted or "no stream yet", not fresh heartbeat |

## CLI / teaching surface

| Surface | Change |
| --- | --- |
| `alln pair pilot status --json` | Honest PRIMARY fields; optional supplementary tree ages; warning flag |
| `ContractRegistry` `pair pilot status` | Rewrite PRIMARY wording; label any tree fields supplementary |
| Help / bootstrap / nextAction | "stream silence is primary"; point at `alln ps` only as secondary |
| `alln ps` | Unchanged truth (already stream-based for runs) |

Closeout questions (founder-input workflow):

- Which HelpTopicRegistry topics teach `pilot status` liveness?
- Do they name only flags/commands that resolve in ContractRegistry?
- Does `help search` for "pilot silence" / "liveness" / "hung round" hit them?

## Risk

- Low privacy / credentials.
- Semantic break for any agent that treated near-zero `silenceAgeSeconds` as
  "pgid still busy" — that reading was never documented; documented reading was
  worker progress. Fix restores the doc.
- No new kill behavior in S01/S02.

## Done when (packet)

1. Incident contradiction fails the new unit seam.
2. Contract + help teach stream-primary honesty.
3. Running pilot rounds expose `devRunId` + stream-silence warning path.
4. S03 still deferred unless founder reopens.
5. Promote keepable law into code comments / ContractRegistry; archive this
   packet. Update `AGENTS.md` / `docs/phases/README.md` routes on archive.
