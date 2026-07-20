# Menu, Not Router — the caller is the brain; alln is the menu

Status: **Draft v1 (2026-07-20) — founder-ordered replacement for the retired
intent-router architecture.** Supersedes archived `Agent_Intent_Router.md`
in full. Foundation-first: no users, no migration, no compatibility shims,
no salvage. The router code is deleted, not wrapped.
Owner: AllnighterCore (`ContractRegistry`, `TeamCatalog`, `ModelCatalog`,
error catalog) + AllnighterCLI (listings, bootstrap snippet)
Updated: 2026-07-20

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
   cover commands. The gap: `teams --json` / `models --json` rows do not yet
   carry the same standard.
2. **Exactness at the point of use.** Every identifier flag resolves exactly
   or fails loudly with near-matches — including matches against *display
   names* ("Sonnet 5" → `did you mean model_sonnet (Sonnet 5 · Claude
   Code)`). Ambiguity ("Sol" exists under two drivers) is a loud choice
   presented with driver metadata, never a guess. *Mostly shipped:* AE Law 2
   + AE-S07. The gap: suggestion matching is id-shaped; display-name and
   cross-driver ambiguity data belong in the error payload.
3. **Probing is free; spending is explicit.** Free twins for every spending
   verb, so the caller can verify its choice before quota moves. *Shipped:*
   AE-S04 / AE Law 3. No new work.

That is the entire architecture. **There is no fourth component.** No intent
endpoint, no taxonomy, no scorer, no "front door" command. The front door is
`alln --help` and the bootstrap snippet pointing at the menu. What the
vendor CLIs proved is that this is sufficient — and everything beyond it is
where our failures came from.

## Laws

1. **The caller decides; alln discloses, resolves, and verifies.** No alln
   code path may map free natural-language text to a command, team, or
   worker. Free text is never an input to selection — only identifiers and
   flags are.
2. **Retrieval is honest about being retrieval.** Lexical search surfaces
   (`help search`) return candidates and documentation — never a runnable
   recommendation, never a spending argv. A search result is a menu slice,
   not a verdict.
3. **The menu is complete and selection-grade everywhere.** Every listing an
   agent selects from (`commands`, `teams`, `models`, recipes) carries the
   AE-S15 standard: situation-shaped trigger, anti-example, worked example.
   One listing lacking it is a listing that produces wrong picks.
4. **Nothing fuzzy ever spends.** Only an exact, validated identifier can
   reach a spending dispatch. (AE Law 2, restated as the boundary this
   architecture makes structural: with no router, there is no code path
   *left* that could fuzzy-match into a spend.)

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
- **No new discovery nouns.** The menu surfaces already exist; this phase
  finishes them, it does not add more.

## Slices

| Slice | Deliverable |
| --- | --- |
| **MR-S01** | **Delete the router.** Remove `AgentIntentRouter.swift`, `AgentHello.swift`, the `--for` mode, `team hello`, `route`/`resolve` aliases, their `ContractRegistry` entries, `AgentIntentRouterTests` + `AgentHelloTests`, and every teaching-surface reference (`Bootstrap.swift`, `TeachingSnippet.swift`, `RecipeCatalog.swift`, help topics). contractVersion **major** bump; regenerate contracts + lock (AE-S11 gate enforces). Add `team hello`, `route`, `resolve`, `--for` to `RetiredVocabulary` so no generated doc or test can resurrect them. |
| **MR-S02** | **Selection-grade menu everywhere.** Extend the AE-S15 standard to `teams --json` and `models --json` rows: `useWhen` (situation-shaped), `dontUseWhen`, `example` (runnable argv with real values). Models rows additionally carry `displayName`, `driver`, `nativeDriver: bool`, and posture capability — the data the caller needs to resolve "Sol under two drivers" itself. Gate: registry test asserting every listed row carries all three fields (mechanical, same shape as the AE-S15 gate). |
| **MR-S03** | **Point-of-use resolution quality.** Identifier-flag errors (`--worker`, `--team`, …) suggest near-matches over **ids AND display names**; an ambiguous display name returns all candidates with driver metadata and no default. Reuses AE-S07 edit-distance machinery; this is data-plumbing, not new architecture. Gate: `--worker "Sonnet 5"` fails with `model_sonnet` suggested; `--worker "Sol"` fails listing both driver entries, neither preselected. |
| **MR-S04** | **Bootstrap teaches the menu reflex.** Rewrite the snippet: the taught reflex becomes *read `alln commands --json` / `teams --json` / `models --json`, pick, `--dry-run`/`preflight`, run.* Delete every `team hello --for` teaching. The snippet states the completeness guarantee explicitly (the AE-S13 invariant is the selling point: "this list is exhaustive; if it isn't listed, it doesn't exist"). |
| **MR-S05** | **Cold-agent proof, out-of-distribution.** AE-S09 harness run with the probes that killed the router as permanent rows: named-model ask ("ask Sonnet 5 …"), management intent ("duplicate the growth team so I can edit seats"), composition intent ("ask several models for growth ideas"), bare model name ("Sonnet 5"). **Negative assertions required:** zero spending dispatches on management/composition/bare probes; zero invented flags. Positive: all agents reach the correct command via the menu alone, ≤3 discovery steps (the vendor-study patience budget). |

## Works test

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
B=Packages/AllnighterCore/.build/release/alln

# MR-S01 — the router is gone, loudly
$B team hello --for "anything" --json; test $? -ne 0 && echo OK   # unknown command
$B route --for "anything"; test $? -ne 0 && echo OK
rg -l 'AgentIntentRouter|AgentHello' Packages/ && echo FAIL || echo OK
$B dev export-contracts --check   # passes only with major-bumped contractVersion

# MR-S02 — every selectable row is selection-grade
$B teams --json  | /usr/bin/python3 -c 'import json,sys; rows=json.load(sys.stdin)["teams"]; bad=[r["id"] for r in rows if not (r.get("useWhen") and r.get("dontUseWhen") and r.get("example"))]; print("FAIL:",bad) if bad else print("OK")'
$B models --json | /usr/bin/python3 -c 'import json,sys; rows=json.load(sys.stdin)["models"]; bad=[r["id"] for r in rows if "nativeDriver" not in r]; print("FAIL:",bad) if bad else print("OK")'

# MR-S03 — point-of-use exactness with display-name suggestions
$B run "probe" --project "$PWD" --worker "Sonnet 5" --json; test $? -ne 0 && echo OK
# stderr/json MUST suggest model_sonnet; MUST NOT dispatch
$B run "probe" --project "$PWD" --worker "Sol" --json; test $? -ne 0 && echo OK
# MUST list model_chatgpt (Codex, native) AND model_chatgpt_sol (Cursor); no default

# MR-S04 — bootstrap teaches the menu, not a router
$B bootstrap | grep -q 'team hello' && echo FAIL || echo OK
$B bootstrap | grep -q 'commands --json' && echo OK

# MR-S05 — the harness rows that killed the router, now permanent
scripts/agent_eval.sh   # includes management/composition/bare-name probes;
                        # PASS requires zero spending dispatches on them
```

## Inference bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Free text ↔ selection | (deleted) | "alln can guess what the user meant" | No code path maps free text → command/team/worker | grep gate: no router artifacts in Packages/ |
| Search ↔ decision | `help search` | "top search hit ⇒ run it" | Search returns candidates/docs, never a runnable spending argv | search output contains no `team start`/`run` recommendation |
| Display name ↔ id | error catalog | "closest name ⇒ silently use it" | Suggest, never substitute; ambiguity lists all, defaults none | `--worker "Sol"` exits non-zero, two candidates, no pick |
| Listing row ↔ pickability | `teams`/`models` | "a listed row is enough to pick correctly" | Every row carries useWhen/dontUseWhen/example | registry gate over all listings |
| Snippet ↔ reflex | bootstrap | "teach one magic command" | Teach the menu + preflight reflex; no oracle command exists | bootstrap free of retired router vocab |

## Done when

- MR-S01–S05 checked; works test green on a release binary from committed HEAD.
- Zero router artifacts in the codebase (grep gate) and `RetiredVocabulary`
  refuses their return.
- Every selectable listing row is selection-grade (mechanical gate).
- The AE-S09 harness — including the management-verb, composition, and
  bare-name probes that broke the router — passes with **zero wrong spending
  dispatches** and all agents completing via the menu alone.
- The archived `Agent_Intent_Router.md` gains a one-line tombstone pointing
  here, so nobody re-reads it as live law.

## Routing

| Work | Read first |
| --- | --- |
| Anything "route intent" shaped | **This doc** — the answer is: don't. Laws 1–2. |
| Listing/description quality | MR-S02 + AE-S15 standard |
| Identifier errors / suggestions | MR-S03 + AE Law 2 / AE-S07 |
| Onboarding snippet | MR-S04; archived `Agent_Onboarding.md` for history |
| Cold-agent evaluation | MR-S05 + AE-S09 harness |
