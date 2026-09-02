# Local Runtime — Brief

**Tier:** C as named by LR-S05 in `docs/archive/phases/Local_Runtime_Surface.md`.
**Escalation (flagged, not resolved):** see **Tier flag** below. Founder call.
**Visual kit:** Settings › CLIs midnight page (`TeamStudioView` `.clis` /
`TeamReadinessView`). Tokens: `docs/design-system/production.md`. No dedicated
ui-kit specimen — packet §2.1 mockup is the visual target.
**Behavioral owner:** `docs/archive/phases/Local_Runtime_Surface.md` §0.1, §2.1–§2.4.
**Contract:** 10.9.0. GUI consumes shipped Core/CLI; it does not invent fields
or walk sockets.

Do not re-derive the packet. This brief binds the Mac half of rulings 1, 2, 4,
and 5.

---

## Tier flag — founder call

Packet LR-S05 labels this **Tier C** (new Settings section). `GUI_Workflow.md`
§3 / invariant 13 escalate to **Tier D** when UI touches run/dispatch state.

Enabling a local tag mints a seated catalog row. After LR-S04b, a seated+enabled
local pin is in `BenchReadiness.readyModels` and the run path will dispatch it.
S04b exists because a pinned local seat was silently substituted onto a **paid**
seat when the ready-set ignored Ollama. The toggle is therefore not paint: it
changes what the run path can dispatch.

This brief does **not** re-tier the work. Implement to the packet's Tier C
reads unless the founder escalates to D (then also read
`docs/workflows/SSOT_Feature_Workflow.md` + the owning contract already named
above). Visual Proof Gate applies either way.

---

## Purpose

Settings › **CLIs** grows a **LOCAL RUNTIME** section so a user who has pulled
an Ollama tag can see it, pick one harness body, and turn it on. Ollama is
inference, not an agent body. Pairing in three words: **Ollama via OpenCode**.

LOCAL RUNTIME is its **own class**, never a READY body row (ruling 5, §2.4).
It is the only list of local tags. Enabling nothing is a valid steady state —
visibility is the guarantee (ruling 3 / rule 6).

---

## Home

Settings › **CLIs** (`StudioRoute.clis` → `TeamReadinessView`). Not Default
model. Not a body card roster. Pointer on the hosting body card jumps here.

Labels the Mac draws come from `ChromeCopy` and, once S05 ships them,
`alln chrome --json` on `settings.clis`. Do not hard-code a second set.

---

## States

### Section — four installed-state rows (packet §2.1)

Installed means the body CLI is present on `alln drivers --json`. One of:

| Installed | Runtime row |
| --- | --- |
| both bodies | `Ollama via OpenCode / Claude Code` + section-level selector |
| OpenCode only | `Ollama via OpenCode` (no selector) |
| Claude Code only | `Ollama via Claude Code` (no selector) |
| neither | `Ollama · N models · needs OpenCode or Claude Code` — **no ready dot**, install action |

### Surface completeness (GUI_Workflow §4)

| State | What the user sees |
| --- | --- |
| loading | Section chrome visible; tags not yet painted as empty. No "0 models" lie. |
| empty — unobserved | `menu --json.localRuntime` **absent** (Ollama not observed on this snapshot). Copy: unobserved, not "no tags". Seated local rows that exist paint Unavailable (law). |
| empty — zero tags | Ollama observed, `tags: []` after §2.3 filter. Honest zero. Ready dot still follows the ready-dot law. |
| empty — neither body | Neither row above. Install action names the missing body. Enable command on a tag still names the missing body. |
| populated | Tag list from the overlay. Off is the default. Mixed on/off is normal. |
| enable in flight | Toggle already flipped (it always flips). Row waits on the CLI result. |
| enable failed | Honest CLI error. Toggle returns to the last persisted `enabled`. |
| done | Store matches `models --json` / `menu.localRuntime` after the write. |

There is no "running" inference on this surface. A local seat that is executing
lives on the run grid, not here.

### Per-tag row

- **Discovered, not seated, not enabled** — default. Off. `enableCommand` is
  the affordance. `readiness` absent (not `Available`).
- **Seated, enabled on / off** — catalog row bound to one body. `Available` /
  `Unavailable` apply here only.
- **capability-unknown** — `/api/tags` had no `capabilities` field. Still
  visible. Not dropped. No name heuristic. The **title** is still derived from
  the tag (`OllamaLocalDisplayName`); "no name heuristic" means we do not
  guess capability from the name.
- **Removed tag** — `ollama rm`: tag leaves the discovered list; a seated row
  becomes Unavailable, not deleted.

**Row title.** Always derive a readable display name from the Ollama tag
(`gpt-oss:20b` → `GPT-OSS 20B`, `qwen3.8:27b-mlx` → `Qwen3.8 27B`). Keep the
raw tag on the secondary line (`ollama/<tag>`). Do not use a catalog `--name`
as the title — a user who pulls three models must not get two raw tags and
one audit nickname.

**ON toggle.** Always accent (`--accent`). Amber means the tag is enabled.
The neither-state install chrome does **not** restyle the switch; an earlier
white-vs-amber split across fixtures was accidental environment tint, not a
"enabled but no body can host it" signal.

**Repeated advisory.** Per-row when the sentence is actually about that
model (G1 failed, a served window like `32K`, capability-unknown plus G1
unknown). When every visible row would print the same sentence (typical
cold tags: window unobserved, or G1 never run), lift it once to
`sharedAdvisory` under the list. Repeating "Allnighter will know this
model's context size after it runs once." three times is noise, not
information.

---

## Ready-dot law

The ready dot on the **runtime** row means **Ollama is reachable**.

It does **not** mean a seat can run work. Do not reuse the READY body-row
`●` asset if that asset means "this CLI can run work."

The **neither** installed-state row has **no** ready dot, even if Ollama is
up. Install is the action.

Ollama down: no ready dot; discovered list is unobserved, not empty.

---

## Advisory reasons (packet §2.2) — never gates

`allowsAutomaticCodeOffer` is the automatic-Code **offer** predicate, only
when both inputs are **observed**. It does not read advertised `tools`. The
toggle always flips. Automatic Code offers stay gated.

**Never** print `text-fakes` or `too small for Code` on nil inputs. That
marks every cold tag "not recommended" and violates
failure-to-observe-is-not-absence.

Print only this table. Same string or same enum as the CLI twin (Works Test D)
— not GUI-only prose. If `models --json` has no dedicated advisory field yet,
raise the contract gap and bind a Core presenter to this table. Do not invent
copy in the view.

| What we have | What we print |
| --- | --- |
| G1 failed (observed) | G1 failed — structured `tool_calls` missing. Enable still works. |
| G1 never run | G1 unknown. Not a fail. |
| Served window observed and `< 65536` | Served window N (below automatic Code floor). Enable still works. |
| Served window unobserved | Window unobserved (tag not in `/api/ps`). Not a fail. |
| Advertised `tools` without a G1 pass | Do not write "text-fakes." We have not proven a fake. |

`capabilityUnknown: true` is a shipped field (no capabilities on the tag). It
is not a fail and is not "not a completion model."

---

## Body selector (ruling 2)

**One** section-level selector, not per-model. The body is a harness
preference — same weights, same runtime, same tokens.

- Both bodies installed: `via [ OpenCode ▾ ]` (default body `opencode`,
  packet §0.2). Popover via `alPopover` (`1.GUI-Invariants.md` 9b).
- One body: label only, no picker.
- Write persists the default for the **next** enable only. Does not remint
  in-flight or already-seated ids (`seatedID` encodes the body). No
  "switch every enabled seat" verb.

---

## Hosting-body pointer (ruling 5 + §2.4)

LOCAL RUNTIME is the only list. Each body card may show **one**
non-selectable pointer, and **only** the body that currently hosts seats:

```text
── Ollama · N models  →          (jumps to LOCAL RUNTIME)
```

| Rule | Why |
| --- | --- |
| Only on the hosting body | The other card has zero local seats. Do not paint a zero or "disabled." |
| Counts **enabled seated** rows for that body | Discovered-not-enabled tags are hosted by nothing yet. |
| Not selectable, not in the card's model total, not a `models[]` entry | A pointer is a cross-reference, not a seat. |
| Wording is `Ollama · N models` | Not "Ollama Enabled." Count-first; *enabled* is ambiguous. |

Both bodies may show the row if the user hand-seated the same tag twice via
`models add`. That falls out of count > 0; no special case.

Do not put local seats on the OpenCode or Claude Code rosters.

---

## Intents

- Open Settings › CLIs → bind the section from the CLI JSON named below.
- Change section body → persist default body (next enable only).
- Flip a tag on → `alln models enable <candidateID> --body <body>` using the
  section default (`claude_code` \| `opencode`). Always flip; print
  `Assessment.disclosures`; do not gate.
- Flip a seated tag off → existing catalog `setEnabled` (`enable <seated-id>`
  with no `--body`). `--body` on an already-seated id refuses — do not send it.
- Neither-state install → the install action already used for a missing CLI
  on this page. Do not invent a new installer.
- Pointer tap → scroll/focus LOCAL RUNTIME. Not a seat pick. Not a roster
  select.
- Re-check all (existing CLIs control) → refresh the same overlay the CLI
  uses. Still no `/api/tags` from the view.

---

## Data source

The GUI **must not** walk `/api/tags` or `/api/ps`. The GUI **must not**
treat `alln doctor` `source.ollama_local.models` pulled names as seats.
Doctor `source.ollama_local.readiness` is per **seated** label only.

| Element | Feed | Field |
| --- | --- | --- |
| Section exists / tag roster (agent + human parity) | `alln menu --json` | `localRuntime` (`defaultBody`, `tags[]`: `id`, `label`, `enabled`, `seated`, `enableCommand`, `capabilityUnknown`). **Absent** = Ollama unobserved, not `tags: []`. |
| Completeness of that collection | `alln menu --json` | `completeness.localRuntime` |
| Overlay / seated detail, readiness, display name | `alln models --json` | `discovered`, `enabled`, `seated`, `enableCommand`, `capabilityUnknown`, `modelLabel`, `displayName`, `driverId` (body when seated), `readiness` (seated only; omit / never `Available` on overlay) |
| Per-row enable affordance | same | row `enableCommand` — not list-level `nextActions` |
| Which bodies are installed; pointer count | `alln drivers --json` | body `status`; `localRuntimeSeats: N` **omitted when zero** |
| Section / control labels | `alln chrome --json` + `ChromeCopy` | `settings.clis` rows once S05 ships them |
| Ready dot (Ollama reachable) | same observation that projected `localRuntime` | `localRuntime` present ⇒ observed; absent ⇒ unobserved. Not a body `status: ready`. |
| Advisory line | Core presenter of observed G1 / served window → §2.2 table | Never `allowsAutomaticCodeOffer` on nil. CLI twin required. |
| Doctor | `alln doctor --json` | Cross-check only. Never a seat list. |

Do not stuff off local tags into tier-1 `menu.models[]`. Do not read
`state: available` as law `Available`.

---

## Field Ownership Ledger

| GUI field | Core / CLI field | Source | States | Test owner |
| --- | --- | --- | --- | --- |
| Section title | `ChromeCopy` + chrome row (S05) | Core | all | ChromeCatalogTests |
| Installed-state copy | derived from which of `opencode` / `claude_code` appear on `drivers` | `DriverListJSON` | all four | presenter + Mac A |
| Selector value | `menu.localRuntime.defaultBody` | `MenuJSON.LocalRuntime` | both-bodies | LocalRuntimeSurface S01b + GUI presenter |
| Tag name / `ollama/<tag>` | `tags[].label` / models `modelLabel` | menu + models | populated | S01a/S01b + Mac D |
| Off / on | `enabled` | menu tag + models row | populated | same |
| Seated | `seated` | same | populated | same |
| Enable affordance | `enableCommand` | overlay rows only | discovered-not-seated | S01a |
| Capability-unknown mark | `capabilityUnknown` (`true` only) | same | when set | S01a |
| Seated readiness | models `readiness` `Available` \| `Unavailable` | seated rows only | seated | ModelListProjector + doctor seated-only |
| Runtime ready dot | Ollama observed (`localRuntime` present) **and** not neither-state | menu + drivers | populated / empty-zero | Mac C/D |
| Pointer `Ollama · N models` | `drivers[].localRuntimeSeats` | `DriverListJSON.Entry` | count > 0 | S01b + Mac D |
| Body on a seated row | models `driverId` | seated id encodes body | seated | S02 |
| Advisory | §2.2 table from observed G1 / window | Core presenter; CLI twin | populated | presenter; never GUI-only |
| Install (neither) | existing missing-CLI action on this page | drivers `notInstalled` | neither | existing CLI-setup tests |

A GUI field with no core field → stop. Do not invent it.

---

## SwiftUI state ownership

Per `docs/operations/SwiftUI_State_Rules.md` and
`docs/gui/1.GUI-Invariants.md`.

- Domain truth lives in `AllnighterCore` (`MenuJSON.LocalRuntime`,
  `ModelListJSON.Entry`, `DriverListJSON.Entry`) held by the existing
  `@MainActor @Observable` app model. Views render; they do not mint seats
  or write `opencode.json`.
- View-owned: `@State` for popover open, scroll-to-section, in-flight
  enable id. Selector binding into the observable model uses `@Bindable`.
- Injected app model: `@Environment(AppModel.self)` — already the CLIs
  page pattern. No new Combine-era wrappers.
- **Forbidden:** `ObservableObject`, `@Published`, `@ObservedObject`,
  `@StateObject`, `@EnvironmentObject`.
- Derived copy (installed-state sentence, pointer wording, §2.2 advisory)
  lives in a testable presenter, not inline in the view.
- Mac-only views under `Apps/AllnighterMac/`. Do not share SwiftUI with
  iOS (`GUI_Workflow.md` §5).
- Intents call the shipped CLI (`alln models enable … --body …`). The
  view does not call `OllamaLocalModelDiscoveryProvider.discover()` or
  open a socket.

Nothing is ON by default (ruling 4). Discovered-not-enabled tags render
off. The toggle control is not disabled by G1 or window.

---

## Out of scope

- Walking `/api/tags` or `/api/ps` from the app.
- Treating doctor pulled names as seats.
- ON-by-default; reminting every seat when the selector flips.
- An Ollama `DriverManifest`; an Allnighter-owned tool loop over Ollama HTTP.
- A G1 runner / G1 store.
- Local seats on OpenCode / Claude Code rosters; namespace grouping of
  paid cards (LR-S06 dropped).
- Putting the section on Default model.
- Reusing the READY body-row ready-dot asset for "Ollama reachable."
- `alln sweep` on the menu; Context Firewall; Second Mac; residency / OCL-S05.
- iOS companion surface.
- Starting a run from this section.

---

## Visual Proof Gate

Layout-only. `docs/gui/Visual_Proof_Gate.md`. Content/data truth stays with
CLI/Core tests (Mac A + D). Closeout seals after a **layout-watcher** PASS.
The building agent does not sign its own pixels.

Render each fixture with `bash scripts/gui_proof.sh <fixture>`, then spawn
layout-watcher on the PNG. Seal:

```text
bash scripts/gui_proof_seal.sh local-runtime <slug> <fixture> [<fixture>...]
```

### Screenshots that must be captured

| Fixture (proposed) | Why it exists |
| --- | --- |
| `local-runtime-both` | Both bodies. Section + selector + mixed off tags. Ready dot = Ollama reachable, visually distinct from body READY dots. |
| `local-runtime-opencode-only` | `Ollama via OpenCode`, no selector. |
| `local-runtime-claude-only` | `Ollama via Claude Code`, no selector. |
| `local-runtime-neither` | `needs OpenCode or Claude Code`. **No ready dot.** Install action visible. |
| `local-runtime-pointer-host` | Hosting body card shows one non-selectable `Ollama · N models`. N excluded from that card's model total. |
| `local-runtime-pointer-other` | Non-hosting body: **no** pointer (not a zero, not "disabled"). |
| `local-runtime-advisories` | Mixed §2.2 paths on-row: G1-failed string, observed window as `32K` (not `32768`), capability-unknown. No "text-fakes", no "too small for Code." `64K` is the automatic-Code floor so it is not an on-row advisory; the formatter is proven in Core tests. |
| `local-runtime-unobserved` | Ollama down: section does not say "0 models" / "no tags." Seated rows Unavailable. No ready dot. |
| `local-runtime-selector-open` | Section selector via `alPopover`, on-screen, not clipped. Compose-tier capture if the popover is a native overlay. |

Deep-link: Settings › CLIs (`studio-clis` / `StudioRoute.clis`), section in
view. Fixtures seed Core JSON — they do not open Ollama.

Watcher hunts: clip, overlap, collapse, off-screen, scrim/z-order, missing
section, pointer looking like a selectable seat, neither-state ready dot,
runtime dot indistinguishable from a READY body dot.

If the harness cannot render a named fixture, closeout is
`implemented, visually unverified` or `blocked` — never `fixed`.

---

## Mac proof (not this brief)

S05 close also proves packet Works Test **A** (Mac half) and **D** (chrome +
GUI parity). Fixtures never pull a live tag. Dogfood A is recorded in the
slice closeout, not XCTest.

Contract 10.9.0 already carries `discovered` / `enabled` / `seated` /
`enableCommand` / `capabilityUnknown`, `menu --json` `localRuntime`, and
`drivers --json` `localRuntimeSeats`. This brief does not change them.
