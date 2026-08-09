# AI Readiness

Status: **IN FLIGHT — ARA-S01…S04 done; ARA-S05 next.**
  Founder forks settled 2026-08-09.
  PM routes slices to DeepSeek V4 Pro (OpenCode); host audits + completes gaps.
  OpenCode dogfood: `docs/qa/opencode-mutating-commit/ARA_OPENCODE_LOG.md`.
Owner: `BuiltInTeams` + `TeamOutputKind` + artifact projector (code SSOT on ship).
Home: `docs/phases/` — execution packet.
Created: 2026-08-09 | Updated: 2026-08-09 (ARA-S04 shipped)

**Doc lifecycle.** On closeout: promote durable behavior into code SSOT, then archive to
`docs/archive/phases/`. Never a standing pseudo-SSOT here or in `docs/strategy/`.

**Inherited law (do not re-derive):** `docs/operations/Spec_Review.md` §3 lens rules,
§4 stop rules, §5 independence law, §Depth splits charters ·
`SkillCatalog.leadCallEnvelope` · `docs/design-system/readme.md` (voice) ·
`docs/workflows/Product_Vocabulary.md`.

Growth input: run `AFAA2B6A` (`code_growth`), folded and de-slopped — see §11 cut list.

---

## 1. Founder rulings (DECIDED 2026-08-09)

| Fork | Ruling |
| --- | --- |
| **Name** | **AI Readiness.** Not "audit," not a report card. Team id `code_ai_readiness`, output kind `aiReadinessReport`. |
| **Scoring** | **No score. No grade. No letter, no 0–100, no per-bucket rating.** There is no honest way to derive a number from this evidence, so the product does not pretend. Substance replaces it. |
| **Repo scope** | **Local repos only.** To read a GitHub repo, clone it and register the clone (§9). The team never fetches remote. |
| **Share surface** | The existing team artifact — `alln artifact show`/`export` already writes styled private HTML. No hosted URL, no badge, no generated image. |
| **Apply path** | **None in v1.** Read-only. Fixes ship paste-ready so the owner hands them to `Auto` or `Build a Slice` — the mutating teams that already exist. No new machinery. |

Nothing above is open. Implementation starts at ARA-S01.

---

## 2. Mandate

Point Allnighter at a Project. Seats fan out read-only. You get one page that says what
working in this repo is actually like for an agent, the two or three changes that would
help most, and what is already right.

```text
Any local repo. One run. Plain findings with receipts, and three fixes worth doing today.
```

Two readers, one artifact, both must land:

| Reader | What they get |
| --- | --- |
| A repo with real gaps | Named gaps with evidence, and a paste-ready fix for the top three |
| A repo already doing it well | An honest clean bill with cited strengths, plus frontier moves (§6) |

The second case is where audit products die. A tool that can only find fault gets run
once. `Spec_Review.md` §3 already makes "no material findings" a first-class, rewarded
answer; this team inherits it and staffs a seat for it (§8).

---

## 3. Why no score

The founder ruling above is the law; this is the reasoning, so nobody rebuilds it.

A grade would have to come from somewhere. Every available source is a lie with a number
on it: weighting seven buckets is arbitrary, so the composite argues about weights
instead of the repo; a model asked to output `B−` is generating a token, not measuring;
and a rubric tight enough to be reproducible would be a checklist that a repo passes by
having files, not by being workable. Ranking repos against each other needs a population
we do not have.

This is the house law applied to ourselves — **measure the actual thing, not the
system's report of it.** A number the code invented about its own judgment is exactly the
green-test theater the Measurement seat exists to catch (`Spec_Review.md` §4).

**What survives, because it is counted rather than judged:** the agreement count in the
cold-read receipts (§7). Five seats answered; one matched the truth. That is a tally of
real answers, not a derived score, and it is the only number the artifact shows.

**Banned by this ruling:** letter grades, 0–100, percentages, per-bucket ratings,
maturity tiers, stars, progress bars, badges, and any at-a-glance ordinal that implies a
measurement we did not make.

---

## 4. What it is not

- Not an enterprise "AI readiness" survey (which models, RAG vs fine-tune). This is about
  whether *your repo* is workable by agents.
- Not a security review — `code_security_review` owns that (`BuiltInTeams.swift:237`).
- Not a Spec Review of a feature packet.
- Not a model comparison. Findings indict the repo, never rank vendors (§7).
- Not mutating. Ever.
- Not a lint dump ranked by count.

**The one thing nobody can copy:** several different CLIs reading the same cold repo and
disagreeing. A single-model opinion about a repo is a prompt anyone writes this
afternoon. "Four of five agents would have run the wrong test command, and here is what
each one said" is a fact that requires the bench.

---

## 5. The artifact

A Lead Call whose craft body is the AI Readiness report. One artifact, no card variant.

### Lead Call conformance (INVIOLABLE)

The Lead emits the universal envelope (`SkillCatalog.leadCallEnvelope`) — no bespoke
second contract for this team:

- **Status: Ready | Partial.** Never "not ready."
- **Title** ≤12 words naming the outcome. **The call** in 1–2 plain sentences.
- **Recommendations** table, ≤5 rows — the three fixes live here.
- **Basis** — one line on what the team could not see. Load-bearing on this team: this is
  where "I could not determine your test command" lands honestly.
- Fenced `lead-call` JSON mirrors the visible markdown.

Seats emit the one-sentence `seat` summary (`SkillCatalog.seatSummaryEnvelope`), never a
mini Lead Call.

### Report body

```text
# AI Readiness · <project>
<fingerprint> · <date> · read-only · <n> seats

## The call
One paragraph: what working in this repo is like for an agent today.
Plain language. No rating.

## Cold-read receipts
The question asked · each seat's answer · agreed N/M · one quoted miss

## Three fixes
Per fix: what · why it bites you · paste-ready stub or diff · done-when

## Findings
Grouped by bucket (§6). Severity blocking | material | polish.
Every finding cites a path, a command, or a named absence.
A bucket with nothing found says so — that is information, not a gap in the report.

## Already right
Named practices with file citations. Not a participation ribbon.

## Frontier moves
The next tier, for repos past the basics.

## Could not determine
Plain list. Trust, not failure.

## Appendix
Per-seat finding packets.
```

### Artifact bar

1. **Precision over coverage.** One wrong finding on a repo the owner knows cold destroys
   the report's authority. Drop a weak finding; never pad.
2. **Evidence or it is cut.** A path, a command, or a named absence. `Spec_Review.md` §5
   already rejects advice ungrounded in the repo; the writer drops uncited findings rather
   than softening them.
3. **"Could not determine" is rewarded**, never a silent miss. Never guess a shape, a test
   command, or an intent.
4. **Three fixes, maximum.** Length is the scold. A twelve-item list gets closed; three
   paste-ready diffs get applied.
5. **Every fix carries a done-when** the owner can check without us.
6. **Re-runnable as a delta:** the same schema, so a second run shows which findings are
   gone and whether the agreement count moved.

---

## 6. Buckets

Universal and stack-independent. Each ships with what good looks like, so the report can
praise precisely and fix precisely. **Buckets group findings; they carry no rating.**

| Bucket | Good looks like | Common gap |
| --- | --- | --- |
| **Setup** | One deterministic command brings the repo to runnable; secrets never in agent reach | Bootstrap lives in a teammate's head |
| **Documentation** | A thin router that points; a folder map; help on demand | A novel-length instruction file, or three docs that disagree |
| **Tests and proof** | A fast subset; a protected runner; tests that fail for the real reason | A watcher as the default test command; green-test theater |
| **Maintenance** | Cleanup scoped to the change; ownership legible | Drive-by refactors ride along with features |
| **Development loop** | Name the truth owner before editing; a closeout ritual | Symptom patches on the same surface, repeatedly |
| **Agent context** | Corrections become skills; recurring jobs become named teams | Every session re-explains the product |

Severity uses the house vocabulary — **blocking · material · polish**
(`Spec_Review.md` §2). Severity is a judgment label, not a score, and never sums.

### Frontier moves (the clean-bill path)

For repos that pass the basics. The hardest writing in the artifact, and the reason a
strong team keeps the report.

| Move | Why it is the next tier |
| --- | --- |
| Make one proof able to fail for the real reason | Most strong repos still assert the system's own report of itself |
| Add a known-answer probe | A population whose answer you already know is the only honest instrument |
| Turn your last three corrections into one skill file | Corrections that stay in chat are paid for every session |
| Name the recurring job and make it a team | The third time you explain a review, it is a role, not a message |
| Split heavy proof from fast proof | The runner nobody waits for is the runner nobody runs |
| Write down what must never regress | An invariant nobody wrote is one an agent will trade away |
| Delete the second path that does the same thing | Two rails means every future change is paid for twice |
| Tag claims as built, decided, or proposed | Untagged prose about how the system works ages into confident fiction |

A repo with no findings still gets two of these, chosen against its actual evidence. If
the team genuinely finds nothing, it says so and stops. Quota-ing findings is banned
(`Spec_Review.md` §3).

### Gold nuggets

Findings teach. Each attaches to a named, transferable lesson, so the owner learns
something reusable even if they ignore our fix. Seed library — expand from real dogfood,
never invented:

| Nugget | The lesson in one line |
| --- | --- |
| **Router, not a manual** | An instruction file that explains everything gets skimmed; one that routes gets used |
| **One command to runnable** | If setup takes judgment, every agent spends its first minutes guessing |
| **The watcher trap** | A default test command that never exits reads as a hang to every agent |
| **Fast subset or nothing** | Proof that takes fourteen minutes gets skipped under deadline, by humans and agents alike |
| **Green means asked, not right** | Green means the code did what the test asked; it never means the test asked the right thing |
| **Name the truth owner** | Fix where the meaning lives, or fix the symptom again next week |
| **No silent fallbacks** | Required data that quietly defaults turns a loud bug into a slow lie |
| **One rail** | A second path built because the first was slow means fixing the slow one was the actual job |
| **Corrections become skills** | The same correction given three times is a missing file, not a communication problem |
| **Untagged claims are untrusted** | Prose asserting behavior without evidence is folklore with confidence |
| **Secrets are not context** | Anything an agent can read, an agent can quote |
| **Scope the cleanup** | Cleanup mixed into a feature makes both unreviewable |

---

## 7. Cold-read receipts

**Mechanic.** Several seats are asked the same small, decidable question about the repo —
cold, and blind to each other (`Spec_Review.md` §5, inviolable). The report quotes their
answers verbatim and states the agreement count.

Seed question set — small, decidable, universally relevant:

1. How do I run the tests here?
2. How do I run this project locally from a clean clone?
3. Where is the durable truth about how this product behaves?
4. If I change behavior, what proves I did not break something?

**Laws:**

- **Indict the repo, never the models.** No "Claude beat Codex" reading; a vendor
  scoreboard inherits a tribal war and loses the point. Seat roles are attributed in the
  appendix, never as a vendor ranking.
- **Blind, or worthless.** Agreement between seats that read each other is sycophancy;
  agreement between blind seats is signal.
- **"Could not determine" is a distinct answer**, never silently a miss.
- **The count is a tally, not a score.** Report `agreed 1/5`. Never convert it to a
  percentage, a confidence, or a grade — that is the §3 ban.

---

## 8. Crew

Parallel blind answer seats plus one Lead writer. Each seat emits the one-sentence `seat`
summary and a structured finding packet — never an essay as its only output.

| Seat | Buckets | Job |
| --- | --- | --- |
| `readiness_setup_scout` | Setup | Path from clean clone to runnable; secrets in agent reach |
| `readiness_context_cartographer` | Documentation · Agent context | Router quality, folder map, duplicate or contradictory truth |
| `readiness_measurement_auditor` | Tests and proof | Can the proof fail for the real reason? Same charter as the shipped `measurement_auditor` (`BuiltInTeams.swift:443`, Release Proof) |
| `readiness_test_infra_scout` | Tests and proof | Runner discipline, fast subset, flake handling, hang traps |
| `readiness_loop_scout` | Development loop · Maintenance | Truth-owner habit, closeout ritual, scope discipline |
| `readiness_automation_mapper` | Agent context | Corrections that should be skills; recurring jobs that should be teams |
| `readiness_shape_specialist` | Shape | Fingerprint questions only; stands down when shape is unclear |
| `readiness_strength_scout` | Already right | **Finds what is good, with citations.** Its own seat because a panel of critics cannot produce an honest clean bill |
| `ai_readiness_writer` | Lead | Lead Call + report; picks the three fixes; preserves dissent |

`readiness_strength_scout` is the structural answer to the clean-bill requirement. Praise
cannot be a leftover of the critic seats — they are incentivized to find fault, and
`Spec_Review.md` §5 warns that blurred mandates collapse into generic review. It gets its
own charter and must cite files.

### Finding packet

```text
seatId:
bucket: setup | documentation | tests | maintenance | loop | context | shape | strength
findings:
  - id: <stable-slug>
    severity: blocking | material | polish
    title: <short, plain>
    evidence: <path | command | "absent: …">
    nugget: <nugget id, §6>
    whyItBites: <one sentence, concrete consequence>
    fix: <paste-ready stub or diff>
    doneWhen: <checkable by the owner>
strengths: [{ title, evidence }]
couldNotDetermine: [<question>]
dissent: <optional>
```

No `score` field. No per-seat rating. (§3)

**Depth.** Ship one team. Min/Max only if charters stay distinct, and then
`Spec_Review.md` §Depth splits charters binds: a removed seat's questions must be absorbed
by a named pass on a seat that remains.

### Shape fingerprints

Detection changes **which questions seats ask**, not a badge. One shape-true finding beats
twenty generic ones. If shape is unclear, ask the universal questions only and say so —
never invent a shape.

| Fingerprint | Extra questions |
| --- | --- |
| **iOS / macOS app** | Simulator bootstrap determinism; scheme discoverability; SPM vs CocoaPods clarity; build logs too noisy to find the error in |
| **Android app** | Gradle module map; emulator bootstrap; instrumented vs unit split; flavor matrix explosion |
| **Web / frontend** | Dev server vs build; visual proof seam; CSS ownership; end-to-end tests that hang |
| **Node / TypeScript** | Which script is *the* test; package manager truth; workspace graph |
| **Monorepo** | Package-scoped proof; which package to open first; boundary docs |
| **CLI / agent-facing tool** | Machine-readable output; teach-at-failure; cold PATH; invented-flag risk |
| **Design system** | Token single source; visual gate; second-brand drift |
| **Python / data / ML** | Environment lockfile; notebook vs package; fixture size; hardware assumptions |
| **Backend / API** | Migration isolation; seed and reset; contract tests; local vs remote truth |

**v1 ships three well:** TypeScript app or monorepo, Swift Apple app, CLI tool. Add
fingerprints later without multiplying teams.

---

## 9. Running it

Local Project, read-only:

```text
alln run "Audit this repo for AI readiness" --team code_ai_readiness --json
alln artifact show latest
```

A GitHub repo you do not own — clone first, then it is an ordinary local Project:

```text
git clone <url> ~/repos/<name>
alln project add ~/repos/<name> --json
alln run "Audit this repo for AI readiness" --team code_ai_readiness --project <id> --json
```

That is a documented recipe, not a product surface. The team never fetches remote, and
there is no URL input to build, secure, or rate-limit.

**The loop:** run → read the three fixes → hand one to `Auto` or `Build a Slice` → re-run
→ the finding is gone and the agreement count moved. Cold start: the first recommended
Code Team when a Project has no prior run.

---

## 10. Voice

From `docs/design-system/readme.md`; the Ikiro design skill states the same copy laws:

- **Sentence case. No emoji.** Metadata uses the middle dot `·`.
- **Plain and calm.** Say **you**. Lead with the outcome.
- **Numbers are concrete and mono**, and there is exactly one: `agreed 1/5`.
- **Name the thing, then the consequence.** "Your default test command starts a watcher,
  so every agent run reads as a hang" — not "test configuration could be improved."
- **No roasting.** Blunt about the repo, never about the people. A report a lead cannot
  forward to their own team dies in a DM.

---

## 11. Cut list

Removed with reasons, so nobody re-adds them:

| Cut | Why |
| --- | --- |
| Letter grades, 0–100, per-bucket ratings, maturity tiers | No honest derivation exists (§3) |
| Weighted score grids | Invites an argument about weights that has no end |
| A separate share card / generated image | The team artifact already renders styled HTML |
| README badge, public grade page, famous-repo leaderboard | All require a grade, which no longer exists |
| Paste a GitHub URL | Allnighter runs in a local repo root; clone instead (§9) |
| Emoji lane maps and status dots | Design system bans emoji |
| Roast / savage / "dragged" framing | Unforwardable inside a team; fails the voice bar |
| Credit-score and "love score" metaphors | Borrowed meaning, no substance |
| Seat-count precision ("3 seats → 5") | Fake precision; needs the receipts engine underneath first |
| Per-seat play-by-play as the user-facing story | Seats are how the report is made, not the story |
| Overnight / unattended framing | Hero is the attended Mac bench |
| Gap dumps beyond three fixes | Length is the scold |
| Config, signup, or seat ceremony before the first run | The first decision is where the run is lost |
| An apply/Execute path in v1 | `Auto` and `Build a Slice` already do mutating work |

---

## 12. Works Test

1. Run on Allnighter's own repo plus two known-shape fixtures (a TypeScript app, a Swift
   app stub).
2. At least one finding the founder recognizes as painfully true. **Zero wrong findings.**
3. Receipts panel shows real disagreement, or an honest "could not determine."
4. Run on a deliberately well-prepared fixture: the report returns a clean bill with cited
   strengths and at least one frontier move, and **invents no fault**.
5. Apply one fix by hand, re-run: that finding is gone, and the agreement count moved for
   the stated reason.
6. The artifact contains **no score, grade, rating, or percentage** anywhere — a
   deterministic check on the projected artifact, not a reviewer's judgment.

Gates 4 and 6 would pass silently in a normal test pass, so they are named: a critic panel
that cannot produce an honest clean bill is not shippable, and a banned number will be
re-added by the first well-meaning writer prompt unless a check refuses it.

---

## 13. Slices

| Slice | Outcome |
| --- | --- |
| **ARA-S01** | `TeamOutputKind.aiReadinessReport` (`TeamCatalog.swift:36`) + artifact schema: call, receipts, three fixes, findings, strengths, could-not-determine. No score field anywhere |
| **ARA-S02** | `code_ai_readiness` in `BuiltInTeams` + nine seat charters; finding-packet shape required by each prompt |
| **ARA-S03** | Receipts engine: shared cold-read question set, blind seat answers, agreement tally |
| **ARA-S04** | Shape detector for the first three fingerprints, wired into seat briefs |
| **ARA-S05** | Artifact projection in the design system (existing `alln artifact` path — no new render surface) |
| **ARA-S06** | Works Test §12, including the clean-bill fixture and the no-number check, then first-recommended-team wiring |

---

## 14. Closeout

1. Promote durable behavior into code SSOT; add a First Routing row pointing at the code,
   not this file.
2. Archive this packet to `docs/archive/phases/`.
