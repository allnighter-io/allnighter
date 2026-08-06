# OpenCode Go Capacity

Status: **Dogfood spike approved — qualification required before bench integration**
Owner: AllnighterCore (targeted dashboard acquisition + parser diagnostics) +
AllnighterCLI (existing `capacity` surface only during qualification)
Created: 2026-08-05
Revised: 2026-08-05 (SOL reliability review; baseline `adc582cd`)
Origin: Founder dogfood — OpenCode Go plan limits exist only on the browser
`/go` dashboard, not in the `opencode` TUI. ALLN meters six local CLI seats via
PTY; Go is the seventh seat with the **same per-source module shape**, but
acquisition is **browser HTTP scrape**, never `CapacityProbe` PTY.

Related shipped substrate (reuse, do not re-build):
[`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md),
[`Capacity_Warm_Bench.md`](Capacity_Warm_Bench.md),
`CapacityWindow`, `CapacityBenchProjection`, `CapacityStripRenderer`,
`VendorBackoffPolicy`, OpenCode **driver** (`OpenCodeServeClient` — dispatch
only). Parser behavior reference (not a runtime dep):
[`@slkiser/opencode-quota`](https://github.com/slkiser/opencode-quota).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

Baseline brainstorm (pre-review): `adc582cd`.

---

## SOL review (2026-08-05)

### Verdict: ship a smaller dogfood qualification slice, not v1 as specced

The full packet is **not Ready for Implementation**. A session-cookie HTML
scraper is an unstable adapter over an undocumented page, and the current proof
plan is too weak to justify putting its numbers in the normal capacity bench.
The official Go usage API request and PR remain open; the PR has not been
verified against the production backend. Waiting indefinitely is not warranted,
but neither is presenting a community regex port as product truth.

Evidence reviewed: `@slkiser/opencode-quota` 4.5.1 from the local npm cache,
especially `dist/lib/opencode-go.js` and `dist/providers/opencode-go.js`. It:

- regexes SolidJS `$R[...]` hydration internals and falls back to `data-slot`
  markup only when **none** of the SSR windows matched;
- treats any non-empty subset of rolling/weekly/monthly as success by default;
- does not reject duplicates or require two matching strategies to agree;
- clamps negative percentage/reset input instead of rejecting the sample;
- reports HTTP failures but has no positive classification for a followed
  redirect or HTTP 200 login page.

That is useful proof that the page can be scraped today. It is not proof that
the scrape is sufficiently stable or honest for Allnighter. The upstream
[official API issue](https://github.com/anomalyco/opencode/issues/16017) and
[unverified PR](https://github.com/anomalyco/opencode/pull/16513) were both open
at review time.

Build only a targeted, explicitly dogfood acquisition path first. It may be
promoted to the normal bench only after the reliability gate below passes. If it
does not pass, delete the spike and wait for the official API.

This review is binding where it conflicts with the candidate design below.
Before implementation, revise the rest of this packet to match it; do not treat
the older three-slice plan as an allowlist.

### Smallest reliable slice (founder-approved dogfood gate)

```text
OPENCODE_GO_WORKSPACE_ID + OPENCODE_GO_AUTH_COOKIE
  -> alln capacity --dogfood --refresh --source opencode_go [--json]
  -> either all three dashboard windows, atomically validated,
     or one typed unknown result with scrape diagnostics
```

**Without `--dogfood`:** `opencode_go` is an unknown `--source` (same error as a
typo). The spike is intentionally invisible to the normal agent front door.

**Not in v1 spike:** `benchSourceOrder` stays six seats; no Mac strip, menu
envelope, park/substitution, or `alln opencode-go configure|status`.

Cut from the qualification slice:

- encrypted file storage, `machine.key`, and crypto reuse;
- `alln opencode-go configure` and `alln opencode-go status`;
- interactive/hidden credential prompts and a new status JSON contract;
- default seven-seat refresh and unconditional normal-strip inclusion;
- Mac presentation, background refresh, menu, park/substitution, `/usage`, and
  any monitoring of the upstream community scraper.

Use the two named environment variables only, both-or-neither. This is a
deliberate dogfood constraint, not the final credential UX. Document a safe
launch-scoped export and warn against putting the cookie in shell history. If
the scrape earns promotion, make a separate decision about persistent storage;
do not prepay a bespoke AES-GCM credential subsystem for a parser that may be
deleted.

Do not add separate configure/status commands. The existing targeted
`alln capacity` command is the capability and its `--json` output is its status
surface. Add scrape-health fields to that existing observation/row contract if
the current unknown-reason shape cannot carry them. One command should answer:
was a fetch attempted, what was observed, which parser strategy matched, and
why no numeric value was emitted.

Keep all three windows in the parser. Cutting weekly/monthly saves almost no
acquisition complexity because the same response contains all three; requiring
the exact set is also a valuable page-integrity check. **Partial success is
failure.** If rolling, weekly, or monthly is missing, duplicated, ambiguous, or
invalid, emit no Go percentages. This is stricter and safer than the upstream
plugin, which accepts any subset it happens to parse.

### Ranked practical failure modes

| Rank | Failure | Why it matters | Required response |
| --- | --- | --- | --- |
| 1 | SolidJS hydration or `data-slot` markup changes | Deploys can rename fields, change serialization, reorder/nest markup, or move data to a client API | No numeric output; `schemaDrift`/typed parse health with strategy id |
| 2 | Expired/invalid cookie returns redirect or HTTP 200 login HTML | A status-only 401/403 check misses the common browser-auth shape | Detect 401/403, sign-in redirect/final URL, and positive login-page markers as `authRequired` |
| 3 | SSR stops carrying quota and the browser fetches it after load | Raw HTTP sees a valid dashboard shell with no numbers | Distinguish authenticated dashboard shell from login and from known data; fail closed |
| 4 | Partial or ambiguous parse | The most dangerous outcome is a plausible wrong number, not an obvious failure | Require exactly one valid value for each of three windows; reject duplicate/conflicting strategies |
| 5 | A/B, locale, plan state, workspace mismatch, or no-usage state | Labels and empty states may legitimately differ by account | Fixtures for every observed state; unknown until each state has a proven semantic mapping |
| 6 | WAF/bot challenge, rate limit, timeout, or transient 5xx | Browser-like User-Agent is not a stability contract | Typed fetch failure; bounded timeout; no retry storm and no stale value presented as fresh |
| 7 | Provider changes limit semantics or reset units | Values can remain parseable while meaning changes | Bounds plus browser comparison; official docs are metadata, dashboard remains v1 authority |

Do not classify every unparseable page as `authRequired`. That would assert an
unobserved cause. Authentication is automatic only for positive evidence:
401/403, a redirect/final URL to sign-in, or a stable login-page signature.
Otherwise report schema drift / unrecognized content.

### Parser acceptance and privacy guardrails

One live response is accepted only when all of these hold:

- HTTP 200, expected HTML content type, bounded response size, and final URL is
  the requested workspace `/go` page;
- the response positively identifies the Go dashboard, not merely any OpenCode
  page;
- exactly one rolling, weekly, and monthly record is present;
- each percentage is finite and inside `0...100`; never clamp bad input;
- reset seconds are finite, non-negative, and credible for the window (5h,
  7d, and calendar-month upper bounds with a small clock tolerance);
- when two strategies both match, their normalized values agree exactly or the
  entire sample fails closed;
- the parser strategy has a stable diagnostic id such as `solid_ssr_v1` or
  `data_slot_v1`; fixture provenance records capture date and strategy.

Raw authenticated HTML must **not** be written to the normal debug directory.
It can contain account/session data. Persist only a redacted diagnostic
fingerprint (HTTP status, content type, final-host/path class, response size,
parser id, matched/missing field names, and a hash). A raw capture for fixture
renewal must be an explicit local developer action, stored outside the repo,
reviewed/redacted manually, and never produced automatically.

### Proof and promotion gate

Fixture tests are necessary but cannot prove an undocumented live page. Do not
add a credentialed network test to CI, and do not call an unauthenticated live
request a drift test; neither exercises the claimed boundary.

Before normal bench inclusion, dogfood must record:

- at least 14 days and 100 targeted authenticated refreshes;
- at least two observed rolling resets and one deliberate expired-cookie test;
- at least 20 side-by-side browser comparisons across non-zero values;
- **zero false numeric readings**; every mismatch or ambiguous response emits
  unknown, never a partial or last-known value labeled fresh;
- at least 99% successful matches when the browser dashboard itself loads;
- percentage equality with the browser and reset time within 90 seconds;
- verified classification for 401, 403, login redirect/200 login page, timeout,
  5xx, partial-window HTML, duplicate values, out-of-range values, and unknown
  markup.

Fixture drift checks run on every parser change. Live-vs-fixture comparison is a
local, credentialed dogfood gate with a small redacted result ledger, not flaky
CI. Any false numeric reading resets the qualification clock. Two schema-drift
incidents in the 14-day window are a no-go unless both are caused by the same
known rollout and the parser is requalified from zero.

### Go / no-go decision

- **No-go:** the full configure/store/status/default-bench v1 below.
- **Go:** one env-only, targeted, three-window-atomic dogfood slice with honest
  scrape health.
- **Promotion:** only after the gate above. Then decide whether encrypted local
  persistence earns its maintenance cost.
- **Wait for official API:** immediately if the spike produces any plausible
  false value, needs a headless browser, requires additional session cookies,
  or fails qualification. Prefer the official endpoint whenever it ships.

The product claim remains three windows matching the browser. The smaller slice
reduces configuration and integration surface; it does not weaken truthfulness.

---

## Dogfood CLI (spike only)

First **developer-gated** capacity surface in ALLN (`--dogfood` on the existing
`capacity` command — not a new top-level verb).

```text
alln capacity --dogfood --refresh --source opencode_go [--json]
```

| Gate | Rule |
| --- | --- |
| `--dogfood` | Required for any `opencode_go` scrape; refuse without it |
| Credentials | Env only: `OPENCODE_GO_WORKSPACE_ID` + `OPENCODE_GO_AUTH_COOKIE` (both-or-neither) |
| Bench | Six-row product path unchanged; dogfood adds a seventh row only on this invocation |
| Visibility | Documented in phase packet + contract flag; omitted from `alln menu` (`.public` only) |
| Ledger | Append redacted scrape outcome to `…/Allnighter/Capacity/opencode-go-qualification.jsonl` |

Human stderr (never stdout): fetch attempted, parser strategy id, failure class.
JSON: existing `CapacityStripJSON` rows plus stderr diagnostics — no raw HTML, no
cookie values.

---

## One claim

```text
With Go credentials supplied, `alln capacity --dogfood --refresh --source opencode_go`
shows the same rolling / weekly / monthly values as the browser `/go` page, or
a typed unknown result. It never emits a partial or plausibly stale Go sample.
```

---

## Feature Packet

```text
Allnighter Feature Packet

Status: Dogfood spike approved — blocked on SOL reliability qualification for promotion

Founder Intent
- Raw request: Meter OpenCode Go in ALLN like Claude/Codex/Grok, but scrape
  browser /go instead of PTY-ing a local CLI.
- Prior art: kubectl/gh-style `configure` + `status` for credentials; capacity
  strip already owns display; community `@slkiser/opencode-quota` proved the
  scrape. Adopt cookie+workspace configure; deviate from npm plugin (own pure
  Swift parse + encrypted file, no runtime npm).
- Product value: Go is $5→$10/mo with $12/5h · $30/wk · $60/mo caps and no
  official quota API. One avoided wall during pilot/relay pays for ALLN.
- Trusted workflow slice (spike):
    export OPENCODE_GO_WORKSPACE_ID + OPENCODE_GO_AUTH_COOKIE
    → alln capacity --dogfood --refresh --source opencode_go
    → seventh row shows rolling / weekly / monthly % + reset clocks
    → (promotion) default bench; (phase 2) park/substitute before the 5h wall
- Non-goals: invent % from /usage ledger sums; Keychain; npm dependency;
  block `opencode` driver dispatch on missing Go config; OpenCode Zen;
  menu/park in v1.

Current State
- Existing truth owners: CapacityAcquisition (PTY-only six seats today),
  CapacityWindow / CapacityUnknownReason, CapacityBenchProjection,
  CapacityStripRenderer, HelpTopicRegistry topic `capacity`, ContractRegistry
  `capacity` + `capacityStripJSON`.
- Existing models/API paths: none for Go dashboard.
- Existing parsers: per-source `*CapacityProbe` pure parsers (Grok, Codex, …)
  fed by CapacityProbe PTY — pattern to mirror, not extend.
- Existing UI surfaces: capacity strip (CLI + Mac); no Go row.
- Existing tests/proof: CapacityAcquisition* / CapacityStrip* assume six PTY
  seats; prefer `.count` over literal `6` when updating.

SSOT
- Truth owner: AllnighterCore —
    OpenCodeGoCapacityProbe (pure HTML → [CapacityWindow]; no IO; no Date())
    OpenCodeGoCapacityClient (HTTP GET /go; injectable transport)
    OpenCodeGoCredentialStore (AES-GCM file; env override)
    OpenCodeGoCapacityExecutor (orchestrates load→fetch→parse; NOT PTY)
  CapacityAcquisition orchestrates refresh waves; it does not own Go parse.
- Lie-prone layers: HelpTopicRegistry / ContractRegistry "six-row" copy;
  CapacityAcquisition header ("PTY only, all six"); any path that invents 0%;
  teaching that conflates driver `opencode` with capacity `opencode_go`.
- New/changed semantic rules:
    1. Source id `opencode_go` is a bench seat with acquisition tier
       `dashboardScrape`.
    2. Cookie auth failure is `CapacityUnknownReason.authRequired` (new case —
       does not exist today; add with strip JSON kind + copy in the same slice
       that first emits it).
    3. Driver `opencode` and capacity `opencode_go` are independent.
- Duplicate truth to delete: none yet. Do not teach Go as a PTY seat.

Implementation
- CLI surface:
    Existing: alln capacity [--json] [--refresh] [--source opencode_go]
    New: alln opencode-go configure [--workspace-id <wrk_…>] [--cookie <auth>]
         alln opencode-go status [--json]
    Exit: 0 success; 1 validation / usage; never print cookie after save.
    JSON: existing CapacityStripJSON rows + new source id; additive
    opencodeGoStatusJSON for status.
- Teaching surface: extend topic `capacity` (seven-row / dynamic count;
  `opencode_go` source); new topic `opencode_go` (configure, cookie paste,
  status, authRequired recovery). Search: `opencode go`, `go plan`,
  `go quota`, `go capacity`, `opencode go limits`. Recovery:
  authRequired → status → configure; neverSampled → configure first.
- Retired grammar: none.
- Model/package impact: AllnighterCore modules + AllnighterCLI thin dispatch.
  AllnighterEngine: only if CapacityFetch / resident paths hardcode six —
  follow benchSourceOrder; no new Engine semantics in v1.
- Mac app impact: strip already projects CapacityBenchRow — seventh row
  appears when acquisition returns it. No Mac-only truth.
- iOS: none (v1).
- WebSocket/protocol: none.
- Agent driver: none (OpenCodeServeClient untouched).
- Auth/privacy: session cookie encrypted at rest; never log; no Keychain;
  High-Risk Stop if storage design changes to Keychain or leaves machine.

Proof
- Works Test (fixture): saved /go HTML → three CapacityWindows with % + reset;
  encrypted credential round-trip; env override wins; no plaintext cookie on disk.
  Exact: scripts/swift-test.sh --filter OpenCodeGo
- Works Test (live dogfood, founder): configured host →
  alln capacity --refresh --source opencode_go matches browser /go %.
- Missing proof / waiver: live dogfood is founder-gated; CI stays fixture-only
  (no live network).

Done When
- User-visible claim above holds on a binary from committed HEAD.
- CLI contract + help topics shipped; nothing dead taught.
- CapacityProbe.swift has zero opencode_go / cookie / HTML scrape logic
  (grep gate).
- Sprint docs archived; promote strip/help law; archive this packet.
```

---

## SSOT intake (founder input workflow)

```text
Founder intent:
  Meter OpenCode Go plan limits in ALLN the same way we meter Claude/Codex/Grok —
  but scrape the browser /go dashboard instead of PTY-ing a local CLI.

Product value:
  Go subscribers hit dollar caps with no official quota API. Rolling headroom
  before dispatch (and phase-2 park) is the product bet.

Trusted workflow slice:
  alln opencode-go configure → alln capacity --refresh --source opencode_go
  → strip % + resets → (phase 2) park/sub

Current state:
  Six PTY bench seats. opencode driver ships; not on capacity bench.
  CapacityUnknownReason has no authRequired yet.
  CapacityAcquisition is documented/implemented as PTY-only for all
  benchSourceOrder members.

Truth owner:
  OpenCodeGoCapacity* modules (Core) + CapacityAcquisition wave split.

CLI surface:
  alln capacity … --source opencode_go
  alln opencode-go configure | status [--json]

Help surface:
  capacity + opencode_go topics; search aliases above; authRequired recovery.

Proof scenario:
  Fixtures + one live dogfood refresh.

Blocking questions:
  Can the authenticated page pass the SOL reliability qualification without a
  browser runtime or extra session state? Persistent credential UX is deferred
  until that answer is yes. Phase 2 park/sub needs founder dogfood on a real
  wall-cross.

Next slice:
  OCG-S00 — env-only targeted dogfood spike + redacted evidence ledger. Do not
  add default-bench wiring, persistent credentials, or new opencode-go commands.
```

---

## Corrections against live code (binding)

Verified against the tree at finalize time — implementers must not trust the
brainstorm (`adc582cd`) where it conflicts.

1. **`CapacityAcquisition` is PTY-only today.** Header and arrays treat
   `benchSourceOrder == ptyOnlySources == tier3ProbeableSources` (six seats).
   Adding `opencode_go` to `benchSourceOrder` **without** splitting
   `ptyOnlySources` / `sourcesProbed` would send Go into
   `LiveCapacityProbeExecutor` and fail closed nonsense. **Law:**
   `ptyOnlySources` stays the six TUI seats; `benchSourceOrder` gains
   `opencode_go`; refresh runs a PTY wave **and** a dashboard wave.

2. **`CapacityUnknownReason.authRequired` does not exist.** Cookie/decrypt
   failure must not be mislabeled `parserFailed` or `spawnFailed`. Add
   `authRequired` (+ `CapacityStripUnknownKind` + human/short copy) in the
   first slice that can emit it (OCG-S02 store miss / OCG-S03 live scrape).

3. **`CapacityAcquisitionTier.dashboardScrape` does not exist.** Append a new
   case (do **not** renumber existing Int raw values — Codable identity).
   Prefer `dashboardScrape = 5` (or next free). Tier marks acquisition method,
   not a freshness ladder rank vs PTY.

4. **`CapacityStripRenderer.displayOrder` is a second six-id list.** Update in
   lockstep with `benchSourceOrder` (OCG-S03). Prefer deriving from
   `CapacityAcquisition.benchSourceOrder` if a one-line alias is safe; otherwise
   keep both and test equality.

5. **`sourcesWithShortWindow` is only `{claude_code, kimi}` today.** Add
   `opencode_go` (rolling fiveHour). Without it the short column blank-treats
   a real 5h cap.

6. **Crypto reuse:** `RemoteMediaCrypto` (AES-GCM in `RemoteFoundation.swift`)
   is the encrypt/decrypt primitive. **Do not** store the Go cookie via
   `RemoteMacAgentCredentialStore` (plaintext JSON under Config/Remote). Own
   `machine.key` + `opencode_go.enc` under Application Support Config.

7. **Contract/help still say "six-row".** Same-slice update in OCG-S03
   (`HelpTopicRegistry`, `ContractRegistry` capacity summary/trigger). Teaching
   surface is part of the capability, not polish.

8. **Package layout:** Core sources under
   `Packages/AllnighterCore/Sources/AllnighterCore/`; CLI under
   `…/Sources/AllnighterCLI/` (executable target `AllnighterCLI`).

---

## Product law

### Same seat model, different acquisition tier

| Layer | TUI seats (codex, claude, …) | OpenCode Go (`opencode_go`) |
| --- | --- | --- |
| **Pure parser** | `GrokCapacityProbe`, `CodexCapacityProbe`, … | `OpenCodeGoCapacityProbe` |
| **Acquisition** | `LiveCapacityProbeExecutor` → `CapacityProbe` PTY | `OpenCodeGoCapacityExecutor` → HTTP `/go` |
| **Normalize** | `CapacityWindow` | `CapacityWindow` (same type) |
| **Display** | `CapacityBenchProjection` → strip | same path |

Go is **not** a special case inside `CapacityProbe`. Do not add HTTP, cookies,
or HTML parsing to `CapacityProbe.swift`. Keep PTY machinery untouched.

`OpenCodeGoCapacityExecutor` must **not** conform to `CapacityProbeExecuting`
(that protocol is the PTY request seam). Parallel type, called from
`CapacityAcquisition.windows()` on the dashboard wave only.

### Driver ≠ capacity source

| Id | Role | Owner |
| --- | --- | --- |
| `opencode` | Driver — `opencode serve`, model dispatch | `OpenCodeServeClient`, `RunService` |
| `opencode_go` | Capacity — Go subscription meter | `OpenCodeGoCapacity*` modules |

`opencode` ready + `opencode_go` unconfigured → driver works; capacity row is
`neverSampled`. Never block OpenCode dispatch on Go capacity config.

### Capacity authority

| Page | Role in ALLN |
| --- | --- |
| `/workspace/{id}/go` | **Primary** — rolling / weekly / monthly % + reset |
| `/workspace/{id}/usage` | **Phase 2 only** — per-model $ attribution; never sum ledger to invent % |

Official caps ([OpenCode Go docs](https://opencode.ai/docs/go/)): $12 / 5h,
$30 / week, $60 / month (dollar-denominated; dashboard shows %).

Map dashboard windows → `CapacityWindowScope`: rolling → `fiveHour`, weekly →
`weekly`, monthly → `monthly`. `sourceTier: .dashboardScrape`.

### Credential storage

```text
~/Library/Application Support/Allnighter/Config/
  machine.key          # 256-bit random, chmod 600, created once per machine
  opencode_go.enc      # AES-GCM(JSON { workspaceId, authCookie })
```

- Encrypt at rest via `RemoteMediaCrypto.encrypt/decrypt` (or thin wrapper).
- **No Keychain** — no permission popups, no headless breakage.
- **No plaintext JSON** on disk for the cookie.
- Env override: `OPENCODE_GO_WORKSPACE_ID`, `OPENCODE_GO_AUTH_COOKIE`
  (override wins when both set; partial env → fail closed with clear error).
- Only `auth` cookie is secret; `workspaceId` is public (URL path).
- Decrypt failure → `authRequired`, never retry with empty cookie.

### Fail closed (same honesty as other seats)

| State | `CapacityUnknownReason` / observation |
| --- | --- |
| Not configured | `neverSampled` |
| Bad / expired cookie / HTTP 401–403 | `authRequired` |
| HTTP other non-200 / transport error | typed fetch failure → unknown (`parserFailed` or dedicated fetch mapping — never invent %) |
| HTML unparseable | typed schema drift + redacted diagnostic fingerprint; no automatic raw HTML dump |
| Never invent 0% | Banned |

---

## Module layout (Core — one file per concern)

Mirror existing per-source capacity files. **New code in AllnighterCore**; CLI
is thin dispatch only.

```text
Packages/AllnighterCore/Sources/AllnighterCore/
  OpenCodeGoCapacityProbe.swift      # Pure HTML → [CapacityWindow]. No IO. No Date().
  OpenCodeGoCapacityClient.swift     # HTTP GET /go. Injectable transport for tests.
  OpenCodeGoCredentialStore.swift    # machine.key + opencode_go.enc (AES-GCM).
  OpenCodeGoCapacityExecutor.swift   # load → fetch → parse. NOT CapacityProbeExecuting.

Packages/AllnighterCore/Tests/AllnighterCoreTests/
  OpenCodeGoCapacityProbeTests.swift
  OpenCodeGoCredentialStoreTests.swift
  OpenCodeGoCapacityExecutorTests.swift

Packages/AllnighterCore/Tests/Fixtures/opencode-go/
  go-dashboard-ssr.html              # Manually captured, reviewed, redacted
  go-dashboard-dataslot.html         # Manually captured, reviewed, redacted

Packages/AllnighterCore/Sources/AllnighterCLI/
  OpenCodeGoCLI.swift                # configure + status subcommands only
```

**Touch on wire-in slice (OCG-S03) only:**

- `CapacityAcquisition.swift` — add `opencode_go` to `benchSourceOrder`;
  **split** `ptyOnlySources` / `sourcesProbed` so Go never enters the PTY
  executor; branch refresh to `OpenCodeGoCapacityExecutor`.
- `CapacityWindow.swift` — `CapacityAcquisitionTier.dashboardScrape`;
  `CapacityUnknownReason.authRequired` if not already added in S02.
- `CapacityBenchProjection.swift` — `opencode_go` in `sourcesWithShortWindow`.
- `CapacityStripRenderer.swift` — display order + display name + unknown copy.
- `HelpTopicRegistry.swift`, `ContractRegistry` — row count / topics / search.
- Tests that hardcode six seats → `.count` or update to seven.

**Do not touch:** `CapacityProbe.swift` PTY spawn, `OpenCodeServeClient`,
`RunService` dispatch paths (v1).

---

## CLI contract

### `alln capacity` (existing — dogfood extension, OCG-S00–S03)

```text
alln capacity [--json] [--refresh] [--source <id>] [--dogfood]
```

**Spike (OCG-S00–S03):**

- `--dogfood` unlocks `--source opencode_go` only. Without it, `opencode_go`
  is rejected as an unknown source (six-seat valid list unchanged).
- Targeted dogfood: six `neverSampled` PTY rows + one `opencode_go` dashboard
  wave (no PTY siblings probed).
- JSON: existing `CapacityStripJSON`; seventh row uses source id `opencode_go`.
- Scrape diagnostics on stderr only (redacted fingerprint — no HTML/cookie).

**Promotion (OCG-S04+ — after qualification gate):**

- Add `opencode_go` to `benchSourceOrder`; drop `--dogfood` requirement for Go.
- Update help/contract row count; Mac strip + menu envelope.

### `alln opencode-go configure` (deferred — promotion only)

```text
alln opencode-go configure [--workspace-id <wrk_…>] [--cookie <auth>]
```

- Interactive default: prompt workspace ID (accept clipboard `wrk_*` from URL),
  prompt cookie (hidden input), encrypt, write `opencode_go.enc`.
- Non-interactive: flags or stdin for automation.
- Exit 0 on save; exit 1 on validation failure.
- **Never print the cookie** after save.

Cookie help: open [opencode.ai](https://opencode.ai) while logged in → DevTools
→ Application → Cookies → copy `auth` value.

### `alln opencode-go status` (new)

```text
alln opencode-go status [--json]
```

Human:

```text
OpenCode Go capacity: configured
Workspace: wrk_01KZAKC3FS66DE4V0CG7YESNC3
Credential: encrypted file (updated 2026-08-05)
Last scrape: ok — rolling 0% weekly 0% monthly 0% (observed 12s ago)
```

JSON (`opencodeGoStatusJSON` — additive contract slice):

```json
{
  "configured": true,
  "workspaceId": "wrk_…",
  "credentialSource": "encrypted_file",
  "lastConfiguredAt": "2026-08-05T…",
  "lastScrape": { "ok": true, "observedAt": "…", "windows": 3 },
  "error": null
}
```

`authRequired` recovery text points here, then `configure`.

---

## Acquisition flow

```text
CapacityAcquisition.windows(refresh: true)
  ├─ PTY wave (unchanged): codex, claude_code, cursor_agent, grok, kimi, agy
  │     → LiveCapacityProbeExecutor → CapacityProbe
  └─ Dashboard wave: opencode_go
        → OpenCodeGoCapacityExecutor
              → OpenCodeGoCredentialStore.load()
              → OpenCodeGoCapacityClient.fetch(workspaceId, authCookie)
              → GET https://opencode.ai/workspace/{id}/go
                    Cookie: auth={authCookie}
              → OpenCodeGoCapacityProbe.parse(html, observedAt: now)
              → [CapacityWindow] × up to 3
```

Targeted `--source opencode_go`: dashboard wave only (no PTY siblings probed).
Targeted PTY source: unchanged (Go stays `neverSampled` / last-known per
existing hydrate rules — do not invent a Go sample).

Parser port reference (behavior only, not runtime dep):
`@slkiser/opencode-quota` `opencode-go.js` — SolidJS SSR regex + `data-slot`
fallback.

---

## Inference bans

| Junction | Owner | Possible bad inference | Ban | Negative proof |
| --- | --- | --- | --- | --- |
| driver ready → capacity configured | `OpenCodeServeClient` vs Go store | `opencode` on PATH means Go row is live | Independent ids; unconfigured Go → `neverSampled` only | Driver smoke without configure still neverSampled |
| cookie fail → parse fail | `OpenCodeGoCapacityExecutor` | 401 HTML looks like markup miss | HTTP 401/403 / decrypt fail → `authRequired` | Fixture 401 never emits parserFailed |
| /usage $ rows → strip % | phase-2 only | sum ledger ≈ dashboard % | `/go` is sole v1 authority | No /usage code in v1 allowlist |
| Go seat → PTY executor | `CapacityAcquisition` | new bench id goes through `CapacityProbeExecuting` | Go never in `ptyOnlySources`; executor ≠ `CapacityProbeExecuting` | Unit: sourcesProbed(PTY) excludes opencode_go; grep CapacityProbe.swift |
| missing sample → 0% | strip / projection | unknown paints as empty | Fail closed; never invent 0% | Unconfigured refresh row unknownReason set, usedPercent nil |
| env partial → file cookie | credential store | one env var "helps" | Partial env fail closed; both-or-neither override | Test partial env refuses |

---

## Slice plan

| Slice | Goal | Allowlist | Works Test |
| --- | --- | --- | --- |
| **OCG-S00** | `--dogfood` gate + refuse `opencode_go` without it; contract flag | `AllnighterCLI.runCapacity`, `ContractRegistry`, `CapacityAcquisition.validateRefreshSourceId` | CLI usage tests |
| **OCG-S01** | Pure parser + fixtures (atomic 3-window) | `OpenCodeGoCapacityProbe.swift`, tests | `swift-test.sh --filter OpenCodeGoCapacityProbe` |
| **OCG-S02** | HTTP client + env creds + `authRequired` + executor | `OpenCodeGoCapacityClient.swift`, `OpenCodeGoCredentialStore.swift`, `OpenCodeGoCapacityExecutor.swift`, `CapacityWindow` tier/reason | `swift-test.sh --filter OpenCodeGo` |
| **OCG-S03** | Wire dogfood path + strip display + qualification ledger | `CapacityFetch`, `CapacityStripRenderer`, `CapacityBenchProjection` (short window), `AllnighterCLI` | `swift-test.sh --filter OpenCodeGo` |
| **OCG-S04** | Promotion only (after SOL gate) | `benchSourceOrder`, Mac strip, help, optional encrypted store | Full wall |

Estimate: **1–2 focused days** for OCG-S00–S03 spike; OCG-S04 is a separate promotion packet.

Sprint docs: create under `docs/phases/sprint/opencode-go/` at slice start;
archive on close per `docs/phases/sprint/README.md`.

---

## Phase 2 (after v1 dogfood)

| Slice | Value |
| --- | --- |
| OCG-S04 | Menu envelope row (QABC S00 injection) |
| OCG-S05 | Park / substitution when `opencode_go` rolling ≤ thin threshold |
| OCG-S06 | `/usage` table → model burn hints + `CapacityPaidAmount` on receipts |

Phase 2 `/usage` is **attribution**, not primary capacity. Do not sum the
ledger to replace `/go` %.

---

## Risks

| Risk | Mitigation |
| --- | --- |
| HTML markup changes | Atomic validation; stable strategy ids; redacted diagnostics; qualification clock resets on false values |
| Cookie = full web session | Encrypt at rest; never log; document rotation |
| Scraper ≠ API | Document best-effort; [opencode#16513](https://github.com/anomalyco/opencode/pull/16513) pending |
| PTY code pollution | Hard rule + grep: no HTTP/cookie/HTML in `CapacityProbe.swift` |
| Help drift | Same-slice `HelpTopicRegistry` + contract update (OCG-S03) |
| Accidental PTY probe of Go | Split `ptyOnlySources`; negative test on `sourcesProbed` |

---

## Done when (spike — OCG-S00–S03)

- [ ] `--dogfood` required for `opencode_go`; refused without it
- [ ] `OpenCodeGoCapacityProbe` parses fixtures → three windows with % + reset (atomic)
- [ ] Env-only credentials; both-or-neither; no Keychain; no encrypted file in spike
- [ ] `alln capacity --dogfood --refresh --source opencode_go` shows seventh row when configured
- [ ] `CapacityProbe` / PTY path unchanged (grep: no opencode_go / cookie / HTML scrape in PTY file)
- [ ] `benchSourceOrder` still six seats; `opencode_go` not in default refresh
- [ ] Qualification ledger appends redacted outcomes
- [ ] Founder dogfood: live refresh matches browser /go %

## Done when (promotion — OCG-S04+)

- [ ] SOL qualification gate passed (14d / 100 refreshes / 20 browser compares / …)
- [ ] `benchSourceOrder` includes `opencode_go`; strip/help row count updated
- [ ] Optional: encrypted credential store + `configure`/`status` CLI
- [ ] Sprint docs archived; promote strip/help law; archive this packet

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| OpenCode Go capacity | This packet + `CapacityAcquisition.swift` |
| OpenCode driver / serve | `OpenCodeServeClient.swift` (dispatch — separate concern) |
| Park / menu capacity | `Quota_Aware_Bench_Continuity.md` (phase 2) |
