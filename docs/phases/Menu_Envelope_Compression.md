# Menu Envelope Compression

Status: **OPEN — design recommendation (no new encoding authorized)**
Owner: AllnighterCore (`MenuCatalog`, `MenuJSON`, `MenuCLI`) + tests
Updated: 2026-07-31
Related: archived [`Menu_Not_Router.md`](../archive/phases/Menu_Not_Router.md),
[`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md),
`MenuSelectionGradeTests`, `MenuCatalogTests`

---

## Lens

**Usability for agents is #1. Size is a distant second.** We do not want to be
stupid about size, but we do not trade easy discovery for clever encoding.

80/20: the menu already works. Most compression ideas make agents worse. Do the
few boring things; reject the rest.

---

## Derived truth (do not trade)

1. **Tier-1 shows all** — one read discloses every selectable team, model,
   recipe, command, and action (`useWhen` / `dontUseWhen`, readiness, templates).
2. **Tier-2 is hydration after choice**, not browsing. Agents satisfice.
3. **`truncated: false`** — no pagination, no hidden tails.
4. **Plain JSON on stdout** — a cold agent must see how `alln` works immediately.

---

## Incorporate (these only)

| Do | Why | Size effect |
| --- | --- | --- |
| **1. Keep default `alln menu --json` as plain, expanded JSON** | World-class agent CLIs (`gh`, `kubectl`, Claude SDK) emit readable JSON. No decode step. | — |
| **2. Gate a realistic catalog, raise the cap to match show-all** | Cap must protect the surface agents actually read. A 32 KiB aesthetic that forces encoding is the wrong trade. Realistic gate already moved toward **40 KiB** (`4ab65b23`); keep headroom for capacity + catalog growth. Candidate ceiling if needed: **48 KiB**. | Honest budget |
| **3. Omit absent optional fields; round noisy capacity numbers** | Same semantics, less noise. `blockedReason` only when present; ages/percents as ints (QABC already plans this). Zero agent learning cost. | Small, free |

That is the whole incorporate list.

---

## Do not incorporate

| Idea | Why reject |
| --- | --- |
| **gzip on stdout** | HTTP best practice, **wrong for agent CLI**. No transparent decompress in the agent loop. Binary gibberish → agent guesses. Wire savings ≠ token savings. |
| **Columnar / string-pool / short-key JSON** | Saves ~30–40% but adds a schema the agent must learn. Failure mode is subtle. |
| **Template patterns agents instantiate** | ~5 KB savings; high risk of wrong command under pressure. Keep verbatim `runTemplate` / `validateTemplate`. |
| **Move selection fields to tier-2** | Violates show-all. Agents won't browse. |
| **Drop `ref` / `displayName` / `name` for bytes** | Hurts skimmability. Not worth it under this lens. |
| **Truncate catalog rows to fit a cap** | Cap serves the product; product does not serve the cap. |

---

## Why this is enough

- Live menu ~35 KB ≈ **~9–10K tokens once per session** (teaching: read menu once).
- Capacity row ~562 B is noise next to models/teams/commands.
- Pre-menu discovery was **164 KB** across three commands. The current menu is
  already the 80/20 win. Fighting the last few KB with encoding is diminishing
  returns paid in usability.

**Short answer:** raise/honest-gate the budget, keep the menu boring, trim only
null noise. Ship capacity. Stop there.

---

## Open questions (founder)

1. **Cap number:** stay at **40 KiB** (current realistic gate) or set **48 KiB**
   with explicit headroom for capacity + new seats?
2. **Gate fixture:** pinned maximal fixture (stable CI) vs any live-bench
   projection (can flake on custom teams)? Prefer pinned maximal.
3. **Absent-field encoding:** confirm omit-null is allowed on MenuJSON (breaking
   for parsers that require every key present)? Prefer omit — agents tolerate
   missing optionals better than binary/gzip.

No other decisions needed. gzip, compact modes, and structural encoding stay
off the table unless a future founder ruling reopens them.

---

## Success

- Default `alln menu --json` remains plain JSON a cold agent can use on first try.
- Realistic envelope is gated; cap matches show-all (not the other way around).
- QABC capacity ships without encoding tricks.
- MR-S06 menu-not-router eval still passes on the default envelope.
