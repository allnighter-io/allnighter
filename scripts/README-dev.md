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

Overlay fixtures (`compose-*`) capture **native SwiftUI popovers**, which requires
Screen Recording permission. Grant it once through the real `.app` bundle:

```sh
bash scripts/gui_proof_grant.sh
```

The proof harness is **`#if DEBUG` only** — it is compiled out of Release builds.
Proof scripts (`gui_proof.sh`, `gui_proof_grant.sh`) build Debug by default.

1. Allnighter opens a **grant window** (not a silent 1.5s flash).
2. Click **Open System Settings**.
3. If Allnighter is missing, click **+** → ⌘⇧G → paste the path shown in the window.
4. Turn **Allnighter** ON.
5. Wait for the green checkmark, then **Quit**.

Then capture proofs normally:

```sh
bash scripts/gui_proof.sh compose-mode-menu
```

If an overlay capture fails, the script exits non-zero with the error — it does
**not** silently produce a broken PNG.
