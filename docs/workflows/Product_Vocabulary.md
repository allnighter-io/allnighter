# Product Vocabulary

Standing word-list for product, GUI, CLI, and docs. **Not a phase packet.**

**Code SSOT for runs:** `RunService.swift`, `TeamPreset` / `TeamCatalog`,
`RunWriteLockRegistry`.
**Closed cutover records:** `docs/archive/phases/Language_Cutover.md`,
`docs/archive/phases/Work_Order_Team_Model.md`,
`docs/archive/phases/Team_Depth_Naming.md`.

Hard rule: **no aliases** for retired product words. Prefer rename over dual
paths.

---

## Human layer

| Word | Meaning |
| --- | --- |
| **Ask AI** | Title-bar door for questions about Allnighter on this Mac. Regular Auto run, inward prompt, read-only. Not a Team. Not the repo composer. Hatch: **support@allnighter.io**. Terminal twin: **`alln feedback`**. For where a control lives, the run calls **`alln chrome --json`**. The open project is not evidence about Allnighter UI. |
| **Feedback** | `alln feedback "<msg>"` — a short note to a person. Payload is quoted text + CLI version + OS only. `--dry-run` sends nothing. Failures fall back to emailing **support@allnighter.io**. Agents must not invent a message. |
| **Chrome catalog** | `alln chrome --json` — Mac owner-action rows projected from the labels the app draws (`ChromeCopy` / `ChromeCatalog`). Sibling of `alln menu --json`. Not doctor. Not a help article. The model writes the sentence. |
| **Chat** | The default turn surface inside a Project — a run of the Default Team. |
| **Delegate** | Hand intent to a team. UI label: **Send to team** (retired: Fan out). |
| **Execute** | Authorize a make-real / mutating send. **Not** a composer mode. |
| **Team** | The actor noun — the agent lineup you send to. |
| **Crafts** | **Code · Design · Copy** (+ **Signal** scout). Code was: Build. |
| **Signal** | Repo-aware scout: outside → insights (not “move cards”). |
| **Project** | Local repo/folder floor where work happens. |
| **Loop** | The family noun for a durable, multi-round PM↔dev object — **`alln loop`** in both the Mac composer and the CLI. It owns runs, survives the caller, and is resumable. The `kind` slot ships **empty** today; when a kind exists it names what *done* means (e.g. `research` = until questions are exhausted, `review` = until clean) — never a posture or a mechanism. The PM chair is an **occupant** — `caller` (a live agent session) or a spawned agent id — not a separate verb or mode. You brief it once (the **kickoff**) and it drives itself. |
| **Kickoff** | The founder's one-time brief to a Loop, round 1 only, delivered via `alln loop start "<what you want done>"`. Not chat, not the PM→dev handover, and not `founderNote` (which is resume-only). |
| **Pilot** | Retired as a CLI verb. What it named — a live agent CLI session holding the PM chair — is now `--pm caller` on `alln loop start`. The Mac app is never the PM seat, so it never exposes `--pm caller`. |

`lane` means **craft** (Code/Design/Copy/Signal). It is never “a single run.”

## Capacity vocabulary (promoted from the capacity packet, 2026-07-30)

| Term | Meaning |
| --- | --- |
| **Bench capacity** | What each paid CLI subscription has left. Vendor-printed only — never estimated, never projected. |
| **Acquisition ladder** | Where a seat's number comes from, cheapest first: on-disk log (tier 1) → structured stream (tier 2) → PTY probe of the vendor's own usage TUI (tier 3) → 429 failure classification (tier 4). |
| **Effective availability** | The tightest ceiling across all of a seat's windows. A fresh 5-hour window under an exhausted weekly is unreachable, so it reads 0. This is where Allnighter is deliberately **more honest than the vendor's own meter**. |
| **`neverSampled` vs `vendorExposesNothing`** | `neverSampled` = we did not look. `vendorExposesNothing` = the vendor genuinely has no usage surface. **Never claim the latter for a seat we ship a parser for** — blaming the vendor for our own gap is the lie this subsystem exists to prevent. There is a test enforcing it. |
| **Refresh, three affordances** | refresh-all (the routine glance, keeps rows comparable) · the **age chip is the per-row refresh** · `--refresh --source <id>` for agents · automatic pre-dispatch refresh that nobody clicks. |

Standing laws: no projections or forecasts, only observed facts and
retrospective arithmetic. Never zero-fill a missing sample. Unknown never
blocks dispatch. Nothing may trigger acquisition except launch, explicit
refresh, post-run piggyback, and pre-long-dispatch — events record from what is
already known, they never go and ask. Code SSOT: `CapacityWindow`,
`CapacityAcquisition`, `CapacityBenchProjection`, `CapacityStripRenderer`,
`CapacityHistoryStore`, and the five `*CapacityLog` parsers.

**Daily-use vs automated routing (2026-08-12).** Automated capacity influencing
seat *selection* is killed (feature creep). `alln capacity` remains a daily-use
surface: the founder reads the strip and routes work by hand. Never degrade
acquisition for any source. "No code consumer" ≠ "no consumer". Reactive
park/substitute (`VendorBackoffPolicy.shouldPark`, `SeatReseat`) is unchanged.
Full law: `docs/operations/Project_Laws.md` §Capacity. Closed record: archived
`docs/archive/phases/Capacity_Warm_Bench.md`.

## Local runtime (promoted 2026-08-14)

**Ollama provides the model; a CLI provides the tools.**

| Term | Meaning |
| --- | --- |
| **Local runtime** | An inference engine (Ollama) that supplies models to agent bodies. Never itself a body, never a `READY` row, never a seat. |
| **Discovered** | `/api/tags` showed this local tag and the capability filter did not hide it. Not enabled. Not seated. Not `readiness: Available`. Surfaces on `alln models --json` and default `alln menu --json` `localRuntime`. |
| **Enabled** | The user turned the tag on. Same word as catalog `enabled`. |
| **Seated** | A `ModelCatalog` row bound to one body (`seatedID(tag:bodyDriverId:)` or a custom add). This is what law means by **seat**. `Available` / `Unavailable` apply here only. |
| **Available / Unavailable** | Per **seated** row only — two words, unchanged law. Available = Ollama reachable **and** that seat's tag pulled. Never capacity, never `alln capacity`, never `benchSourceOrder`. Doctor and models share `OllamaLocalDoctorReport.readinessWord`. |
| **`ollama_local`** | Signal source for local runtime readings. Attribution only — not a strip seat. |
| **Busy / Idle (retired)** | Cut 2026-08-13. Busy meant resident-in-memory, which is the fast case, so the word inverted a scarcity warning. `/api/ps` still feeds served context; it does not mint a readiness word. |
| **G0–G3** | Model gate ladder. G0 inference; G1 structured `tool_calls`; G2 agent-body mutate; G3 `alln run` path. Advertised `tools` is lie-prone. **G2 does not predict G3.** |

Do not put `discovered` in `state` or `readiness`. Distinct JSON fields: `discovered`,
`enabled`, `seated`, `enableCommand`, `capabilityUnknown` (overlay rows only).

Standing laws: `docs/operations/Project_Laws.md` §Local Ollama seats. Code SSOT:
`OllamaLocalRuntimeClient`, `OllamaLocalDoctorReport`, `OllamaLocalModelDiscoveryProvider`,
`ModelDiscoveryProvider`, `ModelCatalog`, `LocalRuntimeSeatMint`, `ModelCatalog.saveDiscovered`,
`LocalSeatPinHonesty`, `LocalRuntimeDefaultBody`, `LocalRuntimePointerPresenter`,
`LocalRuntimeAdvisory`, `ClaudeLocalIsolation`. History: archived
`docs/archive/phases/OpenCode_Local_Ollama_Seats.md`; surface packet
`docs/phases/Local_Runtime_Surface.md`.

## Quota-aware bench vocabulary (promoted from QABC, 2026-08-09)

**Moat:** Anthropic can only see Anthropic's meter. Cross-vendor arbitrage is
impossible from inside any one vendor. Allnighter sees the whole bench and acts
on it at plan time and at the wall.

| Term | Meaning |
| --- | --- |
| **Plan-time quota** | `alln menu --json` and bootstrap carry a lean `capacity` block (decision rows, not the full strip). Injected from CLI with `refresh: false` — zero probes on read. |
| **Capacity park** | A vendor session cap mid-turn: run is `queued` + `waitingForVendor` with `blocker.wakeAfter`. A parked turn is **still in progress**, not a terminal outcome. |
| **Claim-or-adopt** | At wake, the loop claims the parked run lease or adopts the settled run if `alln serve` won the race — never escalates on a lost claim. |

Standing laws: check `vendorPark` **before** `LoopTurnClassifier` in both turn
dispatchers; never mint a competing `runId` while parked; parked loops stay
`status == .running` with facts in `capacityPark` (side-field, not a new status).
Capacity is injected into Core, never acquired there. Code SSOT:
`CapacityDisplayAcquisition`, `MenuCatalog`/`Bootstrap` injection,
`LoopCoordinator.resolveCapacityPark`, `VendorBackoffReconciler`,
`VendorSubstitutionPolicy`.

## Probe freshness vocabulary (promoted from Probe Freshness, 2026-08-09)

| Term | Meaning |
| --- | --- |
| **`lastDetectedAt`** | Cheap presence — binary still there, any check. Decays slowly. |
| **`lastProbeAt`** | Capability evidence only — a real smoke (`full: true`) or a successful completed run. Never invented on the cheap path. |
| **`evidenceSource`** | Where the freshness row came from: `"probe"`, `"run"`, or `"driver"` (model rows inherit the driver). |
| **`stale`** | Read-time projection: capability evidence is older than the 30m gate. Stale never asserts a negative — it weakens the claim. |
| **Three states** | **not detected** · **detected, never exercised** · **confirmed at T**. The middle state is honest for new users. |

Standing laws: readiness sensors **inform, never block** dispatch (`DispatchReadiness`).
A meter and a declared vendor refusal are **different facts** — neither disproves
the other. Expiry is read-time projection only; never mutate `cli_setup.json` from
a read path. **Failure to observe is never observation of absence** — a pass
that resolves no path may not overwrite a prior `ready` whose executable still
exists (`ProbeRecordMerge`). `alln serve` hosts two schedulers:
`CapacityRefreshScheduler` (capacity store) and `ProbeRecordRefreshScheduler`
(probe records, founder B periodic full smoke when stale). Code SSOT:
`ProbeFreshnessGate`, `ProbeFreshnessDisclosure`, `SourceProbeService`,
`CensusIngest`, `RunService` (capability clock writer),
`ProbeRecordRefreshScheduler`, `ProbeRecordMerge`. Full law:
`docs/operations/Project_Laws.md` §Bench tally.

**The `alln loop` grammar** — one object, one vocabulary, CLI and Mac alike:

```text
alln loop start "<what you want done>" [--spec <path>] [--pm caller|<agent-id>] [--dev <agent-id>] [--dry-run]
alln loop list | status | stop | resume | wait | step | pm
```

**Everything in brackets is optional. The brief is the only required input.**
`--pm` defaults to the Frontier tier and `--dev` to Balanced
(`DefaultModelSettings.swift`); `caller` is a reserved `--pm` value meaning the
live session holds the chair. `--spec` is a shortcut for handing the loop a
document to work from — it is not the shape of the feature. The loop's job is
multi-round work that produces commits, not a document; brief-only is the
headline form. There is no mode word and never will be — what varies across
invocations is **casting** (who holds the PM chair), never posture.

Founder Stop is `alln loop stop` (durable `stopped`, reason `founder stopped`,
PM Turn written, **not** resumable) — never `alln kill`, which is
process-ownership machinery, not a product verb.

**Law 1 — `kind` names what *done* means, when one exists.** The `kind` slot
ships empty today. When a kind is added, it names its own terminal condition
(`research` = until questions are exhausted, `review` = until clean). Never
name a kind after a posture or a mechanism.

**Law 2 — the chair is an occupant, not a mode.** `--pm` takes `caller` (a live
agent session holds the chair) or a canonical agent id (a spawned agent holds
it). One slot, one word — there is no mode enum to keep in sync, and none
should ever be added.

**Law 3 — operations are defined against the state machine, never against who
holds the PM chair.** `step` (submit the next PM decision) is accepted only in
status `awaitingPM` and errors on the *status* for any other state — never on
the *occupant*. Every future loop operation follows this rule.

## Background scheduler vocabulary (promoted from ASR, 2026-08-11)

Hard cutover. Code SSOT: `ServeLifecycle`, `ServeDaemon`, `ServeStatusJSON`,
`CanonicalCLIInstall`. Host proofs: `docs/qa/alln-serve/`.

| Term | Meaning |
| --- | --- |
| **Background scheduler** (`alln serve`) | One supervised per-user daemon, started by launchd via the LaunchAgent `com.allnighter.resident-coordinator`. Owns deferred obligations only. Never owns run semantics. |
| **Deferred obligation** | Work `serve` wakes for: pending wake, PM turn wake, boost seed, vendor backoff, notifications, capacity refresh, probe record refresh. **`alln run` does not depend on serve** — attended work runs with serve dead or disabled. |
| **Canonical binary** | `~/.local/share/allnighter/bin/alln`. PATH symlink, LaunchAgent `program`, health, and update all name this one path. |
| **Binary match** | Decided by recorded **code identity**, never by version string. An unrecorded or not-yet-reported identity is *unknown*, never a mismatch. |
| **Stand-down** | Daemon exit `0`. launchd must **not** respawn it (`KeepAlive = { SuccessfulExit = false }`), and `serve status` shows `degraded` with `lastExitCode: 0` and a recovery command. A stood-down daemon is never silently absent. |
| **Crash** | Signal death or nonzero exit. launchd **does** respawn, after `ThrottleInterval` (30 s). |
| **`starting`** | Bounded transient: supervisor loaded, daemon not yet through its first health handshake. Not `degraded`, and never prescribes a command that restarts the daemon. |
| **Disable persists** | A user disable survives logout/login and is never undone by a later install. Only `alln serve enable` reverses it. |
| **Foreign `HOME`** | Serve lifecycle is per-**user**, not per-`HOME`. A lifecycle command run with a `HOME` that is not the account home refuses (`SERVE_FOREIGN_HOME`) and mutates nothing. `serve status` stays readable. |

Wake bound: a deadline that comes due during system sleep fires **within 2
minutes of wake** — deadlines are wall-clock and re-evaluated on wake, not
timer-relative.

## Machine layer

One primitive: **run a team** (a solo agent is a team of one). A team carries
`craft` + `mutating:bool`. No approval gate on mutating runs — `RunService`
executes once the team resolves to one agent seat.

Retired ceremony (do not revive): propose → approve → dispatch → verify as a
separate Project Manager spine; posture enum `propose|review|execute|scout` as
product gates.

## Team model nouns

| Term | Meaning |
| --- | --- |
| **Source** | How Allnighter reaches a model (CLI/runtime). Setup/internal. |
| **Execution source** | The single source/driver that owns a mutating run. |
| **Bench** | Models the user has available. |
| **Parked** | A CLI the user has shelved — not probed, not seated, not in Needs attention, until put back **on the bench**. Not delete. CLI: `alln drivers park` / `unpark`. |
| **Model** | Recognizable AI identity (Opus, Grok, …). CLI pin: `--model <model_id>`. |
| **Pure name** | A catalog id that names a family without a generation (`model_grok`, `model_sonnet`). Always means the newest member of that family. |
| **Pin** | A versioned id (`model_grok_46`) or a vendor alias that is already exact. Never rematerialized. |

**Standing rule — a pure name is the newest in its family.** Two mechanisms, chosen per family, never mixed:

1. **Vendor alias** — the CLI itself accepts a name that always means latest (`opus`, `sonnet`, `fable` on Claude Code). We store the alias. The vendor keeps it current. Verified 2026-08-12: Grok CLI has no such alias (only `grok-4.6` / `grok-4.5`); Kimi and Cursor Agent also have none.
2. **Catalog-resolved** — pins declare `family` + integer `generation` in AgentOS `catalog.json`. A row with `family` and no `generation` is the pure name and inherits the highest declared generation. Generation is authored, never parsed from a label (`K3 > K2.7` would be `30 > 27`; Sol / Luna / Terra have no generation because they are siblings, not a ladder).

The rule does **not** apply when there is no unambiguous order: GPT Sol/Luna/Terra, Composer vs Composer Fast, Kimi HighSpeed. Those families either have no pure name or stay an explicit choice. Availability / parking is `VendorSubstitutionPolicy`, unchanged. Code SSOT: AgentOS `FamilyLatest`, `CatalogLoader`; Allnighter `ModelPinFact` on the run journal. Replay uses the pin, never the pure name alone.
| **Agent** | A staffed roster row: one **model** wearing one **skill** on a team. Count plural: **agents** (not models — four Auto seats are four agents, not four models). |
| **Skill** | Hat / instruction profile a model wears. Shared by `skillId` across teams; the editable body is **skill.md** (the `template` field in catalog JSON). Same-ID overrides edit in place; **Restore** drops the override. Mac drill-in: **Edit skill**. |
| **Type** | Optional subtype metadata inside a craft; not a Send-to-team selector. |
| **Reasoning effort** | Per-agent model reasoning (`low|med|high` when supported). Never changes lineup, depth, or flavor. |
| **TeamPreset** | Saved team definition (lane, agents, synthesis policy). UI says Team. |

**Retired (user-facing):** **Worker** — do not use in GUI, CLI flags, help, or
docs. Never teach `worker*` to humans.

**Machine contracts** (TeamRunJSON, floor, NDJSON stream, threads, pending,
handoff mailbox, spec retrieval): staffed seats expose **`agentId`**; catalog
pins expose **`modelId`**. Never overload one field for both meanings.

**Layer E (internal only — not product seats, not agent-facing wire):** journal
`TeamRun.workers`, `workerAnswer(workerId:)`, internal `RunEvent` payload keys,
process ownership (`WarmWorker*`, `kind: "worker"`), on-disk `workers/`
artifact directories. These stay until an explicit process-layer cutover.

Historical cutover record: `docs/archive/phases/Worker_To_Agent_Migration.md`.
Optional hygiene backlog (do not start by default):
`docs/archive/phases/Worker_To_Agent_Migration.md` (ship line complete; optional
hygiene backlog only).

Shortcut: *Model at rest. Agent at work (model + skill).*

### CLI pins (no aliases)

| Flag | Meaning |
| --- | --- |
| `--model` | Pin which model runs (`alln run`, `alln thread send`, `alln pending add`, …). |
| `--pm <caller\|agent-id>` | `alln loop start` PM chair occupant: `caller` (live session) or a canonical agent id (spawned). Optional — defaults to the Frontier tier. |
| `--dev <agent-id>` | `alln loop start` dev seat agent id. |
| `--seat` | Ordered model ids for one-off judgment-team staffing (not a synonym for `--model`). |

Retired flags: `--worker`, `--dev-worker`, `--pm-worker`, `--pm-model`,
`--dev-model`, `--relay`. The old `project workers` subcommand is retired in
favor of `alln project models`.

### Execution source gate

Judgment / research teams may mix sources. Mutating teams must resolve to
**exactly one** source/driver before spawn. Do not silently pick the first ready
source, flip mutating off, invent mirrors, or spawn multiple CLIs as “one”
execution team. Shared blocker: `EXECUTION_TEAM_MIXED_SOURCES`. Historical
proof: `docs/archive/phases/Execution_Team_Source_Gate.md`.

### Effort vs depth

- **Effort** = model reasoning only.
- **Depth** = a different **named Team** (Min / bare / Max), never an effort dial.

---

## Team depth naming (Min / Default / Max)

1. **Family name = the job** (Spec Review, Bug Hunt, …). One name in picker,
   docs, and marketing.
2. **Depth vocabulary:** Min / (bare name) / Max. IDs: `<family>_min` /
   `<family>` / `<family>_max`.
3. **Bare name is the default.** Picker may show “Default” as a UI label only —
   it never appears in the team name, ID, or CLI id.
4. **No numbers in names.** Seat count is metadata, not the name.
5. **Not every family ships all three tiers.** Unique names only for different
   jobs (e.g. Polish vs Usability Review), not for depth.
6. **Routing:** auto / default send → bare team. Min is always an explicit
   choice. Escalation may recommend Max; never silent switch.
7. **Min** = smallest curated roster that keeps the family’s core outcome.
   **Max** = every seat that earns its place on the hardest case class.

Roster truth lives in `BuiltInTeams.swift` / `TeamCatalog`.

---

## Substitution tiers (Frontier / Balanced / Economy)

Auto and healthy substitution draw from a **tier** — an ordered roster, not a
model property. Distinct from team depth (Min / bare / Max) and from caliber
(seating strength).

| Tier | Meaning |
| --- | --- |
| **Frontier** | Smartest models you are willing to spend on Auto |
| **Balanced** | Everyday workhorses |
| **Economy** | Lowest acceptable spend for Auto |

- IDs / CLI / JSON: `frontier` | `balanced` | `economy`.
- **Retired tier names:** `flagship`, `fast` — still parse from old settings files
  but must not appear in new Allnighter copy, help, or UI.
- **Never use “Fast”** as a tier label — vendor model names already use it
  (`Composer 2.5 Fast`, etc.).
- Code SSOT: `DefaultModelSettings.swift`, `DefaultSettingsJSON`, `alln defaults`.

## Trial, pay, Keep going (promoted 2026-08-13)

Offer numbers: `docs/marketing/Pricing_Recommendation.md`. Law:
`docs/operations/Project_Laws.md` §Entitlement. Code: `EntitlementCopy`,
`EntitlementChrome`, `BillingCLI`.

| Term | Meaning |
| --- | --- |
| **Run (meter)** | A dispatch: `alln run`, `alln loop start`, or Mac Run. Looking at capacity, help, doctor, or billing does not count. A loop counts once at start. |
| **Trial** | 14 calendar days unlimited, starting at first run, not install. No account. |
| **Free forever** | After trial: 3 of those runs per day, full product, nothing feature-locked. |
| **Builder** | $8/mo or $80/yr, unlimited dispatch within the user's own provider limits. |
| **Founding Builder** | $160 once, first 100, then retired. |
| **Keep going** | Mac overlay on the blocked 4th run. Quote: “That’s today’s three.” CTA is Keep going — $8/month, not a Stripe URL. |
| **`tellHuman`** | Verbatim paragraph on `ENTITLEMENT_LIMIT` / BillingJSON. Agents quote it; they do not paraphrase. |
| **`alln billing checkout`** | The buy command. Returns a hosted Checkout `url` for the human. Never put that URL in `nextAction.command`. |
