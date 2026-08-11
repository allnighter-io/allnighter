# 2026-08-11 — CLI install Documents CWD TCC

```text
Tier: T2
Symptom / repro: rebuild_cli / install-cli from ~/Documents checkout →
  “alln would like to access files in your Documents folder.”
Bug fingerprint: foreground alln inherits Documents CWD; ServeLifecycle
  launchctl Process() children inherit that CWD; daemon plist WorkingDirectory
  does not cover the install process
Truth owner: ProtectedCWDEscape (AllnighterEngine) + call sites in
  AllnighterCLI runInstallCLI / serve enable|repair|disable; belt in
  scripts/rebuild_cli.sh
Lie-prone layer: LaunchAgent WorkingDirectory alone; gate 6 Documents
  string-grep “proof”
Fix: escape Documents/Desktop/Downloads cwd to ProbeScratch before
  install/serve-mutate; rebuild_cli cd belt
Proof: scripts/swift-test.sh --filter ProtectedCWDEscapeTests (12 green)
  Empirical no-prompt Documents reset = founder-only (non-blocking)
Code: b65a2ea2 · packet archived CLI_Install_Documents_CWD_TCC.md
```
