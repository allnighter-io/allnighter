# Code Audit

Readonly architecture checkpoint before non-trivial closeout or founder smoke.
It checks whether the slice is structurally safe, not whether the code is pretty.

## When It Runs

Run after focused proof and deslop when a change touches product behavior,
durable state, WebSocket protocol, agent bridge contracts, PTY orchestration,
routing, auth, permissions, privacy/security, or more than one module.

Skip only for `T0` copy/paint fixes, docs-only edits, or process-only changes
that do not alter runtime behavior.

## Verdicts

| Verdict | Meaning |
| --- | --- |
| `CLEAN` | Closeout may proceed. |
| `REFACTOR REQUIRED` | Fix findings in the same slice, then re-audit. |
| `INCONCLUSIVE` | Gather missing evidence, then re-audit. |

## Rubric

1. One job per file. A touched file should have a sentence-sized responsibility.
2. No half extractions. If a helper was added, the caller lost the job.
3. No duplicate truth. Semantic ownership exists in one durable place.
4. No silent fallbacks. Required semantic data fails loud or blocks safely.
5. Proof matches claim. The test/command covers the owner-visible behavior, not
   only a convenient helper.

## Audit Packet

```text
Verdict: CLEAN | REFACTOR REQUIRED | INCONCLUSIVE
Scope reviewed:
Proof reviewed:
Findings:
- [P0-P3] file:line - issue; required action
Residual risk:
```
