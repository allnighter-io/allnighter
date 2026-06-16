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

Build is cached under `.build/mac/` (gitignored), so repeat runs are fast.
The built bundle is `Allnighter.app` (`PRODUCT_NAME` in `Apps/AllnighterMac/project.yml`).
On a build failure it prints the `error:` lines and the log path.
