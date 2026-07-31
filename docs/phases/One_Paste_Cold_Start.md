# One-Paste Cold Start

Status: **OPEN — founder priority (distribution wedge)** · implementation-ready  
Owner: install script + release binary + `Bootstrap` / help  
Created: 2026-07-31  
Updated: 2026-07-31 (final — first-principles pass: PATH truth, pipe safety,
signing floor, static URLs; cut bloat)  
Origin: Hermes / OpenClaw users with **no `alln`** need one paste so agents run
on **subscription CLIs**, not API keys.

Ephemeral packet. Closeout: promote install/teaching law into code +
`docs/operations/` / help; archive this file.

Related (reuse): `InstallCLI.swift` (PATH symlink only), `Bootstrap.swift` +
`TeachingSnippet.swift`, `scripts/rebuild_cli.sh`, open QABC (capacity in menu —
not a blocker), archived MCP retirement (**MCP stays dead**), deferred P05-S06
app DMG (separate High-Risk track).

---

## The one claim

```text
Paste one command. Your agent runs on the subscriptions you already pay for.
```

```bash
curl -fsSL https://get.allnighter.app | sh
```

One public string. Help, README, marketing, and the script default all cite it.
No cousins.

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
agent runners). `get.allnighter.app` (or override base) serves **direct** paths,
e.g.:

```text
https://get.allnighter.app/alln-macos-arm64
https://get.allnighter.app/alln-macos-arm64.sha256
https://get.allnighter.app/alln-macos-x86_64
https://get.allnighter.app/alln-macos-x86_64.sha256
```

Edge redirect / object store / Worker — implementer's choice. Contract: fixed
paths, no API, pin optional via `ALLN_VERSION` only if we also publish
versioned URLs later. V1 may make those paths mean "latest".

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

---

## Founder intake (short)

```text
Intent: one paste for Hermes/OpenClaw → alln on the machine → host paste →
  menu/run on subscription CLIs, not API keys.
Value: kill chicken-and-egg (install-cli + bootstrap require alln today).
Non-goals: MCP; npm in V1; fake $ savings; auto-edit host or shell configs;
  Linux; app DMG as the agent path; GH API version resolution.
```

### Live bugs this packet fixes

| Lie / gap today | Fix |
| --- | --- |
| Help: no alln → run `alln install-cli` | Cold recovery = one-liner; `install-cli` is PATH **repair** only |
| `Bootstrap.Host` has no hermes/openclaw | Add them (S02) |
| Snippet always teaches checkout `rebuild_cli.sh` | Drop/gate for release installs (poison when no checkout) |
| No fetch faucet | `scripts/get-alln.sh` + published binary |
| Doctor cannot run without alln | Pre-install recovery is the one-liner in docs/help text |

---

## Blocking questions

| ID | Decision (packet default) | Blocks |
| --- | --- | --- |
| **BQ-1** | Canonical URL: `https://get.allnighter.app` (static assets; no GH API) | Public cutover only |
| **BQ-2** | Public = Developer ID signed + SHA256. Dogfood free without public DNS. Notarize before big launch. | Public cutover only |
| **BQ-3** | **Defer npm/npx** | Nothing in V1 |

### Decision log

| Date | ID | Decision |
| --- | --- | --- |
| 2026-07-31 | BQ-1 | Provisional lock: `get.allnighter.app` + static paths (founder can rename before public) |
| 2026-07-31 | BQ-2 | Public floor = Developer ID + SHA256; dogfood unsigned/private OK |
| 2026-07-31 | BQ-3 | Defer npm |

---

## Two faucets, one price

| Who | How |
| --- | --- |
| Terminal agents | curl one-liner → CLI + paste block |
| Humans | Mac app (existing / DMG later) + `install-cli` / Teach your CLIs |

Same product. App not required for Hermes. npm later only.

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

---

## Bootstrap (S02)

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

## Teaching (S03)

- Cold start / install topic: the one-liner.
- Search: install, curl, hermes, openclaw, get alln, no alln, PATH.
- Delete help lie: "no alln → alln install-cli" as sole recovery.
- README agent section: one-liner for cold; `install-cli` for repair.
- One constant for the one-liner string (Core or script+help test that greps both).

Doctor (when binary exists): never API keys; PATH repair = absolute path +
`install-cli`. Doctor does not install a missing binary.

---

## Slices

| Slice | Goal | Done when |
| --- | --- | --- |
| **OPC-S02** | hermes/openclaw + C3 snippet fix | Contract, tests, no checkout poison |
| **OPC-S03** | Help/README recovery = one-liner | Search hits; no install-cli chicken-egg |
| **OPC-S00** | Asset names + dogfood publish recipe | Static paths locked; private or local URL works |
| **OPC-S01** | `scripts/get-alln.sh` + fixture proof | Laws 1–2 green on cold Mac / temp HOME |
| **OPC-S05** | Public cutover | BQ-1/2 real: signed assets on get.allnighter.app |
| **OPC-S04** | npm (optional) | Only if founder reopens BQ-3 |

Order: **S02 → S03 → S00 → S01 → S05**. S02/S03 need no network.

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

---

## Works Test

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

---

## Done when

- One claim true on a cold Mac via one paste (dogfood OK for founder).
- Public hostname only after Developer ID + SHA256 assets.
- S02–S03 teaching honest; S01 script reliable under laws 1–2.
- Packet promoted and archived.
