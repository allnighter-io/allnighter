# Team Depth Naming — Min / Default / Max

**Status: DECIDED (founder, 2026-07-16).** Naming-convention SSOT for built-in
team families and depth tiers. Supersedes the Lite / Forensics naming in
`Team_Lab_Composition_And_Seat_Economics.md` §Named Team Variants (rosters,
seat economics, and routing mechanics there are unchanged — names only).

## The problem

The founder could not name his own hero team: the spec-hardening loop is
marketed as "Pressure Test" (`Pressure_Test.md`) while the team in the picker
is "Spec Review". The bug family is worse — `code_bug_hunt_lite` displays as
"Bug Hunter" and `code_bug_hunt` displays as "Bug Hunter Forensics", so IDs and
display names disagree on which one is the base. Unique flavor names per depth
cost `families × depths` memory slots. If the founder can't remember the names,
users are lost, and Allnighter never becomes a habit.

## The rule

1. **Family name = the job, named by what it does.** Spec Review, Bug Hunt,
   Security Review, Release Proof. Function beats brand: "Pressure Test" stays
   a marketing/loop name in docs and landing copy ("the Pressure Test workflow:
   run Spec Review before you build") — it is never a team name.
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
   is always the default send. Min and Max exist only where Team Lab proves
   them (necessity suite for Min, forward selection for Max). This also
   resolves the old "default send → Lite" routing: the first-pass roster IS
   the unsuffixed team.
7. **Unique names remain for genuinely different jobs.** Conversion Studio vs
   Premium Polish are different jobs, not depths of one job. The rule is only:
   never spend a unique name where a depth word suffices.

## What Min and Max mean (definitions, not vibes)

- **Min** = the smallest roster with positive seat economics — every seat
  proven necessary on the family's necessity suite. Min is not "weak"; it is
  *nothing wasted*.
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
| — (does not exist) | `code_spec_review_min` → "Spec Review Min" (~3 seats; first new Min to cut, LAB-C04-style overlay) |
| `code_bug_hunt_lite` → "Bug Hunter" | `code_bug_hunt` → "Bug Hunt" (bare/default tier) |
| `code_bug_hunt` → "Bug Hunter Forensics" | `code_bug_hunt_max` → "Bug Hunt Max" (description keeps the forensics framing) |

ID migration ordering note: today's `code_bug_hunt` must move to
`code_bug_hunt_max` **before** `code_bug_hunt_lite` takes the bare
`code_bug_hunt` id. User overrides stored at the same id (edit-in-place) must
be migrated with their team or explicitly invalidated — decide in the slice,
never silently orphaned.

## UI consequences

- Depth is **one segmented control (Min / Default / Max)** rendered next to
  the family — never three sibling rows in the team picker. Tiers a family
  doesn't have render disabled or hidden.
- Escalation copy writes itself from the vocabulary:
  *"Bug Hunt thinks this runs deeper than it looks — rerun as Bug Hunt Max?"*
  (`escalationRecommended` routing, LAB-C08 — unchanged, relabeled.)

## Deferred

- The rename slice itself (frozen behind `Language_Cutover.md` landing;
  hard-rename, no aliases).
- Cutting `code_spec_review_min` (Team Lab necessity work, not a hand guess).
- Sweep remaining built-ins for depth-words-in-disguise once the first two
  families land.
