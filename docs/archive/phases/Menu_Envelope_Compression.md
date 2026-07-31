# Menu Envelope Compression

Status: **CLOSED / NO BUILD — archived 2026-07-31.** Founder ruling: raising
the menu byte cap is the only useful move. Compression/encoding ideas do not
justify a living phase packet. Do not resume without a fresh founder ruling.
Owner (historical): AllnighterCore (`MenuCatalog`, `MenuJSON`, `MenuCLI`)
Related: archived [`Menu_Not_Router.md`](Menu_Not_Router.md),
[`Quota_Aware_Bench_Continuity.md`](../../phases/Quota_Aware_Bench_Continuity.md)
(capacity injection — separate packet), realistic envelope gate `4ab65b23`

---

## Outcome

**Raise the cap / gate a realistic catalog. Keep default `alln menu --json` as
plain expanded JSON. Stop.**

Usability for agents is #1; size is a distant second. The menu already delivers
the 80/20 win (one read vs ~164 KB fragmented discovery). Fighting the last few
KB with encoding trades agent ease for aesthetics.

Successor: size budget lives in menu tests (`MenuSelectionGradeTests` /
`MenuCatalogTests` — realistic catalog gate, currently ~40 KiB). Capacity row
rounding/injection remains owned by QABC, not this packet.

---

## Why compression ideas were rejected

| Idea | Rejected because |
| --- | --- |
| **gzip on stdout** | HTTP best practice, wrong for agent CLI. No transparent decompress in the agent loop. Cold agents get binary gibberish and invent structure. Wire savings ≠ LLM token savings. |
| **Columnar / string-pool / short-key JSON** | Keeps disclosure but adds a decode schema. Agents fail subtly; no major agent CLI uses this as the default discovery surface. |
| **Template patterns agents must instantiate** | ~5 KB savings; high risk of wrong `run`/`validate` commands under pressure. Verbatim templates stay. |
| **Move selection fields to tier-2** | Violates derived truth “tier-1 shows all.” Agents follow the shortest path and will not browse. |
| **Drop `ref` / `displayName` / `name` for bytes** | Hurts skimmability for tiny gain. |
| **Truncate catalog rows to fit a cap** | Cap serves show-all; show-all does not serve the cap. |
| **Omit-null / micro content trims as a phase** | Too small / contested to justify a packet. Capacity rounding belongs in QABC if at all. |

---

## Historical context (do not treat as open work)

Live menu (~35 KB) exceeded the old 32 KiB built-in-fixture gate. Design spike
asked whether gzip or structural encoding could reclaim headroom without
breaking discovery. Under a usability-first lens, the answer was no — raise the
budget and keep the menu boring.
