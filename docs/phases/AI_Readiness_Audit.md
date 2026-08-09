# AI Readiness Audit

Status: **OPEN — build packet** (founder intent 2026-08-09; Growth pass `AFAA2B6A` folded in)
Owner: Code craft / `BuiltInTeams` + `TeamOutputKind` + artifact projector (when authorized)
Home: **`docs/phases/`** (ephemeral execution packet)

**Doc lifecycle (DECIDED by phases law):** this lives in `docs/phases/` while we build.
On closeout: **promote** keepable product law into code SSOT (`BuiltInTeams`, output
kind, artifact schema) and any standing ops/marketing surface that must stay live;
then **archive** this packet. Do **not** park lasting truth in `docs/strategy/` —
strategy is for non-build positioning, not team/build specs. (Initial draft was
misfiled under strategy; corrected 2026-08-09.)

Growth input: run `AFAA2B6A` (`code_growth`, 2026-08-09) — lead call summarized below.
Related signal: [agent OS layers](https://x.com/vibemarketer_/status/2085721177251782967?s=51) ·
contrast [enterprise “AI Readiness” surveys](https://x.com/chiefaioffice/status/1787200629699453288?s=20)
(wrong product — we grade the *factory*, not model shopping).

---

## Mandate

Point Allnighter at any Project → multi-seat **read-only** audit → a **share-worthy
AI Readiness Report** that:

1. Grades how ready the repo is for multi-agent / agent-OS development work.
2. Gives **killer recommendations** (gifts: paste-ready stubs + done-when), not homework lists.
3. Encourages **best practices** for setup, documentation, tests, code maintenance, and day-to-day AI-driven development.
4. Feels **repo-shape specific** (mobile, web, monorepo, CLI, …) via fingerprints that change which questions seats ask.

Public promise:

```text
Any repo. One run. A card people screenshot — and three unlocks that make every later Team better.
```

---

## Growth lead call (folded — run `AFAA2B6A`)

**Title:** Ground the grade in receipts: agents caught misreading your repo.

**Call:** Ship a single **grade card** whose authority comes from real evidence —
multiple CLI seats cold-read the repo and the report quotes where they diverged
or guessed wrong. The grade is the headline; **measured disagreement** is the moat
no single-model prompt can clone.

| Decision | Lean |
| --- | --- |
| Evidence engine | Grade derives from measured cold-read behavior, quoted verbatim; “couldn't determine” is a valid, trust-building output |
| Share artifact | Phone-sized card: big letter grade, fingerprint chip, **one verbatim agent quote**, agreement stat (e.g. 1/5) |
| Recommendations | **Max 3**, paste-ready diffs/stubs + done-when (re-run → agreement moves); never prose scolding |
| Fingerprints | Shape detection changes **which questions seats are asked**, not just a badge |
| Public name | **Founder fork** — Growth wants to kill “AI Readiness” in *public* copy (consultant-coded). Lean: **Agent Readiness Report Card**. Team id may stay `code_ai_readiness`. |

**Contrarian (v2):** seat-count framing (“3 productive seats → 5 with two upgrades”)
— deepest tie to daily Teams; hold until evidence engine exists (avoid fake precision).

**Hard rule:** disagreement card **indicts the repo**, never ranks models
(“Claude beat Codex”). Model scoreboards start tribal wars and lose the point.

**Cut (anti-wow):** weighted 12-page grids; full gap dumps beyond Top 3; config/signup
before first card; per-seat play-by-play as the user story; famous-repo leaderboard
at launch; overnight / unattended framing.

---

## Product shape

| Field | Proposal |
| --- | --- |
| Team id | `code_ai_readiness` |
| Display name | **AI Readiness Audit** (product/team name — founder) |
| Public artifact title | **OPEN** — founder pick vs Growth lean (*Agent Readiness Report Card*) |
| Lane | Code |
| Mutating | **No** (v1). Apply/install is a later explicit Execute path |
| Effort default | High |
| Output kind | **PROPOSED** `aiReadinessReport` |
| Depth | One team first. Min/Max only if seat charters stay distinct |

Cold-start: first recommended Code Team after `project add` / when no prior grade.

---

## The killer artifact

Two surfaces, one truth:

1. **Share card** (primary wow) — screenshot / OG / phone-readable.
2. **Full report** (depth) — scorecard, findings, gifts, appendix.

### Share card (must fit a phone)

```text
┌─────────────────────────────────────┐
│  <repo> · <fingerprint chip>        │
│                                     │
│           B−                        │
│     Agent readiness grade           │
│                                     │
│  “I'd have run `npm test` —         │
│   which starts a watcher and hangs.”│
│           Agreement 1/5             │
│                                     │
│  Top unlock: one line in AGENTS.md  │
│  allnighter · read-only             │
└─────────────────────────────────────┘
```

Second-wave share: **delta card** (B− → A− / agreement 1/5 → 5/5 after a gift stub).
That is the retention loop — audits stop being one-shot souvenirs.

### Full report sections

```text
# AI Readiness Report
Project · fingerprint · date · Grade (letter; optional 0–100)

## Executive scorecard
| Universal bucket | Score 0–5 | Verdict |
| Setup | … | … |
| Documentation | … | … |
| Tests & proof | … | … |
| Code maintenance | … | … |
| Development loop | … | … |
| Context / agent OS | … | … |
| Shape-specific | … | … |   # only if fingerprint fired
| Overall | … | … |

## Cold-read receipts (wow core)
Question asked → per-seat answers → agreement N/M → one quoted miss

## Top unlocks (max 3) — gifts
Each: title · why · paste-ready stub/diff · done-when · owner seat

## Findings by bucket
…

## Shape addendum (if any)
Mobile / monorepo / … specific findings

## Next moves
Re-run for delta · suggested Teams · optional pending enqueue

## Appendix — per-worker finding packets
```

### Artifact qualities (v1 non-negotiable)

1. **Shareable** — card first; report second.
2. **Citable** — path, command, or explicit absence / “couldn't determine.”
3. **Gifted** — Top 3 unlocks are paste-ready, not essays.
4. **Comparable** — schema supports delta re-runs.
5. **Honest** — one wrong finding destroys trust; prefer precision over coverage.

---

## Buckets

### Universal best-practice buckets

Encourage (and score) practices that make AI-driven work compound:

| Bucket | Encourages | Example gifts |
| --- | --- | --- |
| **Setup** | Deterministic bootstrap; one install/run command; secrets stay out of agent context | `scripts/bootstrap.md` stub; “agent-safe env example” |
| **Documentation** | Thin router (`AGENTS.md` / `CLAUDE.md`), folder map, discoverable help — not novel-length dumps | Router stub; “delete duplicate truth doc X” |
| **Tests & proof** | Protected runner; fast subset; proofs that can fail for the real reason; Works Test habit | `test:fast` script; quarantine note; Works Test template |
| **Code maintenance** | Deslop / audit closeout; no drive-by refactors; ownership clarity | Closeout checklist skill; maintainer queue stub |
| **Development loop** | Diff → validate → proof → commit; debugger packet before symptom patches | Debugger intake card; “truth owner before edit” |
| **Context / agent OS** | Where truth lives; skills vs folklore; named Teams/automations vs one-prompt forever | Skill stub; pending job from recurring chat job |

Each finding: `id`, `severity` (P0–P3), `bucket`, `evidence`, `suggestedFix` (gift-shaped), `ownerSeat`.

### Shape fingerprints (repo-specific)

Detection changes **questions and rubrics**, not only a cosmetic chip.
If unsure → say so; never invent a shape.

| Fingerprint | Extra questions / gifts (examples) |
| --- | --- |
| **iOS / macOS app** | Simulator/bootstrap determinism; scheme naming; SPM vs CocoaPods clarity; UI test vs unit split; Xcode log noise agents drown in |
| **Android app** | Gradle module map; emulator bootstrap; instrumented vs unit; flavor/matrix explosion |
| **Web / frontend** | Dev server vs build; Storybook/visual proof; CSS ownership; e2e hang traps |
| **Node / TS library or app** | Package manager; workspace graph; which script is “the” test; watcher scripts that hang agents |
| **Monorepo** | Package-scoped tests; boundary docs; which package an agent should open first |
| **CLI / agent-facing tool** | `--json` / menu-not-router; teach-at-failure; cold PATH; no folklore flags |
| **Design system / UI kit** | Token SSOT; screenshot/visual gates; “don't invent a second brand” |
| **Python / data / ML repo** | Env/lockfile; notebook vs package; fixture data size; GPU assumptions |
| **Backend / API** | Migration isolation; seed/reset; contract tests; local vs remote truth |

v1: detect top shapes well (start with **TS/JS app or monorepo**, **Swift Apple app**, **CLI**). Expand fingerprints without multiplying teams.

---

## Crew

Parallel answer seats + one writer. Each seat emits a **finding packet** (structured), not an essay-only answer.

### Finding packet

```text
seatId:
bucket: setup | documentation | tests | maintenance | development | context | shape | cross
scoreContribution: 0–5
findings: [{ id, severity, title, evidence, whyItMatters, suggestedFix }]
coldRead: { question, answer, confidence }   # when seat participates in receipts
dissent: optional
```

### Proposed seats (v1)

| Seat | Primary buckets | Job |
| --- | --- | --- |
| `context_cartographer` | Documentation, Context | Router, load bombs, secrets in context |
| `setup_scout` | Setup | Bootstrap, install, agent-safe env |
| `proof_engineer` | Tests & proof | Green-test theater; Works Test; claim≠measure |
| `test_infra_scout` | Tests & proof | Runner lock, fast subset, flake quarantine |
| `edit_loop_scout` | Development, Maintenance | Closeout, deslop/audit habit, hunk hygiene |
| `debugger_scout` | Development | Truth-owner / regression-law habit |
| `shape_specialist` | Shape | Fingerprint-driven questions only (skip if unknown) |
| `automation_mapper` | Context / agent OS | Skills, Teams, pending vs chat folklore |
| `ai_readiness_writer` | synth | Card + report; Top 3 gifts; receipts panel; dissent |

Optional later: `security_blast_radius` (still not a full Security Review), `cli_front_door`, `browser_proof_scout`, parallelism/seat-count scorer (Growth v2).

Harvest **laws** from dogfood (debugger, deslop, code audit, proof honesty) — not a copy of one monorepo's tree.

---

## Loop

```text
1. Point at Project
2. Run AI Readiness Audit (read-only)
3. Land on share card + Top 3 gifts
4. Apply a gift (human or later Execute)
5. Re-run → delta card (grade / agreement moves)
6. Graduate to Bug Hunt / Spec Review / Build a Slice / Loop
```

---

## Non-goals (v1)

- General security audit (use Security Review).
- Spec Review of a feature packet.
- Model-vendor comparison or “which LLM to buy.”
- Auto-rewrite without explicit Execute.
- Scoring product AI features (chatbots in the app) — this scores **development factory** readiness.
- Enterprise maturity-tier / Gartner language in the share surface.

---

## Works Test

1. Dogfood Allnighter's own repo + two known-shape fixtures (e.g. simple TS app, Swift app stub).
2. Report shows ≥1 finding the founder recognizes as painfully true; **zero** wrong findings.
3. Cold-read receipts panel shows real disagreement or honest “couldn't determine.”
4. Apply one gift stub → re-run moves grade and/or agreement stat (delta card).
5. Share card is screenshot-readable without reading the full report.

---

## Build slices (when authorized)

| Slice | Outcome |
| --- | --- |
| ARA-S00 | Founder rulings: public artifact name; letter vs letter+score |
| ARA-S01 | `TeamOutputKind.aiReadinessReport` + artifact schema (card + report + findings + receipts) |
| ARA-S02 | `code_ai_readiness` in `BuiltInTeams` + seat skill charters (packet shape required) |
| ARA-S03 | Shape detector (top 3 fingerprints) wired into seat briefs |
| ARA-S04 | Share card render (terminal + artifact HTML/OG) |
| ARA-S05 | Dogfood Works Test + first recommended Team wiring |

CLI sketch: `alln run "Audit this repo for AI readiness" --team code_ai_readiness --json`

---

## Open decisions

1. Public name on the card (keep “AI Readiness” vs Growth lean *Agent Readiness Report Card*).
2. Grade scale (letter only vs letter + 0–100).
3. Apply/install path (second Team vs Loop vs Execute on report).
4. Public share URL / README badge timing (Growth wants it; launch risk if grades are wrong).

---

## Closeout rule

When the Team ships and Works Test passes:

1. Promote durable behavior into **code** (and short standing help/marketing only if needed).
2. **Archive** this phase doc (`docs/archive/phases/`).
3. Remove the First Routing pointer from “open packet” to code SSOT + archive note.

This file must not become a permanent pseudo-SSOT in `phases/` or `strategy/`.
