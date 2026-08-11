# ASR-S05c — `alln uninstall`: disable first, then remove what we installed

Status: **ready**
Priority: **P2 — §8 ASR-S05 requires it; the command does not exist.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §8
ASR-S05 ("Uninstall disables/boots out first, then removes canonical CLI, plist,
desired state, runtime receipt, and logs according to the uninstall
disclosure"), §4.1 (canonical layout), §2.2 (disclosure posture).

## 1. Measured gap

`alln menu --json` lists 125 commands. **None is `uninstall`.** A user who
installed a per-user LaunchAgent has no supported way to remove it. §2.2 makes
install disclose that a background scheduler was added; the packet's counterpart
obligation — a clean way to take it away — has never been built.

## 2. The ordering that makes it safe

Boot out **before** deleting anything. Deleting the plist while the job is loaded
leaves launchd holding a registration for a file that no longer exists; deleting
the binary first leaves a loaded job pointing at a missing executable, which is
the thrash this packet exists to prevent (§8 ASR-S01's ordering guard says the
same thing about staged bytes).

Order: disable/bootout → verify stopped → remove artifacts → report what was
removed and what was left.

## 3. Copy-paste prompt

> Add `alln uninstall [--json]`. It disables serve and boots out the LaunchAgent
> first, verifies it stopped, then removes the artifacts Allnighter installed:
> canonical binary, PATH symlink, plist, desired-state file, runtime receipt, and
> serve logs. It must say exactly what it removed and what it deliberately kept,
> require explicit confirmation for the destructive step unless `--yes` is
> passed, and never remove user data — runs, threads, projects, presets,
> credentials.

## 4. Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/CanonicalCLIInstall.swift` and
  `InstallCLI.swift` — the exact set of paths install creates. **Uninstall
  removes what install created and nothing else**; derive the list from there
  rather than hardcoding a guess.
- `Packages/AllnighterCore/Sources/AllnighterEngine/ServeLifecycle.swift` — the
  disable/bootout path to reuse. Do not write a second bootout.
- `docs/phases/Alln_Serve_Hotfixes.md` §4.1 for the canonical layout, and §5.3
  for the exit-code table.
- `Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift`
  — how a command and its error codes are declared.

## 5. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCore/ContractRegistry+Milestone1.swift
Packages/AllnighterCore/Sources/AllnighterCore/UninstallCLI.swift            (new)
Packages/AllnighterCore/Sources/AllnighterCLI/AllnighterCLI.swift
Packages/AllnighterCore/Tests/AllnighterCoreTests/UninstallCLITests.swift    (new)
```

## 6. Do not touch

`ServeLifecycle`'s internals, the plist shape, any scheduler, any script,
`HelpTopicRegistry` (a help topic for uninstall is a separate slice).

## 7. Steps

1. **Disable and bootout first**, reusing `ServeLifecycle`. Verify stopped before
   removing anything. If the bootout fails, **stop and report** — do not proceed
   to delete a plist for a job that is still loaded.

2. **Remove only what install created**, derived from the install owner:
   - canonical binary `~/.local/share/allnighter/bin/alln` and any
     `<canonical>.rollback`;
   - the PATH symlink — **only if** it resolves to the canonical binary. A
     symlink pointing elsewhere is someone else's and must be left alone, and
     said so;
   - `~/Library/LaunchAgents/com.allnighter.resident-coordinator.plist`;
   - the desired-state file;
   - the runtime receipt;
   - serve logs under `~/Library/Logs/Allnighter/`.

3. **Never remove user data.** Runs, threads, projects, presets, skills,
   credentials, and the rest of `~/Library/Application Support/Allnighter/` stay.
   Print the path that was kept so the user knows where their data is and can
   remove it themselves if they want. This is the difference between uninstalling
   the product and deleting someone's work.

4. **Confirm before destroying.** Interactive confirmation by default; `--yes`
   to skip. `--json` implies non-interactive and therefore requires `--yes` —
   refuse otherwise rather than destroying on a scripted call that did not say so.

5. **Report per artifact**: removed / absent / kept-and-why. A summary that says
   "done" without naming what happened is not a disclosure.

6. **Honour the foreign-HOME guard** (ASR-S06i). Uninstall is a lifecycle
   operation; under a foreign `HOME` it must refuse exactly as
   `enable`/`disable`/`repair` do. A test must prove it.

7. **Exit codes** per §5.3. Pick deliberately and justify in the commit message.

## 8. Works Test

```bash
scripts/swift-test.sh --filter 'UninstallCLITests|ContractRegistryTests'
bash scripts/rebuild_cli.sh
alln uninstall --json          # must REFUSE without --yes
```

**Do not run `alln uninstall --yes` on this host** — it would remove the
founder's live install. Tests must exercise the real logic against a temp
directory tree, not the real paths.

## 9. Done when

- [ ] `alln uninstall` exists, is in the contract, and appears in `alln menu`.
- [ ] Bootout/verify-stopped happens before any deletion; a failed bootout stops
      the operation.
- [ ] Only install-created artifacts are removed; the PATH symlink is left alone
      unless it resolves to the canonical binary.
- [ ] User data is never removed, and the retained path is printed.
- [ ] Destructive step requires confirmation; `--json` requires `--yes`.
- [ ] Per-artifact report: removed / absent / kept-and-why.
- [ ] Refuses under a foreign `HOME`, proven by test.
- [ ] Focused tests and `rebuild_cli.sh` pass; no test writes outside a temp dir.
- [ ] One commit.

## 10. Host-state invariant

Additive. The command exists but does nothing unless invoked with confirmation.
Nothing about install or serve behaviour changes.
