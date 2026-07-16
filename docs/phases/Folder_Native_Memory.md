# Folder-Native Memory — the repo remembers, no matter which CLI touched it

Status: **smallest slice SHIPPED** (seed `061b1a1b` + pointer `40235f8f`).
Consolidation mechanism stays future work.
Owner: AllnighterCore + conventions (repo owns the memory content)
Sibling design: Ikiro Phase 88 (`websitemd.studio/Docs/phases/88_Folder_Native_Memory.md`,
LOCKED v2) — deliberately share its design language: one read seam, consolidation as
compression, "memory must be felt, not filed," export-anytime honesty.
Created: 2026-07-16 · Updated: 2026-07-16

## The bet (same physics as Ikiro 88, one twist stronger)

Every CLI vendor is building memory at the ACCOUNT level, siloed per vendor —
Claude's memory doesn't know what Codex learned about this repo; Cursor's rules
don't know what the Grok seat discovered overnight. Allnighter is the only thing
that sits above all seats at the FOLDER level: it watches every vendor's worker
succeed, fail, get gated, get flagged, get corrected — in one place.

> "Your repo remembers, no matter which CLI touched it" — a sentence no lab can
> say, structurally (they won't consolidate a competitor's lessons).

Evidence from the first week of piloted deliveries (#1–#5): the loop worked better
*because the piloting PM had cross-session memory* (verdict-tail traps, cursor
allowlist behavior, known test baselines, seat speeds). A spawned overnight PM has
none of that — every relay is a cold read. The signals already exist and are
durable (round logs, verdicts, dev reports, repoDeltas, gate blocks, escalations,
founder resume answers — the highest-signal events, the analog of Ikiro's
reverts/rejections). They are stored as run-truth and never distilled: they
evaporate, exactly like Ikiro's pre-88 analytics.

It also compounds the commercial answer to "why pay when an agent can copy the
invocation recipe": a DIY loop can copy the recipe; it cannot copy six months of
the repo's accumulated posterior — and the *process* that maintains it runs only
while Allnighter runs.

## The 10x (named, so we don't chase the wrong one)

The 10x is NOT better retrieval — no vector DB, no RAG, no memory subsystem. The
10x is **what is remembered and how it is felt**:

> After a week of Allnighter, the repo behaves like it has a permanent staff
> engineer who watched every CLI, remembered every failure, and briefs the next
> shift. Every other surface makes agents re-earn the same scars.

Product sentence: **"Stop paying the cold-start tax."** The conversion event is
**night 2**: the first overnight run that opens by citing what night 1 learned.
Everything below serves those two sentences; anything that doesn't is bloat.

## Design skeleton (v0 — harden as we learn)

- **One read seam:** the repo's own `MEMORY.md` (open format, portable,
  git-versioned) + the freshest not-yet-consolidated relay events. The PM prompt
  and dev preamble carry ONE pointer line: "read `MEMORY.md` if present." This is
  NOT a context packet (which the Unified Run Model killed) — the agent reads a
  real file in the repo, which is the law that replaced packets.
- **Write authority (the ONE statement — everything else defers here):**
  Allnighter the PRODUCT never writes the repo. Sessions and workers do:
  a cockpit pilot session (the user's agent with repo hands) may write MEMORY.md
  directly; unattended contexts write via a dispatched worker (the seed pattern);
  a scheduled consolidation round is that worker on a clock. Concurrent-writer
  sequencing is an open question (below).
- **No second memory system.** Allnighter's stores stay episodic run-truth; the
  folder file is the distilled posterior. No vector DB, no embeddings, no new
  store. (Ikiro v2's exact simplification.)
- **Boundary:** `MEMORY.md` (machine-maintained, learned posterior) stays distinct
  from `AGENTS.md` (human-authored constitution) — Ikiro's playbook-prior vs
  site-posterior split. Vendor convention files (CLAUDE.md, `.cursor/rules`) may
  POINT at it; the bootstrap snippet can teach that pointer.
- **Memory is a control surface, not a diary.** Five line types, as plain
  markdown prefixes — agents filter, humans audit, consolidation compresses by
  type, zero machinery:
  - `trap` — avoid / always check ("Cursor allowlist blocks shell unless
    project `.cursor/cli.json`; verify: run `git status` at turn start")
  - `proof` — the command of truth ("`swift test --package-path …` is the wall;
    xcodebuild only for Mac app targets")
  - `seat` — routing economics, WITH evidence ("model_X stalled 3/4 long turns
    week of 7/14" — never gossip without a receipt)
  - `decision` — founder lock, once, until revoked ("no API keys, ever")
  - `suspect` — contradicted, pending rewrite or death
  Line shape: **claim → when it last burned us → how to verify.** Dense and
  falsifiable, or it doesn't go in.
- **Curation order (ruthless):** 1 pain events (gate blocks, failed rounds,
  escalations, founder rejections) → 2 proof truth (real commands, fake-green
  traps) → 3 seat economics → 4 founder decisions. Soft style preferences last
  or never. If 1–4 are solid, agents pull the file into context voluntarily.
- **Invalidation is half the feature.** Stale memory is worse than none — it
  causes *confident* failure. Every line can die: a seat that observes reality
  contradicting a memory line reports the contradiction (not a silent workaround);
  the next consolidation rewrites or removes it via `suspect`. Trust in the file
  is the product; protect it like a ledger.
- **Hard caps.** MEMORY.md must never become AGENTS.md #2 — a long, polite,
  ignored README. Cap the file (target ≤ ~60 lines); consolidation compresses or
  evicts, never just appends — except `decision` lines, which are exempt from
  cap-driven eviction and die only by explicit founder revocation.
- **Secrets refusal.** Memory never holds tokens, key paths, credentials, or
  private URLs — a consolidation-order constraint, stated in the order every time.
- **Felt, not filed:** (a) seats that honor a line CITE it in their report
  ("honored MEMORY: cursor allowlist trap") — convention first, measured later
  as an honor rate (a trust-based self-report — known limitation; it must never
  feed automated decisions without a spot-check); (b) the consolidation round's report is a short **Learning
  card** — what entered, what was demoted, what remains unknown — a
  human-readable delta, never a silent rewrite. The card is for the founder;
  the file is for the agents.

## The team-improvement loop (decided 2026-07-16 — it is the `seat` line, nothing else)

Teams (TeamPresets) improve through memory, with ZERO new machinery: every panel/
pilot **done-note records seat-behavior observations WITH receipts** ("model_X
stalled 3/4 long turns, panel r2 7/16") → consolidation distills them into `seat`
lines → every session reads the posterior before composing rosters or picking
seats → a human or their session edits the team (existing `alln teams`
edit-in-place) when evidence accumulates. Rare, deliberate, judgment-owned.
Scope note: teams are global, MEMORY.md is per-repo — a seat blocked by a repo
fact (allowlist) means fix the repo, not the team; per-repo duplication of global
observations is cheap and honest until cross-repo priors are ever unparked.
Pilot cockpit sessions may write MEMORY.md directly (they are the user's agent
with repo hands — the no-write law binds Allnighter the product, not the user's
session); relay/overnight contexts write via an ordered worker (the seed pattern).

## Remaining work (pointer + seed SHIPPED: 061b1a1b + 40235f8f)

1. ~~Pointer line in relay prompts + pilot scaffold~~ DONE.
2. Convention (live): done-round orders fold lessons / record seat observations.
3. NEXT: the scheduled consolidation round (dispatched worker; Allnighter
   schedules, never writes) — this is what unlocks the night-2 works test.
4. Adoption polish (panel finding, accepted): a zero-line scaffold HEADER for new
   repos (schema + curation rules only, zero unearned lines — compatible with the
   no-starter-templates anti-goal) + the bootstrap snippet gains the MEMORY.md
   pointer clause so cockpit sessions learn it too.

## Anti-goals (rejected from feedback review, 2026-07-16 — do not revive without cause)

- No vector DB / embeddings / RAG / memory subsystem (unchanged).
- No "Repo IQ" score for now — gamification sludge risk exceeds the value; the
  Learning card + honor rate cover the visible-compounding need honestly.
- No starter MEMORY templates — shipping unearned wisdom is fake-green for
  memory; the file starts empty and earns every line.
- No cross-repo auto-sharing, ever by default (priors are gold AND liability).
- No auto-tuning of TeamPresets from seat lines/stats — judgment theft + roster
  churn; teams change only when a person or their session decides. Seat stats,
  if ever wanted, are an on-demand projection over existing round logs, never a
  system feeding memory automatically.
- No pricing/tier design in this doc — strategy docs own that.

## Works test (night-2, the conversion event — REQUIRES the consolidation round, unshipped)

Until consolidation ships, the honest variant is pilot-driven: the cockpit
session folds lessons at done and the next session cites them (proven live
2026-07-16, piloted delivery #9 round 1). The full unattended version: same doc, two overnight relays on consecutive nights. Night 1 runs cold and its
closing consolidation writes MEMORY.md (Learning card emitted). Night 2's PM
opens by citing at least one memory line, avoids at least one night-1 trap
without re-discovering it, and the founder's morning digest shows the delta.
PASS = a reviewer comparing the two round logs can point at the cold-start tax
that was not paid twice. (Cold-vs-warm side-by-side is also the demo asset.)

## Open questions (harden here as dogfood teaches)

- Consolidation cadence: per-relay closing round vs periodic sweep vs on-adopt?
- Concurrent writers: cockpit direct-writes vs a consolidation worker could race
  on MEMORY.md — sequencing convention needed before consolidation ships (panel
  finding, accepted 2026-07-16).
- Shared/public repos: default is commit-to-repo; an opt-out/redaction posture
  for founders who can't commit a seat/trap posterior publicly (panel finding,
  accepted — adoption note, not machinery).
- Cross-repo priors (an Allnighter-level playbook across a founder's projects) —
  the Ikiro two-level system; likely NEVER auto-shared, but worth naming.
- How does a pilot PM (external, already has its own memory) interplay with the
  file — read-only? contributor via its own commits?

## Learning log (append as we learn — this section is the point of parking)

- 2026-07-16: doc created from the founder brainstorm + Ikiro 88 read. First week
  of piloted deliveries recorded as the motivating evidence above.
- 2026-07-16 (round 2, pointer line): relay prompts + pilot scaffold carry the one
  MEMORY.md pointer; prompt-assembly tests assert presence and cite wording. Pointer
  commit: `40235f8f`.
  Candidate future memory line: dev-seat stall-retry can double-commit the same
  message if a turn re-runs after work is already committed (`e545a289` +
  `061b1a1b`, 11 min apart — harmless here). Provenance trailer's first live
  appearance was the memory seed commit (`061b1a1b`).
- 2026-07-16 (hardening pass, external feedback triaged): incorporated — typed
  memory lines (control surface not diary), claim→burned→verify line shape,
  ruthless curation order, invalidation-as-half-the-feature, hard caps, secrets
  refusal, cite-or-it-didn't-happen + Learning card, night-2 works test, "stop
  paying the cold-start tax" positioning. Rejected — Repo IQ score, starter
  templates, pricing tiers (recorded as anti-goals). Sharpest reframe kept: the
  product is not "memory," it is the **repo posterior maintained as a process**
  — account memory is personality notes; folder memory is how this system
  actually behaves under load.
