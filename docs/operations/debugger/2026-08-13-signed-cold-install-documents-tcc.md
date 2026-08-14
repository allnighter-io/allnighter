# 2026-08-13 — Signed cold install Documents TCC

```text
Tier: T1 (first-user / customer one-liner)
Symptom / repro: from ~/Documents/GitHub/Allnighter, after uninstall:
  curl -fsSL https://get.allnighter.io | sh
  → “alln would like to access files in your Documents folder.”
  Binary: public 1.1.3 Developer ID (not ad-hoc).
Bug fingerprint: get-alln.sh execs `$DOWNLOAD version` then
  `exec $DOWNLOAD install-cli` with the caller’s cwd; Documents checkout
  is a normal paste site; getcwd on that cwd is the TCC touch.
Truth owner: scripts/get-alln.sh (pre-exec cd "$HOME" before any alln);
  scripts/uninstall-allnighter.sh (ProbeScratch/HOME cd before serve disable).
Lie-prone layer: “the popup is only unsigned / ad-hoc.” 2026-08-11 waive
  (CLI_Install_Documents_TCC_Adhoc_Waive) said no signed first-user defect
  because signed install from ~ writes only under ~/.local. Unmeasured:
  the one-liner inherits cwd. Signing makes Allow stick; it does not skip
  the prompt. ProtectedCWDEscape cannot avoid the first getcwd.
Fix: cd "$HOME" in get-alln.sh after chmod, before version + install-cli.
  Uninstall belt before `alln serve disable`.
Proof: scripts/test-get-alln.sh (structural cd-before-version + scenario E
  pipe install from a Documents-like cwd). Empirical no-prompt after
  tccutil reset remains founder-only (Documents-hosted checkout).
Live faucet: repo script is not what curl|sh runs until install/get-alln.sh
  is re-uploaded to R2 (High-Risk: production deploy — founder action).
```
