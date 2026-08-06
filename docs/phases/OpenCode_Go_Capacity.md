# OpenCode Go Capacity

Status: **OPEN — not started (founder brainstorm 2026-08-05)**
Owner: AllnighterCore (probe + credentials) + AllnighterCLI (configure +
capacity injection) + AllnighterEngine (acquisition wiring, optional park)
Created: 2026-08-05
Origin: Founder dogfood — OpenCode Go subscription limits exist only in the
browser dashboard, not in the `opencode` TUI. Community plugin
[`@slkiser/opencode-quota`](https://github.com/slkiser/opencode-quota) proves
the scrape path; ALLN should own it natively with bench continuity.

Related shipped substrate (reuse, do not re-build):
[`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md),
`CapacityAcquisition` / `CapacityWindow` / `CapacityBenchProjection`,
`VendorBackoffPolicy`, OpenCode driver (`OpenCodeServeClient`).

Phases are ephemeral. At closeout: promote product law into help / vocabulary /
operations; code remains SSOT; archive this packet.

---

## Founder intent

OpenCode Go subscribers ($5 first month, then $10/month) get dollar-denominated
limits with no official quota API. Limits are visible only on the web dashboard.
ALLN already meters six local CLI seats via PTY probes; Go is the first
**browser-only** capacity source.

Product bet: for anyone on a Go plan, seeing the meter in `alln capacity` and
(phase 2) parking/substituting before the 5h wall pays for ALLN faster than the
subscription costs — especially during pilot/relay loops that burn the rolling
window on expensive models (e.g. one `grok-4.5` call ≈ 5% of the $12/5h cap).

## Problem

| Surface | What it shows | ALLN today |
| --- | --- | --- |
| `opencode` TUI `/quota` | Nothing unless third-party plugin installed | Not probed |
| [`/go`](https://opencode.ai/docs/go/) dashboard | Rolling / Weekly / Monthly **% used** + reset countdown | Not read |
| [`/usage`](https://opencode.ai/workspace/…/usage) dashboard | Per-request cost ledger (model, tokens, $) | Not read |

The six bench seats (`codex`, `claude_code`, `cursor_agent`, `grok`, `kimi`,
`agy`) all use **tier-3 PTY probes** (`CapacityProbe`). OpenCode Go has no
equivalent local usage TUI — capacity lives behind web auth at
`https://opencode.ai/workspace/{workspaceId}/go`.

## Official Go limits (vendor docs)

Per [OpenCode Go docs](https://opencode.ai/docs/go/) — caps are **dollar value**,
not request count; cheaper models stretch the same % further:

| Window | Cap |
| --- | --- |
| Rolling (~5h) | $12 |
| Weekly | $30 |
| Monthly | $60 |

The dashboard prints **percentage used** and **reset countdown** for each window.
That maps directly onto ALLN `CapacityWindow` (`fiveHour`, `weekly`, `monthly`).

## v1 scope (prove the meter)

**In:**

- Scrape `GET /workspace/{workspaceId}/go` with session cookie
- Parse three windows (SolidJS SSR hydration + `data-slot` HTML fallback —
  port from `opencode-quota`)
- New bench source id: `opencode_go`
- New acquisition tier: `dashboardScrape` (not PTY)
- Encrypted credential file (see Storage) — **no Keychain**
- Env override: `OPENCODE_GO_WORKSPACE_ID`, `OPENCODE_GO_AUTH_COOKIE`
- `alln opencode-go configure` + `alln opencode-go status`
- 7th row on `alln capacity --refresh --source opencode_go`
- Fixture tests from saved `/go` HTML (no live network in CI)
- Fail closed: no config → `neverSampled`; bad/expired cookie → `authRequired`;
  parse miss → `parserFailed`

**Out (later slices):**

- `/usage` table scrape (model burn attribution, receipt dollars)
- Menu envelope injection (`Quota_Aware_Bench_Continuity` S00 pattern)
- Park / vendor substitution when Go rolling is thin
- OpenCode Zen plan
- Depending on `@slkiser/opencode-quota` npm package
- Keychain storage (popups, TCC friction — rejected)

## Non-goals

- Inventing capacity from summed `/usage` rows (ledger is incomplete; `/go` % is
  authoritative)
- Storing or proxying Go API keys — this is a **session cookie** for dashboard
  scrape only
- Making OpenCode Go capacity block non-Go OpenCode driver runs
- Claiming behavior is proven without fixture tests + one live dogfood refresh

## Architecture

### Acquisition path

```
OpenCodeGoCredentialStore.load()
  → OpenCodeGoCapacityClient.fetch(workspaceId, authCookie)
  → GET https://opencode.ai/workspace/{id}/go
      Cookie: auth={authCookie}
  → OpenCodeGoCapacityProbe.parse(html)
  → [CapacityWindow] × 3 (rolling, weekly, monthly)
```

Wire into `CapacityAcquisition.windows()` as a **special case** — not through
`CapacityProbe` PTY spawn. HTTP fetch runs in the same refresh wave as PTY
seats; `opencode_go` is added to `benchSourceOrder` and
`sourcesWithShortWindow` (has rolling 5h).

Reference implementation (behavior, not dependency):
`@slkiser/opencode-quota` → `dist/lib/opencode-go.js`,
`dist/lib/opencode-go-config.js`.

### Storage (encrypted file — no Keychain)

Only the **`auth` cookie** is secret. `workspaceId` is public (URL path).

```
~/Library/Application Support/Allnighter/Config/
  machine.key          # 256-bit random, chmod 600, created once per machine
  opencode_go.enc      # AES-GCM(JSON { workspaceId, authCookie })
```

- Reuse `RemoteMediaCrypto` (CryptoKit AES-GCM) or a thin shared wrapper
- **Never Keychain** — no permission popups, no headless breakage
- **Never plaintext JSON on disk**
- Env vars override file (scripts, CI, power users)
- Decrypt failure → `authRequired`, not retry with empty cookie

### Source identity

| Id | Meaning |
| --- | --- |
| `opencode` | Driver seat — warm `opencode serve`, model dispatch |
| `opencode_go` | **Capacity source** — Go subscription meter (browser scrape) |

A user can have `opencode` ready without Go configured; capacity row shows
`neverSampled` until `alln opencode-go configure`.

### Display

- Strip row: `opencode_go` with short column = rolling 5h, dashboard = weekly or
  monthly per `CapacityBenchProjection` rules
- Update help/contract copy from fixed "six-row" to dynamic row count or
  "seven-row" where hardcoded
- Tests that assert `benchSourceOrder.count == 6` must follow the new order

## Slice plan

| Slice | Goal | Touch (indicative) | Proof |
| --- | --- | --- | --- |
| **OCG-S01** | Parser + fixtures | `OpenCodeGoCapacityProbe.swift`, tests, `Fixtures/opencode-go/` | `swift-test.sh --filter OpenCodeGoCapacity` |
| **OCG-S02** | HTTP client + encrypted store | `OpenCodeGoCapacityClient.swift`, `OpenCodeGoCredentialStore.swift`, configure/status CLI | `swift-test.sh --filter OpenCodeGoCredential` |
| **OCG-S03** | Acquisition + strip | `CapacityAcquisition.swift`, `CapacityAcquisitionTier`, `CapacityBenchProjection`, strip/help | `swift-test.sh --filter CapacityAcquisition` |

Estimate: **2–3 focused days** / three sprint work orders for v1 strip.

### OCG-S02 configure flow

```text
alln opencode-go configure
  → prompt workspace ID (default: parse from clipboard URL if wrk_* present)
  → prompt auth cookie (paste from DevTools → Application → Cookies → auth)
  → encrypt → write opencode_go.enc

alln opencode-go status
  → configured yes/no, workspace id, cookie age, last scrape result/error
  → never print the cookie value
```

Cookie instructions (help text): open [opencode.ai](https://opencode.ai) while
logged in → DevTools → Application → Cookies → copy `auth` value.

## Phase 2 (after v1 dogfood)

| Slice | Value |
| --- | --- |
| OCG-S04 | Menu envelope row (QABC S00 injection pattern) |
| OCG-S05 | Park / substitution when `opencode_go` rolling ≤ thin threshold |
| OCG-S06 | `/usage` table → per-model burn hints + `CapacityPaidAmount` on receipts |

Phase 2 `/usage` is **attribution**, not primary capacity. One `grok-4.5` row at
`Go ($0.6260)` explains wall hits; do not sum the ledger to replace `/go` %.

## Risks

| Risk | Mitigation |
| --- | --- |
| Dashboard HTML changes | Two parse strategies + debug dump on failure; monitor `opencode-quota` |
| Cookie expires | `authRequired` + `alln opencode-go status` tells user to re-paste |
| Scraper treated as API | Document as best-effort; official API pending ([opencode#16513](https://github.com/anomalyco/opencode/pull/16513)) |
| Cookie is full session | Encrypt at rest; never log; document rotation; scoped read API would be better long-term |
| `benchSourceOrder` churn | Mechanical test updates; prefer `benchSourceOrder.count` over literal `6` in new tests |

## Done when (v1)

- [ ] Saved `/go` HTML fixtures parse to three `CapacityWindow`s with correct %
  and reset times
- [ ] Encrypted credential round-trip; env override works; no plaintext on disk
- [ ] `alln capacity --refresh --source opencode_go` shows live row when
  configured; `neverSampled` / `authRequired` when not
- [ ] No Keychain usage; no dependency on `@slkiser/opencode-quota` at runtime
- [ ] Founder dogfood: one refresh against real Go dashboard matches browser %
- [ ] Sprint docs archived; routing row in `AGENTS.md` if promoted to standing law

## AGENTS.md routing (when implementing)

| Task | Read first |
| --- | --- |
| OpenCode Go capacity scrape, configure, strip row | This packet + `CapacityAcquisition.swift` + `Quota_Aware_Bench_Continuity.md` |
| OpenCode driver / serve / dispatch | `docs/archive/phases/setup/OpenCode_CLI_Support.md` (if present) + `OpenCodeServeClient.swift` |
