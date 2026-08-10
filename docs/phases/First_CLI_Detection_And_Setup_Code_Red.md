# First CLI Detection & Setup — CODE RED

Status: **CODE RED — OPEN — v4 (CLI-first parity; curl|sh co-equal)**
Owner: AllnighterCLI (`detect`, `doctor`, `menu`, `bootstrap`) + install faucet
(`scripts/get-alln.sh` / `ReleaseChannel.installCommand`) + AllnighterCore
(`BenchTallyProjector` TBD, `SetupStore`, `ProbeFreshnessGate`, `BenchReadiness`,
`MenuCatalog`, `TeachingSnippet` / `HelpTopicRegistry`) + AllnighterMac
(`BenchHealthBadge`, `ThreadEmptyStateBody`, `ReadinessView`, Home first-run frame)
Created: 2026-08-10
Revised: 2026-08-10 (v4 — founder correction: CLI-only / CLI-first must work;
Mac app is not the only first proof)
Origin: First open of the Mac app showed amber **`0/9 ready`** with zero probes.
Founder follow-up: many users never open the app — they install with
`curl -fsSL … | sh` and live in `alln` / host agents. That path must find CLIs
and reach a working bench with the **same truth** the GUI would show.

Related (read before coding — do not relitigate closed law):
- **Home empty-state CLI pills (model grain bug):** [`First_Launch_CLI_Strip.md`](First_Launch_CLI_Strip.md)
  — separate packet; marketing chips ≠ capacity; fix grain/color/tap only
- **Intake / CLI-first:** `docs/workflows/SSOT_Founder_Input_Workflow.md`,
  `docs/workflows/SSOT_Feature_Workflow.md` (§CLI-First Rule, Teaching Surface)
- Install faucet: `docs/phases/One_Paste_Cold_Start.md`, `scripts/get-alln.sh`,
  `ReleaseChannel.installCommand` (today: `https://get.allnighter.io`)
- Live setup intent: `docs/phases/setup/00_First_Run_Setup_Experience.md`,
  `docs/phases/setup/01_CLI_Detection_Auth_And_Bench.md`, `docs/phases/setup/README.md`
- Launch Authority (Mac Dock process-quiet): archived
  `docs/archive/phases/Launch_Authority_TCC_Hotfix.md`
- Same-day TCC: `docs/operations/debugger/2026-08-10-first-launch-tcc-popups-PACKET.md`
- Cursor Agent CLI: archived `docs/archive/phases/setup/Cursor_Agent_CLI_Support.md`
- Freshness: archived `Probe_Freshness.md`; open `Vendor_Signal_Isolation.md`
- Vocabulary: `docs/workflows/Product_Vocabulary.md`

Phases are ephemeral. Closeout: promote tally + first-scan / detect authority
into setup docs, help, and AGENTS routing; code stays SSOT; archive this packet.

---

## Founder intake (SSOT_Founder_Input_Workflow)

```text
Founder intent:
  First CLI detection & setup is CODE RED. After install, the product must see
  what is on the machine and get seats ready — ideally with no ceremony, else
  one honest action per installed CLI. Cursor without the Agent CLI gets a
  dead-simple path. This must work for curl|sh CLI-only users, not only the
  Mac app. CLI and GUI share one contract.

Product value:
  "You already pay for the team" is proven at first use — whether that use is
  `alln menu` after curl, or opening the Dock app.

Trusted workflow slice:
  install alln → detect/find CLIs → ready seats in SetupStore → menu/run/GUI
  all read the same tally (never grade an unscanned host as 0/catalog).

Current state:
  - `alln detect` exists and persists via SourceProbeService → SetupStore.
  - Mac cold launch is process-quiet (cache only) → virgin app paints 0/9.
  - Install/bootstrap teach `menu --json`, not "find your CLIs / alln detect".
  - No shared BenchTally; badge/thread invent a catalog ratio; CLI paths do
    not project an honest never-scanned headline either.
  - Cursor IDE ≠ cursor_agent; CLI and GUI both under-teach that.

Truth owner:
  SetupStore probe records + CLIDetector smoke; one BenchTallyProjector in Core
  consumed by CLI JSON/text AND Mac chrome (never a second ratio).

CLI surface (required — Feature Workflow CLI-First Rule):
  - `alln detect` — intentional first scan (human or agent); persists SetupStore
  - `alln doctor` / `alln doctor --full` — recovery; must not invent 0/catalog
  - `alln menu --json` — session front door; must expose tally / never-scanned
  - `alln bootstrap` + get-alln stdout — teach detect (or equivalent) after install
  - Optional later: `alln detect --json` contract field for agents (if missing)

Help surface:
  Topics/search: detect, doctor, first run, find CLIs, cursor agent vs IDE.
  Recovery: empty help search → doctor / detect / menu.
  Installer/bootstrap must name only ContractRegistry-resolvable commands.

Proof scenario:
  A) curl install on a Mac with ≥1 signed-in agent CLI, never open Dock app:
     after one detect (or taught auto-path), menu shows ready seats; run works.
  B) Virgin Dock app: never shows 0/9; Find my team / detect parity.
  C) Cursor IDE only: both CLI and GUI offer Agent CLI install+login+recheck.

Blocking questions:
  1. Public install host: founder said get.allnighter.app; code/docs SSOT is
     get.allnighter.io (`ReleaseChannel.installCommand`). Domain rename is OUT
     of this packet unless founder explicitly opens One_Paste cutover — cite .io
     until then.
  2. Post-install auto-detect: may get-alln / first `menu` offer or run detect?
     Default: teach + one explicit `alln detect` (agents can run it); do not
     silent-smoke inside every menu.
  3. Soft-gate Home until ≥1 ready? Default: keep non-trapping (existing law).

Next slice:
  FCS-S01 Core BenchTallyProjector → FCS-S02 CLI contract + teaching → FCS-S03
  Mac chrome reads same tally. No Mac-only "fix" that leaves curl users cold.
```

---

## 0. Code-red claim (one sentence)

**After `alln` is on the machine — via curl or the app — Allnighter must find the
CLIs the user already pays for (or put each one one honest action away), and
CLI + GUI must tell the same story. Never grade a host we have not scanned
against the size of our support catalog.**

`0/9 ready` in the app is one symptom. An agent that only ever runs `alln menu`
after curl and never learns to `detect` is the same failure in another coat.

---

## 1. Two first-user paths (co-equal)

| Path | How they arrive | First proof today | What must be true |
| --- | --- | --- | --- |
| **CLI-first / CLI-only** | `curl -fsSL https://get.allnighter.io \| sh` (SSOT string), then host agent / terminal | Install → bootstrap paste → `menu --json`; detect exists but is under-taught | Never need the Dock app. Detect + SetupStore + menu/doctor tally. Cursor path in CLI text/JSON. |
| **Mac app first** | Open Allnighter.app | Process-quiet Home + amber `0/9 ready` | Same SetupStore. Same tally. Framed Find my team = the GUI face of `alln detect`. |

**Parity law:** Anything the badge may claim, `alln menu --json` (and doctor)
must be able to claim from the same projector. Anything `alln detect` persists,
the app must load without a second probe authority. No GUI-only readiness
semantics (Feature Workflow CLI-First Rule).

**Launch Authority scope:** process-quiet / TCC applies to the **Dock app
identity**. `alln detect` / `doctor --full` are already explicit user/agent
intent in a terminal — they are the CLI Shape A. Do not "fix" CLI-only by
spawning probes from Mac `onAppear`.

---

## 2. What the founder saw (Mac) — still true; incomplete alone

| # | Observed | Code |
| --- | --- | --- |
| 1 | Title-bar **`0/9 ready`**, amber | `BenchHealthBadge` — `SetupViews.swift` |
| 2 | Empty thread **`0/9 CLIs ready`** | `ThreadEmptyStateBody` — `ThreadView.swift` |
| 3 | Composer seats **"Not detected"** with no detect run | `AppModel.composeBench` |
| 4 | Capacity down-set empty when records empty | `HomeNewRunPane.notReadyOrParked` |
| 5 | No scan affordance; setup never auto-opens | `RootView` → `loadCachedSetupState()` |

### CLI-side gap (v4 addition)

| # | Gap | Why it hurts curl users |
| --- | --- | --- |
| 6 | get-alln / bootstrap push `menu --json`, not find-CLIs / `detect` | Agents start "using" Allnighter with an empty SetupStore and opaque not-ready drivers |
| 7 | `alln detect` prints per-driver lines + assembled team, but no shared never-scanned **headline** contract for menu/doctor | Front door and detect can disagree in tone/shape |
| 8 | No requirement that menu JSON expose the same tally the GUI will use | GUI-only projector would violate CLI-first |
| 9 | Cursor Agent vs IDE under-taught on CLI help/bootstrap | Same confusion as the app, for Hermes/OpenClaw/Cursor-host agents |

### The two numbers (Mac badge) — lie is the slash

| Symbol | Code | Meaning |
| --- | --- | --- |
| **X** | `readyToolCount` | Smoke-ready records (empty cache ⇒ 0 measurements, not "0 ready") |
| **Y** | `totalToolCount` | Support catalog size (build-time constant) |

**The lie is the slash**, not the zero. Same law on CLI: do not print or JSON-encode
a readiness ratio when `measured == 0`.

### Absence-of-record trap

Never-probed = **no** `ToolProbeRecord`. Filtering `toolStatuses` for problems
makes a virgin host look fine (capacity) or falsely "Not detected" (composer).
`setupCards` already enumerates supported drivers → `notChecked`. CLI list/
doctor/menu drivers path must keep that discipline; Mac must adopt it.

---

## 3. First principles

1. **Never measured is a state, not a value** — everywhere: badge, thread, menu, doctor.
2. **A ratio claims two measurements** — catalog size ≠ machine readiness.
3. **Enumerate the supported set**, not only observed records.
4. **Ready = smoke token only** (`isSmokeReady`). No IDE / Keychain / dashboard.
5. **Asymmetric costs** — false ready is loud; false absent deletes a paid seat.
6. **First proof is the product** — for curl users, the first proof is CLI.
7. **Spawning is attributed intent** — Mac: press; CLI: `detect` / `doctor --full`.
8. **CLI-first / one contract** — GUI presents CLI truth; never a parallel tally.

---

## 4. Anti-patterns

| Anti-pattern | Why banned |
| --- | --- |
| `0/<catalog> ready` (GUI or CLI) on unscanned host | Unmeasured ratio |
| Mac-only BenchTally with no menu/doctor/detect projection | Breaks CLI-first + curl users |
| Teaching install → menu without a find-CLIs / detect step | Agents skip the first proof |
| Silent Mac `onAppear` full smoke | Launch Authority / TCC class |
| Silent smoke on every `alln menu` | Quota + surprise; teach detect instead |
| Inferring ready from Cursor IDE / configs / Keychain | Honesty law |
| Hard-gating the app (or CLI) behind ≥1 ready | Non-trapping law |
| GUI-only Cursor card with no CLI equivalent copy/JSON | Parity failure |
| Second surface recomputing X/Y from ready/total counts | FCS-L5 |

---

## 5. Standing law (do not repeal)

- **CLI-First + Teaching Surface** (`SSOT_Feature_Workflow.md`).
- **Launch Authority** for Dock app cold launch (archived hotfix).
- **Non-trapping** (`00_…` §3).
- **Honesty** (`01_…` §5) — five-way status split.
- **Freshness asymmetry** (`ProbeFreshnessGate`).
- **One SetupStore** — `alln detect` and Mac setup write/read the same records
  (`SourceProbeService` / `SetupStore`). Parity means shared persistence, not
  duplicated probe caches.

---

## 6. Ideal outcome

**CLI-only (within ~60s of curl on a machine with ≥1 signed-in agent CLI):**

1. Install stdout / bootstrap tells the human or agent to **find CLIs**
   (`alln detect` or successor verb — must resolve in ContractRegistry).
2. After detect: menu/doctor show **found / ready / needs step** honestly —
   never `0/9`-style catalog grade when unscanned.
3. `alln run` / team dispatch can seat a ready model without opening the app.
4. Cursor-without-Agent: detect/doctor/help name install + `agent login` +
   re-detect.

**Mac app:** same SetupStore and tally; framed **Find my team** is the GUI of
detect; badge never amber-grades an unscanned host.

**Both:** next launch/session with warm cache stays quiet (no TCC storm; no
re-smoke unless asked).

---

## 7. Shape A vs B (both surfaces)

| Shape | CLI | Mac |
| --- | --- | --- |
| **A — one scan** | `alln detect` (explicit) | Framed Home **Find my team** → `runFullSetupProbe(userInitiated: true)` |
| **B — roster / per-CLI** | detect/doctor per-driver lines + fix commands; optional later `detect --driver` | CLI setup page; one primary action per card |

**Default:** A then B as recovery on both. CLI already has A (`detect`); teach it
after install. Mac needs the framed press (not `onAppear`).

**Hard constraint (Mac):** zero child processes until press. **CLI:** detect is
the press; menu must not become a hidden detect.

---

## 8. Missing truth owner: `BenchTallyProjector` (Core — shared)

One pure projector in **AllnighterCore** (mid-slice proof via
`scripts/swift-test.sh`). Mac **and** CLI call it.

```text
BenchTallyProjector.tally(registry:records:parked:now:) -> BenchTally

BenchTally {
  supported: Int
  measured: Int
  ready: Int
  needsStep: Int
  notInstalled: Int
  needsCheck: Int
  headline: Headline   // .configurationMissing | .neverScanned |
                       // .partial | .allReady | .noneReady
}
```

Rules (unchanged from v3, binding):

- `supported == 0` ⇒ `.configurationMissing` (not never-scanned).
- Else `measured == 0` ⇒ `.neverScanned` — **type carries no ratio**.
- Else mechanical `.allReady` / `.noneReady` / `.partial`.
- `supported` never used as chrome/CLI denominator; setup/doctor prose may say
  "we support N".
- Parked excluded; dedupe by latest `lastProbeAt`; ignore unknown manifests.
- Before `needsStep`, apply `ProbeFreshnessGate.unassertableNegatives` —
  expired/inferred negatives → `needsCheck`.

### Projection map

| Headline | Mac badge / empty thread | CLI (`menu --json` / doctor / detect summary) |
| --- | --- | --- |
| `.neverScanned` | **Find my team** (neutral) / "No CLIs checked yet" | `tally.headline: neverScanned` + nextAction `alln detect` — **no** `ready/total` ratio fields used as a grade |
| `.partial` | **`N ready`** (± needs step) | same counts + driver rows |
| `.noneReady` | **Set up CLIs** | fix commands per driver |
| `.allReady` | **`N ready`** positive | ready counts |
| `.configurationMissing` | Setup unavailable | doctor sources-loaded failure |

Exact JSON field names are part of the slice contract bump — one schema, GUI
reads the same meanings (even if GUI only uses text today).

---

## 9. Cursor IDE vs Cursor Agent CLI

Same implementable path as v3 (§ catalog fields). **Parity:**

- CLI: detect/doctor/help print installHint + login + docs; never call the IDE
  the seat.
- GUI: Cursor-without-CLI card; Re-check must call
  `runSetupProbe(..., onlyDriverId: "cursor_agent")` (not full-bench only).
- No process-list / `~/.cursor` inference on either surface.

---

## 10. Execution start here

**Do not ship Mac badge copy alone.** Order:

1. **FCS-S01** — `BenchTallyProjector` + Core tests (foundation).
2. **FCS-S02** — CLI contract + install/bootstrap teaching (curl path works).
3. **FCS-S03** — Mac badge + empty-thread consume the same projector.

S01 alone is not dogfood-complete for founder’s CLI-first correction; S01+S02 is
the minimum that makes `curl | sh` users whole. S03 removes the app’s `0/9`.

---

## 11. Slices

### FCS-S00 — Packet + board (this document)

Works Test: builder knows CLI-first order and will not Mac-only the tally.

### FCS-S01 — Core `BenchTallyProjector`

- Files: `BenchTallyProjector.swift` + `BenchTallyProjectorTests.swift` in
  AllnighterCore.
- Works Test: fixtures for empty records ⇒ `.neverScanned` (no ratio); empty
  registry ⇒ `.configurationMissing`; dedupe; parked; unknown; freshness;
  partial/all-ready.
- Proof: `scripts/swift-test.sh --filter BenchTallyProjectorTests`
- Out of scope: Mac UI, CLI wiring (those are S02/S03).

### FCS-S02 — CLI contract + post-install teaching (curl path)

- Goal: never-scanned and partial tallies are visible on the agent front door;
  install/bootstrap teach detect.
- Truth owner: MenuCatalog / DoctorReport / detect summary + TeachingSnippet /
  HelpTopicRegistry + get-alln bootstrap invocation (print only).
- Exact touchpoints (adjust only with contract discipline):
  - `alln detect` summary line from `BenchTally` (text; `--json` if contract needs it)
  - `alln menu --json` exposes tally headline/counts (contract bump as required)
  - `alln doctor` uses same headline (no invented catalog ratio)
  - bootstrap cold-start / TeachingSnippet / help: `alln detect` after install,
    Cursor Agent ≠ IDE search hit
  - get-alln already calls bootstrap — ensure that paste includes find-CLIs
- Works Test (falsifiable):
  - Empty SetupStore: `menu --json` tally headline is `neverScanned` (or
    equivalent), and does **not** encode a ready/total grade; `nextAction` /
    teaching names `alln detect`.
  - After detect with one ready fixture store: headline/counts show 1 ready.
  - `alln help search cursor` distinguishes Agent CLI vs IDE.
- Proof: Core/CLI tests via `scripts/swift-test.sh --filter` on menu/doctor/
  teaching/detect tests touched; contract export if schema changes.
- Out of scope: Mac badge (S03), Mac framed scan (S04).

### FCS-S03 — Mac chrome reads the same tally

- Files: `AppModel.benchTally`; `BenchHealthBadge`; `ThreadEmptyStateBody`;
  presentation tests + GUI proof.
- Works Test: empty cache → badge **Find my team** (neutral), thread **No CLIs
  checked yet**; no `0/`; one ready → **1 ready**. Same numbers as CLI would
  show for that store.
- Proof: Core filter already green; Mac assertions at **one** closeout
  `bash scripts/check.sh`; GUI proof per Visual_Proof_Gate.
- Out of scope: RootView scan frame, probing changes.

### FCS-S04 — Mac framed first scan (GUI Shape A)

- Home frame, press-only → `runFullSetupProbe(userInitiated: true)`; results use
  roster. Recording seam: appear ⇒ 0 spawns; double-press ⇒ 1 probe.
- Proof: LaunchAuthority + AppModel recording tests; founder TCC reset.

### FCS-S05 — Roster recovery + Cursor card (GUI Shape B) + CLI copy parity

- Setup cards; login docs URL mapping; per-driver recheck; Cursor card from
  catalog; CLI detect/doctor already show statuses — align copy/help.

### FCS-S06 — Selection surfaces (composer + capacity down-set)

- Enumerate supported drivers; never-probed → "Not checked"; capacity down-set
  must not treat empty records as all-up.

### FCS-S07 — Teaching closeout / ASF questions

- Answer founder-input help closeout questions for detect/tally/cursor.

### FCS-S08 — Promote + archive

- Update setup `00`/`01`, debugger regression backlog FCS-L*, archive packet.
- Founder dogfood: **curl path without opening app** AND virgin app path.

---

## 12. Regression laws

| # | Law | Enforced by |
| --- | --- | --- |
| **FCS-L1** | No readiness ratio when never measured (CLI or GUI) | BenchTally + projector tests + menu JSON test |
| **FCS-L2** | No "what's wrong" set from filtering only existing records; absent → not checked | S06 + driver list tests |
| **FCS-L3** | Ready only from smoke token | `isSmokeReady` |
| **FCS-L4** | No Mac launch/on-appear CLI spawn | LaunchAuthorityProbeTests + TCC packet |
| **FCS-L5** | Exactly one tally owner; CLI and GUI both read it | Projector in Core; menu + badge tests |
| **FCS-L6** | Cursor IDE never seats `cursor_agent`; copy never equates them | SetupCursor + help search tests |
| **FCS-L7** | curl|sh / bootstrap path teaches find-CLIs (`detect`) before assuming a bench | Install/bootstrap/teaching tests (v4) |

---

## 13. Out of scope

- Renaming get.allnighter.io → .app (One_Paste / release channel packet).
- Capacity acquire / serve / remote relay (separate 2026-08-10 work).
- New vendors, pricing, iOS.
- Cinematic 6-scene onboarding.
- Keychain / dashboard / IDE process inference.
- Auto-smoke on every `menu` invocation.
- Repealing process-quiet for warm Mac launches.
- Auto-installing CLIs for the user.

---

## 14. Done when

- [ ] curl|sh user can detect and run with ready seats **without** opening the app.
- [ ] Unscanned state never shows `0/<catalog> ready` in GUI or CLI grade form.
- [ ] One Core projector; menu/doctor/detect summary and Mac badge agree.
- [ ] Install/bootstrap/help teach `alln detect` (or registry-resolvable successor).
- [ ] Cursor-without-Agent obvious on CLI and GUI.
- [ ] Selection surfaces do not claim unmeasured seats.
- [ ] Warm Mac launch stays process-quiet; TCC-reset dogfood PASS when untouched.
- [ ] FCS-L1…L7 each have a test or explicit waiver.
- [ ] Help closeout questions answered for the new teaching.

---

## 15. Debug fingerprint

```text
Tier: T2 SSOT (readiness) — T3 if probe authority / TCC regresses
Symptom: virgin app 0/9; curl users never taught to detect; CLI/GUI tally drift risk
Fingerprint: catalog denominator over empty SetupStore (Mac) + install→menu
  without find-CLIs teaching (CLI) + absence-of-record display traps
Truth owner: SetupStore + smoke; BenchTallyProjector (missing)
Lie-prone layer: readyToolCount/totalToolCount ratios; record-only filters;
  Mac-only fixes; bootstrap that skips detect
Fix boundary: shared tally + CLI teaching + Mac chrome + press/detect scan.
  No silent menu smoke, no silent Mac onAppear smoke, no domain rename here
Proof:
  scripts/swift-test.sh --filter 'BenchTallyProjectorTests|…menu/doctor/teaching…'
  bash scripts/check.sh   # closeout — Mac call sites
  Founder A: curl install → detect → menu ready (no app)
  Founder B: tccutil reset → open app → touch nothing → CTA, zero dialogs
```

---

## 16. Version history

| Ver | Date | Author | Change |
| --- | --- | --- | --- |
| v1 | 2026-08-10 | Intake | Claim, RCA, Shape A/B, FCS-S00…S06 |
| v2 | 2026-08-10 | Opus | Ratio-as-lie; absence-of-record trap; BenchTally in Core; Shape decision; Cursor from catalog; FCS-L1…L6 |
| v3 | 2026-08-10 | Sol | Code-checked touchpoints; S01-first dogfood; falsifiable proofs; Home-first Shape A |
| v4 | 2026-08-10 | Founder correction + intake | **CLI-first / curl\|sh co-equal**; founder intake block; parity law; FCS-S02 CLI contract before Mac chrome; FCS-L7; install/bootstrap must teach detect; .app vs .io flagged out of band |
