# Agent Intent Router — one front door that routes intent to the right killer team

Status: Specced v1 — the keystone gate between "agent found alln" and "agent
ran the right team." Awaiting founder go. The matcher is built on catalog
metadata (`description`/`typeTags`/`starters`/`lane`) — but that catalog is
STALE and pre-rename: only Spec Review and Growth follow the Min/Default/Max law
with obvious names. **IR-S00 (founder-gated catalog normalization) is a hard
prerequisite; the router cannot route over a stale catalog.**
Owner: AllnighterCore (`AgentHello` + catalog) + AllnighterCLI (`team hello`)
Updated: 2026-07-18

## The gap (the third gate)

An agent passes three gates before Allnighter gets used:

1. **FIND it** — `alln` on PATH, no empty silence → `Agent_Front_Door.md` (SHIPPED).
2. **SUGGEST it** — a cold session reaches for it unprompted → `Agent_Onboarding.md`.
3. **ROUTE it** — given the user's intent, land on the *right killer team or
   primitive* without memorizing the catalog → **THIS doc.**

Today `alln team hello` is a **static readiness report**: it returns the same
`nextCommandPlan` (`alln team preflight --team <team-id> --json`, a literal
placeholder) regardless of what the user actually wants. The agent still has to
know which team `<team-id>` should be. As the catalog grows — Bug Hunt,
Security, Growth, Design, Copy, Signal — a bigger catalog gets *worse* for a
cold agent, not better, unless something routes by intent. **More killer teams
only pay off behind an intent router.**

## The insight

`team hello` should stop being documentation and become a tiny local solutions
engineer. The agent's easiest decision must become: *"I'm unsure whether
Allnighter applies, so I'll ask Allnighter — it costs nothing and changes
nothing."*

The match material already exists in the catalog. Every `TeamPreset` carries
`description` (an intent phrase), `typeTags` (machine match keys), `starters`
(example utterances), and `lane`. The router is a matcher over that index, plus
the readiness the verdict already computes.

## Decisions

1. **New mode, same command: `alln team hello --for "<intent>" --json`.** With
   `--for`, hello resolves the caller's intent to a recommended team (or Pilot/
   Relay primitive), returns *why*, readiness, an **exact runnable command**, and
   ONE fallback if the ideal seats are down. Without `--for`, hello keeps today's
   readiness-report behavior (no breaking change).
2. **The no-empty-silence law extends here.** `--for` NEVER returns a bare "pick
   a team." It returns a concrete command or an honest fallback + `nextActions`.
   (Same law as `Agent_Front_Door.md` F3.)
3. **Route to the specific team, never a generic "Panel."** The teaching mnemonic
   is *Panel hardens the judgment · Pilot builds the work · Relay runs the night*,
   but the router resolves to a real team id (`code_bug_hunt`, `code_growth`,
   `code_spec_review`, …) or a real primitive (`pair pilot`, `pair relay`). The
   mnemonic is for humans; the command is for machines.
4. **Every family is Min / Default / Max; route to Default, offer up/down.** The
   depth law is universal (`Team_Depth_Naming.md`): every team family exposes the
   same three tiers — **Min / Default / Max** ("Default" is the bare, everyday
   team id; it is what the router picks). Route to Default and surface Min/Max as
   alternates — never auto-escalate to Max. A family that does NOT yet have all
   three tiers is NOT router-ready (see IR-S00). **No flavor names for depth**
   (no "Premium Polish", "Conversion Studio" as tiers) — those are either
   distinct job families in their own right or they collapse into Design's tiers;
   IR-S00 decides, the founder approves.
5. **Team names must be obvious job phrases — for humans AND the router.** A team's
   name is the JOB stated plainly (Bug Hunt, Spec Review, Growth, Security Review,
   Design, Copy…), depth as the Min/Default/Max suffix. Obscure or flavor names
   ("Post-to-Project Signal", "Radical Directions") defeat both a human scanning
   the picker and the router matching intent. Renaming to obvious names is part of
   IR-S00 and is founder-gated.
6. **Honesty preserved.** If the user named a specific worker/model, the router
   echoes that requirement and never silently substitutes — a down requested seat
   is a loud fallback, not a swap (the routing law + explicit-worker honesty
   work). Automatic selection is only offered when the user did NOT name a seat,
   and is labeled automatic.
7. **The matcher is deterministic + explainable, not a model call.** Intent →
   team is a keyword/tag/lane match over the catalog index with a scored, testable
   mapping. No LLM in the hot path of the front door (latency + honesty). A future
   fuzzy pass is a parked enhancement, gated behind the deterministic floor.

## Return shape (`--for`)

```jsonc
{
  "recommended": {
    "teamId": "code_spec_review",
    "kind": "team",                 // team | pilot | relay | chat
    "why": "Intent 'harden this spec before I build' matched typeTags [spec, review].",
    "command": "alln team start --team code_spec_review --json \"<intent>\"",
    "depthAlternates": ["code_spec_review_min", "code_spec_review_max"]
  },
  "readiness": { "ready": true, "blockedReason": null },
  "fallback": {                     // present only when ideal seats are down
    "teamId": "code_spec_review_min",
    "why": "Preferred seats unavailable; Min needs no Claude/ChatGPT.",
    "command": "alln team start --team code_spec_review_min --json \"<intent>\""
  },
  "nextActions": [ /* never empty when not runnable */ ]
}
```

## The intent → target-family matrix (the 80%) — and the catalog is NOT ready

This is the routing table the matcher must implement: the ~80% of dev/vibe-coder
intent, mapped to the JOB family it should reach. **This table is the target.
The current catalog does NOT yet satisfy it** — and that is the real work, not a
footnote.

**Only `Spec Review` and `Growth` are approved and correctly tiered
(Min/Default/Max).** Every other family is either missing tiers, single-team, or
flavor-named — all of which defeat both a human scanning the picker and the
router matching intent. Status is honest below; ✅ is reserved for
approved-and-tiered.

| Intent (how the user talks) | Target family | Depth today | Status |
| --- | --- | --- | --- |
| "harden this spec / challenge my plan before I build" | **Spec Review** | Min/Default/Max | ✅ LOCKED |
| "how do we get users to love + spread this" | **Growth** | Min/Default/Max | ✅ LOCKED |
| "fix this bug / find the real cause" | **Bug Hunt** | Default + Max, **no Min** | ⚠ REVIEW — add Min |
| "the UI is visibly broken" | **Bug Hunt** (GUI) | separate single team | ⚠ REVIEW — GUI = a Bug Hunt tier/variant or its own family? |
| "design a screen / directions / polish / usability" | **Design** | 5 flavor-named teams (`premium_polish`, `conversion_studio`, `radical_directions`, `usability_triage`) | ⚠ REVIEW — which are Design tiers vs distinct families? Rename to law |
| "is this secure? check credentials/permissions" | **Security Review** | single team | ✗ RENORMALIZE — add Min/Default/Max |
| "prove this slice is actually done" | **Release Proof** | single team | ✗ RENORMALIZE |
| "turn this rough idea into a plan" | **Code Core / Plan** | single (`code_core`) | ✗ RENORMALIZE + obvious name |
| "write clearer/persuasive copy" | **Copy** | `copy_core` + `copy_landing_page` (flavor) | ✗ RENORMALIZE — tiers + obvious names |
| "rewrite this landing page to convert" | **Copy** (or Landing family) | flavor-named | ✗ RENORMALIZE |
| "what changed outside / what to build next" | **Signal** | 2 obscure-named teams (`post_to_project`, `what_to_build_next`) | ✗ RENORMALIZE — obvious names + tiers |
| "have another model BUILD this while I supervise" | `pair pilot` | primitive | ✅ (not a team) |
| "keep building + reviewing overnight" | `pair relay` | primitive | ✅ (not a team) |
| "just ask a model a question" | Auto / Chat | `default_chat` | — routing default |

**Finding (corrected): the catalog is STALE and pre-rename.** Only Spec Review
and Growth follow the universal Min/Default/Max law with obvious names. The
router cannot route reliably over flavor names, missing tiers, and obscure ids.
So the near-term work is a **catalog normalization pass**, not "just discovery" —
and it is founder-gated (which families are approved is a founder call, exactly
as Spec Review and Growth were).

**Known gaps to decide during IR-S00, not silently:** test-writing, docs/README
authoring, refactor-at-scale, and dependency/upgrade triage have no family today
and route to Code Core / Pilot. Decide per-gap whether a dedicated family earns
its place.

## Where the team list is finalized and built

This doc **owns the intent taxonomy and the target matrix** (which JOB families
must exist and be reachable). It does **not** own the team definitions — those
live in `BuiltInTeams.swift`, governed by `Team_And_Skill_Catalogs.md` and the
Team Lab docs (`Team_Lab_Run_Factory.md`). The contract:

- **Router doc (here):** decides *which intents must have a killer family* and
  the target names/tiers. Names gaps.
- **Catalog / Team Lab:** normalizes and builds the definitions to the law — every
  approved family gets Min/Default/Max, an obvious job name, an intent-phrase
  `description`, tight `typeTags`, and ≥1 `starter`. **Team metadata IS the router
  index** (amendment recorded in `Team_And_Skill_Catalogs.md`).

So "finalize the team list" happens in **IR-S00**, which is a real normalization
project (below), not a rubber-stamp audit.

## Slices

| Slice | Deliverable |
| --- | --- |
| IR-S00 | **Catalog normalization (founder-gated) — the real prerequisite.** For each JOB family in the matrix: (a) founder approves it as a family (as Spec Review + Growth already are); (b) give it an obvious job name; (c) build Min/Default/Max rosters (Spec Review + Growth are the template; Bug Hunt needs Min; Security/Release Proof/Code Core/Copy/Signal need full tiers; Design's flavor teams get sorted into tiers vs distinct families); (d) intent-phrase `description` + tight `typeTags` + ≥1 `starter`. Enforce Min/Default/Max completeness + non-empty `typeTags` + ≥1 `starter` in `BuiltInTeamsTests`. **Blocks S01** — the router cannot route over a stale catalog. |
| IR-S01 | `alln team hello --for "<intent>" --json` — deterministic matcher over catalog `typeTags`/`description`/`lane`; `recommended` + `readiness` + `fallback` + `nextActions`; no-empty-silence + honesty laws enforced; golden-transcript tests for the matrix rows. |
| IR-S02 | Depth + primitive routing — Min/Default/Max alternates; Pilot/Relay/Chat as first-class targets; requested-worker echo (no silent substitution). |
| PARKED | Fuzzy/model-assisted intent match behind the deterministic floor · completion-receipt unified result shape across team/pilot/relay (true metrics only — rounds, commits, tests, unattended duration; NEVER invented "handoffs avoided"). |

## Anti-goals

- **No generic "Panel" as a route target** — always a specific team id or primitive.
- **No flavor names for depth, no obscure ids** — obvious job name + Min/Default/Max.
  Flavor/obscure names defeat both human scan and router match.
- **No LLM in the front-door hot path** — deterministic matcher first; latency and
  honesty both forbid a model call to answer "which team."
- **No silent substitution** — a down requested seat is a loud fallback.
- **No new top-level noun** — this is a *mode* of `team hello`, not a new command.
- **No inventing families to fill the matrix for its own sake** — a gap the
  generalist route serves honestly stays a generalist route; a new family is
  founder-approved, exactly as Spec Review and Growth were.

## Works test

After IR-S00 normalization: `alln team hello --for "harden this spec before I
build" --json` → the **Spec Review** Default team with a runnable `team start`
command and Min/Max alternates. `--for "how do we get X builders to love this"` →
**Growth**. `--for "find the real cause of this crash"` → **Bug Hunt** Default.
`--for "rewrite my landing page"` → the **Copy** family. `--for "keep building
overnight without me"` → `pair relay`. A down-seat case returns a loud fallback,
never a silent swap. A named-worker case echoes the requirement. No `--for` =
today's readiness report unchanged. Every matrix row has a golden-transcript test;
IR-S00 shows every approved family tiered Min/Default/Max with an obvious name and
zero unnamed gaps.
