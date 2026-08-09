# AI Readiness Audit

Status: **PROPOSED** (founder intent 2026-08-09 — not built)
Owner: Code craft / built-in Teams (`BuiltInTeams` when authorized)
Home: strategy brief until a build packet is opened
Related: [VibeMarketer / Greg Isenberg — agent OS layers](https://x.com/vibemarketer_/status/2085721177251782967?s=51) · [Scale AI “AI Readiness” survey framing](https://x.com/chiefaioffice/status/1787200629699453288?s=20)

---

## One-sentence claim

Point Allnighter at any repo → get a **killer AI Readiness Report** that grades how ready the codebase is for multi-agent development work, with clear buckets and findings per worker, plus a ranked unlock list.

## Why this exists

Most Teams assume the repo is already agent-operable. Most repos are not.

**PROPOSED** first recommended run after `project add` / bootstrap:

```text
Send to team → AI Readiness Audit
```

Same hero shape as Design / Spec Review: cold start works on *any* Project; taste lives in specialized seats; the artifact is what people keep and share.

### Not that other “AI Readiness”

Enterprise surveys (e.g. Scale’s report) ask which models orgs use, RAG vs fine-tune, open vs closed. Useful market context — **wrong product**.

This audit asks: **is this repository set up so AI-driven software work compounds?** Context storage, how work is checked, which corrections become skills, which jobs become automations — the OS layers, not the model catalog.

---

## Product shape

| Field | Proposal |
| --- | --- |
| Team id | `code_ai_readiness` |
| Display name | **AI Readiness Audit** |
| Lane | Code |
| Mutating | **No** (v1). Apply / install is a later explicit Execute path |
| Effort default | High |
| Output kind | **PROPOSED** `aiReadinessReport` (new `TeamOutputKind`) |
| Depth | Ship **one** team first (not Min/Max). Add Lite/Max only if seat charters stay distinct |

Public promise:

```text
Any repo. One run. A report that tells you what to fix so every later team works better.
```

---

## The killer artifact: AI Readiness Report

The report is the product. Worker chat is scaffolding.

### Must-have sections (human + machine)

```text
# AI Readiness Report
Project: <name> · Root: <path> · Date: <iso> · Grade: A–F (or 0–100)

## Executive scorecard
| Bucket | Score 0–5 | One-line verdict |
| Context | … | … |
| Checks | … | … |
| Skills | … | … |
| Automations | … | … |
| Overall | … | … |

## Top unlocks (max 5)
1. [P0] <title> — why it unlocks leverage — owner seat — evidence
2. …

## Findings by bucket
### Context
- [severity] id · finding · evidence (path or “absent”) · suggested fix
### Checks
…
### Skills
…
### Automations
…

## Per-worker packets (appendix)
<each seat’s structured findings — see below>

## Next moves
- Re-run after fixes (delta audit)
- Suggested next Teams (Bug Hunt / Release Proof / …)
- Optional: enqueue Top unlocks as pending items
```

### Scorecard spine (four buckets)

Aligned to the agent-OS thesis — not a lint dump:

| Bucket | Question |
| --- | --- |
| **Context** | Where does durable truth live? Can a cold agent load the right docs without eating secrets or the whole monorepo? |
| **Checks** | How is work proven? Can a test fail for the *real* reason? Is there an owner-visible Works Test habit? |
| **Skills** | Do repeated corrections become reusable skills/recipes, or only chat folklore? |
| **Automations** | Are proven jobs named Teams / loops / pending jobs, or one-prompt forever? |

Each finding carries: `id`, `severity` (P0–P3), `bucket`, `evidence`, `suggestedFix`, `ownerSeat`.

Synthesis may dissent; the report **preserves minority findings** when evidence conflicts (same posture as risk registers).

### Artifact qualities (non-negotiable for v1)

1. **Shareable** — reads like a board memo, not a log dump.
2. **Citable** — every finding points at a path, command, or explicit absence.
3. **Ranked** — Top unlocks by leverage, not completeness theater.
4. **Comparable** — same schema so a second run can be a **delta** (“what changed since last grade?”).
5. **Actionable** — each Top unlock names a next verb (doc stub, gate, skill draft, team to run).

Machine envelope (when built): project via existing `alln artifact` path; JSON mirror of the scorecard + findings arrays.

---

## Crew: clear buckets, findings per worker

Parallel answer seats; one synthesis writer. Each seat owns **one bucket slice** and emits a **finding packet** — never a free-form essay as the only output.

### Finding packet (per worker)

```text
seatId:
bucket: context | checks | skills | automations | cross
scoreContribution: 0–5   # local grade for this seat’s scope
findings:
  - id: <stable-slug>
    severity: P0|P1|P2|P3
    title: <short>
    evidence: <path:line | command | "absent: …">
    whyItMatters: <one sentence>
    suggestedFix: <smallest unlock>
dissent: <optional note if disagreeing with another seat>
```

### Proposed seats (v1 — ~7 answer + writer)

| Seat id | Bucket | Looks for | Example findings |
| --- | --- | --- | --- |
| `context_cartographer` | Context | `AGENTS.md` / `CLAUDE.md` router, folder map, secret leakage into agent context, monorepo load bombs | Missing router; AGENTS dumps the world; `.env` referenced in agent prompts |
| `truth_ssot_auditor` | Context | Duplicate product truth in UI / prompts / comments; claim hygiene | Two docs disagree; UI invents status |
| `proof_engineer` | Checks | Green-test theater; proofs that cannot fail; claim≠measurement | Suite asserts own headers; no Works Test |
| `test_infra_scout` | Checks | Runner discipline, lock/flake quarantine, heavy/light split | Concurrent suites; no protected runner |
| `edit_loop_scout` | Skills | Diff → deslop → audit → commit habit; hunk hygiene | No closeout recipe; drive-by refactors |
| `debugger_scout` | Skills | Symptom patches; missing truth-owner / regression-law habit | Bugs fixed without naming lie-prone layer |
| `automation_mapper` | Automations | Recurring jobs with no Team; one-prompt culture; no pending/queue | “We always re-explain review in chat” |
| `ai_readiness_writer` | (synth) | Merges packets → **AI Readiness Report** | Grade + Top unlocks + dissent notes |

Optional later seats (Max only if charters stay distinct): `security_blast_radius`, `cli_front_door`, `skill_miner`, `browser_proof_scout`.

Harvest posture: encode **laws** from dogfood (Ikiro/Allnighter ops — debugger, deslop, code audit, proof honesty), not a copy-paste of one monorepo’s file tree. Stack fingerprints (Node / Swift / …) adapt evidence targets; buckets stay fixed.

---

## Loop

```text
1. Point at Project (any repo)
2. Run AI Readiness Audit (read-only)
3. Read the Report — especially Top unlocks
4. Human (or Execute path later) applies smallest unlocks
5. Re-run → delta grade
6. Graduate to Bug Hunt / Spec Review / Build a Slice / Loop
```

**PROPOSED** recommendation: surface this Team as the cold-start default suggestion when a Project has never run a Code Team (or when grade is missing / stale).

---

## Explicit non-goals (v1)

- Not a general security audit (use Security Review).
- Not a Spec Review of a feature packet.
- Not model-vendor comparison or “which LLM should we buy.”
- Not auto-rewriting the repo without an explicit Execute / apply path.
- Not scoring “AI feature presence” (chatbots in the product). This scores **AI-driven development factory** readiness.

---

## Works Test (when built)

1. Add a messy public or fixture repo as a Project.
2. Run `code_ai_readiness`.
3. Report cites real absences with evidence (not vibes).
4. Apply the top unlock manually (or via approved apply path).
5. Re-run: grade moves; delta section names what changed.
6. Cold agent completes a trivial task that failed before the unlock — measured outcome, not self-report.

---

## Build notes (when authorized)

- Add `TeamOutputKind.aiReadinessReport` + synthesis profile + artifact schema.
- Register `code_ai_readiness` in `BuiltInTeams` with seat → skill charters that **require** the finding packet shape.
- CLI: `alln run "Audit this repo for AI readiness" --team code_ai_readiness --json`
- Do not open Min/Max until one team’s report quality is dogfood-green.

## Open decisions

1. Exact grade scale (letter vs 0–100 vs both).
2. Whether apply/install is a second Team, a Loop kind, or Execute on the same report.
3. Whether the report is the first public share card (growth) or stay private-by-default.

---

## Founder packet

```text
Founder intent: Default Allnighter Team — AI Readiness Audit — any repo → killer report.
Product value: First loop that makes every later Team better; works immediately on cold Projects.
Trusted workflow slice: read-only multi-seat audit → aiReadinessReport artifact → ranked unlocks.
Current state: PROPOSED strategy only; no team id / outputKind in code yet.
Truth owner (when built): BuiltInTeams + TeamOutputKind + artifact projector.
Proof scenario: fixture/messy repo → citable report → fix → delta grade up.
Blocking questions: grade scale; apply path; share-card default.
Next slice: open a phases/ build packet only when founder authorizes implementation.
```
