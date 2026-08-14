# 2026-08-14 — Bare `alln` Documents TCC

```text
Tier: T1 (first-user / every new binary identity)
Symptom / repro: from ~/Documents/GitHub/Allnighter (or oh-my-zsh last-working-dir
  restore), after curl|sh:
  alln
  → “alln would like to access files in your Documents folder.”
  get-alln.sh cd-HOME belt did not prompt (pipe subshell). Interactive `alln`
  keeps the checkout cwd.
Bug fingerprint: AllnighterCLI.main defaulted empty argv to help, then
  constructed ToolRuntime + HelpTopicRegistry.topics (RecipeCatalog /
  Bundle.module) while cwd was the Documents checkout. ProtectedCWDEscape
  was never called on this path. escapeIfNeeded cannot help: its first
  instruction is getcwd, and that read is the TCC touch. Ship scratch
  dist/.build-universal under the repo also baked ~/Documents/... into
  SPM Bundle.module fallback (stated when sibling lookup fails; on the
  builder, often the first candidate).
Truth owner: ProtectedCWDEscape.adoptNeutral (chdir ProbeScratch, never
  getcwd) from AllnighterCLI.main for commands that do not need repo cwd;
  scripts/build-universal.sh scratch under ~/Library/Developer/Allnighter/CLI-universal.
Lie-prone layer: “install-cli / serve-mutate escape is enough”; “cd HOME in
  get-alln.sh covers interactive alln”; relocate-proof hiding bundles (the
  compile-time path string remains and is still stat’d).
Fix: adoptNeutral before ToolRuntime/help; preserve cwd only for run/loop/
  project/ps/… ; move universal scratch out of Documents.
Proof: scripts/swift-test.sh --filter ProtectedCWDEscapeTests
  check-fast.sh greps the Library scratch default.
  Empirical no-prompt after tccutil reset = founder-only (Documents-hosted checkout).
```
