# CLI Install Documents TCC — Ad-hoc Dogfood Follow-up

Status: **OPEN — v1 investigation (ruling proposed: WAIVE)**  
Created: 2026-08-11  
Parent (shipped): archived `CLI_Install_Documents_CWD_TCC.md` (`ProtectedCWDEscape`, `b65a2ea2`)  
Trigger: founder still sees “alln would like to access files in your Documents
folder” on uninstall + CLI reinstall after P1 landed.

## First principles

1. Documents TCC prompts when **this code identity** touches Documents (cwd
   resolve / `getcwd` / open / spawn inheritance)—not because the binary was
   *built from* a Documents package path.
2. Ad-hoc (`codesign --sign -`) has **no stable team anchor**. Identity **is**
   the CDHash. Every `rebuild_cli` is a new TCC client.
3. Measured on this host after the “fixed” rebuild: `Signature=adhoc`,
   `TeamIdentifier=not set`, CDHash churned (`a32e0637…` → `89caec7c…`).
4. `otool` shows **no** Documents rpaths on the installed binary—only system /
   Xcode swift paths.
5. `ProtectedCWDEscape.escapeIfNeeded` **must read** `currentDirectoryPath`
   before it can leave Documents. If the process already started with a
   Documents cwd, that read **is** the protected touch. Catch-22. Only a
   **pre-exec** `cd` (rebuild_cli belt) avoids it.
6. `uninstall-allnighter.sh` still runs `alln serve disable` from the caller’s
   cwd (typically the Documents checkout) **before** any cd-away—so uninstall
   alone can surface the dialog for whatever `alln` identity is on PATH.

## What P1 did / did not buy

| Shipped | Helps signed install from Documents cwd | Stops ad-hoc rebuild re-prompt |
| --- | --- | --- |
| `ProtectedCWDEscape` before install/serve-mutate | Yes (after first getcwd—still one touch if already in Documents) | No if any Documents touch remains |
| `rebuild_cli` cd before `exec install-cli` | Yes for that hop | Only if **nothing** in that process touches Documents |

## Proposed ruling (v1)

**WAIVE further code war on this popup for ad-hoc dogfood.**

This is a **dev-build / signing-track** nuisance, not a first-user product bug:

- First-user path is Developer ID + notarized `curl \| sh` / DMG (see
  `One_Paste_Cold_Start.md`)—stable team identity; Allow sticks.
- Dogfood path is ad-hoc `rebuild_cli` from `~/Documents/GitHub/Allnighter`—
  new CDHash every rebuild; Documents checkout is the ambient cwd for
  uninstall/`alln` calls.
- Founder instruction: if this is a signing / unsigned-dev issue, **ignore**.

Do **not**:

- Add more chdir layers, FDA, entitlements, or “click Allow” copy
- Relitigate resident `repoRoot` under Documents here
- Treat gate 6 Documents waiver failure as a release blocker for ad-hoc

Optional hygiene (non-blocking, only if cheap later): uninstall script should
`launchctl bootout` without invoking `alln` from a Documents cwd—or cd to
ProbeScratch/`$HOME` before any `alln` call. Not required to close this ruling.

## Works Test for this ruling

None code. Acceptance = founder accepts WAIVE for ad-hoc dogfood; signed
cold-install remains the proof surface for “no Documents prompt on install.”

## Changelog

| Ver | Change |
| --- | --- |
| v1 | Investigation: ad-hoc CDHash churn + Documents-cwd uninstall/`getcwd` catch-22; propose WAIVE. |
