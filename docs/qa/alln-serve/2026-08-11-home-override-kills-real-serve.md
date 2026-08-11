# Running `alln` with an overridden `HOME` disables the real user's serve

Date: 2026-08-11 (UTC)
Found by: ASR-S06h (gate 1 cold-install harness) taking the founder's live bench
down twice.
Host: second Mac (Mac mini), macOS 15.6 (24G84). Build `8f038730`.
Severity: **high** — silent, persistent loss of all background scheduling.

## Reproduction, measured

```bash
launchctl print gui/$(id -u)/com.allnighter.resident-coordinator   # LOADED
TMPH=$(mktemp -d)
HOME="$TMPH" ~/.local/share/allnighter/bin/alln serve disable
#   → "com.allnighter.resident-coordinator disabled: bootout settled,
#      plist removed, stopped verified"
launchctl print gui/$(id -u)/com.allnighter.resident-coordinator   # NOT LOADED
ls ~/Library/LaunchAgents/ | grep allnighter                        # GONE
cat ~/Library/Application\ Support/Allnighter/serve-desired-state.json
#   → { "state": "disabled" }        ← the REAL file, not the temp one
```

The temp home receives **nothing**. The real host loses the plist, the loaded
job, the running daemon, and has its durable desired state flipped to
`disabled`.

## Why

`InstallCLI` honors `HOME` — that was ASR-S01d, and it works: the canonical
binary and PATH symlink landed correctly under the temp home.

`ServeLifecycle` does not. It defaults both paths to
`FileManager.default.homeDirectoryForCurrentUser`
(`ServeLifecycle.swift:175`, `:182`, `:712`), which resolves through `getpwuid`
and **ignores the `HOME` environment variable**:

```swift
plistURL: URL = FileManager.default.homeDirectoryForCurrentUser …
homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
```

So one `install-cli` invocation splits in half: the **install layout** follows
`HOME` into the temp directory, while the **serve lifecycle** — plist path,
desired-state file, bootout, bootstrap — operates on the real user's home and
the real per-user launchd domain.

There is a deeper constraint underneath: the label
`com.allnighter.resident-coordinator` is scoped to the **user**, not to `HOME`.
Even a fully HOME-honoring lifecycle could not give a temp home its own
supervised daemon without a distinct label.

## Why it is worse than a broken test

`serve disable` writes `disabled` to the **real** durable desired-state file. Per
§2.2 and gate 8 — both proven working today — a disable is honored across login
and is not undone by a later install. So this does not self-heal:

- background scheduling stops;
- it stays stopped after logout/login;
- `install-cli` will not re-enable it, correctly, because the user "asked" for
  disabled;
- nothing about it is attributable — the plist is simply gone.

Recovery is `alln serve enable`, but only for someone who knows to look.

## Relationship to §10.1 R1 — candidate, not diagnosis

R1 records two unexplained events where the job was found not loaded with the
cause unidentified. This defect produces exactly that observable state, from an
ordinary-looking action, with no error and no log line naming it.

Any process that runs `alln` with a different `HOME` triggers it: a test harness,
a CI shim, a sandboxed or containerised agent, a worker whose environment sets
`HOME`. This session did it **twice by accident** while building a gate.

It is a **candidate explanation only**. Neither historical incident recorded the
environment of the process that ran before it, so the link cannot be confirmed.
R1 stays open. Do not archive the packet claiming otherwise.

## Second, smaller finding — §2.2 disclosure on the opt-out path

Cold install with `--no-serve` prints:

```text
serve: desired state set to disabled
…
serve: skipped (--no-serve)
```

§2.2 requires install output to "plainly say that Allnighter installed a per-user
background scheduler, why it exists, and how to disable it". On the opt-out path
the mirror obligation — that it was **not** installed, what the user is giving
up, and how to enable it later — is not met. `serve: skipped (--no-serve)` names
neither the consequence nor `alln serve enable`.

## Host state

Restored. `alln serve enable` → `healthy`, pid 43895, `binary.matches: true`,
real desired-state back to `enabled`.

## Fixed and verified on the live host — `3d6a0187` (ASR-S06i)

`ServeLifecycle` now routes every mutating path through one admission check that
compares symlink-canonical homes and refuses before touching anything:

```text
$ HOME=$(mktemp -d) alln serve disable
serve disable failed: SERVE_FOREIGN_HOME: refusing serve lifecycle for effective
HOME /var/folders/…/alln-foreign.GSVnIb; the per-user launchd label belongs to
real home /Users/openclaw. Use the real HOME and retry.
```

Measured after the fix, on the live host:

| Check | Result |
| --- | --- |
| `serve disable` under foreign HOME | refuses, **exit 1** |
| `serve enable` under foreign HOME | refuses, **exit 1** |
| `serve repair` under foreign HOME | refuses, **exit 1** |
| real LaunchAgent | **still loaded** |
| real plist | **still present** |
| real desired-state | **still `enabled`** |
| `serve status --json` under foreign HOME | **still readable**, `healthy`, exit 0 |

Observation is not mutation, so status stays allowed — the INFORM-never-BLOCK
law. The refusal names both paths so a caller sees immediately that its `HOME` is
the problem.

## Follow-up

[`ASR-S06i`](../../archive/phases/sprint/alln-serve/ASR-S06i-serve-lifecycle-refuses-foreign-home.md)

## Signature

Recorded by the PM agent from a controlled reproduction on the live host.

**No founder signature required.** §8 names gates **7, 8, 9 and 10** as the
ones needing a human at the machine, and only those. This gate was executed
and measured by the PM agent on the live host; the record above is the
evidence. An earlier draft of this file carried a "pending founder
countersignature" line — that was ceremony this packet does not ask for, and
it is removed.
