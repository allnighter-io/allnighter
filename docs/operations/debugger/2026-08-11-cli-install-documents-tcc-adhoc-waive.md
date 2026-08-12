# 2026-08-11 — CLI install Documents TCC ad-hoc WAIVE

```text
Tier: T2 (dogfood nuisance; not first-user defect)
Symptom / repro: uninstall + rebuild_cli from ~/Documents checkout →
  “alln would like to access files in your Documents folder” after P1 landed
Bug fingerprint: ad-hoc CDHash churn; uninstall runs alln serve disable from
  Documents cwd (~line 209) with no pre-exec cd; ProtectedCWDEscape cannot
  avoid first getcwd read when already in Documents
Truth owner: ProtectedCWDEscape + rebuild_cli belt (install-cli hop only);
  residual uninstall hop = scripts/uninstall-allnighter.sh caller cwd
Lie-prone layer: treating uninstall prompt as install-cli regression; gate 6
  Documents string-grep as CWD safety proof
Ruling: WAIVE further code — ad-hoc dogfood only; founder ignores unsigned/dev
Proof: prompt expectation matrix in archived packet; no code change authorized
Packet: docs/archive/phases/CLI_Install_Documents_TCC_Adhoc_Waive.md (v3)
Reviews: DeepSeek 8B500118 · Composer CDCD7AC4
Parent: b65a2ea2 · CLI_Install_Documents_CWD_TCC.md
```
