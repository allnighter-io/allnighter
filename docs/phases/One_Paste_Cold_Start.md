# One-Paste Cold Start

Status: **OPEN — founder priority (distribution wedge)** · **implementation-ready
(dual track: dogfood faucet free; public `curl | sh` blocked on BQ-1/BQ-2)**  
Owner: AllnighterCLI + distribution (install script / release binary) + teaching  
Created: 2026-07-31  
Updated: 2026-07-31 (implementation-ready pass — live-code corrections, slice
contracts, dual-track publish path)  
Origin: Founder intake — Hermes / OpenClaw power users need one copy-paste to go
from *no `alln`* to *agent runs on subscriptions they already pay for*, not API
keys. Brainstorm locked the product sentence and the install shape; this packet
is the build contract.

Ephemeral build packet. At closeout: promote keepable install/teaching law into
`docs/operations/` + `HelpTopicRegistry` / `Bootstrap` / a single install-URL
constant; code + release script are runtime SSOT; archive this packet. Do not
leave living distribution law only here.

Related (reuse, do not rebuild):
- archived `Agent_Front_Door.md` / `Agent_Onboarding.md` — findable + suggested
  once `alln` exists; **this packet owns the missing cold-start faucet**
- `InstallCLI.swift` — PATH **symlink** after a binary already exists (chicken/egg
  for fetch; still the PATH repair tool post-install)
- `Bootstrap.swift` + `TeachingSnippet.swift` — print-never-edit paste; hosts
  today are `claude|cursor|codex|generic` only
- `scripts/rebuild_cli.sh` — local-dev rebuild → `~/.local/bin` (pattern to
  mirror for install dir preference)
- open [`Quota_Aware_Bench_Continuity.md`](Quota_Aware_Bench_Continuity.md) —
  plan-time capacity in `menu`/`bootstrap` so the paste line is smarter; **not a
  blocker** for S01–S03
- archived `MCP_Retirement.md` — **MCP stays dead**; shell-out only
- deferred `docs/mvp/05_History_Presets_And_Distribution.md` P05-S06/S07 —
  notarized DMG still deferred; this packet is the **CLI faucet**, not the app
  DMG path (they share the High-Risk Stop on public distribution identity)

---

## Corrections against live code (2026-07-31)

Checked against the tree, not remembered. Implementers must treat these as law.

| # | Live fact | Packet consequence |
| --- | --- | --- |
| C1 | `Bootstrap.Host` = `claude \| cursor \| codex \| generic` only (`Bootstrap.swift`). CLI fail text and `ContractRegistry` flag summary match. | S02 **adds** `hermes` + `openclaw`. Update `Bootstrap.Host`, `AllnighterCLI.runBootstrap` error string, `ContractRegistry` flag, help, tests. |
| C2 | `Bootstrap.snippet` is **one shared body** for every host. `BootstrapTests` asserts `Set(all.map(\.snippet)).count == 1`. Body = binary fallback line + optional `install-cli` + **always** `scripts/rebuild_cli.sh` checkout advice + `TeachingSnippet.wrap()`. | Host differences belong in **`render()` lead-in** (and JSON `pasteTarget`), **not** a forked teaching body. Do not break shared-snippet SSOT without updating tests + `HelpService.hostInstructionBlock`. |
| C3 | Snippet always says: rebuild from an Allnighter **checkout** via `bash scripts/rebuild_cli.sh`. | **Poison for cold Hermes.** Cold users have no checkout. S02: gate checkout rebuild advice to dev/checkout binaries only, **or** drop it from the default on-PATH snippet and leave rebuild only in help topic "bootstrap" / "rebuild". Prefer gate or drop — never teach a missing path. |
| C4 | `InstallCLI` only **symlinks** the *running* binary. Default dir: `/usr/local/bin` if writable, else `~/.local/bin`. It cannot fetch. | Cold script must **download + place a real binary**, then symlink (or write) onto PATH. Prefer **`~/.local/bin`** for the agent faucet (matches `rebuild_cli.sh`; no sudo). Do not invent a second PATH policy without documenting the delta from `InstallCLI.defaultInstallDirectory`. |
| C5 | Help "getting started" / "bootstrap" say: if `which alln` fails, run `alln install-cli`. | **Lie.** That command requires `alln`. S03 must replace that recovery with the **canonical one-liner** (and absolute-path `install-cli` only when a binary already exists). |
| C6 | `alln doctor` is inside the binary. | Doctor **cannot** recover a machine with no `alln`. Pre-install recovery is docs/help **text that is reachable without alln** (README, marketing, host paste from a friend, this packet's one-liner). Post-install: doctor must not recommend API keys; PATH repair stays `install-cli`. |
| C7 | No public install hostname, no release binary publish job, no `scripts/get-alln.sh`. P05-S06 notarized DMG is **deferred**. | Dual track: **dogfood faucet** (fixture / private GH Release / local file) can ship S01 mechanically; **public** `curl \| sh` to strangers requires BQ-1 + BQ-2. |
| C8 | Product law: subscription CLIs only — never API keys / BYOK (`docs/phases/README.md` Post-MVP Product Laws). | Paste + doctor + help **never** suggest API keys. Negative tests required. |
| C9 | Teaching surface rule: same slice updates `HelpTopicRegistry` + contract flag text + retired MCP deny-list stays green. | S02 and S03 are not optional polish. |
| C10 | Proposed marketing paste in earlier draft diverged from `TeachingSnippet` (live-menu reflex, 10 rules, markers). | **Do not invent a cousin teaching body.** Installer may print a short **subscription-fuel preamble**, then run `alln bootstrap --host hermes` (or print the same render). Canonical agent discipline stays `TeachingSnippet`. |

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
  host paste block → next Hermes turn routes coding work through alln →
  mutating seats prefer subscription CLIs over API keys.

Non-goals:
  - MCP server / `hermes mcp add` / tool schemas in context (retired; do not revive)
  - Free dashboard + $9 auto-router as a separate product split
  - Fake "API Spend Avoided: $X" receipts
  - Teaching Hermes to be Allnighter (Allnighter is the bench the host calls)
  - Replacing QABC / loop park-yield (those are continuity; this is install)
  - Notarized Mac app DMG (P05-S06) — separate High-Risk track; CLI faucet only here
  - Linux / non-Darwin install in V1
  - Silently editing Hermes/OpenClaw/Claude/Cursor config files from the script

Current state (verified):
  - `alln install-cli` symlinks the *running* binary onto PATH — requires alln
  - `alln bootstrap` prints paste-ready snippet — requires alln; hosts lack hermes/openclaw
  - Snippet teaches checkout rebuild (`scripts/rebuild_cli.sh`) — wrong for cold users
  - Help recovers "no alln" with `alln install-cli` — unreachable without alln
  - Mac app can Teach your CLIs (ONB) — requires app install first
  - No public cold-start URL, no signed release binary faucet, no npm package
  - Capacity / substitution / loop park exist or are in-flight — useless if the
    host never gets `alln` on PATH

Truth owner (target):
  - Cold install: release install script + published macOS `alln` binary
    (versioned + checksum); script is the only actor that may fetch
  - Install URL string: **one** constant (script default + help/README cite it;
    no marketing cousins)
  - Post-install PATH repair: existing `InstallCLI`
  - Host paste: `Bootstrap.render` / `Bootstrap.json` (hosts include hermes|openclaw)
  - Teaching body: `TeachingSnippet` (shared); host preamble for subscription fuel
  - Pre-alln recovery text: README + HelpTopicRegistry install topics + one-liner
    (reachable in docs even when binary missing)

CLI surface (post-install — product contract stays CLI-only):
  alln version
  alln doctor
  alln bootstrap [--host hermes|openclaw|generic|claude|cursor|codex] [--json]
  alln menu --json
  alln run / alln loop …   (existing; not invented here)
  alln install-cli         (PATH repair only; not the cold fetch)

Help surface:
  - New/updated topics: cold start / install / get alln / hermes / openclaw
  - Search terms: install, curl, hermes, openclaw, get started, no alln, PATH
  - Recovery when `alln` missing: **canonical one-liner** — never MCP, never
    "run alln install-cli" as the only step

Proof scenario:
  Machine with Claude Code + Cursor (or Grok) logged in, no `alln` on PATH.
  Paste the one-liner. `which alln` succeeds. Installer stdout includes the
  Hermes paste block (bootstrap --host hermes). Fresh Hermes session given that
  block reaches for `alln menu --json` / `alln run` instead of Anthropic/OpenAI
  API keys for the coding seat.
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

*(Hostname may change per BQ-1 — the packet and code share **one** string.
Dogfood may override with `ALLN_INSTALL_BASE_URL` / script flags; marketing still
cites only the public string once BQ-1 locks.)*

What that command must do, in order:

1. Refuse non-macOS (Darwin) with a clear stderr message and non-zero exit.
2. Detect arch (`arm64` / `x86_64`) and select the matching published asset.
3. Fetch the versioned macOS `alln` binary + checksum (HTTPS only).
4. Verify checksum (and size sanity). Fail closed on mismatch.
5. Install binary to a stable home path, then put `alln` on a writable PATH dir
   (prefer `~/.local/bin`; create it if needed; print how to add to PATH if the
   dir is not on PATH yet).
6. Clear quarantine only if required for the dogfood/unsigned path — document
   it; never hide Gatekeeper failures.
7. Verify `alln version` exits 0 using the installed path.
8. Optionally observe installed subscription CLIs (doctor / detect substrate —
   observe only; never suggest API keys). Nice-to-have in S01; required honesty
   if printed.
9. Print **one** paste block by invoking the installed binary:
   `alln bootstrap --host hermes` (or `openclaw` if `ALLN_BOOTSTRAP_HOST` set;
   default `hermes` for the agent faucet). That output is SSOT — script does not
   hand-maintain a second teaching body.
10. Exit non-zero with a readable error if download, checksum, or PATH write fails.
    Never exit 0 on a half-install.

Hardened variant (document; may be what the hosted page serves after dogfood):

```bash
curl -fsSL https://get.allnighter.app/install.sh -o /tmp/alln-install.sh
# show / checksum script itself in hardened mode
sh /tmp/alln-install.sh
```

V1 product story remains the one-liner pipe; hardening is an allowed evolution
of the same URL without inventing a second public brand string.

---

## Two faucets, one product, one price

| Audience | Faucet | Gets |
| --- | --- | --- |
| Hermes / OpenClaw / terminal agents | **curl one-liner** (this packet) | CLI on PATH + paste block |
| Humans who click | Mac app download (existing / P05-S06 later) | App + CLI (`install-cli` / Teach your CLIs) |

Rules:

- Same entitlement / price whether they take CLI-only or app+CLI.
- App must not be required for the Hermes path.
- npm/`npx` is **optional later** (BQ-3) — same binary, second faucet — not the
  V1 story.
- **Never** route cold agents through MCP install.

---

## Dual track (so work is not blocked on notarization)

| Track | Audience | URL / artifact | May ship when |
| --- | --- | --- | --- |
| **A — Dogfood** | Founder + trusted testers | Private GH Release, or `ALLN_INSTALL_BASE_URL=file://…` / local fixture; script in repo | S01 script + checksum + mechanical tests green |
| **B — Public** | Strangers on the internet | Canonical `https://get.allnighter.app` (or BQ-1 URL) serving script that fetches a **BQ-2-approved** binary | BQ-1 + BQ-2 recorded; High-Risk Stop cleared by founder |

Implement S01–S03 against track A. Point track B at the same script once BQ
locks. Do not publish track B from CI without an explicit founder go.

---

## Blocking questions (founder)

| ID | Question | Default in this packet | Blocks |
| --- | --- | --- | --- |
| **BQ-1** | Public install hostname | Provisional: `https://get.allnighter.app` | Public marketing + track B only |
| **BQ-2** | First public artifact: unsigned GH Release (dogfood) vs notarized / Developer ID CLI binary | **Dogfood = private/unsigned OK for track A.** **Track B = founder must pick before public curl.** High-Risk Stop in `AGENTS.md`. | Public track B |
| **BQ-3** | npm / npx in V1? | **Defer** (S04 optional) | Nothing in S01–S03 |

Record answers in the decision log below when founder picks; update the
canonical string in script + help in the same commit.

### Decision log

| Date | ID | Decision | Decided by |
| --- | --- | --- | --- |
| 2026-07-31 | BQ-3 | Defer npm/npx to optional S04 | Packet default (founder intake) |
| — | BQ-1 | *open* — provisional URL in packet | — |
| — | BQ-2 | *open* — track A dogfood free; track B blocked | — |

---

## Feature Packet

```text
Allnighter Feature Packet

Status: Implementation-ready (track A). Track B blocked on BQ-1/BQ-2.

Founder Intent
- Raw request: one copy-paste cold start so Hermes users get subscription fuel
  without already having alln; curl preferred; app still ok for humans; npm maybe
- Prior art: `curl | sh` (rustup, Homebrew install, deno, bun). Adopt curl as
  primary — agent hosts already shell. Deviate from brew-first: private Mac
  product binary, not a formula yet. Deviate from MCP install: MCP retired for
  token tax.
- Product value: cold-start faucet for the subscription-fuel promise
- Trusted workflow slice: one paste → alln on PATH → host paste block → menu/run
- Non-goals: MCP; fake savings; dashboard/router split; npm-in-V1; Linux V1;
  silent host config edits; inventing a second teaching body

Current State
- Existing truth owners: InstallCLI (PATH symlink only), Bootstrap + TeachingSnippet,
  doctor, capacity probes, GlobalTeachingInstaller (app), rebuild_cli.sh
- Existing models/API paths: none for remote install
- Existing UI: app download / Teach your CLIs
- Existing tests: InstallCLITests, BootstrapTests — no cold-fetch proof
- Lie in help: "no alln → alln install-cli"

SSOT
- Truth owner: published release binary + install script; post-install InstallCLI
  + Bootstrap; teaching body TeachingSnippet; one install-URL constant
- Lie-prone layers: install URL docs, help "download the app first" / "alln
  install-cli" as only cold recovery, MCP revival, marketing cousins of the
  one-liner, hand-maintained paste text in the shell script
- New/changed semantic rules: cold-start install is an allowed network fetch of
  *our* binary only; script never writes host config files (print-only paste,
  same consent posture as bootstrap)
- Duplicate truth to delete: MCP as agent install path; "go download the app" as
  the only agent cold start; help recovery that requires alln to install alln

Implementation
- CLI surface: no new mutating alln verb for V1 fetch. Script is outside alln
  until binary exists. Post-install: bootstrap --host hermes|openclaw registered.
  install-cli remains PATH repair.
- Teaching surface: help topics + fixed recovery strings; bootstrap host variants
- Retired grammar: MCP install / mcp add / hermes mcp — keep deny-list green
- Model/package impact: scripts/get-alln.sh (or scripts/install/get-alln.sh) +
  release notes / publish recipe; optional GitHub Actions later under BQ-2
- Mac app impact: optional Settings one-liner later; must not block CLI-only
- iOS / WebSocket / agent driver: none
- Auth/privacy: script downloads binary; no Keychain; no telemetry required.
  Distribution/notarization is High-Risk Stop (BQ-2) for track B.

Proof
- Works Test: clean PATH → one-liner (or script with fixture base URL) → which
  alln → version → bootstrap --host hermes → menu --json; no API keys; no MCP
- User gesture: paste one command
- Missing proof / waiver: live Hermes battery may be human/harness; mechanical
  PATH + bootstrap + script dry-run with fixture binary required

Done When
- One claim true on a cold Mac via one paste (track A dogfood OK for founder)
- Canonical URL + script + binary path exist; track B only after BQ-1/2
- bootstrap host paste for hermes/openclaw shipped + helped
- doctor/help recover "no alln" to the one-liner (not install-cli alone)
- No MCP teaching
- Packet promoted + archived
```

---

## Install script contract (OPC-S01)

**Path (recommended):** `scripts/get-alln.sh`  
**Hosted entry:** whatever BQ-1 serves must be this script (or a thin wrapper
that execs the same logic) so dogfood and public do not diverge.

### Behavior

| Step | Contract |
| --- | --- |
| OS | `uname -s` must be Darwin; else exit 1 with "macOS only" |
| Arch | `uname -m` → `arm64` or `x86_64` (map `amd64` → `x86_64` if ever seen); else exit 1 |
| Version | Default `latest` resolved by `BASE/latest` or env `ALLN_VERSION=0.x.y` |
| Base URL | Env `ALLN_INSTALL_BASE_URL` overrides default (dogfood/file/fixture). Default constant = provisional public URL root |
| Assets | e.g. `alln-macos-{arch}` + `alln-macos-{arch}.sha256` (names locked in S00/S01 when first release is cut — pick one scheme and do not drift) |
| Verify | `shasum -a 256` (or `sha256sum`) must match; fail closed |
| Layout | Binary at `~/.local/share/allnighter/bin/alln` (versioned sibling optional); symlink or install `alln` → `~/.local/bin/alln` |
| PATH | If `~/.local/bin` not on PATH, print exact line to add (`export PATH="$HOME/.local/bin:$PATH"`) and still exit 0 **only if** `~/.local/bin/alln version` works via absolute path; document that agents must use absolute path until PATH is updated — **prefer** also detecting common agent PATH gaps |
| Post | Run `"$HOME/.local/bin/alln" bootstrap --host "${ALLN_BOOTSTRAP_HOST:-hermes}"` (or absolute installed path) |
| Fail | Non-zero on any failed step; no partial "success" |
| Writes | Only under `~/.local/share/allnighter/`, `~/.local/bin/`, and temp dirs. **Never** `~/.hermes/`, `~/.claude/`, etc. |
| Secrets | No Keychain, no tokens, no analytics |

### Env / flags (minimal)

| Name | Purpose |
| --- | --- |
| `ALLN_INSTALL_BASE_URL` | Override download root (fixture / private release) |
| `ALLN_VERSION` | Pin version (optional) |
| `ALLN_BOOTSTRAP_HOST` | `hermes` (default) \| `openclaw` \| `generic` \| … |
| `ALLN_INSTALL_DIR` | Override PATH dir (default `~/.local/bin`) |
| `--dry-run` | Print planned actions; no write/fetch (or fetch to temp only) — for CI |

### Tests (mechanical)

- Shellcheck (or `bash -n`) on script.
- Fixture binary + local `file://` or `python -m http.server` base URL:
  install into temp HOME → `version` green → bootstrap stdout contains teaching
  markers / `alln menu --json`.
- Checksum mismatch → non-zero, no binary left on PATH.
- Non-Darwin mock → non-zero.
- After install, hermes config fixture mtime unchanged (inference ban).

### Publish recipe (S00/S01 notes — not full CI yet)

1. `swift build -c release --product alln` (same scratch discipline as
   `rebuild_cli.sh` if building on a protected checkout).
2. Copy binary to asset name for arch; write `.sha256`.
3. Upload to dogfood channel (private Release or internal URL).
4. Point `ALLN_INSTALL_BASE_URL` at that channel for Works Test.

---

## Bootstrap host contract (OPC-S02)

### Host enum extension

Add to `Bootstrap.Host`:

| Host | `pasteTarget` (print-only guidance) |
| --- | --- |
| `hermes` | Hermes system / tools instructions (or host context file — print-only; Allnighter never writes it) |
| `openclaw` | OpenClaw agent instructions / system prompt (print-only; Allnighter never writes it) |

Exact product nouns can be tightened when founders confirm Hermes/OpenClaw file
paths; **v1 must not claim a path we have not verified**. Prefer honest
"host system prompt / tools instructions" over a guessed path.

### Render shape

```text
Paste into <pasteTarget>:

<optional host preamble — 2–4 lines max>
  - Allnighter coordinates the subscription CLIs on this Mac (Claude, Cursor,
    Codex, Grok, …). Prefer those over API keys for coding work.
  - After install, start with `alln menu --json` and run recommended commands
    only when the user authorizes that work.

<shared Bootstrap.snippet — TeachingSnippet SSOT>
```

Rules:

- Shared `snippet()` stays host-invariant (keep `BootstrapTests` shared-snippet
  assertion unless deliberately expanded).
- Preamble is host-specific and **short** (byte/line budget: keep total render
  readable; extend tests with a max line or byte ceiling for hermes render).
- Strip or gate **checkout rebuild** line from default snippet (C3).
- JSON: `host`, `pasteTarget`, `snippet` (shared body), existing fields; preamble
  may live only in human render **or** be folded into `snippet` for hermes only
  — if folded, update the "one snippet for all hosts" test and document why.

**Recommendation:** keep `snippet` shared; put subscription preamble only in
`render()` for `hermes`/`openclaw` (and mention it in human stdout). JSON
consumers still get `TeachingSnippet` + binary fallback; add optional
`preamble: String?` to `Bootstrap.JSON` if agents need it (schema bump +
contract). Prefer adding `preamble` for hermes/openclaw so `--json` hosts are
not second-class.

### Files to touch (S02)

- `Packages/AllnighterCore/Sources/AllnighterCore/Bootstrap.swift`
- `Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift` (`runBootstrap`)
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift` (host flag summary)
- `Packages/AllnighterCore/Sources/AllnighterCore/HelpTopicRegistry.swift` (host list)
- `Packages/AllnighterCore/Tests/AllnighterCoreTests/BootstrapTests.swift`
- Contract export / schema if `Bootstrap.JSON` gains `preamble`
- Example recipe optional: `bootstrap_hermes_json`

### Negative tests (S02)

- No `mcp`, `mcp add`, `API key`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY` in
  hermes/openclaw render or JSON snippet/preamble.
- No `scripts/rebuild_cli.sh` in on-PATH cold snippet (after C3 fix).
- Print-never-edit: bootstrap still does not touch the filesystem.

---

## Teaching + doctor recovery (OPC-S03)

### Help lies to delete

| Location | Today | Replace with |
| --- | --- | --- |
| Help topic getting started / bootstrap | `which alln` fails → `alln install-cli` | Canonical one-liner; then `alln install-cli` only as PATH **repair** when binary exists but is not linked |
| README "If `alln` isn't on PATH" | `alln install-cli` only | One-liner for cold start; `install-cli` for repair |
| Any "download the Mac app first" as sole agent path | — | Agent path = curl one-liner |

### New / updated help

- Topic or section: **Cold start / install** — one-liner, macOS-only, no MCP.
- Aliases / search: `install`, `curl`, `hermes`, `openclaw`, `get alln`,
  `no alln`, `PATH`, `get started`.
- Bootstrap topic: document `--host hermes|openclaw`.
- Doctor: when binary **is** present, never recommend API keys; if PATH broken,
  prefer absolute path + `install-cli`. Doctor does not claim to fix missing
  binary via itself.

### Install URL constant

Single source for the public string, e.g.:

- `InstallCLI` or small `ColdStartInstall` enum in Core with
  `public static let canonicalOneLiner = "curl -fsSL https://get.allnighter.app | sh"`
- Help + README + script default cite it (script may duplicate the URL as the
  shell default with a comment "keep in sync with ColdStartInstall" **or**
  generate script header from the constant in a later slice — V1 comment sync
  is acceptable if a test greps both).

### Files to touch (S03)

- `HelpTopicRegistry.swift` + help corpus tests / retired vocabulary gate
- `README.md` agent cold-start lines
- Optional: `DoctorReport` only if a check currently suggests API keys (verify;
  do not invent doctor scope)

---

## Ordered slices

| Slice | Goal | Done when | Depends |
| --- | --- | --- | --- |
| **OPC-S00** | Lock dogfood publish path + asset naming; record BQ-1/2 status | Asset names + dogfood upload steps in this packet; provisional URL still OK | — |
| **OPC-S01** | Install script + fixture/dogfood binary | Track A Works Test green; checksum fail paths honest; script never writes host configs | S00 asset names |
| **OPC-S02** | `bootstrap --host hermes\|openclaw` + C3 snippet fix | Contract + help host list + tests; print-never-edit; no API-key teaching | — (parallel with S01) |
| **OPC-S03** | Teaching + recovery | `help search install` / `hermes` / `openclaw` hit; no-alln recovery names one-liner; README fixed | Canonical URL constant (provisional OK) |
| **OPC-S04** (optional) | npm/npx second faucet | Same binary; only if BQ-3 flips | Track B healthy |
| **OPC-S05** (optional) | Public track B cutover | Founder BQ-1/2 signed; hosted URL serves S01 script; notarization/signing per BQ-2 | S01–S03 + BQ |

**Parallelism:** S02 and S03 can land without a public binary. S01 needs a
fixture binary for CI even without notarization.

**QABC:** does not block S01–S03. Capacity in bootstrap is a later nice-to-have
on the same paste path.

---

## Per-slice implementation checklist

### OPC-S00 — Publish path lock

- [ ] Choose asset naming: `alln-macos-arm64` / `alln-macos-x86_64` + `.sha256`
- [ ] Dogfood channel: private GitHub Release **or** founder-held HTTPS bucket
- [ ] Document build one-liner (release `alln` product from `Packages/AllnighterCore`)
- [ ] Record BQ-1/BQ-2 open/closed in decision log
- [ ] No public DNS cutover required for S00

### OPC-S01 — Script + binary

- [ ] Add `scripts/get-alln.sh` per contract above
- [ ] Fixture-based CI or `scripts/` prove script (no network to strangers)
- [ ] Works Test on a Mac with `ALLN_INSTALL_BASE_URL` pointing at dogfood/fixture
- [ ] Inference ban: hermes config mtime unchanged
- [ ] Do **not** enable public get.allnighter.app until S05 + BQ

### OPC-S02 — Bootstrap hosts

- [ ] `hermes` / `openclaw` cases + paste targets
- [ ] Optional `preamble` on JSON
- [ ] C3: remove/gate checkout rebuild from cold snippet
- [ ] ContractRegistry + CLI usage string
- [ ] Tests: hosts parse, preamble subscription language, no MCP/API keys, budgets
- [ ] Proof filter: `scripts/swift-test.sh --filter BootstrapTests`

### OPC-S03 — Teaching

- [ ] Help topics + search aliases
- [ ] README cold-start
- [ ] Canonical one-liner constant + dual citation
- [ ] Help corpus / retired vocabulary still green
- [ ] Proof filter: HelpTopicRegistry / related tests

---

## Inference bans

| Junction | Owner | Bad inference | Ban | Negative test |
| --- | --- | --- | --- | --- |
| Install script → host configs | script | Silently edit Hermes/OpenClaw/Claude config | Script **prints** paste only; never writes host files | Fixture: after install, host config mtime unchanged |
| Cold start → MCP | help / marketing | `hermes mcp add alln` | MCP grammar deny-listed | Help corpus gate |
| Install success → API routing | bootstrap paste | Teach BYOK / API keys | Paste + doctor never suggest API keys | Bootstrap / doctor string tests |
| App download → agent path | marketing | "Agents must install the Mac app" | Agent path is the curl one-liner | Launch/Growth cite curl for Hermes |
| No alln → install-cli | help | Tell user to run `alln install-cli` when alln is missing | Cold recovery is the one-liner | Help string test |
| Script → second teaching body | script | Hand-written Hermes manifesto that drifts from TeachingSnippet | Script calls `alln bootstrap --host …` | Install stdout contains teaching markers / menu reflex |
| Checkout rebuild → cold user | Bootstrap.snippet | Teach `scripts/rebuild_cli.sh` with no checkout | Gate or remove for release installs | Snippet test |

---

## Risk

- **Distribution / notarization** — High-Risk Stop (`AGENTS.md`). Do not publish
  track B (`curl | sh` to strangers) without founder BQ-2. Track A dogfood may
  use a private/release URL first.
- **curl \| sh trust** — script must stay short and readable; pin version +
  checksum; prefer download-to-file + verify + exec when hardening.
- **Gatekeeper** — unsigned downloads may quarantine; fail with a readable fix
  rather than silent non-start.
- **No secrets** — install must not touch Keychain or vendor credentials.
- **PATH not updated in agent sessions** — install can succeed while Hermes still
  lacks `~/.local/bin`; paste block and installer stdout must show absolute
  binary path as fallback (Bootstrap already supports binary fallback).

---

## Works Test (owner-visible)

```text
Setup: Mac with at least one subscription CLI ready; `alln` not on PATH.
      (CI may use ALLN_INSTALL_BASE_URL + fixture binary + temp HOME.)
Gesture: paste the canonical one-liner (or dogfood equivalent).
Owner path: install script → binary on PATH (or ~/.local/bin) → bootstrap paste.
Assert:
  1. which alln  OR  absolute ~/.local/bin/alln is executable
  2. alln version exits 0
  3. stdout contains Hermes paste block / teaching markers / menu --json reflex
  4. alln doctor (post-install) does not recommend API keys
  5. no MCP install instructions appear
  6. no host agent config files were modified by the script
```

---

## Done when

- The one claim is true for a cold Hermes user via one paste (track A sufficient
  for founder dogfood; track B for strangers).
- BQ-1 and BQ-2 are resolved and recorded before public track B.
- S01–S03 shipped with teaching; S04 only if founder wants npm.
- Help no longer teaches unreachable `alln install-cli` as the cold-start path.
- Packet promoted + archived.

---

## Implementation order (recommended)

1. **OPC-S02** first (no network, unblocks installer step 9 and teaching).
2. **OPC-S03** in parallel or immediately after (fixes the live help lie).
3. **OPC-S00** asset naming + dogfood upload.
4. **OPC-S01** script + fixture proof.
5. **OPC-S05** only after founder BQ-1/BQ-2 for public curl.
