# One-Paste Cold Start (+ shared release channel)

Status: **OPEN — S02/S03/S00/S01/S06(core) shipped 2026-07-31; S05 (public
cutover) blocked on founder DNS + Apple Developer ID access; Mac update UI
(part of S06) not started**  
Owner: install script + release manifest + CLI projection + Mac update UI  
Created: 2026-07-31  
Updated: 2026-07-31 (hardening pass: publish race, injection, self-overwrite,
in-flight upgrade, semver compare; trial/entitlement seams reserved)  
Updated: 2026-07-31 (delivery pass — PM: Fable 5, dev: Grok 4.5 via `alln
loop`) — S02/S03/S00/S01/S06(core) code-complete and independently verified,
commits `11af7bcc` `5feeb78c` `3699d2fb` `e9e45fbf` `bba67abe` `b9a43085`;
see the Slices table below for exact per-slice state.  
Origin: Hermes / OpenClaw users with **no `alln`** need one paste so agents run
on **subscription CLIs**, not API keys. Follow-on: once installed, **CLI-only
users and agents never open the Mac app** — they still need to learn when a
**release** is available (not every git commit).

Ephemeral packet. Closeout: promote install/teaching/update law into code +
`docs/operations/` / help; archive this file.

Related (reuse): `InstallCLI.swift` (PATH symlink only), `Bootstrap.swift` +
`TeachingSnippet.swift`, `MenuJSON.capacity` (the precedent for an optional
cached projection field), `ServeDaemonProbe` (binaryVersion already on the wire),
`scripts/rebuild_cli.sh`, archived MCP retirement (**MCP stays dead**), deferred
P05-S06 app DMG (this packet owns the **shared release channel** the DMG/Sparkle
path must use when it ships — not a second update product).

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
2. **Symlink** — never copy — onto the **first** of:
   - a directory already on `$PATH` that is writable without sudo
   - `/usr/local/bin` if writable (often on PATH; same preference as
     `InstallCLI.defaultInstallDirectory`)
   - else `~/.local/bin` (create if needed)
   A copy goes stale on the next upgrade; a symlink to the stable home means
   upgrades need no re-link.
3. Prove install with **absolute** path: `"$BIN" version` must exit 0.
4. If the link dir is not on `$PATH`, **print** the one export line — do **not**
   auto-edit `~/.zshrc` / `~/.bash_profile`. Silent shell-rc edits surprise
   agents and break the print-never-edit consent posture.
5. Installer stdout and bootstrap always include the **absolute binary fallback**
   (Bootstrap already does this). Hosts that never reload PATH still work.
6. After linking, resolve `command -v alln`. If it resolves to something that is
   **not** our link, print the conflict (both paths + both versions). Silence
   here is what creates the "update available forever" trap (law 6, BUG-6).

Works Test primary assert: absolute `version` green + paste block printed.
`which alln` is optional and only expected when the link dir was already on PATH
or the user exported it.

### 2. Never half-run; never half-install

- **Outer pipe:** script body is `main() { … }; main "$@"` so a truncated
  `curl | sh` does not execute half a script.
- **Every child gets `</dev/null`.** Under `curl … | sh`, the shell's stdin *is
  the script*. Any subprocess that reads stdin eats the rest of the script.
  `"$BIN" version </dev/null`, `"$BIN" bootstrap … </dev/null`, `curl … </dev/null`.
  This is the single most likely cold-start bug and it is invisible in a
  `sh ./get-alln.sh` test — the fixture test must run through a **pipe**.
- **POSIX `/bin/sh` only.** No `[[`, no arrays, no `pipefail`, no `local`
  assumptions. Check exit codes explicitly; `set -eu` plus explicit checks.
- **Binary fetch:** manifest → download to temp → verify **SHA256** → atomic
  install → only then print success. Fail closed; never exit 0 on partial state.
- **Atomic install:** write `~/.local/share/allnighter/bin/.alln.tmp.$$` on the
  **same filesystem**, then `mv` (rename) over `alln`. Never write in place: a
  running `alln serve` / loop / detached run holds that inode, and an in-place
  write is either `ETXTBSY` or a corrupted running process (BUG-3). Rename from
  `$TMPDIR` can cross devices — stage in the destination directory.
- `trap` cleanup of the temp dir on EXIT/INT; `umask 022`.

### 3. Public binary must run on Apple Silicon

arm64 Mach-O **must carry a valid signature to execute at all** (ad-hoc is the
floor). Unsigned or wrong-signed dies with `Code Signature Invalid`. Track:

| Track | Audience | Bar |
| --- | --- | --- |
| **Dogfood** | Founder / trusted | Local build or private URL; ad-hoc sign OK; SHA256 still required for any network fetch |
| **Public** | Strangers | **Developer ID Application** sign (hardened runtime). SHA256 in manifest. Notarization before a loud launch — not required to start dogfood |

`curl` does not set `com.apple.quarantine`, so the Gatekeeper *prompt* is not the
failure mode here — the signature check is. Do not cargo-cult `xattr -d` into the
script. Instead: if `"$BIN" version` fails, print the raw error plus the one
remedy line, and exit non-zero (law 2).

High-Risk Stop (`AGENTS.md`): do not flip the public hostname to strangers until
signing (BQ-2) is real.

### 4. Manifest first; immutable asset paths; no GitHub API

Do not resolve version via `api.github.com` (shared 60 req/hr rate limits kill
agent runners). And do not fetch `binary` and `binary.sha256` as two independent
mutable objects — a publish between the two requests yields a valid binary that
fails a stale checksum, or worse (BUG-1).

**One mutable object, everything else immutable:**

```text
https://get.allnighter.app/latest.json                    # ONLY mutable object; edge TTL <= 60s
https://get.allnighter.app/v0.12.0/alln-macos-universal   # immutable, never rewritten; long TTL
https://get.allnighter.app/v0.12.0/Allnighter.dmg         # immutable
```

`latest.json` names the exact versioned URL **and** its sha256, so binary and
checksum can never disagree. Republishing a version = new version number, never
an overwrite. Edge redirect / object store / Worker — implementer's choice.

**One asset, not an arch matrix.** Ship a **universal** binary
(`swift build --arch arm64 --arch x86_64`, or `lipo -create`). This deletes the
arch-detection branch, halves the release matrix, and removes the entire
"downloaded the wrong slice" bug class. (BQ-5.)

### 5. One teaching body; script never writes host configs

Installer ends by running the installed binary:

```bash
"$BIN" bootstrap --host hermes </dev/null   # or openclaw via ALLN_BOOTSTRAP_HOST
```

That print is SSOT (`TeachingSnippet` + host preamble). Script does not
hand-maintain a second manifesto. Script never writes Hermes / Claude / Cursor
files — print only (same as bootstrap).

### 6. One product on PATH — last writer wins, and say so

Cold-start places a **standalone** binary. App `install-cli` still symlinks the
*running* binary. Do not build upgrade-negotiation in V1.

Rule: whatever last ran `install-cli` (or the cold script's link step) owns the
PATH name `alln`. Both the script (law 1.6) and `doctor` must **print the
conflict** when the resolved `alln` is not the standalone home. Otherwise the
user upgrades the standalone binary forever while PATH keeps resolving to an
older app-bundled one, and `update.available` never clears (BUG-6).

`version --json` already carries `binaryPath` — the update projection reuses it.

### 7. Subscriptions only; MCP dead

Paste, help, doctor: never model-vendor API keys / BYOK; never `mcp add` / MCP
install. (An Allnighter **account** for entitlement is not a model API key — see
§Trial. It is still never required to install, bootstrap, or read the menu.)

### 8. Release ≠ commit; one channel for CLI and Mac app

40 commits/day is noise. An **update** exists only when we **publish** a release
and bump the channel manifest. Agents and humans share **one** system:

| Rule | Detail |
| --- | --- |
| **SSOT** | `latest.json` on the install host (same base URL as cold start) |
| **Announce ≠ apply** | Surfaces say "update available + command"; never silent binary swap mid-session |
| **Upgrade path** | CLI: same one-liner as cold start. Mac app: install the published app build for that release (Sparkle or manual) — versions align with the **same** manifest |
| **Where agents look** | Piggyback `alln menu --json` (already taught as session start). Secondary: `version --json`, `doctor` |
| **Where humans look** | Same menu field if they use CLI; Mac app update UI reads the **same** channel — not a private Sparkle-only truth |
| **Network tax** | Cache check (~24h). Fail open (no field). Never block `run` on check failure |
| **Not every commit** | CI does not flip `latest.json` on merge; only on an explicit release publish |

If the Mac app and CLI disagree on "what's latest," the channel is wrong — fix the
manifest, don't add a second feed.

### 9. The network is data, never an instruction to an agent

`latest.json` is fetched over the wire and then read by an LLM that can execute
shell. Anything free-text in it is a **prompt-injection / RCE path** the moment
an agent is told "run `update.command`" (BUG-4).

- `update.command` is the **compiled-in constant** (`ReleaseChannel.installCommand`).
  The manifest's `installCommand` is *never* projected — it exists only so a human
  reading the file sees the canonical string. Mismatch → ignore it silently.
- **No free text reaches the agent.** `notes` is not projected into
  `menu --json` / `version --json` in V1. Humans can see it in the Mac app
  (rendered as plain text, never as a command).
- Version strings are parsed as semver and re-emitted from parsed components —
  a raw remote string is never echoed into a field an agent may paste.

### 10. The update check never blocks and never runs in a hot path

- Checked only in `menu`, `version --json`, `doctor`, and explicit
  `alln update --check`. **Never** in `run`, `loop`, or any dispatch path.
- Read cache first. Fetch only when the cache is older than TTL (24h), with a
  hard **2s** timeout, at most once per TTL, fail-open (omit the field).
- On failure, stamp `nextAttemptAt = now + 1h` so an offline host does not pay
  the timeout on every call.
- Cache writes are temp+rename (concurrent `alln` invocations are normal; a torn
  JSON cache must never be possible — BUG-2). A cache that fails to parse is a
  miss, never an error.
- Clock defence: if `fetchedAt` is more than 5 minutes in the future, treat the
  cache as stale (BUG-5).
- `ALLN_NO_UPDATE_CHECK=1` disables the check entirely (CI, air-gapped).

### 11. Upgrading must be safe while work is in flight

Upgrade is a file swap under a live machine. Two real hazards:

- **Running processes.** Solved by atomic rename (law 2). A running
  `alln serve` / loop keeps its old inode and does not crash.
- **Durable state format cutovers.** These are not theoretical: 0.11.0 (LVC-S05)
  deliberately made old `LoopState` undecodable — "finish or `stop` every
  in-flight loop before upgrading." An agent that blind-runs the one-liner mid-loop
  bricks that loop (BUG-7).

Therefore the install script, **after** a successful install:

1. Reads `alln loop list` / `alln ps` (new binary, `</dev/null`) and prints a
   plain warning if anything is in flight.
2. Prints the `alln serve` restart line if a serve daemon is running an older
   `binaryVersion` (`ServeDaemonProbe` already records it).

It does **not** kill anything, and it does not refuse to install. Announce, don't
mutate. The teaching line in bootstrap says: upgrade between rounds, not during.

### 12. Entitlement never blocks discovery

Install, `bootstrap`, `menu`, `help`, `version`, `doctor`, `ps`, `artifact`,
`kill` work forever, paid or not. Only **dispatch** is metered. An expired user
must still be able to read their data and learn exactly how to pay — from the
CLI, offline, with no account.

---

## Founder intake (short)

```text
Intent:
  1) one paste for Hermes/OpenClaw → alln on the machine → host paste →
     menu/run on subscription CLIs, not API keys.
  2) after install, agents + CLI-only humans learn about *releases* without
     opening the Mac app; Mac app uses the same release truth.
  3) free to install, free to try for a bounded window, and deleting +
     reinstalling must not reset that window.

Value: kill chicken-and-egg; stop rotting on week-old bins while shipping daily;
  make the trial honest without a DRM arms race.
Non-goals: MCP; npm in V1; fake $ savings; auto-edit host/shell configs;
  Linux; auto-apply upgrades; commit-SHA "you're behind"; GH API; app-only
  Sparkle as sole update channel; forcing alln serve for update checks;
  anti-VM / anti-tamper hardening; gating discovery commands.
```

### Live bugs this packet fixes

| Lie / gap today | Fix |
| --- | --- |
| Help: no alln → run `alln install-cli` | Cold recovery = one-liner; `install-cli` is PATH **repair** only |
| `Bootstrap.Host` has no hermes/openclaw (`claude, cursor, codex, generic`) | Add them (S02) |
| Snippet always teaches checkout `rebuild_cli.sh` | Drop/gate for release installs (poison when no checkout) |
| No fetch faucet | `scripts/get-alln.sh` + published binary |
| Doctor cannot run without alln | Pre-install recovery is the one-liner in docs/help text |
| Updates only visible if you open the Mac app | Shared `latest.json` + menu/`update` field (S06); app UI same channel |
| Humans/agents don't know to "check for updates" | Piggyback the command they already run (`menu --json`) |

### Bugs found in the hardening pass (must be designed for, not discovered)

| ID | Bug | Fix (law) |
| --- | --- | --- |
| **BUG-0** | `curl \| sh` + a child that reads stdin eats the rest of the script; passes when tested as a file, fails as a pipe | `</dev/null` on every child; fixture test runs through a real pipe (L2) |
| **BUG-1** | Binary and `.sha256` fetched as two mutable objects → publish race gives a real binary with a stale hash → install "fails" or a mismatched pair installs | Manifest-first + immutable versioned paths (L4) |
| **BUG-2** | Two concurrent `alln` invocations write the update cache → torn JSON → every later call errors or re-fetches | temp+rename write; unparseable = miss (L10) |
| **BUG-3** | Upgrade writes over the binary a running `serve`/loop is executing → `ETXTBSY` or corrupted process | stage in dest dir + rename (L2) |
| **BUG-4** | `installCommand` / `notes` come from the network and land in `menu --json`, where an agent is instructed to execute them | Compiled-in command only; no remote free text projected (L9) |
| **BUG-5** | String compare says `0.9.0 > 0.10.0`; clock skew freezes the TTL cache forever; a rolled-back release announces a downgrade | Numeric semver compare, announce only on strict `latest > current`, future-`fetchedAt` = stale (L10) |
| **BUG-6** | Standalone binary upgrades but PATH resolves to the app-bundled `alln` → `update.available` never clears; user "updates" daily forever | Print the resolved-path conflict in script + `doctor`; carry `binaryPath` in the projection (L1.6, L6) |
| **BUG-7** | Blind one-liner upgrade mid-loop across a state-format cutover (0.11.0 LVC-S05) makes in-flight `LoopState` undecodable | Post-install in-flight warning + serve-restart line; teach "upgrade between rounds" (L11) |
| **BUG-8** | Adding `MenuJSON.update` changes `contractHash` — schemas, contract lock, and the menu verifier drift and CI reds late | S06 ships `menu.schema.json` + `menu-show.schema.json` + `contract.lock.json` + `scripts/verify_menu_contract.py` + additive `contractVersion` minor bump + `binaryVersion` +0.0.1 in the same slice (precedent: QABC-S00e `capacity`) |
| **BUG-9** | Entitlement stored in Keychain → the documented Codex/host sandbox Keychain block makes paid users look unpaid | Entitlement token is a `0600` file under Application Support. **Never Keychain** (L12, §Trial) |
| **BUG-10** | Trial clock kept locally → `rm -rf ~/Library/Application Support/Allnighter` resets it; or the user sets the clock back | Server-side ledger keyed on machine hash; token carries server `issuedAt`/`expiresAt`; local clock < `issuedAt` = tamper → force refresh (§Trial) |

---

## Blocking questions

| ID | Decision (packet default) | Blocks |
| --- | --- | --- |
| **BQ-1** | Canonical URL: `https://get.allnighter.app` (static assets; no GH API) | Public cutover only |
| **BQ-2** | Public = Developer ID signed + SHA256. Dogfood free without public DNS. Notarize before big launch. | Public cutover only |
| **BQ-3** | **Defer npm/npx** | Nothing in V1 |
| **BQ-4** | Soft update only in V1 (announce + command). Hard `minSupportedBinaryVersion` fail closed = later packet if protocol breaks. | Not V1 |
| **BQ-5** | **One universal CLI binary**, no per-arch assets | S00/S01 asset naming |
| **BQ-6** | Trial = **14 calendar days** unlimited, machine-keyed, starts at first successful dispatch. Free tier after it = **3 full-capability dispatches/day**, never zero. Offer SSOT: `docs/marketing/Pricing_Recommendation.md` v3. | Trial packet only |
| **BQ-7** | Entitlement/payments **spin out** to a sibling packet; this packet only reserves the seams and ships S00–S06 without a gate | Nothing in this packet |

### Decision log

| Date | ID | Decision |
| --- | --- | --- |
| 2026-07-31 | BQ-1 | Provisional lock: `get.allnighter.app` + static paths (founder can rename before public) |
| 2026-07-31 | BQ-2 | Public floor = Developer ID + SHA256; dogfood unsigned/private OK |
| 2026-07-31 | BQ-3 | Defer npm |
| 2026-07-31 | BQ-4 | Soft announce only; no force-upgrade gate in this packet |
| 2026-07-31 | BQ-5 | Universal binary — one asset, one path, no arch branch |
| 2026-07-31 | BQ-6 | Active days beat calendar days (the clock must not run while the user isn't looking); a **daily** free allowance beats a lifetime run count — it resets, so "did that count?" is never a support ticket |
| 2026-07-31 | BQ-7 | Cold start must ship before the gate exists; seams reserved so it is not a rewrite |

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
  1. Darwin only; else exit 1.  POSIX sh; set -eu; umask 022; trap cleanup
  2. BASE=${ALLN_INSTALL_BASE_URL:-https://get.allnighter.app}
  3. curl -fsSL "$BASE/latest.json" </dev/null    → cliVersion, cli.url, cli.sha256
  4. curl -fsSL "$CLI_URL" </dev/null → temp; shasum -a 256 must equal cli.sha256
     (fail closed, print both hashes)
  5. install atomically: HOME_BIN=~/.local/share/allnighter/bin
     write "$HOME_BIN/.alln.tmp.$$" (same fs), chmod 755, mv → "$HOME_BIN/alln"
  6. symlink into PATH dir per law 1; print export line if needed
  7. "$BIN" version </dev/null                    # absolute — required success
  8. resolved=$(command -v alln || true); warn if resolved != our link (BUG-6)
  9. warn on in-flight loops / older running serve (law 11)
 10. "$BIN" bootstrap --host ${ALLN_BOOTSTRAP_HOST:-hermes} </dev/null
 11. exit 0 only if 7 succeeded
}
main "$@"
```

Env: `ALLN_INSTALL_BASE_URL` (dogfood/fixture), `ALLN_BOOTSTRAP_HOST`,
`ALLN_INSTALL_DIR` (optional force link dir).  
Writes only under `~/.local/share/allnighter/`, chosen link dir, temp.  
No Keychain, no telemetry, no host config edits, no shell-rc edits, no `sudo`.

**CI proof:** fixture manifest + binary served from a temp dir, `ALLN_INSTALL_BASE_URL`
+ temp HOME. Asserts: checksum mismatch → non-zero and **no** file at the install
path; host config mtime unchanged; **script executed through a pipe** (`cat
get-alln.sh | sh`) still reaches step 10 (BUG-0 regression gate).

**Also the upgrade tool:** re-running this script *is* CLI upgrade. `alln update`
(S06) prints the same one-liner; it is not a second downloader.

---

## Release channel contract (`latest.json`) — OPC-S06

Published only on **release**, not on every merge. The only mutable object.

```json
{
  "schemaVersion": 1,
  "cliVersion": "0.12.0",
  "appVersion": "0.12.0",
  "releasedAt": "2026-07-31T00:00:00Z",
  "notes": "human-only; never projected to agents",
  "installCommand": "curl -fsSL https://get.allnighter.app | sh",
  "cli": {
    "url": "https://get.allnighter.app/v0.12.0/alln-macos-universal",
    "sha256": "…"
  },
  "app": {
    "url": "https://get.allnighter.app/v0.12.0/Allnighter.dmg",
    "sha256": "…"
  }
}
```

Rules:

- Versioned asset paths are **immutable**. A bad build ships as `0.12.1`, never as
  a rewrite of `0.12.0`.
- `cliVersion` / `appVersion` may match (preferred) or diverge only when a release
  truly ships one surface — still **one file**, not two private channels.
- `installCommand` must equal the canonical one-liner string, and is
  informational only (law 9).
- Unknown fields are ignored by readers; `schemaVersion` > known → treat as "no
  update information" and fail open (never guess).
- Dogfood: same shape at a private base URL; CLI/app honor `ALLN_INSTALL_BASE_URL`
  / Settings override for checks.
- Sparkle (when wired): appcast **generated by the same publish step**, not a
  hand-maintained parallel "latest" that can drift.

### CLI projection (agent-native)

Cache: `~/Library/Application Support/Allnighter/Release/latest-check.json`
(`AllnighterPaths.release`), TTL 24h, temp+rename write, fail-open (law 10).  
Inject into **`alln menu --json`** (primary — agents already open it):

```json
"update": {
  "available": true,
  "current": "0.11.1",
  "latest": "0.12.0",
  "binaryPath": "/Users/me/.local/share/allnighter/bin/alln",
  "command": "curl -fsSL https://get.allnighter.app | sh"
}
```

- Optional field, exactly like `MenuJSON.capacity`. When current ≥ latest, or the
  check failed/skipped/was disabled: **omit** `update` entirely (keep the happy
  path quiet — no `"available": false` noise).
- `command` is compiled-in. No `notes`. No remote strings (law 9).
- `binaryPath` present so an agent can see a BUG-6 PATH conflict without a second
  command.
- Same truth on `alln version --json` and as a `doctor` check — **one owner**
  (`ReleaseChannel`), three projections.
- Humans on a TTY get one stderr line per TTL from `menu`/`doctor`. Never on
  stdout, never during `run`.
- `alln update` / `alln update --check`: prints current, latest, and the
  one-liner. It does **not** download or exec in V1 (BQ-4). Applying is the
  human/agent running the one-liner.

**Teaching:** one reflex line (bootstrap/help): if `update.available`, tell the
user and run `update.command` only when they authorize it — and prefer **between
rounds**, not mid-loop (law 11).

### Mac app projection (same channel)

Today: update UX is app-centric and easy to miss if the app is closed for a week.
Improve under **the same laws**:

| Do | Don't |
| --- | --- |
| Read `latest.json` (or a Sparkle feed generated by the same publish) | Own a second "latest version" only in app prefs code |
| Compare `appVersion` to running app; show notes as **plain text** + install path | Require a buried Settings page to discover updates |
| Status item / first window / about: quiet badge or one line when behind | Modal every launch |
| After app update, offer/repair CLI via existing `install-cli`, and show which binary PATH resolves to | Silently fight a standalone cold-start binary (law 6) |
| Use the same base URL override as the CLI | Hardcode a different CDN for "app updates only" |

Sparkle remains an **implementation** for downloading the DMG — not the product
SSOT for "is there a release?" Product SSOT is `latest.json`.

### Publish recipe (release day)

One intentional step (script or CI job "release"):

1. Build universal + sign CLI (+ app if shipping); compute sha256.
2. Upload to **versioned, immutable** paths.
3. Write/upload `latest.json` last (and generate the Sparkle appcast from it).
4. Do **not** bump `latest.json` on ordinary merges.
5. Purge/short-TTL only `latest.json` at the edge; assets are immutable.

Ordering matters: assets before manifest, so the manifest never points at a 404.

---

## Bootstrap (OPC-S02)

Add hosts `hermes` | `openclaw` to `Bootstrap.Host` (today: `claude, cursor,
codex, generic`).  
`pasteTarget`: honest "host system prompt / tools instructions (print-only)" —
do not invent a file path we have not verified.

- Shared `snippet()` stays `TeachingSnippet` SSOT (keep host-invariant body).
- Short host **preamble** in `render()` (subscription CLIs over API keys; start
  with `alln menu --json`; authorize before spend/mutate; upgrade between rounds).
- Remove/gate checkout `rebuild_cli.sh` from the cold on-PATH snippet.
- Size: keep hermes render compact; no second manifesto.
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
- One constant for the one-liner string (`ReleaseChannel.installCommand`) with a
  test that greps script + help + README against it.

Doctor (when binary exists): never API keys; PATH repair = absolute path +
`install-cli`; reports the BUG-6 conflict and `update.available` from cache.
Doctor does not install a missing binary.

---

## Trial & payments (seams reserved here; **sibling packet owns the build**)

Founder ask: free to install, free to try for X days, and `rm -rf` + reinstall
must not mint a fresh trial. Design below is the answer; per BQ-7 it ships as
`docs/phases/Trial_And_Entitlement.md`, **not** inside the cold-start train.
Recorded here because two seams must exist from day one or S01/S06 get rewritten.

**Anchor (same as the Mac app).** Sign in with Apple → Supabase
(`RemoteAccountModel.signInWithApple`, `trusted_devices`, `mac_agents` already
exist). One entitlement service for CLI, Mac, and iOS. Not a second product.

**The abuse fix is that the clock is not local.** A server ledger row is keyed on
a **machine hash** — an HMAC (static compiled-in salt) over stable IOKit hardware
identity; the raw UUID never leaves the machine and is never stored. First
successful dispatch writes `trial_started_at` for that machine hash. Reinstall
finds the same row. A fresh Apple ID on the same machine finds the same row. The
server always keeps the **earliest** start it has ever seen for a key.

- Trial = **14 calendar days** unlimited, no account required (preserves
  one-paste magic; BQ-6). The ledger row holds **one timestamp** — `trial_started_at`.
  The end date is derived, fixed, and something the user can verify.
- **Free tier is not zero.** After the trial: **3 dispatches per day, at full
  capability** — a dispatch is the unit whether it seats one worker or six, so a
  single-seat run to any CLI counts as one — no feature flags, no seat cap, no single-worker lane. The only
  free-tier state is a day-keyed counter (`YYYY-MM-DD` + count), reset by date
  change, reconciled server-side on the same 24h check. A failed dispatch that
  never spawned a worker does not count — and the daily reset means a wrong call
  costs a wait, never a support ticket.
- Sign in with Apple is required only to **pay** and to sync entitlement across
  machines / iOS.
- Offline at first dispatch: grant a provisional local start, reconcile on next
  contact (server always keeps the earlier timestamp).
  Unactivated + never able to reach the server = **72h** grace, then fall back to
  the free daily allowance — **never to zero** (§Degrade, never brick).
- Residual risk accepted: VM / hardware spoofing. **No anti-VM, no
  anti-tamper, no obfuscation** — a $10/mo prosumer tool does not win a DRM arms
  race, and every hardening step costs support incidents from honest users.

**Token, not a phone-home per run.** Activation/refresh returns a short-lived
signed entitlement token (Ed25519; public key compiled in) carrying account (if
any), machine hash, plan, `issuedAt`, `expiresAt` (7d). Stored `0600` at
`~/Library/Application Support/Allnighter/Entitlement/token.json` — **never
Keychain**, because the documented host-sandbox Keychain block would make paid
users look unpaid (BUG-9). Local clock earlier than `issuedAt` = rollback →
force refresh, and refuse to extend on local time alone (BUG-10). Refresh
piggybacks the same 24h check as the release channel — one network reflex, not two.

**What is metered:** dispatch only (`alln run`, `loop` start, any worker spawn) —
and only as a *count per day* on the free tier, never as a capability gate.
Everything else is free forever (law 12). An in-flight run is never killed by an
expiry or an allowance — admission is checked at dispatch, once. A multi-round
loop counts once, at start, not per round.

**Failure shape:** structured `ErrorEnvelope` with a real `nextAction` (the
checkout URL or `alln activate`), so an agent can tell its human exactly what to
do. Never a silent hang, never a generic error.

**Payments:** hosted Stripe Checkout link → webhook → Supabase entitlement row.
No in-app payment UI, no IAP (direct distribution, unsandboxed by design). Founder
is solo — the whole surface is one table, one webhook, one signed token.

**Seams to reserve now (cheap now, expensive later):**

1. `ReleaseChannel` fetch/cache/TTL/backoff is written generically enough that the
   entitlement refresh reuses it (one cached network reflex, one lock, one clock
   defence) — do not build a second cache later.
2. `MenuJSON` gains **one** optional projection field per concern. `entitlement`
   is reserved as a sibling of `update` so adding it later is another additive
   minor bump, not a reshuffle.
3. Dispatch already funnels through `RunService` — the admission check has exactly
   one call site. Do not scatter checks.

**High-Risk Stop:** hardware-derived identity + payment state is a privacy /
billing surface per `AGENTS.md`. The sibling packet discloses exactly what is
hashed and sent, in `doctor` and in the privacy line, before it ships.

---

## Slices

| Slice | Goal | Done when |
| --- | --- | --- |
| **OPC-S02** | hermes/openclaw + C3 snippet fix | **Shipped 2026-07-31 (`11af7bcc`).** Contract 7.3.0, tests, no checkout poison |
| **OPC-S03** | Help/README recovery = one-liner | **Shipped 2026-07-31 (`5feeb78c`).** Search hits; no install-cli chicken-egg; `ReleaseChannel.installCommand` grep-gated |
| **OPC-S00** | Universal build + versioned asset layout + publish recipe | **Shipped 2026-07-31 (`3699d2fb`).** `scripts/build-universal.sh` + `scripts/publish-release.sh`; immutable paths locked; local/dogfood URL proven — dual-arch SPM fails on this toolchain (BuildInfoPlugin), two `--arch` builds + `lipo -create` used instead |
| **OPC-S01** | `scripts/get-alln.sh` + fixture proof | **Shipped 2026-07-31 (`e9e45fbf`).** Laws 1–2 green on temp HOME **through a pipe**; BUG-0/1/3/6/7 gated; `scripts/test-get-alln.sh` proof |
| **OPC-S06** | Shared release channel: `latest.json` + `ReleaseChannel` + `menu.update` + `version --json` + doctor + Mac reads same feed | **Core/CLI shipped 2026-07-31 (`bba67abe`, `b9a43085`).** Contract 7.4.0, binary 0.11.3. Mac About/status projection **not done this round** (CLI/Core scope only) |
| **OPC-S05** | Public cutover | **Blocked on founder** — needs real DNS control (`get.allnighter.app`), an Apple Developer ID signing certificate, and notarization credentials; none of these can be provisioned by an agent |
| **OPC-S04** | npm (optional) | Only if founder reopens BQ-3 |

Order: **S02 → S03 → S00 → S01 → S06 → S05**.  
S02/S03 need no network. S06 can dogfood against a fixture `latest.json` before
public DNS. S05 is the public flip for install **and** update channel together
— it is the one slice this packet cannot finish without the founder at the
keyboard (DNS + Apple Developer account access).

### OPC-S06 checklist

- [x] `ReleaseManifest` decode + fixtures (unknown fields ignored; future
      `schemaVersion` → no update info)
- [x] `ReleaseVersion` numeric semver compare + tests (`0.9.0 < 0.10.0`;
      malformed → no announcement; never announce a downgrade)
- [x] Cached fetch: 24h TTL, 2s timeout, 1h failure backoff, atomic write,
      corrupt cache = miss, future `fetchedAt` = stale, `ALLN_NO_UPDATE_CHECK`
- [x] `MenuJSON.update` optional field + `menu.schema.json` +
      `contract.lock.json` + `contractVersion` additive minor (7.3.0 → 7.4.0) +
      `binaryVersion` +0.0.1 (0.11.2 → 0.11.3) (BUG-8, one commit `b9a43085`).
      Judgment call: `update` is a global fact, not per-model — not echoed onto
      `MenuShowJSON.ModelDetail`/`menu-show.schema.json` the way `capacity` is.
      `scripts/verify_menu_contract.py` not touched — not confirmed whether it
      needs updating for the new field.
- [x] `version --json` + `doctor` project the same `ReleaseChannel` truth
- [x] `alln update --check` prints; no download, no exec
- [x] Injection gate: remote `installCommand`/`notes` never appear in any JSON
      projection — structurally enforced (`ReleaseUpdateInfo` never takes the
      manifest's fields as init parameters) plus a hostile-fixture test;
      live-verified with a hand-crafted hostile manifest across all three
      projections + `update --check`
- [ ] Mac: About/status reads the same base URL + `appVersion`; no parallel
      "latest" constant in app-only code — **not done**, CLI/Core only this round
- [ ] Publish recipe documents assets-then-manifest ordering — `publish-release.sh`
      (OPC-S00) intentionally does not write `latest.json` yet; no publish
      script currently writes the manifest at all — **open**, needs a follow-up
      slice or founder decision on where that step lives
- [x] Negative: no GH API; no auto binary replace; check failure does not fail
      `run`; `run` performs no update network call at all — confirmed by
      grepping `RunService`/`RunCLI`/`LoopDispatch`/`LoopEngineCLI` for any
      `ReleaseChannel` reference (none)

---

## Inference bans

| Bad inference | Ban |
| --- | --- |
| Script edits Hermes/Claude/shell rc | Print only |
| Cold start → MCP | Deny-list stays green |
| Paste → model-vendor API keys | String tests |
| No alln → `alln install-cli` alone | One-liner first |
| Script owns a second teaching body | Call `alln bootstrap` |
| Public curl of unsigned arm64 | BQ-2 / S05 |
| Version via GitHub API | Static URLs only |
| "Behind" because git is busy | Only `latest.json` / published version |
| Auto-upgrade under a live agent | Announce + authorized command only |
| Mac Sparkle is the only update truth | Channel SSOT is `latest.json`; Sparkle is transport |
| Update check requires `alln serve` | CLI check is self-contained |
| Copy the binary onto PATH | Symlink to the stable home (law 1) |
| Overwrite a published version's asset | New version number, always |
| Echo a remote string an agent might run | Compiled-in constants only (law 9) |
| Update check inside `run` | Discovery commands only (law 10) |
| Trial clock in a local file / Keychain | Server ledger + `0600` token (BUG-9/10) |
| Gate `menu`/`doctor`/`help` on entitlement | Discovery is free forever (law 12) |
| Anti-VM / anti-tamper hardening | Explicit non-goal |

---

## Works Tests

### Cold start (S01)

```text
Setup: Mac, subscription CLI ready, alln not available. Fixture base URL.
Gesture: cat scripts/get-alln.sh | sh   (a PIPE, not a file — BUG-0)
Assert:
  1. Absolute "$BIN" version exits 0
  2. Installer stdout includes the bootstrap paste (menu --json / teaching markers)
  3. No MCP, no API-key advice
  4. No host config or shell-rc files modified
  5. which alln only if link dir was on PATH (or after printed export)
  6. Tampered sha256 → non-zero exit AND no binary at the install path
  7. Re-run while a fake long-lived process holds the old binary → succeeds,
     old process survives, new version reported (BUG-3)
  8. PATH resolves elsewhere → conflict printed with both paths (BUG-6)
```

### Update channel (S06)

```text
Setup: alln at version A; fixture latest.json reports B > A.
Gesture: alln menu --json (cache miss / forced refresh in test).
Assert:
  1. update.available == true, latest == B, command == compiled-in one-liner
  2. Hostile fixture (installCommand "rm -rf ~", notes with backticks) → those
     strings appear NOWHERE in any projection (BUG-4)
  3. Offline / bad URL / 500 / garbage body: menu still succeeds, field omitted,
     nextAttemptAt backoff set
  4. current 0.10.0 vs latest 0.9.0 → no announcement; 0.9.0 vs 0.10.0 → announced
  5. Corrupt cache file → treated as miss, menu succeeds
  6. After upgrade to B: field omitted
  7. alln run performs zero release-channel network calls
  8. Mac app seam given the same latest.json reports the same appVersion story
```

---

## Estimate

| Slice | Dev days (solo + agent seats) |
| --- | --- |
| S02 hosts + snippet | 0.5 |
| S03 help/README/one-liner constant | 0.5 |
| S00 universal build + asset layout + publish script | 1.0 |
| S01 `get-alln.sh` + pipe/fixture proof | 1.5 |
| S06 `ReleaseChannel` + menu/version/doctor + contract artifacts + Mac read | 2.0 |
| S05 public cutover (DNS, Developer ID, notarize) | 1.0 |
| **Total (this packet)** | **~6.5 dev days** |
| Sibling trial/entitlement packet (Supabase table, edge function, device flow, Stripe, CLI gate, Mac/iOS parity) | ~6 dev days |

**Importance: 9/10 — definitely do.** Two live problems, one packet: agents cannot
start at all without a paste (the wedge), and installed agents silently rot on
old binaries with no way to find out (the retention bug). Everything downstream —
public launch, the trial, the DMG — needs this channel to exist first.

Per-slice: S02/S03 **9** (cheap, fixes live lies). S00/S01 **9** (the wedge).
S06 **9** (the rot bug; also the only honest place to hang the entitlement
refresh). S05 **7** (gated on founder's public-launch timing). S04 npm **2**.
Sibling trial packet **6** — required before strangers, not before dogfood.

---

## Done when

- One claim true on a cold Mac via one paste (dogfood OK for founder).
- Public hostname only after Developer ID + SHA256 assets.
- S02–S03 teaching honest; S01 script reliable under laws 1–2 **through a pipe**.
- S06: agents and CLI-only humans learn about **releases** via menu; Mac app uses
  the **same** channel; no remote string can reach an agent as a command.
- BUG-0 … BUG-8 each have a named regression test.
- Trial seams reserved (one cached network reflex, one admission call site, one
  reserved menu field); the gate itself ships in its own packet.
- Packet promoted and archived.
