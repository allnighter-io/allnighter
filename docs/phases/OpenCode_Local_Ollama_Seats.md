# OpenCode Local (Ollama) Seats

Status: **OCL-S00 pipe PASS (partial honesty) — code slices still unauthorized.**
  Founder rulings locked (§0.1). Spec Review Min: Ready for OCL-S00 only
  (`FE9F2530…`). Live dogfood recorded §0.3.
Revised: 2026-08-07 (v4 — OCL-S00 on MacBook Air M4 32GB with qwen2.5:0.5b)
Owner: unassigned (AllnighterCore catalog + model discovery; AgentOS only if
local turn timing needs to change in the OpenCode driver)
Created: 2026-08-07
Origin: Founder dogfood — Ollama 0.32.x ships `ollama launch opencode` and
documents OpenCode → `http://localhost:11434/v1` (OpenAI-compatible). Local
models are becoming real implementation labor. ALLN seats them through the
**same `opencode` driver** as Go, with local provenance and local honesty.
**Dogfood split:** prove the pipe on a Mac mini / Air (any Apple Silicon); sell
the upside to Mac Studio users. Same software.

Companion packets:
[`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md) (same driver, different
seat economics — binding structural analogy),
[`Scarcity_Aware_Routing.md`](Scarcity_Aware_Routing.md) (abundant vs scarce;
read its §3 rejected list before proposing any auto-routing),
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) (a signal answers
only for the source that produced it),
[`OpenCode_Long_Run_Continuity.md`](OpenCode_Long_Run_Continuity.md) /
[`OpenCode_Completion_Truth_Followup.md`](OpenCode_Completion_Truth_Followup.md)
(OpenCode completion honesty — local models stress it harder, see §12).

Upstream docs (external, not SSOT):
[Ollama](https://docs.ollama.com/),
[OpenCode integration](https://docs.ollama.com/integrations/opencode),
[OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility),
[Context length](https://docs.ollama.com/context-length),
[Tool calling](https://docs.ollama.com/capabilities/tool-calling).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## 0. Review verdict

**Pipe proven on Air. Not Ready for Implementation slices** until Spec Review
fixes land and a coding-class gated repair passes (§11 B optional; honesty gaps
below are mandatory for S01+).

### 0.1 Founder rulings (2026-08-07) — binding

1. **Readiness, not capacity strip.** Local availability is **not**
   `benchSourceOrder` / subscription capacity. `Product_Vocabulary.md` capacity
   stays vendor-printed quota. Local surface: `alln models` / `doctor`.
2. **v1 readiness states are three words only:**
   `Unavailable` | `Idle` | `Busy`.
   No VRAM %, no fake 5h/weekly meters, no context gauges in v1 UI. Prefer
   observed `ollama ps` / `/api/ps` (loaded ⇒ Busy; reachable + nothing loaded ⇒
   Idle; down / no usable model ⇒ Unavailable). Unobserved ⇒ Unavailable, never
   a guessed Busy. (**Busy = resident in memory**, not “currently inferring” —
   Spec Review: `keep_alive` keeps models loaded after idle.)
3. **Signal id:** `ollama_local` (attribution only — not a strip seat).
4. **Dogfood hardware split:** Prove the **pipe** on **any Apple Silicon on the
   desk** (Air / mini). Studio is ICP/sales, not a build gate.
5. **OCL-S00 on current hardware** — done (§0.3).
6. **Ollama Cloud stays out.** Remote `OLLAMA_HOST` / LAN Studio farm stay out.

### 0.2 Spec Review Min (2026-08-07) — `FE9F2530-7E96-4E16-AC0F-296F4CA26D86`

Verdict: **Ready for OCL-S00 only.** Leans locked for implementers:

- ≥64k: hard block on **automatic** offers; **warn-and-allow** on explicit
  `--model` (unblocks served-context deadlock).
- Discovery: list all / enable none; build S03 only after one real gated local
  repair.
- No raw `ollama` driver — OpenCode only for this packet’s lifetime.

### 0.3 OCL-S00 live result (2026-08-07, MacBook Air M4 32GB)

Host: `Mac16,13` · 32 GB · ollama 0.32.6 · opencode 1.18.15.

| Step | Result |
| --- | --- |
| Backup + merge `ollama` into `enabled_providers` (keep `opencode-go`) | **PASS** — backup `~/.config/opencode/opencode.json.bak-ocl-s00-20260807-204036` |
| `opencode models` lists `ollama/qwen2.5:0.5b` + Go seats | **PASS** |
| `alln models add` → `custom_opencode_ollama_qwen25_05b_local_7496` | **PASS** |
| `alln models verify` (needs healthy `opencode serve` on :4096) | **PASS** when serve fresh; **FAIL** with stale/missing serve (`Session not found` / Unexpected server error) |
| `alln models enable` | **PASS** |
| `alln run --model … --no-commit` mutating TARGET.md | **PASS (pipe)** — run `6B012D73-4223-4A52-BBE7-E4E0E4B77AE0` · `sourceId=opencode` · wall ~4s · write tool activity observed |
| Real file edit | **PASS** — `docs/qa/ocl-s00-dogfood/TARGET.md` became `STATUS: AFTER` (plus model-added co-author line) |
| Outcome honesty | **FAIL** — `completedWithoutChanges: true` / `repoDelta.changed: false` despite write (untracked path + weak model narrative claiming `result.txt`) |
| Served context (`ollama ps`) | **4096** — below 64k agent guidance; explicit pin still ran (matches Spec Review warn-and-allow lean) |
| Stall / 120s quiet | **N/A** — tiny model finished in seconds |
| Go seats after merge | **PASS** — `enabled_providers` still includes `opencode-go`; Go model ids still listed |

**Also observed (1.5b coder earlier):** run `AC6BD0CB…` returned tool JSON as text without editing TARGET — same pipe, weaker tool follow-through. Prefer 0.5b run as the recorded S00 mutating proof (file actually changed).

**OCL-S00 verdict:** **Pipe works on Air.** Do not authorize S01–S05 until (1) Spec Review doc fixes land, (2) outcome/repoDelta honesty for local writes is understood, (3) optionally one coding-class gated repair on a stronger local model.

### 0.4 Still blocking Ready-for-Implementation

1. Spec Review packet fixes (context gate, Busy definition, §7.1 vocabulary, etc.)
2. Outcome lie: completedWithoutChanges with a real write
3. OpenCode CT unfinished — local amplifies false-done
4. No coding-class gated repair yet (0.5b is pipe-only)

What v4 changed: §0.3 live Air dogfood; status flipped from “no OCL-S00” to pipe PASS.

---

## 1. One claim

With Ollama running and one tool-capable local model pulled, the user can put
that model on the bench as an **OpenCode** seat and pin it with `--model`, the
same way they pin a Go seat — no new agent harness, no new driver, and no claim
that Allnighter runs models.

Trusted workflow slice (target):

```text
ollama serve + tool-capable model pulled
  → Allnighter detects Ollama and lists local models (tools? context?)
  → the model appears on the bench as an opencode seat, provenance: local
  → alln run "…" --model <local_model_id> --json
  → OpenCode agent body (tools / FS / shell) + Ollama inference
  → honest completion or honest failure; readiness is Unavailable | Idle | Busy,
    never a subscription meter
```

### Dogfood vs sell (founder)

```text
Mac mini (or any AS)  → prove the pipe (integration Works Test)
Mac Studio owners     → who feel the upside (larger local models, abundant labor)
```

Same binary. Different wallet and model class. Integration dogfood must not
depend on Studio RAM.

---

## 2. The bridge — why this is Allnighter's job

### 2.1 Three planes, three owners

```text
Ollama      = inference. Weights, VRAM, context, load/unload. Nothing else.
OpenCode    = the agent body. Tools, filesystem, shell, session, completion.
Allnighter  = the bench. Detect · seat · provenance · honesty · write lock.
```

Neither of the other two layers wants Allnighter's job. Ollama's own posture is
to *launch and configure existing agents*
([integrations](https://docs.ollama.com/integrations/index.md)) — it points at
OpenCode rather than becoming it. OpenCode runs one agent well and has no
opinion about the six other CLIs the user pays for. The gap between "I can run a
model" and "this model showed up to work alongside Claude, Codex, and Grok under
one write lock, with one run contract and one honest failure story" is the
product.

What Allnighter adds that neither layer does:

| Layer | Contribution |
| --- | --- |
| Detect | Ollama present, reachable, which models, which are tool-capable |
| Seat | One `model_id` on the bench next to paid seats, same `--model` pin |
| Provenance | This answer came from *your machine*, not a vendor |
| Honesty | Local scarcity is hardware, and is never dressed as a quota |
| Safety | One mutating worker per root; the local seat is not exempt |
| Contract | Same `TeamRunJSON`, same `alln show`, same artifacts |

### 2.2 The Mac Studio wedge

The ICP is a Mac with large unified memory (128 GB and up) whose owner already
pays for two to four coding CLIs. Today that machine's local models are a second
workflow: a different terminal, a different mental model, a different place to
look for the result. The wedge is that they stop being a second workflow.

"Real implementation" means the local seat does bounded mutating work — the
repair-shaped slices `Scarcity_Aware_Routing.md` §5a found delegate best (9/9
clean, including from the two weakest seats on the bench) — not just
summarization and review. The historical local-worker note
(`docs/archive/2026-06-13-allnighter-pivot/strategy/Allnighter-Local-AI-Worker-Opportunity.md`)
argued for starting read-only and earning trust; it was written before the
OpenCode agent body existed and before six delegated build slices landed. Its
durable half is the market read — *the local runtime market is crowded, the
"local model as scheduled worker" market is not* — and that half still holds.
Its "night shift" framing does not: dogfood reality is all-day Teams and Loop.

The economics are the point. Claude hours are scarce and walled; a local seat is
**abundant** — no per-token cost, no reset clock, no vendor to ask. That is the
same asymmetry `Scarcity_Aware_Routing.md` §1 is built on, with the abundant side
made stronger: an abundant seat that is also private and offline-capable. Note
what that packet forbids, though — abundance is a **disclosure**, never a
standing "prefer local" rule and never a sensor that overrides a named seat.

Mission fit: *you already pay for the team* extends cleanly to hardware you
already bought. The Studio is a paid seat that never shows up to work.

### 2.3 What this is not

| Not | Why |
| --- | --- |
| An Ollama UI / model manager | LM Studio and Open WebUI own that. ALLN never pulls, quantizes, or tunes. |
| A LAN Studio farm | [`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md) is shelved. One Mac, local inference. No multi-host mutators. |
| A raw `ollama run` driver | A completion CLI is not an agent body. See §3. |
| A local model provider | ALLN does not host, serve, or bill inference. Ollama does. |
| An overnight pitch | All-day Teams + Loop. The name is brand only. |

---

## 3. Why OpenCode and not a new driver

| Path | Verdict |
| --- | --- |
| New `DriverManifest` for `ollama run` | **Wrong for mutating Code / Loop.** A completion CLI with no tools, no FS, no session. Judgment-only fallback at most, and not proposed. |
| Allnighter-owned tool loop over Ollama HTTP | **Out of scope.** Reinvents OpenCode, and inherits every completion-truth defect CT-01…CT-14 already paid for. |
| OpenCode provider → `http://localhost:11434/v1` | **v1 path.** Same driver `opencode`; local model ids as seats. |
| Runs driven via interactive `ollama launch opencode` | **Non-goal.** Human onboarding UX. Product runs stay under `RunService` + the write lock with config-backed provider wiring. |

---

## 4. Non-goals (ironclad)

- **Ollama Cloud** models, accounts, or cloud base URLs as product seats. Cloud
  users already have Claude, Codex, Cursor, and OpenCode Go. This packet is
  local provenance only — do not meter, catalog, or market Cloud seats here.
- A standalone `ollama` coding driver for mutating work.
- `ollama launch …` as the Allnighter run path.
- **Rewriting the user's `~/.config/opencode/opencode.json`.** Additive only,
  behind an explicit setup verb, reversible. See §12 for the specific way this
  goes wrong on the dogfood host today.
- LAN / multi-host execution (shelved). A remote `OLLAMA_HOST` as an
  *inference URL only* is a separate future packet, not this one.
- Auto-routing local vs cloud. `Scarcity_Aware_Routing.md` is brainstorm and its
  §3 rejects standing vendor-preference rules outright.
- Any capacity percentage, park-for-limit, or substitution decision derived from
  Ollama state.
- Claude-Code-via-Ollama as a v1 seat — different `sourceId` and auth story.

---

## 5. Current state (verified 2026-08-07 — binding over v1 assumptions)

### 5.1 Live code

| Fact | Where | Why it matters |
| --- | --- | --- |
| Driver `opencode` invokes `opencode run --attach http://127.0.0.1:4096 -m {{model}}`, `maxConcurrentSpawns: 1`, `timeoutSeconds: 1800` | AgentOS `Catalog/catalog.json` | A local seat is a model **label**, not a new driver. The concurrency ceiling already exists. |
| OpenCode models are ids like `model_opencode_deepseek_v4_pro` with label `opencode-go/deepseek-v4-pro` | AgentOS `catalog.json` + `catalog_overlay.json` (ranks 92→55) | **The provider is inside the label.** Today every OpenCode seat is a *Go* seat. A local seat is a different id with an `ollama/<tag>` label — not the same seat relabelled. |
| `alln models add --driver <id> --name <n> --model-label <label>` then `alln models verify <id>` | `ModelsCLI.swift`, `ModelCatalog.createCustom`, `verifyModelSmoke` | A local seat can be created and smoke-verified **today, with no code**. This is OCL-S00. |
| `ModelOrigin.discovered` exists; `ModelDiscoveryRegistry.provider(for:)` returns `nil` for every driver | `ModelCatalogTypes.swift`, `ModelDiscoveryProvider.swift` | The discovery seam is built and unused. A local-model provider would be its **first** implementation — extend the seam, do not invent a parallel one. |
| Capacity is 8 seats: 6 PTY + 2 dashboard-scrape (`opencode_go`, `bailian_token_plan`), authored lists, not aliases | `CapacityAcquisition.swift` | The v1 packet's "seventh seat" framing is stale. More importantly, both existing tiers meter **paid subscriptions**. |
| `CapacityAcquisitionTier` = onDisk / streamPiggyback / tuiProbe / failureClassification / dashboardScrape | `CapacityWindow.swift` | There is no tier for "ask the local runtime." Adding one is a product decision (§7.5), not a mechanical extension. |

### 5.2 This host (honest, and it is not the ICP)

```text
Mac16,13 · 32 GB unified memory · macOS 15.6.1
ollama 0.32.6 · /api/ps empty · /api/tags → one model: qwen2.5:0.5b
  (capabilities: ["completion","tools"], context_length 32768)
opencode 1.18.15 · ~/.config/opencode/opencode.json:
  { "enabled_providers": ["opencode-go"], "plugin": ["@slkiser/opencode-quota"] }
```

Three consequences, all load-bearing:

1. **32 GB puts Ollama's default context at 32k** (its bands: <24 GiB → 4k,
   24–48 GiB → 32k, ≥48 GiB → 256k), below the 64k its docs require for coding
   agents. The gate in §7.4 would refuse a Code seat on this machine by default,
   which is the correct behavior and also the reason the wedge is a Studio wedge.
2. **The only pulled model is 0.5B.** It is enough to prove *plumbing* — it does
   advertise `tools` — and nowhere near enough to prove *capability*. Keep those
   two proofs separate and never let the first be reported as the second.
3. **`enabled_providers` is an allowlist containing only `opencode-go`.** A
   setup verb that writes rather than merges would silently remove all seven Go
   seats. See §12.

---

## 6. Structural parity with Go seats

### 6.1 Driver ≠ capacity source (the binding analogy)

| Layer | OpenCode Go | OpenCode Local (Ollama) |
| --- | --- | --- |
| **Driver id** | `opencode` | `opencode` (identical) |
| **Model plane** | Go remote models, label `opencode-go/…` | Local models, label `ollama/…` |
| **Seat identity** | Authored catalog ids + authored rank | Discovered ids + **local** provenance; rank authored only for known models |
| **Scarcity** | Dollar caps per rolling / weekly / monthly window | VRAM, load state, effective context, machine contention |
| **Signal source** | `opencode.ai/workspace/{id}/go` (HTTP scrape) | `127.0.0.1:11434` (`/api/tags`, `/api/ps`) |
| **Meter id** | `opencode_go` (capacity bench seat) | `ollama_local` — **recommended**, and see §6.2 on where it lives |
| **Never** | Block `opencode` dispatch on missing Go credentials | Block `opencode` dispatch on missing Ollama when the seats in play are remote |

Same law: **driver ≠ signal source.** Local inference state must not be stuffed
into `CapacityProbe` PTY, and must not be read or reported by
`OpenCodeGoCapacity*`.

### 6.2 Source id recommendation: `ollama_local`

Pick `ollama_local` over `opencode_local`. `Vendor_Signal_Isolation.md`'s
promoted law is that a derived signal is attributed to **the source that
produced it**. Ollama produces every one of these readings; OpenCode is merely
the body that consumes the tokens. Naming it `opencode_local` would make the
agent body answer for a runtime it does not own — and would age badly the moment
a second agent body (or a second local runtime) appears. `ollama_local` is also
unambiguous next to driver `opencode` and capacity `opencode_go`.

This id should be used wherever the signal lands, **whether or not it ever joins
`benchSourceOrder`** (§7.5).

### 6.3 One serve, one lane (the v1 packet missed this)

Local and remote OpenCode seats are **not** independent. They share:

- one `opencode serve` on `:4096` (`OpenCodeServeCoordinator.defaultPort`);
- one `OpenCodeSpawnLock`, one `DriverConcurrencyGate`, `maxConcurrentSpawns: 1`;
- one SSE event bus, with all the foreign-session scoping CT-03 exists to fix;
- one 15-minute serve idle TTL and one 1800s driver wall.

So "add local seats" is not additive at the process level: a slow local turn
occupies the same lane a Go seat wants. The concurrency ceiling is therefore
already handled; the thing that is **not** handled is timing (§12).

---

## 7. Product law (candidate)

### 7.1 Provenance

| Provenance | Meaning | Availability language |
| --- | --- | --- |
| OpenCode remote (Go / Zen) | Vendor plan models | Subscription windows via `opencode_go` |
| **Local Ollama** | Models pulled on this Mac | Installed · loaded · effective context · machine busy · not installed |
| Ollama Cloud | **Out of packet** | Do not ship |

A locally computed VRAM, load, or context reading is never presented as a
vendor-stated fact ([project laws](../../AGENTS.md)).

### 7.2 Never block the remote path

`opencode` ready + Ollama absent → Go seats work normally and no local seat is
offered. Negative proof required in the first slice that can break it: with
Ollama unreachable, the seven Go seats resolve and dispatch unchanged.

### 7.3 Readiness gates (fail closed)

Before a local model is offered as a **mutating / Code** seat:

1. Ollama reachable (`/api/version`).
2. The tag is present locally in `/api/tags` — never a cloud tag.
3. The model advertises `tools` in its `capabilities`.
4. Effective context ≥ 64k (§7.4).

Absent evidence yields no offer, never an assumed one. Judgment-only seats may
relax 3 and 4 **with explicit labeling** — never as a silent Code default.

### 7.4 Context truth: advertised max ≠ served window

`/api/tags` reports each model's `context_length` — that is the model's trained
maximum (32768 for the model on this host). The window actually served is set by
the app slider or `OLLAMA_CONTEXT_LENGTH` and is observable in `/api/ps` as
`CONTEXT`, **only while the model is loaded**. Ollama defaults it from VRAM, so a
model advertising 256k can be served at 4k.

Rule: the ≥64k gate is measured against the **served** window. When the served
window cannot be observed, the seat is not a Code seat by default and the reason
is stated. Do not infer the served window from the advertised maximum; that
inference is exactly the shape of lie `Vendor_Signal_Isolation.md` forbids, and
its failure mode is a coding agent silently truncating the repo it was asked to
reason about.

### 7.5 Capacity vs readiness (founder ruled — closed)

`Product_Vocabulary.md`: *bench capacity = what each paid CLI subscription has
left; vendor-printed only, never estimated.* A local model has no subscription
and no vendor meter.

**Founder ruling:** local availability is **readiness, not capacity.** Do **not**
add `ollama_local` to `benchSourceOrder` in v1. Surface readiness through
`alln models` / `alln doctor` only.

**v1 readiness vocabulary (only):**

| State | Meaning | Typical evidence |
| --- | --- | --- |
| `Unavailable` | Cannot use local seats | Ollama down, or no usable local model |
| `Idle` | Ready, nothing running | Reachable; `/api/ps` empty (or equivalent) |
| `Busy` | Local inference in use | Model loaded / serving per `/api/ps` |

No VRAM %, no context gauges, no fake quota windows in v1. If evidence is
missing, emit `Unavailable` — never invent `Busy`.

OCL-S06 (strip row) stays **cancelled for v1**, not deferred-with-hope.

### 7.6 Vendor signal isolation

Ollama failures — server down, OOM, model missing, context too short, load
timeout — answer only for `ollama_local` and the local seat. They never classify
as a Claude, Codex, Grok, or Go limit, never park a run for a vendor limit that
did not happen, and never produce a substitution. Fail closed.

---

## 8. Module sketch (candidate owners — not an allowlist)

| Concern | Likely home |
| --- | --- |
| Detect Ollama; read `/api/tags` + `/api/ps` | AllnighterCore — one pure client + one pure parser, injectable transport, mirroring the `OpenCodeGoCapacityClient` / `…Probe` split |
| Project local tags → seats | **`ModelDiscoveryProvider` for `opencode`** — the registry's first real provider; `origin: .discovered` |
| Ensure OpenCode can reach `11434/v1` | Setup verb — **merge** into `enabled_providers` + `provider.ollama`, never overwrite |
| Dispatch | Existing `opencode` driver. No change. |
| Readiness surface | `alln models` / `alln doctor` — Unavailable \| Idle \| Busy only (§7.5) |
| Capacity strip row | **Cancelled for v1** (founder). Do not build. |

---

## 9. Truth owner / lie-prone layers

| | |
| --- | --- |
| **Truth owner** | Ollama `/api/tags` + `/api/ps` for local runtime state; OpenCode turn outcome for run truth; `ModelCatalog` for seat identity and provenance |
| **Lie-prone** | Advertised context read as served context; a discovered model inheriting an authored rank; local readings phrased as quota; Ollama errors classified against another vendor; a setup verb that replaces `enabled_providers`; a 0.5B plumbing smoke reported as capability |
| **Missing proof** | One `alln run --model <local>` that mutates a repo through OpenCode and settles honestly; the same on ICP-class hardware; stall/wall behavior on a slow local turn |

---

## 10. Slice ladder (candidate — **unauthorized**)

Not an implementation allowlist. No slice starts without a founder ruling, and
OCL-S00 should decide whether the rest is worth writing.

| Id | Intent | Code? |
| --- | --- | --- |
| **OCL-S00** | **DONE (2026-08-07).** Pipe PASS on Air with `qwen2.5:0.5b` — see §0.3. | **None** |
| **OCL-S01** | Detect + doctor: Ollama reachable; list local models; readiness Unavailable/Idle/Busy | Core |
| **OCL-S02** | Setup verb: additive OpenCode provider wiring, reversible, proven non-clobbering | Core/CLI |
| **OCL-S03** | First `ModelDiscoveryProvider` for `opencode`: local tags → opt-in seats with `.discovered` origin and local provenance | Core |
| **OCL-S04** | Readiness surface in `alln models` / `doctor` — three states only (§7.5) | Core/CLI |
| **OCL-S05** | Turn timing for local seats: stall window / wall that fit cold load without hiding real hangs — **only if OCL-S00 measures a real problem** | **AgentOS** |
| ~~**OCL-S06**~~ | ~~Capacity strip row~~ — **cancelled for v1** (founder) | — |

Out of ladder entirely: scarcity auto-routing, remote `OLLAMA_HOST`,
Claude-via-Ollama, Ollama Cloud, anything multi-host.

---

## 11. Works Test (target)

Two tiers. Never report the first as the second.

**A — Plumbing / pipe (any Apple Silicon, including Mac mini — required):**

```text
Given: Ollama up, a tool-capable local model that fits this Mac, opencode.json
       merged to enable an ollama provider alongside existing providers
When:  alln models verify <local_model_id>
       alln run "<one-file bounded edit>" --model <local_model_id> --json
Then:  the seat verifies; the run completes with a real answer or fails with a
       classified reason; the repo delta is real; provenance reads local;
       paid OpenCode seats are unaffected throughout; readiness never speaks
       quota language
```

**B — Capability / ICP feel (Studio-class RAM — optional sales proof, not a
ship gate for the pipe):**

```text
Given: A large-unified-memory Mac serving a coding-class local model at ≥64k
When:  the same bounded repair slice is given to the local seat and to a paid
       seat, and the lead re-runs the filtered gate itself
Then:  the local seat's work stands on its own gate — not on its own report
```

Do not block Ready-for-pipe on B. Do not sell B as proven because A passed.

**Negative test (required in whichever slice can first break it):** with Ollama
stopped, Go seats resolve, dispatch, and complete unchanged; no capacity row,
park, or substitution mentions Ollama.

Proof waiver: none claimed. Nothing here is shipped.

---

## 12. Risks

| Risk | Response |
| --- | --- |
| **`enabled_providers` clobber.** The dogfood config is an allowlist of exactly `["opencode-go"]`. A setup verb that writes instead of merging deletes all seven Go seats and looks like a driver outage. | Merge-only, with a before/after fixture test and a documented undo. Never touch the file outside an explicit verb. |
| **Stall watchdog vs cold local load.** `stallQuietInterval` is a hardcoded 120s; a large model's load plus long-prompt prefill can be silent longer than that, and CT-02's fix (only touch on *real* progress) removes the accidental keepalive. A healthy local turn would be reported `stalled_no_progress`. | OCL-S05. Do **not** widen the window globally — that would blind the remote seats CT-02 exists to protect. Scope the timing to the seat, or find a real local progress signal. |
| **1800s driver wall.** Slow local generation on a long turn can hit it while working. | Measure in OCL-S00/S01 before changing anything; a wall that is honestly hit is not a defect. |
| Shared `:4096` lane contention between local and Go seats | Already ceilinged at 1 spawn. Name it in diagnostics so "waiting for the lane" never reads as a vendor limit. |
| OpenCode completion truth is weaker on local models | Stay on the CT owners. Do not paper over with green tests — `Scarcity_Aware_Routing.md` §5a: every delegated defect this month was caught by re-running the gate, none by the seat's own report. |
| Served context silently below 64k | §7.4 gate, fail closed, stated reason. |
| Strength ranks for arbitrary pulls | `models add` already seats custom models as *Unrated — seats last*. Keep it. Author caliber only for models actually dogfooded. |
| Thermal / memory pressure on the user's foreground machine | Readiness reflects it; it never silently vetoes a named seat (`Scarcity_Aware_Routing.md` §3 ruling 3). |
| Scope creep into Cloud, LAN, or a model manager | §4 non-goals; separate packets only. |

---

## 13. Open questions (remaining)

**Closed by founder (§0.1):** capacity vs readiness; Idle/Busy vocabulary;
`ollama_local` id; mini proves pipe / Studio is ICP; OCL-S00 on current hardware;
Ollama Cloud / LAN out.

Still open (Spec Review may recommend; founder decides):

1. Discovery posture: every pulled tag offered opt-in, or only explicitly seated
   models? Lean: discover all, enable none by default, Code-gate on §7.3.
2. Is a judgment-only raw `ollama` driver ever wanted, or is OpenCode the only
   local agent body forever? Lean: OpenCode-only.
3. Served-context ≥64k: hard Code gate in v1, or warn + allow pin with labeled
   risk on mini-class RAM?

---

## 14. Done when (packet exit — future)

- [ ] A local Ollama model does real bounded mutating work as an OpenCode seat,
      proven by a gate the seat did not author
- [ ] Local provenance and local availability language never borrow quota words
- [ ] Ollama absent leaves every paid seat untouched (negative proof)
- [ ] Setup is additive and reversible; no user config is overwritten
- [ ] Ollama Cloud remains out of product
- [ ] Help + doctor teach detect → seat → run
- [ ] Promote keepable law; archive this packet

---

## 15. Related archive / do-not-resume

- [`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md) —
  shelved multi-host execution fabric. This packet is **single-Mac local
  inference under OpenCode**. Streamed diffs, remote mutators, and
  PeerTransport-as-execution do not return here.
- `docs/archive/2026-06-13-allnighter-pivot/strategy/Allnighter-Local-AI-Worker-Opportunity.md`
  — historical thesis. Keep the market read (operating layer, not runtime
  layer); discard the night-shift positioning and the read-only-forever framing.

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| Local / Ollama seats via OpenCode | This packet + `ModelCatalog` / `ModelDiscoveryProvider` |
| OpenCode driver / serve lifecycle | AgentOS `OpenCodeServeClient.swift` (dispatch — separate concern) |
| OpenCode Go subscription meter | [`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md) |
| Abundant vs scarce seat selection | [`Scarcity_Aware_Routing.md`](Scarcity_Aware_Routing.md) §3 first |
| Any capacity signal attribution | [`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) |
