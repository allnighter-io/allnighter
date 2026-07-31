# Menu Envelope Compression

Status: **OPEN — design recommendation (no implementation authorized)**
Owner: AllnighterCore (`MenuCatalog`, `MenuJSON`, `MenuCLI`) + tests
Updated: 2026-07-31
Related: archived [`Menu_Not_Router.md`](../archive/phases/Menu_Not_Router.md),
[`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md) (S00 prerequisite),
`MenuSelectionGradeTests`, `MenuCatalogTests`

---

## Problem

Live `alln menu --json` on the founder bench is **35,037 bytes** — over the
documented **32,768-byte** tier-1 cap. `MenuSelectionGradeTests` and
`MenuCatalogTests` only assert against the **built-in fixture**, so CI does not
protect the real surface. QABC-S00 needs to add `capacity` (~562 B compact) on
top of an already-over budget.

This doc answers: **how do we stay within budget without breaking the menu's
reason for existing?**

---

## Derived truth (do not trade away)

From archived Menu Not Router + repeated founder rulings:

1. **Tier-1 shows all.** One read must disclose every selectable team, model,
   recipe, command, and menu action — including `useWhen` / `dontUseWhen`,
   readiness, and validate/run templates.
2. **Tier-2 is hydration after choice**, not a browsing layer. Agents follow the
   shortest path; frequent tier-1 → tier-2 hops mean undiscovered capability.
3. **`truncated: false` is a product promise.** Pagination and hidden tails on
   the default menu are forbidden.
4. **The menu exists because fragmented discovery failed.** Pre-menu dogfood:
   164 KB across three commands before recipes or detail.

Any compression proposal that moves selection-grade disclosure to tier-2 is out of
scope — that is slimming, not compression.

---

## Recommendation

**Default `alln menu --json` stays plain, expanded, agent-readable JSON. No gzip
on stdout. No columnar/string-pool encoding as the default path.**

Priority order:

| Priority | Action | Rationale |
| --- | --- | --- |
| **1** | **Gate the live projection**, not just the built-in fixture | The cap is meaningless if the bench agents actually use isn't measured. |
| **2** | **Revisit the 32 KiB cap** | If "show all" is the derived truth, the budget may be the stale artifact — not the catalog. ~35 KB ≈ ~9–10K tokens once per session may be the correct price of full discoverability. |
| **3** | **Trim only provably redundant *content*** | Same semantics, fewer bytes: tighter authored copy within existing bounds (48/72), omit null/absent fields, round noisy numbers (QABC already plans this for capacity). Not tier-2 offload. |
| **4** | **Defer exotic structural encoding** | Columnar rows, string pools, and short-key tables save bytes but add a decode step agents must learn. Treat as opt-in or post-evidence, not v1. |
| **5** | **Do not gzip default stdout** | See §Gzip below. |

**Short version:** fix the test gate, decide whether the cap still serves the
product, keep the menu boring and readable. Compression tricks are a distant
fourth.

---

## Rationale

### What "world class" means here

World class for an **agent-facing CLI** is not the same as world class for a
**web API**:

| Surface | gzip? | Why |
| --- | --- | --- |
| HTTP APIs (`Content-Encoding: gzip`) | Yes — universal | Clients negotiate transparently; humans never see compressed bytes. |
| Browser / SDK downloads | Often | Decompression is built into the stack. |
| **Agent CLI stdout** | **No — not the norm** | The LLM reads raw stdout. No universal decompressor in the agent loop. |

**What agent CLIs actually do** (observed conventions, not invented):

- **Plain JSON on stdout** — `gh`, `kubectl`, `aws`, Comfy CLI `--json`, Claude
  Agent SDK `--output-format stream-json`. Data on stdout; logs on stderr.
- **NDJSON for streams** — one complete JSON object per line when output is
  event-shaped (Comfy CLI, Allnighter relay progress). Not for the menu catalog.
- **Self-describing schemas** — consistent keys, `null` for absent fields,
  `--help` / contract docs. Agents hardcode parsers; surprises break retries.
- **cli-output-spec / cli-for-agent community guidance** — stdout = data only,
  parseable, stable shape. No mention of gzip as a default agent contract.

Allnighter already matches this: `alln menu --json` emits sorted-key JSON an
agent can `json.load` with zero ceremony. That **is** the world-class baseline.

### Why gzip on stdout is the wrong default

1. **Extra costly step.** Agent must know to pipe through `gunzip`, or get binary
   gibberish and guess. Failure mode = hallucinated menu structure.
2. **Does not reduce LLM token cost** unless something decompresses *before*
   context ingestion. Wire savings ≠ context savings for chat-driven agents.
3. **Invented for this surface.** gzip is real and excellent — for transports with
   transparent clients. Applying it to agent-visible stdout is a category error.
4. **Usability regression.** A cold agent that runs `alln menu --json` and does
   not immediately see JSON has failed the front door. The teaching snippet
   says "read `alln menu --json`" — not "decompress then parse."

**Acceptable gzip use (if ever):** opt-in flag for machine pipelines that
explicitly request and decompress (`alln menu --json --gzip` → base64 or raw
bytes on stdout). Never the default. Never required for agents to operate.

### Why structural encoding is second-class (for now)

Columnar arrays, string pools, and short-key tables are **legitimate compression**
— they preserve full disclosure in one payload. But:

- Agents must read a schema header and materialize rows — extra cognitive load.
- Failure mode is subtle (wrong column index, missed `_s` lookup) not obvious
  (invalid JSON).
- No major agent CLI uses this as the default discovery surface.
- Gains are estimated ~30–40% expanded — meaningful but not transformative if
  the cap moves to ~40–48 KiB.

**Verdict:** interesting for a future `menu --json --compact` opt-in; not the
path that preserves "intuitive and easy to use."

### What about template repetition?

Per-row `runTemplate` / `validateTemplate` strings are the largest dumb
redundancy (~6 KB). Two approaches:

| Approach | Saves bytes | Agent risk |
| --- | --- | --- |
| **String pool** (concat lookup) | ~4–5 KB | Medium — mechanical but non-obvious |
| **Declared pattern** (`teamRunPattern` + id) | ~5 KB | High — agent must instantiate |
| **Keep verbatim strings** | 0 | None — copy/paste validate/run |

**Recommendation:** keep verbatim strings in default JSON. The menu's job is
zero-ambiguity dispatch. Template indirection is the kind of "clever" that
agents get wrong under pressure.

---

## Token cost (separate from byte cap)

- **32,768 is bytes, not tokens.** ~35 KB JSON ≈ **~9–10K tokens** when ingested.
- **Not every `alln` call pays this.** Teaching snippet (~1.2 KB) is the standing
  session tax. Full menu hits context **once per session** when the agent runs
  `alln menu --json` (teaching rule #1).
- Individual `alln run`, `alln help get`, etc. return small bounded envelopes.

Raising the byte cap does not change the once-per-session read discipline.

---

## Proposed near-term path (if authorized)

### MEC-S00 — Honest budget gate (no format change)

- Measure **live** `MenuCatalog.project()` (same inputs as `MenuCLI`), not only
  `BuiltInTeams.all.filter { !$0.isLabTeam }` in isolation if the live path
  differs (custom teams, bench model state).
- Fail CI when live projection exceeds cap **or** emit a founder-visible warning
  with byte breakdown by section (models / teams / commands / …).
- Document actual live size in test failure output.

### MEC-S01 — Cap decision (founder)

Choose one:

- **A. Raise cap** to a value that fits "show all" + planned growth (capacity,
  new teams/models) with headroom. Candidate: **48 KiB** (~12K tokens).
- **B. Hold 32 KiB** and authorize content trims only (tighter copy, drop
  derivable fields with explicit teaching rule — e.g. `ref` derivable from kind+id).
- **C. Hold 32 KiB** and authorize opt-in compact encoding (not default).

**Recommendation: A + S00.** The menu earned its size by replacing 164 KB of
fragmented discovery. Fighting 3 KB over cap with encoding cleverness trades
usability for aesthetics.

### MEC-S02 — QABC capacity injection

Blocked on S01. Capacity row is ~562 B compact — noise compared to the 2.2 KB
overrun. Do not let capacity be the forcing function for gzip.

---

## Open questions (founder)

1. **Is 32 KiB still the right cap?** It was justified by attention/U-shaped
   recall research (Menu Relations packet). Does that still outweigh "show all"
   at ~35 KB / ~10K tokens once per session?

2. **Live vs fixture gate.** Should CI fail on live bench state (flaky if custom
   teams vary) or on a **pinned maximal fixture** that includes worst-case
   built-ins + representative custom rows?

3. **Derivable field policy.** Are we willing to drop `ref` when `kind` + `id`
   are present, or `name` when derivable from `command:{name}`? Saves bytes;
   costs skimmability. Is that on the wrong side of usability?

4. **Opt-in compact format.** If ever built, is `alln menu --json --compact` with
   a documented expand step (`alln menu expand` or `jq` recipe) acceptable —
   or is any non-obvious encoding banned from the product surface?

5. **Teaching contract.** If cap rises, does teaching snippet change? (Probably
   no — "read menu once per session" still holds.)

6. **Bootstrap parity.** `alln bootstrap --json` does not embed the menu today
   (by design — `TeachingSnippet` is protocol only). Confirm that remains true
   after QABC (capacity in menu, not duplicated prose in teaching).

---

## Anti-recommendations (explicit)

- ❌ gzip default stdout
- ❌ tier-2 browsing for selection-grade fields
- ❌ template patterns agents must compose
- ❌ truncating teams/models/commands to fit cap
- ❌ binary MessagePack/CBOR as the only output (agents parse JSON best)
- ❌ hiding `--json` behind a format agents won't recognize on first use

---

## Success criteria (when closed)

- Live menu projection is gated in CI (or cap formally raised with documented
  rationale).
- QABC `capacity` row ships without forcing encoding tricks.
- Default `alln menu --json` remains plain JSON a cold agent can use on first
  try with no decompress/decode step.
- MR-S06 menu-not-router eval suite still passes on the default envelope.
