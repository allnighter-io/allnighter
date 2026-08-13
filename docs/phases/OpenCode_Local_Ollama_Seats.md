# Ollama Local Seats (OpenCode + Claude Code)

Status: **Ladder built and dogfooded live (2026-08-13).** OpenCode-local Works
  Test **A satisfied**. Claude-local still needs its own **A** proof. **B**
  unproven on this hardware. OCL-S05 unbuilt (measured, not assumed). Founder
  rulings locked (§0.1), including **both agent bodies**, the **delegation
  asymmetry**, and **explicit local `--pm` allowed** (2026-08-13, §0.1.14 —
  supersedes any local-cannot-lead reading). Live dogfood §0.3; bakeoff §0.4;
  2026-08-13 findings §0.6.
  **Workflows and market segments: §2.4–§2.8 — the reason this packet exists.**
Revised: 2026-08-13 (v9 — two-state per-seat readiness; Busy cut because it
  inverted the word. Remaining: Claude-local A, §11 B, OCL-S05)

Owner: unassigned (AllnighterCore catalog + model discovery; AgentOS for
OpenCode serve attach / local turn timing / Claude-local env isolation as scoped)
Created: 2026-08-07

**Headline claim: a frontier seat plans; local seats execute — under one write
lock, with honest outcomes.** (§2.4)

**Split out of this packet (founder, 2026-08-09) — packet 1 of 3:**
[`Context_Firewall.md`](Context_Firewall.md) (packet 2) — the egress boundary is
not Ollama-specific and earns its own packet.
[`Second_Mac_Bench.md`](Second_Mac_Bench.md) (packet 3) — v2, second host / LAN.

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
[`OpenCode_Serve_Attach.md`](../archive/phases/OpenCode_Serve_Attach.md) (leftover `:4096` attach —
blocks all OpenCode seats including local),
[`Scarcity_Aware_Routing.md`](Scarcity_Aware_Routing.md) (abundant vs scarce;
read its §3 rejected list before proposing any auto-routing),
[`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) (a signal answers
only for the source that produced it),
[`OpenCode_Long_Run_Continuity.md`](../archive/phases/OpenCode_Long_Run_Continuity.md) /
[`OpenCode_Completion_Truth_Followup.md`](../archive/phases/OpenCode_Completion_Truth_Followup.md)
(OpenCode completion honesty — local models stress it harder, see §12),
[`Ambient_Dirty_Run_Outcome.md`](../archive/phases/Ambient_Dirty_Run_Outcome.md) (`--no-commit` /
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

**Ladder shipped and dogfooded live on Air (2026-08-13).** OCL-S00–S04 and
OCL-S07–S08 are in the tree. A coding-class gated local repair passed
(`c88a0383`, gpt-oss:20b). Honesty gaps that blocked S01+ are closed in code
(outcome `7a7f8117`; leftover-serve reclaim `53c14465`; Zen scoping `3d0ae06b`;
Claude-local isolation `567acaee`). Remaining is not “code unauthorized”:
Claude-local still needs its own Works Test **A**; **B** is unproven on this
hardware; OCL-S05 stays unbuilt because cold load of gpt-oss:20b was 20.9s
against a 120s first-activity budget (warm 0.6s) — larger models on larger
machines are unmeasured. Do not project a number.

### 0.1 Founder rulings — binding

**2026-08-07**

1. **Readiness, not capacity strip.** Local availability is **not**
   `benchSourceOrder` / subscription capacity. `Product_Vocabulary.md` capacity
   stays vendor-printed quota. Local surface: `alln models` / `doctor`.
2. **~~v1 readiness states are three words only: `Unavailable` | `Idle` |
   `Busy`.~~ Superseded 2026-08-13 (§0.1.15).** Do not implement Idle or Busy.
   Local readiness is two states only, **per seat:** Available or Unavailable.
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

**2026-08-09 (workflows + headline)**

11. **The delegation asymmetry is the thesis.** Frontier models can act as
    project managers — decompose, decide, delegate, judge, route. Local models
    cannot yet, so today *only the human* can route work to a local model. The
    bridge is what lets a frontier PM command abundant local labor, which is
    where the automation ceiling actually lifts. Full argument §2.4. **The
    marketing hook "turn your AI into the PM" stays rejected (2026-08-06)** —
    §2.4 is architecture, not positioning.
12. **Model-vs-model benchmarking is out** (§4). Tokens/sec and "which model
    won" is theater, returns a screenshot, and collides with *alln never rates
    itself* + the no-projections law. Side-by-side survives only as **option
    generation** (two patches, keep one), which is not local-specific.
13. **Three-way split (approved 2026-08-09).** Build order:
    **(1) nail Ollama seats — this packet, no firewall;
    (2) [`Context_Firewall.md`](Context_Firewall.md);
    (3) [`Second_Mac_Bench.md`](Second_Mac_Bench.md).**
    Split test applied — each has a different truth owner, a different
    characteristic failure, and a different Works Test:

    | Packet | Truth owner | Characteristic failure | Works Test |
    | --- | --- | --- | --- |
    | Ollama seats (here) | Ollama runtime + agent body | model cannot hold the job; serve busy; meters lie | a local seat does bounded mutating work, honestly |
    | Context Firewall | the dispatch boundary | a crossing unrecorded; a silent promotion | dispatched payload == ledger, byte for byte |
    | Second Mac | a network + a second host | host identity, remote write lock, cross-machine orphans | a remote seat works under a lock you can prove |

    The firewall left because **it is not Ollama-specific** — the boundary is
    valuable with any local body, and would matter even if Ollama vanished.
    What stays here is the *why for Ollama itself*: delegation asymmetry (§2.4),
    sweep (§2.6.1), two-tier teams (§2.6.2), Loop with local execution seats.

**2026-08-13 (local lead pin)**

14. **Explicit `--pm` of a local Ollama-backed seat is allowed (binding;
    supersedes any local-cannot-lead reading).** Refusing it
    (`LOOP_LOCAL_SEAT_CANNOT_LEAD`) is out — removed `ab86226e`. Project law:
    sensors inform, they never block. The only refuse-class items are a parked
    driver, a disabled model, an unknown model id, and the per-root write lock.
    Provenance is not one of them. Owner intent wins. Allnighter does not
    decide which model is worthy of leading — users have different hardware and
    different jobs, and a capable local model on a large machine must not be
    refused by the same rule that would refuse a tiny one. §7.7 already: the
    user selects; Allnighter does not auto-prefer. Disclose local provenance
    and the served context window (if known) once, then proceed — same
    warn-and-allow as §0.2 on an explicit `--model` pin below the context gate.
    No nag, no repeated warning, no confirmation prompt.
    `roundLog.executionOutcome` stays Allnighter-owned measurement of what
    happened, for paid and local seats alike — that is not a judgment about who
    is allowed to work.

**2026-08-13 (readiness — two states, per seat)**

15. **Cut the three readiness words.** Local Ollama readiness is two states
    only: **Available** or **Unavailable**. **Busy is removed.** Scope is
    **per seat**, not per runtime: a seat is Available when Ollama is
    reachable **and** that seat's tag is pulled locally. Ollama down makes
    every local seat Unavailable — no special casing. Failure to observe is
    not Available; never a guessed Available (that law stands). Keep calling
    `/api/ps`: served context still feeds the §7.3 gate and the local `--pm`
    disclosure. Removing Busy does not remove the probe. Local readiness
    stays out of the capacity strip and `benchSourceOrder`. Do **not** add a
    latency or warm/cold indicator; if that is ever wanted it must be
    labelled latency and measured, not smuggled back in as a state word.
    S01b doctor and S04 models go through **one** projection.

    **Why Busy was cut (not a simplification):** Busy meant a model resident
    in memory, and resident is the **fast** state. Measured on this host
    2026-08-13: warm first-byte **0.6s**, cold **20.9s**. So Busy read as a
    scarcity warning while actually marking the quickest case, and Idle
    marked the slow one. Busy also never meant work would be refused —
    Ollama queues. The word gated no decision and inverted the meaning it
    borrowed from vendor capacity. That is why it goes.

### 0.1.1a Order of execution (founder, 2026-08-09)

Packets execute **end to end**, in document order. Ladder position is not a
priority signal and must not be reshuffled to argue sequencing strategy. New
workflow slices are therefore **appended** (§10 OCL-S07+), and "build now" is
expressed by the headline marker, not by moving rows.

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
Owned with [`OpenCode_Serve_Attach.md`](../archive/phases/OpenCode_Serve_Attach.md).

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

G2.5 (recommended, 2026-08-13) compile / gate the mutation
      → write tool firing is not the result compiling (qwen3:8b G2-pass,
        then Swift 2 that did not compile while claiming applied)

G3  alln run --model <seat> same mutate
      → bench path (serve attach, outcome honesty, provenance)
```

**G0 is necessary and cheap. G1 is the missing filter** that would have saved
the first bakeoff. A model that only passes G0 must not be sold as a Code seat.
Do not jump G0 → G3 and call alln red when G1 was never green.

Air canary for plumbing: **`qwen2.5:0.5b`**.

**Mid-tier (2026-08-13, this host — measured):** §0.4.2 named
`qwen2.5-coder:7b` as the next mid-tier candidate. It **fails G1** here, as do
`qwen2.5-coder:1.5b` and `:3b`: they emit tool calls as **text** on both native
`/api/chat` and OpenAI-compat `/v1`. Tags that **pass G1** with structured
`tool_calls` on this host: **`qwen3:8b`** and **`gpt-oss:20b`**. Advertised
`tools` capability is lie-prone (see §9): `qwen2.5-coder:7b` declares
`capabilities.tools`, ships a tools template, and still text-fakes. §7.3’s
**advertises-tools AND passes-G1** is load-bearing.

**G2 does not predict G3.** `qwen3:8b` cleared G0, G1, and G2, then produced
Swift 2 syntax that did not compile while reporting the change was applied and
ready for review. Recommended rung between G2 and G3: the write tool firing is
not the result compiling.

**§7.3 gate 4 is meetable** on this class of machine. Served context is a
**per-model architectural ceiling**, not a category wall: `qwen3:8b` caps at
40960; `gpt-oss:20b` serves 65536 and meets the gate. The macOS Ollama app
ignores `launchctl` env and supervises its own serve; its context length lives
in the **app’s own settings**.

Studio / ≥64k served context remains the capability/ICP proof (§11 B), not the
pipe gate. **B stays unproven on this hardware.**

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
| Ladder **S01–S04, S07–S08** in tree? | **Yes — built and dogfooded live (2026-08-13).** Commits in §10. |
| Works Test **A** (OpenCode-local)? | **Satisfied.** |
| Works Test **A** (Claude-local)? | **Not yet** — isolation code shipped (`567acaee`); still needs its own A proof. |
| Works Test **B**? | **Unproven on this hardware.** Do not claim Studio-class capability. |
| OCL-S05 (slow-load timing)? | **Unbuilt.** Measured on this host: gpt-oss:20b cold **20.9s** vs 120s first-activity budget; warm **0.6s**. Larger models on larger machines are unmeasured — do not project a number. |
| Do we know the architecture? | **Yes:** Ollama = inference; bodies = Claude Code **and** OpenCode; readiness Available/Unavailable per seat, outside capacity strip; signal `ollama_local`. Explicit local `--pm` allowed (§0.1.14). |

### 0.5 Blocker list (2026-08-13 — closed vs remaining)

**Closed in this ship batch** (do not re-open as “unauthorized”):

1. Spec Review leans in code: two-state per-seat Available/Unavailable
   (Busy cut — it inverted the word; §0.1.15); discovery list-all / enable-none;
   ≥64k automatic Code gate with warn-and-allow on explicit pin (S01–S04, S03).
2. `--no-commit` + dirty ⇒ false `completedWithoutChanges` — **fixed**
   `7a7f8117`.
3. OpenCode leftover `:4096` / serve-busy (the §0.3.2 defect) — leftover serve
   **reclaim** `53c14465`. Distinct from the two defects below.
4. Never treat terminal-run `identityAlive` pid as killable without `ps` —
   may be `alln serve`. **Ops law, still binding.** Not a remaining product
   slice. `53c14465` recycles leftover **opencode** serve only; never `alln serve`.
5. OpenCode CT unfinished — local still amplifies false-done prose. **Open as
   CT owner work**, not as a local-seat ladder slice. `roundLog.executionOutcome`
   stays Allnighter-owned (S07).
6. Claude-local isolation + meter honesty — **coded** `567acaee`. Remaining is
   Works Test **A for Claude-local**, not design.
7. Coding-class gated repair — **closed.** First passing gated local repair:
   a local **gpt-oss:20b** seat fixed `parsePs` (cloud residents), passed 25
   tests it did not author, committed `c88a0383` with the local seat credited
   as co-author.
8. Dev-build gate before productizing discovery/setup — **superseded by the
   2026-08-13 dogfood.** Discovery/setup shipped; “dev builds only until fully
   ready” (§0.1.10) still describes productization caution, not a missing slice.

**Two OpenCode defects the old §0.5 item 3 did not name** (neither is the
serve-busy defect in §0.3.2):

- With `:4096` **free**, `models verify` still failed because the opencode
  driver probe smoke-tests **OpenCode Zen**, so a remote provider’s rejection
  disabled a **local** seat — the §6.1 Never cell. **Fixed** `3d0ae06b`.
- A long-lived `opencode serve` **caches its model list**, so tags registered
  later are invisible to `alln` while visible to the CLI. **Fixed** `53c14465`.

**Still open (honest remaining, not “code unauthorized”):**

- Claude-local Works Test **A** (own proof; isolation is in tree).
- Works Test **B** — unproven on this hardware.
- OCL-S05 — **unbuilt, now measured not assumed.** Cold load of gpt-oss:20b
  was **20.9s** against a 120s first-activity budget on this host; warm
  **0.6s**. Larger models on larger machines are unmeasured. Do not project a
  number.
- Recommended G2.5 rung (§0.4.2): write-tool fire ≠ compiling.

Not blockers here (moved with the split): root-less dispatch and the egress
ledger → [`Context_Firewall.md`](Context_Firewall.md). Outcome honesty (old
item 2) no longer blocks that packet on a lying meter.

What v5 changed: both bodies as law; bakeoff §0.4; G0–G3 gates; Claude keep /
OpenCode keep; Spec Review OpenCode-only lean superseded.

What v6 changed: **delegation asymmetry** as the durable thesis (§2.4); segment
research incl. prior art (§2.5); **workflow catalog** (§2.6); horizon /
inversion argument (§2.8); model-vs-model benchmarking added to non-goals (§4).

What v7 changed: the **three-way split** (§0.1.13). Context Firewall — egress
policy, ledger, root-less dispatch, the regulated-tier market read — moved
whole to [`Context_Firewall.md`](Context_Firewall.md). Second Mac / LAN moved to
[`Second_Mac_Bench.md`](Second_Mac_Bench.md). This packet keeps the delegation
asymmetry, the segment read, sweep, two-tier teams, and the horizon argument,
and returns to a shippable scope: **detect · seat · honest run · both bodies**.

What v9 changed (2026-08-13): founder cut Idle/Busy. Readiness is Available |
Unavailable per seat. Busy inverted the word (resident = fast, 0.6s warm vs
20.9s cold; Ollama queues). `/api/ps` stays for served context. No latency
indicator. Doctor and models share one projection.

### 0.6 Live findings (2026-08-13) — several packet claims were already correct

1. **§0.4.2 mid-tier name.** `qwen2.5-coder:7b` was the named candidate. It
   fails G1 on this host (with 1.5b and 3b): text-faked tools on native
   `/api/chat` and OpenAI-compat `/v1`. `qwen3:8b` and `gpt-oss:20b` pass G1
   with structured `tool_calls`.
2. **Advertised tools is lie-prone** — belongs in §9. `qwen2.5-coder:7b`
   declares `capabilities.tools`, ships a tools template, and still
   text-fakes. §7.3 advertises-tools **AND** passes-G1 is load-bearing.
3. **§7.3 gate 4 is meetable.** Served context is a per-model architectural
   ceiling, not a category wall (`qwen3:8b` 40960; `gpt-oss:20b` 65536).
   macOS Ollama app ignores `launchctl` env and supervises its own serve;
   context length lives in the app’s settings.
4. **First passing gated local repair** closes old §0.5 item 7: gpt-oss:20b
   `c88a0383` (local seat co-author).
5. **G2 ⇏ G3.** `qwen3:8b` G0–G2 then non-compiling Swift 2 while claiming
   applied / ready for review. Recommend a rung between G2 and G3.
6. **§0.5 OpenCode blocker was incomplete.** Zen probe disabling a local seat
   (`3d0ae06b`) and leftover-serve model-list cache (`53c14465`) are distinct
   from §0.3.2 serve-busy.
7. **Founder ruling 2026-08-13 (binding):** a local seat may hold the Loop PM
   chair when explicitly pinned. Provenance is not a refuse-class. Sensors
   inform, never block; only parked driver, disabled model, unknown model id,
   and the per-root write lock refuse. Allnighter does not decide which model
   is worthy of leading. Earlier `LOOP_LOCAL_SEAT_CANNOT_LEAD` was wrong and
   was removed in `ab86226e`. Supersedes any local-cannot-lead reading.
   Full text §0.1.14.
8. **OCL-S05 stays unbuilt, measured not assumed:** gpt-oss:20b cold 20.9s /
   warm 0.6s vs 120s first-activity budget on this host. Larger models on
   larger machines unmeasured. Do not project a number.

---

## 1. One claim

With Ollama running and one tool-capable local model pulled, the user can put
that model on the bench as a **local seat** behind an agent body they already
use — **Claude Code and/or OpenCode** — and pin it with `--model`, the same way
they pin any other seat. No new inference stack, no claim that Allnighter runs
models, no crowning of a single local harness.

**And the claim that makes it worth building:** a frontier seat can then
*delegate to that local seat* — decompose, dispatch, and judge — so abundant
local labour is commanded by scarce judgment instead of by the user's hands
(§2.4). That is this packet's headline and it needs no new architecture:
`alln loop` already has the shape.

Keeping the frontier seat away from the source while it does that is a separate
packet ([`Context_Firewall.md`](Context_Firewall.md)) and **not** a prerequisite
here — local seats are worth shipping with `egress: open`.

Trusted workflow slice (target):

```text
ollama serve + tool-capable model pulled (passes G0; Code seats also G1)
  → Allnighter detects Ollama and lists local models (tools? context?)
  → user enables a local seat on a chosen body (claude_code | opencode)
  → provenance: local (ollama_local); readiness: Available | Unavailable (per seat)
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
| A model leaderboard | §0.1.13 — no tok/s, no model-vs-model verdicts. |

### 2.4 The delegation asymmetry — the durable claim

Frontier models became **project managers**. They decompose a goal, decide what
matters, delegate, judge the result, and route the next step. Local models are
not there yet — and PM capability is precisely the capability that arrives
**last**, because it needs long stable context, tool discipline sustained over
many turns, and judgment under ambiguity. Those are the first things to degrade
under quantization. Execution capability arrives first. Delegation arrives last.

| | Frontier seat | Local seat (today) |
| --- | --- | --- |
| Decompose · decide · route | **yes** | no |
| Judge a result | **yes** | weak |
| Apply a bounded, well-specified order | yes | **yes** |
| Grind 400 targets | economically no | **yes** |
| Marginal cost per step | metered | ~0 |
| Clock | resets, limits, parks | none |

**Without a bridge, the human is the router.** Every local task must be handed
over by a person, one at a time, because nothing local can be trusted to decide
what to hand over. That caps automation at human dispatch rate — which is why a
Studio full of weights still behaves like a chat toy.

**With a bridge, one paid planning turn commands many free execution turns.**
The paid cost of a fifty-step job collapses toward the cost of the plan. That is
not a speed claim or a quality claim; it is a change in what is economically
worth automating at all.

This is the shape [`alln loop`](../operations/Execution-Playbook.md) already has:
a strong lead steers and reviews, execution seats do the mutating work, exactly
one mutating worker per root. **Loop was specified before local seats existed
and needs no new architecture to accept one.** The local seat is the execution
seat Loop was always describing.

**When local PMs arrive, this packet does not expire.** The PM seat's provenance
changes from paid to local; nothing else moves — same write lock, same run
contract, same egress ledger, same artifacts, same honesty rules. The gap that
closes is capability. The gap that does not close is the need for *something* to
delegate, and for a bench that records what happened. We are building the half
that survives (§2.8).

### 2.5 Who runs local (segment read, 2026-08-09)

External research, not SSOT. Recorded because it changes what to build first.

| Segment | What they have | Unsolved today |
| --- | --- | --- |
| **Quota-squeezed power user** (our dogfood) | Paid CLIs + a Mac | Reading files burns paid context and quota. Hand-rolled workarounds already exist (prior art below). |
| **Studio / local maximalist** | 128–512 GB unified memory | The machine is a **chat toy** — one model, one TUI, one session. Abundance with no consumption mechanism. |
| **Regulated** (ITAR / HIPAA / SOX) | Mandate + budget | **All-or-nothing.** Every shipping answer is "go fully on-prem and eat the capability gap." Nobody offers *keep the frontier model, deny it the source*. |
| **Privacy pragmatist** (larger than regulated) | Proprietary code, no mandate | Same all-or-nothing, by preference rather than policy. |
| **Cost-constrained indie / non-US** | Free local, rationed cloud | Same as row 1 with a harder floor. |

**Prior art — the wedge is already being hand-rolled.** `ask-local`
(github.com/alisorcorp/ask-local, ~47 stars, originated in an r/LocalLLaMA
thread) delegates file-reading from Claude Code to a local LM Studio model so
that "file contents stay on your machine; only the final answer enters your
Claude session." Its own README lists the jobs: pattern inventory, content
audits, triage, log analysis. It is a single MCP tool — LM Studio only, one
direction, no run contract, no queue, no write lock, no record of what crossed.
**Read this as validated demand with a hobby implementation**, not as a
competitor. Its stated limits (30B-class quality lags on subtle correctness;
degrades well below advertised context) match our G1/§7.4 findings exactly.

**Field convention worth adopting verbatim:** route per **task**, not per
workflow. Local for extraction, classification, formatting, high-frequency
routine, and privacy-bound reads; frontier for hard reasoning, long context, and
quality-risk output. This is a *user-selected team shape*, never an automatic
router — `Scarcity_Aware_Routing.md` §3 still forbids standing preference rules.

**Batch is a known open wound.** Published practice is that teams burn hundreds
of engineering hours on fragile for-loop + retry + checkpoint scripts. Nothing
does this for *coding agents*, local or otherwise (§2.6.1).

### 2.6 Workflow catalog

The reason to build this packet. Each row states what is impossible or painful
today, not what is faster.

#### 2.6.0 Context Firewall — **moved out (§0.1.13)**

The egress boundary — `open | abstracted | local_only`, the egress ledger,
root-less dispatch, the regulated-tier market read, and the *auditable, never
sanitised* honesty bound — now lives in
[`Context_Firewall.md`](Context_Firewall.md).

It left because it is **not Ollama-specific**: the boundary is valuable behind
any local body and would matter even if Ollama vanished. It is **not a
prerequisite for this packet** — local seats ship first, with `egress: open`.
Do not re-add egress policy, ledger, or root-less dispatch here.

#### 2.6.1 Sweep — bulk work with a resumable queue

One order, N targets, checkpointed, **resumable**. 400 files, the model dies at
250, you resume at 250. That resume property is what the hundreds of hand-rolled
engineering hours are actually spent on.

This is the Studio's missing consumption mechanism, and it is judgment at a
volume nobody would ever buy: *does every doc still agree with
`Product_Vocabulary.md`?* *Is this test tautological (the `measurement_auditor`
question, applied to every test file rather than the twelve in the diff)?*
Between `grep` (free, deterministic, dumb) and a frontier seat (sharp, rationed)
there is a gap that only abundant local labour fills.

Alln already owns run ids, artifacts, the journal, and the write lock. Sweep is
a verb over machinery that exists.

#### 2.6.2 Two-tier teams — frontier judgment × local labour

| Direction | Shape |
| --- | --- |
| **Local drafts → frontier judges** | N cheap candidate patches; the paid seat picks and repairs one. Volume from the free seat, quality floor from the expensive one. Option generation with local economics. |
| **Frontier plans → local executes** | The lead writes a precise bounded work order; local seats apply it across many sites. This is `alln loop` unchanged (§2.4). |
| **Local as tripwire** | Local re-reads each commit continuously and escalates to a paid seat only on a smell. Paid attention is scarce; local attention is free. |

#### 2.6.3 Continuity across the boundary

Today, switching from a paid model to a local one means a new session and
re-pasting the context. Hit a limit, switch, re-explain. `ask-local` does not fix
it; `ollama launch` does not; editor extensions do not. **Alln threads are
continuous across seats — change the model mid-thread and keep the context.**
Small surface, felt daily, and it falls out of the existing thread model rather
than needing new architecture.

#### 2.6.4 Standing orders on abundant labour

`alln serve` is already a background scheduler. A local seat is the only seat
schedulable without a quota conversation: every commit, every hour, every branch.
Framed as **standing orders**, never as the banned overnight pitch. Escalation to
a paid seat is by exception and always disclosed.

#### 2.6.5 `alln models gate <tag>` — the ladder as a product

When V4-Flash-class then V4-Pro-class weights land locally, every user's question
becomes *"is my local model good enough for this job yet?"* Today they burn an
afternoon finding out. The G0→G3 ladder (§0.4.2) already answers it and is
currently framed as internal dogfood. Shipped, it accumulates **the user's own
observed pass/fail per model per job class** — a personal asset no benchmark site
has, and the thing worth posting instead of tok/s.

Stays legal: observed pass/fail on the user's own gates is a **fact**, not a
score, a rating, or a projection — same precedent as the Cost Advisor's
retrospective-usage-only rule. It does not rank models against each other and it
never rates Allnighter (D5).

### 2.7 What to build now

Ranked by *unavailable today*, not by effort. Execution stays document order
(§0.1.1a); this is the packet's identity, not its schedule.

1. **An honest local seat** — §0.5 remaining is Claude-local **A**, **B**, and
   OCL-S05; the lying-meter / leftover-serve / gated-repair blockers are closed.
2. **Loop with local execution seats** (§2.6.2) — the headline demonstrated
   rather than argued, and the proof that the thesis needs no new architecture.
3. **Sweep** (§2.6.1) — the workhorse; turns abundance into output.

Everything else in §2.6 is real but follows these. The Context Firewall is
packet **2 of 3** and does not gate any of the above
([`Context_Firewall.md`](Context_Firewall.md)).

### 2.8 Horizon — why this survives the inversion

Today: local is cheap and weak, frontier is sharp and scarce. That is closing
fast — open-weight coding models now sit within single-digit points of frontier
on SWE-Bench-Verified-class evals and near parity on simpler coding evals, and
V4-Pro-class weights already fit the largest Studios. Assume the capability gap
substantially closes inside this horizon rather than betting against it.

When it does, the asymmetry inverts: local becomes **sharp and abundant**, paid
becomes marginally sharper and still scarce. At that point:

- A **router** loses its reason to exist — there is less to route around.
- A **bridge** loses value as the banks converge.
- **Provenance, honesty, the write lock, and the egress ledger do not.** The
  question stops being *which model* and becomes *did the work actually happen,
  and can I prove what crossed which boundary.*

Allnighter is a bench, not a bridge. Build the parts that outlive the gap:
attribution, completion truth, one mutating worker per root, and a record of
every crossing. Those are the same items already sitting in §0.5 as blockers —
which is the argument for doing them regardless of how local capability lands.

Market note (external, non-binding): 256/512 GB Studios went refurbished-only in
March 2026 on memory supply; large-memory Macs are expected to reopen with M5
Ultra late 2026. The ICP is supply-constrained *right now* and widens later —
another reason the durable half is the right thing to build first.

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
- **Model-vs-model benchmarking.** No tokens/sec, no "local vs Claude" verdicts,
  no leaderboard (§0.1.12). It is theater, it returns a screenshot, and it
  collides with *alln never rates itself* and the no-projections law. Only the
  user's own observed G0–G3 pass/fail is recorded, and only for their own tags
  (§2.6.5).
- **Egress policy, egress ledger, or root-less dispatch in this packet.** Moved
  to [`Context_Firewall.md`](Context_Firewall.md) (§0.1.13). Local seats ship
  with `egress: open`.
- **Second host / LAN / remote mutator.** Moved to
  [`Second_Mac_Bench.md`](Second_Mac_Bench.md) (v2). A remote `OLLAMA_HOST` as
  an inference URL only is that packet's question, not this one's.

---

## 5. Current state (verified 2026-08-13 — binding over early assumptions)

### 5.1 Live code

| Fact | Where | Why it matters |
| --- | --- | --- |
| Driver `opencode` invokes `opencode run --attach http://127.0.0.1:4096 -m {{model}}`, `maxConcurrentSpawns: 1`, `timeoutSeconds: 1800` | AgentOS `Catalog/catalog.json` | OpenCode-local is a model **label**, not a new driver. Concurrency ceiling exists. |
| OpenCode models are ids like `model_opencode_deepseek_v4_pro` with label `opencode-go/…` | AgentOS `catalog.json` + overlay | **Provider is inside the label.** Local = `ollama/<tag>`, not a Go seat relabelled. |
| `alln models add --driver <id> --name <n> --model-label <label>` then `verify` | `ModelsCLI.swift`, `ModelCatalog` | OpenCode-local seat (OCL-S00). Claude-local seating path exists (`567acaee`); Works Test A for Claude-local still outstanding. |
| `ModelOrigin.discovered` + Ollama `/api/tags` provider | `ModelDiscoveryProvider` / S03 `90151f66` | Body-agnostic list, body-specific enable; cloud rows excluded (`cfb32fe7`). |
| Capacity tiers meter **paid** subscriptions only | `CapacityAcquisition.swift` | Local stays readiness, not strip (§7.5). |
| Claude Code paid seats use `claude_code` | catalog | Claude-local must share driver carefully: env isolation + provenance, never capacity bleed. |

### 5.2 This host (honest, and it is not the ICP)

```text
Mac16,13 · 32 GB unified memory · macOS 15.6.1
ollama 0.32.x (macOS app supervises serve; ignores launchctl env;
  served context length is the app’s own setting)
pulled (this host, 2026-08-13): qwen2.5:0.5b; qwen2.5-coder:1.5b, :3b, :7b
  (all three coder tags fail G1 — text-fake tools despite advertised tools);
  qwen3:8b (G1 pass; served context cap 40960); gpt-oss:20b (G1 pass;
  served 65536; meets §7.3 gate 4)
opencode · enabled_providers includes opencode-go + ollama
Claude Code · local isolation in tree (`567acaee`); alln A proof not yet
```

Consequences:

1. **Served context is per-model, not a host category.** 32 GB does not imply
   every tag is stuck at 4k. `qwen3:8b` caps at 40960; `gpt-oss:20b` serves
   65536. Automatic Code offers stay gated on served ≥64k; explicit `--model`
   warn-and-allow (§0.2).
2. **0.5b is the Air pipe canary** — enough for G0/G2 plumbing; not capability.
3. **`qwen2.5-coder:7b` is not the mid-tier Code seat on this host.** It fails
   G1 with 1.5b/3b. Do not treat that as “Air cannot do local.” G1 passers here:
   `qwen3:8b`, `gpt-oss:20b`.
4. **`enabled_providers` clobber risk remains** for OpenCode setup verbs (§12);
   S02a is merge-only (`fab645bf`).

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
[`OpenCode_Serve_Attach.md`](../archive/phases/OpenCode_Serve_Attach.md). Claude-local does **not**
share that port — different isolation hazard (Anthropic env / keychain), not
serve-busy.

---

## 7. Product law (candidate)

### 7.1 Provenance

| Provenance | Meaning | Availability language |
| --- | --- | --- |
| OpenCode remote (Go / Zen) | Vendor plan models | Subscription windows via `opencode_go` |
| Claude / Anthropic paid | Vendor plan models | Existing Claude capacity story |
| **Local Ollama** (any body) | Models pulled on this Mac | Available \| Unavailable (per seat) |
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
   **Load-bearing (2026-08-13):** advertised `tools` is lie-prone. A tag can
   declare `capabilities.tools` and ship a tools template and still text-fake
   (`qwen2.5-coder:7b` on this host). Advertises-tools without G1 is not a
   Code seat.
4. Effective **served** context ≥ 64k for automatic Code offer; warn-and-allow
   on explicit `--model` (§0.2). **Meetable:** this is a per-model architectural
   ceiling, not a category wall. On this host `qwen3:8b` caps at 40960;
   `gpt-oss:20b` serves 65536 and meets the gate. macOS Ollama app settings own
   the served length (not `launchctl` env).

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
standing rule (§3 of Scarcity packet). The same law applies to Loop `--pm`:
the user selects the lead, including a local Ollama-backed seat. Allnighter
discloses local provenance and the served context window when known; it does
not refuse.

### 7.8 Egress policy — moved out

Egress policy (`open | abstracted | local_only`), the egress ledger, and the
fail-closed refusal are now candidate law in
[`Context_Firewall.md`](Context_Firewall.md) (§0.1.13). Nothing in this packet
changes what a seat may read. Local seats ship with `egress: open`.

One law that stays here because it is about *provenance*, not egress: a local
seat's answer is attributed to the user's machine (`ollama_local`), and that
attribution must survive whatever boundary policy is in force.

---

## 8. Module sketch (candidate owners — not an allowlist)

| Concern | Likely home |
| --- | --- |
| Detect Ollama; `/api/tags` + `/api/ps` | AllnighterCore — pure client + parser (body-agnostic) |
| Project local tags → candidate seats | `ModelDiscoveryProvider` — first real provider |
| OpenCode: ensure `11434/v1` provider | Setup verb — **merge** `enabled_providers` + `provider.ollama` |
| Claude-local: per-run Anthropic-compat env | AgentOS / `claude_code` spawn path — isolation + meter strip |
| Dispatch | Existing `opencode` / `claude_code` drivers |
| Readiness surface | `alln models` / `doctor` — Available \| Unavailable per seat |
| Capacity strip row | **Cancelled for v1** |
| Sweep queue: N targets, checkpoint, resume | Run/artifact layer; reuses run ids + `ArtifactProjector` |

---

## 9. Truth owner / lie-prone layers

| | |
| --- | --- |
| **Truth owner** | Ollama `/api/tags` + `/api/ps` for local runtime; agent-body turn outcome for run truth; `ModelCatalog` for seat identity and provenance |
| **Lie-prone** | Advertised context as served; **advertised `tools` capability / tools template as G1**; G0 pass sold as Code-ready; text-fake tools treated as harness bugs; OpenCode serve busy as model failure; OpenCode Zen probe failure as a local-seat defect; leftover serve’s cached model list as “tag missing”; Claude-local `costUSD` / 200k context / firstParty; `enabled_providers` clobber; 0.5b plumbing sold as Studio capability; ambient dirty / concurrent commits misread as the local seat’s `repoDelta`; **a sweep that skips targets and reports done**; G2 mutate sold as G3 / compiling |
| **Missing proof** | Claude-local Works Test **A**; Studio-class §11 **B** on this hardware; OCL-S05 on larger models / larger machines (unmeasured — do not project); recommended G2.5 compile rung |

---

## 10. Slice ladder (shipped 2026-08-13 except OCL-S05)

Code is in the tree. Remaining work is named in §0.5, not a blanket
unauthorized flag.

| Id | Intent | Code? |
| --- | --- | --- |
| **OCL-S00** | **DONE (2026-08-07).** OpenCode-local pipe PASS on Air with `0.5b` — §0.3. | **None** |
| **OCL-S00b** | Bakeoff recorded (§0.4). Claude G2 mutate PASS on `0.5b`; gates defined. | **None** |
| **OCL-S01** | Detect + doctor: Ollama reachable; list local models; readiness Available/Unavailable per seat (**body-agnostic**) | **DONE** — S01a observer `709c376a`; S01b doctor `92e1159f`; two-state per-seat 2026-08-13 |
| **OCL-S02a** | Setup verb: additive OpenCode provider wiring, reversible, non-clobbering | **DONE** — `fab645bf`; setup registers tags `b02304e0` |
| **OCL-S02b** | Claude-local: per-run env isolation + meter strip + seating path | **DONE in code** `567acaee`. Works Test **A for Claude-local still outstanding.** |
| **OCL-S03** | `ModelDiscoveryProvider` for Ollama tags → opt-in seats, `.discovered`, local provenance; body chosen at enable | **DONE** `90151f66`; gate-2 cloud filter `cfb32fe7` |
| **OCL-S04** | Readiness surface in `alln models` / `doctor` — Available/Unavailable per seat | **DONE** `9818d8da`; two-state 2026-08-13 |
| **OCL-S05** | Turn timing for slow local loads — **only if measured** | **UNBUILT.** Measured on this host, not assumed: gpt-oss:20b cold **20.9s** vs 120s first-activity budget; warm **0.6s**. Larger models on larger machines unmeasured. Do not project a number. |
| ~~**OCL-S06**~~ | ~~Capacity strip row~~ — **cancelled for v1** | — |
| **OCL-S07** | **Loop with a local execution seat, end to end** — frontier lead plans, local seat mutates under the per-root write lock (§2.6.2). Explicit `--pm` of a local seat discloses provenance + served context once and proceeds (never refuses). | **DONE** `dbef460c`; PM veto removal `ab86226e` |
| **OCL-S08** | **Sweep:** one order × N targets, checkpointed and **resumable**, one artifact; honest per-target outcome (no skipped-but-done) | **DONE** `6dcb1982` |

Honesty / isolation follow-ups in the same dogfood (not new ladder ids):
outcome honesty `7a7f8117`; Zen scoping `3d0ae06b`; leftover serve reclaim
`53c14465`; `parsePs` cloud residents `c88a0383` (gated local repair).

Appended per §0.1.1a — ladder position is not priority. §2.7 states the
headline; the packet still executes end to end.

Depends on sibling packets: Ambient Dirty honesty (landed `7a7f8117`);
OpenCode Serve Attach (leftover reclaim `53c14465`). OCL-S07 depended on
outcome honesty — landed.

Out of ladder: scarcity auto-routing, remote `OLLAMA_HOST`, Ollama Cloud,
multi-host, crowning one body, model-vs-model benchmarking (§4), egress policy
and root-less dispatch ([`Context_Firewall.md`](Context_Firewall.md)).

Not slices, recorded so they are not lost: continuity across the boundary
(§2.6.3) falls out of the existing thread model; standing orders (§2.6.4) are an
`alln serve` question, not a local one; `alln models gate` (§2.6.5) is a
productisation of §0.4.2 and should follow one real gated local repair
(**that repair landed** `c88a0383` — gate verb still unbuilt).

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

**A status (2026-08-13):** satisfied for **OpenCode-local**. Claude-local still
needs its own **A** proof (isolation is in tree; the pipe proof is not).

**B — Capability / ICP feel (Studio-class RAM — optional sales proof):**

```text
Given: coding-class local model at ≥64k served context (mid-tier+ on Air for
       dry rehearsal; Studio for the claim)
When:  same bounded repair on local seat vs paid seat; lead re-runs the gate
Then:  local work stands on the gate — not on its own report
```

**C — Model gate regression (dogfood):** G0→G1 scripted on each pulled tag
before filing “alln local is broken.”

**D — Sweep (OCL-S08):** N targets, kill the run mid-sweep, resume; every target
ends `done | failed | not-attempted`, never silently skipped-and-reported-done.

**Negative tests:** Ollama stopped ⇒ Go seats and paid Claude unchanged; no
park/substitution mentions Ollama.

Proof waiver: none claimed for Claude-local **A** or for **B**. OpenCode-local
**A** is satisfied. Do not report a lower tier as a higher one. **B stays
unproven on this hardware.**

---

## 12. Risks

| Risk | Response |
| --- | --- |
| **`enabled_providers` clobber** (OpenCode) | Merge-only setup verb; before/after fixture; documented undo. |
| **Claude env bleed** into paid Anthropic or reverse | Per-run env only; fail closed; never park Claude for Ollama faults; negative proofs. |
| **Claude-local meter lies** (200k / costUSD / firstParty) | Strip or relabel for `ollama_local`; never vendor-shaped. |
| **Model-dependent tool bugs** blamed on Air / alln | G0→G3 ladder; attribute per §0.4. |
| **Stall watchdog vs cold local load** | OCL-S05 only if measured; do not widen globally. |
| **OpenCode `:4096` serve busy** | [`OpenCode_Serve_Attach.md`](../archive/phases/OpenCode_Serve_Attach.md). |
| Shared OpenCode lane local ↔ Go | Ceilinged at 1; diagnostics must not read as vendor limit. |
| OpenCode CT weaker on local | Stay on CT owners; re-run gates. |
| Served context &lt; 64k | §7.4; warn-and-allow on explicit pin. |
| Scope creep Cloud / LAN / model manager | §4. |
| Building both body ladders before one Works Test | §0.1.8 — serialize adapters; share detect/readiness. |
| **Sweep reports done with targets skipped** | Per-target outcome is `done \| failed \| not-attempted`; §11 D resume test. |
| **Frontier-PM automation amplifies a weak local seat** | Delegation multiplies whatever the execution seat is. G1 gate stays mandatory before a seat is offered for Code work (§7.3). |
| **Betting against the capability gap closing** | §2.8 — build the durable half (provenance, honesty, lock, ledger) rather than router value. |

---

## 13. Open questions (remaining)

**Closed by founder:** capacity vs readiness; two-state per-seat Available/
Unavailable (Busy cut 2026-08-13 — it inverted the word); `ollama_local`; mini
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
4. **Second Mac / two-machine work** — moved to
   [`Second_Mac_Bench.md`](Second_Mac_Bench.md) (packet 3 of 3). Not an open
   question here; do not reopen LAN, remote mutators, or a remote
   `OLLAMA_HOST` inside this packet.
5. **Context Firewall questions** — root-less dispatch, ledger surface, and
   whether `abstracted` needs a per-run override — moved to
   [`Context_Firewall.md`](Context_Firewall.md) (packet 2 of 3).

---

## 14. Done when (packet exit)

- [x] A local Ollama model does real bounded mutating work as an **OpenCode**
      seat, proven by a gate the seat did not author — `c88a0383` (gpt-oss:20b
      `parsePs`; 25 tests it did not author)
- [ ] A local Ollama model does real bounded mutating work as a **Claude Code**
      seat, same standard — isolation shipped; **A** proof outstanding
- [x] Local provenance and readiness never borrow quota / Anthropic meter words
      — S02b `567acaee`; S04 `9818d8da`
- [x] Ollama absent leaves every paid seat untouched (negative proof per body)
      — S01b / S04
- [x] OpenCode setup additive/reversible; Claude-local env per-run only —
      S02a `fab645bf`; S02b `567acaee`
- [x] Ollama Cloud remains out of product — `cfb32fe7` / `c88a0383`
- [ ] Help + doctor teach detect → choose body → seat → run; G0–G3 for dogfood
      — doctor readiness shipped (S01b); G0–G3 teaching as a product surface
      (`alln models gate`) still unbuilt
- [x] **A frontier seat plans and a local seat executes, end to end, under the
      per-root write lock — the delegation asymmetry demonstrated, not argued
      (§2.4, §11 A + OCL-S07)** — `dbef460c`; explicit local `--pm` `ab86226e`
- [x] **A sweep survives a mid-run kill and resumes with no target silently
      skipped (§11 D + OCL-S08)** — `6dcb1982`
- [x] No leaderboard, tok/s figure, or model-vs-model verdict ships (§4)
- [ ] Promote keepable law; archive this packet — remaining: Claude-local **A**,
      §11 **B**, OCL-S05 (unbuilt; measured not assumed). This v9 revision
      records two-state per-seat readiness; archive when those three are honest or waived.

---

## 15. Related archive / do-not-resume

- [`Mac_Studio_LAN_Bench.md`](../archive/phases/Mac_Studio_LAN_Bench.md) —
  shelved multi-host execution fabric — now the input to
  [`Second_Mac_Bench.md`](Second_Mac_Bench.md). This packet stays **single-Mac
  local inference** under Claude Code and/or OpenCode.
- `docs/archive/2026-06-13-allnighter-pivot/strategy/Allnighter-Local-AI-Worker-Opportunity.md`
  — historical thesis. Keep the market read (operating layer, not runtime
  layer); discard the night-shift positioning and the read-only-forever framing.

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| Local / Ollama seats (Claude Code and/or OpenCode) | This packet + `ModelCatalog` / `ModelDiscoveryProvider` |
| Context Firewall, egress policy/ledger, root-less dispatch, "keep the frontier model away from my source" | **Not here** — [`Context_Firewall.md`](Context_Firewall.md) (packet 2 of 3) |
| Second Mac, Studio in the office, LAN, remote `OLLAMA_HOST` | **Not here** — [`Second_Mac_Bench.md`](Second_Mac_Bench.md) (packet 3 of 3) |
| Frontier seat delegating to a local seat; "why not just use the model directly" | This packet §2.4 (delegation asymmetry) — and `alln loop`, which already has the shape |
| Bulk / batch / sweep over many targets | This packet §2.6.1 + OCL-S08; resumability is the feature |
| Anyone proposing a local-vs-cloud benchmark, tok/s figure, or model ranking | §4 non-goals + §0.1.13 — refuse; only the user's own G0–G3 pass/fail is recorded |
| OpenCode driver / serve lifecycle | AgentOS `OpenCodeServeClient.swift` + [`OpenCode_Serve_Attach.md`](../archive/phases/OpenCode_Serve_Attach.md) |
| Claude-local isolation / env | This packet §0.4 / §4 / §7.6 — code SSOT `567acaee` |
| OpenCode Go subscription meter | [`OpenCode_Go_Capacity.md`](OpenCode_Go_Capacity.md) |
| Abundant vs scarce seat selection | [`Scarcity_Aware_Routing.md`](Scarcity_Aware_Routing.md) §3 first |
| Any capacity signal attribution | [`Vendor_Signal_Isolation.md`](Vendor_Signal_Isolation.md) |
