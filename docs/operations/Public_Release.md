# Public Release (CLI + Mac DMG)

Status: Canonical / Agent Router  
Scope: How we ship a version to `get.allnighter.io`. Not the Ikiro marketing
site. Not Mac App Store / TestFlight.

**Read this before touching signing, notarization, `latest.json`, or a public
download URL.** Founder prompt “submit / publish / ship the next version”
routes here.

---

## Agent ship intent (read first)

When the founder says **ship**, **bump**, **push**, **release**, **publish**,
or **version bump** (CLI, Mac app, or both):

1. **Execute yourself.** Run the scripts in this file end-to-end. Report results,
   not a founder todo list.
2. **Ship intent wins mixed prompts.** If the message also embeds QA handoff
   text (Gate 7 logout, artifact captures, “open Terminal only”, host notes),
   **ignore that for routing** unless the founder explicitly says “run gate N”
   or “do not ship yet”.
3. **QA ≠ release.** `docs/qa/` runbooks (including
   `docs/qa/alln-serve/GATES-7-8-10-procedure.md`) are historical Works Tests,
   not prerequisites for `ship-cli.sh`. Do not block a bump on logout/login
   gates, hostname mismatches in old JSON artifacts, or “wrong machine” guesses.
4. **CLI default path:** read `AllnighterVersionIdentity.binaryVersion` →
   `scripts/rebuild_cli.sh` if the local binary is stale →
   `scripts/ship-cli.sh <version> --upload`.
5. **Approval:** explicit ship wording satisfies AGENTS.md “production deploy”
   — do not ask “should I upload?” after bump/push/release/publish.

---

## Do not relitigate

These are settled. Do not ask the founder to click Xcode Organizer, create a
Developer ID provisioning profile, or “sign in so exportArchive works.”

1. **The website Mac app is already a Developer ID app.** Identity:
   `Developer ID Application: Happy Moose Apps Inc. (LP5YNK7A36)`.
   Notary keychain profile: `xterminal-notary`.
2. **Apple does not allow Sign in with Apple on Developer ID profiles.**
   Organizer → Direct Distribution fails with that exact error if the archive
   still carries SIWA. That is Apple’s rule, not a missing login.
3. **A public DMG therefore ships without SIWA.** Entitlements file:
   `Apps/AllnighterMac/Sources/AllnighterMac.DeveloperID.entitlements`
   (network client/server only). Debug / Run from Xcode still uses
   `AllnighterMac.entitlements` **with** SIWA (Apple Development). iPhone
   pairing works from a Run-from-Xcode build; it does not work from the
   website DMG. SIWA in a *public* Mac app means Mac App Store later — not a
   DMG trick.
4. **Xcode showing an Apple ID does not change (2) or (3).** The ship path is
   `scripts/build-dmg.sh`, which re-signs the archived `.app` with Developer
   ID. It does not use Organizer Direct Distribution.
5. **“Signed” means Gatekeeper (Developer ID + notarize + staple).** It does
   not mean “Sign in with Apple is in the DMG.” Those are different Apple
   features. The 1.0.1 DMG is signed.

Marketing site copy lives in Ikiro, not this repo. If a download button is
wrong, tell the site person. Do not edit HTML here.

---

## What strangers download

Same host. Two URLs. Never mix them.

| What | URL | What it is |
| --- | --- | --- |
| CLI | `curl -fsSL https://get.allnighter.io \| sh` | Install script at `/` |
| Mac app | `https://get.allnighter.io/Allnighter.dmg` | 302 → versioned DMG |

The Mac button on allnighter.io must be the DMG URL. **`https://get.allnighter.io/`
is the CLI script.** Pointing the Mac button at `/` looks like a broken download.

Versioned files are immutable:

```text
https://get.allnighter.io/v1.1.9/alln-macos-universal.tar.gz
https://get.allnighter.io/v1.1.3/Allnighter.dmg
https://get.allnighter.io/latest.json    # ONLY mutable object
```

Older versioned prefixes (`/v1.0.1/`, `/v1.1.2/`) stay on the bucket and must
not be overwritten.

Channel contract (field names, fail-open, one-liner):
`docs/phases/One_Paste_Cold_Start.md` § OPC-S06. This file owns the **ship
steps**. `latest.json` `app.url` / `app.sha256` must match the DMG we just
uploaded. `appVersion` must equal the app’s
`CFBundleShortVersionString` (`MARKETING_VERSION` in
`Apps/AllnighterMac/project.yml`) or the running app will show an update
forever.

Current public floor (2026-08-14): CLI **1.1.11** + Mac app **1.1.5** (arm64
DMG). CLI payload is `alln-macos-universal.tar.gz` (binary + SPM resource
bundles). Relocate-proof is a ship gate — a builder-local `version` check is
not proof (`menu --json` loads the catalog; `version` does not). Universal CLI scratch is `$HOME/Library/Developer/Allnighter/CLI-universal`
(not `dist/.build-universal` under a Documents checkout). Person hatch on
`alln version`. `alln feedback` postcard. Failures fall back to emailing
support@allnighter.io.

---

## Version bump law (CLI + Mac)

**Never republish the same version with different bytes.** Immutable prefixes
on R2; `latest.json` must point at a binary whose `alln version` gitSha matches
the tree you built.

| Change lands in | Bump | Ship |
| --- | --- | --- |
| `AllnighterCore`, `AllnighterEngine`, `AllnighterCLI`, or `scripts/get-alln.sh` | `AllnighterVersionIdentity.binaryVersion` (+ `MARKETING_VERSION` when app ships too) | `scripts/ship-cli.sh <version> [--upload]` |
| Mac app only (`Apps/AllnighterMac`) | `MARKETING_VERSION` in `project.yml`, then `scripts/public-floor.sh sync` | `build-dmg.sh` → publish DMG block in `latest.json` |
| Shared Core (capacity, probes, entitlement, install) | **Both** version fields | **Both** surfaces — CLI-only users inherit Core fixes |

Before upload: `alln version` on the candidate binary must show the new
`binaryVersion` and a gitSha equal to `git rev-parse HEAD`. Stale SPM scratch
(`rebuild_cli.sh` deletes `BuildInfo.generated.swift`) is the usual lie.

Pin: `VersionIdentityTests.testCurrentBinaryVersionIsBumped` +
`testBuildInfoGitShaMatchesWorkspaceHEAD` +
`testPublicFloorDocsMatchVersionIdentity`. GitHub `README.md` “Current floor”
is rewritten by `scripts/public-floor.sh` (also a `check-fast` gate). `ship-cli.sh`
syncs and commits those docs **before** the build so gitSha still matches HEAD.

---

## Ship the Mac app

Founder said submit/publish/ship the Mac app. Bump only when they want a
**new** version (not because Organizer failed).

1. Set `MARKETING_VERSION` in `Apps/AllnighterMac/project.yml`. Keep
   `CFBundleShortVersionString` as `$(MARKETING_VERSION)` in
   `Sources/Info.plist`.
2. `scripts/build-dmg.sh`  
   Archives Release (arm64), strips the Apple Development profile, signs with
   Developer ID + `AllnighterMac.DeveloperID.entitlements`, packs
   `dist/Allnighter.dmg`, notarizes, staples. Proof in the script output:
   `Authority=Developer ID Application: Happy Moose Apps Inc.`, notary
   `Accepted`, stapler `The validate action worked!`
3. Copy into the publish layout **without rewriting existing CLI bytes**:

   ```text
   dist/releases/v<version>/Allnighter.dmg
   dist/releases/v<version>/Allnighter.dmg.sha256
   ```

   `scripts/publish-release.sh <version>` **refuses** if `v<version>/` already
   exists. If CLI `1.0.1` is already on R2, add the DMG as a **new object**
   under that prefix. Do not rerun publish for the same CLI version.
4. Edit `dist/releases/latest.json`: keep the `cli` block unless also shipping
   CLI; set `appVersion`, `app.url`, `app.sha256`. Upload **assets first,
   `latest.json` last** (`scripts/upload-release-to-r2.sh` or
   `wrangler r2 object put` on bucket `allnighter-releases`, from
   `infra/get-faucet`).
5. Redeploy the Worker only if faucet code changed
   (`cd infra/get-faucet && wrangler deploy`). `/Allnighter.dmg` already 302s
   from `latest.json` `app.url`.
6. Check:

   ```bash
   curl -sSI https://get.allnighter.io/Allnighter.dmg
   # 302 → /v<version>/Allnighter.dmg
   curl -sS https://get.allnighter.io/latest.json
   ```

Do not overwrite a versioned object with different bytes. Bad build = new
version number.

The first public DMG is **Apple Silicon**. CLI is universal. Do not call the
DMG “universal” on the site.

---

## Ship the CLI

**One command.** Do not assemble this by hand — that is how a naked Mach-O
reached production.

```bash
scripts/ship-cli.sh <version>           # build, relocate-proof, sign, notarize, layout
scripts/ship-cli.sh <version> --upload  # then R2 (assets, get-alln.sh, latest.json last)
```

`ship-cli.sh` refuses unless `AllnighterVersionIdentity.binaryVersion` already
equals `<version>`, the relocated binary loads the catalog (`menu --json`) with
build-scratch bundles **hidden**, `strings` has no protected-folder bake, and
`alln version --json` gitSha equals `git rev-parse HEAD`.

Under the hood (do not skip relocate-proof):

1. `scripts/build-universal.sh` — lipo, copy SPM resource bundles next to the
   binary, **relocate-proof** (`scripts/relocate-cli-proof.sh`).
2. `scripts/sign-cli.sh` — Developer ID + hardened runtime, notarize a zip of
   binary + bundles. Staple is N/A on a unix executable.
3. `scripts/publish-release.sh <version>` — writes
   `v<version>/alln-macos-universal.tar.gz` + sha256, then `latest.json` last.
   Refuses a naked Mach-O.
4. `scripts/upload-release-to-r2.sh dist/releases` (only via `--upload`)

Same `latest.json`. Prefer matching `cliVersion` and `appVersion` when both
surfaces ship together. CLI-only ship keeps the current `app` block / 
`ALLN_APP_VERSION`.

---

## What this is not

| Do not | Why |
| --- | --- |
| Xcode Organizer → Direct Distribution for the website DMG | SIWA on the Debug entitlements makes Apple refuse the profile. Ship path is `build-dmg.sh`. |
| Create a “Mac Team Direct” profile that includes Sign in with Apple | Apple rejects it. |
| Point the Mac download button at `https://get.allnighter.io/` | That URL is `curl \| sh`. |
| Skip relocate-proof or publish a naked `alln` Mach-O | 1.1.5–1.1.8 `curl \| sh` crash. `scripts/ship-cli.sh` is the path. |
| Hand-edit the GitHub README version | It will age. `scripts/public-floor.sh` is the writer; `ship-cli.sh` syncs it. |
| Treat Sparkle as the source of “what’s latest” | Sparkle is future transport. SSOT is `latest.json`. |
| Edit allnighter.io copy in this repo | Ikiro. |

High-risk: notarization identity, production R2, Worker deploy — ask only when
the founder has **not** already said ship / bump / push / release / publish.
