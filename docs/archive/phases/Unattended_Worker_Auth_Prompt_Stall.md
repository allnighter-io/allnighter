# Unattended Worker Auth-Prompt Stall

Status: **Complete** — env hardening + stall diagnosis shipped
Owner: AllnighterEngine (`AllnighterSpawnEnvironmentPolicy`, `ProcessOwnership` stall diagnosis)
Updated: 2026-07-27
Incident: unattended `alln pair pilot handoff` wedged 32+ minutes on a
`SecurityAgent` Keychain modal via `git-credential-osxkeychain`

## Problem

alln makes runs unattended. A descendant that blocks on an interactive
credential prompt turns a one-click dialog into an indefinite stall. The
receipt showed a bare timeout; nothing named the auth-prompt wedge that was
sitting in the process tree the whole time.

## What shipped

### 1. Non-interactive worker environment (blast-radius reduction)

ONE definition in `AllnighterSpawnEnvironmentPolicy.nonInteractiveWorkerEnvironment`:

- `GIT_TERMINAL_PROMPT=0`
- `GIT_ASKPASS=/usr/bin/true`
- `SSH_ASKPASS=/usr/bin/true`
- `SSH_ASKPASS_REQUIRE=never`

Applied via the existing spawn policy (every `CommandRunner` site) and
`processEnvironment(extra:)` for bare `Foundation.Process` sites
(`ProcessACPTransport`, `PilotCLI`, `GitObserver`, …).

**Honest limit:** these vars do **not** suppress Security.framework /
`git-credential-osxkeychain` Keychain modals. They would **not** have prevented
the founder incident. They fail closed common git/ssh *terminal* prompts only.
Do not claim unattended runs are prompt-proof.

### 2. Named stall diagnosis (the valuable half)

Before timeout kill, `ProcessGroupCommandRunner` samples the owned descendant
tree + process-group members and classifies:

- interactive auth prompt (`SecurityAgent`, `*-askpass`, `git-credential-*`)
- frozen zero-CPU descendant (generic wedge)

Persists `stall_diagnosis.json`, enriches worker `errorReason` via
`StallDiagnosisEnrichingWorkerRunner`, and appends the summary to `alln ps`
silence lines. Timeout kill also reaps orphaned grandchildren that left the
process group.

## Proof

```text
swift test --package-path Packages/AllnighterCore \
  --filter ProcessOwnershipStallDiagnosisTests
```

Missing proof (explicit): cannot reproduce a live `SecurityAgent` modal in CI;
classifier coverage is synthetic process-tree snapshots.

## Successor owner

Code: `AllnighterSpawnEnvironmentPolicy`, `ProcessOwnershipStallDiagnosis`,
`ProcessGroupCommandRunner.diagnoseAndReapOnTimeout`,
`StallDiagnosisEnrichingWorkerRunner`.
