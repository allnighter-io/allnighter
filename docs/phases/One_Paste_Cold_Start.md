# One-Paste Cold Start

Status: **OPEN — founder priority (distribution wedge)**  
Owner: AllnighterCLI + distribution (install script / release binary) + teaching  
Created: 2026-07-31  
Updated: 2026-07-31  
Origin: Founder intake — Hermes / OpenClaw power users need one copy-paste to go
from *no `alln`* to *agent runs on subscriptions they already pay for*, not API
keys. Brainstorm locked the product sentence and the install shape; this packet
is the build contract.

Ephemeral build packet. At closeout: promote keepable install/teaching law into
`docs/operations/` + `HelpTopicRegistry` / `Bootstrap`; code + release script are
runtime SSOT; archive this packet. Do not leave living distribution law only here.

Related (reuse, do not rebuild):
- archived `Agent_Front_Door.md` / `Agent_Onboarding.md` — findable + suggested
  once `alln` exists; **this packet owns the missing cold-start faucet**
- `InstallCLI.swift` — PATH symlink after a binary already exists (chicken/egg)
- `Bootstrap.swift` — print-never-edit paste snippet for hosts
- open [`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md) —
  plan-time capacity in `menu`/`bootstrap` so the paste line is actionable
- archived `MCP_Retirement.md` — **MCP stays dead**; shell-out only

---

## Founder intake (SSOT_Founder_Input_Workflow)

```text
Founder intent:
  One screaming idea: your agent should run on the AI subscriptions you already
  pay for — not on API keys. Make that one click / one terminal command for a
  Hermes (or OpenClaw) user who does not yet have alln. One copy-paste. Curl
  installer preferred for agents; Mac app still fine for humans; npm optional if
  it helps; same product / one price whether they take CLI-only or app+CLI.

Product value:
  Kill the chicken-and-egg. Today `alln install-cli` and `alln bootstrap` only
  help people who already have a binary. Hermes/OpenClaw users never leave the
  terminal — they will not start by downloading a Mac app. Without a cold-start
  faucet, the subscription-fuel promise never reaches them.

Trusted workflow slice:
  User (or Hermes) pastes one command → `alln` on PATH → installer prints one
  host paste line → next Hermes turn routes coding work through alln → mutating
  seats prefer subscription CLIs over API keys.

Non-goals:
  - MCP server / `hermes mcp add` / tool schemas in context (retired; do not revive)
  - Free dashboard + $9 auto-router as a separate product split
  - Fake "API Spend Avoided: $X" receipts
  - Teaching Hermes to be Allnighter (Allnighter is the bench the host calls)
  - Replacing QABC / loop park-yield (those are continuity; this is install)

Current state:
  - `alln install-cli` symlinks the *running* binary onto PATH — requires alln
  - `alln bootstrap` prints a paste-ready snippet — requires alln
  - Mac app can Teach your CLIs (ONB) — requires app install first
  - No public cold-start URL, no signed release binary faucet, no npm package
  - Capacity / substitution / loop park exist or are in-flight — useless if the
    host never gets `alln` on PATH

Truth owner (target):
  - Cold install: release install script + published macOS `alln` binary
    (content-addressed / versioned); script is the only actor that may fetch
  - Post-install PATH: existing `InstallCLI` (or script calling it)
  - Host paste line: `Bootstrap` (extended for `--host hermes|openclaw|generic`)
  - Teaching: `HelpTopicRegistry` + doctor recovery when `which alln` fails

CLI surface (post-install — product contract stays CLI-only):
  alln version
  alln doctor
  alln bootstrap [--host hermes|openclaw|generic|claude|cursor|codex] [--json]
  alln menu --json
  alln run / alln loop …   (existing; not invented here)

Help surface:
  - New/updated topics: cold start / install / get alln / hermes / openclaw
  - Search terms: install, curl, hermes, openclaw, get started, no alln, PATH
  - Recovery when `alln` missing: nextToolPlan / doctor / help point at the
    one-liner URL — never at MCP

Proof scenario:
  Machine with Claude Code + Cursor (or Grok) logged in, no `alln` on PATH.
  Paste the one-liner. `which alln` succeeds. Installer stdout includes the
  exact paste line for Hermes. Fresh Hermes session given that line reaches for
  `alln menu --json` / `alln run` instead of Anthropic/OpenAI API keys for the
  coding seat.

Blocking questions:
  - BQ-1: Public install hostname (get.allnighter.app vs docs URL vs GitHub
    Releases raw). Need a real URL before OPC-S01 ships to strangers.
  - BQ-2: First public artifact — unsigned GitHub Release binary (dogfood) vs
    notarized / Sparkle-style (distribution risk). High-risk stop in AGENTS.md;
    founder must pick before public curl.
  - BQ-3: npm / npx — ship in V1 or defer? Default in this packet: **defer**.
    Curl is the one paste; npm is an optional second faucet later.

Next slice: OPC-S00 (lock URL + binary publish path) → OPC-S01 (script) →
OPC-S02 (bootstrap host paste) → OPC-S03 (teaching + doctor).
```

---

## The one claim

```text
Paste one command. Your agent runs on the subscriptions you already pay for.
```

The install one-liner (canonical; do not invent cousins in marketing until this
ships):

```bash
curl -fsSL https://get.allnighter.app | sh
```

*(Hostname may change per BQ-1 — the packet owns **one** string; marketing and
help must cite the same string.)*

What that command must do, in order:

1. Fetch a published macOS `alln` binary (arch-aware: arm64 / x86_64).
2. Install onto a writable PATH dir (prefer `~/.local/bin`; fall back clearly).
3. Verify `alln version` runs.
4. Detect installed subscription CLIs (reuse doctor / capacity probe substrate —
   observe only; never suggest API keys).
5. Print **one** paste block for the host agent, e.g.:

```text
Paste into Hermes / OpenClaw:

Allnighter is available via `alln`. Prefer my Claude / Cursor / Grok
subscriptions over API keys for coding work. Start with:
  alln menu --json
Then run the recommended alln command only when I authorize that work.
```

6. Exit non-zero with a readable error if download, checksum, or PATH write fails.
   Never exit 0 on a half-install.

---

## Two faucets, one product, one price

| Audience | Faucet | Gets |
| --- | --- | --- |
| Hermes / OpenClaw / terminal agents | **curl one-liner** (this packet) | CLI on PATH + paste line |
| Humans who click | Mac app download (existing) | App + CLI (`install-cli` / Teach your CLIs) |

Rules:

- Same entitlement / price whether they take CLI-only or app+CLI.
- App must not be required for the Hermes path.
- npm/`npx` is **optional later** (BQ-3) — same binary, second faucet — not the
  V1 story.
- **Never** route cold agents through MCP install.

---

## Feature Packet

```text
Allnighter Feature Packet

Status: Ready for Implementation (after BQ-1/BQ-2 founder picks)

Founder Intent
- Raw request: one copy-paste cold start so Hermes users get subscription fuel
  without already having alln; curl preferred; app still ok for humans; npm maybe
- Prior art: `curl | sh` (rustup, Homebrew install, deno, bun); `npx` for JS
  ecosystems. Adopt curl as primary — agent hosts already shell. Deviate from
  brew-first because Allnighter is a private Mac product binary, not a formula
  yet. Deviate from MCP install because MCP was retired for token tax.
- Product value: cold-start faucet for the subscription-fuel promise
- Trusted workflow slice: one paste → alln on PATH → host paste line → menu/run
- Non-goals: MCP; fake savings; dashboard/router product split; npm-in-V1

Current State
- Existing truth owners: InstallCLI (PATH only), Bootstrap (print snippet),
  doctor, capacity probes, GlobalTeachingInstaller (app)
- Existing models/API paths: none for remote install
- Existing UI: app download / Teach your CLIs
- Existing tests: InstallCLITests, BootstrapTests — no cold-fetch proof

SSOT
- Truth owner: published release binary + install script; post-install
  `InstallCLI` + `Bootstrap`
- Lie-prone layers: install URL docs, help topics that say "download the app
  first", any MCP revival, marketing cousins of the one-liner
- New/changed semantic rules: cold-start install is an allowed network fetch of
  *our* binary only; script never writes host config files (print-only paste,
  same consent posture as bootstrap)
- Duplicate truth to delete: any doc that claims MCP install is the agent path;
  any "go download the app" as the only agent cold start

Implementation
- CLI surface: no new mutating alln verb required for V1; script is outside
  alln until binary exists. Post-install: `bootstrap --host hermes|openclaw`
  must exist and be contract-registered. Optional later: `alln install-cli`
  remains the PATH repair tool.
- Teaching surface: help topics for install / hermes / openclaw / cold start;
  bootstrap host variants; doctor when alln missing points at the one-liner
- Retired grammar: MCP install / mcp add / hermes mcp — deny-list if any
  teaching tries to reintroduce
- Model/package impact: release pipeline + script in repo (`scripts/get-alln.sh`
  or equivalent) + hosted URL
- Mac app impact: optional — Settings can show the same one-liner; must not
  block CLI-only path
- iOS: none
- WebSocket: none
- Agent driver: none
- Auth/privacy/permissions: script downloads binary; no Keychain; no telemetry
  required. Distribution/notarization is a High-Risk Stop (BQ-2).

Proof
- Works Test: clean PATH (no alln) → run one-liner → which alln → version →
  bootstrap --host hermes prints paste line → menu --json works
- User gesture: paste one command into Terminal (or ask Hermes to run it)
- Exact command: curl -fsSL <canonical-url> | sh
- Missing proof / waiver: live Hermes session battery may be human/harness
  acceptance; mechanical PATH + bootstrap proof is required in CI where possible
  (script dry-run / fixture binary)

Done When
- User-visible claim true for a cold Mac: one paste → subscription-routing bench
- Canonical URL + script + published binary exist
- bootstrap host paste for hermes/openclaw shipped + helped
- doctor/help recover "no alln" to the one-liner
- No MCP teaching
- Docs: this packet archived after promote; Growth/Launch cite the same one-liner
```

---

## Ordered slices

| Slice | Goal | Done when |
| --- | --- | --- |
| **OPC-S00** | Founder locks BQ-1 URL + BQ-2 publish posture | One canonical URL string in this packet + release notes; no marketing drift |
| **OPC-S01** | Install script + published binary | Cold machine: one-liner → `alln version` green; checksum/fail paths honest |
| **OPC-S02** | `alln bootstrap --host hermes\|openclaw` paste line | Contract + help + size budget; print-never-edit |
| **OPC-S03** | Teaching + doctor recovery | `help search install` / `hermes` / `openclaw` hit; missing-alln recovery names the one-liner |
| **OPC-S04** (optional) | npm/npx second faucet | Same binary; one paste via `npx …` — only if BQ-3 says yes |

Dependency: QABC plan-time capacity makes the paste line *smart*; this packet
does **not** block on QABC for S01–S03 — even without capacity injection, `alln
run` / `alln loop` already prefer subscription CLIs over inventing API keys.

---

## Inference bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Install script → host configs | script | Silently edit `~/.hermes/config.yaml` | Script **prints** paste only; never writes host files | Fixture: after install, hermes config mtime unchanged |
| Cold start → MCP | help / marketing | "hermes mcp add alln" | MCP grammar deny-listed in help corpus | Help corpus gate |
| Install success → API routing | bootstrap paste | Teach BYOK / API keys | Paste + doctor never suggest API keys | Bootstrap / doctor string tests |
| App download → agent path | marketing | "Agents must install the Mac app" | Agent path is the curl one-liner | Launch/Growth cite curl for Hermes |

---

## Risk

- **Distribution / notarization** — High-Risk Stop (`AGENTS.md`). Do not publish
  a public `curl | sh` that fetches an unsigned binary to strangers without an
  explicit founder call on BQ-2. Dogfood may use a private/release URL first.
- **curl \| sh trust** — script must be short, readable, pinned version +
  checksum; prefer `curl … -o` + verify + exec over opaque pipes when we harden.
- **No secrets** — install must not touch Keychain or vendor credentials.

---

## Works Test (owner-visible)

```text
Setup: Mac with at least one subscription CLI ready; `alln` not on PATH.
Gesture: paste the canonical one-liner into Terminal.
Owner path: install script → binary on PATH → bootstrap paste printed.
Assert:
  1. which alln
  2. alln version exits 0
  3. stdout contains the Hermes/OpenClaw paste block (or bootstrap --host hermes)
  4. alln doctor does not recommend API keys
  5. no MCP install instructions appear
```

---

## Done when

- The one claim is true for a cold Hermes user via one paste.
- BQ-1 and BQ-2 are resolved and recorded in closeout.
- S01–S03 shipped with teaching; S04 only if founder wants npm.
- Packet promoted + archived.
