# CLI Install Documents TCC — Ad-hoc Dogfood Follow-up

Status: **Complete — v3 WAIVE** · archived 2026-08-11  
Created: 2026-08-11 · Updated: 2026-08-11 (v3)  
Second opinion: DeepSeek V4 Pro `8B500118` — **agree-with-amendments**  
Composer audit: Composer 2.5 `CDCD7AC4` — **agree-with-amendments**  
Parent (shipped): archived `CLI_Install_Documents_CWD_TCC.md` (`ProtectedCWDEscape`, `b65a2ea2`)  
Trigger: founder still sees “alln would like to access files in your Documents
folder” on uninstall + CLI reinstall after P1 landed.  
Durable note: `docs/operations/debugger/2026-08-11-cli-install-documents-tcc-adhoc-waive.md`

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

**Uninstall prompt ≠ install-cli regression:** P1 (`ProtectedCWDEscape` +
`rebuild_cli` ProbeScratch belt) owns the install-cli hop; uninstall’s
`serve disable` from Documents cwd is a separate belt and was never in P1 scope.

## Prompt expectation matrix

| Path | Typical cwd | Signing | Expected Documents prompt count |
| --- | --- | --- | --- |
| `rebuild_cli` → `install-cli` | ProbeScratch (belt `cd` before `exec`) | ad-hoc | **0** — belt + `ProtectedCWDEscape` own this hop |
| `uninstall-allnighter.sh` → `alln serve disable` | Documents (caller checkout) | ad-hoc | **1** per new CDHash — no pre-exec `cd` |
| Signed cold install from `~` | `~` (non-protected) | Developer ID | **0** — install writes only under `~/.local/*`, LaunchAgents, Application Support |
| Ad-hoc any Documents touch | Documents (or inherited) | ad-hoc | **1** per new CDHash — identity churn, not a product defect |

## What P1 did / did not buy

| Shipped | Effect |
| --- | --- |
| `ProtectedCWDEscape` | Correct hygiene; cannot prevent the first getcwd if already in Documents |
| `rebuild_cli` ProbeScratch `cd` before `exec` | **Fully effective** for the install-cli hop |
| uninstall → `alln serve disable` from Documents cwd | **Still prompts** for whatever identity is on PATH |

## First-user / signed-release-path defect?

**No identified first-user or signed-release-path defect.** Install writes only
under `~/.local/*`, LaunchAgents, Application Support. No Documents rpaths.
`resolvedRunningBinary` uses absolute argv0. Signed cold install from `~` is not
this bug.

**Unmeasured (founder-only):** `tccutil reset SystemPolicyDocumentsFolder` on a
Documents-hosted checkout, and signed-binary uninstall invoked from a Documents
cwd — both deliberately out of scope here (see gate 6 scope limit below).

## Gate 6 cross-link

ASR-S06 gate 6 PASS record and its deliberate Documents-reset scope limit:
[`docs/qa/alln-serve/2026-08-11-gate6-tcc-no-protected-prompt.md`](../qa/alln-serve/2026-08-11-gate6-tcc-no-protected-prompt.md).
That gate’s string-grep + Desktop/Downloads empirical PASS does not substitute
for Documents CWD inheritance; P1 closed the CWD hole separately (parent packet).

## Do not

- Add more chdir layers, FDA, entitlements, or “click Allow” copy
- Relitigate resident `repoRoot` under Documents here
- Treat ad-hoc Documents re-prompt as a release blocker

## Optional hygiene (non-blocking; not required to accept WAIVE)

Before any `alln` call in `uninstall-allnighter.sh`, `cd` to `$HOME` or
ProbeScratch (mirrors rebuild_cli belt). Cheap; helps ad-hoc and signed.
Explicitly **not** a gate for this ruling and **not implemented** in this closeout.

## Manual check (founder-only, optional)

**`tccutil reset SystemPolicyDocumentsFolder` is unsafe on a Documents-hosted
checkout** — it revokes the terminal’s access to the working tree mid-session.

```bash
# From Documents checkout — expect prompt on uninstall for THIS ad-hoc identity
tccutil reset SystemPolicyDocumentsFolder
bash scripts/uninstall-allnighter.sh --yes
# Allow once for that build; rebuild_cli install-cli hop should stay quiet
bash scripts/rebuild_cli.sh
```

## Done when (checked)

- [x] WAIVE ruling recorded with prompt expectation matrix
- [x] Composer audit `CDCD7AC4` amendments incorporated
- [x] No further code authorized (`ProtectedCWDEscape` unchanged; uninstall `cd` not implemented)
- [x] Durable debugger note
- [x] Packet archived; phases board row removed

## Changelog

| Ver | Change |
| --- | --- |
| v1 | Propose WAIVE; ad-hoc CDHash + catch-22. |
| v2 | DeepSeek `8B500118`: name `currentDirectoryPath` API; credit rebuild_cli belt as effective; pin residual to uninstall:~209; NONE for Developer ID cold-install smoking gun; optional uninstall cd; manual check surface. |
| v3 | Composer `CDCD7AC4`: prompt expectation matrix; soften smoking-gun wording + unmeasured Documents reset/signed uninstall; uninstall ≠ install-cli regression sentence; gate 6 scope-limit cross-link; bold Documents reset unsafe on Documents-hosted checkout; **Complete** + archive. |
