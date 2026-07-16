# Folder-Native Memory — the repo remembers, no matter which CLI touched it

Status: **UNPARKED — smallest slice executing (founder call 2026-07-16).** The
original "wait for overnight dogfood" sequencing was defeated by its own logic:
the signals already exist (six piloted deliveries of pilot-PM lessons held in a
mortal session). Smallest slice: seed this repo's MEMORY.md from those lessons
(a piloted round — the worker writes and commits, per the law) + the one pointer
line in relay prompts/scaffold. Consolidation mechanism stays future work.
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
- **Allnighter never writes it.** Allnighter does no git and never mutates the
  repo. Consolidation is a *dispatched worker's job* — a cheap closing round
  ("distill what this relay taught about this repo into MEMORY.md; commit it")
  that Allnighter merely schedules. Scheduling unattended work is pillar one.
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
  evicts, never just appends.
- **Secrets refusal.** Memory never holds tokens, key paths, credentials, or
  private URLs — a consolidation-order constraint, stated in the order every time.
- **Felt, not filed:** (a) seats that honor a line CITE it in their report
  ("honored MEMORY: cursor allowlist trap") — convention first, measured later
  as an honor rate; (b) the consolidation round's report is a short **Learning
  card** — what entered, what was demoted, what remains unknown — a
  human-readable delta, never a silent rewrite. The card is for the founder;
  the file is for the agents.

## Smallest first slice (when unparked)

1. Relay prompts + pilot scaffold gain the one pointer line (rides on Pilot DX
   surfaces, nearly free).
2. Convention before mechanism (the provenance-trailer playbook): the done-round
   order includes "fold lessons into MEMORY.md before declaring done."
3. Only after the convention proves out: a scheduled consolidation round
   (dispatched worker; Allnighter schedules, never writes).

## Anti-goals (rejected from feedback review, 2026-07-16 — do not revive without cause)

- No vector DB / embeddings / RAG / memory subsystem (unchanged).
- No "Repo IQ" score for now — gamification sludge risk exceeds the value; the
  Learning card + honor rate cover the visible-compounding need honestly.
- No starter MEMORY templates — shipping unearned wisdom is fake-green for
  memory; the file starts empty and earns every line.
- No cross-repo auto-sharing, ever by default (priors are gold AND liability).
- No pricing/tier design in this doc — strategy docs own that.

## Works test (night-2, the conversion event)

Same doc, two overnight relays on consecutive nights. Night 1 runs cold and its
closing consolidation writes MEMORY.md (Learning card emitted). Night 2's PM
opens by citing at least one memory line, avoids at least one night-1 trap
without re-discovering it, and the founder's morning digest shows the delta.
PASS = a reviewer comparing the two round logs can point at the cold-start tax
that was not paid twice. (Cold-vs-warm side-by-side is also the demo asset.)

## Open questions (harden here as dogfood teaches)

- Consolidation cadence: per-relay closing round vs periodic sweep vs on-adopt?
- What gets remembered first: repo facts (proof commands, entrypoints, gotchas) vs
  seat behavior (which worker is fast/honest here) vs founder preferences? (Ikiro
  says: highest-signal events first — escalations, gate blocks, failed rounds.)
- Cross-repo priors (an Allnighter-level playbook across a founder's projects) —
  the Ikiro two-level system; likely NEVER auto-shared, but worth naming.
- How does a pilot PM (external, already has its own memory) interplay with the
  file — read-only? contributor via its own commits?

## Learning log (append as we learn — this section is the point of parking)

- 2026-07-16: doc created from the founder brainstorm + Ikiro 88 read. First week
  of piloted deliveries recorded as the motivating evidence above.
- 2026-07-16 (hardening pass, external feedback triaged): incorporated — typed
  memory lines (control surface not diary), claim→burned→verify line shape,
  ruthless curation order, invalidation-as-half-the-feature, hard caps, secrets
  refusal, cite-or-it-didn't-happen + Learning card, night-2 works test, "stop
  paying the cold-start tax" positioning. Rejected — Repo IQ score, starter
  templates, pricing tiers (recorded as anti-goals). Sharpest reframe kept: the
  product is not "memory," it is the **repo posterior maintained as a process**
  — account memory is personality notes; folder memory is how this system
  actually behaves under load.
