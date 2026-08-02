# Capacity Warm Bench

Status: **OPEN — founder priority (2026-08-02). Current path is a no-go.**
Owner: AllnighterEngine (`CapacityFetch`) + AllnighterMac (strip UX) +
AllnighterCLI (`alln capacity`, menu/bootstrap injection)
Created: 2026-08-02
Updated: 2026-08-02 (adversarial review + S00a spike gate)
Supersedes: archived [`Capacity_Phase1_Recovery.md`](../archive/phases/Capacity_Phase1_Recovery.md)
(`refresh: false` default, disk-as-primary, cold PTY per request).

**Cross-doc:** Retires QABC-S00d plan-time injection **for S00–S01** (founder
2026-08-02). Runtime park/substitute from
[`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md) **unchanged**.
Revisit plan-time only after resident trusted cache exists (S02+ appendix).

Phases are ephemeral. At closeout: promote product law into help / teaching /
`Product_Vocabulary.md`; code remains SSOT; archive this packet.

---

## Adversarial review (Grok 4.5, 2026-08-02)

**Lead call: Partial** — S00 honesty direction is correct; **do not code S00b
until CWB-S00a spike is green** and paint matrix is locked below.

### Accepted from review

| Finding | Resolution |
| --- | --- |
| QABC collision | **Founder ruling:** plan-time OFF until trusted resident cache (S02+). Update QABC status note + AGENTS at S00 closeout. |
| Paint laws contradicted each other | **Paint matrix** below — single source per surface |
| CLI contract vs live code | **Cutover table** — bare becomes live; delete `--cached`/`--no-refresh` in S00 |
| Codex/Grok PTY unproven | **CWB-S00a spike** gates disk delete |
| `CapacityFetch` package unclear | Lives in **AllnighterEngine**; replaces `CapacityDisplayAcquisition` acquire path; Core keeps parsers/renderer |
| S01+ vapor in S00 packet | Moved to **Appendix: later speed** |
| Proof holes | Hardened ship gate + dogfood row |
| Menu `absent` vs `null` | **`capacity` key omitted** (not present in JSON) |

### Rejected from review (founder law stands)

| Finding | Rejection |
| --- | --- |
| Keep disk when mtime fresh | Disk is never trustworthy for capacity display — live PTY or unknown |
| Age-gated plan-time menu now | Stale numbers poison routing; dumb routing until resident cache |
| Defer six-seat PTY in favor of disk | Opposite of founder law |
| Rename tax → extend in place only | `CapacityFetch` replaces acquire; `CapacityDisplayAcquisition` becomes thin render wrapper or deleted in S00 |

---

## Spec Review Min (2026-08-02)

### Founder rulings (closed)

| Decision | Ruling |
| --- | --- |
| All six seats | **PTY only** — live probe or unknown |
| Codex/Grok disk | **Deleted** from capacity acquire — not primary, not fallback |
| Live or absent | Successful live PTY sample, or unknown — never stale % |
| **CWB-S00a before S00b** | Codex + Grok cold PTY spike must pass before disk path delete |
| **Dumb routing** | `alln menu` / `alln bootstrap` **omit** `capacity` key entirely |
| Runtime capacity | **Unchanged** — `CapacityObservation` on vendor failure |
| Plan-time capacity | **OFF** until S02+ resident cache (retires QABC-S00d temporarily) |
| Menu bar / warm pool | **Appendix** — not S00 scope |

---

## Verdict on what ships today

**No-go.** Cold PTY boot, `refresh: false` default, disk/history hydrate, and
plan-time menu injection all produce **lying %**. Capacity is the killer app
**if** we nail trust first.

---

## Paint matrix (single law per surface)

No cross-surface exceptions. **History store and disk logs never paint as live.**

| Surface | When % may appear | Default (S00) | After live success |
| --- | --- | --- | --- |
| **Mac strip launch** | Never auto | Unknown / empty | — |
| **Mac strip Refresh** | User taps Refresh | Spinner; off main actor | Show % + honest `observedAge` |
| **Mac strip re-open** | Process-local memo only | Unknown until Refresh | May show if last **live** success in **this app process** was &lt; 30 min ago |
| **`alln capacity` bare** | Every invocation | Cold live PTY all six (~5s); progress stderr | Full table or unknown rows |
| **`alln capacity --source`** | Per seat | Cold live PTY one seat | Same |
| **`alln menu` / bootstrap** | Never (S00) | `capacity` key **absent** | S02+: resident cache only (appendix) |
| **Runtime run failure** | Vendor said no | `CapacityObservation` (unchanged) | Park/substitute/wake |

**Clarifications:**
- **30-minute gate** applies only to **process-local memo** after a successful
  live fetch in the Mac app — not history file, not disk, not cross-launch.
- **CLI has no memo in S00** — every `alln capacity` is a fresh live probe.
- **"Unknown until Refresh"** on launch; memo does not survive app restart in S00.

---

## Product law

1. **Live or absent** — % only after successful live PTY in the current acquire.
2. **PTY only, all six seats** — no disk path for capacity display.
3. **Nothing on the main thread.**
4. **One output contract** — `[CapacityWindow]` → `CapacityBenchProjection` → `CapacityStripRenderer`.
5. **One acquire owner** — `CapacityFetch` (Engine).
6. **Dumb routing (S00)** — menu/bootstrap omit `capacity`; agents run
   `alln capacity` explicitly when they need quota.
7. **Runtime unchanged** — do not touch vendor park/substitute in S00.

---

## CWB-S00 — honesty cut (ship first)

### S00a — Spike gate (do first, no product ship)

Prove Codex and Grok return parseable quota via **cold PTY** before deleting disk.

| Item | Proof |
| --- | --- |
| `codex` cold PTY `/status` or `/usage` | Founder Mac dogfood + fixture capture committed |
| `grok` cold PTY | Same |
| Failure mode documented | If spike fails → seat stays **unknown** forever in S00; disk stays deleted |

**Works Test:** `scripts/swift-test.sh --filter CodexCapacityProbe` (or new
integration test with recorded fixture from live capture).

**Exit:** spike green → proceed S00b. Spike red → doc records "Codex/Grok
unknown until vendor PTY works" — still no disk fallback.

### S00b — Implementation (after S00a green)

| Piece | Responsibility |
| --- | --- |
| **`CapacityFetch`** (Engine) | `warmPool: nil`; cold `CapacityProbe` all six; process-local memo optional for Mac only; 30 min gate on memo |
| **Kill disk acquire** | Remove Codex/Grok from `CapacityAcquisition` display path |
| **Kill hydrate / `refresh:false`** | No history-as-live; bare CLI = live |
| **CLI cutover** | See table below |
| **Dumb routing** | `menuCapacity()` → `nil`; omit key from `MenuCLI`, `runBootstrap` |
| **Mac strip** | Loud Refresh; banner *"Tap Refresh for live capacity"*; off-main |
| **Teaching / help** | Update `TeachingSnippet`, `HelpTopicRegistry`, `ContractRegistry` capacity flags |

### CLI cutover (S00b)

| Today (live code) | After S00b |
| --- | --- |
| Bare `alln capacity` = `refresh: false` (instant, stale) | Bare = **live PTY all six** (~5s) |
| `--refresh` = live probe | **Removed** or alias of bare (same behavior) |
| `--cached` / `--no-refresh` | **Deleted** — usage error |
| `--source` requires `--refresh` | `--source <id>` = live one seat (no `--refresh` required) |
| `menuCapacity()` = `refresh: false` | Returns `nil`; key omitted |

```text
alln capacity                 # live PTY, six rows, ~5s, progress on stderr
alln capacity --json          # same
alln capacity --source codex  # live PTY, one seat
```

### What we delete (S00b)

- `refresh: false` as default for `alln capacity`
- `--cached` / `--no-refresh` flags
- History hydrate as live display
- Codex/Grok disk acquire for capacity
- Plan-time `menuCapacity()` injection
- `CapacityDisplayAcquisition` as acquire owner (fold into `CapacityFetch`)

**Keep:** PTY parsers, fail-closed reasons, Claude `allmodels` normalization,
runtime `CapacityObservation` path, TeachingSnippet verbatim table rule.

---

## Routing: three worlds (do not conflate)

| Layer | Source | S00 | Trust |
| --- | --- | --- | --- |
| **Display** | `alln capacity`, Mac strip | Live PTY or unknown | Opt-in / Refresh |
| **Plan-time** | menu/bootstrap | **Off** (key absent) | No fake routing |
| **Runtime** | Vendor on run failure | **On** (unchanged) | Real observation |

---

## Failure modes (S00)

| Scenario | Behavior |
| --- | --- |
| PTY succeeds but parser fails | Unknown + `parserFailed` — never disk |
| Codex/Grok PTY never shows quota (S00a fail) | Permanent unknown for that seat — still no disk |
| Parallel six cold PTYs slow / timeout | Per-seat unknown; stderr progress; exit 0 |
| Sandbox / Keychain blocks child | `spawnFailed` / unknown; doctor surfaces auth |
| Mac Refresh while prior fetch in flight | Cancel prior task; latest wins |
| App quit during probe | Probe killed; no orphan children |
| Agent expects instant bare table | Teaching: bare is ~5s live; plan accordingly |
| `coolingSources` / vendor park | Runtime only — unrelated to strip % |

---

## Implementation slices

| Slice | Scope | Ship gate | Est. |
| --- | --- | --- | --- |
| **CWB-S00a** | Codex/Grok cold PTY spike; fixtures | Dogfood + test green | 1–2d |
| **CWB-S00b** | `CapacityFetch`, disk/hydrate kill, CLI cutover, dumb routing, Mac strip | All S00b criteria below | 4–6d |

**Do not start S00b until S00a exits.** Warm pool (appendix) blocked on S00b green.

---

## S00b ship gate (must all pass)

**Acquire honesty**
- [ ] `alln capacity` never reads Codex/Grok disk (`rg` + integration test)
- [ ] Never hydrates `CapacityHistoryStore` as live display
- [ ] Failed probe → unknown row, not stale %

**CLI / menu**
- [ ] Bare `alln capacity` runs live PTY (not `refresh: false`)
- [ ] `--cached` / `--no-refresh` removed or hard error
- [ ] `alln menu --json` has **no** `capacity` key (`jq has("capacity")` → false)
- [ ] `alln bootstrap --json` same
- [ ] `MenuCapacityInjectionCLITests` updated: zero probes, no capacity key

**Mac strip**
- [ ] Launch shows unknown (no history paint)
- [ ] Refresh off main actor; no beach ball in XCTest host
- [ ] After live success: % + age; memo &lt; 30 min in-process only

**Runtime (regression)**
- [ ] `scripts/swift-test.sh --filter VendorSubstitutionPolicy`
- [ ] `scripts/swift-test.sh --filter LoopCoordinator` (capacity park paths)

**Dogfood**
- [ ] Founder runs `alln capacity` — six rows match terminal `/usage` or honest unknown
- [ ] Founder Refresh in Mac app — same numbers as CLI within one session

**Closeout docs (S00b)**
- [ ] QABC doc note: plan-time injection suspended pending resident cache
- [ ] AGENTS.md row updated
- [ ] `Product_Vocabulary.md` capacity ladder amended (disk tier retired for display)

---

## Truth owner

| Layer | Owner | Lie risk |
| --- | --- | --- |
| Acquire | `CapacityFetch` (Engine) | Disk/history as live |
| Plan-time | `menuCapacity()` → nil | Stale routing (S00 off) |
| Runtime | `CapacityObservation` | Unchanged |
| Render | `CapacityStripRenderer` (Core) | None if acquire honest |

Code SSOT: `CapacityFetch.swift`, `CapacityProbe.swift`, `AllnighterCLI.runCapacity`,
`AllnighterCLI.menuCapacity`, `CapacityStripModel.swift`.

---

## Appendix: later speed (S01+ — not S00 scope)

**Do not implement until S00b is green.** Aspirational only; details TBD after
honesty cut ships.

| Piece | Intent |
| --- | --- |
| `CapacityWarmPool` | Six warm PTYs in Mac app when menu bar resident |
| `capacity.sock` | CLI fast path when app + menu bar on |
| Menu bar + login defaults | Opt-in after cold path trusted |
| Resident cache file | Re-enable plan-time `capacity` in menu **only** from last live resident fetch &lt; 30 min |
| Settings / first-launch sheet | Menu bar explainer |

**Sequencing sketch:** S01 warm pool → S02 resident service + strip auto-refresh →
S03 socket → S04 settings → S05 help/archive Phase 1 doc.

**Estimate after S00:** ~2 weeks additional.

**Deferred complexity (intentionally out of S00):** socket auth/versioning,
pool idle teardown vs display TTL split, login-item surprise, six idle CLI RAM
budget — specify when appendix work starts.

---

## Why S00 alone simplifies

| Delete | Gain |
| --- | --- |
| Stale menu routing | Agents stop seating on fake % |
| Disk/history hydrate | One truth law: live or unknown |
| `refresh:false` default | CLI matches user expectation |
| Warm pool/socket (deferred) | Ship trust in ~1 week, not ~3 |

Warm speed is additive. **Lying is not acceptable while waiting for warm pool.**
