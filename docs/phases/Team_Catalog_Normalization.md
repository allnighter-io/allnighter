# Team Catalog Normalization — obvious families the router (and humans) can trust

Status: Specced v1 — **the prerequisite for `Agent_Intent_Router.md`.** Decides
the built-in family list (Law 1: obvious names), tier shape (Law 2: optional
Min/Default/Max), and **staffing (Law 3: caliber + capability, never per-team
model lists)**. Decisive (founder veto, not homework — agents do 90% of a vibe
coder's work, so the AI nails the names AND the staffing). CN-S05 (staffing +
K3/Sol design) is in build; the rest awaits founder go.
Owner: AllnighterCore (`BuiltInTeams.swift` + `ModelCatalog.swift`) + `Team_And_Skill_Catalogs.md`
Updated: 2026-07-18

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

## The normalized catalog (decisive)

Four families earn tiers (depth changes the answer AND users dial it): **Spec
Review, Bug Hunt, Growth, Design.** Everything else is a focused single team.

### Code lane

| Family | Tier | Intent it answers | typeTags (router keys) | Change from today |
| --- | --- | --- | --- | --- |
| **Plan** | single | "turn my rough idea/build into an implementable plan — scope, architecture, risks, proof" | `plan, scope, architecture, design-doc, breakdown` | Rename from **Code Core**; stays code-lane default |
| **Spec Review** | Min/Default/Max | "harden an existing spec/phase before I build — challenge premise, audit contract, make proof concrete" | `spec, review, harden, critique, premise` | ✅ LOCKED — keep |
| **Bug Hunt** | Min/Default/Max | "find the real cause of a logic/behavior bug and the smallest correct fix" | `bug, crash, defect, cause, fix, regression` | **Add Min** (has Default+Max) |
| **GUI Bug Hunt** | single | "fix visible native-UI breakage with rendered proof + layout review" | `bug, gui, ui, visual, layout, rendered, clipping` | Keep — genuinely distinct craft |
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
| **Copy Landing** | single | "rewrite a landing page so the offer is clear, trusted, and converts" | `copy, landing, marketing, conversion, page, offer` | Keep; absorbs the conversion intent |

Copy is the clearest proof of Law 2: these are focused jobs where a "bigger team"
wouldn't change the answer, so **no tiers** — and that's correct, not a gap.

### Signal lane

| Family | Tier | Intent it answers | typeTags | Change from today |
| --- | --- | --- | --- | --- |
| **Outside Signal** | single | "distill an external X post / article / release into a project-aware insight — with receipts + a skeptic pass" | `signal, external, news, article, apply, insight` | Rename from **Post-to-Project Signal** |
| **What to Build Next** | single | "scan what changed outside the repo and recommend the next build direction for this project" | `signal, roadmap, next, direction, opportunity` | Rename from "What should we build next?" (already a decent intent phrase) |

### Not families — primitives & defaults (the router routes to these too)

- **Auto** (`default_chat`) — "just ask a model a question." The plain chat default.
- **`pair pilot`** — "have another model BUILD this while I supervise."
- **`pair relay`** — "keep building + reviewing overnight without me."

## Metadata every family ships (the router index)

For each team the router consumes: obvious **name**, an intent-phrase
**`description`** (the "why" it shows), tight **`typeTags`** (match keys above),
and **≥1 `starter`**. Enforced in `BuiltInTeamsTests`:

- every tiered family has a complete Min / Default / Max (or a justified omission);
- no family has an orphan Min/Max without a Default;
- no empty `typeTags`; ≥1 `starter`; no flavor names for depth.

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

**Caliber vocabulary** (bands over the existing `strengthRank`, so authors and
humans can talk about a role's level — realized through the resolver, NOT a new
hand-maintained list):

| Caliber | Band | Typical seats | Used for |
| --- | --- | --- | --- |
| **Flagship** | rank ≥ 95 | Fable, ChatGPT 5.6 Sol, ChatGPT (Codex) | Team Lead / synthesis; strategic seats. **Fable is Lead-only** — never a worker. |
| **High** | 85–94 | Opus, Cursor-Grok, Kimi K3, Grok | The everyday strong worker band. |
| **Mid** | 70–84 | Sonnet, Composer, Cursor-Auto, agy-Opus, Gemini, GLM, Qwen | Cheap capable fill; staff freely. |

The Lead is a named Flagship seat; worker rows triangulate across distinct
capable models (strongest reserved for the Lead), diversity front-loaded by rank.
Both are already what `TeamResolver` does — the fix is to let it, by tagging
capability in the catalog and dropping the hardcoded arrays.

### Design capability — reasoning vs image (and K3 + Sol)

Design has two seat kinds, and conflating them is a bug:

- **`design` capability** = design *reasoning*: information architecture,
  interaction, critique, direction, usability. A text model can hold this seat.
- **`image` capability** = actually *generates* a mockup image. Only image
  engines (Gemini, ChatGPT/Codex, Grok — per the generated-image harvest) qualify.

Decision (founder note): **Kimi K3 and ChatGPT 5.6 Sol are great designers** —
they get the **`design`** capability (reasoning/critique/direction seats), NOT
`image`. Concretely in `ModelCatalog.builtInCapabilities`: K3 gains the `.design`
laneTag **and** `.design` capabilityTag; Sol (and its Codex twin) gain the
`.design` capabilityTag. Because staffing is capability-driven, that one metadata
edit puts them on every design team's reasoning seats — no per-team edits.

## Slices

| Slice | Deliverable |
| --- | --- |
| CN-S05 | **Staffing by caliber (do first — lowest risk, immediate value).** (a) Metadata: add `design` to Kimi K3 (`.design` laneTag + capabilityTag), Sol, and Codex; add `image` to Codex + Grok so image seats resolve by capability; Gemini already carries both. (b) Re-author every team's rows to require capability + triangulate + caliber, and delete the hardcoded model arrays. (c) Graceful degradation verified with a reduced bench. Build + `BuiltInTeamsTests`/`PanelTeamResolverTests`/`TeamCatalogTests` green. **Independent of the rename/tier slices** — lands on the current team ids. |
| CN-S01 | Rename pass — Code Core→Plan, Execution Playbook→Build a Slice, Premium Polish→Polish, Usability Triage→Usability Review, Design Core→Design, Post-to-Project Signal→Outside Signal, "What should we build next?"→What to Build Next. Names + `id`s + `typeTags` + intent-phrase `description`s. |
| CN-S02 | Tier completion — add **Bug Hunt Min**; fold **Radical Directions** into **Design Max**; confirm Spec Review + Growth unchanged. Every tiered family Min/Default/Max complete. |
| CN-S03 | Merges/drops — retire **Conversion Studio**, route its intent to Copy Landing. |
| CN-S04 | `BuiltInTeamsTests` guards — tier completeness, non-empty `typeTags`, ≥1 `starter`, no flavor-depth names, no orphan tiers, **and no hardcoded per-team model arrays** (Law 3). Green gate. |

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

## Works test

Every family in the catalog reads as an obvious job to a cold agent and a human.
Tiered families (Spec Review, Bug Hunt, Growth, Design) have a complete
Min/Default/Max; single families have exactly one team and no orphan tiers.
`typeTags` are non-empty and intent-shaped; every family has ≥1 starter; zero
flavor/internal/depth names remain. **Staffing:** no team defines a hardcoded
model array; every role resolves to a correct-caliber, capability-matched model
from the ready bench and degrades gracefully on a reduced bench; Kimi K3 and Sol
appear on design reasoning seats with zero per-team edits. `BuiltInTeamsTests`,
`PanelTeamResolverTests`, `TeamCatalogTests` green. The router's golden-transcript
rows (in `Agent_Intent_Router.md`) then resolve each sample intent to exactly one
family.
