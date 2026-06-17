# Fast local UI iteration — `allapp`

`scripts/dev.sh` regenerates the Xcode project, does an incremental build, and
relaunches the Mac app — the tight loop for design iteration.

## One-time setup

Add this to `~/.zshrc` (already done if you ran the setup):

```sh
# Allnighter — fast build & launch
allapp() { "$HOME/Documents/GitHub/Allnighter/scripts/dev.sh" "$@"; }
```

Then `source ~/.zshrc` (or open a new terminal).

## Use

```sh
allapp          # build + relaunch the app   (the default loop)
allapp build    # build only, don't launch
allapp test     # full green wall (swift + xcodebuild tests)
allapp clean    # drop the cached build, then build + launch fresh
```

Build output lives under `~/Library/Developer/Allnighter/Build/` — deliberately
OUTSIDE the repo. The checkout is under `~/Documents`, and macOS attributes a
child process's TCC prompts to the `.app`'s location, so launching from
`~/Documents` raised a Documents permission dialog on cold launch (Launch
Authority TCC hotfix, H4). `~/Library` is not TCC-protected and persists across
reboots. Override the location with `ALLNIGHTER_BUILD_DIR`.

The built bundle is `Allnighter.app` (`PRODUCT_NAME` in `Apps/AllnighterMac/project.yml`).
On a build failure it prints the `error:` lines and the log path.

## GUI proof (one-time Screen Recording grant)

**Tiered capture (no TCC for most proofs):**
- `home-*`, `thread-*`, `team-*`, `doctor-*`, `readiness-*`, `command-palette`:
  in-process snapshot of the main window content only. **No Screen Recording
  permission required.**
- `compose-*` (and `tcc-probe`): capture composites the app's own windows so
  **native SwiftUI `.alPopover` popovers** (separate OS windows) are visible in
  the PNG. These require Screen Recording permission granted once.

Grant (for compose popovers / tcc-probe only):

```sh
bash scripts/gui_proof_grant.sh
```

The proof harness is **`#if DEBUG` only** — compiled out of Release. Scripts build Debug.

1. Grant UI opens.
2. Click **Open System Settings**.
3. If Allnighter missing from the list, **+** → ⌘⇧G, paste the path shown, Open.
4. Toggle **Allnighter** ON.
5. Wait for green check in the grant window, then Quit.

Quick verification commands:

```sh
# No TCC needed — unblocks CR4 home/thread proofs
bash scripts/gui_proof.sh thread-empty
bash scripts/gui_proof.sh home-with-threads

# Exercises the Screen Recording composite path (uses the grant)
bash scripts/gui_proof.sh tcc-probe     # or compose-mode-menu
```

If a compose/tcc-probe capture fails, the script exits non-zero (no silent bad PNG)
and reprints the grant instructions. Re-run grant after major rebuilds if using
adhoc Debug signing (see "Stable signing for SR proofs" below).

### Stable signing for SR proofs (compose-*/tcc-probe)

Ad-hoc Debug builds (`Signature=adhoc`, no TeamIdentifier) cause the Screen
Recording grant to stop working after rebuilds because TCC on macOS for this
service is sensitive to the exact binary signature (CDHash) for adhoc-signed
bundles.

**Recommended:** sign Debug builds with a real "Apple Development" certificate
(requires Apple ID / free developer account in Xcode).

**CLI builds (`allapp`, `gui_proof.sh`):** signing is controlled by
`Apps/AllnighterMac/project.yml` (`DEVELOPMENT_TEAM` + no adhoc `-` identity).
`xcodegen` runs on every build, so changing Team only in the Xcode UI is wiped on
the next `allapp`. Edit `DEVELOPMENT_TEAM` in `project.yml`, then rebuild.

Verify after rebuild:

```sh
codesign -dv ~/Library/Developer/Allnighter/Build/Build/Products/Debug/Allnighter.app 2>&1 | grep -E 'TeamIdentifier|Signature'
# Expect: TeamIdentifier=LP5YNK7A36 (or your team), Signature NOT adhoc
```

In Xcode (optional sanity check): AllnighterMac target → Signing & Capabilities →
same Team as `project.yml`.

With a stable dev identity + TeamIdentifier, the grant typically survives
subsequent Debug rebuilds of the same bundle ID.

Alternative (adhoc only): after each clean/rebuild that breaks preflight,
re-run `gui_proof_grant.sh` + re-toggle in Settings, or `tccutil reset ScreenCapture com.allnighter.mac`.

The build output deliberately lives under `~/Library/Developer/Allnighter/Build`
(outside ~/Documents) per the Launch Authority TCC hotfix.
