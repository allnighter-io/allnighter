# OpenCode Go Capacity

Status: **Ready for Implementation** (v1 strip — not started)
Owner: AllnighterCore (per-source modules + acquisition branch) +
AllnighterCLI (`opencode-go` configure/status; capacity injection stays CLI)
Created: 2026-08-05
Revised: 2026-08-05 (SSOT founder-input + feature-workflow finalize; baseline
`adc582cd`)
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

## One claim

```text
Configure Go once. `alln capacity --refresh --source opencode_go` shows the
same rolling / weekly / monthly % the browser /go page shows.
```

---

## Feature Packet

```text
Allnighter Feature Packet

Status: Ready for Implementation

Founder Intent
- Raw request: Meter OpenCode Go in ALLN like Claude/Codex/Grok, but scrape
  browser /go instead of PTY-ing a local CLI.
- Prior art: kubectl/gh-style `configure` + `status` for credentials; capacity
  strip already owns display; community `@slkiser/opencode-quota` proved the
  scrape. Adopt cookie+workspace configure; deviate from npm plugin (own pure
  Swift parse + encrypted file, no runtime npm).
- Product value: Go is $5→$10/mo with $12/5h · $30/wk · $60/mo caps and no
  official quota API. One avoided wall during pilot/relay pays for ALLN.
- Trusted workflow slice:
    alln opencode-go configure (once)
    → alln capacity --refresh --source opencode_go
    → strip shows rolling / weekly / monthly % + reset clocks
    → (phase 2) park/substitute before the 5h wall
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
  None for v1 strip. Phase 2 park/sub needs founder dogfood on real wall-cross.

Next slice:
  OCG-S01 — parser + fixtures (no wiring).
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
| HTML unparseable | `parserFailed` + debug dump |
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
  go-dashboard-ssr.html              # Saved /go page (SolidJS hydration)
  go-dashboard-dataslot.html         # data-slot fallback format

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

### `alln capacity` (existing — extended)

```text
alln capacity [--json] [--refresh] [--source opencode_go]
```

- `opencode_go` becomes a valid `--source` when wired (OCG-S03);
  `validateRefreshSourceId` / `validRefreshSourceIds` follow `benchSourceOrder`.
- JSON: existing `CapacityStripJSON` / bench rows; new source id only.
- Bare / no prior sample: `neverSampled` for `opencode_go` until a successful
  refresh path samples it (same honesty as other seats).

### `alln opencode-go configure` (new)

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
| **OCG-S01** | Pure parser + fixtures | `OpenCodeGoCapacityProbe.swift`, tests, fixtures | `swift-test.sh --filter OpenCodeGoCapacityProbe` |
| **OCG-S02** | Client + encrypted store + CLI | `OpenCodeGoCapacityClient.swift`, `OpenCodeGoCredentialStore.swift`, `OpenCodeGoCLI.swift`, `authRequired` enum/copy if first emit, tests | `swift-test.sh --filter OpenCodeGo` |
| **OCG-S03** | Acquisition + strip + help | `OpenCodeGoCapacityExecutor.swift`, `CapacityAcquisition.swift` (PTY/dashboard split), `CapacityAcquisitionTier`, `CapacityBenchProjection`, `CapacityStripRenderer`, help/contract | `swift-test.sh --filter OpenCodeGoCapacityExecutor` + `CapacityAcquisition` + help/contract checks |

Estimate: **2–3 focused days** / three sprint work orders.

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
| HTML markup changes | Dual parse strategies; debug dump; monitor upstream scraper |
| Cookie = full web session | Encrypt at rest; never log; document rotation |
| Scraper ≠ API | Document best-effort; [opencode#16513](https://github.com/anomalyco/opencode/pull/16513) pending |
| PTY code pollution | Hard rule + grep: no HTTP/cookie/HTML in `CapacityProbe.swift` |
| Help drift | Same-slice `HelpTopicRegistry` + contract update (OCG-S03) |
| Accidental PTY probe of Go | Split `ptyOnlySources`; negative test on `sourcesProbed` |

---

## Done when (v1)

- [ ] `OpenCodeGoCapacityProbe` parses fixtures → three windows with % + reset
- [ ] Encrypted credential round-trip; env override; no plaintext on disk; no Keychain
- [ ] `alln opencode-go configure` + `status` ship with help topics
- [ ] `alln capacity --refresh --source opencode_go` shows live row when configured
- [ ] `CapacityProbe` / PTY path unchanged (grep: no opencode_go / cookie / HTML scrape in PTY file)
- [ ] `ptyOnlySources` excludes `opencode_go`; `benchSourceOrder` includes it
- [ ] Founder dogfood: live refresh matches browser /go %
- [ ] Sprint docs archived; promote strip/help law; archive this packet

## AGENTS.md routing

| Task | Read first |
| --- | --- |
| OpenCode Go capacity | This packet + `CapacityAcquisition.swift` |
| OpenCode driver / serve | `OpenCodeServeClient.swift` (dispatch — separate concern) |
| Park / menu capacity | `Quota_Aware_Bench_Continuity.md` (phase 2) |
