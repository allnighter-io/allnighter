# Fast iOS iteration — `allios`

`scripts/ios_dev.sh` builds AllnighteriOS, launches it on the simulator, or runs
unit tests — the tight loop for iOS work in this repo.

## One-time setup

Add to `~/.zshrc`:

```sh
# Allnighter iOS — build, launch simulator, unit tests (Allnighter-iOS repo)
allios() { "$HOME/Documents/GitHub/Allnighter-iOS/scripts/ios_dev.sh" "$@"; }
```

Then `source ~/.zshrc` (or open a new terminal).

For **live** Mac relay (not preview):

```sh
scripts/bootstrap_remote_env.sh
scripts/serve_remote.sh    # separate terminal on your Mac
```

## Use

```sh
allios              # .env present → live relay; else DEBUG preview
allios preview      # build + launch preview (no .env required)
allios launch       # install + relaunch only (~seconds if simulator is warm)
allios build        # build only
allios test         # AllnighteriOSTests on simulator
allios clean        # wipe iOS DerivedData, then build + launch
```

**Fast UI loop:** `allios build` once, then `allios launch` after small SwiftUI edits
(or use Xcode ⌘R with Derived Data at `~/Library/Developer/Allnighter/iOS-Build`).

Build output: `~/Library/Developer/Allnighter/iOS-Build/` (override with
`ALLNIGHTER_IOS_BUILD_DIR`). Simulator device: `IOS_SIMULATOR_DEVICE` (default:
first available iPhone).

Unit test log: `/tmp/allnighter-ios-unit-tests.log`
