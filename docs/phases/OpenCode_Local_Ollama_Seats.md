# Ollama Local Seats (OpenCode + Claude Code)

Status: **OCL-S00 pipe PASS (partial honesty) — code slices still unauthorized.**
  Founder rulings locked (§0.1), including **both agent bodies** (2026-08-08).
  Spec Review Min: Ready for OCL-S00 only (`FE9F2530…`); OpenCode-only lean
  **superseded** by §0.1.7. Live dogfood §0.3; bakeoff §0.4.
Revised: 2026-08-08 (v5 — Claude Code + OpenCode agnostic; bakeoff; G0–G3 gates)
Owner: unassigned (AllnighterCore catalog + model discovery; AgentOS for
OpenCode serve attach / local turn timing / Claude-local env isolation as scoped)
Created: 2026-08-07
Origin: Founder dogfood — Ollama 0.32.x ships `ollama launch opencode` **and**
`ollama launch claude`, and documents both against local inference
([OpenCode](https://docs.ollama.com/integrations/opencode) → OpenAI-compat
`11434/v1`; [Claude Code](https://docs.ollama.com/integrations/claude-code) →
Anthropic-compat `11434`). Local models are becoming real implementation labor.
ALLN seats them with **local provenance** under existing agent drivers — not a
raw `ollama` mutator, and not a single crowned body.
**Dogfood split:** prove the pipe on a Mac mini / Air (any Apple Silicon); sell
the upside to Mac Studio users. Same software.

Companion packets:
[`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md) (OpenCode driver, different
seat economics — binding structural analogy for Go vs local labels),
[`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md) (leftover `:4096` attach —
blocks all OpenCode seats including local),
[`Scarcity_Aware_Routing.md`](Scarcity_Aware_Routing.md) (abundant vs scarce;
read its §3 rejected list before proposing any auto-routing),
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) (a signal answers
only for the source that produced it),
[`OpenCode_Long_Run_Continuity.md`](OpenCode_Long_Run_Continuity.md) /
[`OpenCode_Completion_Truth_Followup.md`](OpenCode_Completion_Truth_Followup.md)
(OpenCode completion honesty — local models stress it harder, see §12),
[`Ambient_Dirty_Run_Outcome.md`](Ambient_Dirty_Run_Outcome.md) (`--no-commit` /
dirty-tree outcome honesty — shared ship blocker).

Upstream docs (external, not SSOT):
[Ollama](https://docs.ollama.com/),
[OpenCode integration](https://docs.ollama.com/integrations/opencode),
[Claude Code integration](https://docs.ollama.com/integrations/claude-code),
[OpenAI compatibility](https://docs.ollama.com/api/openai-compatibility),
[Context length](https://docs.ollama.com/context-length),
[Tool calling](https://docs.ollama.com/capabilities/tool-calling).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## 0. Review verdict

**Pipe proven on Air. Not Ready for Implementation slices** until Spec Review
packet fixes land, serve-attach / Claude-isolation honesty gaps close, and a
coding-class gated repair passes (§11 B optional; honesty gaps below are
mandatory for S01+).

### 0.1 Founder rulings — binding

**2026-08-07**

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

**2026-08-08 (agent-body + bakeoff)**

7. **Agnostic agent bodies — both.** End state is **not** “pick OpenCode or
   Claude Code forever.” Ollama is inference; the agent body is a seat attribute
   the same way Allnighter already refuses to crown a single paid CLI.
   - **Claude Code body** — ICP wedge: developers who already live in Claude
     stay in the tool they trust; local labor without leaving that harness.
   - **OpenCode body** — ICP wedge: local / open-source-leaning users who
     already run OpenCode (and Go seats) keep one mental model; OCL-S00 pipe
     already exists.
   Both are in-scope. Crowning one forever is out.
8. **Sequence ≠ architecture.** Shared Ollama detect / readiness /
   `ollama_local` provenance ships once. Body adapters (OpenCode provider wiring
   vs Claude per-run Anthropic-compat env) serialize. Do not build two full
   discovery ladders in parallel before one honest Works Test per body.
9. **Model gates before alln blame.** Different models show different bugs;
   that does **not** mean the Air “fails.” Gate ladder §0.4.2 (G0→G3) is
   binding for dogfood and for what we offer as a Code seat.
10. **Dev builds only until fully ready** (founder) — no CLI dev-build gate
    exists yet; that mechanism precedes productizing OCL-S01/S02/S04.

### 0.2 Spec Review Min (2026-08-07) — `FE9F2530-7E96-4E16-AC0F-296F4CA26D86`

Verdict: **Ready for OCL-S00 only.** Leans locked for implementers:

- ≥64k: hard block on **automatic** offers; **warn-and-allow** on explicit
  `--model` (unblocks served-context deadlock).
- Discovery: list all / enable none; build S03 only after one real gated local
  repair.
- ~~No raw `ollama` driver — OpenCode only for this packet’s lifetime.~~
  **Superseded by §0.1.7:** still **no raw `ollama` mutator**; agent bodies are
  **OpenCode and Claude Code**, not OpenCode-only.

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
| Outcome `completedWithoutChanges` | **ALLN semantics, not model** — see §0.3.1 |
| Model narrative (`result.txt`) | **Weak model** — see §0.3.1 |
| Served context (`ollama ps`) | **4096** — below 64k agent guidance; explicit pin still ran |
| Stall / 120s quiet | **N/A** — tiny model finished in seconds |
| Go seats after merge | **PASS** — `enabled_providers` still includes `opencode-go` |
| Follow-up JSON transform (no tools) | Run `985C04B1…` — JSON shape returned; `shouted` wrong (echoed Co-Authored-By) — **weak model** (+ possible provenance prompt bleed) |
| Serve contention | Run `DECEC902…` failed `opencode serve busy: port owned by pid …` — **infra bug**, model-independent |

**Also observed (1.5b coder earlier):** run `AC6BD0CB…` returned tool JSON as text without editing TARGET — tool follow-through weak on tiny models.

**OCL-S00 verdict:** **Pipe works on Air.** Cleared to **finalize the spec and plan iron-out slices**. **Not** cleared to build the full discovery/setup ladder as if local coding seats are product-ready.

### 0.3.1 Bug vs weak model (attribution)

Three different “lies,” three owners:

| Observation | Owner | Why |
| --- | --- | --- |
| `outcome.completedWithoutChanges: true` while TARGET.md changed under `--no-commit` | **Allnighter** | `TeamRunJSONMapper` sets that flag from `repoDelta.changed` only. `RepoDelta.changed` is **commit-range** truth (`baseline ≠ head`). With `--no-commit`, head never moves, so the flag is true even when `worktreeDirty: true`. The dirty bit was present and honest; the headline flag ignored it. **Model-independent.** Code: `TeamRunJSONMapper` + `RepoDelta` docs. |
| Answer claimed `result.txt` / “already done” while write tool hit TARGET.md | **Weak model** (0.5B) | Tools actually ran (`workerActivity` tool=write). Narrative ≠ tool trail. Stronger models may still need CT honesty, but this instance is capability. |
| JSON probe `shouted` = Co-Authored-By string | **Mostly weak model**; check provenance injection | Shape OK; value wrong. May be echoing Allnighter’s no-commit / co-author prompt furniture — still not an outcome-meter bug. |
| `models verify` / run fail with serve busy or Session not found | **Allnighter ↔ OpenCode serve** | Stale or foreign `:4096` owner blocks attach. Recurs in dogfood. **Must iron out** before local seats feel reliable. |

**Implication:** do **not** dismiss S00 honesty issues as “0.5B is trash.” At least one is a real product bug (`completedWithoutChanges` under `--no-commit` + dirty tree). Serve ownership is a second real bug. Model weakness explains false prose, not the meter.

### 0.3.2 Continued testing (same night) — kill safety + serve leftover

**Ops law (founder FYI, binding for agents):** do **not** kill `alln serve`
(e.g. pid 43273, multi-day daemon). A terminal run can show `identityAlive: true`
while the identity points at the **long-lived server**, not a worker. Killing
“dead” runs by pid without `ps` can take down Allnighter entirely. Check
`ps -p <pid> -o command=` first; refuse if the command is `alln serve`.

**OpenCode `:4096` leftover is a separate process** (`opencode … serve`). It is
not `alln serve`. Stopping a leftover OpenCode serve for dogfood reclaim is OK;
stopping `alln serve` is not.

| Run | What | Result |
| --- | --- | --- |
| `6F7F31AD…` | Arithmetic JSON while foreign OpenCode :4096 up | **FAIL** `opencode serve busy: port owned by pid 4459` — healthy serve refused |
| `E04065FB…` | Same JSON with :4096 free (alln starts OpenCode) | **PASS pipe** — completed; answer was fake `write` tool JSON (weak model), not `{"sum":5}` |
| `D9D921EF…` | Mutating edit **immediately after** — leftover OpenCode pid 14749 still listening | **FAIL** `serve busy: port owned by pid 14749` — **reproducible** |
| `5946FEB0…` | After stopping **only** OpenCode leftover (alln serve untouched) | **PASS pipe** — completed; model emitted fake `webfetch` JSON; TARGET unchanged; `completedWithoutChanges: true` again |

**Hardening target #1 for local (and all OpenCode) seats:** after a run ends,
either (a) tear down the OpenCode serve this worker started, or (b) **attach**
to an already-healthy `:4096` instead of reporting busy. Today’s behavior makes
second local runs flake unless a human clears the port — model-independent.
Owned with [`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md).

`alln serve` stayed up through all of the above.

### 0.4 Bakeoff (2026-08-08) — OpenCode vs Claude Code on Air

Host unchanged: `Mac16,13` · 32 GB · ollama 0.32.6 · opencode 1.18.15 ·
Claude Code 2.1.225. Fixtures under `docs/qa/ollama-bakeoff/` (spike only).

#### 0.4.1 What was wrong with the first pass

First bakeoff used **`qwen2.5-coder:3b` / `1.5b`**. Those often **print fake
tool JSON as text** (no structured `tool_calls`). That is a **model / tool-API
failure**, not proof that the Air cannot run local seats and not a fair
Claude-vs-OpenCode verdict. Founder catch: retest on the tiny canary
`qwen2.5:0.5b` and gate models before blaming harnesses.

#### 0.4.2 Binding model gate ladder (G0→G3)

```text
G0  ollama run <tag> "<fixed JSON extract>"
      → inference loads and answers

G1  native /api/chat (or /v1) with one write tool
      → structured tool_calls (not text faking tools)

G2  agent body mutate TARGET.md (Claude Code and/or OpenCode)
      → harness + model together

G3  alln run --model <seat> same mutate
      → bench path (serve attach, outcome honesty, provenance)
```

**G0 is necessary and cheap. G1 is the missing filter** that would have saved
the first bakeoff. A model that only passes G0 must not be sold as a Code seat.
Do not jump G0 → G3 and call alln red when G1 was never green.

Air canary for plumbing: **`qwen2.5:0.5b`**. Next mid-tier candidate to pull
when capability matters: **`qwen2.5-coder:7b`** (still Air-feasible). Studio /
≥64k served context remains the capability/ICP proof (§11 B), not the pipe gate.

#### 0.4.3 Results (condensed)

| Probe | Result | Owner |
| --- | --- | --- |
| Ollama OpenAI `/v1` + Anthropic `/v1/messages` smoke | Both return `PONG` | Ollama pipe OK |
| G0: `ollama run qwen2.5:0.5b` name/role JSON extract | **PASS** (~2s) — correct JSON | Model OK for judgment |
| G1: native tools on `0.5b` | Structured `tool_calls` (args often messy) | Model weak, not dead |
| G1: native / OpenAI / Anthropic tools on `3b` | Often text-JSON, no structured calls | **Model** — not Air failure |
| G2: Claude Code + `0.5b` mutate TARGET | **PASS** — file became `STATUS: AFTER`, `DONE` | Body + model OK for pipe |
| G2: OpenCode + `0.5b` mutate TARGET | Real `write` tool fired; **content wrong** (garbage + still `BEFORE`) | Weak model / body follow-through |
| G2: both bodies + `3b` mutate | Exit 0, TARGET unchanged, fake tool JSON as text | Model tool-structure fail |
| G2 judgment `17*19` both bodies + `3b` | Both returned 323 | Judgment OK when no tools |
| G3: `alln` + OpenCode local while leftover `:4096` | **FAIL** `opencode serve busy: port owned by pid …` | **Allnighter ↔ OpenCode serve** |
| Claude `--bare` + Ollama env; wrong model `sonnet` | Local **404**, no Anthropic bleed | Isolation workable |
| Claude local success shape | Claims `contextWindow: 200000`, `costUSD`, `provider: firstParty` on 4096 local turn | **Lie-prone** — strip for local provenance |
| Concurrent alln rebuild / other commits mid-spike | Outcome / `repoDelta` easy to misread | Dogfood hygiene — attribute carefully |

**Bakeoff verdict:** Air does **not** fail. Tool bugs vary by **model**. On the
fair canary (`0.5b`), **Claude Code won the correct mutate**; OpenCode proved
tools can fire but content honesty was weak. Product law remains **both
bodies** (§0.1.7). OpenCode keep reasons: open-source / local affinity + Go
parity + OCL-S00. Claude keep reasons: stay-in-tool ICP + stronger dogfood
agent when the model cooperates.

#### 0.4.4 Architecture after bakeoff

```text
Ollama         = inference (11434). Signal source: ollama_local.
Agent body     = Claude Code  OR  OpenCode  (seat attribute; both in-scope).
Allnighter     = detect · seat · provenance · honesty · write lock.
```

| Body | Inference wire (external) | ALLN driver today | Local seat shape (target) |
| --- | --- | --- | --- |
| OpenCode | OpenAI-compat `http://localhost:11434/v1` | `opencode` | label `ollama/<tag>` under driver `opencode` (OCL-S00) |
| Claude Code | Anthropic-compat `ANTHROPIC_BASE_URL=http://localhost:11434` + token `ollama` + empty API key | `claude_code` (paid Anthropic today) | same driver family, **local provenance**, per-run env isolation — must never poison paid Claude capacity / backoff |

Interactive `ollama launch claude|opencode` remains **human onboarding**, not
the Allnighter run path.


| Question | Answer |
| --- | --- |
| Cleared for **OCL-S00** (pipe)? | **Yes — done.** |
| Cleared for **full implementation** (S01+ as product)? | **No.** Honesty / serve-attach / Claude isolation / Spec Review packet fixes first. |
| Do we know the architecture? | **Yes:** Ollama = inference; bodies = Claude Code **and** OpenCode; readiness Idle/Busy outside capacity strip; signal `ollama_local`. |
| Do we know the ship blockers? | **Yes:** (1) `--no-commit` outcome honesty, (2) OpenCode serve attach/busy, (3) Spec Review context-gate packet fix, (4) Claude-local env + meter isolation design, (5) coding-class gated repair (G1+G2 on mid-tier, not only 0.5b). |

**Recommended next (unauthorized until founder says go):**

1. **Doc/spec v5** — this revision (absorb Spec Review leans + both bodies + bakeoff).
2. **Small honesty slice** — mutating `--no-commit` must not claim
   `completedWithoutChanges` when `worktreeDirty` (see Ambient Dirty packet).
3. **Serve ownership** — [`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md).
4. **Claude-local spike design** — per-run env isolation + strip Anthropic-shaped
   meters for `ollama_local` seats (no product surface until designed).
5. **Model ladder dogfood** — G0→G1 on pulled tags; pull `qwen2.5-coder:7b` when
   ready for mid-tier G1/G2; only then treat G3 alln failures as bench bugs.
6. **Only then** shared S01 readiness + body setup verbs.

### 0.5 Still blocking Ready-for-Implementation

1. Spec Review packet fixes (context gate, Busy=resident, discovery lean; body
   lean updated to both)
2. `--no-commit` + dirty ⇒ false `completedWithoutChanges` (**bug**)
3. OpenCode serve leftover / foreign `:4096` ⇒ next run `serve busy` (**bug**,
   reproducible; reclaim or attach)
4. Never treat terminal-run `identityAlive` pid as killable without `ps` —
   may be `alln serve`
5. OpenCode CT unfinished — local amplifies false-done prose
6. Claude-local isolation + meter honesty not designed in code
7. No coding-class gated repair yet (0.5b is pipe-only; 3b failed G1 often)
8. Dev-build gate mechanism (founder) before productizing discovery/setup

What v5 changed: both bodies as law; bakeoff §0.4; G0–G3 gates; Claude keep /
OpenCode keep; Spec Review OpenCode-only lean superseded.

---

## 1. One claim

With Ollama running and one tool-capable local model pulled, the user can put
that model on the bench as a **local seat** behind an agent body they already
use — **Claude Code and/or OpenCode** — and pin it with `--model`, the same way
they pin any other seat. No new inference stack, no claim that Allnighter runs
models, no crowning of a single local harness.

Trusted workflow slice (target):

```text
ollama serve + tool-capable model pulled (passes G0; Code seats also G1)
  → Allnighter detects Ollama and lists local models (tools? context?)
  → user enables a local seat on a chosen body (claude_code | opencode)
  → provenance: local (ollama_local); readiness: Unavailable | Idle | Busy
  → alln run "…" --model <local_model_id> --json
  → agent body (tools / FS / shell) + Ollama inference
  → honest completion or honest failure; never a subscription meter
```

### Dogfood vs sell (founder)

```text
Mac mini / Air (any AS)  → prove the pipe (integration Works Test; 0.5b canary)
Mac Studio owners        → who feel the upside (larger local models, abundant labor)
```

Same binary. Different wallet and model class. Integration dogfood must not
depend on Studio RAM.

### Why both bodies (ICP)

| Body | Who it wins | Why Allnighter keeps it |
| --- | --- | --- |
| Claude Code | Developers who already live in Claude | Stay-in-tool; strongest paid dogfood agent; Ollama documents Anthropic-compat officially |
| OpenCode | Local / open-source-leaning users; Go seat users | Same driver family as Go; OCL-S00 pipe; open tools affinity matches “run weights on my Mac” |

Allnighter already supports many CLIs without picking a winner. Local inference
is the same shape: **one abundant runtime × multiple bodies**.

---

## 2. The bridge — why this is Allnighter's job

### 2.1 Three planes, pluggable body

```text
Ollama       = inference. Weights, VRAM, context, load/unload. Nothing else.
Agent body   = Claude Code  OR  OpenCode. Tools, filesystem, shell, session.
Allnighter   = the bench. Detect · seat · provenance · honesty · write lock.
```

Neither inference nor a single agent body wants Allnighter's job. Ollama's own
posture is to *launch and configure existing agents*
([integrations](https://docs.ollama.com/integrations/index.md)) — Claude Code
and OpenCode both appear in `ollama launch`. Each body runs one agent well and
has no opinion about the rest of the bench. The gap between "I can run a model"
and "this model showed up to work alongside Claude, Codex, and Grok under one
write lock, with one run contract and one honest failure story" is the product.

What Allnighter adds that neither layer does:

| Layer | Contribution |
| --- | --- |
| Detect | Ollama present, reachable, which models, which pass G0/G1 |
| Seat | One `model_id` on the bench next to paid seats, same `--model` pin |
| Body | Claude Code **and** OpenCode adapters; user chooses; no crown |
| Provenance | This answer came from *your machine*, not a vendor (`ollama_local`) |
| Honesty | Local scarcity is hardware, never dressed as a quota; body meters stripped when local |
| Safety | One mutating worker per root; the local seat is not exempt |
| Contract | Same `TeamRunJSON`, same `alln show`, same artifacts |

### 2.2 The Mac Studio wedge

The ICP is a Mac with large unified memory (128 GB and up) whose owner already
pays for two to four coding CLIs. Today that machine's local models are a second
workflow: a different terminal, a different mental model, a different place to
look for the result. The wedge is that they stop being a second workflow —
**including staying inside Claude Code when that is their home**, and staying
inside OpenCode when that is theirs.

"Real implementation" means the local seat does bounded mutating work — the
repair-shaped slices `Scarcity_Aware_Routing.md` §5a found delegate best — not
just summarization and review. The historical local-worker note
(`docs/archive/2026-06-13-allnighter-pivot/strategy/Allnighter-Local-AI-Worker-Opportunity.md`)
argued for starting read-only and earning trust; it was written before these
agent bodies existed. Its durable half is the market read — *the local runtime
market is crowded, the "local model as scheduled worker" market is not* — and
that half still holds. Its "night shift" framing does not: dogfood reality is
all-day Teams and Loop.

The economics are the point. Claude hours are scarce and walled; a local seat is
**abundant** — no per-token cost, no reset clock, no vendor to ask. Abundance is
a **disclosure**, never a standing "prefer local" rule
(`Scarcity_Aware_Routing.md` §3).

Mission fit: *you already pay for the team* extends cleanly to hardware you
already bought **and** to the CLI you already live in. The Studio is a paid
seat that never shows up to work.

### 2.3 What this is not

| Not | Why |
| --- | --- |
| An Ollama UI / model manager | LM Studio and Open WebUI own that. ALLN never pulls, quantizes, or tunes. |
| A LAN Studio farm | [`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md) is shelved. One Mac, local inference. No multi-host mutators. |
| A raw `ollama run` driver | A completion CLI is not an agent body. G0-only. See §3. |
| A local model provider | ALLN does not host, serve, or bill inference. Ollama does. |
| An overnight pitch | All-day Teams + Loop. The name is brand only. |
| A forever-OpenCode-only local path | Superseded §0.1.7 — both bodies. |

---

## 3. Why agent bodies (not a new ollama driver)

| Path | Verdict |
| --- | --- |
| New `DriverManifest` for `ollama run` | **Wrong for mutating Code / Loop.** Completion CLI; G0 only. Judgment-only fallback not proposed. |
| Allnighter-owned tool loop over Ollama HTTP | **Out of scope.** Reinvents agent bodies and inherits every completion-truth defect already paid for. |
| OpenCode provider → `http://localhost:11434/v1` | **In-scope body #1.** Same driver `opencode`; local labels `ollama/<tag>`. OCL-S00 proven. |
| Claude Code → Anthropic-compat `11434` via per-run env | **In-scope body #2.** Same `claude_code` driver family; local provenance; isolation is the ship gate. |
| Interactive `ollama launch claude\|opencode` | **Non-goal for product runs.** Human onboarding UX. Product stays under `RunService` + write lock. |
| Crown one body forever | **Rejected.** Same law as multi-CLI bench. |

---

## 4. Non-goals (ironclad)

- **Ollama Cloud** models, accounts, or cloud base URLs as product seats. Cloud
  users already have Claude, Codex, Cursor, and OpenCode Go. This packet is
  local provenance only — do not meter, catalog, or market Cloud seats here.
- A standalone `ollama` coding driver for mutating work.
- `ollama launch …` as the Allnighter run path.
- **Rewriting the user's `~/.config/opencode/opencode.json`.** Additive only,
  behind an explicit setup verb, reversible. See §12.
- Silently rewriting global Claude / Anthropic env for the user’s shell.
  Claude-local must be **per-run** isolation.
- LAN / multi-host execution (shelved). A remote `OLLAMA_HOST` as an
  *inference URL only* is a separate future packet, not this one.
- Auto-routing local vs cloud. `Scarcity_Aware_Routing.md` §3 rejects standing
  vendor-preference rules.
- Any capacity percentage, park-for-limit, or substitution decision derived from
  Ollama state.
- Reporting Anthropic-shaped meters (`costUSD`, fake 200k context, “firstParty”)
  as truth for `ollama_local` seats.

---

## 5. Current state (verified 2026-08-07/08 — binding over early assumptions)

### 5.1 Live code

| Fact | Where | Why it matters |
| --- | --- | --- |
| Driver `opencode` invokes `opencode run --attach http://127.0.0.1:4096 -m {{model}}`, `maxConcurrentSpawns: 1`, `timeoutSeconds: 1800` | AgentOS `Catalog/catalog.json` | OpenCode-local is a model **label**, not a new driver. Concurrency ceiling exists. |
| OpenCode models are ids like `model_opencode_deepseek_v4_pro` with label `opencode-go/…` | AgentOS `catalog.json` + overlay | **Provider is inside the label.** Local = `ollama/<tag>`, not a Go seat relabelled. |
| `alln models add --driver <id> --name <n> --model-label <label>` then `verify` | `ModelsCLI.swift`, `ModelCatalog` | OpenCode-local seat can be created today (OCL-S00). Claude-local seating not productized yet. |
| `ModelOrigin.discovered` exists; discovery providers unused | `ModelDiscoveryProvider.swift` | First real provider should be Ollama tags — body-agnostic list, body-specific enable. |
| Capacity tiers meter **paid** subscriptions only | `CapacityAcquisition.swift` | Local stays readiness, not strip (§7.5). |
| Claude Code paid seats use `claude_code` | catalog | Claude-local must share driver carefully: env isolation + provenance, never capacity bleed. |

### 5.2 This host (honest, and it is not the ICP)

```text
Mac16,13 · 32 GB unified memory · macOS 15.6.1
ollama 0.32.6 · pulled: qwen2.5:0.5b, qwen2.5-coder:1.5b, qwen2.5-coder:3b
  (all advertise tools; served CONTEXT often 4096 on this host)
opencode 1.18.15 · enabled_providers includes opencode-go + ollama (post OCL-S00)
Claude Code 2.1.225 · local via env spike only (not an alln seat yet)
```

Consequences:

1. **32 GB default context bands** can leave served window at 4k–32k — below
   64k agent guidance. Explicit `--model` warn-and-allow (§0.2); automatic Code
   offers stay gated on served ≥64k.
2. **0.5b is the Air pipe canary** — enough for G0/G2 plumbing; not capability.
3. **1.5b/3b coder can fail G1** (text-fake tools). Do not treat that as “Air
   cannot do local.” Pull mid-tier (`7b`) before capability claims.
4. **`enabled_providers` clobber risk remains** for OpenCode setup verbs (§12).

---

## 6. Structural parity

### 6.1 Driver ≠ capacity source (still binding)

| Layer | OpenCode Go | OpenCode Local | Claude Local (target) |
| --- | --- | --- | --- |
| **Driver id** | `opencode` | `opencode` | `claude_code` (isolated) |
| **Model plane** | `opencode-go/…` | `ollama/…` | local model id + provenance |
| **Scarcity** | subscription windows | VRAM / load / context | same local hardware |
| **Signal source** | Go dashboard scrape | `127.0.0.1:11434` | same `ollama_local` |
| **Never** | Block opencode on missing Go creds when seat is local | Block opencode on missing Ollama when seat is Go | Park paid Claude for Ollama OOM / miss |

### 6.2 Source id: `ollama_local`

Pick `ollama_local` over `opencode_local` or `claude_local`. Ollama produces the
runtime readings; the body only consumes tokens. Naming the body as the signal
source ages badly the moment a second body appears — and we now have two.

### 6.3 OpenCode: one serve, one lane

Local and remote OpenCode seats share `:4096`, spawn lock, and SSE bus. See
[`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md). Claude-local does **not**
share that port — different isolation hazard (Anthropic env / keychain), not
serve-busy.

---

## 7. Product law (candidate)

### 7.1 Provenance

| Provenance | Meaning | Availability language |
| --- | --- | --- |
| OpenCode remote (Go / Zen) | Vendor plan models | Subscription windows via `opencode_go` |
| Claude / Anthropic paid | Vendor plan models | Existing Claude capacity story |
| **Local Ollama** (any body) | Models pulled on this Mac | Unavailable \| Idle \| Busy |
| Ollama Cloud | **Out of packet** | Do not ship |

A locally computed VRAM, load, or context reading is never presented as a
vendor-stated fact. Claude-local must not present `costUSD` / fake large context
as Anthropic truth.

### 7.2 Never block the remote path

- `opencode` ready + Ollama absent → Go seats work; no local OpenCode seat offered.
- `claude_code` ready + Ollama absent → paid Claude works; no local Claude seat offered.
- Negative proofs required when the first slice can break either.

### 7.3 Readiness gates (fail closed) for mutating / Code seats

1. Ollama reachable (`/api/version`).
2. Tag present locally in `/api/tags` — never a cloud tag.
3. Model advertises `tools` **and** passes **G1** (structured tool_calls) before
   automatic Code offer. G0-only → judgment / explicit pin with labeled risk.
4. Effective **served** context ≥ 64k for automatic Code offer; warn-and-allow
   on explicit `--model` (§0.2).

### 7.4 Context truth: advertised max ≠ served window

Unchanged: gate on **served** window from `/api/ps` when loaded; do not infer
from advertised `context_length`.

### 7.5 Capacity vs readiness (founder ruled — closed)

Local availability is **readiness, not capacity.** Do **not** add `ollama_local`
to `benchSourceOrder` in v1. Surface via `alln models` / `doctor` only.
OCL-S06 strip row **cancelled for v1**.

### 7.6 Vendor signal isolation

Ollama failures answer only for `ollama_local` and the local seat. They never
classify as a Claude, Codex, Grok, or Go limit, never park a paid run, never
produce a substitution. Claude-local env must fail closed toward Ollama — never
silently fall back to Anthropic mid-seat.

### 7.7 Body choice

The user (or team seat config) selects the agent body. Allnighter does not
auto-prefer Claude-local or OpenCode-local. No scarcity router invents a
standing rule (§3 of Scarcity packet).

---

## 8. Module sketch (candidate owners — not an allowlist)

| Concern | Likely home |
| --- | --- |
| Detect Ollama; `/api/tags` + `/api/ps` | AllnighterCore — pure client + parser (body-agnostic) |
| Project local tags → candidate seats | `ModelDiscoveryProvider` — first real provider |
| OpenCode: ensure `11434/v1` provider | Setup verb — **merge** `enabled_providers` + `provider.ollama` |
| Claude-local: per-run Anthropic-compat env | AgentOS / `claude_code` spawn path — isolation + meter strip |
| Dispatch | Existing `opencode` / `claude_code` drivers |
| Readiness surface | `alln models` / `doctor` — three states only |
| Capacity strip row | **Cancelled for v1** |

---

## 9. Truth owner / lie-prone layers

| | |
| --- | --- |
| **Truth owner** | Ollama `/api/tags` + `/api/ps` for local runtime; agent-body turn outcome for run truth; `ModelCatalog` for seat identity and provenance |
| **Lie-prone** | Advertised context as served; G0 pass sold as Code-ready; text-fake tools treated as harness bugs; OpenCode serve busy as model failure; Claude-local `costUSD` / 200k context / firstParty; `enabled_providers` clobber; 0.5b plumbing sold as Studio capability; ambient dirty / concurrent commits misread as the local seat’s `repoDelta` |
| **Missing proof** | G3 honest mutate on OpenCode-local after serve-attach fix; G2/G3 Claude-local as an alln seat; mid-tier (`7b`) G1+G2; Studio-class §11 B |

---

## 10. Slice ladder (candidate — **unauthorized**)

Not an implementation allowlist. No slice starts without a founder ruling.

| Id | Intent | Code? |
| --- | --- | --- |
| **OCL-S00** | **DONE (2026-08-07).** OpenCode-local pipe PASS on Air with `0.5b` — §0.3. | **None** |
| **OCL-S00b** | Bakeoff recorded (§0.4). Claude G2 mutate PASS on `0.5b`; gates defined. | **None** |
| **OCL-S01** | Detect + doctor: Ollama reachable; list local models; readiness Unavailable/Idle/Busy (**body-agnostic**) | Core |
| **OCL-S02a** | Setup verb: additive OpenCode provider wiring, reversible, non-clobbering | Core/CLI |
| **OCL-S02b** | Claude-local: per-run env isolation + meter strip + seating path (design then code) | Core/AgentOS |
| **OCL-S03** | `ModelDiscoveryProvider` for Ollama tags → opt-in seats, `.discovered`, local provenance; body chosen at enable | Core |
| **OCL-S04** | Readiness surface in `alln models` / `doctor` — three states only | Core/CLI |
| **OCL-S05** | Turn timing for slow local loads — **only if measured** | AgentOS |
| ~~**OCL-S06**~~ | ~~Capacity strip row~~ — **cancelled for v1** | — |

Depends on sibling packets: Ambient Dirty honesty; OpenCode Serve Attach.

Out of ladder: scarcity auto-routing, remote `OLLAMA_HOST`, Ollama Cloud,
multi-host, crowning one body.

---

## 11. Works Test (target)

Three tiers. Never report a lower tier as a higher one.

**A — Plumbing / pipe (any Apple Silicon — required), per body:**

```text
Given: Ollama up; canary model passes G0 (+ G1 if claiming tools);
       body wired (OpenCode provider merge OR Claude-local env isolation)
When:  alln models verify <local_model_id>
       alln run "<one-file bounded edit>" --model <local_model_id> --json
Then:  seat verifies; run completes or fails with classified reason;
       repo delta / dirty truth is honest; provenance local;
       paid seats of that driver family unaffected; readiness never speaks quota
```

Prove **A** for OpenCode-local and for Claude-local separately.

**B — Capability / ICP feel (Studio-class RAM — optional sales proof):**

```text
Given: coding-class local model at ≥64k served context (mid-tier+ on Air for
       dry rehearsal; Studio for the claim)
When:  same bounded repair on local seat vs paid seat; lead re-runs the gate
Then:  local work stands on the gate — not on its own report
```

**C — Model gate regression (dogfood):** G0→G1 scripted on each pulled tag
before filing “alln local is broken.”

**Negative tests:** Ollama stopped ⇒ Go seats and paid Claude unchanged; no
park/substitution mentions Ollama.

Proof waiver: none claimed. Nothing here is shipped as product.

---

## 12. Risks

| Risk | Response |
| --- | --- |
| **`enabled_providers` clobber** (OpenCode) | Merge-only setup verb; before/after fixture; documented undo. |
| **Claude env bleed** into paid Anthropic or reverse | Per-run env only; fail closed; never park Claude for Ollama faults; negative proofs. |
| **Claude-local meter lies** (200k / costUSD / firstParty) | Strip or relabel for `ollama_local`; never vendor-shaped. |
| **Model-dependent tool bugs** blamed on Air / alln | G0→G3 ladder; attribute per §0.4. |
| **Stall watchdog vs cold local load** | OCL-S05 only if measured; do not widen globally. |
| **OpenCode `:4096` serve busy** | [`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md). |
| Shared OpenCode lane local ↔ Go | Ceilinged at 1; diagnostics must not read as vendor limit. |
| OpenCode CT weaker on local | Stay on CT owners; re-run gates. |
| Served context &lt; 64k | §7.4; warn-and-allow on explicit pin. |
| Scope creep Cloud / LAN / model manager | §4. |
| Building both body ladders before one Works Test | §0.1.8 — serialize adapters; share detect/readiness. |

---

## 13. Open questions (remaining)

**Closed by founder:** capacity vs readiness; Idle/Busy; `ollama_local`; mini
proves pipe / Studio ICP; OCL-S00; Ollama Cloud / LAN out; **both agent bodies**;
model gate ladder; dev-builds-only until ready.

Still open (Spec Review may recommend; founder decides):

1. Discovery posture: every pulled tag offered opt-in, or only explicitly seated?
   Lean: discover all, enable none by default, Code-gate on §7.3 + G1.
2. Served-context ≥64k: hard automatic Code gate (yes per §0.2) — confirm copy
   for warn-and-allow on explicit pin.
3. Implementation sequence: OpenCode-local productization first (OCL-S00 exists)
   vs Claude-local first (ICP stay-in-tool)? Lean: **shared S01 first**, then
   **S02a (OpenCode)** in parallel design with **S02b (Claude)**; ship whichever
   isolation story is ready — do not block Claude on OpenCode serve-attach or
   vice versa beyond shared detect.

---

## 14. Done when (packet exit — future)

- [ ] A local Ollama model does real bounded mutating work as an **OpenCode**
      seat, proven by a gate the seat did not author
- [ ] A local Ollama model does real bounded mutating work as a **Claude Code**
      seat, same standard
- [ ] Local provenance and readiness never borrow quota / Anthropic meter words
- [ ] Ollama absent leaves every paid seat untouched (negative proof per body)
- [ ] OpenCode setup additive/reversible; Claude-local env per-run only
- [ ] Ollama Cloud remains out of product
- [ ] Help + doctor teach detect → choose body → seat → run; G0–G3 for dogfood
- [ ] Promote keepable law; archive this packet

---

## 15. Related archive / do-not-resume

- [`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md) —
  shelved multi-host execution fabric. This packet is **single-Mac local
  inference** under Claude Code and/or OpenCode.
- `docs/archive/2026-06-13-allnighter-pivot/strategy/Allnighter-Local-AI-Worker-Opportunity.md`
  — historical thesis. Keep the market read (operating layer, not runtime
  layer); discard the night-shift positioning and the read-only-forever framing.

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| Local / Ollama seats (Claude Code and/or OpenCode) | This packet + `ModelCatalog` / `ModelDiscoveryProvider` |
| OpenCode driver / serve lifecycle | AgentOS `OpenCodeServeClient.swift` + [`OpenCode_Serve_Attach.md`](OpenCode_Serve_Attach.md) |
| Claude-local isolation / env | This packet §0.4 / §4 / §7.6 — code SSOT TBD |
| OpenCode Go subscription meter | [`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md) |
| Abundant vs scarce seat selection | [`Scarcity_Aware_Routing.md`](Scarcity_Aware_Routing.md) §3 first |
| Any capacity signal attribution | [`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) |
