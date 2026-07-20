# Menu, Not Router — the caller is the brain; alln is the menu

Status: **Draft v2 (2026-07-20) — founder-ordered replacement for the retired
intent-router architecture, hardened by two independent mentor reviews.**
Supersedes archived `Agent_Intent_Router.md` in full. Foundation-first: no
users, no migration, no compatibility shims, no salvage. The router code is
deleted, not wrapped.
**Scope of the claim (mentor-forced honesty): this phase ends
wrong-spend-from-guessing.** It does not by itself make `alln` the tool of
choice — the named follow-ons are listed below and are NOT this phase.
Owner: AllnighterCore (`ContractRegistry`, `TeamCatalog`, `ModelCatalog`,
error catalog) + AllnighterCLI (listings, bootstrap snippet)
Updated: 2026-07-20 (v2)

Related: archived `Agent_Intent_Router.md` (the retired architecture — read
only to understand what NOT to rebuild) · `CLI_Agent_Ergonomics.md`
(AE — this phase completes its thesis; Laws 2/3/6 and S13/S15 are the
foundation this builds on) · `docs/workflows/SSOT_Feature_Workflow.md`
(Prior Art step — this phase exists because that step was skipped once)

## Founder ruling (2026-07-20)

A deterministic server-side intent router is the wrong architecture, period.
`alln`'s caller is a frontier LLM — the best intent-understander on the
machine, already paid for, holding conversation context we will never see.
Claude Code, Codex, Cursor, and Grok all solved capability selection the same
way: **a complete, well-described menu that the model reads and chooses
from.** None of them ship a keyword NLU that guesses what the user meant.
Retrieval may be lexical; **decision is never lexical.**

We built the opposite — a Swift keyword matcher deciding, on the caller's
behalf, which quota-spending command to run — and it failed every cold-agent
probe in exactly the way open intent space guarantees a closed keyword list
must fail. Our own AE-S00 vendor study said this verbatim ("disclosure to the
model; the model selects") before the router shipped. The premise was never
audited. It is now, and it is dead.

## The from-scratch derivation (what this phase builds)

Question: an agent wants to use Allnighter — chat with a named model, run a
team, start a pilot — without memorizing the catalog. What is the minimum
honest machinery?

1. **A complete menu written for model selection.** Names, trigger-shaped
   descriptions ("use when the user says…"), anti-examples ("do NOT use
   when…"), one worked invocation. The caller's weights do the rest at an
   accuracy no matcher can approach. *Mostly shipped:* AE-S13
   (`commands --json`, completeness marker) + AE-S15 (description standard)
   cover commands. The gaps: `teams --json` / `models --json` / recipe rows
   do not yet carry the standard, and full-detail dumps violate the two-tier
   pattern the vendors are unanimous on.
2. **Exactness at the point of use.** Every identifier flag resolves by
   **exact match over id ∪ display name** (normalized case/whitespace) or
   fails loudly with structured near-matches. A *unique* exact display name
   ("Sonnet 5") resolves — that is validation, not routing. An *ambiguous*
   name ("Sol", two drivers) fails listing every candidate with driver
   metadata and no default. A miss fails with suggestions carrying
   ready-to-paste argv. Never edit-distance auto-resolution; suggest, never
   substitute. *Mostly shipped:* AE Law 2 + AE-S07; the gaps are
   display-name matching and structured repair payloads.
3. **Probing is free; spending is explicit.** Free twins for every spending
   verb, so the caller can verify its choice before quota moves. *Shipped:*
   AE-S04 / AE Law 3. No new work.

That is the entire architecture. **There is no fourth component.** No intent
endpoint, no taxonomy, no scorer, no "front door" command. The front door is
`alln --help` and the bootstrap snippet pointing at the menu.

## The residual risk the mentors both found

**The menu can mislead without a router.** Post-deletion, the dangerous path
is an *honest* one: an agent reads `teams --json`, sees `code_growth`, and
maps "create a growth team" → `team start --team code_growth`. No matcher
required — just a spending row with no management anti-example. The menu is
only as safe as its anti-examples are ruthless. That risk drives MR-S02's
mandatory cross-verb anti-examples and MR-S05's honest-menu-misread probe;
zero-wrong-spends is asserted against *this* path, not only the deleted
router's.

Second residual: **`alln` is not ambient.** Claude Code and Cursor re-present
their tool menus every turn; `alln` is an external binary the agent must
remember to consult, and a catalog memorized in one session is stale in the
next. The countermeasure is taught discipline (MR-S04), not machinery:
re-read the relevant listing before any unfamiliar spend; never trust a
cached catalog across sessions.

## Laws

1. **The caller decides; alln discloses, resolves, and verifies.** No alln
   code path may map free natural-language text to a command, team, or
   worker. Free text is never an input to selection — only identifiers and
   flags are.
2. **Retrieval is honest about being retrieval.** Lexical search surfaces
   (`help search`) return **menu slices** — the same structured fields as the
   listings — never a runnable recommendation, never a spending argv. A
   search result is a menu excerpt, not a verdict.
3. **The menu is complete, selection-grade, and skimmable — two tiers.**
   Tier 1: every listing's default output is a **complete compact index**
   (id, display name, one-line trigger) cheap enough to read whole — a
   listing that doesn't fit in a tool result is incomplete in practice.
   Tier 2: full selection-grade detail (`useWhen`, `dontUseWhen`, worked
   example) on demand per id or via `--full`, on **existing nouns** (`team
   show`, `models`, `docs`) — no new discovery commands. The completeness
   gates bind to the tier-2 records.
4. **Every spending row carries cross-verb anti-examples.** A row whose
   example spends quota must state the adjacent intents it does NOT serve
   and name where they live ("do NOT use for create / duplicate / edit /
   customize a team — `teams duplicate`, `teams edit`"). This is the
   structural defense for the honest-misread path above.
5. **Errors are structured repairs.** An unresolved or ambiguous identifier
   returns machine fields — error code, flag, provided value, candidates
   with `{id, displayName, driver, nativeDriver}` and a ready-to-paste
   corrected argv — so the caller applies a one-shot repair without parsing
   prose. (Agent-first schemas law, applied to the failure path.)
6. **Nothing fuzzy ever spends.** Only an exact, validated identifier can
   reach a spending dispatch. With no router, no code path is *left* that
   could fuzzy-match into a spend; this law keeps it that way.

## Anti-goals

- **No intent endpoint, ever again** — not deterministic, not model-assisted,
  not "just for the easy cases." The parked "fuzzy/model-assisted match" from
  the archived router doc is not parked; it is rejected.
- **No model call inside alln** (no-API-keys law; latency). The model in the
  loop is the caller, for free.
- **No salvage wrappers.** `AgentIntentRouter` is deleted, not demoted to a
  "suggest" helper. Dead architecture leaves no residue to re-grow from.
- **No compatibility aliases** for `team hello` / `route` / `resolve`.
  Pre-user, foundation-first: removed commands are removed
  (contractVersion major bump per AE-S11 semantics).
- **No new discovery nouns.** Two-tier disclosure lands on existing surfaces;
  the menu gets finished, not multiplied.
- **No static catalog copies in installed surfaces.** The bootstrap snippet
  teaches the reflex and the stable family names only — an embedded full
  catalog in host configs is a hand-written drift surface reborn (AE
  Pattern C).

## What this phase does NOT fix (named follow-ons, not smuggled in)

- **Posture honesty + skinny chat envelope** — a one-word ask today returns a
  bloated envelope labeled `mutating`; agents need an honest read-only
  posture and a thin answer view. This is the next bottleneck after the menu
  is correct, and it is its own phase.
- **Composition workflows** — Growth → phase doc → Pilot is a chain, not a
  row pick. MR-S02 puts recipes into the menu; teaching multi-step chains
  well is follow-on work.
- **Misc discovery friction** — positional-only `help search`, missing
  `docs` topics, no cheap "list active runs," placeholder-heavy examples
  outside the touched surfaces. Real; tracked; not this phase.

## Slices

| Slice | Deliverable |
| --- | --- |
| **MR-S01** | **Delete the router.** Remove `AgentIntentRouter.swift`, `AgentHello.swift`, the `--for` mode, `team hello`, `route`/`resolve` aliases, their `ContractRegistry` entries, `AgentIntentRouterTests` + `AgentHelloTests`, and every teaching-surface reference (`Bootstrap.swift`, `TeachingSnippet.swift`, `RecipeCatalog.swift`, help topics). contractVersion **major** bump; regenerate contracts + lock (AE-S11 gate enforces). Add `team hello`, `route`, `resolve`, `--for` to `RetiredVocabulary`. **Readiness facts survive elsewhere:** before deleting, verify every fact bare `team hello` reported is available via `doctor` / `team preflight` / `teams`; anything orphaned moves there in the same slice — free probe-before-spend is a pillar, and it must not be collapsed into "preflight after you've chosen." |
| **MR-S02** | **Selection-grade, two-tier menu everywhere.** Tier 1: `teams --json` / `models --json` default to the complete compact index (Law 3). Tier 2: detail records carry `useWhen` (situation-shaped), `dontUseWhen`, `example` (runnable argv, real values); model records add `displayName`, `driver`, `nativeDriver: bool`, posture capability. **Every spending row carries cross-verb anti-examples (Law 4) — gate enforced.** Recipes join the completeness guarantee as rows reachable from `commands --json`/existing help surfaces (no new noun), so composition intents ("ask several models…") are findable from the menu alone. Gate: registry test over all tier-2 records for the three fields + the management anti-example on spending rows. |
| **MR-S03** | **Point-of-use resolution: exact over id ∪ display name, structured repairs.** Unique exact display name resolves (`--worker "Sonnet 5"` → `model_sonnet`, logged as resolved-by-display-name in the envelope). Ambiguity fails listing all candidates with driver metadata, no default. Miss fails with structured suggestions per Law 5 (candidates + ready-to-paste corrected argv). Reuses AE-S07 machinery; matching stays exact — no edit-distance auto-resolution. Gates: `"Sonnet 5"` resolves; `"Sol"` exits non-zero with both driver entries, neither preselected; `"Sonet 5"` exits non-zero with `model_sonnet` in a structured `didYouMean` carrying corrected argv. |
| **MR-S04** | **Bootstrap teaches the menu reflex — one call, then re-fetch discipline.** The taught reflex: **one** tier-1 fetch (`alln commands --json`, which names the teams/models/recipes listings) → pick → `--dry-run`/`preflight` → run. Delete every `team hello --for` teaching. The snippet states the completeness guarantee ("this list is exhaustive; if it isn't listed, it doesn't exist") and the two staleness rules: re-read the relevant listing before any unfamiliar spending command; never reuse a catalog memorized in a previous session. Snippet contains the reflex + stable family names only — never an embedded catalog (anti-goal). |
| **MR-S05** | **Cold-agent proof, out-of-distribution, positive AND negative.** AE-S09 harness with permanent rows: named-model ask ("ask Sonnet 5 …"), management intent ("duplicate the growth team so I can edit seats"), composition intent ("ask several models for growth ideas"), bare model name ("Sonnet 5"), and the **honest-misread probe** — an agent given only the menu must land management intents on `teams duplicate`/`teams edit`, proving Law 4's anti-examples carry the weight the router no longer pretends to. **Negative assertions:** zero spending dispatches on management/composition/bare probes; zero invented flags; `help search` output contains no spending argv (Law 2 regression row). **Positive assertions:** each probe reaches the *correct* command — not merely no wrong one — within ≤3 discovery steps (vendor patience budget), terminating in an exact command or an explicit cannot-fulfill; a discovery loop (re-reading listings without converging) is a FAIL, not a timeout. |

## Rejected from mentor feedback (with reasons)

- **New `alln menu --summary` noun.** Two-tier disclosure is adopted — on
  existing nouns. A new discovery command multiplies the surface this phase
  exists to finish.
- **Hard 2-step execution cap.** The vendor study's measured patience is 2–3
  discovery attempts; ≤3 with loop-detection keeps the teeth without
  manufacturing false failures.
- **Embedding the full catalog in the bootstrap snippet.** An installed
  static copy is a hand-authored drift surface (AE Pattern C) that goes
  stale in every host config that pasted it. The reflex is one cheap live
  call instead.
- **Keeping bare `team hello` as a readiness surface.** The readiness
  *facts* are preserved (MR-S01); the *command name* is an oracle-shaped
  attractor that dies with the router.
- **Skinny answer envelope / read-only posture in this phase.** Real, and
  the likely next bottleneck — named as a follow-on above, not smuggled into
  this scope (the reviewing mentor agrees).

## Works test

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
B=Packages/AllnighterCore/.build/release/alln

# MR-S01 — the router is gone, loudly; readiness facts survived
$B team hello --for "anything" --json; test $? -ne 0 && echo OK   # unknown command
$B route --for "anything"; test $? -ne 0 && echo OK
rg -l 'AgentIntentRouter|AgentHello' Packages/ && echo FAIL || echo OK
$B dev export-contracts --check   # passes only with major-bumped contractVersion
$B doctor --json | grep -q ready && echo OK   # bench readiness reachable without hello

# MR-S02 — two tiers: compact-complete index; selection-grade detail
$B teams --json | wc -c        # tier-1: complete AND small enough to read whole
$B team show code_growth --json | /usr/bin/python3 -c 'import json,sys; r=json.load(sys.stdin); ok=r.get("useWhen") and r.get("dontUseWhen") and r.get("example"); print("OK" if ok else "FAIL")'
$B team show code_growth --json | grep -qi 'duplicate' && echo OK   # cross-verb anti-example present
$B models --json | /usr/bin/python3 -c 'import json,sys; rows=json.load(sys.stdin)["models"]; bad=[r["id"] for r in rows if "nativeDriver" not in r]; print("FAIL:",bad) if bad else print("OK")'
$B commands --json | grep -qi recipe && echo OK   # recipes inside the completeness guarantee

# MR-S03 — exact over id ∪ display name; structured repairs
$B run "probe" --project "$PWD" --worker "Sonnet 5" --dry-run --json && echo OK
# ^ unique display name RESOLVES to model_sonnet (dry-run: proves resolution, spends nothing)
$B run "probe" --project "$PWD" --worker "Sol" --json; test $? -ne 0 && echo OK
# MUST list model_chatgpt (Codex, native) AND model_chatgpt_sol (Cursor); no default
$B run "probe" --project "$PWD" --worker "Sonet 5" --json 2>&1 | grep -q didYouMean && echo OK
# structured suggestions with ready-to-paste argv; MUST NOT dispatch

# MR-S04 — bootstrap teaches the one-call menu reflex, not a router, not a cached catalog
$B bootstrap | grep -q 'team hello' && echo FAIL || echo OK
$B bootstrap | grep -q 'commands --json' && echo OK
$B bootstrap | grep -qiE 're-read|refetch|stale' && echo OK   # staleness discipline taught

# MR-S05 — the harness rows that killed the router, now permanent
scripts/agent_eval.sh   # management/composition/bare-name/honest-misread probes;
                        # PASS = zero wrong spends AND correct command reached ≤3 steps;
                        # discovery loop = FAIL; help search output free of spending argv
```

## Inference bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Free text ↔ selection | (deleted) | "alln can guess what the user meant" | No code path maps free text → command/team/worker | grep gate: no router artifacts in Packages/ |
| Search ↔ decision | `help search` | "top search hit ⇒ run it" | Search returns menu slices, never a runnable spending argv | harness row: search output free of spending argv |
| Menu row ↔ adjacent verbs | spending rows | "the Growth row serves every growth-flavored intent" | Cross-verb anti-examples mandatory on spending rows | honest-misread probe lands on `teams duplicate` |
| Display name ↔ id | error catalog | "closest name ⇒ silently use it" | Exact-unique resolves; ambiguity lists all, defaults none; miss suggests with argv | `"Sol"` exits non-zero, two candidates, no pick |
| Listing size ↔ completeness | tier-1 listings | "complete means dump everything" | Compact-complete index; detail on demand | tier-1 output fits a tool result; tier-2 gates hold |
| Session memory ↔ catalog | bootstrap discipline | "the catalog I read yesterday still holds" | Re-read before unfamiliar spend; no cross-session cache | snippet teaches staleness rules (grep gate) |
| Snippet ↔ reflex | bootstrap | "teach one magic command" | Teach the one-call menu reflex; no oracle command exists | bootstrap free of retired router vocab |

## Done when

- MR-S01–S05 checked; works test green on a release binary from committed HEAD.
- Zero router artifacts in the codebase (grep gate) and `RetiredVocabulary`
  refuses their return.
- Tier-1 listings are complete and compact; every tier-2 record is
  selection-grade; every spending row carries cross-verb anti-examples
  (mechanical gates).
- The AE-S09 harness — including the management-verb, composition,
  bare-name, and honest-misread probes — passes with **zero wrong spending
  dispatches AND the correct command reached** within ≤3 steps on every row.
- The archived `Agent_Intent_Router.md` gains a one-line tombstone pointing
  here, so nobody re-reads it as live law.

## Routing

| Work | Read first |
| --- | --- |
| Anything "route intent" shaped | **This doc** — the answer is: don't. Laws 1–2. |
| Listing/description quality, anti-examples | MR-S02 + Laws 3–4 + AE-S15 standard |
| Identifier errors / display names / repairs | MR-S03 + Laws 5–6 + AE-S07 |
| Onboarding snippet / staleness discipline | MR-S04; archived `Agent_Onboarding.md` for history |
| Cold-agent evaluation | MR-S05 + AE-S09 harness |
| Chat posture / envelope size complaints | Follow-on phase (see "does NOT fix") — not here |
