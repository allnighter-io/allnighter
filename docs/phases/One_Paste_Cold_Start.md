# One-Paste Cold Start (+ shared release channel)

Status: **OPEN — founder priority (distribution wedge)** · implementation-ready  
Owner: install script + release manifest + CLI projection + Mac update UI  
Created: 2026-07-31  
Updated: 2026-07-31 (release channel + agent/Mac update discovery as same system)  
Origin: Hermes / OpenClaw users with **no `alln`** need one paste so agents run
on **subscription CLIs**, not API keys. Follow-on: once installed, **CLI-only
users and agents never open the Mac app** — they still need to learn when a
**release** is available (not every git commit).

Ephemeral packet. Closeout: promote install/teaching/update law into code +
`docs/operations/` / help; archive this file.

Related (reuse): `InstallCLI.swift` (PATH symlink only), `Bootstrap.swift` +
`TeachingSnippet.swift`, `scripts/rebuild_cli.sh`, open QABC (capacity in menu —
not a blocker), archived MCP retirement (**MCP stays dead**), deferred P05-S06
app DMG (this packet owns the **shared release channel** the DMG/Sparkle path
must use when it ships — not a second update product).

---

## The one claim

```text
Paste one command. Your agent runs on the subscriptions you already pay for.
```

```bash
curl -fsSL https://get.allnighter.app | sh
```

One public install/upgrade string. Help, README, marketing, menu `update.command`,
and the script default all cite it. No cousins.

**Second claim (same faucet, ongoing):**

```text
When a release ships, the next alln menu (or Mac app check) says so —
and the fix is the same one command (or app install of that release).
```

---

## Design laws (stupid simple)

These beat long checklists. If a design fights a law, the design is wrong.

### 1. Succeed by absolute path; treat bare `alln` as a bonus

`~/.local/bin` is **not** on default macOS `zsh`/`bash` PATH. Asserting
`which alln` right after install is a lie on stock Macs.

**Install layout:**

1. Store the real binary at `~/.local/share/allnighter/bin/alln` (stable home).
2. Link/copy onto the **first** of:
   - a directory already on `$PATH` that is writable without sudo
   - `/usr/local/bin` if writable (often on PATH; same preference as
     `InstallCLI.defaultInstallDirectory`)
   - else `~/.local/bin` (create if needed)
3. Prove install with **absolute** path: `"$BIN" version` must exit 0.
4. If the link dir is not on `$PATH`, **print** the one export line — do **not**
   auto-edit `~/.zshrc` / `~/.bash_profile`. Silent shell-rc edits surprise
   agents and break the print-never-edit consent posture.
5. Installer stdout and bootstrap always include the **absolute binary fallback**
   (Bootstrap already does this). Hosts that never reload PATH still work.

Works Test primary assert: absolute `version` green + paste block printed.
`which alln` is optional and only expected when the link dir was already on PATH
or the user exported it.

### 2. Never half-run; never half-install

- **Outer pipe:** script body is `main() { … }; main "$@"` so a truncated
  `curl | sh` does not execute half a script.
- **Binary fetch:** download to a temp file → verify **SHA256** → install → only
  then print success. Fail closed; never exit 0 on a partial install.
- Prefer the hosted page to keep serving this same script (hardening later:
  download script to a file first — same URL brand).

### 3. Public binary must run on Apple Silicon

Unsigned / wrong-signed arm64 Mach-O dies under Gatekeeper (`Code Signature
Invalid`). Track:

| Track | Audience | Bar |
| --- | --- | --- |
| **Dogfood** | Founder / trusted | Local build or private URL; ad-hoc sign OK; SHA256 still required for any network fetch |
| **Public** | Strangers | **Developer ID Application** sign (hardened runtime). SHA256 in script. Notarization before a loud launch — not required to start dogfood |

High-Risk Stop (`AGENTS.md`): do not flip the public hostname to strangers until
signing (BQ-2) is real.

### 4. Static asset URLs — no GitHub API

Do not resolve version via `api.github.com` (shared 60 req/hr rate limits kill
agent runners). `get.allnighter.app` (or override base) serves **direct** paths:

```text
https://get.allnighter.app/alln-macos-arm64
https://get.allnighter.app/alln-macos-arm64.sha256
https://get.allnighter.app/alln-macos-x86_64
https://get.allnighter.app/alln-macos-x86_64.sha256
https://get.allnighter.app/latest.json          # release channel SSOT (S06)
```

Edge redirect / object store / Worker — implementer's choice. Contract: fixed
paths, no API. V1 paths may mean "latest".

### 5. One teaching body; script never writes host configs

Installer ends by running the installed binary:

```bash
"$BIN" bootstrap --host hermes   # or openclaw via ALLN_BOOTSTRAP_HOST
```

That print is SSOT (`TeachingSnippet` + host preamble). Script does not
hand-maintain a second manifesto. Script never writes Hermes / Claude / Cursor
files — print only (same as bootstrap).

### 6. One product on PATH — last writer wins

Cold-start places a **standalone** binary. App `install-cli` still symlinks the
*running* binary. Do not build upgrade-negotiation in V1.

Rule: whatever last ran `install-cli` (or the cold script's link step) owns the
PATH name `alln`. `alln version` shows which build. Optional later: doctor notes
mismatch. Not a cold-start blocker.

### 7. Subscriptions only; MCP dead

Paste, help, doctor: never API keys / BYOK; never `mcp add` / MCP install.

### 8. Release ≠ commit; one channel for CLI and Mac app

40 commits/day is noise. An **update** exists only when we **publish** a release
and bump the channel manifest. Agents and humans share **one** system:

| Rule | Detail |
| --- | --- |
| **SSOT** | `latest.json` on the install host (same base URL as cold start) |
| **Announce ≠ apply** | Surfaces say “update available + command”; never silent binary swap mid-session |
| **Upgrade path** | CLI: same one-liner as cold start (optional thin `alln update` wrapper). Mac app: install the published app build for that release (Sparkle or manual) — versions align with the **same** manifest |
| **Where agents look** | Piggyback `alln menu --json` (already taught as session start). Secondary: `version --json`, `doctor` |
| **Where humans look** | Same menu field if they use CLI; Mac app update UI reads the **same** channel — not a private Sparkle-only truth |
| **Network tax** | Cache check (~24h). Fail open (no field). Never block `run` on check failure |
| **Not every commit** | CI does not flip `latest.json` on merge; only on an explicit release publish |

If the Mac app and CLI disagree on “what’s latest,” the channel is wrong — fix the
manifest, don’t add a second feed.

---

## Founder intake (short)

```text
Intent:
  1) one paste for Hermes/OpenClaw → alln on the machine → host paste →
     menu/run on subscription CLIs, not API keys.
  2) after install, agents + CLI-only humans learn about *releases* without
     opening the Mac app; Mac app uses the same release truth.

Value: kill chicken-and-egg; stop rotting on week-old bins while shipping daily.
Non-goals: MCP; npm in V1; fake $ savings; auto-edit host/shell configs;
  Linux; auto-apply upgrades; commit-SHA "you're behind"; GH API; app-only
  Sparkle as sole update channel; forcing alln serve for update checks.
```

### Live bugs this packet fixes

| Lie / gap today | Fix |
| --- | --- |
| Help: no alln → run `alln install-cli` | Cold recovery = one-liner; `install-cli` is PATH **repair** only |
| `Bootstrap.Host` has no hermes/openclaw | Add them (S02) |
| Snippet always teaches checkout `rebuild_cli.sh` | Drop/gate for release installs (poison when no checkout) |
| No fetch faucet | `scripts/get-alln.sh` + published binary |
| Doctor cannot run without alln | Pre-install recovery is the one-liner in docs/help text |
| Updates only visible if you open the Mac app | Shared `latest.json` + menu/`update` field (S06); app UI same channel |
| Humans/agents don’t know to “check for updates” | Piggyback the command they already run (`menu --json`) |

---

## Blocking questions

| ID | Decision (packet default) | Blocks |
| --- | --- | --- |
| **BQ-1** | Canonical URL: `https://get.allnighter.app` (static assets; no GH API) | Public cutover only |
| **BQ-2** | Public = Developer ID signed + SHA256. Dogfood free without public DNS. Notarize before big launch. | Public cutover only |
| **BQ-3** | **Defer npm/npx** | Nothing in V1 |
| **BQ-4** | Soft update only in V1 (announce + command). Hard `minSupportedBinaryVersion` fail closed = later packet if protocol breaks. | Not V1 |

### Decision log

| Date | ID | Decision |
| --- | --- | --- |
| 2026-07-31 | BQ-1 | Provisional lock: `get.allnighter.app` + static paths (founder can rename before public) |
| 2026-07-31 | BQ-2 | Public floor = Developer ID + SHA256; dogfood unsigned/private OK |
| 2026-07-31 | BQ-3 | Defer npm |
| 2026-07-31 | BQ-4 | Soft announce only; no force-upgrade gate in this packet |

---

## Two faucets, one product, one price, one channel

| Who | Install | Learn about updates | Apply update |
| --- | --- | --- | --- |
| Terminal agents | curl one-liner | `alln menu --json` → `update` | same one-liner (authorized) |
| CLI-only humans | curl one-liner | menu / version / doctor | same one-liner |
| Mac app humans | app download / DMG | app UI + optional CLI | app installer / Sparkle for **that** release |

Same entitlement. App not required for Hermes. npm later only.  
**One release channel** (`latest.json`) feeds every row above.

---

## Install script contract (`scripts/get-alln.sh`)

```text
main() {
  1. Darwin only; else exit 1
  2. arch: arm64 | x86_64
  3. BASE=${ALLN_INSTALL_BASE_URL:-https://get.allnighter.app}
  4. curl binary + .sha256 to temp; verify sha256; fail closed
  5. install to ~/.local/share/allnighter/bin/alln
  6. link into PATH dir per law 1; print export line if needed
  7. "$BIN" version   # absolute — required success
  8. "$BIN" bootstrap --host ${ALLN_BOOTSTRAP_HOST:-hermes}
  9. exit 0 only if 7 succeeded and link step did not leave a broken state
}
main "$@"
```

Env: `ALLN_INSTALL_BASE_URL` (dogfood/fixture), `ALLN_BOOTSTRAP_HOST`,
`ALLN_INSTALL_DIR` (optional force link dir).  
Writes only under `~/.local/share/allnighter/`, chosen link dir, temp.  
No Keychain, no telemetry, no host config edits, no shell-rc edits.

**CI proof:** fixture binary + `ALLN_INSTALL_BASE_URL` + temp HOME; checksum
mismatch → non-zero; host config mtime unchanged.

**Also the upgrade tool:** re-running this script *is* CLI upgrade. Optional
`alln update` (S06) is a thin wrapper, not a second downloader.

---

## Release channel contract (`latest.json`) — OPC-S06

Published only on **release**, not on every merge:

```json
{
  "schemaVersion": 1,
  "cliVersion": "0.12.0",
  "appVersion": "0.12.0",
  "releasedAt": "2026-07-31T00:00:00Z",
  "notes": "optional one line for humans/agents",
  "installCommand": "curl -fsSL https://get.allnighter.app | sh",
  "cli": {
    "arm64": { "url": "https://get.allnighter.app/alln-macos-arm64", "sha256": "…" },
    "x86_64": { "url": "https://get.allnighter.app/alln-macos-x86_64", "sha256": "…" }
  },
  "app": {
    "url": "https://get.allnighter.app/Allnighter.dmg",
    "sha256": "…"
  }
}
```

Rules:

- `cliVersion` / `appVersion` may match (preferred) or diverge only when a release
  truly ships one surface — still **one file**, not two private channels.
- `installCommand` must equal the canonical one-liner string.
- Dogfood: same shape at a private base URL; CLI/app honor `ALLN_INSTALL_BASE_URL`
  / Settings override for checks.
- Sparkle (when wired): appcast **derived from or pointing at this release**, not
  a hand-maintained parallel “latest” that can drift. Prefer generating appcast
  from the same publish step that writes `latest.json`.

### CLI projection (agent-native)

Cache path: Application Support (or equivalent), TTL ~24h.  
Inject into **`alln menu --json`** (primary — agents already open it):

```json
"update": {
  "available": true,
  "current": "0.11.0",
  "latest": "0.12.0",
  "notes": "optional one line",
  "command": "curl -fsSL https://get.allnighter.app | sh"
}
```

When current ≥ latest or check failed/skipped: omit `update` or
`"available": false` (prefer omit to keep the happy path quiet).

Also expose on `alln version --json` and a doctor check when useful.  
Optional: `alln update` / `alln update --check` — check or re-exec install
script; print-never-auto unless user/agent passes an explicit apply flag later.

**Teaching:** one reflex line (bootstrap/help): if `update.available`, tell the
user and run `update.command` only when they authorize an upgrade — same consent
as other spending/mutating recommendations.

**Non-goals for S06:** auto-replace binary; hard min-version kill; serve daemon
required; GH API; nag on every command.

### Mac app projection (same channel)

Today: update UX is app-centric and easy to miss if the app is closed for a week.
Improve under **the same laws**:

| Do | Don’t |
| --- | --- |
| Read `latest.json` (or generated Sparkle feed from the same publish) | Own a second “latest version” only in app prefs code |
| Compare `appVersion` to running app; show notes + install path | Require opening a buried Settings page to discover updates |
| Status item / first window / about: quiet badge or one line when behind | Modal every launch |
| After app update, offer/repair CLI via existing `install-cli` if app bundles CLI | Silently fight a standalone cold-start binary (law 6: last writer wins; show versions) |
| Use dogfood base URL override consistent with CLI | Hardcode a different CDN for “app updates only” |

Sparkle remains an **implementation** for downloading the DMG/app zip — not the
product SSOT for “is there a release?” Product SSOT is `latest.json`.

### Publish recipe (release day)

One intentional step (script or CI job “release”):

1. Build + sign CLI (+ app if shipping).
2. Upload static assets + `.sha256`.
3. Write/upload `latest.json` (and generate Sparkle appcast from it if used).
4. Do **not** bump `latest.json` on ordinary merges.

---

## Bootstrap (OPC-S02)

Add hosts `hermes` | `openclaw`.  
`pasteTarget`: honest "host system prompt / tools instructions (print-only)" —
do not invent a file path we have not verified.

- Shared `snippet()` stays `TeachingSnippet` SSOT (keep host-invariant body).
- Short host **preamble** in `render()` (subscription CLIs over API keys; start
  with `alln menu --json`; authorize before spend/mutate). Optional JSON field
  `preamble` if agents need it.
- Remove/gate checkout `rebuild_cli.sh` from cold on-PATH snippet.
- Size: keep hermes render compact (aim ≲ existing snippet budgets + few preamble
  lines; no second manifesto).
- Negative tests: no MCP, no API key strings; no filesystem writes.

Files: `Bootstrap.swift`, `AllnighterCLI.runBootstrap`,
`ContractRegistry+Milestone1` host flag, `HelpTopicRegistry`, `BootstrapTests`.

---

## Teaching (OPC-S03)

- Cold start / install topic: the one-liner.
- Search: install, curl, hermes, openclaw, get alln, no alln, PATH, update, upgrade.
- Delete help lie: "no alln → alln install-cli" as sole recovery.
- README agent section: one-liner for cold; `install-cli` for repair; updates via
  menu `update` + same one-liner.
- One constant for the one-liner string (Core or script+help test that greps both).

Doctor (when binary exists): never API keys; PATH repair = absolute path +
`install-cli`. Doctor does not install a missing binary; may report
`update.available` when cache says so.

---

## Slices

| Slice | Goal | Done when |
| --- | --- | --- |
| **OPC-S02** | hermes/openclaw + C3 snippet fix | Contract, tests, no checkout poison |
| **OPC-S03** | Help/README recovery = one-liner | Search hits; no install-cli chicken-egg |
| **OPC-S00** | Asset names + dogfood publish recipe | Static paths locked; private or local URL works |
| **OPC-S01** | `scripts/get-alln.sh` + fixture proof | Laws 1–2 green on cold Mac / temp HOME |
| **OPC-S06** | Shared release channel: `latest.json` + CLI `menu.update` + Mac reads same feed | Agents see update without opening app; app not a second SSOT; cache/fail-open; no auto-apply |
| **OPC-S05** | Public cutover | BQ-1/2 real: signed assets + `latest.json` on get.allnighter.app |
| **OPC-S04** | npm (optional) | Only if founder reopens BQ-3 |

Order: **S02 → S03 → S00 → S01 → S06 → S05**.  
S02/S03 need no network. S06 can dogfood against a fixture `latest.json` before
public DNS. S05 is the public flip for install **and** update channel together.

### OPC-S06 checklist

- [ ] `latest.json` schema + fixture tests (parse, compare, omit when current)
- [ ] Cached fetch (TTL ~24h); injectable URL for tests; fail open
- [ ] `MenuJSON` / menu projection field `update` (CLI inject, Core types)
- [ ] `version --json` carries same truth (or points at menu field — one owner)
- [ ] Optional `alln update --check` (print); apply = re-run install script
- [ ] Help + bootstrap: authorize before upgrade command
- [ ] Mac: About/status (or existing update entry) reads same base URL +
      `appVersion`; no parallel “latest” constant in app-only code
- [ ] Publish recipe documents writing manifest + assets in one step
- [ ] Negative: no GH API; no auto binary replace; check failure does not fail `run`

---

## Inference bans

| Bad inference | Ban |
| --- | --- |
| Script edits Hermes/Claude/shell rc | Print only |
| Cold start → MCP | Deny-list stays green |
| Paste → API keys | String tests |
| No alln → `alln install-cli` alone | One-liner first |
| Script owns a second teaching body | Call `alln bootstrap` |
| Public curl of unsigned arm64 | BQ-2 / S05 |
| Version via GitHub API | Static URLs only |
| “Behind” because git is busy | Only `latest.json` / published version |
| Auto-upgrade under a live agent | Announce + authorized command only |
| Mac Sparkle is the only update truth | Channel SSOT is `latest.json`; Sparkle is transport |
| Update check requires `alln serve` | CLI check is self-contained |

---

## Works Tests

### Cold start (S01)

```text
Setup: Mac, subscription CLI ready, alln not available.
Gesture: curl one-liner (or script + ALLN_INSTALL_BASE_URL fixture).
Assert:
  1. Absolute "$BIN" version exits 0
  2. Installer stdout includes bootstrap paste (menu --json / teaching markers)
  3. No MCP, no API-key advice
  4. No host config files modified
  5. which alln only if link dir was on PATH (or after printed export)
```

### Update channel (S06)

```text
Setup: alln on PATH at version A; fixture latest.json reports version B > A.
Gesture: alln menu --json (after cache miss or forced refresh in test).
Assert:
  1. update.available == true, latest == B, command == canonical one-liner
  2. Offline / bad URL: menu still succeeds; no false available
  3. After script upgrade to B: update absent or available false
  4. Mac app (or unit seam) given same latest.json reports the same appVersion story
  5. No auto binary replace without explicit update/apply path
```

---

## Done when

- One claim true on a cold Mac via one paste (dogfood OK for founder).
- Public hostname only after Developer ID + SHA256 assets.
- S02–S03 teaching honest; S01 script reliable under laws 1–2.
- S06: agents and CLI-only humans learn about **releases** via menu; Mac app
  uses the **same** channel (not a second product).
- Packet promoted and archived.
