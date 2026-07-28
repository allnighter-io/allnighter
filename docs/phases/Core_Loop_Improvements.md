# Core Loop Improvements — operator truth, agent scale, golden path

Status: **Open — planning packet, no work authorized.** Phase doc, not SSOT.
Owner: Founder (prioritization); AllnighterCLI + AllnighterEngine (execution)
Created: 2026-07-28
Origin: post-PLS hotfix dogfood + Gemini relay smoke (2026-07-28); prior
incident class across archived packets (see Evidence).

Companions:

- Strategy anchor: `docs/strategy/Allnighter-Agent-Control-Loop-Strategy.md`
- Product vocabulary: `docs/workflows/Product_Vocabulary.md`
- Closed liveness hotfix: `docs/archive/phases/Pilot_Status_Liveness_Lie_Hotfix.md`
- Ownership / reconcile law: `docs/archive/phases/Process_Ownership.md`
- Run lifecycle: `docs/archive/phases/Run_Lifecycle_Reliability.md`
- Agent front door (shipped): archived `Menu_Not_Router.md`, `Agent_Front_Door.md`

## Founder intake (SSOT)

```text
Founder intent:
  After PLS fix + relay smoke, capture first-principles improvements without
  overfitting one test; rank what generalizes to many agents/humans; commit as
  a phase packet for later prioritization.

Product value:
  Honest control loop — operators and host agents trust status, spend less time
  on kill/reconcile archaeology, and run unattended relay/team loops safely.

Trusted workflow slice:
  Unattended: pair relay → relay-status / notification → terminal verdict.
  Attended: menu → team run / run → artifact. (Golden path — CLP-S05.)

Current state:
  PLS-S01/S02 shipped (stream-primary pilot status, early devRunId). Relay smoke
  passed on model_gemini. Orphan/stale relay state still needs manual reconcile
  on some paths. Default ps is noisy. Smoke relay committed to branch (no intent mode).

Truth owner:
  Run journal (`RunService` / `run.lastActivityAt`) for PRIMARY liveness;
  `ProcessOwnership` + reconcile for terminal state; `RelayCoordinator` round log.

CLI surface:
  None in this packet (planning only). Proposed slices name future surfaces:
  reconcile-on-read (ps, relay-status, pilot status), --intent smoke|dry-run,
  doctor --for relay, default ps filter, bounded-verify lint.

Help surface (topics / search terms / recovery):
  Not yet — no shipped CLI change. When CLP-S01+S02 ship: update pair/pilot/ps
  teaching topics; help search "liveness", "stuck relay", "reconcile";
  recovery → doctor --for relay, pair relay-status.

Proof scenario:
  CLP-S01: heartbeat-advancing + frozen journal → all status surfaces report
  stream silence. CLP-S02: kill -9 relay owner → first pilot status terminal.

Blocking questions:
  Which slice to authorize first? (Packet recommends CLP-S01+S02.)

Next slice:
  Founder pick — recommend CLP-S01 + CLP-S02 (liveness audit + reconcile-on-read).
```

## One-sentence version

Tighten the **control loop** so every human and every agent gets the same
durable truth on liveness, terminal state, and next action — without archaeology
before every session.

## Overfitting check (read this first)

This packet was **sparked** by one successful Gemini relay smoke and one brutal
liveness incident. It does **not** treat either as market research.

| Evidence tier | What it is | What we can claim |
| --- | --- | --- |
| **A — Incident class** | Multiple shipped hotfixes and audits (PLS, IDLE-HF, Process Ownership, RLR, CODE_RED) | Same failure modes recur when surfaces disagree or orphans linger |
| **B — Architecture / strategy** | Unified run model, control-loop thesis, agent-native dogfood bar | Recommendations align with stated product law even at N=1 |
| **C — Agent scale model** | Agents poll JSON status; humans delegate; hosts are Claude/Cursor/Codex/etc. | Fixes that reduce per-poll cognitive load **multiply** with agent count, not user count |
| **D — Single smoke relay** | One `pair relay`, `model_gemini` both seats, trivial work order | Proves the loop **can** complete; does **not** prove UX for novices or multi-repo fleets |

**Honest scope:** Allnighter is pre-launch founder dogfood. There are not
hundreds of external users yet. The recommendations below are justified for
**hundreds of agents and polling loops** (the actual scale vector) and for
**any human who must trust status without becoming an operator**. They are
**not** validated by cohort analytics. Where we lack data, slices name a cheap
proof instead of pretending we know adoption.

What **was** overfit from the smoke test alone:

- Vendor choice (Gemini / `agy`) — irrelevant to the list.
- “Relay always commits” — one data point; generalized only as **mutation intent**
  (see CLP-S04), not “never commit on relay.”

What **generalizes** without overfitting:

- **Truth fragmentation** hurts more when agents automate polling (C) than when
  a founder eyeballs `ps` once (D).
- **Orphan / stale terminal state** compounds with session count and blocks
  unattended loops for everyone (A + B).
- **Surface sprawl** taxes every host agent that must choose a verb (B + C).

## Product bar (who this is for)

```text
Human:     delegates a bounded round, walks away, gets a honest terminal + next action
Agent:     polls one JSON surface, never hand-merges ps + pilot + heartbeat
Operator:  zero-session archaeology (kill/reconcile/status triage) for the happy path
```

Success is **not** “more CLI nouns.” Success is **fewer decisions per loop**
at equal safety.

## Top recommendations (ranked)

Priority reflects **blast radius × agent multiplier × alignment with shipped law**,
not ease.

### 1. One liveness contract, every surface (CLP-S01)

**Claim:** Stream-primary liveness must be the **only** PRIMARY progress signal
for run rows and pilot/relay status. Supplementary signals (heartbeat, pgid CPU,
`commitsSinceBaseline`, tree mtimes) are labeled secondary and never merged into
`silenceAgeSeconds` / `lastProgressAt`.

**Why it generalizes:** PLS was not a one-off — IDLE-HF intentionally wrote
`pgid_activity` into heartbeat; PLT-S02 taught agents to trust status PRIMARY.
Any host agent polling the wrong surface makes **every** long turn look healthy.
At 100 agents × 45s poll interval, a 30-minute lie is thousands of wrong decisions.

**Partially shipped:** PLS-S01/S02 (`PilotCLI.resolveLastProgressAt`, early
`devRunId`). **Still open:** audit every other reader/writer of progress age;
contract tests that forbid merge; teaching parity in `ContractRegistry`.

**Proof:** Machine test — fixture with advancing heartbeat + frozen
`run.lastActivityAt` must report stream silence on **all** status surfaces.

---

### 2. Reconcile on read, terminal by default (CLP-S02)

**Claim:** Any status/list command (`ps`, `relay-status`, `pilot status`, menu
health) **eagerly reconciles** identity-dead owners and returns terminal state
in the same response. Humans and agents should not need a separate
`team reconcile` / `relay-status` triage step on the happy path.

**Why it generalizes:** Process Ownership packet already defines
`identityAlive → reconciledOrphan`; smoke still left `running` + dead owner
until explicit reconcile. That pattern scales badly: every new user (and every
agent session) starts with distrust. Unattended relay (URN) cannot notify
“needs you” if status says `running` forever.

**Proof:** Works test — kill -9 relay owner mid-round; first `pilot status`
returns `stopped` + reason, zero manual reconcile.

---

### 3. `ps` shows the floor, not the museum (CLP-S03)

**Claim:** Default `alln ps` lists **alive or needs-action** processes for the
current project (and opt-in `--all` for history). Historical terminal relays /
pilots should not crowd the default view.

**Why it generalizes:** Agent context windows are finite. Dumping dozens of
`identityAlive: false` rows trains host models to ignore `ps`. Humans scanning
for “what’s running now” suffer the same noise. This is UX law, not a smoke-test
artifact.

**Proof:** Dogfood script — after 10 completed relays, default `ps` row count
bounded (e.g. ≤ active + 2 parked), full history available via flag.

---

### 4. Mutation intent on dispatch (CLP-S04)

**Claim:** Mutating runs declare intent: **production** (default), **smoke**
(no git commit; scratch paths or auto-revert), **dry-run** (read-only). Relay
and `alln run` respect the mode; proof gates adjust accordingly.

**Why it generalizes:** The smoke relay committed to `feat/design-chain`. One
founder may want that; any shared bench, CI agent, or junior operator will not.
This is safety at scale, not “that commit annoyed me once.”

**Not claiming:** full git policy product — only explicit intent at dispatch so
agents can default safe.

**Proof:** `--intent smoke` relay completes without branch mutation; artifact
still records what would have changed.

---

### 5. Golden path as the only required mental model (CLP-S05)

**Claim:** Document and instrument one attended loop and one unattended loop,
each ≤5 commands, with `nextActions` in JSON always populated until terminal:

```text
Attended:   menu → team run / run → artifact show → done
Unattended: pair relay --doc … → pair relay-status (or notification) → done
```

Everything else (`pilot watch`, `relay adopt`, proof tickets, harness verbs) is
**escalation**, not day-one vocabulary. Menu remains front door; help search
should not surface escalation verbs before golden path.

**Why it generalizes:** Strategy doc ranks host CLI + `alln` as surface #1.
Every extra noun is tax on **every** host agent’s tool list across vendors.
Narrowing the hero path helps N users indirectly by helping N×agents.

**Proof:** `scripts/agent_eval.sh` suite — fresh agent can complete unattended
relay using only golden-path commands in teaching snippets.

---

### 6. Bounded verify is PM law, not agent improvisation (CLP-S06)

**Claim:** Relay / pilot teaching and PM envelopes forbid unbounded verify steps
(`tail -f`, `wrangler tail`, watch modes) unless explicit `--allow-streaming-verify`.
Default proof profile uses bounded commands with timeouts.

**Why it generalizes:** PLS incident trigger was a bad work order — but the
product **amplified** harm by lying about liveness. Even with honest liveness,
unbounded verify still wastes quota across **any** vendor seat. PM templates
should encode the bound so **every** PM worker inherits it.

**Proof:** PM envelope lint or doctor check flags unbounded patterns in
`--doc` before dispatch.

---

### 7. Mid-flight correlation always on (CLP-S07)

**Claim:** From first dev dispatch, `relay-status` / `pilot status` always carry
`devRunId`, `pmRunId`, and deep links (`alln ps --run …`, journal path). Never
`null` mid-round while a turn is in flight.

**Why it generalizes:** Agents correlate logs across surfaces by ID. Null
`devRunId` forced fallback to heartbeat (PLS evidence). Early stamp shipped in
PLS-S02; extend to **all** round states and failure paths.

**Proof:** Coordinator test — status queried between `persistDeliveredDevRun` and
`runService.run` completion returns non-null `devRunId`.

---

### 8. Human attention via notification + verdict, not polling (CLP-S08)

**Claim:** For humans away from CLI, **URN shipped surface** is the product:
local notification on terminal / escalate / stall warning (`streamSilenceWarning`).
CLI polling is for agents; notifications are for people.

**Why it generalizes:** Hundreds of users will not poll. Hundreds of agents will.
Splitting the channel prevents humans from adopting agent anti-patterns (45s
poll loops) and keeps agents on JSON.

**Partially shipped:** URN-S01–S03. **Open:** wire `streamSilenceWarning` to
notification candidates; on-host banner proof still outstanding per URN packet.

---

### 9. Doctor as loop gate, not encyclopedia (CLP-S09)

**Claim:** `alln doctor` (or `doctor readiness`) answers three questions only
before first unattended relay of the day:

1. Can my chosen workers run headless?
2. Is teaching installed where my host agent lives?
3. Is coordinator / reconcile path healthy?

**Why it generalizes:** Readiness output today is comprehensive but dilutes
actionability. Agents need a **pass/fail + fixCommand** triple, not 30 checks.

**Proof:** `--for relay` mode returns ≤5 checks, all green on founder Mac before
smoke relay.

---

### 10. Defer / do not fund from this packet

| Idea | Disposition |
| --- | --- |
| GUI live board as default floor | Deferred — CLI + notifications first per strategy |
| Mandatory `--idle-timeout` on every pilot | Rejected in PLS — keep optional; surface warning instead |
| Repo mtime as liveness | Rejected in IDLE-HF |
| New CLI nouns for each harness concern | Reject — fold into reconcile-on-read + golden path |
| Multi-tenant / hosted relay | Out of scope — local control loop only |

## Slices (proposed)

Ordered by dependency. No slice authorized until founder picks a start.

| Slice | Delivers | Depends on |
| --- | --- | --- |
| **CLP-S01** | Liveness contract audit + contract tests + teaching parity | PLS (partial) |
| **CLP-S02** | Reconcile-on-read for `ps`, `relay-status`, `pilot status` | Process Ownership law |
| **CLP-S03** | Default `ps` filter + `--all` history | S02 helpful |
| **CLP-S05** | Golden path teaching + agent_eval suite | — |
| **CLP-S07** | Correlation IDs on all mid-flight statuses | PLS-S02 (partial) |
| **CLP-S06** | PM bounded-verify envelope + doctor lint | S05 teaching |
| **CLP-S04** | `--intent smoke|dry-run` on relay + run | architecture-policy touch |
| **CLP-S08** | `streamSilenceWarning` → notification | URN |
| **CLP-S09** | `doctor --for relay` narrow gate | S05 |

**Suggested first PR:** CLP-S01 + CLP-S02 (truth + hygiene) — same blast radius
as PLS but product-wide, not pilot-only.

## What would falsify this packet

- Cohort data shows operators **prefer** full history in default `ps` (unlikely;
  measure if unsure).
- Reconcile-on-read causes measurable status latency or lock contention at scale
  (benchmark before shipping S02).
- Smoke intent mode is unused after 30 days dogfood — fold into docs only.

## Founder decision (optional)

None required to **read** this packet. To **start** work, pick:

1. First slice (recommend CLP-S01+S02), or
2. Explicit deferral of the whole packet until post-receipt / Buzz room test.

---

*Ephemeral packet — promote durable law to `docs/operations/` or code contracts
when slices ship; archive to `docs/archive/phases/` when closed.*
