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
