# ASR-S06h — cold install into a clean home, with the opt-out

Status: **ready**
Priority: **P2 — gate 1 unrun; `--no-serve` (§2.2) has never been tested at all.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §8
host matrix item **1**, §2.2 (install enables by default, disclosed opt-out),
§4.1 (canonical layout), §4.3 (install transaction).
Prior: ASR-S01d made the install honor `HOME`, which is what makes this testable
at all.

## 1. The safety constraint that shapes this slice

Gate 1 wants a cold install in a clean user home. `HOME` can be overridden, so
the install layout is testable. **The LaunchAgent label cannot be.**

`com.allnighter.resident-coordinator` is scoped to the *user*, not to `HOME`. A
cold install that enables serve from a temp home would bootstrap that same label
into `gui/501` — taking over the founder's live daemon and pointing it at a
binary under `/tmp`. Deleting the temp home afterwards would leave launchd
thrashing on a missing executable.

So this slice tests the cold install **with serve opted out**:
`ALLN_NO_SERVE=1` / `--no-serve`. That is not a dodge — it is the only variant
that is safe to run, and it happens to cover a §2.2 requirement that no gate has
ever touched. What it does not cover is stated in the record, not implied.

**Do not** enable serve from a temp home. **Do not** touch
`~/Library/LaunchAgents`. If the scenario would register anything into `gui/501`,
that is a bug in the scenario.

## 2. Copy-paste prompt

> Add an inspect-only scenario `--assert cold-install` to
> `scripts/works-test-serve-continuity.sh`. It performs a cold `install-cli` into
> a throwaway `HOME` under a temp directory with serve opted out, then asserts
> §4.1's canonical layout was created there, that the disclosure §2.2 requires is
> printed, that the desired-state marker records the opt-out, and — most
> importantly — that **nothing was registered into the real user's launchd domain
> and the real agent is untouched**. It cleans the temp home up on every exit
> path.

## 3. Read only

- `scripts/works-test-serve-continuity.sh` — helpers, the stderr/stdout rule, the
  existing `--assert` flag shape.
- `docs/phases/Alln_Serve_Hotfixes.md` §2.2 (opt-out and the disclosure
  requirement), §4.1 (canonical layout paths), §8 item 1.
- `Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift` — what
  `install-cli` writes and what `--no-serve` does. **Do not change it.**

## 4. Touch only

```text
scripts/works-test-serve-continuity.sh
```

## 5. Do not touch

Any Swift source or test. Any other script. `~/Library/LaunchAgents`. The real
canonical binary at `~/.local/share/allnighter/bin/alln`. Anything under the real
`$HOME`.

## 6. Steps

1. **`--assert cold-install`**, non-mutating with respect to the real host. It
   must be safe to run at any time.

2. **Snapshot the real agent first** — label loaded or not, its `program`, and
   the real daemon pid. Re-check all three at the end and **fail loudly** if any
   changed. This is the assertion that protects the founder's bench, so write it
   first and make sure it can fail.

3. **Build the temp home**: `mktemp -d`, then run the *installed* `alln` binary
   with `HOME` pointed at it and serve opted out. Use the documented opt-out —
   `ALLN_NO_SERVE=1` env or `--no-serve`; report which one you used.

4. **Assert §4.1 layout inside the temp home**, not the real one:
   - `<tmp>/.local/share/allnighter/bin/alln` exists and is executable;
   - it is byte-identical to the source binary that installed it;
   - the PATH symlink `<tmp>/.local/bin/alln` resolves to that canonical path;
   - the desired-state file exists and records **disabled**;
   - **no** plist was written under `<tmp>/Library/LaunchAgents/`.

5. **Assert the §2.2 disclosure.** Install output must plainly say a per-user
   background scheduler exists, why, and how to disable it — or, on the opt-out
   path, that it was **not** installed and how to enable it. Assert on the
   substance, and print the actual output so a reader can judge the wording.

6. **Assert the real host is untouched**: real agent still loaded with the same
   `program`, real daemon pid unchanged, real canonical binary sha256 unchanged,
   and the temp path appears nowhere in `launchctl print gui/$(id -u)/…`.

7. **Clean up the temp home on every exit path**, via a trap. Never `rm -rf` a
   path that is not the one `mktemp -d` returned — guard on the prefix.

## 7. Works Test

```bash
bash scripts/works-test-serve-continuity.sh --assert cold-install
bash scripts/works-test-serve-continuity.sh --assert identity-and-receipts   # unchanged
bash scripts/works-test-serve-continuity.sh                                  # unchanged
```

All safe and non-mutating with respect to the real host. **Run all of them
yourself and paste real output.**

## 8. Done when

- [ ] Cold install into a throwaway `HOME` produces the §4.1 canonical layout
      there, with the binary byte-identical to its source.
- [ ] Desired state records the opt-out; no plist written in the temp home.
- [ ] The §2.2 disclosure is asserted on substance and printed verbatim.
- [ ] The real agent, real daemon pid, and real canonical binary are proven
      unchanged — and that assertion is able to fail.
- [ ] Temp home removed on every exit path, with a prefix guard on the delete.
- [ ] Existing scenarios untouched and passing.
- [ ] One commit, one file.

## 9. Host-state invariant

Read-only with respect to the real host. Everything it creates lives under a
`mktemp -d` path and is removed.

## 10. Out of scope — say so in the record

The serve-enabled cold install. It cannot be tested from a temp home because the
launchd label is per-user, and taking over the founder's live agent to prove a
gate is not a trade worth making. Gate 1's serve half stays unproven; gates 2, 3,
4, 7 and 8 cover the supervised daemon on the real home, which is not the same
claim.
