# Rate Limit Continuity — parked, not dead: runs survive vendor usage windows

Status: **DRAFT (founder brainstorm captured 2026-07-19; pre–Spec Review).**
Sequencing: the park state rides the RLR blocker/activity truth spine — do not
start RLC slices before `Run_Lifecycle_Reliability.md` S03 (activity truth)
lands, or the watchdog will be taught about parked runs twice. RLC-S00 (binary
path fix) is independent and can land any time.
Owner: AllnighterCore + AllnighterEngine (driver dialects, `RunStore` blocker
facts, watchdog/reaper, `ExecutionLaneRegistry`, SBDS tier resolver) +
AllnighterCLI/Mac (park surface).
Updated: 2026-07-19.

Related: `Run_Lifecycle_Reliability.md` (blocker truth, FIFO tickets, activity
truth) · `Warm_Single_Lane_Chat.md` (per-driver dialects — the isolation
pattern the limit classifier copies) · SBDS default-model/tier system (the
substitution map Tier 2 reuses) · `Unified_Run_Model.md`.

## Founder intent

Every vendor CLI has a rolling usage window (~5h). Hitting it kills work
**hard**, and — deliberately — nothing resumes when the window resets. The
founder's real workflow today is an Apple Watch alarm clock. Live transcript
from a Claude Code session driving Allnighter's own RLR build (2026-07-19):

```text
⏺ Agent(RLR-S03 recon + execution plan) Opus 4.8 (1M context)
⏺ Agent "RLR-S03 recon + execution plan" failed: Agent terminated early due to
  an API error: You've hit your session limit · resets 4:20pm (Europe/Madrid)
You've hit your session limit · resets 4:20pm (Europe/Madrid)
/upgrade to increase your usage limit.

✻ Baked for 3h 12m 55s

❯ Please continue
```

**3h 12m of dead air**, ended only because a human alarm fired and a human
typed "Please continue." The vendor *printed the reset time* and still did
nothing with it. That gap — noticing the limit, waiting out the stated window,
sending "continue" — is pure orchestration, and it is exactly what Allnighter
is for. The caps are per-vendor; the work is not.

Why vendors won't fix it: flat-rate subscriptions price for the median user;
the hard stop + manual restart friction *is* the throttle on the tail. No
vendor will auto-resume its own CLI, and no vendor can ever resume your work
on a competitor's CLI. Only the layer above the vendors can — structural moat.
They can't stop it any more than they can stop a user setting an alarm clock.

### Vendor window landscape (observed 2026-07-19 — drifts, keep current)

| Vendor | Window shape |
| --- | --- |
| Claude | 5h rolling window + weekly cap |
| Kimi | 5h window |
| Codex | weekly only (recently **dropped** its 5h window) |
| Grok | weekly |
| Cursor | monthly (plan-based) |

Two regimes, two strategies. **Short windows (hours):** waiting is viable —
park + wake is the whole answer. **Long windows (week/month):** the reset is
days away; parking is not a completion strategy, so **substitution (Tier 2)
is the only way the job finishes** — for Grok/Cursor/Codex it is a must, not
a nice-to-have. Window *shapes* are drifting (Codex just moved), but caps
themselves are permanent — they are the economics of flat-rate subscriptions.
Everything in this design except the wake timer is window-shape-agnostic: the
limit classifier, the park blocker, the substitution trigger, and the
limit-event log are the same durable facts whenever the window resets. Resume
strategy keys off the observed `resumesAt` **distance**, never off a
hardcoded "5h" assumption.

Honest claim:

> A run that hits a vendor usage limit **parks with a truthful blocker naming
> the reset time**, is never reaped as dead, and **resumes itself** — same
> vendor by default, substitute vendor by policy. Zero limit-caused dead runs.

## Design

### Detection — the failing turn IS the notice

No polling is needed to *notice* a limit. Allnighter owns every worker's
stream; when a turn dies on a limit, the evidence lands in the settlement path
(stream-json error for Claude, ACP/app-server error for Grok/Cursor/Codex,
stderr for cold CLIs). Add a per-driver **limit-signal classifier** at the
point where a turn is already being classified as failed:

- Output: `rateLimited(vendor, resumesAt: Date?, raw: String)` instead of a
  generic failure.
- `resumesAt` is parsed when the vendor states it (Claude prints
  "resets at 4:20pm (Europe/Vienna)" — parse time **and timezone**; observed
  same-session drift Vienna→Madrid, so trust the instant, not the label).
- Isolated per driver, same pattern as the warm dialects — vendor error text
  will drift; keep each parser a small replaceable unit with fixture tests
  from real captured transcripts (the one above is fixture #1).

### Park — a first-class blocker fact on the RLR truth spine

`rateLimited` is a **blocker**, not a terminal state, durable in the run
journal like the S02 FIFO ticket facts:

- **The watchdog/reaper must treat a parked run as legitimately quiet.** A
  parked run has no activity by design; reaping it as stalled/orphaned would
  be Allnighter killing the very run it is saving. This is why RLC waits for
  RLR S03 activity truth — parked is a truth state, taught once.
- Lane policy: the parked run **holds its FIFO ticket** by default (a
  mutating order mid-flight must not lose its place or admit a competitor
  onto the same lane). Revisit only with evidence.
- Wire + GUI: `blocker{kind: rateLimited, resumesAt}` on the JSON/NDJSON
  surface; Mac shows **"Parked — resumes ~4:20pm"** (amber, calm), never a
  dead/stalled run.

### Resume — the resume attempt IS the probe

A 429/limit rejection happens **before any work is done and costs nothing
against quota**. So there is no separate readiness ping: on schedule, send the
real resume prompt; if it rejects, re-park; if it lands, work is already
flowing. One mechanism, no wasted successful probe turns.

Schedule:

1. `resumesAt` known → **one wake at resumesAt + jitter (1–5 min)**. Zero
   probes, maximally polite.
2. `resumesAt` unknown → resume attempts on a slow fixed cadence
   (~every 60 min, floor 30). Honor any `Retry-After` the vendor supplies.
3. **Park horizon:** if `resumesAt` is beyond a user-configurable horizon
   (default ~8h), silent parking is the wrong answer — a weekly/monthly cap
   means the run would sit for days. Beyond the horizon, apply the Tier 2
   substitution policy immediately (hop if allowed) or surface a loud
   decision to the human ("Grok capped until Tuesday — substitute or hold?").
   Within the horizon, park quietly and wake.

Resume prompt by worker state:

- **Warm worker still alive:** bare "continue" — the parked process is the
  checkpoint (warm-worker investment pays again).
- **Worker dead** (long park, process reaped, machine slept): resume via
  vendor session continuity (`claude --resume <sessionId>` etc.). This makes
  the open **Codex `vendorSessionId` capture gap load-bearing** — pull that
  follow-up into this phase.
- Momentum loss is bounded by commit granularity: agents commit as they go
  (no-git-management model), so "continue" resumes from the last commit.

### Tier 2 — substitution through the existing SBDS resolver

Rate-limited is just **"down until T."** SBDS Auto already routes around a
down CLI; fire the same resolver on the `rateLimited` blocker. For
long-window vendors (Grok weekly, Cursor monthly, Codex weekly) this tier is
**required for completion** — there is no "wait it out" when T is days away.
No new settings surface:

- The many-to-many **tier map = the equivalence map** (user-edits it on the
  Default-model screen today).
- The **Auto toggle = substitution ON/OFF** (OFF ⇒ always wait for the named
  vendor).
- New piece is **per-order-kind policy**: chat/plan/review work hops vendors
  freely; a mutating Execute order mid-flight defaults to *wait for its own
  vendor* (session + lane continuity), with hop-on-limit **opt-in**. In-flight
  waste on a hop is acceptable to most users (fixed subscription cost —
  "basically free AI") but must be their choice.

### Tier 3 — self-metered headroom (later, emergent)

Vendors do not expose remaining quota headless (deliberately). Allnighter
doesn't need them to: it sends every turn and streams report token usage back.
Self-metering gives a per-vendor lower-bound burn meter, and every observed
limit + reset teaches the window shape. Pacing/scheduling ("Claude is running
hot — drain light work, front-load heavy slices") falls out of Tier 1–2
telemetry. Weekly/monthly budgets make this *more* valuable, not less: a 5h
window forgives a burn mistake by dinnertime; blowing a monthly Cursor cap on
day 9 hurts for three weeks — budget pacing becomes real money management. Not in scope for the first slices; just **log every limit event
durably now** (vendor, timestamp, resumesAt, what was parked) so Tier 3 has
history on day one.

## Respectful by construction (ToS stance)

Not circumvention — the user resuming the CLI they already paid for, at the
vendor's own stated reset time, from their own authenticated login.
Indistinguishable from a disciplined human with an alarm clock. Bright lines,
enforced by design, never weakened:

- Never probe faster than the floor (30–60 min); always honor stated
  reset/`Retry-After`; jittered wakes.
- Never hammer through a limit, never rotate accounts, never spoof clients.
- Same-vendor resume is one prompt at human cadence; substitution uses a
  different subscription the user also pays for.

## Prerequisite fix (dogfooded the hard way)

RLC-S00 — **detached dispatch must resolve the `alln` binary absolutely.**
Field report 2026-07-19: detached/`--no-wait` dispatch spawns `alln` as a
cwd-relative path (`<project>/alln`), so any detached dev turn from a project
without a local symlink silently fails to start (reaped rounds #12/#13 and
S3c.2 in the RLR pilot). Workaround in the wild: gitignored `alln` symlink in
the project dir. Fix: resolve via absolute path/PATH at dispatch build time.
Independent of everything else; land first. **Every RLC resume is a detached
dispatch — resume cannot ship on a spawn path that only works by symlink.**

## Slices

| Slice | Deliverable |
| --- | --- |
| RLC-S00 | Absolute `alln` binary resolution for detached/background dispatch (field fix; independent, land first) |
| RLC-S01 | Per-driver limit-signal classifier at settlement → `rateLimited(vendor, resumesAt?)`; fixture tests from real transcripts; durable limit-event log |
| RLC-S02 | Park truth: `rateLimited` blocker fact in journal + on the wire; watchdog/reaper treats parked as quiet-by-design; lane ticket held; Mac "Parked — resumes ~T" |
| RLC-S03 | Wake scheduler + resume-attempt-as-probe: resumesAt+jitter wake, slow-cadence fallback, park-horizon policy (far reset → substitute/escalate, never silent multi-day park), warm "continue" path; re-park on repeat rejection |
| RLC-S04 | Dead-worker resume via vendor session continuity (incl. closing the Codex `vendorSessionId` capture gap) |
| RLC-S05 | Tier 2: `rateLimited` fires the SBDS resolver; per-order-kind hop policy (chat/plan hop free; mutating Execute opt-in); Auto toggle gates all substitution |

Works test (the honest-claim proof): fake CLI emits a limit error with a
stated reset 2 minutes out → run parks with truthful blocker, survives a
watchdog pass and an `alln ps` from another process, resumes itself at reset,
settles. Then the same with no stated reset (cadence fallback), and once with
substitution ON (worker hops, order completes on the substitute).

## Open questions

- Park across machine sleep/reboot: wake scheduler must be re-armed from the
  durable blocker on next Allnighter start (blocker is truth; timer is
  projection — probably falls out of RLR reconcile, verify).
- Does a parked run's held FIFO ticket starve unrelated same-lane work for
  hours? Default = hold (safety), but surface it loudly in `alln ps`/GUI.
- Multi-worker teams where only one seat parks: park the seat or the round?
- Notification: push/menu-bar "Claude parked until 4:20pm — will resume" so
  the human can choose to hop manually before the timer fires.
