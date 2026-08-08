# OpenCode Local (Ollama) Seats

Status: **Brainstorm — NOT ready for implementation. No slice authorized.**
Owner: unassigned (AllnighterCore catalog + capacity; AgentOS only if local
runtime truth needs a home beyond OpenCode dispatch)
Created: 2026-08-07
Origin: Founder dogfood — Ollama 0.32.x ships `ollama launch opencode` and
documents OpenCode → `http://localhost:11434/v1` (OpenAI-compatible). Local
models (Studio-class DeepSeek V4 Pro / Flash and peers) are becoming real
implementation seats, not chat toys. ALLN should put them on the same OpenCode
bench as Go seats — agent body already owned; Ollama is the model plane only.

Companion packets:
[`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md) (same driver, different
seat economics),
[`Scarcity_Aware_Routing.md`](Scarcity_Aware_Routing.md) (abundant vs scarce),
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) (no cross-source
capacity lies),
[`OpenCode_Long_Run_Continuity.md`](OpenCode_Long_Run_Continuity.md) /
[`OpenCode_Completion_Truth_Followup.md`](OpenCode_Completion_Truth_Followup.md)
(OpenCode completion honesty — local will stress it harder).

Upstream docs (external, not SSOT):
[Ollama](https://docs.ollama.com/),
[OpenCode integration](https://docs.ollama.com/integrations/opencode),
[OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility),
[Context length](https://docs.ollama.com/context-length),
[Tool calling](https://docs.ollama.com/capabilities/tool-calling).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## 1. One claim

With Ollama installed and at least one tool-capable local model pulled, the user
can seat that model on an **OpenCode** worker the same way they seat Go / Zen
models — `alln run` / Teams / Loop — without a new agent harness and without
Allnighter becoming a model runner.

Trusted workflow slice (target):

```text
ollama serve + model pulled (e.g. deepseek-class local)
  → Allnighter detects Ollama + lists local models
  → local models appear as OpenCode seats (provenance: local / ollama)
  → alln run --seat <local-opencode-model> "…" --json
  → OpenCode agent body (tools / FS / shell) + Ollama inference
  → capacity strip shows local hardware truth (loaded / busy / context),
    never a fake subscription meter
```

---

## 2. Why this belongs (and why not a raw `ollama` driver)

| Path | Verdict |
| --- | --- |
| New `DriverManifest` for `ollama run` | **Wrong for mutating Code / Loop.** Completion CLI, not an agent body. Judgment-only fallback only if ever needed. |
| New Allnighter-owned tool loop over Ollama HTTP | **Out of scope.** Reinvents OpenCode. |
| OpenCode provider → `http://localhost:11434/v1` | **v1 path.** Same driver `opencode`; local model ids as seats. |
| Drive runs via interactive `ollama launch opencode` | **Non-goal.** Human onboarding UX. Product runs stay under `RunService` + write lock with programmatic / config-backed provider wiring. |

Ollama’s own posture matches this: it launches and configures existing agents
([integrations overview](https://docs.ollama.com/integrations/index.md),
[OpenCode](https://docs.ollama.com/integrations/opencode.md)); it does not ask
Allnighter to become the agent.

### Parallel to Go seats (binding analogy)

| Layer | OpenCode Go | OpenCode Local (Ollama) |
| --- | --- | --- |
| **Driver** | `opencode` | `opencode` (same) |
| **Model plane** | Go / Zen remote models | Local Ollama models at `11434/v1` |
| **Seat identity** | Catalog models + Go economics | Catalog / discovered models + **local** provenance |
| **Capacity source** | Separate `opencode_go` (dashboard scrape) | Separate local capacity id (TBD name) — **hardware**, not quota |
| **Never** | Block `opencode` dispatch on Go config | Block `opencode` dispatch on Ollama missing when seats are remote-only |

Same law as Go: **driver ≠ capacity source**. Local inference scarcity must not
be stuffed into `CapacityProbe` PTY or into Go scrape modules.

---

## 3. Founder intent (product)

- ICP includes Mac Studio / large unified-memory Macs running serious local
  coding models (DeepSeek V4 Pro / Flash class and peers) for **real
  implementation**, not only review text.
- Local seats are first-class abundant labor: private, always-on, zero
  subscription burn — scarcity is VRAM / load / context / concurrency.
- **Ignore Ollama Cloud.** Cloud users already have Claude, Codex, Cursor,
  OpenCode Go, etc. This packet is **local-only** model provenance. Do not
  meter, catalog, or market Ollama Cloud seats under this work.
- Do not pitch overnight / sleep automation. All-day Teams + Loop.

---

## 4. Non-goals

- Ollama Cloud models, Ollama.com accounts, or cloud base URLs as product seats.
- A standalone `ollama` coding driver for mutating work.
- Using `ollama launch …` as the Allnighter run path.
- LAN Mac Studio farm / remote mutator offload (shelved:
  [`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md)).
  Optional later: remote `OLLAMA_HOST` for **inference only** — separate packet.
- Auto-routing that picks local vs cloud without an authorized scarcity design
  ([`Scarcity_Aware_Routing.md`](Scarcity_Aware_Routing.md) remains brainstorm).
- Fake capacity % or park-for-limit from Ollama “usage.”
- Overwriting the user’s `~/.config/opencode/opencode.json` without an explicit
  setup verb (Ollama launch uses inline config and does not clobber that file —
  Allnighter must be equally careful).
- Claude-Code-via-Ollama as a v1 seat (interesting dogfood; different
  `sourceId` / auth story — defer).

---

## 5. Current state

- OpenCode driver ships (AgentOS `OpenCodeServeClient` / SSE / permissions;
  Allnighter seating via catalog).
- Go seats: capacity packet
  [`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md) — subscription meter.
- Catalog already authors OpenCode strength ranks for remote seats
  (`model_opencode_deepseek_v4_pro`, `_flash`, etc. in `catalog_overlay.json`).
- Ollama 0.32.x on founder machine: `ollama launch` lists OpenCode among
  integrations; API at `127.0.0.1:11434`; `/api/tags` lists local models +
  capabilities (e.g. `tools`).
- No Allnighter detect → local OpenCode seat path yet.
- Historical strategy note (not live law):
  `docs/archive/2026-06-13-allnighter-pivot/strategy/Allnighter-Local-AI-Worker-Opportunity.md`.

---

## 6. Product law (candidate)

### 6.1 Planes

```text
OpenCode  = agent body (tools, repo, shell, completion truth)
Ollama    = local inference only (localhost OpenAI-compatible API)
Allnighter = detect, catalog, seat, capacity honesty, write lock
```

### 6.2 Provenance

| Provenance | Meaning | Capacity language |
| --- | --- | --- |
| OpenCode remote (Go / Zen / …) | Vendor / plan models | Existing + `opencode_go` where applicable |
| **Local Ollama** | User-pulled models on this Mac | Loaded / available / busy / context / not installed |
| Ollama Cloud | **Out of packet** | Do not ship |

A locally computed VRAM or load signal is never presented as a vendor-stated
quota fact ([project laws](../../AGENTS.md) — local vs vendor truth).

### 6.3 Agent readiness gates (fail closed)

For a local model to be offered as a **mutating / coding** OpenCode seat:

1. Ollama reachable (`/api/version` or equivalent).
2. Model present in local tags (not cloud).
3. Model advertises **tool** capability when required for the seat’s work.
4. Effective context length suitable for agents — Ollama docs: coding agents
   should use **≥ 64k** ([context length](https://docs.ollama.com/context-length)).
   Default VRAM-based contexts can be far lower; refuse or warn honestly.

Judgment-only seats may relax tools/context with explicit labeling — not as
silent Code defaults.

### 6.4 Concurrency

One large local model can monopolize the machine. Prefer a hardware-aware
spawn ceiling (reuse `DriverManifest.maxConcurrentSpawns` / OpenCode spawn
lock patterns) over unlimited parallel local seats. This is not the same
failure as OpenCode CLI deadlock — name it separately in capacity diagnostics.

### 6.5 Vendor Signal Isolation

Ollama errors (server down, OOM, model missing, context too short) answer only
for the local capacity / local seat `sourceId`. They must never classify as
Claude / Codex / Go rate limits
([`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md)).

---

## 7. Module sketch (TBD at implementation — not an allowlist yet)

Candidate owners (revise before first slice):

| Concern | Likely home |
| --- | --- |
| Detect Ollama + list local tags | AllnighterCore (doctor / setup / catalog feed) |
| Map tags → OpenCode model seats + provenance | `ModelCatalog` / overlay + discovery |
| Ensure OpenCode can reach `11434/v1` for local seats | Setup / config projector — **no silent clobber** |
| Dispatch | Existing `opencode` driver path |
| Local capacity row | Parallel to Go: dedicated modules, **not** `CapacityProbe` PTY, **not** `OpenCodeGoCapacity*` |
| Strip / CLI | `CapacityAcquisition` / `alln capacity` when a local source id is promoted |

Naming (open): capacity source id candidates `opencode_local` /
`ollama_local` — pick one before code; keep distinct from driver `opencode`
and capacity `opencode_go`.

---

## 8. Slice ladder (candidate — unauthorized)

Do not treat this as an implementation allowlist until a founder/SOL review
marks Ready.

| Id | Intent |
| --- | --- |
| **OCL-S00** | Detect + doctor: Ollama installed / reachable; list local models; no seating yet |
| **OCL-S01** | Catalog: project N local models as OpenCode seats with `local` provenance; opt-in enable |
| **OCL-S02** | Headless Works Test: one `alln run` on a local OpenCode seat returns honest observation |
| **OCL-S03** | Capacity: local hardware truth row (loaded / busy / context / unknown) — fail closed |
| **OCL-S04** | Setup UX: “use Ollama with OpenCode” without clobbering user config; help topic |
| **OCL-S05** | Dogfood Studio seats (Pro / Flash class) on Code team / Loop with concurrency gate |

Out of ladder: scarcity auto-router, remote `OLLAMA_HOST`, Claude-via-Ollama,
Ollama Cloud.

---

## 9. Truth owner / lie-prone layers

| | |
| --- | --- |
| **Truth owner** | OpenCode run outcome + Ollama process/API state; catalog provenance tags |
| **Lie-prone** | Treating `ollama run` as an agent; inventing quota %; stuffing local into Go or PTY capacity; silent 4k-context coding seats; cloud models labeled local |
| **Missing proof** | Live Studio (or equivalent) `alln run` on a tool-capable local model through OpenCode; capacity row that refuses to invent subscription language |

---

## 10. Works Test (target)

```text
Given: Ollama up, one tool-capable local model pulled, OpenCode configured for
       localhost:11434/v1 for that model id
When:  alln run "<bounded prompt>" --seat <local-opencode-seat> --json
Then:  run completes or fails honestly under existing OpenCode observation;
       seat provenance is local; capacity does not show a fake 5h/weekly %
```

Proof waiver until first authorized slice: none claimed shipped.

---

## 11. Risks

| Risk | Response |
| --- | --- |
| OpenCode completion truth weaker on local models | Stay on Long Run / Completion Truth owners; do not paper over with green tests |
| Context default too small for agents | Gate seats on ≥64k (or explicit warn + non-default) |
| Config clobber / fight with `ollama launch` | Setup verb owns a documented, reversible path |
| Strength ranks for unknown pulls | Author caliber only for known dogfood ids; unknown models low/default-off |
| Thermal / VRAM thrash from fan-out | Concurrency ceiling + capacity busy signal |
| Scope creep into Ollama Cloud or LAN cluster | Explicit non-goals; separate packets only |

---

## 12. Open questions (founder / review)

1. Capacity source id: `opencode_local` vs `ollama_local`?
2. Static overlay for Studio dogfood models vs fully dynamic `ollama list`?
3. Default-on for any local model, or enable-per-model after detect?
4. Is judgment-only `ollama run` ever worth a second driver, or OpenCode-only forever?
5. When (if ever) is remote `OLLAMA_HOST` in-scope as inference URL only?

---

## 13. Done when (packet exit — future)

- [ ] Local Ollama models seat as OpenCode workers for Code-class work
- [ ] Provenance and capacity language stay local/hardware, never fake quota
- [ ] Ollama Cloud remains out of product
- [ ] Help + doctor teach detect → seat → run
- [ ] Promote keepable law; archive this packet

---

## 14. Related archive / do-not-resume

- [`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md) —
  shelved multi-host execution fabric. This packet is **single-Mac local
  inference under OpenCode**, not a Studio farm.
