# Local Runtime Surface — make the local seats we already built reachable

Status: **ALL SLICES IMPLEMENTED — packet NOT closed.** Do not archive.
Founder-ruled 2026-08-14. Successor to packet 1
([`OpenCode_Local_Ollama_Seats.md`](../archive/phases/OpenCode_Local_Ollama_Seats.md),
archived 2026-08-13) — not a reopening of it.
Owner: unassigned (`ModelCatalog` discovery wiring + Mac CLI strip)
Updated: 2026-08-14 (closeout hygiene)
Created: 2026-08-14

**One line:** packet 1 shipped a working local seat pipeline and never connected
it to a command or a screen. A user with Ollama installed cannot find, enable,
or refresh a local model.

**How to read this.** Implementing a slice: §0.1 rulings → §0.5 binds → your row
in §4 → your test in §5. That is ~60 lines. §0.3 is verified code state — consult
it when a slice surprises you; do not re-derive it. Everything else is reference.

### Closeout state — 2026-08-14, PM verified. Not softened.

All ladder slices are **IMPLEMENTED**:

| Slice | Commit |
| --- | --- |
| S00 | `ff52f3f1` |
| S01a | `d05c399b` |
| S01b | `03d29d28` |
| S02a | `7e71b7ec` |
| S02b | `6e80ebdb` |
| S04b | `1a133698` |
| S03+S04 | `dd788af5` |
| brief | `84a129ff` |
| S05b | `b5154976` |
| S05c | `854ec69c` |
| S07 | `39597ca9` |

Contract **10.9.0**. `binaryVersion` **1.1.18** (**unpublished**).

**The packet is not closed.** Do not mark it closed. Do not archive it.

`scripts/check.sh` **ran and failed** at the GUI visual proof gate, before
reaching the Swift suite. It flagged 13 views as changed-without-fresh-proof.
Only **two** are this packet's: `RootView.swift` and
`LocalRuntimeSectionView.swift`. The other **eleven** are pre-existing debt
(`AboutUpdatesView`, `AskAIPanel`, `BoostWindowView`, `CapacityStripView`,
`DefaultModelView`, `ReadinessView`, `SetupViews`, `TeamControlView`,
`TeamStudioView`, `UseFromCLIView`, `WorkspaceMode`). The GUI gate was already
failing before this packet.

**Disclose this:** the PM then re-ran `check.sh` once with
`ALLNIGHTER_GUI_PROOF_WAIVER` set, purely to learn whether the Swift suite was
green. That was a **diagnostic override**, **not** a closeout waiver. The visual
gate remains **unsatisfied**. The re-run was refused anyway by a 45m wall
cooldown, and the PM chose **not** to stack the `ALLNIGHTER_WALL_REASON`
override on top of it.

Instead a blast-radius filtered suite ran: **230 tests, 2 failures**, both the
version-floor drift (`binaryVersion` 1.1.15 vs public floor docs still on
1.1.14). Everything else green. Closeout hygiene later synced the floor via
`scripts/public-floor.sh sync` (not hand-edited) and proved
`VersionIdentityTests` green (`6 tests, 0 failures`), including
`testPublicFloorDocsMatchVersionIdentity`.

`scripts/gui_proof.sh` times out on **every** fixture including the
pre-existing `ask-ai-open`, so it is broken **environment-wide**, not by this
packet. Evidence: the app consumes `gui-proof-request.json` but writes neither
the PNG nor `gui-proof-last-error.txt`; the `gui-proof-screen-recording.ok`
marker is our own bookkeeping dated Jul 30, not macOS TCC truth, and the app
has been rebuilt many times since. Likely fix is `bash scripts/gui_proof_grant.sh`,
which needs a human to click through System Settings.

**No pixel of the new surface has been looked at.** Works Test A has **never**
been run live. Neither is claimed as proven.

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
5. **No local seats on the OpenCode / Claude Code rosters.** Founder: *"I would
   not have Ollama seats appear under OpenCode or Claude. I think that is
   confusing."* Instead the hosting body carries **one non-selectable pointer
   row** naming the count (§2.4). A pointer is a cross-reference; a roster entry
   is a seat. Same pixels, opposite meaning — an implementer who blurs them
   re-creates the confusion this ruling removes.

**Therefore packet 1's `defaultEnabled = false` STANDS.** This packet reverses
no promoted law. `OllamaLocalModelDiscoveryProvider`'s *"discover all local
tags, enable none — that is a default, not a gate"* is upheld. The defect was
never the default; it was that **off currently means invisible.**

### 0.2 Decided by the implementing agent (reversible, founder deferred)

- **Default body when both are installed: `opencode`.** Nothing to fail closed,
  no fake meters to suppress, and already wired in `opencode.json` on the
  dogfood host. A section-level selector makes a wrong default one click.
- **Vocabulary lands in this packet.** JSON field names are decided in LR-S01;
  S07 only promotes them into `Product_Vocabulary.md` / `Project_Laws.md`.

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
| `alln models add --driver <body> --model-label ollama/<tag>` | The **manual** seating path (`ClaudeLocalIsolation.seatingExample`). **Executed in S00** — see §10. One Claude Code custom seat kept on this host. |
| `alln models --json` | Pre-S00: 43 seats, **0 local**. Post-S00: 44 seats, **1 local** (`custom_claude_code_qwen38_27b_local`). |
| `alln menu --json` actions | `drivers`, `models`, `run`, `teams duplicate`, `teams edit`. No local, no `sweep`. |
| `alln opencode-local status` | `wired: true`, `enabledProviders: ["opencode-go","ollama"]`, `ollamaTagsObserved: **false**`, `ollamaModelIds` = 6 tags — **missing `qwen3.8:27b-mlx` pulled the same day**. A frozen snapshot. |
| Mac app | `grep -rl -i ollama Apps/AllnighterMac/Sources/` → **nothing.** Zero Ollama concept. |

**Consequence:** packet 1's Works Test A was proven through a path no user can
reach. That is the defect this packet closes — not the seat behavior, which is
sound.

**Code facts** (re-read 2026-08-14; first pass plus what that pass missed):

- Documented add path is
  `alln models add --driver <body> --name <name> --model-label ollama/<tag>`
  then `models verify <id>` then `models enable <id>`. `createCustom` always
  persists `origin: .custom`, forces the new id **off** the bench, and
  `verifyModelSmoke` refuses anything that is not `.custom`. S00 and S02 are
  **different paths**.
- `saveCustom` / `updateCustom` also require `origin == .custom`. There is
  **no persist API** for `origin: .discovered`. `ModelCatalog.list()` /
  `get()` are built-ins + on-disk customs only. A discovery overlay that is
  not saved is invisible to `setEnabled` / `get`.
- `OpenCodeOllamaSetup.status` passes `tags: .skipped`. It never calls
  `/api/tags`. Setup **does** observe tags and merges them via
  `OpenCodeOllamaProviderMerge.merge`. Reclaim is
  `OpenCodeLeftoverServeReclaim.reclaim` — public; S02 calls it, it does not
  invent a new recycler. A new pull is invisible to the OpenCode body until
  merge runs again.
- `OllamaLocalRuntimeObserver.LocalTag` is `{ name }` only. `/api/tags`
  `capabilities` are not parsed. §2.3 cannot ship on the current observer.
- `allowsAutomaticCodeOffer` is `g1Passed == true && (servedContextWindow ?? 0)
  >= 65536`. No production G1 store. `assessExplicitEnable` with `g1Passed !=
  true` (including nil) always discloses *"has not passed G1"*. That is the
  existing string — S02 prints it; do not invent a fail line or a G1 runner.
- `ModelListJSON.state` is `"onBench" | "available"`. `readiness` is
  `"Available" | "Unavailable"`. No `discovered` field. List-level
  `nextActions` exist only when `models` is empty.
- `ModelListProjector` paints `readiness` on **any** `ollama/` label when a
  snapshot exists. Overlaying tags without changing the projector makes
  unseated tags `Available`.
- `ModelsCLI.modelListJSON` observes Ollama only when
  `observeOllamaReadiness: true`. `MenuCLI` calls it with the **default
  false**. `alln menu --json` does not look at Ollama today.
- `MenuCatalog.isTierOneSelectable` requires `enabled` and drops
  `notReady` / `driverMissing` / `parked`. Default `menu --json` is that
  filter. `completeness.models` is hardcoded `complete: true` on the
  unfiltered input count. `blocked` is `{count, see: "alln models"}` —
  a count, not names.
- `ModelCatalog.neverAutomaticSubstituteIds` is a **static paid-id set**
  (`model_cursor_gpt_sol`). `allowsAutomaticSubstitution` is `!contains`.
  It cannot express "every local seat." `fallbackCapabilities` copies the
  **richest built-in** profile for that driver, then sets
  `unratedModelRank` (40). A Claude-local **custom** seat inherits Code
  lane tags and is auto-staff eligible. Packet 1 ruling 11 still applies.
- Doctor `readinessDetail` walks **every** `/api/tags` name as
  `ollama/<tag>` plus catalog `localSeatLabels`. That is how the dogfood
  host read `Available` with zero catalog seats.

### 0.4 Dogfood host facts (do not project to other hardware)

MacBook Air M4, 32 GB. `qwen3.8:27b-mlx` (18 GB, nvfp4, declares
`completion, vision, tools, thinking`): **10.1 tok/s**, cold load **22.5s**,
warm 0.6s. Ollama 0.32.12. Larger tags on larger machines are unmeasured
(OCL-S05 remains unbuilt — §7).

### 0.5 Implementer binds

Four earlier drafts of this ladder were wrong. Do not reintroduce them:

1. **S00 is a catalog-path audit** — not a live G3 re-prove, not a
   Team-auto-staff gate. Stop the packet only if custom Claude-local
   add→verify→enable cannot mint an honest row. Teams refusing an unpinned
   local seat is packet 1 ruling 11 working, not a blocker.
2. **Leftover `opencode serve` reclaim is on S02**, not OCL-S05. A status-only
   S03 does not make Test B green.
3. **LOCAL RUNTIME is its own class**, never a READY body row (ruling 5, §2.4).
4. **Ruling 3 is not satisfied by `alln models --json` alone.**
   `alln menu --json` is the agent front door.

**Decided from this tree (not founder; not UNDECIDED):**

| Item | Decision | Owner |
| --- | --- | --- |
| Menu shape | A `localRuntime` object on default `alln menu --json`. Lists every discovered tag (id, label, enabled, seated, per-row enable command) plus the section default body. **Illegal:** only `blocked.count` / `see: alln models`. **Illegal:** stuffing off seats into tier-1 `models[]` (Test C: not selectable). Split them out in `MenuCatalog.project` **before** the omitted count. `completeness` must include this collection — today's `models.complete: true` on a filtered list is a lie if local tags live only in a sidecar the flag does not name. `menu --detailed` may also show catalog rows; default menu must not require `--detailed`. | S01 |
| Body-selector write | One persisted default body. Applies to the **next** enable only. Does not remint in-flight or already-seated ids (`seatedID` encodes the body). No "switch every enabled seat" verb in this packet. | S01 names the field; S02 reads it; S05 (and CLI) write it |
| Enable grammar | `alln models enable <candidateID> --body <claude_code\|opencode>` mints `seatedID(tag:bodyDriverId:)`, persists `origin: .discovered`, sets enabled. Resolve the candidate from the **live overlay** (`candidateID(tag:)` + `/api/tags`) — `get()` will not find it. `enable <seated-id>` (no `--body`) stays today's `setEnabled`. `--body` on an already-seated id **refuses**. Contract bump. | S02 |
| Auto-sub seam | **Not** `neverAutomaticSubstituteIds`. Guard on `ollama/` label (`OllamaLocalDoctorReport.isOllamaBackedSeat` / `ClaudeLocalIsolation.isLocalSeat` / `OpenCodeLocalSeatReadiness.isLocalOpenCodeSeat`) so the S00 **custom** path is covered too. Origin-only misses `.custom`. | S00 if question (4) is yes; else S02 |
| Candidate persist | Do **not** persist discovered-not-seated tags. Overlay at list time via `OllamaLocalModelDiscoveryProvider.result(from: snapshot)` using the list's existing snapshot. Do not call async `discover()` (second socket). Persist **seated** rows only — add a `.discovered` save; do not rebase onto `.custom` to reuse `verify`. | S01 overlay; S02 save |
| G1 disclosure | Print `Assessment.disclosures` as the policy already writes them. Nil G1 is *"has not passed G1. Explicit enable proceeds."* — not a display "G1 failed". | S02 |

**Still founder-owned (out of this packet):** remint-all when the selector
flips; ON-by-default (ruling 4, already dropped).

---

## 1. The claim

A user pulls a model with `ollama pull`, opens Allnighter, sees no Ollama, and
leaves. Ollama is inference, not an agent body (`ollama run` has no tool loop —
packet 1 §3). The pairing in three words: `Ollama via OpenCode`.

---

## 2. Surface

### 2.1 The section

Home: Settings › **CLIs** (`TeamReadinessView` / `TeamStudioView` `.clis`).
Not the Default model page. Not a `READY` body row.

```text
LOCAL RUNTIME                                    via [ OpenCode ▾ ]
  Ollama · 0.32.12 · 7 models                                    ●
    Qwen3.8 27B          ollama/qwen3.8:27b-mlx        [ off ]
    gpt-oss 20B          ollama/gpt-oss:20b            [ off ]
    Qwen3 8B             ollama/qwen3:8b               [ off ]
    qwen2.5-coder 7B     tools advertised; G1 unknown  [ off ]
    qwen2.5-coder 1.5B   served window unobserved      [ off ]
```

Mockup reasons are **honest unknowns**. Do not ship "text-fakes" / "too small
for Code" from `allowsAutomaticCodeOffer` on nil inputs — that marks every
cold tag "not recommended" and violates failure-to-observe-is-not-absence.

| Installed | Row |
| --- | --- |
| both bodies | `Ollama via OpenCode / Claude Code` + selector |
| OpenCode only | `Ollama via OpenCode` |
| Claude Code only | `Ollama via Claude Code` |
| neither | `Ollama · N models · needs OpenCode or Claude Code` — **no ready dot**, install action |

The ready dot on the **runtime** row (Ollama reachable) is not a seat ready
dot. Do not reuse the body-row `●` asset if that asset means "this CLI can
run work."

### 2.2 Advisory reasons, never gates

`allowsAutomaticCodeOffer` is the automatic-Code **offer** predicate, only
when both inputs are **observed**. It does not read advertised `tools`.

| What we have | What we print |
| --- | --- |
| G1 failed (observed) | G1 failed — structured `tool_calls` missing. Enable still works. |
| G1 never run | G1 unknown. Not a fail. |
| Served window observed and `< 65536` | Served window N (below automatic Code floor). Enable still works. |
| Served window unobserved | Window unobserved (tag not in `/api/ps`). Not a fail. |
| Advertised `tools` without a G1 pass | Do not write "text-fakes." We have not proven a fake. |

The toggle always flips. Automatic Code **offers** stay gated. Do not persist
a G1 runner in this packet.

### 2.3 Filter

Hide a tag only when `/api/tags` **declares** capabilities **and** that set
does not include `completion`. S01 extends `LocalTag`. Absence of a
capabilities field is not "not a completion model" — stay visible,
capability-unknown. No name heuristic (`*embed*`).

### 2.4 The hosting-body pointer (ruling 5)

LOCAL RUNTIME is the only list. The body card gets **one row**, and only the
body currently hosting seats gets it:

```text
OpenCode                                                         ●
  Big Pickle   DeepSeek V4 Pro   GLM-5.2   MiniMax M3   …
  ── Ollama · 3 models  →                     (jumps to LOCAL RUNTIME)
```

| Rule | Why |
| --- | --- |
| Only on the hosting body | The other card has zero local seats. *"Ollama: not enabled"* is noise. |
| Counts **enabled seated** rows for that body | Discovered-not-enabled tags are hosted by nothing yet. |
| Not selectable, not in the card's model total, not a `models[]` entry | It is a link. Counting it re-creates ruling 5's confusion. |
| CLI twin required | `alln drivers --json` carries `localRuntimeSeats: <n>` on that body's row. A GUI-only pointer **fails Test D** (ruling 3). |

Wording is `Ollama · N models`, not "Ollama Enabled" — count-first matches
every other card, and *enabled* is ambiguous about whether the runtime, the
body, or the models are meant.

Both bodies may show the row if a user hand-seated the same tag twice via
`models add`. That falls out of "show when count > 0"; no special case.

S06 (namespace grouping of paid roster cards) stays dropped.

---

## 3. New/changed semantic rules

1. **Discovery runs from a command.** List-time overlay on `alln models` and
   on the same builder `MenuCLI` uses. Never from catalog load. One snapshot
   per list; map with `result(from:)`.
2. **Discovered ≠ enabled ≠ seated.** Not `state` (`onBench`/`available`),
   not `readiness` (`Available`/`Unavailable`). Distinct fields; contract
   bump. Law `Available` applies only to a **seated** local model. An overlay
   tag must not emit `readiness: "Available"` — change `ModelListProjector`.
3. **Each state has its own command string on the row**, not a pile of
   list-level `nextActions` (those fire only when `models` is empty).
4. **The OpenCode body sees a live tag list.** Status re-reads `/api/tags`.
   S02 enable/refresh runs `OpenCodeOllamaProviderMerge.merge` on the live
   tag list **and** `OpenCodeLeftoverServeReclaim.reclaim`. A tag pulled
   after setup is runnable without re-running `opencode-local setup`.
   `opencode.json` is what OpenCode will accept after that merge, not the
   current tag list.
5. **Body is chosen at enable**, section-wide default from §0.2, recorded on
   the seated id. Journal records which body ran. Selector write = §0.5.
6. **Enabling nothing is a valid steady state.** Visibility is the guarantee.
7. **A local seat is never an automatic substitute.** Explicit `--model` /
   `--seat` / `preferredModelId` only. Seam = §0.5 auto-sub (label, not the
   Cursor Sol id set).
8. **Doctor does not call an unseated tag a seat.**
   `source.ollama_local.models` may still list pulled names.
   `source.ollama_local.readiness` is per **seated** label only.

---

## 4. Slice ladder

| Id | Intent | Code? |
| --- | --- | --- |
| **LR-S00** | Catalog-path audit. Documented add→verify→enable on **one** already-pulled tag, Claude Code body first (`--name` required). Inspect `alln models --json` + `alln run --model <id> --dry-run`. OpenCode add if cheap. **Four questions — do not collapse.** (1) Does the custom path mint an honest row? (2) Does dry-run resolve the body? (3) Does explicit `--seat` / `preferredModelId` accept it, or refuse on lane tags? Record; do not halt visibility. (4) Does a capability-staffed Team **without** a pin pick it? If yes, land the §0.5 label guard **in this slice** before S02. **Stop the packet only if (1) fails on Claude Code.** Do not re-run packet 1 G3. One tag, one body — do not staff three local seats. | None unless (4) forces the guard |
| **LR-S01** | Wire the overlay. Decide JSON words (rule 2). Parse `/api/tags` capabilities (§2.3). `alln models --json` lists overlay tags as **not seated**, `readiness` omitted or not `Available`, each with the S02 enable command string. Default `alln menu --json` carries `localRuntime` (§0.5). Menu must observe Ollama (today it does not). `ModelListProjector` + `MenuCatalog.project` as named above. `alln drivers --json` gains `localRuntimeSeats` per body (§2.4 CLI twin). **Ruling 3 — agent half.** Prove CLI A + D. Contract + `AllnighterVersionIdentity.binaryVersion` bump. | Core/CLI |
| **LR-S04b** | Run ready-set observes Ollama. `BenchReadiness.readyModels` takes `ollamaLocal` defaulted nil, so `isLocallyReady` fails closed and an explicitly pinned local seat is silently substituted to a PAID seat (S00 Q3, §10). Violates sensors-inform-never-blocks. Sequenced before LR-S05. | Core |
| **LR-S02** | Minting enable (§0.5 grammar). `assessExplicitEnable` → print `disclosures` → persist `origin: .discovered` seated id → `setEnabled(seated, true)` → rule 7. OpenCode body: `OpenCodeOllamaProviderMerge.merge` + `OpenCodeLeftoverServeReclaim.reclaim`. Claude Code body: no `opencode.json` write. Prove Test B dry-run. | Core/CLI |
| **LR-S03** | `opencode-local status` re-reads `/api/tags` and reports drift vs `opencode.json` (`ollamaTagsObserved` can be true). Does not replace the S02 write. | Core/CLI |
| **LR-S04** | Pin-ability: an **enabled** seated id resolves `--model` / human pick. **Not** extra READY-row chips (ruling 5). If S02 already did this, say so and skip. | Core |
| **LR-S05** | Mac `LOCAL RUNTIME` (§2.1), the hosting-body pointer row (§2.4, ruling 5), selector write (§0.5), advisory reasons (§2.2), four installed-state rows. Same overlay/projector as CLI — do not walk doctor tags as seats. **Ruling 1, 2 — the human half.** GUI Workflow **Tier C**: first deliverable `docs/gui/surfaces/local-runtime/brief.md`. Close with Visual_Proof_Gate (render + layout-watcher). `alln chrome --json` projects the section labels. Prove Mac A + D. | GUI |
| **LR-S07** | Promote §6 into `Product_Vocabulary.md` and amend `Project_Laws.md` §Local Ollama seats: seat = body-bound catalog row, not a pulled tag. Help: `opencode_local_setup`, `claude_local_isolation`. | Docs |

**LR-S06 dropped.** Namespace grouping of paid body cards is not the defect.

Out of ladder: ON-by-default (ruling 4); an Ollama `DriverManifest`; an
Allnighter-owned tool loop over Ollama HTTP; a G1 runner / G1 store; reminting
every seat when the selector flips; residency/thrash and OCL-S05 (§7);
`alln sweep` on the menu; `Context_Firewall.md`; `Second_Mac_Bench.md`.

S01 before S02: overlay ids exist before mint. S02 before S03: status cannot
rescue Test B. S05 after the CLI contract (GUI does not own the words). S07
is promotion.

Each slice's proof is in §5. S01 is green without S02 (enable command is a
string; it need not succeed yet). S02 is green without S03. S04/S05 do not
unblock S02.

---

## 5. Works Test

Split **fixture** (Green Wall) from **dogfood** (this host). A
`scripts/swift-test.sh` case must not open Ollama, rewrite the user's
`opencode.json`, or touch the real catalog (`Execution-Playbook.md` § Green
Wall).

**A — a newly pulled model surfaces itself (headline).**

S01 closes the CLI half. S05 closes the Mac half. Packet close needs both.

```text
Given: Allnighter running, Ollama reachable, a completion-capable tag
       not previously in /api/tags
When:  ollama pull <that tag>
Then:  alln models --json lists it as discovered, not seated, not ready-to-run
       readiness is absent or not "Available"
       the row carries the S02 enable command (not list-level nextActions)
       default alln menu --json.localRuntime names the tag (not blocked.count,
       not only --detailed)
       alln doctor does not report that tag as an Available seat
       (S05) the Mac LOCAL RUNTIME section lists it
       none of this required opencode-local setup or models add
```

Fixture twin: inject a tags payload with a new completion tag + an
embedding tag + a no-capabilities tag; assert the projector. Never pull.

**B — enable seats it in the chosen body (dogfood, after S02):**

```text
When:  alln models enable <candidateID> --body opencode
Then:  Assessment.disclosures print (including the existing nil-G1 line)
       alln models --json shows seatedID(tag:bodyDriverId:)
       origin is discovered, not custom
       driverId is the body, not ollama_local
       opencode.json contains the tag
       leftover opencode serve was reclaimed or reported honestly
       alln run --model <seated-id> --dry-run resolves
       optional: one live run, one tag, --no-commit; journal records the body

Repeat dry-run for --body claude_code (no opencode.json write).
```

Fixture twin: minting CLI path against a fake catalog + fake merge. Do not
call live `/v1` from XCTest.

**C — negative proofs (fixture first; dogfood where marked):**

```text
- capabilities present and no `completion` → not a candidate
- capabilities field absent → still visible, marked unknown; not dropped
- name-based embed heuristic is not used (nomic-shaped names with no
  capabilities field still appear)
- discovered-not-enabled: alln run --model <candidate-id> refuses
  (unknown / not enabled / not seated — never starts work)
- discovered-not-enabled: ready == false; readiness is not "Available";
  default menu models[] does not present it as selectable
- default menu localRuntime still names it (ruling 3)
- allowsAutomaticCodeOffer == false with unobserved G1/window: still
  enableable; reason column is "unknown" / "unobserved", not "not recommended"
- observed G1 fail: visible, enableable, reason states the fail
- neither body installed: no ready-to-run mark on the runtime row;
  enable command names the missing body
- ruling 5: a seated local model appears in NO body roster; the hosting
  body's `Ollama · N models` pointer is not selectable, is absent from that
  body's `models[]`, and is excluded from its model count
- the non-hosting body shows no pointer at all (not a zero, not "disabled")
- ollama rm <tag> (dogfood): tag leaves the discovered list; a seated
  row for that tag becomes Unavailable (law) — not deleted
- Ollama down: every seated local row is Unavailable; discovered list
  is unobserved, not "no tags"
- Claude Code local row does not inherit costUSD / contextWindow 200000 /
  provider firstParty (already coded; do not regress)
```

**D — agent parity (ruling 3, blocking; fixture + dogfood):**

| Mac | CLI |
| --- | --- |
| tag name / `ollama/<tag>` | `alln models --json` row **and** `menu --json` `localRuntime` |
| off / on | `enabled` + discovered/seated fields from S01 |
| body (`via OpenCode` / `via Claude Code`) | seated `driverId` + section default |
| hosting-body pointer `Ollama · N models` (§2.4) | `drivers --json` `localRuntimeSeats: N` on that body |
| advisory reason | same string or same enum, not GUI-only prose |
| neither-body empty | models + menu both say the bodies are missing |
| enable / install affordance | per-row command, not a tooltip |

`alln chrome --json` carries the section labels once S05 ships. Doctor must
not contradict models (no Available seat that models does not treat as seated).

A test that only round-trips the Mac view-model into `models --json` after
S05, and never opens default `menu --json`, **passes while agents still
cannot see local tags.** Gate D on S01 (CLI) and re-check on S05 (chrome + GUI).

**Proof command:** `scripts/swift-test.sh --filter <TouchedTests>` per
slice for fixtures. Dogfood A/B/C-rm on this host, recorded in the slice
closeout — not inside XCTest. `bash scripts/check.sh` at **packet**
closeout only.

**Missing proof / waiver:**

- Packet 1 already proved G3 mutate on both bodies. This packet does not
  re-claim that. Optional live B confirms the **wired** path.
- Works Test A has **never** been run live. No pixel of the Mac surface has
  been looked at. Neither is claimed as proven.
- `scripts/check.sh` ran and **failed** at the GUI visual proof gate (13
  views changed-without-fresh-proof). Two are this packet (`RootView.swift`,
  `LocalRuntimeSectionView.swift`). Eleven are pre-existing debt — the GUI
  gate was already failing before this packet. See Closeout state.
- The `ALLNIGHTER_GUI_PROOF_WAIVER` re-run was a **diagnostic override**,
  **not** a closeout waiver. The visual gate remains **unsatisfied**. The
  re-run was then refused by the 45m wall cooldown; `ALLNIGHTER_WALL_REASON`
  was **not** stacked.
- `scripts/gui_proof.sh` times out on every fixture (including pre-existing
  `ask-ai-open`). Environment-wide; likely `bash scripts/gui_proof_grant.sh`
  (human click-through).
- Works Test B on Studio-class hardware remains unproven (packet 1 B).
  Out of scope.

---

## 6. Vocabulary (field names in S01; promote in S07)

- **Local runtime** — an inference engine (Ollama) that supplies models to
  agent bodies. Never itself a body, never a `READY` row, never a seat.
- **Ollama provides the model; a CLI provides the tools.** Use verbatim.
- **Discovered** — `/api/tags` showed this local tag (and §2.3 did not
  exclude it). Not enabled. Not seated. Not `readiness: Available`.
- **Enabled** — the user turned the tag on. Same word as today's catalog
  `enabled`.
- **Seated** — a `ModelCatalog` row bound to one body, id from
  `seatedID(tag:bodyDriverId:)`. This is what law means by **seat**.
  `Available` / `Unavailable` apply here only.
- **Available / Unavailable** — unchanged law, **per seated row**. Doctor
  and models share `OllamaLocalDoctorReport.readinessWord`.

S07 amends the law paragraph so "seat" means the body-bound catalog row,
not a pulled tag. Do not put `discovered` in `state` or `readiness`.

---

## 7. Not in this packet

- **Residency / thrash.** After seats exist. One tag, one run in S00 / Test B.
  Three local seats on three tags will look like a seating bug.
- **OCL-S05** — cold load in the run clock. If a live B dies on first-activity,
  measure before opening that slice; do not start it here.
- **`alln sweep` on the front door.** A consumer of seated local models, not
  a dependency.

Leftover `opencode serve` is **not** in this list — it is on S02. Context
Firewall and Second Mac still do not block this ladder.

---

## 8. Truth owner / lie-prone layers

| | |
| --- | --- |
| **Truth owner** | `/api/tags` for what exists on disk; `ModelCatalog` for what is seated. Neither answers for the other. `opencode.json` answers only for what the OpenCode process will accept, and only after a merge this packet owns. |
| **Lie-prone** | Cached `opencode-local status`; leftover serve; discovered tag as a runnable seat; `readiness: Available` on a non-seat; `state: available` read as "Available"; ready dot on a runtime that cannot execute; Claude local `costUSD` / `contextWindow: 200000` / `provider: firstParty`; offer predicate false-on-nil painted "not recommended"; GUI affordance with no CLI twin; default `menu --json` omitting every off local tag while `completeness.models.complete` is true; doctor listing unseated tags as Available seats; Teams silently picking a local seat via inherited driver caps; persisting a discovered seat as `.custom` so `verify` will take it; the §2.4 pointer drifting into a selectable roster entry or into the body's model count (ruling 5). |
| **Missing proof** | Live Works Test A (never run). Mac pixels (never looked at). Visual_Proof_Gate unsatisfied (`gui_proof.sh` environment-wide timeout). OpenCode `--model` dry-run not recorded. 1.1.16 unpublished. Packet not closed. S00 recorded in §10. |

---

## 9. Done when

- [x] S00 recorded: four questions answered; packet proceeds to LR-S01
      (custom Claude-local add→verify→enable minted an honest row; §10)
- [ ] A newly pulled completion tag appears in `alln models --json` **and**
      default `alln menu --json` `localRuntime` **and** the Mac section, with
      no setup re-run and no `models add`
      **Blocker:** Works Test A has never been run live. No pixel of the Mac
      section has been looked at. Visual_Proof_Gate unsatisfied.
- [ ] Doctor does not call that tag an Available seat until it is seated
      **Fixture now green** (`testPulledUnseatedTagsAreInventoryNotReadiness`,
      `testReadinessListsSeatedLabelsOnly`). **Blocker:** live Works Test A
      still not re-run on the 1.1.16 binary (1.1.15 reproduced the lie).
- [x] `alln models enable <candidateID> --body <body>` mints a
      `.discovered` seated row through `assessExplicitEnable`; OpenCode
      merge + leftover reclaim happen on `--body opencode`
      (LR-S02a `7e71b7ec`, LR-S02b `6e80ebdb`; fixtures
      `LocalRuntimeSurfaceS02aTests` / `LocalRuntimeSurfaceS02bTests`)
- [ ] `alln run --model <seated-id> --dry-run` resolves on both bodies
      (this box is what makes a local model *usable*, not merely listed)
      **Blocker:** live S00 dry-run was the Claude Code **custom** path only.
      S04 fixture (`testDiscoveredSeatedIdListsAndResolvesExplicitModel`)
      resolves a Claude Code `.discovered` id. OpenCode `--model` dry-run
      not recorded tonight.
- [x] `opencode-local status` observes `/api/tags`; `opencode.json` is never
      presented as the current tag list
      (LR-S03 `dd788af5`; fixtures
      `OpenCodeOllamaSetupTests.testStatusObservesLiveTagsAndReportsDrift`,
      `testStatusInSyncWhenLiveMatchesConfig`,
      `testStatusUnreachableIsUnobservedNotEmptyLiveList`)
- [ ] Enabled `ollama/` seats are pin-able and appear on **no** OpenCode /
      Claude Code roster (ruling 5). The hosting body shows one non-selectable
      `Ollama · N models` pointer, mirrored by `drivers --json`
      `localRuntimeSeats`, counted in neither the roster nor `models[]`
      **Blocker:** CLI half is fixture-green (S01b / S05c). Mac pointer and
      roster exclusion have not been looked at. Visual_Proof_Gate
      unsatisfied; `gui_proof.sh` times out environment-wide.
- [ ] `LOCAL RUNTIME` ships all four installed-state rows; Visual_Proof_Gate
      + `alln chrome --json` for the labels
      **Blocker:** Visual_Proof_Gate unsatisfied. `gui_proof.sh` times out on
      every fixture. No pixel looked at. layout-watcher never spawned.
      `ChromeCatalogTests` covers the chrome labels in fixture only.
- [x] Automatic substitution never picks a local seat (label guard, including
      origin-`.custom` ollama/ rows)
      (LR-S02a `testLocalSeatIsNeverAutomaticSubstituteIncludingCustomOrigin`,
      `testUnpinnedTeamDoesNotAutoStaffLocalSeat`; S00 Q4 did not pick)
- [x] Every state in §5 D is visible on default `alln menu --json` (ruling 3)
      — not only on `models --json` or `menu --detailed`
      (LR-S01b fixtures: `testMenuLocalRuntimeListsEveryDiscoveredTagWithDefaultBody`,
      `testMenuTierOneOmitsOverlayButLocalRuntimeStillNamesIt`. Mac column
      of the D table is **not** in this box and is **not** proven.)
- [x] Vocabulary promoted; `Project_Laws.md` §Local Ollama seats amended (LR-S07)
- [ ] CLI behavior change published as a **new**
      `AllnighterVersionIdentity.binaryVersion` — do not overwrite an
      immutable R2 prefix (`Public_Release.md` § Version bump law). One bump
      if S01–S03 ship together; bump again if a later slice ships separately.
      **Blocker:** `binaryVersion` is **1.1.16 unpublished**. Floor docs now
      match identity (`scripts/public-floor.sh sync`). No
      `rebuild_cli.sh` / ship this turn.
- [ ] Promote keepable law; archive this packet
      **Blocker:** packet is **not** closed. Do not archive.

### Blocked on founder

1. **Tier C vs D** for the Mac surface. Packet §4 names GUI Workflow
   **Tier C**. `docs/gui/GUI_Workflow.md` says escalate to D when the work
   touches starting, killing, or routing agent runs / workers. The enable
   toggle seats a model a later run can pin — founder picks the tier.
2. **Screen Recording grant.** `scripts/gui_proof.sh` is broken
   environment-wide until a human runs `bash scripts/gui_proof_grant.sh`
   and clicks through System Settings.
3. **Permission to run `rebuild_cli.sh` at closeout.** 1.1.16 is
   unpublished. This turn did not run it.
4. **Whether to spawn `.claude/agents/layout-watcher.md` for the sighted
   pass.** `scripts/check_gui_proof.sh` itself prescribes spawning it
   after `gui_proof.sh` (step 1 of the fail text). No pixel has been
   looked at; the watcher was not spawned.
5. **Paid-pin substitution law** — **ruled 2026-08-15.** Never substitute
   a cloud seat with a local seat or the other way around. Same-side
   substitution keeps one honesty disclosure for both. Promoted:
   `docs/operations/Project_Laws.md` §Local and cloud seats.

---

## 10. LR-S00 catalog-path audit (2026-08-14)

Closeout Code Audit (2026-08-15): **P1** delete owns only mint-added
`opencode.json` tags; **P2** `SubstitutionResolver` same-side local/cloud
guard. Full record at the end of this section (`### Closeout Code Audit P1/P2`).

Dogfood host, one tag, one body. No live inference. Seat **kept**.

**Packet proceeds to LR-S01.** Question (1) passed on Claude Code. Question (4)
did **not** pick the local seat, so the §0.5 label guard is **not** landed in
this slice (stays on S02).

### Path executed

```text
alln models add --driver claude_code --name "Qwen3.8 27B local" --model-label ollama/qwen3.8:27b-mlx --json
alln models verify custom_claude_code_qwen38_27b_local --json
alln models enable custom_claude_code_qwen38_27b_local --json
```

`verify` is local-evidence only for `ollama/` + Claude Code (binary + `/api/tags`);
it did not spawn Claude Code or send tokens.

```json
{
  "driverId" : "claude_code",
  "id" : "custom_claude_code_qwen38_27b_local",
  "label" : "ollama/qwen3.8:27b-mlx",
  "status" : "recognized"
}
```

Minted id: `custom_claude_code_qwen38_27b_local`. Origin `.custom`, forced
off-bench at add, enabled after verify. OpenCode add **not** run (one tag,
one body).

### (1) Honest row? **YES — packet does not stop.**

Command: `alln models --json` (row extracted; catalog now 44).

```json
{
  "capabilities": {
    "capabilityTags": ["code", "planner", "review", "security", "design", "copy", "localContext"],
    "laneTags": ["code", "design", "copy", "signal"],
    "strengthRank": 40
  },
  "displayName": "Qwen3.8 27B local",
  "driverId": "claude_code",
  "driverName": "Claude Code",
  "enabled": true,
  "id": "custom_claude_code_qwen38_27b_local",
  "modelLabel": "ollama/qwen3.8:27b-mlx",
  "origin": "custom",
  "readiness": "Available",
  "ready": true,
  "role": "answerer",
  "stale": true,
  "state": "onBench",
  "status": "ready"
}
```

| Field | Honest? |
| --- | --- |
| `driverId` | Yes — `claude_code` (body), not `ollama_local` |
| `origin` | Yes — `custom` (createCustom persist) |
| `modelLabel` | Yes — `ollama/qwen3.8:27b-mlx` |
| `readiness` | Yes — **Available**. Tag is pulled, Ollama reachable, row is **seated**. Not a false Available on an unseated overlay tag. |
| `ready` / `status` | Yes on `models --json` (`true` / `ready`) |

Inherited richest Claude Code capability + all four lane tags at
`unratedModelRank` 40. Identity fields are true; the inheritance is the
ruling-11 seam tested in (4).

Related split (not a (1) fail): default `alln menu --json` lists the same id
as `ready: false`, `status: "notChecked"`, `blockedReason: "Source not checked"`.
Menu does not observe Ollama today (§0.3). That split explains (3) and (4).

### (2) `--model` dry-run resolve the body? **YES.**

```text
alln run "LR-S00 resolution only; do not execute" --model custom_claude_code_qwen38_27b_local --dry-run --json
```

```json
{
  "canStart" : true,
  "counts" : { "blockedWorkers" : 0, "readyWorkers" : 1, "resolvedSourceIds" : 1, "seatCount" : 1 },
  "modelId" : "custom_claude_code_qwen38_27b_local",
  "resolvedModelLabel" : "ollama/qwen3.8:27b-mlx",
  "resolvedPinModelId" : "custom_claude_code_qwen38_27b_local",
  "teamPresetId" : "default_chat",
  "writePolicy" : "mutating"
}
```

Pin resolved. Label is the Ollama tag. Body is the catalog `driverId`
`claude_code`. `canStart: true`. No tokens sent.

### (3) Explicit `--seat` / `preferredModelId`? **Not a lane-tag refuse.**

`--seat` on Doc Review (1 crew slot):

```text
alln run "LR-S00 explicit seat pin; do not execute" --team code_doc_review --seat custom_claude_code_qwen38_27b_local --dry-run --json
```

```json
{
  "blockedReason" : "seat 1 (custom_claude_code_qwen38_27b_local): not ready — check `alln doctor` / `alln menu --json`",
  "canStart" : false,
  "seats" : [
    { "driverId" : "codex", "family" : "gpt", "modelId" : "model_gpt_sol", "reason" : "band+unusedFamily", "skillId" : "doc_reviewer", "stage" : "answer" },
    { "driverId" : "cursor_agent", "family" : "claude", "modelId" : "model_cursor_fable", "reason" : "band+unusedFamily", "skillId" : "doc_reviewer", "stage" : "plan" }
  ],
  "teamPresetId" : "code_doc_review"
}
```

Refused **not ready** (`TeamExplicitSeats` ready-set — the same
`notChecked` menu path). Did **not** hit `seatIncompatible` / lane tags.
`--seat` on `code_spec_review` (5 crew slots) failed earlier on count
mismatch (`got 1`) — not informative about the local seat.

`preferredModelId` (temp team `custom_lr_s00_pin`, duplicated from
`code_doc_review`, then deleted):

```text
alln teams duplicate code_doc_review --id custom_lr_s00_pin --name "LR-S00 preferredModelId pin" --json
# agentSpecs[0].preferredModelId + lead.preferredModelId = custom_claude_code_qwen38_27b_local
alln teams edit custom_lr_s00_pin --file <edit.json> --json
alln run "LR-S00 preferredModelId pin; do not execute" --team custom_lr_s00_pin --dry-run --json
alln teams delete custom_lr_s00_pin --json
```

```json
{
  "canStart" : true,
  "seats" : [
    { "driverId" : "claude_code", "family" : "claude", "modelId" : "model_opus", "reason" : "reuseFamily", "skillId" : "doc_reviewer", "stage" : "answer" },
    { "driverId" : "claude_code", "family" : "claude", "modelId" : "model_fable", "reason" : "band+unusedFamily", "skillId" : "doc_reviewer", "stage" : "plan" }
  ],
  "teamPresetId" : "custom_lr_s00_pin",
  "warnings" : [
    "Doc Reviewer: preferred custom_claude_code_qwen38_27b_local unavailable; resolved to Opus 5."
  ]
}
```

The pin was **accepted** (not a lane-tag refuse) and then treated as
**unavailable**; resolver substituted Opus 5. Same ready-set split as `--seat`.

### (4) Unpinned capability-staffed Team pick it? **NO — guard not landed here.**

Commands (all `--dry-run --json`; no `--model` / `--seat`):

```text
alln run "LR-S00 unpinned team; do not execute" --team code_doc_review --dry-run --json
alln run "LR-S00 unpinned team; do not execute" --team code_spec_review --dry-run --json
alln run "LR-S00 unpinned team; do not execute" --team code_spec_review_max --dry-run --json
alln run "LR-S00 unpinned team; do not execute" --team code_gui_bug_hunt --dry-run --json
alln run "LR-S00 unpinned team; do not execute" --team code_plan --dry-run --json
alln run "LR-S00 unpinned team; do not execute" --team fusion --dry-run --json
alln run "LR-S00 unpinned team; do not execute" --dry-run --json
```

| Team | canStart | seats | picked local? |
| --- | --- | --- | --- |
| `code_doc_review` | true | `model_gpt_sol`, `model_cursor_fable` | no |
| `code_spec_review` | true | Sol, Cursor Fable, Grok 4.6, Kimi K3, GLM-5.2, Fable | no |
| `code_spec_review_max` | true | 10: Grok 4.6, Sol, Cursor Fable, Kimi K3, GLM-5.2, Qwen 3.8 Max, DeepSeek V4 Pro, Cursor Opus, Opus 5, Fable | no |
| `code_gui_bug_hunt` | true | 10 (same paid mix, no local id) | no |
| `code_plan` | true | 8 paid | no |
| `fusion` | true | Gemini, Kimi K2.7, DeepSeek V4 Pro, Opus 5 | no |
| Default Team (`default_chat`) | true | `modelId` / `resolvedPinModelId` = `model_fable` | no |

`code_spec_review_max` excerpt (`canStart: true`, local id absent):

```json
{
  "canStart" : true,
  "counts" : { "seatCount" : 10 },
  "seats" : [
    { "modelId" : "model_grok_46" },
    { "modelId" : "model_gpt_sol" },
    { "modelId" : "model_cursor_fable" },
    { "modelId" : "model_kimi_k3" },
    { "modelId" : "model_opencode_glm_5_2" },
    { "modelId" : "model_qwen_38_max" },
    { "modelId" : "model_opencode_deepseek_v4_pro" },
    { "modelId" : "model_cursor_opus" },
    { "modelId" : "model_opus" },
    { "modelId" : "model_fable" }
  ]
}
```

Not the live ruling-11 regression (a Team **picking** the local seat). The
row is still auto-staff-eligible **if** it ever enters the run ready-set:
inherited Code lane tags, `allowsAutomaticSubstitution` is id-set-only, origin
`.custom` is not a local guard. That is why §0.5 still binds the label guard
on **S02** (or here, only if (4) had been yes).

### Disposition

- Seat **kept**: `custom_claude_code_qwen38_27b_local` (honest Claude Code
  custom row; founder wants that seat).
- No `models delete`.
- No code in this slice.
- **Next: LR-S01.** Do not start it from this record.

### LR-S02a — minting enable, Claude Code body (2026-08-14)

`alln models enable <candidateID> --body claude_code` resolves the candidate from
the live overlay, prints `assessExplicitEnable` disclosures (nil G1 is the
existing "has not passed G1" line), persists `origin: .discovered` via
`ModelCatalog.saveDiscovered`, then `setEnabled`. `enable <seated-id>` with no
`--body` is unchanged. `--body` on an already-seated id refuses. Rule 7 guards
on the `ollama/` label (named helpers), not `neverAutomaticSubstituteIds`, so
the S00 `.custom` seat is covered. OpenCode merge + leftover reclaim stay S02b.

### LR-S02b — minting enable, OpenCode body (2026-08-14)

`--body opencode` on the same enable path runs `OpenCodeOllamaProviderMerge.merge`
on the live `/api/tags` list (not the frozen `opencode-local status` snapshot),
writes `opencode.json` when the merge changes, then
`OpenCodeLeftoverServeReclaim.reclaim` — reclaimed or disclosed honestly, never
silently. `--body claude_code` writes nothing to `opencode.json`. Fixture proof:
`LocalRuntimeSurfaceS02bTests`. Contract stays 10.8.0; `binaryVersion` 1.1.15.

### LR-S01a — field names + Q3 (2026-08-14)

S01a ships the `alln models --json` overlay only. Menu / drivers / persist / bump stay on S01b.

**JSON words** (S01 owns them; promote in S07). Distinct fields — never inside `state` or `readiness`:

| Field | Meaning | Encode |
| --- | --- | --- |
| `discovered` | `/api/tags` showed this local tag and §2.3 did not hide it | bool, omit on paid rows |
| `enabled` | existing catalog word — the user turned it on | already required |
| `seated` | a `ModelCatalog` row bound to one body (`seatedID` or a custom add). This is what law means by seat | bool, omit on paid rows |
| `enableCommand` | S02 string `alln models enable <candidateID> --body opencode` | overlay rows only |
| `capabilityUnknown` | `/api/tags` had no `capabilities` field (or it was unparseable). Still visible | `true` only; omit otherwise |

`readiness: "Available"` remains seated-only. Overlay rows omit `readiness`. List-level `nextActions` stay empty-list-only.

**Q3 — would S01b (menu observing Ollama) fix the Opus 5 silent substitute?**

No. It needs its own slice.

The hypothesis that `MenuCLI` → `modelListJSON(observeOllamaReadiness: false)` is what `TeamExplicitSeats` reads is **false as a causal chain**. Those two paths do not share that flag.

- Default `alln menu --json` *does* call `ModelsCLI.modelListJSON` with the default `false`, so the seated local row paints `notChecked` / "Source not checked". **S01b will fix that paint.**
- Dry-run `alln run --dry-run` (what S00 ran) takes `runtime.readyModels` from `ToolRuntime.readyModels`, which calls `BenchReadiness.readyModels` **without** `ollamaLocal` (default `nil`). `isLocallyReady` on a nil snapshot is unobserved → not ready. `TeamExplicitSeats` / `TeamResolver` then treat the pin as unavailable and substitute Opus 5.
- Foreground `RunService.run` is a different ready-set: `readyModels()` is every enabled model, and `sourceReadyModelIds()` *does* observe Ollama. The S00 substitute was the dry-run path.

S01b's job (menu `localRuntime`, observe Ollama on that builder, `drivers --json` pointer, contract bump) does not pass a snapshot into `ToolRuntime.readyModels`. Wire that snapshot on a later slice — not here.

### LR-S04b — run ready-set observes Ollama (2026-08-14)

`ToolRuntime.benchReadySet` takes one `OllamaLocalDoctorReport.snapshotIfAllowed` per invocation and passes it into `BenchReadiness.readyModels`. Tests still get `nil` (no socket). A seated+enabled local row with Ollama reachable and the body CLI installed is in the ready-set, so `models --json` / `menu --json` / dry-run agree.

**S00 Q3 now passes (fixture).** A Team with `preferredModelId` on a seated local id, Ollama observed reachable, resolves to the **local** seat, not Opus. S00 pinned both Lead and crew to the same id; Lead reservation must not hide that explicit local pin. Proof: `LocalRuntimeSurfaceS04bTests.testS00Q3PinnedLocalResolvesWhenOllamaObserved`.

**Substitution honesty (superseded 2026-08-15).** LR-S04b made local-pin fallback loud and left paid-pin fallback buried. Founder law now forbids crossing the local/cloud boundary at all, and requires one honesty disclosure for same-side substitution. See the 2026-08-15 addendum below.

**Founder question (answered 2026-08-15):** never silently reseat any explicit pin onto the other side of the local/cloud boundary. Refuse. Same-side substitution stays, with one honesty standard.

Contract stays 10.9.0; `binaryVersion` 1.1.15. No wire change.

### Local/cloud substitution law (2026-08-15)

Founder ruling (2026-08-15): "NEVER substitute a CLOUD with a LOCAL seat and vise versa. They are so different it is not just about capability but also about speed."

Promoted to `docs/operations/Project_Laws.md` §Local and cloud seats. This is a product invariant, not a packet detail. Contract stays 10.9.0. `binaryVersion` 1.1.18.

S00 Q3 was local-out: a pinned free local model silently resolved to Opus 5. The ollama-label guard from `7e71b7ec` only stopped a local seat being substituted in. Both directions now refuse when the only candidate would cross. Same-side (cloud to cloud, local to local) still proceeds, with one honesty disclosure. The refusal names the asked-for model, says it is unavailable, and points at `alln menu --json`. User intent, not a sensor veto — same refuse-class as the write lock and parked drivers.

### LR-S03 — `opencode-local status` observes `/api/tags` (2026-08-14)

`OpenCodeOllamaSetup.status` re-reads `/api/tags` via the same observer as setup
(read-only — never writes `opencode.json`). `ollamaTagsObserved` can be true;
`ollamaLiveTagIds` vs `ollamaModelIds` reports drift (`ollamaTagsInSync`,
`ollamaTagsMissingFromConfig`, `ollamaTagsExtraInConfig`). Ollama unreachable →
unobserved, never an empty live list. Merge + reclaim stay on S02b enable/setup.
Fixture proof: `OpenCodeOllamaSetupTests.testStatusObservesLiveTagsAndReportsDrift`,
`testStatusInSyncWhenLiveMatchesConfig`, `testStatusUnreachableIsUnobservedNotEmptyLiveList`.
Contract 10.8.0 → 10.9.0; `binaryVersion` 1.1.15.

### LR-S04 — pin-ability (2026-08-14) **SKIPPED — already works**

No new code. Evidence:

- S02a/S02b mint `.discovered` seated ids; `ModelCatalog.list()` /
  `get()` / `resolvedModels()` include them (`mergedDefinitions` loads disk;
  `materialize` keeps non-built-in rows whose `driverId` is installed).
- S00 Q2: `alln run --model <custom-local-id> --dry-run` resolved (custom path).
- S04b: seated+enabled local enters `BenchReadiness.readyModels` when Ollama is
  observed; `preferredModelId` resolves to the local seat
  (`LocalRuntimeSurfaceS04bTests.testS00Q3PinnedLocalResolvesWhenOllamaObserved`).
- This slice adds `--model` choke-point proof for `.discovered` origin:
  `LocalRuntimeSurfaceS04Tests.testDiscoveredSeatedIdListsAndResolvesExplicitModel`.

---

### LR-S05b — Mac LOCAL RUNTIME section (2026-08-14)

Settings › CLIs ships `LocalRuntimeSectionView` bound to
`LocalRuntimeSurfacePresenter` + `LocalRuntimeAdvisory` (Core). Four installed-state
rows, tag toggles (off by default), §2.2 advisories, distinct Ollama reachable dot.
Out of scope here: body-selector persist (LR-S05c), hosting-body pointer rows.

### LR-S05c — persisted default body + hosting-body pointer (2026-08-14)

Section selector writes **one** persisted default body (`local_runtime.json` via
`LocalRuntimeDefaultBody`). It applies to the next enable only — seated ids are
not reminted; there is no "switch every enabled seat" verb.

OpenCode / Claude Code cards consume `drivers --json` `localRuntimeSeats` as
one non-selectable `Ollama · N models` pointer on the hosting body only.
Enabled seated local rows stay off the body roster, out of the card's model
total, and are not a `models[]` entry. The non-hosting body shows nothing.

Proof: `LocalRuntimeSurfaceS05cTests`.

Visual Proof Gate — four installed-state fixture renders landed 2026-08-15
(fixture bug: capture fired from `RootView.onAppear` before `TeamStudioView`
mounted; deferred to `LocalRuntimeSectionView.onAppear`). PNGs at
`docs/qa/gui/_captures/local-runtime-{both,opencode-only,claude-only,neither}.png`.
layout-watcher **not** run in this slice — pixels await a sighted reviewer.

Fixture proof: `LocalRuntimeAdvisoryTests`, `LocalRuntimeSurfacePresenterTests`,
`ChromeCatalogTests`.

---

### LR-S07 — vocabulary and law promotion (2026-08-14)

Promoted packet §6 into `docs/workflows/Product_Vocabulary.md` §Local runtime
(discovered / enabled / seated split; `Available`/`Unavailable` seated-only;
verbatim *Ollama provides the model; a CLI provides the tools.*). Amended
`docs/operations/Project_Laws.md` §Local Ollama seats: **seat** = body-bound
catalog row, not a pulled tag. Help topics `opencode_local_setup` and
`claude_local_isolation` teach the shipped enable path
(`alln models enable <candidateID> --body …`), `alln models --json` /
default `alln menu --json` `localRuntime`, and `alln drivers --json`
`localRuntimeSeats`. Code SSOT names added to law/vocab.

**Founder question (not implemented):** `AGENTS.md` first-routing table still
links vocab `§Local Ollama readiness`; the promoted heading is now
`§Local runtime`. Update the router on archive, or keep the old anchor label?

### Live dogfood — 1.1.15 binary, 2026-08-15

Two honesty defects on the rebuilt 1.1.15 CLI. Both shipped in **1.1.16**.
Contract stays **10.9.0** (no wire change: doctor check names and
`models delete` `ModelListJSON` are unchanged; unregister disclosures go to
stderr, same as enable).

**DEFECT 1 — doctor still called an unseated pulled tag Available.**
`ollama pull smollm2:135m` then `alln doctor --json` painted
`source.ollama_local.readiness` as `smollm2:135m: Available; …` for a tag
that was not seated. Cause was already in §0.3: `readinessDetail` walked
every `/api/tags` name as `ollama/<tag>` plus catalog `localSeatLabels`.
§3 rule 8 and §9 Done-when required seated-only; no prior slice landed it.
`alln models --json` already omitted `readiness` on overlay rows.

Fix: `OllamaLocalDoctorReport.readinessDetail` walks **seated labels only**.
`source.ollama_local.models` still lists pulled tag names (inventory).
Fixture: `OllamaLocalDoctorReportTests.testPulledUnseatedTagsAreInventoryNotReadiness`,
`testReadinessListsSeatedLabelsOnly`.

**DEFECT 2 — delete did not unregister `opencode.json`.**
`alln models enable <id> --body opencode` registers the tag (S02b).
`alln models delete <seated-id>` left it behind. Live: after deleting the
seat, `opencode-local status` reported `ollamaTagsExtraInConfig: ['smollm2:135m']`,
`inSync: false`; the PM had to hand-clean the real config.

Fix: `LocalRuntimeSeatDelete.delete` is the inverse of S02b merge. Deleting
a seated local row unregisters that tag when no remaining OpenCode seat
still needs it, and discloses `Unregistered from opencode.json: <tag>.` on
stderr. Tests pass a fixture `opencodeConfigURL`; XCTest without an override
refuses the real `~/.config/opencode/opencode.json` and still deletes the
catalog row. Fixture: `LocalRuntimeSurfaceDeleteTests`.

**Corrected 2026-08-15 (closeout P1):** unregister only tags that seat's mint
persisted on `addedOpenCodeModelIds` — the same ownership `OpenCodeOllamaSetup.undo`
uses (`receipt.addedModelIds`). A pre-existing tag, a setup-receipt-owned tag,
or a Claude-body delete must leave `opencode.json` alone.

### Closeout Code Audit P1/P2 (2026-08-15)

Recorded in packet §10.

**P1 — delete ownership.** Enable persists `merge.addedModelIds` on the seated
row. Delete unregisters only those ids, and only when no remaining OpenCode
seat needs the tag and the setup receipt does not own it. Claude-body delete
is a no-op on `opencode.json` (byte-identical). Replaced
`testClaudeSeatDeleteUnregistersWhenNoOpenCodeSeatRemains` with
`testClaudeSeatDeleteLeavesOpenCodeConfigByteIdentical`. Required fixture:
`testSetupRegisteredTagSurvivesSeatDelete` (setup registers → seat → delete →
tag remains).

**P2 — SubstitutionResolver same-side.** `resolveAuto` / `resolveRequested`
now apply `LocalSeatPinHonesty.sameSide` so Mac Team Control, Threads, and
`defaults` cannot cross the local/cloud boundary. Proof:
`DefaultModelSettingsTests.testRequestedNeverCrossesLocalCloudBoundary`,
`testAutoNeverPicksLocalForCloudTierDefault`. Law SSOT list now includes
`SubstitutionResolver`.

Contract stays **10.9.0**. `binaryVersion` **1.1.18**.

---

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| Local models missing from the app or `alln models`; a newly pulled tag not appearing | This packet §0.3 (verified state) + §0.5 + §4 |
| Which agent body runs a local model, and how the user picks | §0.1 ruling 2, §0.2, §0.5 body-selector write; code `OllamaLocalSeatEnablePolicy.allowedBodies`, `ClaudeLocalIsolation` |
| Ollama as a driver / an alln-owned tool loop over Ollama HTTP | Refuse — packet 1 §3; `ollama run` is a completion CLI, G0 only |
| Local seat readiness, provenance, isolation, served context | Archived [`OpenCode_Local_Ollama_Seats.md`](../archive/phases/OpenCode_Local_Ollama_Seats.md); law `Project_Laws.md` §Local Ollama seats |
| Egress policy / keeping the frontier model away from source | [`Context_Firewall.md`](Context_Firewall.md) — packet 2; unaffected by this work |
