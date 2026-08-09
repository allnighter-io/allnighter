# AI Readiness Audit

Status: **READY FOR IMPLEMENTATION** — founder intent 2026-08-09; Growth pass `AFAA2B6A`
folded and de-slopped; conformed to the shipped Lead Call / blind-fan-out laws.
Owner: `BuiltInTeams` + `TeamOutputKind` + artifact projector (code SSOT on ship).
Home: `docs/phases/` — execution packet.

**Doc lifecycle.** This is a build packet, not law. On closeout: **promote** durable
behavior into code SSOT (`BuiltInTeams`, output kind, artifact schema, seat charters)
plus any standing surface that must stay live, then **archive** to
`docs/archive/phases/`. Never park lasting truth in `docs/phases/` or
`docs/strategy/` — strategy is non-build positioning only. (First draft was misfiled
under strategy; corrected 2026-08-09.)

**Inherited law (do not re-derive):**
`docs/operations/Spec_Review.md` §Depth splits charters, §3 lens rules, §4 stop rules,
§5 independence law · `SkillCatalog.leadCallEnvelope` (universal Lead envelope) ·
`docs/design-system/readme.md` (voice + card visuals) ·
`docs/workflows/Product_Vocabulary.md`.

---

## 1. Mandate

Point Allnighter at any Project. Seats fan out read-only. You get one page that tells
you how ready your repo is for multi-agent work — and hands you the two or three
changes that make every later team run better.

```text
Any repo. One run. A page worth screenshotting — and three fixes worth doing today.
```

Two audiences, one artifact, and **both must land**:

| Reader | What they must get |
| --- | --- |
| A repo with real gaps | Named gaps with receipts, and a paste-ready fix for the top three |
| A repo already doing it well | An honest **clean bill** — plus frontier moves most strong repos have not made yet |

The second case is where audit products die. A tool that can only find fault is a tool
you run once. `Spec_Review.md` §3 already made "no material findings" a first-class,
rewarded answer; this team inherits that and goes further: a clean bill still ships a
frontier ladder (§6).

---

## 2. What makes it different

Every other audit grades code quality for humans. This grades **how your repo behaves
when agents work in it** — and it is the only audit that can put several different CLIs
in front of the same cold repo and record where they disagreed.

| Not this | This |
| --- | --- |
| Enterprise "AI readiness" survey (which models, RAG vs fine-tune) | Is *this* repo set up so AI-driven work compounds |
| A lint dump ranked by count | Max three fixes ranked by leverage, each paste-ready |
| A grade asserted by one model | A grade backed by quoted cold-read behavior across seats |
| Generic best-practice advice | Findings that cite a path, a command, or an explicit absence |

**The moat, in one line:** a vibe grade is cloneable by anyone with a prompt this
afternoon. "Four of five agents would have run the wrong test command, verbatim" is a
fact only a multi-CLI bench can produce.

---

## 3. The artifact

The audit produces a Lead Call whose craft body is the **AI Readiness Report**, plus a
**card** built for a screenshot. One truth, two densities. Output kind: `aiReadinessReport`.

### 3a. Lead Call conformance (INVIOLABLE)

The Lead emits the universal envelope from `SkillCatalog.leadCallEnvelope` — no
bespoke second envelope for this team:

- **Status: Ready | Partial.** Never "not ready." Ready = every fork decided, the owner
  can act without answering a question first. Partial = only true human forks remain
  (each with a recommendation).
- **Title** ≤12 words naming the outcome. **The call** in 1–2 plain sentences.
- **Recommendations** table (≤5 rows) — the Top unlocks live here.
- **Basis** — one line on what the team could not see. On this team Basis is
  load-bearing: it is where "I could not determine your test command" lands honestly.
- Fenced `lead-call` JSON block mirrors the visible markdown.

The grade and card are **craft body**, not a replacement envelope. Seats emit the
one-sentence `seat` summary (`SkillCatalog.seatSummaryEnvelope`) — never a mini Lead Call.

### 3b. The card

Phone-readable. Allnighter brand: midnight surface, one amber signal, mono numbers,
middle dot metadata, **no emoji** (`docs/design-system/readme.md`).

```text
┌──────────────────────────────────────────────┐
│  allnighter · agent readiness                │
│                                              │
│  acme-app                                    │
│  TS monorepo · pnpm · 4 packages              │
│                                              │
│         B−                                    │
│  Agents can work here, with friction          │
│                                              │
│  "package.json has five test scripts.        │
│   I'd have run npm test — which starts a     │
│   watcher and never exits."                  │
│  Seats that agreed on the test command  1/5  │
│                                              │
│  Top fix · one line in AGENTS.md             │
│  read-only · 8 seats · 2026-08-09            │
└──────────────────────────────────────────────┘
```

Why this composition, and not a score gauge: the **grade** stops the scroll, the
**verbatim quote** earns belief (every builder has lost twenty minutes to exactly that),
and the **agreement count** is a fact rather than an opinion — nothing to argue with.

Second-wave card: the **delta** (`B− → A−` · agreement `1/5 → 5/5`) after a fix lands.
That turns a one-shot audit into a loop worth re-running.

### 3c. The report

```text
# Agent readiness · <project>
<fingerprint> · <date> · Grade <band>

## The call
One paragraph: what working here is like for an agent today.

## Cold-read receipts
The question asked · each seat's answer · agreement N/M · one quoted miss

## Top fixes (max 3)
Per fix: what · why it bites you · paste-ready stub or diff · done-when

## Scorecard
| Bucket | Score | Verdict |  (Setup · Documentation · Tests and proof ·
                              Maintenance · Development loop · Agent context
                              · Shape, when a fingerprint fired)

## Findings
Grouped by bucket. Severity blocking | material | polish. Each cites evidence.

## What is already good
Named, specifically. Not a participation ribbon — cite the practice and the file.

## Frontier moves
The next tier of practice, for repos already past the basics.

## What we could not determine
Plain list. This is trust, not failure.

## Appendix
Per-seat finding packets.
```

### 3d. Artifact bar

1. **Precision over coverage.** One wrong finding on a repo the owner knows cold
   destroys the whole report's authority. Drop a weak finding; never pad.
2. **Every finding cites evidence** — a path, a command, or a named absence.
   `Spec_Review.md` §5 already rejects generic advice ungrounded in the repo; the same
   rule binds here, and the writer drops uncited findings rather than softening them.
3. **"Could not determine" is a valid, rewarded output.** Never guess a shape, a test
   command, or an intent.
4. **Max three fixes.** Length is the scold. A twelve-item list is homework and gets
   closed; three paste-ready diffs get applied.
5. **Every fix carries a done-when** the owner can check without us.
6. **Comparable across runs** so a re-run is a delta, not a fresh opinion.

---

## 4. Grades

Bands are behavioral, not numeric vibes. The wording is the product — a grade that
reads like a verdict on the *team* fails the voice bar.

| Band | What it means | What the report leads with |
| --- | --- | --- |
| **A** | Agents land correct work on the first try; proof can fail for the real reason | Clean bill + frontier moves |
| **B** | Agents work here with friction; the friction is named and cheap to remove | Top fixes, all small |
| **C** | Agents guess at the basics — setup or the test command is not discoverable | One structural fix first |
| **D** | Agents will confidently break things; proof cannot catch them | Proof gap before anything else |
| **F** | Nothing an agent can trust; every session starts from archaeology | Bootstrap and router first |

**Letter only.** No weighted percentage grid — a 0–100 composite invites "your weights
are wrong," an argument with no end and no value. (Rejected from the Growth round.)

---

## 5. Buckets

Universal, stack-independent. Each ships with **what good looks like**, so the report can
praise precisely and fix precisely.

| Bucket | Good looks like | Common gap |
| --- | --- | --- |
| **Setup** | One deterministic command brings the repo to runnable; secrets never in agent reach | Bootstrap lives in a teammate's head |
| **Documentation** | A thin router that points; a folder map; help on demand | A novel-length instruction file, or three docs that disagree |
| **Tests and proof** | A fast subset; a protected runner; tests that fail for the real reason | A watcher as the default test command; green-test theater |
| **Maintenance** | Cleanup is scoped to the change; ownership is legible | Drive-by refactors ride along with features |
| **Development loop** | Name the truth owner before editing; a closeout ritual | Symptom patches on the same surface, repeatedly |
| **Agent context** | Corrections become skills; recurring jobs become named automations | Every session re-explains the product |

Findings use the house severity vocabulary — **blocking · material · polish**
(`Spec_Review.md` §2) — not an invented P-scale.

---

## 6. Frontier moves (the clean-bill path)

For repos that pass the basics. This is the section that makes a good team keep the
report, and it is deliberately the hardest writing in the artifact.

| Move | Why it is the next tier |
| --- | --- |
| Make one proof able to fail for the real reason | Most strong repos still assert the system's own report of itself |
| Add a known-answer probe | A population whose answer you already know is the only honest instrument |
| Turn your last three corrections into one skill file | Corrections that stay in chat are paid for every session |
| Name the recurring job and make it a team | The third time you explain a review, it is a role, not a message |
| Split heavy from fast proof | The runner nobody waits for is the runner nobody runs |
| Write down what must never regress | An invariant nobody wrote is an invariant an agent will trade away |
| Delete the second path that does the same thing | Two rails means every future change is paid for twice |
| Tag your claims as built, decided, or proposed | Untagged prose about how the system works ages into confident fiction |

A repo at **A** should still get two of these, chosen against its actual evidence. If
the team genuinely finds nothing, it says so plainly and stops — quota-ing findings is
banned (`Spec_Review.md` §3).

---

## 7. Gold nuggets

Findings teach, not just point. Each attaches to a named, transferable pattern so the
owner learns something reusable even when they ignore our fix. Seed library (expand
from real dogfood, never invented):

| Nugget | The lesson in one line |
| --- | --- |
| **Router, not a manual** | An instruction file that explains everything gets skimmed; one that routes gets used |
| **One command to runnable** | If setup takes judgment, every agent spends its first minutes guessing |
| **The watcher trap** | A default test command that never exits reads as a hang to every agent |
| **Fast subset or nothing** | Proof that takes fourteen minutes will be skipped under deadline, by humans and agents alike |
| **Green means asked, not right** | Green means the code did what the test asked; it never means the test asked the right thing |
| **Name the truth owner** | Fix where the meaning lives, or you will fix the symptom again next week |
| **No silent fallbacks** | Required data that quietly defaults turns a loud bug into a slow lie |
| **One rail** | A second path built because the first was slow means fixing the slow one for everyone was the actual job |
| **Corrections become skills** | The same correction given three times is a missing file, not a communication problem |
| **Untagged claims are untrusted** | Prose asserting behavior without evidence is folklore with confidence |
| **Secrets are not context** | Anything an agent can read, an agent can quote |
| **Scope the cleanup** | Cleanup mixed into a feature makes both unreviewable |

---

## 8. Shape fingerprints

Detection changes **which questions seats ask**, not just a badge on the card. One
shape-true finding beats twenty generic ones. If shape is unclear, say so and ask the
universal questions only — never invent a shape.

| Fingerprint | Extra questions |
| --- | --- |
| **iOS / macOS app** | Simulator bootstrap determinism; scheme discoverability; SPM vs CocoaPods clarity; build logs so noisy an agent cannot find the error |
| **Android app** | Gradle module map; emulator bootstrap; instrumented vs unit split; flavor matrix explosion |
| **Web / frontend** | Dev server vs build; visual proof seam; CSS ownership; end-to-end tests that hang |
| **Node / TypeScript** | Which script is *the* test; package manager truth; workspace graph |
| **Monorepo** | Package-scoped proof; which package to open first; boundary docs |
| **CLI / agent-facing tool** | Machine-readable output; teach-at-failure; cold PATH; invented-flag risk |
| **Design system** | Token single source; visual gate; second-brand drift |
| **Python / data / ML** | Environment lockfile; notebook vs package; fixture size; hardware assumptions |
| **Backend / API** | Migration isolation; seed and reset; contract tests; local vs remote truth |

**v1 ships three well:** TypeScript app or monorepo, Swift Apple app, CLI tool. Add
fingerprints without multiplying teams.

---

## 9. Cold-read receipts

The wow, and the part nobody can copy without a multi-CLI bench.

**Mechanic.** Several seats are asked the same small, decidable question about the repo
— cold, blind to each other (`Spec_Review.md` §5, inviolable). The report quotes their
answers verbatim and states the agreement count.

Seed question set (small, decidable, universally relevant):

1. How do I run the tests here?
2. How do I run this project locally from a clean clone?
3. Where is the durable truth about how this product behaves?
4. If I change behavior, what proves I did not break something?

**Laws:**

- **The card indicts the repo, never the models.** No "Claude beat Codex" reading. A
  model scoreboard inherits a tribal war and loses the point. Attribution is by seat
  role in the appendix, not a vendor leaderboard on the card.
- **Blind, or it is worthless.** Agreement between seats that read each other is
  sycophancy; agreement between blind seats is signal.
- **"Could not determine" counts as a distinct answer**, never silently as a miss.
- Agreement is reported as a plain count (`1/5`), never a confidence percentage.

---

## 10. Crew

Parallel answer seats, blind, plus one Lead writer. Each seat emits the one-sentence
`seat` summary and a structured finding packet — never an essay as its only output.

| Seat | Buckets | Job |
| --- | --- | --- |
| `readiness_setup_scout` | Setup | Path from clean clone to runnable; secrets in agent reach |
| `readiness_context_cartographer` | Documentation · Agent context | Router quality, folder map, duplicate or contradictory truth |
| `readiness_measurement_auditor` | Tests and proof | Can the proof fail for the real reason? Shares the charter of the shipped `measurement_auditor` (`BuiltInTeams.swift:443`, Release Proof) |
| `readiness_test_infra_scout` | Tests and proof | Runner discipline, fast subset, flake handling, hang traps |
| `readiness_loop_scout` | Development loop · Maintenance | Truth-owner habit, closeout ritual, scope discipline |
| `readiness_automation_mapper` | Agent context | Corrections that should be skills; recurring jobs that should be teams |
| `readiness_shape_specialist` | Shape | Fingerprint questions only; stands down when shape is unclear |
| `readiness_strength_scout` | Cross | **Finds what is already good, with citations.** A dedicated seat because a panel of critics cannot produce an honest clean bill |
| `ai_readiness_writer` | Lead | Lead Call + card + report; ranks the three fixes; preserves dissent |

`readiness_strength_scout` is the structural answer to the founder requirement that a
strong repo hears so. Praise cannot be a leftover of the critic seats — they are
incentivized to find fault, and `Spec_Review.md` §5 warns that seats drift into generic
review when their mandate blurs. It gets its own charter and must cite files.

### Finding packet

```text
seatId:
bucket: setup | documentation | tests | maintenance | loop | context | shape | strength
score: 0-5 for this seat's scope
findings:
  - id: <stable-slug>
    severity: blocking | material | polish
    title: <short, plain>
    evidence: <path | command | "absent: …">
    nugget: <nugget id, §7>
    whyItBites: <one sentence, concrete consequence>
    fix: <paste-ready stub or diff>
    doneWhen: <checkable by the owner>
strengths: [{ title, evidence }]
couldNotDetermine: [<question>]
dissent: <optional>
```

**Depth.** Ship **one** team. Min/Max only if charters stay distinct, and then
`Spec_Review.md` §Depth splits charters binds: a removed seat's questions must be
absorbed by a named pass on a seat that remains — never silently dropped.

---

## 11. Voice and visual bar

From the shared design skill (`docs/design-system/readme.md`; the Ikiro design skill
states the same copy laws):

- **Sentence case everywhere. No emoji.** Metadata uses the middle dot `·`.
- **Plain and calm.** Say **you**. Lead with the outcome.
- **Numbers are concrete and mono:** `agreement 1/5`, `8 seats`, `3 fixes`.
- **Name the thing, then the consequence.** "Your default test command starts a watcher,
  so every agent run reads as a hang" — not "test configuration could be improved."
- **No roasting.** Contempt does not travel in a team channel, and a report a lead cannot
  forward to their own team is a report that dies in a DM. Blunt about the repo, never
  about the people. (Explicitly overrides the Growth round's roast framing.)
- **One amber signal** on the card; the grade and the primary action own it.

---

## 12. The loop

```text
1. Point at a Project
2. Run the audit (read-only)
3. Land on the card and three fixes
4. Apply one
5. Re-run — delta card
6. Graduate to Bug Hunt, Spec Review, Release Proof, or a Loop
```

Cold start: the first recommended Code Team when a Project has no prior grade.

---

## 13. Cut list

Removed from the Growth round with reasons, so nobody re-adds them:

| Cut | Why |
| --- | --- |
| Paste a GitHub URL | Allnighter runs in a registered local repo root. Remote clone is a new product surface, not a card feature |
| Emoji lane maps and status dots | Design system bans emoji |
| Roast / savage / "dragged" framing | Unforwardable inside a team; fails the voice bar |
| Credit-score and "love score" metaphors | Borrowed meaning; the grade already carries it |
| Weighted sub-score grids and percentages | Invites an argument about weights that has no end |
| Public grade leaderboard of famous repos at launch | One wrong grade on a repo the internet knows sinks credibility in a single post |
| README badge before grades are proven | Same risk, permanently embedded |
| Seat-count precision ("3 seats → 5") | Fake precision until the receipts engine exists. Held as a v2 flag |
| Per-seat play-by-play as the user-facing story | Seats are how the card is made, not the story |
| Overnight / unattended framing | Hero is the attended Mac bench |
| Full gap dumps beyond three fixes | Length is the scold |
| Config, signup, or seat ceremony before the first card | The first decision is where the run is lost |

---

## 14. Non-goals

- Not a security review (`code_security_review` owns that, `BuiltInTeams.swift:237`).
- Not a Spec Review of a feature packet.
- Not model-vendor comparison.
- Not a mutating run. Applying a fix is an explicit later Execute path, never a side
  effect of an audit.
- Not a score of the product's AI features. This scores the development factory.

---

## 15. Works Test

1. Run on Allnighter's own repo plus two known-shape fixtures (a TypeScript app, a Swift
   app stub).
2. At least one finding the founder recognizes as painfully true. **Zero wrong findings.**
3. Receipts panel shows real disagreement, or an honest "could not determine."
4. Run on a deliberately well-prepared fixture: the report returns a **clean bill** with
   cited strengths and at least one frontier move — and invents no fault.
5. Apply one fix stub, re-run: the delta card moves for the stated reason.
6. The card is readable, and the grade defensible, without opening the report.

Gate 4 is the one that would fail silently in a normal test pass, so it is named
explicitly: a critic panel that cannot produce an honest clean bill is not shippable.

---

## 16. Slices

| Slice | Outcome |
| --- | --- |
| **ARA-S00** | Founder rulings (§17) |
| **ARA-S01** | `TeamOutputKind.aiReadinessReport` (`TeamCatalog.swift:36`) + artifact schema: card, report, findings, receipts, strengths |
| **ARA-S02** | `code_ai_readiness` in `BuiltInTeams` + nine seat charters; finding-packet shape required by each prompt |
| **ARA-S03** | Receipts engine: shared cold-read question set, blind seat answers, agreement count |
| **ARA-S04** | Shape detector for the first three fingerprints, wired into seat briefs |
| **ARA-S05** | Card render (terminal + artifact HTML) in the design system |
| **ARA-S06** | Works Test §15, including the clean-bill fixture, then first-recommended-team wiring |

CLI shape:

```text
alln run "Audit this repo for AI readiness" --team code_ai_readiness --json
```

---

## 17. Founder forks

1. **Public name.** Keep **AI Readiness Audit**, or rename the public artifact (Growth
   lean: *Agent Readiness Report Card*; team id can stay `code_ai_readiness` either way).
2. **Share surface timing.** Card image and public link in v1, or terminal + local
   artifact first? (Recommendation: local first, share after gate 2 of §15 passes twice.)
3. **Apply path.** Second team, a Loop kind, or Execute on the report? (Recommendation:
   defer entirely until the report is trusted.)

Everything else is decided; implementation can start on ARA-S01 without an answer to
these.

---

## 18. Closeout

1. Promote durable behavior into code SSOT; add a First Routing row pointing at the code,
   not this file.
2. Archive this packet to `docs/archive/phases/`.
3. This file must never become a standing pseudo-SSOT.
