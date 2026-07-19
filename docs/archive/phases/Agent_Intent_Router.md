# Agent Intent Router — one front door that routes intent to the right killer team

Status: **Complete (archived 2026-07-19).** IR-S00–IR-S02 delivered.
IR-S01 `3d515ff0` · IR-S02a `aafb6ce6` · IR-S02b `df334af8`. Code is SSOT;
this doc is the historical law + proof packet. PARKED items remain parked
(fuzzy/model-assisted match; completion-receipt unified result shape).
Owner: AllnighterCore (`AgentHello` + `AgentIntentRouter`) + AllnighterCLI
(`team hello`)
Updated: 2026-07-19 (archived).

Execution order: ~~archived `Run_Lifecycle_Reliability.md`~~ (Complete /
RLR-S06) → ~~**IR-S02**~~ (Complete) → `Agent_Onboarding.md` (next; unblocked).

**Closeout (deslop/audit):** Docs-only archive. No product-code deslop in this
turn — IR-S02a/b already landed with focused golden tests (29/29
`AgentIntentRouterTests|AgentHelloTests`). No structural audit findings to
carry; successor work is `Agent_Onboarding.md`. Code SSOT:
`AgentIntentRouter.swift` / `AgentHello.swift`.

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

### Field evidence (2026-07-19, live probe)

A capable agent with the full `alln` help in front of it tried the ordinary
intent *"ask ChatGPT 5.6 Sol for read-only feedback on two docs"* and hit gate 3
exactly as predicted:

- **No verb maps the intent.** `alln run` self-describes as a *mutating project
  run*; `team` runs rosters; `help search "ask one model"` lands on the Auto
  topic, which explains what happens when you *don't* pick a model. A cautious
  agent stalls precisely because the honest docs say "mutating" and the intent
  is read-only.
- **The named worker resolves ambiguously.** "ChatGPT 5.6 Sol" matches TWO
  catalog entries across drivers — `model_chatgpt` (Codex, the native driver)
  and `model_chatgpt_sol` (Cursor) — and the natural id guess
  (`model_chatgpt_sol`, it contains "sol") picks the *wrong* driver. Nothing
  resolves display names to ids.

Both failures are router jobs. They are specced as Decisions 8–9 below; the
probe is the honest baseline the works test must beat.

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
4. **Route to Default; offer Min/Max only when the family is tiered.** Tiers are
   OPTIONAL per family (`Team_Catalog_Normalization.md` Law 2 — like model effort
   levels): tiered families (Spec Review, Bug Hunt, Growth, Design) expose
   **Min / Default / Max**; focused families (Copy, Security Review, Signal…) are
   single teams and that is correct, not a gap. The router always picks the
   Default and surfaces Min/Max as alternates *only when they exist* — never
   auto-escalates to Max. "Default" is the everyday team id (UI-only label).
5. **Team names must be obvious job phrases — for humans AND the router.** A team's
   name is the JOB stated plainly (Bug Hunt, Spec Review, Growth, Security Review,
   Design, Copy…), depth as the Min/Default/Max suffix. Obscure or flavor names
   (the retired "Post-to-Project Signal", "Radical Directions") defeated both a
   human scanning the picker and the router matching intent. The rename to
   obvious names SHIPPED 2026-07-19 (CN-S01, `1247bd12`).
6. **Honesty preserved.** If the user named a specific worker/model, the router
   echoes that requirement and never silently substitutes — a down requested seat
   is a loud fallback, not a swap (the routing law + explicit-worker honesty
   work). Automatic selection is only offered when the user did NOT name a seat,
   and is labeled automatic.
7. **The matcher is deterministic + explainable, not a model call.** Intent →
   team is a keyword/tag/lane match over the catalog index with a scored, testable
   mapping. No LLM in the hot path of the front door (latency + honesty). A future
   fuzzy pass is a parked enhancement, gated behind the deterministic floor.
8. **Named-worker resolution is a router job, not the caller's.** When the
   intent names a model ("Sol", "Grok", "ChatGPT 5.6 Sol"), `--for` resolves
   the name against catalog `displayName`/`modelLabel`/`id` — across drivers —
   and returns the resolved id in `requestedWorker`. When one model exists
   under multiple drivers, the pick is a **defined precedence, not vibes**:
   (1) filter to drivers that can honor the requested safety posture (a
   read-only ask never resolves to a driver that cannot mechanically enforce
   read-only — "same model, unsafe-for-this-posture driver" is a named refusal,
   not a fallback); (2) prefer the model vendor's own CLI (Codex for ChatGPT
   models) over a reseller driver; (3) then readiness; ties break on stable id
   order. Other-driver entries are listed as loud alternates with *why* — never
   a silent guess. A named worker constrains the WHOLE result: if the named
   seat is down, `recommended` carries no runnable command — `nextActions`
   offers the explicit choices (fix the seat, or the user re-chooses); an
   alternate is never runnable-as-recommended without explicit selection. An
   unresolvable name is a named failure (`WORKER_NAME_AMBIGUOUS` /
   `WORKER_NAME_UNKNOWN`) with the nearest matches in `nextActions`, not a
   fallback to Auto. Within a routed shape, a named worker pins a seat (the
   full `intent × named worker × family` precedence table is an IR-S02
   deliverable).
9. **The read-only quick ask is a first-class route, not a footnote of chat.**
   "Ask <model> what it thinks of X — don't change anything" must resolve to a
   runnable command that is honest about mutation — and "read-only" must be
   **mechanically enforced, not prompt-begged**: a "do not modify files" line
   in the prompt is an instruction the worker may ignore, so the route requires
   a read-only primitive/flag whose guarantee comes from the driver (Codex can
   sandbox read-only; Cursor headless runs `--trust` and cannot — see Decision
   8's posture filter). Until that verb exists, the router may return the
   chat/`run` route with the no-mutation instruction included, but must label
   it advisory-only in `why`. The router never routes a read-only intent to a
   command it must describe as mutating without addressing the mismatch — that
   is the exact stall the field probe hit. (Corollary, observed live: a
   read-only ask routed through `run` also *occupies the one-per-lane mutating
   execution lane*, serializing behind and blocking real mutating work — a
   dedicated read-only ask path is a lane-capacity fix, not just a naming
   fix. The same live run also mis-attributed the caller's concurrent commits
   to the worker in `outcome`/`repoDelta` — mechanical posture enforcement is
   what makes those surfaces trustworthy.)
10. **A long-running recommendation is a control bundle, not only a launch
    command.** IR-S01's `recommended.command` stays the primary runnable command.
    After archived `Run_Lifecycle_Reliability.md` freezes the shared control contract,
    IR-S02 adds the exact monitor/result/cancel argv appropriate to that target
    (team, pilot, relay, or direct chat/run). A mutating or unattended route must
    never teach final-only `--json` as if it were a progress transport. It uses
    the shipped async lifecycle or `--stream`, and every lifecycle argv consumes
    the same canonical run id. The router derives these commands from the CLI
    registry; it does not invent a parallel status schema.

## Return shape (`--for`)

```jsonc
{
  "recommended": {
    "teamId": "code_spec_review",
    "kind": "team",                 // team | pilot | relay | chat
    "why": "Intent 'harden this spec before I build' matched typeTags [spec, review].",
    "command": "alln team start \"<intent>\" --team code_spec_review --json",
    "depthAlternates": ["code_spec_review_min", "code_spec_review_max"]
  },
  "readiness": { "ready": true, "blockedReason": null },
  "requestedWorker": {              // present only when the intent named a seat
    "requestedName": "ChatGPT 5.6 Sol",
    "resolvedModelId": "model_chatgpt",
    "why": "Native Codex driver preferred; also available via Cursor (model_chatgpt_sol).",
    "alternates": ["model_chatgpt_sol"]
  },
  "fallback": {                     // present only when ideal seats are down
    "teamId": "code_spec_review_min",
    "why": "Preferred seats unavailable; Min needs no Claude/ChatGPT.",
    "command": "alln team start \"<intent>\" --team code_spec_review_min --json"
  },
  "lifecycle": {                    // IR-S02; long-running runnable targets only
    "monitor": {
      "argv": ["alln", "team", "status", "<run-id>", "--json"],
      "display": "alln team status <run-id> --json"
    },
    "result": {
      "argv": ["alln", "team", "result", "<run-id>", "--json"],
      "display": "alln team result <run-id> --json"
    },
    "cancel": {
      "argv": ["alln", "team", "cancel", "<run-id>", "--json"],
      "display": "alln team cancel <run-id> --json"
    }
  },
  "nextActions": [ /* never empty when not runnable */ ]
}
```

Two contract notes (the sketch above shows the *team* arm only): the final
schema is a **discriminated union on `kind`** — pilot/relay/chat targets carry
their own payloads (a `teamId`/`depthAlternates` pair is meaningless for
`pair relay`) plus `driverId`/`modelId` and the safety posture. And `command`
is emitted as **structured `argv` plus a display string** — the router never
manufactures shell quoting around untrusted intent text (quotes, newlines,
`$()` in a user utterance must not become a shell injection or a broken
copy-paste). The exact emitted grammar is frozen against the CLI contract in
IR-S01, not improvised per row.

## The intent taxonomy (the 80%) — routes to normalized families

The matcher maps the ~80% of dev/vibe-coder intent to a JOB family. The families,
their obvious names, tier shape, and `typeTags` are **defined in
`Team_Catalog_Normalization.md`** (the single source — this table stays a thin
taxonomy so the two don't drift). Depth is picked per Law 2 there: tiered
families route to Default with Min/Max alternates; single families route to the
one team.

| Intent (how the user talks) | Family (see normalization doc) |
| --- | --- |
| "turn my rough idea into a plan" | Plan |
| "harden this spec / challenge my plan before I build" | Spec Review *(tiered)* |
| "fix this bug / find the real cause" | Bug Hunt *(tiered)* |
| "the UI is visibly broken" | GUI Bug Hunt |
| "is this secure? credentials / permissions / exposure" | Security Review |
| "how do we get users to love + spread this" | Growth *(tiered)* |
| "prove this slice is actually done" | Release Proof |
| "just build this slice in the repo" | Build a Slice |
| "design / redesign this screen or flow" | Design *(tiered)* |
| "make this surface feel expensive / native" | Polish |
| "why does this surface feel confusing / slow" | Usability Review |
| "write clearer / more persuasive copy" | Copy Core |
| "rewrite my landing page / improve conversion" | Copy Landing |
| "what does this external post/article mean for us" | Outside Signal |
| "what should we build next" | What to Build Next |
| "have another model BUILD this while I supervise" | `pair pilot` *(primitive)* |
| "keep building + reviewing overnight" | `pair relay` *(primitive)* |
| "just ask a model a question" | Auto *(chat default)* |
| "ask <named model> for its read-only take on X" | Chat, worker-pinned *(Decisions 8–9)* |

**Known gaps (named, not silent — DECIDED 2026-07-19):** test-writing,
docs/README authoring, refactor-at-scale, and dependency/upgrade triage earn
NO dedicated family; `Team_Catalog_Normalization.md` ("Known-gap intents —
decided") pins each to its honest existing route (Build a Slice / Plan), with
demand evidence + founder approval as the future earn-a-family gate. The
router routes these four intents per that table.

## Where the team list is finalized

The taxonomy above (which intents must be reachable) lives here. The **family
definitions — names, tiers, rosters, metadata — are finalized in
`Team_Catalog_Normalization.md`**, then built into `BuiltInTeams.swift` under
`Team_And_Skill_Catalogs.md`. **Team metadata IS the router's *family* index** —
but not the whole index: named-worker resolution reads `ModelCatalog`
(displayName/driver/posture capability), and Pilot/Relay/Chat are primitives
outside the team catalog. IR-S01 names each index and its owner. That doc is
the hard prerequisite: the router is built only after the catalog is normalized.

## Slices

| Slice | Deliverable |
| --- | --- |
| IR-S00 | ✅ **DONE 2026-07-19** — `Team_Catalog_Normalization.md` landed (CN-S01–S04: obvious names + ids, complete tiers, drops, Law 4 typeTags, guard tests; commits `1247bd12`/`6266b8d4`/`daccc183`). The catalog is normalized; the router is unblocked. |
| IR-S01 | ✅ **DONE 2026-07-19 (`3d515ff0`)** — `alln team hello --for "<intent>" --json`; deterministic catalog matcher; `recommended` + `readiness` + `fallback` + `nextActions`; structured argv/display commands; overlap/no-match golden tests; generated contracts refreshed. Bare hello remains unchanged. Stop point requested by founder. |
| IR-S02 | ✅ **DONE 2026-07-19** — IR-S02a (`aafb6ce6`): named-worker resolution, primitives (Pilot/Relay/Chat), depth Min/Default/Max alternates, field-probe golden tests. IR-S02b (`df334af8`): registry-derived lifecycle monitor/result/cancel bundle + stream honesty; hello workflow status step. |
| PARKED | Fuzzy/model-assisted intent match behind the deterministic floor · completion-receipt unified result shape across team/pilot/relay (true metrics only — rounds, commits, tests, unattended duration; NEVER invented "handoffs avoided"). **Remain parked** — not in scope for this archive. |

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

**Proved 2026-07-19** (live CLI + golden tests).

IR-S01 proof (landed): `alln team hello --for "harden this spec before I
build" --json` → the **Spec Review** Default team with a runnable `team start`
command and Min/Max alternates. `--for "how do we get X builders to love this"` →
**Growth**. `--for "find the real cause of this crash"` → **Bug Hunt** Default.
`--for "rewrite my landing page"` → the **Copy** family. `--for "keep building
overnight without me"` → `pair relay`. A down-seat case returns a loud fallback,
never a silent swap. No `--for` = today's readiness report unchanged. Every
matrix row has a golden-transcript test; IR-S00 shows every approved family
with an obvious name and zero unnamed gaps — every *tiered* family complete
(Min/Default/Max all present), every *single* family with no depth alternates
(tiers are optional per Decision 4, so "untiered" is a passing state, not a
gap).

IR-S02 live works probe (proved):

- `--for "ask ChatGPT 5.6 Sol for read-only feedback on these two docs"` →
  chat, `model_chatgpt`, Cursor alternate, readOnly, `lifecycle.cancel` via
  kill — no stall, no wrong-driver guess.
- `--for "harden this spec before I build"` → `code_spec_review` + full team
  lifecycle monitor/result/cancel argv sharing the canonical run id.

Unit wall: 29/29 green for `AgentIntentRouterTests|AgentHelloTests`. A
long-running routed command returns monitor/result/cancel argv; no recommended
transport describes final-only JSON as live progress.
