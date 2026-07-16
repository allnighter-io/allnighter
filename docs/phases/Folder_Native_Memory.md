# Folder-Native Memory — the repo remembers, no matter which CLI touched it

Status: **PARKED — spec-hardening only, no execution.** Sequenced AFTER Pilot DX and
the first overnight relay dogfood (the dogfood generates the signals this design
feeds on; design from observed lack, not imagination).
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
- **Felt, not filed:** when a seat honors a memory line, reports should cite it
  (the Ikiro ack pattern); a memory nobody feels is a diary.

## Smallest first slice (when unparked)

1. Relay prompts + pilot scaffold gain the one pointer line (rides on Pilot DX
   surfaces, nearly free).
2. Convention before mechanism (the provenance-trailer playbook): the done-round
   order includes "fold lessons into MEMORY.md before declaring done."
3. Only after the convention proves out: a scheduled consolidation round
   (dispatched worker; Allnighter schedules, never writes).

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
