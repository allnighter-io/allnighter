# Project Laws

Standing product and engineering laws. Compact restatement of the
incident-preventing subset lives in `AGENTS.md` § Project Laws — this file is
the durable home. Code that enforces a law is the runtime SSOT; this file is
the human-readable owner when the rule is not (or not only) a check.

Do not paste new law into `AGENTS.md`. Promote it here (or into the code), then
add a one-line route from the router if a new task type needs it.

## Capacity (2026-08-12)

`alln capacity` is a **daily-use** surface: the founder reads the strip and
routes work by hand. The 2026-08-12 kill covers **automated seat selection
only** (archived `docs/archive/phases/Capacity_Warm_Bench.md`). Never degrade
acquisition for any source. "No code consumer" ≠ "no consumer".

Reactive park/substitute is unchanged and evidence-based: vendor states the
limit at the moment of failure (`CapacityClassifier` →
`VendorBackoffPolicy.shouldPark` → `SeatReseat`). Capacity is a sensor: it
never durably parks (that is user intent via `alln drivers park`) and never
gates seat selection. Stale paint ⇒ unknown (`CapacityPaintGate`). Vocabulary:
`docs/workflows/Product_Vocabulary.md` §§Capacity, Quota-aware bench.

**Do NOT gate the pane-reader fallback behind `sawUsagePane`.** Today the model
reader fires on ANY empty parse, without requiring that the usage pane was
recognised — and that is deliberate. A 2026-08-12 review proposed gating it on
"a pane was detected but the regex failed", framed as saving tokens on splash /
boot screens. **Rejected (founder, 2026-08-12).** Pane detection is part of the
deterministic stack; gating the fallback behind it disables the fallback exactly
when a vendor redesign breaks the markers — the one failure it exists to survive.
The seat would go silently unknown with the safety net switched off by the same
break. Grok redesigned its usage view into a tabbed modal the same day this was
argued; the fallback firing on "we captured something we could not read" is what
keeps that readable. If the trigger is ever narrowed, it must be to
"captured but unreadable", never to "recognised but unparsed".

Token cost is not a reason to narrow it: one read on the vendor's own cheapest
model is rounding error against the quota being measured.

## Vendor signals

Promoted from archived `docs/archive/phases/Vendor_Signal_Isolation.md`.

- A derived signal is attributed to the source that produced it. One vendor's
  parser, matcher, or heuristic never answers for another vendor's output —
  scope it by `sourceId`, not by whichever pattern happens to match first.
  The same bound applies to seat readiness: an OpenCode Zen probe must not
  classify a local Ollama seat; a leftover `opencode serve` model list must
  not answer for tags registered after that serve started.
- Absence of a declared signal yields no observation, never an inferred one. A
  false positive here is silent and expensive; a missed signal fails loudly and
  is cheap. Fail closed.
- A locally computed value is never presented as a vendor-stated fact. Local
  boundaries and vendor-sourced truth may both exist, but the storage, the
  confidence, and the user-visible wording must keep them distinct.

Code SSOT: AgentOS `CapacityClassifier` (every matcher scoped by `sourceId`),
`VendorBackoffPolicy.shouldPark`, `CapacityPaintGate`, `SeatReseat`.

## Bench tally / probe records

Promoted from the closed First CLI Detection CODE RED. **Not** owned by
`docs/phases/setup/` — that packet is the engineering spec, not the law.

Code SSOT: `BenchTallyProjector`, `ProbeRecordMerge`. Every SetupStore writer
routes through `ProbeRecordMerge`.

1. **An unscanned host is never graded.** No records ⇒ `neverScanned` with no
   ratio. Never `0/9 ready`, which reads as "you own nothing" when the truth is
   "nobody has looked yet". Buckets are `ready` / `needsStep` / `notInstalled` /
   `needsCheck`; a missing record is `needsCheck`, never `notInstalled`.
2. **Failure to observe is never observation of absence.** A pass that resolves
   no path may not overwrite a prior `ready` record whose executable still
   exists. A stale negative that no longer holds is a seat the user pays for,
   silently benched.
3. **Teach with a live pointer, not a copied instruction.** `alln bootstrap`
   does not hardcode "run `alln detect`"; it routes to `alln menu --json` and
   tells the caller to run `benchTally.nextAction`.
4. **Cursor IDE ≠ Cursor Agent CLI.** Opening the IDE does not seat
   `cursor_agent`; the seat is the headless `cursor-agent` binary (and not
   Grok's `agent`).

## Sensors vs invariants

Readiness, health, capacity, provenance, and other derived-state instruments
**inform**; they never **block** an explicit request. The owner's request takes
precedence and fails loudly if it fails. Parked driver, disabled model, unknown
model id, the per-root write lock, and a local/cloud seat substitution (see
§Local and cloud seats) still refuse (user intent / real invariants); sensor
readings alone never veto. **Provenance is not a refuse-class** — an explicit
Loop `--pm` of a local Ollama-backed seat discloses local provenance and served
context once, then proceeds (`ab86226e`;
`docs/archive/phases/OpenCode_Local_Ollama_Seats.md`). Allnighter does not decide
which model is worthy of leading.

## Local and cloud seats (2026-08-15)

Founder ruling (2026-08-15): "NEVER substitute a CLOUD with a LOCAL seat and
vise versa. They are so different it is not just about capability but also
about speed."

Automatic substitution must never cross the local/cloud boundary, in either
direction. Not for an explicit pin, not for capability staffing, not for
fallback. Today's one-way guard (a local seat is never substituted *in*) is
not enough: a local seat substituted *out* to a paid seat is the S00 Q3 bug
(`docs/phases/Local_Runtime_Surface.md` §10) — a pinned free local model
silently resolved to Opus 5.

When the only remaining candidate would cross that boundary, refuse. Do not
substitute. The refusal names the model that was asked for, says it is
unavailable, and gives the command to pick another.

Same-side substitution (cloud to cloud, local to local) still proceeds, with
one honesty disclosure for both. A buried warning for paid pins and a loud
one for local pins is the same lie-prone split.

This refusal is user intent, not a sensor veto. It sits with the per-root
write lock, parked drivers, disabled models, and unknown model ids. It does
not weaken "sensors inform, never block": Allnighter is not refusing because
a sensor is unhappy. Allnighter is refusing to hand the user a fundamentally
different product than they asked for.

Code SSOT: `TeamResolver.selectModel`, `LocalSeatPinHonesty`,
`VendorSubstitutionPolicy`, `SeatReseat`, `SubstitutionResolver`.

## Local Ollama seats

Promoted from archived `docs/archive/phases/OpenCode_Local_Ollama_Seats.md`
(2026-08-13); seat definition amended 2026-08-14 (LR-S07). Code SSOT:
`OllamaLocalRuntimeClient`, `OllamaLocalDoctorReport`, `OllamaLocalModelDiscoveryProvider`,
`ModelDiscoveryProvider`, `ModelCatalog`, `LocalRuntimeSeatMint`,
`ModelCatalog.saveDiscovered`, `LocalRuntimeSeatDelete`, `LocalSeatPinHonesty`, `LocalRuntimeDefaultBody`,
`LocalRuntimePointerPresenter`, `LocalRuntimeAdvisory`, `ClaudeLocalIsolation`.
Help: `opencode_local_setup`, `claude_local_isolation`, `loop` §local-dev.

- **Seat means a body-bound catalog row, not a pulled tag.** A tag Ollama reports
  on `/api/tags` is **discovered** until the user seats it — minted with
  `alln models enable <candidateID> --body <claude_code|opencode>` (via
  `LocalRuntimeSeatMint` → `ModelCatalog.saveDiscovered`) or the manual
  `models add` custom path. Doctor and `alln models` must not call an unseated
  tag Available. Discovered tags surface on `alln models --json` and default
  `alln menu --json` `localRuntime`; enabled seated counts surface on
  `alln drivers --json` `localRuntimeSeats` on the hosting body only.
- **Readiness is Available or Unavailable, per seated row.** A seated row is
  Available when Ollama is reachable and that seat's tag is pulled locally.
  Ollama down makes every seated local row Unavailable. Failure to observe is
  not Available. This is **not** capacity: never a strip row, never
  `benchSourceOrder`, never a quota word. Surface via `alln models` / `doctor`.
  Signal id `ollama_local` is attribution only.
- **Busy was cut** because resident-in-memory is the fast case (dogfood host:
  warm first-byte ~0.6s, cold ~20.9s) and the word inverted a scarcity warning.
  Ollama queues; Busy never refused work. Keep calling `/api/ps` for served
  context. Do not smuggle latency back in as a readiness state.
- **Provenance is not a refuse-class** (see §Sensors vs invariants). A local
  seat may hold the Loop PM chair when explicitly pinned. Disclose local
  provenance and the served window once, then proceed.
- **One vendor's probe never answers for another seat's readiness.** Closed
  incidents: OpenCode Zen smoke disabling a local Ollama seat (`3d0ae06b`);
  leftover `opencode serve` caching its model list so later tags looked missing
  (`53c14465`). Same law as §Vendor signals.
- **Advertised `tools` is lie-prone.** A tag can declare `capabilities.tools`
  and still text-fake (`qwen2.5-coder:7b`). Automatic Code offers require
  advertises-tools **and** a G1 structured `tool_calls` pass. **A G2 harness
  mutate does not predict a G3 `alln` path pass.**

## Run ownership

- Projects own repo/folder scope for new work; regular chat in a project is an
  agent running in the repo root (the Default Team) — code SSOT
  `RunService.swift`.
- Exactly one mutating worker per repo root, under `RunWriteLockRegistry`.
  Research Teams are parallel and observational. Enforced by
  `scripts/check_architecture_policy.sh` (no mirror, clone, or blanket
  read-only layer).
- Judgment teams may mix sources; mutating/`execute` teams must resolve to one
  CLI/source before dispatch.
- A command that returns without queued work must leave none behind: if
  `alln run` reports failure, no later process may execute that request. Prove
  a host will claim before queuing, and refuse loudly — one typed terminal
  answer — when none will.

## Product truth

- Founder/user input is intent, not final authority.
- SwiftUI may render truth; it must not invent durable product truth.
- Owned SwiftUI state uses Observation; no `ObservableObject`/`@Published` era
  state in app-facing code (`docs/operations/SwiftUI_State_Rules.md`).
- Prompt prose may request work; it must not be the only owner of semantics.
- Generated output (parsers, design bundle) is derived. Change the source
  contract, then regenerate — never hand-edit generated artifacts.
- CLI, GUI, and iOS must share the same team-run contract; do not invent
  parallel JSON around `TeamRunJSON`.
- Mac and iOS do not share SwiftUI views or app-target GUI code; share
  Core/Engine + CLI only (`docs/gui/GUI_Workflow.md` §5).
- Forward Mac app work targets a standalone Dock app plus explicit background
  coordinator. The menu bar is status/quick controls, not the product shell.
- Mac app is unsandboxed by design; still minimize privilege surface and
  document every permission request.
- iOS companion connects only to the user's own Mac over Tailscale/local
  network by default. No mandatory third-party coordination cloud.
- Agent bridge configs describe how to spawn CLI agents; they must not become
  hidden runtime truth for session state.

## How we build

- Every feature slice needs one owner-visible Works Test or an explicit waiver.
- Every non-trivial bug fix names the truth owner, lie-prone layer, and missing
  proof before editing.
- Maintenance preserves behavior unless the task is explicitly a bug fix.
- Do not mix broad cleanup into a feature or bug fix.
- Prefer deterministic checks over recurring agent judgment.
- A failed worker is shown failed, never faked. Hide the plumbing (legacy
  panel / council / master-plan words, worktree, subprocess).
- A test may not reach a live vendor or the user's real state — Green Wall
  (`docs/operations/Execution-Playbook.md` § Green Wall). Code SSOT
  `AllnighterSupportRoot` (`.xctest` support-root redirect) and
  `WorkerInvokerFactory` (`routeOpenCodeToServe`).
- Pure model name = newest in family; versioned ids stay exact pins
  (`docs/workflows/Product_Vocabulary.md` §pure name).

## Entitlement / buy path (2026-08-13)

Promoted from `docs/phases/Trial_And_Entitlement.md` once V1 was public.
Offer numbers stay in `docs/marketing/Pricing_Recommendation.md`. Code SSOT:
`Entitlement.swift`, `BillingCLI.swift`, `RunService.run`, `infra/pay`.

- **Stripe Checkout with email is the cash register.** Sign in with Apple is
  not required to buy. SIWA stays for iPhone pairing later. The website DMG
  cannot carry SIWA (Apple forbids it on Developer ID).
- **No Buy button on allnighter.io.** Strangers install, then pay from the Mac
  overlay or `alln billing checkout`. Hosted Checkout URL lives in JSON `url`;
  the human opens it. **`nextAction.command` is never a Stripe URL** (an agent
  would exec it). Compiled command: `alln billing checkout --plan monthly --json`.
- **Identity is a machine hash** (HMAC over IOKit `IOPlatformUUID`). The raw
  UUID never leaves the machine. Email lives on the Stripe customer for
  receipts. Cross-machine sync is not V1.
- **One Stripe account in production:** Allnighter live on `pay.allnighter.io`.
  Never xterminal’s Keychain live key. Never point the production Worker at
  the Allnighter sandbox. Tests never hit live Stripe (Green Wall).
- **Admission is one call site:** `RunService.run`. A loop admits once at
  start (`EntitlementAdmission.skipInnerDispatch`). In-flight runs are never
  killed. Discovery (`menu`, `help`, `doctor`, `billing`) is free forever.
- **Degrade never bricks:** server down → 72h provisional trial, then local
  3/day. Entitlement token is a `0600` file under Application Support —
  **never Keychain**.
- Public floor: CLI + Mac **1.1.3** on `get.allnighter.io`
  (`docs/operations/Public_Release.md`). Pay Worker is `pay.allnighter.io`,
  not the faucet.
