# Team Depth Naming — Min / Default / Max

**Status: ARCHIVED 2026-07-26** (DECIDED 2026-07-16; catalog applied).
**Promoted:** `docs/workflows/Product_Vocabulary.md` § Team depth naming.
This file is the closed naming-convention record — not live phase work.

## The problem

The founder could not name his own hero team: the spec-hardening loop is
marketed as "Pressure Test" (now `Spec_Review.md`) while the team in the picker
is "Spec Review". The bug family is worse — `code_bug_hunt_lite` displays as
"Bug Hunter" and `code_bug_hunt` displays as "Bug Hunter Forensics", so IDs and
display names disagree on which one is the base. Unique flavor names per depth
cost `families × depths` memory slots. If the founder can't remember the names,
users are lost, and Allnighter never becomes a habit.

## The rule

1. **Family name = the job, named by what it does.** Spec Review, Bug Hunt,
   Security Review, Release Proof. Function beats brand, **marketing included**
   (founder, 2026-07-16): "Pressure Test" is retired everywhere — picker,
   docs, landing copy. One name per job, described in plain words ("run Spec
   Review before you build"). Clear language helps everywhere; a hero loop
   marketed under one name and invoked under another can't become a habit.
2. **Depth = one universal closed vocabulary: Min / (bare name) / Max.** The
   same two suffix words on every family, like model effort levels. Users
   memorize `families + 1` things, not `families × depths`.
3. **The middle tier is unsuffixed and is the default.** The name you remember
   is the name of the right choice. The picker's segmented control renders
   **Min / Default / Max** — "Default" is a UI label only; it never appears in
   a team name, ID, or CLI invocation. Nobody types "Spec Review Default".
4. **IDs follow the names:** `<family>_min` / `<family>` / `<family>_max`.
5. **No numbers in names.** Team Lab ablation changes seat counts; "Spec
   Review 6" becomes a lie the day forward selection proves 5 seats beat 6.
   Seat count is picker metadata (a badge like "8 seats"), never the name.
6. **Not every family ships all three tiers.** The bare name always exists and
   is always the default send. Min and Max are curated product assets; Team Lab
   necessity and forward-selection runs refine their rosters rather than
   generating tiers mechanically. This also
   resolves the old "default send → Lite" routing: the first-pass roster IS
   the unsuffixed team.
7. **Unique names remain for genuinely different jobs.** Polish vs Usability
   Review are different jobs, not depths of one job. The rule is only:
   never spend a unique name where a depth word suffices.

## What Min and Max mean (definitions, not vibes)

- **Min** = the smallest curated roster expected to retain the family's core
  outcome. Team Lab should prove every seat necessary on the family's necessity
  suite and may tune the initial roster. Min is not "weak"; it is *nothing
  wasted*.
- **Max** = every seat that earns its place on the hardest case class
  (forward selection). Old flavor names (e.g. "Forensics") survive as the Max
  tier's *description*, not its name.
- Each tier is a **distinct hand-curated named team** — its own seats, its own
  prompts, its own champion overlay under `docs/team-lab/champions/`. Never a
  generated or amputated copy. "Team shape is a named Team, not a generic
  depth dial" (`Team_Lab_Composition_And_Seat_Economics.md`) stands; the depth
  words are how humans address curated teams, not a roster generator.
- Untouched: **Effort (Low/Med/High) remains per-worker model reasoning only**
  (decision 2026-06-18). Depth never gates worker count off the effort dial.

## Rename map (mechanical slice — follows the `Language_Cutover.md` no-alias rule)

| Today (id → display) | Becomes (id → display) |
| --- | --- |
| `code_spec_review` → "Spec Review" | unchanged (bare/default tier) |
| — (did not exist) | `code_spec_review_min` → "Spec Review Min" (3 workers + Lead; shipped 2026-07-18) |
| `code_spec_review` full panel | `code_spec_review_max` → "Spec Review Max" (full 7-worker + scout + Lead panel) |
| `code_spec_review` full panel | `code_spec_review` → "Spec Review" (curated 5-worker + Lead default) |
| `code_bug_hunt_lite` → "Bug Hunter" | `code_bug_hunt` → "Bug Hunt" (bare/default tier) |
| `code_bug_hunt` → "Bug Hunter Forensics" | `code_bug_hunt_max` → "Bug Hunt Max" (description keeps the forensics framing) |

ID migration ordering note: today's `code_bug_hunt` must move to
`code_bug_hunt_max` **before** `code_bug_hunt_lite` takes the bare
`code_bug_hunt` id. User overrides stored at the same id (edit-in-place) must
be migrated with their team or explicitly invalidated — decide in the slice,
never silently orphaned.

## Routing law (founder, 2026-07-16)

- **Every default send resolves to the bare (Default) team.** Auto and any
  automatic routing never select Min. Min is an explicit user choice, always.
- Escalation may **recommend** Max (`escalationRecommended`, LAB-C08) but
  never silently switches teams — unchanged from the seat-economics spec,
  relabeled.

## UI consequences

- Depth is **one segmented control (Min / Default / Max)** rendered next to
  the family — never three sibling rows in the team picker. Tiers a family
  doesn't have render disabled or hidden.
- Escalation copy writes itself from the vocabulary:
  *"Bug Hunt thinks this runs deeper than it looks — rerun as Bug Hunt Max?"*
  (`escalationRecommended` routing, LAB-C08 — unchanged, relabeled.)

## Execution order (decided 2026-07-16)

1. **The rename slice runs FIRST — before any Team Lab implementation.**
   `Language_Cutover.md` is DONE (2026-06-18), so nothing blocks it; only its
   no-alias rule carries forward. Team Lab writes champion overlays and suites
   keyed by team IDs (`docs/team-lab/champions/<suite>/<team_id>.json`) —
   calibrating against IDs that are about to be hard-renamed would mint dead
   names on day one. Rename first so every lab artifact is born with final
   names.
2. ~~Then Team Lab~~ **Moot (2026-07-24): Team Lab is SHUT DOWN** (founder
   ruling — we have all the teams we want/need for now). The three Team Lab
   docs are archived un-rebased; this step does not resume without a new
   founder ruling.
3. **Spec Review tiers shipped (2026-07-18, founder decision):** the former
   full panel became Max; the bare team is the curated five-worker default; Min
   is a three-worker cross-CLI panel. Team Lab now validates and tunes these
   shipped assets instead of blocking their existence.

## Spec Review v1 staffing and fallback law (2026-07-18)

The tier must remain runnable when Claude and ChatGPT/Codex are both absent.
Preferred worker staffing therefore leads with Kimi K3, Grok 4.5, and Cursor
Grok 4.5 rather than treating them as last-resort substitutes:

| Tier | Preferred workers (Lead excluded) |
| --- | --- |
| Min | First Principles — Kimi K3; Proof — Cursor Grok 4.5; Scope — Grok 4.5 |
| Default | First Principles — ChatGPT 5.6 Sol; Doc Hygiene — Kimi K3; Contract — Grok 4.5; Proof — Cursor Grok 4.5; Contrarian — Gemini |
| Max | Default/full lenses restaffed across Sol, Kimi, Cursor Grok, ChatGPT 5.6, Grok, Composer, and Gemini; Grok outside scout |

Every Spec Review row declares an ordered cross-CLI fallback chain, followed by
the generic ready-bench fallback so custom and future models remain eligible.
All built-in synthesis Leads share the resilient order Fable 5 → ChatGPT 5.6
Sol → Opus 4.8 → Kimi K3 → Cursor Grok 4.5 → Grok 4.5, then continue across
the remaining ready bench. Worker substitution ranks place Kimi K3 and both
Grok routes above Sonnet 5.

## Rename slice scope (zero users → zero dead names)

- Built-in team IDs + display names per the rename map above, including
  edit-in-place override migration.
- **All user-facing strings**: team descriptions, starter prompts, picker
  copy — no "harden"/"pressure test"/"forensics"/"lite" survivors where a
  depth word or the family name is meant.
- **Marketing/docs sweep** (DONE 2026-07-16): `Pressure_Test.md` renamed to
  `Spec_Review.md` and reframed around Spec Review as the one name; active specs
  updated in place. Historical/shipped
  phase docs get a superseded banner, not a rewrite.
- Acceptance: case-insensitive repo grep for the retired names
  (`pressure test`, `forensics`, `lite`) is clean in code, user-facing
  strings, and active specs (banner'd history docs excepted).
