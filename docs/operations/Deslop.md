# Deslop

Deslop is hunk-scoped cleanup after product work. It is not a license for a
second feature.

## Use When

- Before closeout on a non-trivial diff.
- After fast implementation where naming, dead code, or duplicated branches may
  have accumulated.
- Before Code Audit.

## Pass

Inspect only touched hunks and one-hop context.

Fix:

- dead code introduced by the slice;
- confusing names introduced by the slice;
- duplicated branches introduced by the slice;
- unnecessary comments or TODOs introduced by the slice;
- local type looseness introduced by the slice;
- obvious missing fail-loud handling introduced by the slice.

Do not:

- refactor unrelated files;
- change behavior;
- move ownership boundaries;
- rewrite old code because it is nearby;
- add new abstractions unless the hunk already created duplication.

## Verdict

```text
Deslop:
Verdict: CLEAN | FIXED | NOT APPLICABLE | NEEDS CODE AUDIT
Touched:
Residual risk:
```
