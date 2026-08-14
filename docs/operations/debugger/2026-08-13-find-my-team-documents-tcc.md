# 2026-08-13 — Find my team Documents TCC (signed DMG)

```text
Tier: T1 (first-user / customer DMG)
Symptom / repro: install Allnighter.dmg → press Find my team →
  “Allnighter would like to access files in your Documents folder.”
  CLI one-liner (after get-alln.sh cd belt) did not prompt.
Bug fingerprint: AppModel.runSetupProbe → LoginShell zsh -lic with inherited
  cwd, then AllnighterCLIDetector.make(interactive: true) → another -lic.
  Interactive zsh sources ~/.zshrc (oh-my-zsh last-working-dir, direnv) which
  cds into ~/Documents; TCC attributes the touch to Allnighter.app.
Truth owner: LoginShell.resolvedPath (AppConfig.swift) +
  AppModel.runSetupProbe detector interactive: false.
Lie-prone layer: Launch Authority Track 0.1 “one-time TCC is acceptable
  because the user asked.” That was a dogfood PATH trade. Customers hitting
  Find my team on a signed DMG is first-user, not a PATH-debug convenience.
Fix: LoginShell uses -lc and currentDirectoryURL = ProbeScratch (HOME
  fallback). Find my team detector pins interactive: false. bun/asdf/mise
  remain in CLIDetector.defaultCommonBinDirs; Homebrew PATH still comes from
  .zprofile via -lc.
Proof: AppModelTests.testFindMyTeamDoesNotUseInteractiveLoginShell
  Empirical no-prompt after tccutil reset = founder DMG reinstall.
```
