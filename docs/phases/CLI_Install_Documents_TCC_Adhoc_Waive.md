# CLI Install Documents TCC — Ad-hoc Dogfood Follow-up

Status: **OPEN — v2 (WAIVE + amendments)**  
Created: 2026-08-11 · Updated: 2026-08-11 (v2)  
Second opinion: DeepSeek V4 Pro `8B500118` — **agree-with-amendments**  
Parent (shipped): archived `CLI_Install_Documents_CWD_TCC.md` (`ProtectedCWDEscape`, `b65a2ea2`)  
Trigger: founder still sees “alln would like to access files in your Documents
folder” on uninstall + CLI reinstall after P1 landed.

## Ruling

**WAIVE further code war on this popup for ad-hoc dogfood.**

This is a **dev-build / signing-track** nuisance, not a first-user product bug.
Founder instruction: if unsigned/dev — **ignore**.

- First-user path: Developer ID + notarized `curl | sh` / DMG — stable team
  identity; a one-time Allow sticks.
- Dogfood path: ad-hoc `rebuild_cli` from `~/Documents/GitHub/Allnighter` —
  new CDHash every rebuild; Documents is the ambient cwd for uninstall/`alln`.

## First principles

1. Documents TCC prompts when **this code identity** touches Documents (cwd
   resolve / open / spawn inheritance)—not because the binary was built from a
   Documents package path.
2. Ad-hoc (`codesign --sign -`) has **no stable team anchor**. Identity **is**
   the CDHash. Every `rebuild_cli` is a new TCC client.
3. Measured after the “fixed” rebuild: `Signature=adhoc`, `TeamIdentifier=not
   set`, CDHash churned (`a32e0637…` → `89caec7c…`).
4. `otool` shows **no** Documents rpaths on the installed binary.
5. Catch-22: `ProtectedCWDEscape.escapeIfNeeded` reads
   `FileManager.default.currentDirectoryPath` via `Seams.live.currentDirectory`
   (`ProtectedCWDEscape.swift` live seams) **before** it can leave Documents.
   That **read is the protected touch**. No further in-process escape layer
   can avoid the first getcwd. Only a **pre-exec** `cd` avoids it.
6. Residual dogfood popup source: `scripts/uninstall-allnighter.sh` runs
   `alln serve disable` from the caller’s cwd (typically Documents) with **no**
   cd-away first (~line 209). That is separate from `rebuild_cli`, which
   already `cd`s to ProbeScratch **before** `exec install-cli` (lines 58–63)—
   so install-cli inherits ProbeScratch, not Documents.

## What P1 did / did not buy

| Shipped | Effect |
| --- | --- |
| `ProtectedCWDEscape` | Correct hygiene; cannot prevent the first getcwd if already in Documents |
| `rebuild_cli` ProbeScratch `cd` before `exec` | **Fully effective** for the install-cli hop |
| uninstall → `alln serve disable` from Documents cwd | **Still prompts** for whatever identity is on PATH |

## Smoking gun for Developer ID cold install from non-Documents cwd?

**NONE.** Install writes only under `~/.local/*`, LaunchAgents, Application
Support. No Documents rpaths. `resolvedRunningBinary` uses absolute argv0.
Signed cold install from `~` is not this bug. (Uninstall invoked from a
Documents cwd can still one-shot prompt a signed binary—Allow sticks.)

## Do not

- Add more chdir layers, FDA, entitlements, or “click Allow” copy
- Relitigate resident `repoRoot` under Documents here
- Treat ad-hoc Documents re-prompt as a release blocker

## Optional hygiene (non-blocking; not required to accept WAIVE)

Before any `alln` call in `uninstall-allnighter.sh`, `cd` to `$HOME` or
ProbeScratch (mirrors rebuild_cli belt). Cheap; helps ad-hoc and signed.
Explicitly **not** a gate for this ruling.

## Manual check (founder-only, optional)

```bash
# From Documents checkout — expect prompt on uninstall for THIS ad-hoc identity
tccutil reset SystemPolicyDocumentsFolder   # only if safe on this host
bash scripts/uninstall-allnighter.sh --yes
# Allow once for that build; rebuild_cli install-cli hop should stay quiet
bash scripts/rebuild_cli.sh
```

## Changelog

| Ver | Change |
| --- | --- |
| v1 | Propose WAIVE; ad-hoc CDHash + catch-22. |
| v2 | DeepSeek `8B500118`: name `currentDirectoryPath` API; credit rebuild_cli belt as effective; pin residual to uninstall:~209; NONE for Developer ID cold-install smoking gun; optional uninstall cd; manual check surface. |
