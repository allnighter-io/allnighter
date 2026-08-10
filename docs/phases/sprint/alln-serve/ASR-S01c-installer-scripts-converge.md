# ASR-S01c — installer scripts converge on `install-cli`

Status: **ready**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.1
(dev build installs through the same layout), §4.3 (the one-paste installer
downloads, verifies sha256, then invokes the candidate's `install-cli`).

**3 of 3** in the ASR-S01 cut. S01a added `CanonicalCLIInstall` (`d60efa8a`);
S01b routed `install-cli` through it (`91cad2de`). The two shell entry points
still hand-maintain their own install layout. This slice deletes that.

## 1. Goal

`scripts/get-alln.sh` and `scripts/rebuild_cli.sh` stop placing binaries
themselves. Each produces a candidate and calls that candidate's `install-cli`,
so there is exactly one code path that decides where CLI bytes live.

## 2. Copy-paste prompt

> Rewrite the install portion of `scripts/get-alln.sh` and `scripts/rebuild_cli.sh`
> so neither script copies, symlinks, or chooses an install directory itself —
> each hands its verified candidate to `"$CANDIDATE" install-cli` and reports
> that command's result. Keep every existing flag, env var, and exit code that
> callers already depend on. Update `scripts/test-get-alln.sh` to match. Touch no
> Swift source.

## 3. Read only

- `scripts/get-alln.sh` — current download, sha256 verification, and install
  layout; note it already execs the downloaded binary before installing.
- `scripts/rebuild_cli.sh` — where the dev build lands today and what it puts on
  PATH.
- `scripts/test-get-alln.sh` — the harness that must keep passing.

## 4. Touch only

```text
scripts/get-alln.sh
scripts/rebuild_cli.sh
scripts/test-get-alln.sh
```

## 5. Do not read / do not touch

- No Swift source, no `Packages/`, no `Apps/`, no launchd, no plist.
- Do not add a signature or notarization check — §4.3 explicitly keeps the
  existing sha256-only verification. Do not remove the sha256 check either.
- Do not add serve enable/disable, `--no-serve`, or `ALLN_NO_SERVE` handling —
  that is ASR-S02.
- Do not change the published faucet URLs or `ALLN_INSTALL_BASE_URL` semantics.

## 6. Steps

1. **`get-alln.sh`.** Keep: download to a temp dir, verify the published sha256,
   exec the downloaded binary once as a liveness check. Then replace the
   hand-rolled install with a single call to
   `"$TMP_BINARY" install-cli` (passing `--path "$X"` through only when the
   caller supplied an explicit install directory). Delete any code in this script
   that copies the binary to a final location or creates a symlink. Report the
   subcommand's exit code as the script's exit code, unchanged.

2. **`rebuild_cli.sh`.** Keep building into the Library/Developer scratch
   location (§4.3 step 1 depends on that candidate not being under
   `~/Documents`). Replace whatever it does afterward with a single
   `"$BUILT_BINARY" install-cli` call. Delete any direct `ln -s`, `cp`, or
   install-directory choice in this script.

3. **Failure honesty.** If `install-cli` fails, print its stderr verbatim and
   exit with its code. Do not add a retry, do not fall back to a manual copy,
   and do not print a success line after a failure.

4. **`test-get-alln.sh`.** Update expectations so the test asserts the script
   delegated to `install-cli` and that the resulting PATH entry resolves to the
   canonical binary. Keep the existing sha256-mismatch and download-failure
   cases passing.

5. **Comments.** Where a script previously documented its own install layout,
   replace that prose with a one-line pointer to `install-cli` as the owner.
   Do not restate the canonical path in shell — it is the Swift owner's
   decision, and duplicating it here recreates the disagreement §3 names.

## 7. Works Test

```bash
bash scripts/test-get-alln.sh
```

## 8. Done when

- [ ] Neither script contains a `ln -s`, `cp`-to-final-location, or install
      directory choice for the `alln` binary (grep-provable).
- [ ] `get-alln.sh` still verifies sha256 before executing anything, and still
      execs the candidate once before installing.
- [ ] Both scripts exit with `install-cli`'s exit code on failure and print its
      stderr verbatim.
- [ ] `rebuild_cli.sh` still builds to the Library/Developer scratch path, so the
      candidate is never refused as a protected `~/Documents` source.
- [ ] `bash scripts/test-get-alln.sh` passes.
- [ ] No Swift file changed. One commit, explicit paths.

## 9. Host-state invariant

With S01a+S01b+S01c committed, the founder's `rebuild_cli.sh` loop installs a
canonical binary and repoints PATH at it. The live LaunchAgent still runs the
Application Support staged bytes and is now frozen at its current build — it no
longer tracks installs. That is the deliberate intermediate state recorded in
§8 ASR-S02; the next slice rebinds the agent and closes it. Nothing in this
slice can wedge launchd, because nothing in this slice touches launchd.
