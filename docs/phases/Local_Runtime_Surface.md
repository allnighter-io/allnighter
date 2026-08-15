# Local Runtime Surface — make the local seats we already built reachable

Status: **READY FOR IMPLEMENTATION.** Founder-ruled 2026-08-14. Successor to
packet 1 ([`OpenCode_Local_Ollama_Seats.md`](../archive/phases/OpenCode_Local_Ollama_Seats.md),
archived 2026-08-13) — not a reopening of it.
Owner: unassigned (`ModelCatalog` discovery wiring + Mac CLI strip)
Updated: 2026-08-14
Created: 2026-08-14

**One line:** packet 1 shipped a working local seat pipeline and never connected
it to a command or a screen. A user with Ollama installed cannot find, enable,
or refresh a local model.

---

## 0. Standing

### 0.1 Founder rulings — binding (2026-08-14)

1. **A `LOCAL RUNTIME` section under CLIs**, listing `Ollama via <body>`.
2. **Section-level body selector**, not per-model. The body does not change
   answer quality — same weights, same runtime, same tokens. It is a harness
   preference, so it is one choice for all local models.
3. **Visible always — including to agents.** Every discovered tag appears in
   the GUI *and* in the agent-facing CLI surfaces, whether enabled or not.
4. **ON-by-default is dropped**, explicitly conditional on ruling 3. Founder:
   *"If you ensure Visible always even for agents then I don't really care about
   ON by default."*

**Therefore packet 1's `defaultEnabled = false` STANDS.** This packet reverses
no promoted law. `OllamaLocalModelDiscoveryProvider`'s *"discover all local
tags, enable none — that is a default, not a gate"* is upheld. The defect was
never the default; it was that **off currently means invisible.**

### 0.2 Decided by the implementing agent (reversible, founder deferred)

- **Default body when both are installed: `opencode`.** Nothing to fail closed,
  no fake meters to suppress, and already wired in `opencode.json` on the
  dogfood host. A section-level selector makes a wrong default one click.
- **Vocabulary lands in this slice**, not after (§6).

### 0.3 What exists today — verified 2026-08-14, not read from a doc

| Layer | State |
| --- | --- |
| `/api/tags` → `OllamaLocalDoctorReport` → `alln doctor` | **Works.** 7 tags, all `Available`, fresh. |
| `/api/ps` → served window → `ClaudeLocalIsolation`, `LoopLocalSeatPolicy`, `WorkerInvokerFactory` | **Works.** A seat that exists is correctly instrumented. |
| Anthropic-compat `POST :11434/v1/messages` | **200.** Claude Code body is real. |
| OpenAI-compat `POST :11434/v1/chat/completions` | **200.** OpenCode body is real. |
| `OllamaLocalModelDiscoveryProvider.discover()` | **0 production call sites.** Tests only. |
| `ModelDiscoveryRegistry.provider(for:)` | **0 production call sites.** Tests only. |
| `OllamaLocalSeatEnablePolicy.assessExplicitEnable()` | **0 production call sites.** Tests only. |
| `alln models enable <id>` | `ModelCatalog.setEnabled(id, true)` on an **existing** id. No `--body`. Never calls the enable policy. Cannot mint a seat from a tag. |
| `alln models add --driver <body> --model-label ollama/<tag>` | The **manual** seating path (`ClaudeLocalIsolation.seatingExample`). Documented; **not executed during this audit** — verify in S00. |
| `alln models --json` | 43 seats, **0 local**. |
| `alln menu --json` actions | `drivers`, `models`, `run`, `teams duplicate`, `teams edit`. No local, no `sweep`. |
| `alln opencode-local status` | `wired: true`, `enabledProviders: ["opencode-go","ollama"]`, `ollamaTagsObserved: **false**`, `ollamaModelIds` = 6 tags — **missing `qwen3.8:27b-mlx` pulled the same day**. A frozen snapshot. |
| Mac app | `grep -rl -i ollama Apps/AllnighterMac/Sources/` → **nothing.** Zero Ollama concept. |

**Consequence:** packet 1's Works Test A was proven through a path no user can
reach. That is the defect this packet closes — not the seat behavior, which is
sound.

### 0.4 Dogfood host facts (do not project to other hardware)

MacBook Air M4, 32 GB. `qwen3.8:27b-mlx` (18 GB, nvfp4, declares
`completion, vision, tools, thinking`): **10.1 tok/s**, cold load **22.5s**,
warm 0.6s. Ollama 0.32.12. Larger tags on larger machines are unmeasured
(OCL-S05 remains unbuilt — §7).

---

## 1. The claim

A user pulls a model with `ollama pull`. They open Allnighter. They see no
Ollama anywhere, conclude local models are unsupported, and leave. They never
reach the point of being confused about agent bodies.

The architecture is correct — Ollama is inference, not an agent body; `ollama
run` has no tool loop and cannot do mutating work (packet 1 §3). The user's
mental model is also correct — Ollama is where their models live. **The UI
currently sides entirely with the architecture.**

`Ollama via OpenCode` resolves both in three words: findable by the word the
user is looking for, and it names the pairing without a lecture.

---

## 2. Surface

### 2.1 The section

```text
LOCAL RUNTIME                                    via [ OpenCode ▾ ]
  Ollama · 0.32.12 · 7 models                                    ●
    Qwen3.8 27B          ollama/qwen3.8:27b-mlx        [ off ]
    gpt-oss 20B          ollama/gpt-oss:20b            [ off ]
    Qwen3 8B             ollama/qwen3:8b               [ off ]
    qwen2.5-coder 7B     text-fakes tool calls         [ off ]
    qwen2.5-coder 1.5B   too small for Code            [ off ]
```

Header states, by what is installed:

| Installed | Row |
| --- | --- |
| both bodies | `Ollama via OpenCode / Claude Code` + selector |
| OpenCode only | `Ollama via OpenCode` |
| Claude Code only | `Ollama via Claude Code` |
| neither | `Ollama · N models · needs OpenCode or Claude Code` — **no ready dot**, install action |

`LOCAL RUNTIME` is its own class, never a `READY` body row. A ready dot on an
Ollama row would promise it can run work, and a Team staffed with it would fail.

### 2.2 Advisory reasons, never gates

`OllamaLocalSeatEnablePolicy.allowsAutomaticCodeOffer` (advertises tools **and**
G1 structured `tool_calls` pass **and** served context ≥ 65536) becomes the
**display reason** for why a tag is not recommended — not a gate on enabling.
The toggle always flips. *Sensors inform, never block; explicit enable
discloses and proceeds.*

### 2.3 Filter

Only tags whose `/api/tags` `capabilities` include `completion` are candidates.
`ollama pull nomic-embed-text` is routine and an embedding model is never a seat.

### 2.4 Grouping

The OpenCode card carries 8 models today; local tags push it past 15 and it
grows on every `ollama pull`. Group by the namespace already in the id —
`opencode-go/`, `opencode/`, `ollama/`. Ships **with** the ingest, not after:
the ingest is what makes the card overflow.

---

## 3. New/changed semantic rules

1. **Discovery runs from a command.** `ModelDiscoveryRegistry` is invoked by a
   real code path. Discovery still never runs from catalog load.
2. **Discovered ≠ enabled ≠ seated.** Three distinct states, distinguishable in
   JSON, each with its own `nextAction`. An agent must never mistake a
   discovered tag for a runnable seat.
3. **The tag list is live, never a snapshot.** `opencode-local status` re-reads
   `/api/tags`. A tag pulled after setup appears without re-running setup.
4. **Body is chosen at enable**, section-wide, and recorded on the seat id
   (`OllamaLocalModelDiscoveryProvider.seatedID(tag:bodyDriverId:)`). The run
   journal records which body ran.
5. **Enabling nothing is a valid steady state.** Visibility is the guarantee;
   enablement is the user's.

---

## 4. Slice ladder

| Id | Intent | Code? |
| --- | --- | --- |
| **LR-S00** | Verify `alln models add --driver <body> --model-label ollama/<tag>` actually seats a runnable local model end to end, and whether a Team can staff that seat. **Blocks the rest** — if Teams cannot staff a local seat, that outranks this packet. | None (audit) |
| **LR-S01** | Wire discovery: `ModelDiscoveryRegistry` called from a real command; `alln models --json` lists discovered local tags as `discovered`, distinct from enabled, each with an enable `nextAction`. **Ruling 3 — the agent half.** | Core/CLI |
| **LR-S02** | `alln models enable <tag> --body <claude_code\|opencode>` routes through `OllamaLocalSeatEnablePolicy.assessExplicitEnable`, emits its disclosures, mints the seat. | Core/CLI |
| **LR-S03** | Live tag list: `opencode-local status`/recheck re-read `/api/tags`; new pulls appear with no re-setup. Kills the frozen `opencode.json` snapshot. | Core/CLI |
| **LR-S04** | Ingest `ollama/` seats onto the bench so they appear in `alln models` and on the OpenCode/Claude Code cards. | Core |
| **LR-S05** | Mac `LOCAL RUNTIME` section (§2.1), section-level body selector, advisory reasons, empty state. **Ruling 1, 2 — the human half.** | GUI |
| **LR-S06** | Group the model card by provider namespace (§2.4). | GUI |
| **LR-S07** | Vocabulary + help: `LOCAL RUNTIME`, *"Ollama provides the model; a CLI provides the tools"*, discovered/enabled/seated split (§6). | Docs |

Out of ladder: ON-by-default (ruling 4); an Ollama `DriverManifest` (packet 1
§3 — `ollama run` is a completion CLI, G0 only); an Allnighter-owned tool loop
over Ollama HTTP; residency/thrash and OCL-S05 (§7); anything in
`Context_Firewall.md` or `Second_Mac_Bench.md`.

---

## 5. Works Test

**A — a newly pulled model surfaces itself (the headline):**

```text
Given: Allnighter running, Ollama reachable
When:  ollama pull <a tag not previously present>
Then:  alln models --json lists it as discovered, with an enable nextAction
       the Mac LOCAL RUNTIME section lists it
       neither required re-running any setup command
```

**B — enable seats it in the chosen body:**

```text
When:  alln models enable <tag> --body opencode
Then:  the enable policy's disclosures are printed
       alln models --json shows a seat whose id encodes tag + body
       alln run against that seat completes, and the journal records the body
```

**C — negative proofs:**

```text
- an embedding-only tag never appears as a candidate
- a discovered-not-enabled tag is never runnable and is never reported as ready
- a tag failing allowsAutomaticCodeOffer is VISIBLE with a reason, and the
  toggle still enables it (sensors inform, never block)
- with neither body installed, the Ollama row carries no ready dot
- removing a tag with `ollama rm` removes it from the discovered list
```

**D — agent parity (ruling 3, blocking):** every state visible in the Mac
section is visible in `alln models --json`. A GUI-only affordance fails this
packet.

**Proof command:** `scripts/swift-test.sh --filter <TouchedTests>` per slice;
`bash scripts/check.sh` at closeout only.

**Missing proof / waiver:** none claimed. LR-S00 is an audit, not a waiver.

---

## 6. Vocabulary (promote at closeout)

- **Local runtime** — an inference engine (Ollama) that supplies models to
  agent bodies. Never itself a body, never a `READY` row, never a seat.
- **Ollama provides the model; a CLI provides the tools.** The one-line
  explanation of the pairing. Use verbatim.
- **Discovered / enabled / seated** — three states. Packet 1's law calls a
  pulled tag an `Available` *seat*, while `OllamaLocalSeatEnablePolicy` calls
  the body-bound thing the `boundSeat`. Two meanings of "seat" is the root
  cause of the dogfood host reading `Available` and concluding local worked
  while zero seats existed. Settle the split in LR-S07 and amend
  `Project_Laws.md` §Local Ollama seats accordingly.

---

## 7. Not in this packet

- **Residency / thrash.** Ollama holds ~1–2 models resident; alln fans out in
  parallel. Three local seats on three tags = repeated 22.5s cold loads and
  eviction churn. Reuse the per-driver `maxConcurrentSpawns` idiom plus
  `/api/ps`. Real, unique to us, and its own slice once seats exist.
- **OCL-S05** — cold load in the run clock. 22.5s vs a 120s first-activity
  budget on this host; unmeasured on larger tags. Do not project a number.
- **`alln sweep` on the front door.** Built 2026-08-13 (`6dcb1982`), absent
  from `menu --json` actions. The only verb whose economics require an
  unmetered seat. Separate, cheap, and not gated on this packet.

---

## 8. Truth owner / lie-prone layers

| | |
| --- | --- |
| **Truth owner** | `/api/tags` for what exists; `ModelCatalog` for what is seated. Neither answers for the other. |
| **Lie-prone** | A cached tag list presented as current (the live `opencode.json` defect); a discovered tag rendered as a runnable seat; `Available` read as usable; a ready dot on a runtime that cannot execute; Claude Code's `costUSD` / `contextWindow: 200000` / `provider: firstParty` on a local seat; a GUI affordance with no CLI equivalent (fails ruling 3). |
| **Missing proof** | All of §5. LR-S00 first. |

---

## 9. Done when

- [ ] A newly pulled tag appears in `alln models --json` **and** the Mac section
      with no setup command re-run
- [ ] `models enable --body` mints a seat through the enable policy, disclosures shown
- [ ] `opencode.json` is never presented as the current tag list
- [ ] `ollama/` seats appear on the bench and the card is grouped by provider
- [ ] `LOCAL RUNTIME` section ships all four installed-state rows
- [ ] Every state is visible to an agent, not only in the GUI (ruling 3)
- [ ] Vocabulary promoted; `Project_Laws.md` §Local Ollama seats amended for the
      discovered/enabled/seated split
- [ ] Promote keepable law; archive this packet

---

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| Local models missing from the app or `alln models`; a newly pulled tag not appearing | This packet §0.3 (verified state) + §4 |
| Which agent body runs a local model, and how the user picks | §0.1 ruling 2, §0.2; code `OllamaLocalSeatEnablePolicy.allowedBodies`, `ClaudeLocalIsolation` |
| Ollama as a driver / an alln-owned tool loop over Ollama HTTP | Refuse — packet 1 §3; `ollama run` is a completion CLI, G0 only |
| Local seat readiness, provenance, isolation, served context | Archived [`OpenCode_Local_Ollama_Seats.md`](../archive/phases/OpenCode_Local_Ollama_Seats.md); law `Project_Laws.md` §Local Ollama seats |
| Egress policy / keeping the frontier model away from source | [`Context_Firewall.md`](Context_Firewall.md) — packet 2; unaffected by this work |
