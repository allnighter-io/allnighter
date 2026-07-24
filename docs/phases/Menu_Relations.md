# Menu Relations — structure the caller cannot infer

Status: **DRAFT — NOT AUTHORIZED. Queued behind `CODE_RED_Core_Infrastructure_Repair.md`.**
Founder sequencing (2026-07-24): Code Red delivers first; this doc is the next
one taken up, ahead of `Contradiction_Pass.md`.
Owner: AllnighterCore (`MenuCatalog`, `MenuJSON`, `ContractRegistry`,
`RetiredVocabulary`) + AllnighterCLI (`menu`)
Updated: 2026-07-24

Extends archived [`Menu_Not_Router.md`](../archive/phases/Menu_Not_Router.md)
(MR-S01–S06, Complete 2026-07-20). That phase is **not reopened**: every law
there stands, especially Law 1 (the caller chooses) and the anti-goal list. This
doc adds *disclosed structure* to rows the menu already emits. It never adds a
selector, a ranking, or a recommendation.

> **"Laws" in this doc are working hypotheses.** They are revisable by founder
> ruling only — never by an implementing agent mid-slice.

---

## Founder intent

Relationships between menu rows are currently disclosed as English prose inside
`useWhen` / `dontUseWhen`, or not disclosed at all. A calling agent must re-infer
them from that prose on every session. Make the relationships that already exist
in the product **explicit, typed, and machine-checkable** — without spending
bytes the menu does not have, and without letting the intent router grow back.

## Product value

A cold agent that composes correctly on the first attempt: picks the right depth
tier, does not execute a renamed id it read in a stale transcript, and chains
Spec Review → execution without a second discovery call. Selection is already
solved (MR-S06 matrix). **Composition is not measured at all.**

## Non-goals

- No `follows`, `recommends`, `similarTo`, `bestFor`, ranking, or confidence
  edge. Those are the intent router wearing a graph costume and violate archived
  MNR Law 1 + anti-goal "No default recommendation, confidence score, or 'best'
  row."
- No knowledge graph, graph database, entity extraction, embedding index, or
  retrieval layer. `alln` does not do document retrieval and will not start.
- No second discovery call for common work. MNR Law 4 ("Common work is one read
  away") is a hard constraint on this design, not a nice-to-have.
- No reopening of the run grammar, the `menu show` hydrate tier, or effects.

---

## Current state (measured 2026-07-24)

Against the pinned MR-S06 harness capture
(`.build/agent-eval/menu-not-router/menu.json`, binary 2026-07-20):

| Segment | Bytes | Rows |
| --- | ---: | ---: |
| `teams` | 11,069 | 25 |
| `models` | 9,296 | 22 |
| `commands` | 7,723 | 103 |
| `recipes` | 1,843 | 7 |
| `actions` | 1,152 | 4 |
| `effectProfiles` | 814 | 6 |
| everything else | 495 | — |
| **total** | **32,418** | **~150 selectable rows** |

**Budget: 32,768 bytes. Headroom: 350 bytes (1.1%).**

Two facts follow, and the second is the whole design constraint:

1. **The byte gate is already nearly breached, independent of this work.** Mean
   team row is 442 bytes. *One more built-in team breaks
   `MenuCatalogTests` / `verify_menu_contract.py`.* This is a live regression
   risk on the current board and should be treated as such whether or not
   relations are ever built.
2. **Relations must be net byte-neutral or negative.** There is no room to add.
   Anything this doc proposes must pay for itself out of prose it deletes. If it
   cannot, it does not ship — MNR's own rule applies: *"If the schema cannot meet
   the budget, simplify the schema — do not truncate truth."*

Prose currently spends 4,773 bytes on `useWhen` (2,273) + `dontUseWhen` (2,500).

**The displacement opportunity is already visible in the data.** Four families
ship all three depth tiers — `code_bug_hunt`, `code_growth`, `code_spec_review`,
`design_design` — so **12 of 25 team rows are tier siblings**, each carrying its
own independently authored prose restating the same family job and the same
depth relationship. `Team_Depth_Naming.md` §The rule 2 says users should memorize
"families + 1 things, not families × depths." The menu currently makes an agent
read families × depths.

---

## Evidence

Directional support from published work. **None of it tested a bounded
single-payload menu like `alln`'s**, so it predicts a benefit rather than
confirming one — which is why MRL-S01 is a measurement slice with a kill
criterion, not a build slice.

| Finding | Source | Bearing on this doc |
| --- | --- | --- |
| Tool-selection accuracy degrades as the catalogue grows; degradation is reported well before hard tool-count ceilings, and API/tool hallucination rises with catalogue size | [Gorilla (NeurIPS 2024)](https://arxiv.org/abs/2305.15334) + [tool-selection survey](https://machinelearningmastery.com/the-complete-guide-to-tool-selection-in-ai-agents/) | `alln` discloses ~150 selectable rows in one payload — past where the literature reports degradation. Disclosure quality is load-bearing, not cosmetic. |
| Producer–consumer dependencies **inferred from the API specification** are what let a tool generate valid request sequences; requests are only attempted once their dependent resources exist | [RESTler, ICSE 2019 (Microsoft)](https://patricegodefroid.github.io/public_psfiles/icse2019.pdf) | Exactly the `consumes` / `produces` proposal, in a non-LLM setting. Sequence validity comes from declared shapes, not from reading descriptions. |
| Semantic similarity is adequate for tool *selection* but "systematically harmful for ordering" where inter-tool dependencies govern execution order; making precedence explicit as a graph prior fixes it | [SkillGraph](https://arxiv.org/pdf/2604.19793), [NaviAgent](https://arxiv.org/html/2506.19500) | The sharpest result for this doc: **keep prose for selection, add edges for composition.** That is the exact split proposed below. |
| Representing tools/agents as graph nodes with edges improves retrieval: +14.9% Recall@5, +14.6% nDCG@5 over prior retrievers on LiveMCPBench | [Agent-as-a-Graph](https://arxiv.org/abs/2511.18194) | Verified against the abstract — the widely circulated numbers are real. Note the gain is on *retrieval over large catalogues*, a regime `alln` deliberately avoids. |
| Model attention over long inputs is U-shaped; material in the middle is used significantly worse than material at the edges | [Lost in the Middle (TACL 2024)](https://aclanthology.org/2024.tacl-1.9/) | Independent justification for the 32 KiB bound *and* for preferring compact structure over mid-payload prose, which is where relationship sentences currently sit. |

**Counter-evidence, stated plainly:** the MR-S06 cold-agent matrix passes at
100% on its permanent rows today. The literature's failure mode has not been
observed in `alln`. That is the case for measuring before building.

---

## The proposal

### 1. Prose selects; edges compose

| Job | Owner | Stays / changes |
| --- | --- | --- |
| "Is this the right thing for what the user asked?" | `useWhen` / `dontUseWhen` prose | Unchanged in kind, shortened in fact |
| "What shape does it take, what does it emit, is this id still real, which depth am I on?" | typed relations | New |

### 2. One side table, not nested fields

Follows the existing `effectProfiles` precedent — a deduplicated top-level
record referenced by compact rows, already proven inside the budget. Relations
are grouped by type and carry canonical ids only:

```json
"relations": {
  "family": { "code_spec_review": ["code_spec_review_min", "code_spec_review", "code_spec_review_max"] },
  "supersedes": { "code_bug_hunt_lite": "code_bug_hunt" },
  "produces": { "code_spec_review": "spec.hardened", "code_bug_hunt": "findings" },
  "consumes": { "code_spec_review": "prompt|spec", "design_design": "prompt" }
}
```

No prose, no duplication of row payloads, no per-row repetition.

### 3. The four candidate edge types, ranked by value ÷ bytes

| Edge | What it encodes | Why it earns bytes | Verdict |
| --- | --- | --- | --- |
| **`family`** | Min / Default / Max siblings of one job | 12 of 25 team rows are siblings restating the family relationship in prose. One grouping edge lets all 12 drop that sentence. Encodes `Team_Depth_Naming.md` mechanically, including "bare is the default send, never Min." **Most likely to be net byte-negative.** | v1 |
| **`supersedes`** | retired id → current id | `RetiredVocabulary` already holds this truth; the menu does not disclose it. Bootstrap rule 4 ("never trust a pasted catalog") is advisory prose; this makes it repairable. Tiny — a handful of pairs. | v1 |
| **`consumes` / `produces`** | input shape + output class | Encodes existing laws that are currently prose or nowhere: Design runs from a *prompt*, Spec Review emits a *hardened spec + proof plan*. Enables chaining without a hydrate call. | v1 if the budget survives `family` + `supersedes`; else v2 |
| **`requires`** | preconditions (healthy CLI, write lock, project) | Largely already covered by `active` + `blockedReason`. Additive with unclear marginal value. | **Deferred** — do not build until v1 is measured |

### 4. Explicitly rejected

`follows`, `recommends`, `similarTo`, `bestFor`, `confidence`, any weight or
rank. Each one reintroduces the intent router. `follows` was considered and cut:
"what usually comes next" is a recommendation with extra steps.

---

## Laws (working hypotheses — founder-revisable only)

1. **Edges disclose; they never select.** No relation type may express
   preference, ranking, popularity, or suitability. Archived MNR Law 1 governs.
2. **Net-neutral or it does not ship.** Every relation slice must land the menu
   at or below its pre-slice byte count. Adding structure while prose stays
   untouched is a failed slice, not a partial one.
3. **Edges reference canonical ids only.** No display names, no free text, no
   prose inside `relations`. Consistent with MNR Law 5.
4. **One read still answers common work.** If any relation type creates a need
   to call `menu show` for a common path, that type is wrong (MNR Law 4).
5. **Edges are projections, never hand-authored.** `family` derives from the id
   convention + `TeamPreset`; `supersedes` derives from `RetiredVocabulary`;
   `consumes`/`produces` derive from preset shape. A hand-maintained edge list
   beside the catalog is forbidden (MNR Law 2).

---

## Slices

| Slice | Deliverable |
| --- | --- |
| **MRL-S00 — Reclaim headroom (independent of relations)** | The 350-byte headroom is a live gate risk regardless of this phase. Measure the live menu on current HEAD, find the prose duplication across the 12 tier-sibling rows, and land byte reduction with no schema change. Exit: ≥2 KiB headroom, all MNR gates green. **This slice is worth doing even if the rest of the doc is killed.** |
| **MRL-S01 — Measure the composition gap (kill gate)** | Extend the cold-agent harness with composition-shaped asks the current matrix does not cover: (a) "run the deeper version of the spec review" → correct `_max` id; (b) an ask carrying a **retired** id from a stale transcript; (c) "harden this spec then have someone build it" → correct two-step chain; (d) "design me a settings screen" given only a screenshot → correct refusal/clarify per the prompt-not-screenshot law. Run against the pinned binary with the *current* menu. **Kill criterion: if a cold agent already passes these at the MR-S06 bar, stop here and archive the doc.** Publish the failure rate either way. |
| **MRL-S02 — `family` + `supersedes`** | Add the `relations` side table with the two v1 edge types, projected from `TeamPreset` + `RetiredVocabulary`. Delete the prose each edge replaces in the same commit. Add gates: byte budget, edges-resolve-to-live-ids, no-orphan-edges, deterministic ordering, and a forbidden-relation-type test naming `follows`/`recommends`/`similarTo`. |
| **MRL-S03 — `consumes` / `produces` (budget permitting)** | Only if MRL-S02 left headroom and MRL-S01 showed a chaining failure. Same gates. |
| **MRL-S04 — Re-measure** | Re-run the MRL-S01 matrix. Report the delta honestly, including "no change." A null result archives the phase; it does not get a retry with a friendlier matrix. |

## Works Test

```bash
swift build -c release --package-path Packages/AllnighterCore --product alln
B=Packages/AllnighterCore/.build/release/alln

$B menu --json > /tmp/alln-menu.json
/usr/bin/python3 scripts/verify_menu_contract.py /tmp/alln-menu.json \
  --max-built-in-bytes 32768 --require-complete --require-unique-refs
# every relation endpoint resolves to a live canonical id; no orphans
/usr/bin/python3 scripts/verify_menu_contract.py /tmp/alln-menu.json --require-relations-resolve
# forbidden relation types never appear
/usr/bin/python3 -c "import json,sys; r=json.load(open('/tmp/alln-menu.json')).get('relations',{}); \
  bad=set(r) & {'follows','recommends','similarTo','bestFor','confidence'}; sys.exit(bool(bad) and print(bad))"

$B dev export-contracts --check
scripts/agent_eval.sh --suite menu-not-router --binary "$B"
scripts/agent_eval.sh --suite menu-relations --binary "$B"   # MRL-S01 matrix
scripts/check.sh
```

**Proof note:** `scripts/menu_not_router_eval.py` is a mechanical pinned-binary
matrix, not a live LLM eval. The MRL-S01 composition matrix **requires live
cold-agent runs** to mean anything. Dogfood it through a cross-CLI `alln` run;
a mechanical stand-in would prove nothing about first-attempt composition.

## Done when

- Menu headroom is ≥2 KiB and the byte gate is no longer one team from red.
- The composition matrix exists, is permanent, and its pre/post numbers are
  published in this doc — including a null result.
- Every shipped edge type is a projection with a resolve-and-orphan gate.
- No relation type expresses preference; the forbidden-type gate is red on
  reintroduction.

## Open questions

1. **Is `family` derivable, or does it need a `TeamPreset` field?** The
   `<family>_min` / `<family>` / `<family>_max` id convention makes it derivable
   today, but `Team_Depth_Naming.md` §7 warns that unique names remain for
   genuinely different jobs — a convention-only derivation would silently
   mis-group a family that breaks the pattern. Recommendation: derive, and add a
   gate that fails when a `_min`/`_max` id has no bare sibling.
2. **Do `consumes`/`produces` values need a closed vocabulary?** An open string
   becomes prose by the third team. Recommendation: closed enum, extended by
   founder ruling.
3. **Does `supersedes` belong in the menu or in the error path?** Unknown-id
   errors already return same-kind candidates (MR-S04). Disclosing supersessions
   up front prevents the failed call; disclosing them only on failure is cheaper.
   Recommendation: error path first (zero menu bytes), promote to the menu only
   if MRL-S01 shows agents burning a call on retired ids.

## Routing

| Work | Read first |
| --- | --- |
| Menu schema, discovery, selection law, router bans | archived `Menu_Not_Router.md` (code SSOT: `MenuCatalog`) |
| Depth tiers, family naming, escalation law | `Team_Depth_Naming.md` |
| Retired ids and vocabulary gates | archived `CLI_Agent_Surface_Fidelity.md` (code SSOT: `RetiredVocabulary`) |
| Panel disagreement, contradiction handling | `Contradiction_Pass.md` |
