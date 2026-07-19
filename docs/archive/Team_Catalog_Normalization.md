# Team Catalog Normalization — obvious families the router (and humans) can trust

Status: ✅ **SHIPPED &amp; ARCHIVED 2026-07-19** — every slice landed, all guards
green; the catalog in `BuiltInTeams.swift` IS this doc now. CN-S01 renames
`1247bd12` · CN-S02+S03 tiers/fold/drop `6266b8d4` · CN-S04 guards `daccc183`
· CN-S06 preferred capability `355ce3d5` (band semantics: preference reorders
across ranks INSIDE a caliber band — a rank-87 specialist beats a rank-92
generalist in High band — never across bands). IR-S00 in
`Agent_Intent_Router.md` is DONE; the router (IR-S01) is unblocked.
Kept for reference; the laws below remain binding on future catalog edits
(enforced by `BuiltInTeamsTests` guards).

Original charter: **the prerequisite for `Agent_Intent_Router.md`.** Decides
the built-in family list (Law 1: obvious names), tier shape (Law 2: optional
Min/Default/Max), **staffing (Law 3: caliber + capability, never per-team
model lists)**, and **routing keys (Law 4: typeTags unique within a lane)**.
Decisive (founder veto, not homework — agents do 90% of a vibe coder's work,
so the AI nails the names AND the staffing).
**SHIPPED so far:** CN-S05 staffing-by-caliber (2026-07-18, `fb15c38a`+
`d23c9af5`) + follow-ups (2026-07-19): `.copy` capability broadened
(`1df88685`), stale Signal Lead-rank tests fixed (`d87906b6`), intent
`typeTags` + missing `starters` added to every code/design/copy/signal team
(`18065ae7`/`eb75eeb4`/`eb056ee5` — on current pre-rename ids), and the Law 4
uniqueness fix + guard tests (`e8718e24`, after a live `--type spec-review`/
`--type growth` → **Min** mis-route was found; see Law 4).
**FOUNDER APPROVED 2026-07-19 — all gates cleared:** the full rename list, the
four-family tier shape (incl. Bug Hunt Min + Radical Directions folded into
Design Max), and the Conversion Studio drop. CN-S01–S04 execute now.
Frozen id mapping (Law 1 applied to machine ids): `code_core`→`code_plan` ·
`execution_playbook`→`build_slice` (stays lane-prefix-exempt global run team) ·
`design_core`→`design_design` · `design_premium_polish`→`design_polish` ·
`design_usability_triage`→`design_usability_review` ·
`signal_post_to_project`→`signal_outside` · `copy_landing_page`→`copy_landing`
(display "Landing Page Team"→"Copy Landing") · What to Build Next keeps id,
display normalized. New teams: `code_bug_hunt_min`, `design_design_min`,
`design_design_max`. The magic `"<lane>_core"` default fallback in
`TeamCatalog` is deleted (dead after renames; `isDefault` + the single-default
invariant own lane defaults).
Owner: AllnighterCore (`BuiltInTeams.swift` + `ModelCatalog.swift`) + `Team_And_Skill_Catalogs.md`
Updated: 2026-07-19

## Why this comes first

`Agent_Intent_Router.md` routes a user's intent to the right team using catalog
metadata. But today's catalog is STALE and pre-rename: only **Spec Review** and
**Growth** follow a consistent law with obvious names. Bug Hunt lacks a Min;
Security Review / Release Proof / GUI Bug Hunt / Code Core are single teams;
Design is five flavor-named teams; Signal ids are obscure. **A router over a
stale catalog routes badly.** So the catalog is normalized here, first — then the
router is built on top.

The bar: a cold agent OR a human scanning the picker should read a family name
and *immediately* know what it does and when to reach for it. Names are for
humans; `typeTags` are the router's match keys; `description` is the "why." All
three get curated here.

## Law 1 — names are obvious job phrases

- A family's display name **is the job, stated plainly**: "Bug Hunt", "Spec
  Review", "Security Review", "Design", "Copy". Not internal nouns ("Code Core",
  "Execution Playbook") and not flavor ("Premium Polish", "Radical Directions",
  "Conversion Studio", "Post-to-Project Signal").
- One family = one job. If two "families" answer the same intent, they merge.
- Machine `id`s are renamed to match (zero users, zero migration burden — the
  foundation-first rule; build the correct final model now).

## Law 2 — tiers (Min / Default / Max) are OPTIONAL, like effort levels

Not every model exposes reasoning effort; not every family needs depth tiers.
Forcing Min/Max onto a focused job is noise.

A family declares **Min / Default / Max** only when BOTH hold:

1. **Depth changes the answer** — a bigger team adds diverse models, blind lenses,
   a research/signal scout, or more directions that *materially change the output*
   for the SAME job (not merely "more compute").
2. **Users predictably dial it** — there is a real "quick vs thorough" or "routine
   vs nasty" split people reach for.

Otherwise the family is a **single team** (its Default only). Rules:

- **Default always exists.** It is the everyday team the router picks; shown as
  "Default" in the picker (UI-only label, per `Team_Depth_Naming.md`).
- **When tiered, ship the full Min / Default / Max** unless a specific tier
  genuinely adds nothing — and then justify the omission in this doc. Never a Min
  or Max without a Default.
- **The only depth vocabulary is Min / Default / Max.** No numbers, no flavor
  names for depth. (This refines `Team_Depth_Naming.md`: depth vocabulary stays
  universal *when present*; the presence of depth is now per-family, not forced.)

## Law 4 — typeTags are unique within a lane; the family's tag lives on Default

`typeTags` are executable routing keys, not decoration: `--type` resolves
lane-scoped **first-match over declaration order**, and the intent router
matches on the same tags. A tag duplicated within a lane therefore routes by
array position — invisible, order-dependent, and wrong the moment someone
reorders the file.

**Proven live (2026-07-19):** Min tiers are declared before Defaults in
`BuiltInTeams.all`, and the tag-closure pass had put the bare family tag on
every tier — so `--type spec-review` and `--type growth` routed to **Min**,
violating the depth law (a bare send NEVER auto-routes to Min,
`Team_Depth_Naming.md`). Fixed in `e8718e24`.

The law:

- **Within a lane, every typeTag maps to exactly one team.** Enforced by
  `testTypeTagsUniqueWithinLane` — order can never matter again.
- **The family's generic tag (`bug`, `spec-review`, `growth`…) lives ONLY on
  the Default tier.** Min/Max carry suffixed tags (`spec-review-min`,
  `growth-max`, `bug-hunt-max`) plus their own distinctive keys (`nasty`,
  `deep`). Bare family intent → Default; depth is an explicit ask.
  Enforced by `testBareFamilyTypeTagsResolveToDefaultTier`.
- **A generic cross-family word lives on the family that should win the
  generic intent**: bare `copy` → Copy Core (Copy Landing keeps
  `landing-page`, `landing`, `conversion`…); bare `signal` → Outside Signal
  (What to Build Next keeps `roadmap`, `next`, `direction`…).
- Cross-LANE tag reuse is fine (`ui` in code's GUI Bug Hunt and design's
  Design) — lane scoping disambiguates; the router resolves lane before tag.

## The normalized catalog (decisive)

Four families earn tiers (depth changes the answer AND users dial it): **Spec
Review, Bug Hunt, Growth, Design.** Everything else is a focused single team.

### Code lane

| Family | Tier | Intent it answers | typeTags (router keys) | Change from today |
| --- | --- | --- | --- | --- |
| **Plan** | single | "turn my rough idea/build into an implementable plan — scope, architecture, risks, proof" | `plan, scope, architecture, design-doc, breakdown` | Rename from **Code Core**; stays code-lane default |
| **Spec Review** | Min/Default/Max | "harden an existing spec/phase before I build — challenge premise, audit contract, make proof concrete" | `spec, review, harden, critique, premise` | ✅ LOCKED — keep |
| **Bug Hunt** | Min/Default/Max | "find the real cause of a logic/behavior bug and the smallest correct fix" | `bug, crash, defect, cause, fix, regression` | **Add Min** (has Default+Max) |
| **GUI Bug Hunt** | single | "fix visible native-UI breakage with rendered proof + layout review" | `gui, ui, visual, layout, rendered, clipping` *(no bare `bug` — Bug Hunt wins that, Law 4)* | Keep — genuinely distinct craft |
| **Security Review** | single | "check credentials, permissions, exposure, destructive ops" | `security, credentials, permissions, exposure, secrets, vuln` | Keep single (Max is the sanctioned future wing) |
| **Growth** | Min/Default/Max | "find the wedge that makes builders love + spread this — the shareable artifact + simplest lovable version" | `growth, adoption, viral, wedge, users, marketing-idea` | ✅ LOCKED — keep |
| **Release Proof** | single | "prove this slice's owner-visible claim is actually true before it closes" | `proof, release, done, verify, acceptance` | Keep single |
| **Build a Slice** | single | "disciplined build loop: slice → narrow edits → proof → audit → commit" | `build, implement, ship, slice, execute` | Rename from **Execution Playbook** |

### Design lane

| Family | Tier | Intent it answers | typeTags | Change from today |
| --- | --- | --- | --- | --- |
| **Design** | Min/Default/Max | "design/redesign this screen or flow — credible options + tradeoffs; Max widens divergence" | `design, screen, ui, mockup, interface, directions` | Rename from **Design Core**; **absorb Radical Directions into Max** |
| **Polish** | single | "make an existing surface feel expensive, intentional, native — no semantic change" | `polish, premium, native, refine, expensive, calm` | Rename from **Premium Polish** |
| **Usability Review** | single | "diagnose why a surface feels confusing, slow, risky, or hard to repeat" | `usability, ux, confusing, friction, diagnose` | Rename from **Usability Triage** |

**Dropped: Conversion Studio.** "Improve conversion / rewrite this page" is one
intent, not two competing teams. It routes to **Copy → Copy Landing** (below).
One family per intent.

### Copy lane (names approved by founder — keep)

| Family | Tier | Intent it answers | typeTags | Change from today |
| --- | --- | --- | --- | --- |
| **Copy Core** | single | "turn a copy prompt into clear, persuasive options grounded in the real offer" | `copy, writing, persuasive, messaging, tone` | Keep as-is |
| **Copy Landing** | single | "rewrite a landing page so the offer is clear, trusted, and converts" | `landing-page, landing, marketing, conversion, page, offer` *(no bare `copy` — Copy Core wins that, Law 4)* | Keep; absorbs the conversion intent |

Copy is the clearest proof of Law 2: these are focused jobs where a "bigger team"
wouldn't change the answer, so **no tiers** — and that's correct, not a gap.

### Signal lane

| Family | Tier | Intent it answers | typeTags | Change from today |
| --- | --- | --- | --- | --- |
| **Outside Signal** | single | "distill an external X post / article / release into a project-aware insight — with receipts + a skeptic pass" | `signal, external, news, article, apply, insight` | Rename from **Post-to-Project Signal** |
| **What to Build Next** | single | "scan what changed outside the repo and recommend the next build direction for this project" | `roadmap, next, direction, opportunity` *(no bare `signal` — Outside Signal wins that, Law 4)* | Rename from "What should we build next?" (already a decent intent phrase) |

### Not families — primitives & defaults (the router routes to these too)

- **Auto** (`default_chat`) — "just ask a model a question." The plain chat default.
- **`pair pilot`** — "have another model BUILD this while I supervise."
- **`pair relay`** — "keep building + reviewing overnight without me."

### Known-gap intents — decided (no new families yet)

`Agent_Intent_Router.md` names four intents with no dedicated family and defers
the earn-a-family decision here. Decision: **none earns a family today** — each
is served honestly by an existing route, and inventing families to fill a
matrix is an anti-goal. Each may earn one later with demand evidence + founder
approval (the gate Spec Review and Growth passed).

| Gap intent | Routes to | Why no family |
| --- | --- | --- |
| "write tests for this" | **Build a Slice** (tests ARE a slice with proof) | The build loop already demands proof; a test-only team would duplicate it |
| "write/fix the README / docs" | **Build a Slice** | Repo docs are a repo mutation with review — a build job. (Copy lane is *offer/marketing* writing, not repo docs — routing docs to Copy would mis-staff it) |
| "refactor at scale" | **Plan**, then **Build a Slice** / `pair pilot` | The hard part is the plan and the bounded slices, not a new craft |
| "dependency / upgrade triage" | **Plan** | An assessment job (what breaks, what order, what proof) — execution then flows to Build a Slice |

## Metadata every family ships (the router index)

For each team the router consumes: obvious **name**, an intent-phrase
**`description`** (the "why" it shows), tight **`typeTags`** (match keys above,
under Law 4), and **≥1 `starter`** (3 recommended — starters double as the
router's example-utterance corpus AND the picker's examples, so write them as
things a user actually says, not feature prose). Enforced in
`BuiltInTeamsTests`:

- every tiered family has a complete Min / Default / Max (or a justified omission);
- no family has an orphan Min/Max without a Default;
- no empty `typeTags`; ≥1 `starter`; no flavor names for depth;
- typeTags unique within a lane; bare family tag resolves to the Default tier
  (Law 4 — `testTypeTagsUniqueWithinLane`,
  `testBareFamilyTypeTagsResolveToDefaultTier`, SHIPPED `e8718e24`).

## Law 3 — staffing is by CALIBER + CAPABILITY, never per-team model lists

This is the load-bearing rule. Assigning models to roles by hand, for every team,
every time, is the annoyance — and it silently breaks when a user lacks a CLI or
a great new model ships. The staffing logic is already **shared** (`TeamResolver`
+ per-model capability metadata + capability-filtered triangulation). The teams
must USE it instead of bypassing it with hardcoded lists.

**Two layers, one source of truth:**

1. **Model suitability lives in ONE place — `ModelCatalog.builtInCapabilities`.**
   Each model declares its `laneTags`, `capabilityTags` (`code`, `planner`,
   `review`, `security`, `design`, `image`, `copy`, `localContext`, `fast`), and a
   `strengthRank`. **To make a model eligible for a kind of work, tag it here,
   once — and every team that needs that work picks it up automatically.** That is
   the whole "say it once, everything is done" property.

2. **A team row expresses NEED, not identity.** A row declares its lane, the
   **capability** it requires, whether it triangulates (distinct minds for
   diversity), and its **caliber** — nothing more. The shared resolver fills it
   from the *ready* bench, strongest-first within caliber, and **degrades
   gracefully** when CLIs are absent (drops a seat rather than double-booking or
   hard-failing; ≥1 ready model always runs). **No per-team hardcoded model
   arrays** (`designImageModels`, `designWorkerRotation`, `growthPreference`,
   `copyWorkerRotation`, `codeWorkerRotation`) — those are the anti-pattern; they
   fight the resolver and rot when the bench changes.

**Required vs preferred capability (DECIDED — resolves the narrowing
question).** A recurring temptation: make specialist seats *require* the
narrow capability (Security Review's seats require `.security`, review seats
require `.review`). REJECTED as a requirement — on a reduced bench it drops
seats or blocks the team, which breaks the works-without-some-CLIs guarantee.
Also rejected: leaving it fully permissive forever (a `.code`-only match puts
a weak-at-security model in a security seat when a specialist was sitting
ready). The mechanism is **both, split by role**: a row's `required` capability
stays broad (the graceful-degradation floor — any ready lane-capable model can
hold the seat), and a row may add a **`preferred` capability that reorders
candidates within caliber, never filters**. Bench has `.security`-tagged models
ready → they take the security seats; bench doesn't → identical staffing to
today. Preference must never beat caliber (a Mid specialist does not displace a
Flagship generalist from a Lead seat). This is CN-S06.

**Caliber vocabulary** (bands over the existing `strengthRank`, so authors and
humans can talk about a role's level — realized through the resolver, NOT a new
hand-maintained list):

| Caliber | Band | Typical seats *(illustrative snapshot, 2026-07 — NON-normative; ranks live in `ModelCatalog` only)* | Used for |
| --- | --- | --- | --- |
| **Flagship** | rank ≥ 95 | Fable, ChatGPT 5.6 Sol, ChatGPT (Codex) | Team Lead / synthesis; strategic seats. **Fable is Lead-only** — never a worker. |
| **High** | 85–94 | Opus, Cursor-Grok, Kimi K3, Grok | The everyday strong worker band. |
| **Mid** | 70–84 | Sonnet, Composer, Cursor-Auto, agy-Opus, Gemini, GLM, Qwen | Cheap capable fill; staff freely. |

(The band thresholds are the normative part. The model names are a snapshot
that WILL go stale as the bench changes — never treat this table as a staffing
list; that would be the exact hand-maintained rot Law 3 bans.)

The Lead is a named Flagship seat; worker rows triangulate across distinct
capable models (strongest reserved for the Lead), diversity front-loaded by rank.
Both are already what `TeamResolver` does — the fix is to let it, by tagging
capability in the catalog and dropping the hardcoded arrays.

**No exemptions — including the locked families.** Spec Review and Growth are
approved as families, but their staffing is NOT special-cased: they currently
carry hardcoded arrays (`growthPreference`, Spec Review's `strategicSeats`) and
those come out too, so that when a new model is added or capability metadata
changes, Spec Review and Growth benefit from the same shared components as every
other team with zero per-team edits. Expressed as caliber + capability +
triangulate, they resolve identically — just always on.

### Design capability — reasoning vs image (and K3 + Sol)

Design has two seat kinds, and conflating them is a bug:

- **`design` capability** = design *reasoning*: information architecture,
  interaction, critique, direction, usability. A text model can hold this seat.
- **`image` capability** = actually *generates* a mockup image. Only image
  engines (Gemini, ChatGPT/Codex, Grok — per the generated-image harvest) qualify.

Decision (founder note): **Kimi K3, ChatGPT 5.6 Sol, and Fable are great
designers** — they get the **`design`** capability (reasoning/critique/direction
seats), NOT `image`. Concretely in `ModelCatalog.builtInCapabilities`: K3 gains
the `.design` laneTag **and** `.design` capabilityTag; Sol (and its Codex twin)
gain the `.design` capabilityTag; **Fable** gains the `.design` capabilityTag
(it already has the `.design` laneTag). Fable is often unavailable/reserved, but
when it is ready it should be *eligible* to be staffed on design work (its
Lead-only worker reservation is unchanged — this only makes it design-eligible).
Because staffing is capability-driven, those one-line metadata edits put them on
every design team with no per-team edits. **These are just the defaults — users
can always create/edit their own teams and settings.**

## Slices

| Slice | Deliverable |
| --- | --- |
| CN-S05 | ✅ **SHIPPED 2026-07-18/19** (`fb15c38a`+`d23c9af5` + follow-ups `1df88685`/`d87906b6`/`18065ae7`/`eb75eeb4`/`eb056ee5`): staffing by caliber + capability metadata (K3/Sol/Codex/Fable design, Codex/Grok image, `.copy` broadened), hardcoded model arrays deleted, intent `typeTags` + `starters` closed on every team (current pre-rename ids), stale Signal Lead-rank tests fixed. |
| CN-S04a | ✅ **SHIPPED 2026-07-19** (`e8718e24`): Law 4 guards — typeTags unique within lane + bare family tag resolves to Default (fixed the live `--type spec-review`/`growth`→Min mis-route). |
| CN-S01 | ✅ **SHIPPED** (`1247bd12`) Rename pass — all 7 renames + `build_slice`, ids/names/descriptions/typeTags under Law 4, engine executor refs, dead `"<lane>_core"` fallback deleted, contracts regenerated. |
| CN-S02 | ✅ **SHIPPED** (`6266b8d4`) Tier completion — Bug Hunt Min; Design Min/Max with **Radical Directions folded into Design Max**; Design reasoning seats fixed to `.design` (vs `.image` mockup seats) so K3/Sol/Fable are reasoning-eligible. |
| CN-S03 | ✅ **SHIPPED** (`6266b8d4`) **Conversion Studio deleted**; its intent routes to Copy Landing. |
| CN-S04 | ✅ **SHIPPED** (`daccc183`) Guards — no orphan tiers, tiered families complete, depth display names = base + " Min"/" Max", retired-name scan, metadata floor, no hardcoded worker identity outside signal lane (execution-passthrough teams exempt by design). |
| CN-S06 | ✅ **SHIPPED** (`355ce3d5`) **Preferred capability.** `preferredCapabilityTags` reorders candidates **within a caliber band** (across exact ranks — the band, not the rank, is the caliber line), never filters, never crosses bands; Security Review rows prefer `.security`; `model_sonnet` tagged (Fable/Opus/Sol already were); stripped-copy test proves identical staffing on a zero-specialist bench. `.review` preference tagging deferred until a team needs it. |

**Then** `Agent_Intent_Router.md` IR-S01 builds `team hello --for` over the clean
catalog. (IR-S00 in that doc = "this doc lands first.")

## Anti-goals

- **No flavor or internal names** — obvious job phrase or it doesn't ship.
- **No forced tiers** — a focused single-team family is correct, not incomplete.
- **No two families for one intent** — merge instead.
- **No net-new family without founder approval** — the gate Spec Review + Growth
  passed. (But the AI proposes the answer; the founder vetoes, not authors.)
- **No number/flavor depth labels** — only Min / Default / Max.
- **No per-team hardcoded model arrays** — staff by caliber + capability; a
  model's suitability lives once in `ModelCatalog` (Law 3).
- **No duplicated typeTags within a lane, no depth tier carrying the family's
  generic tag** — first-match order must never decide a route (Law 4).
- **No narrow REQUIRED capabilities on specialist seats** — narrowing is done
  via preference (reorder), never requirement (filter); graceful degradation
  is inviolable (Law 3 / CN-S06).

## Works test

Every family in the catalog reads as an obvious job to a cold agent and a human.
Tiered families (Spec Review, Bug Hunt, Growth, Design) have a complete
Min/Default/Max; single families have exactly one team and no orphan tiers.
`typeTags` are non-empty, intent-shaped, and **unique within each lane** —
`--type <bare family tag>` resolves to the family's Default tier regardless of
declaration order (Law 4 guards green); every family has ≥1 starter; zero
flavor/internal/depth names remain. The four known-gap intents route to their
decided families (table above) with no invented teams. **Staffing:** no team defines a hardcoded
model array; every role resolves to a correct-caliber, capability-matched model
from the ready bench and degrades gracefully on a reduced bench; Kimi K3 and Sol
appear on design reasoning seats with zero per-team edits. `BuiltInTeamsTests`,
`PanelTeamResolverTests`, `TeamCatalogTests` green. The router's golden-transcript
rows (in `Agent_Intent_Router.md`) then resolve each sample intent to exactly one
family.
