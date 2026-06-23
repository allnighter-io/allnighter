# Fast iOS iteration — `allios`

`scripts/ios_dev.sh` builds AllnighteriOS, launches it on the simulator with
relay env from `.env`, or runs unit tests — the tight loop for iOS work in this
repo.

## One-time setup

Add to `~/.zshrc`:

```sh
# Allnighter iOS — build, launch simulator, unit tests (Allnighter-iOS repo)
allios() { "$HOME/Documents/GitHub/Allnighter-iOS/scripts/ios_dev.sh" "$@"; }
```

Then `source ~/.zshrc` (or open a new terminal).

First run needs relay env:

```sh
scripts/bootstrap_remote_env.sh
```

Mac agent for live (not preview) data:

```sh
scripts/serve_remote.sh    # separate terminal
```

## Use

```sh
allios          # build + install + launch on simulator (scripts/ios_live.sh)
allios build    # build only — no .env required
allios test     # AllnighteriOSTests on simulator
allios clean    # wipe iOS DerivedData, then build + launch
```

Build output: `~/Library/Developer/Allnighter/iOS-Build/` (override with
`ALLNIGHTER_IOS_BUILD_DIR`). Simulator device: `IOS_SIMULATOR_DEVICE` (default:
first available iPhone).

Unit test log: `/tmp/allnighter-ios-unit-tests.log`
