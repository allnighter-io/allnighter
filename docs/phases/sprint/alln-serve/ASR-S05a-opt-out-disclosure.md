# ASR-S05a — the opt-out path must disclose what it skipped

Status: **ready**
Priority: **P2 — §2.2 disclosure obligation unmet on the `--no-serve` path.**
SSOT: [`docs/phases/Alln_Serve_Hotfixes.md`](../../Alln_Serve_Hotfixes.md) §2.2.
Evidence:
[`2026-08-11-home-override-kills-real-serve.md`](../../../qa/alln-serve/2026-08-11-home-override-kills-real-serve.md)
§"Second, smaller finding" — found by the ASR-S06h cold-install gate.

## 1. The gap

§2.2:

> Install output must plainly say that Allnighter installed a per-user background
> scheduler, why it exists, and how to disable it. **This is the permission/startup
> posture disclosure.**

Measured on a real cold install with the opt-out:

```text
serve: desired state set to disabled
installed: <home>/.local/bin/alln → <home>/.local/share/allnighter/bin/alln
Canonical binary: <home>/.local/share/allnighter/bin/alln
Next: run `alln menu --json`; if benchTally.nextAction is set, run that command once.
serve: skipped (--no-serve)
```

`serve: skipped (--no-serve)` tells the user nothing. It does not say what a
background scheduler would have done, what is now not happening, or how to turn
it on later. The disclosure obligation is symmetric — a user who opts out needs
to know what they opted out of at least as much as one who does not.

## 2. Copy-paste prompt

> On the `--no-serve` / `ALLN_NO_SERVE=1` install path, replace the bare
> `serve: skipped (--no-serve)` line with a short disclosure that says the
> per-user background scheduler was **not** installed, names in one line what it
> would have done, and gives the exact command to enable it later. Keep it to a
> few lines — this is a disclosure, not a sales pitch. Check the enabled path
> also meets §2.2 and fix it in the same slice if it does not.

## 3. Read only

- `Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift` — where the
  install prints its serve lines, both paths.
- `docs/phases/Alln_Serve_Hotfixes.md` §2.2 and §6's scheduler list (what serve
  actually owns, so the one-line "what it would have done" is accurate and not
  invented).

## 4. Touch only

```text
Packages/AllnighterCore/Sources/AllnighterCore/InstallCLI.swift
Packages/AllnighterCore/Tests/AllnighterCoreTests/InstallCLITests.swift
```

## 5. Do not touch

`ServeLifecycle`, the desired-state store, any plist, any scheduler, any script,
the JSON shape of `install-cli --json`. **Human output only** — a JSON caller's
payload must not change.

## 6. Steps

1. **Say what was skipped, why it exists, and how to enable it.** The enable
   command is `alln serve enable`. Name it exactly.

2. **Be accurate about what serve owns.** §6 lists the schedulers: pending wake,
   PM turn wake, boost seed, vendor backoff, notifications, capacity refresh,
   probe record refresh. Summarise honestly in one line — do not claim behaviour
   serve does not have, and do not imply the CLI is broken without it. `alln run`
   works fine with serve disabled; only *deferred* obligations are affected.

3. **Check the enabled path too.** §2.2 asks for three things — that it was
   installed, why, and how to disable. If the enabled path is missing any of
   them, fix it here; that is the same obligation, not scope creep.

4. **Do not change `--json`.** The disclosure is for humans. A JSON consumer
   reading `install-cli --json` must see byte-identical structure; add a test
   that proves it.

5. **Keep it short.** Three or four lines. A wall of text is not a disclosure.

## 7. Works Test

```bash
scripts/swift-test.sh --filter 'InstallCLITests'
bash scripts/rebuild_cli.sh
```

Safe manual check — install into a throwaway home, which touches nothing real
now that `SERVE_FOREIGN_HOME` refuses lifecycle operations there:

```bash
TMPH=$(mktemp -d); HOME="$TMPH" alln install-cli --no-serve; rm -rf "$TMPH"
```

Paste the actual output.

## 8. Done when

- [ ] Opt-out output names: not installed, what it would have done, and
      `alln serve enable`.
- [ ] Enabled path meets all three of §2.2's requirements.
- [ ] Claims about serve's behaviour match §6; nothing invented.
- [ ] `install-cli --json` structure unchanged, proven by test.
- [ ] Focused tests and `rebuild_cli.sh` pass. One commit.

## 9. Host-state invariant

Text only. No lifecycle, scheduling, or install-layout behaviour changes.
