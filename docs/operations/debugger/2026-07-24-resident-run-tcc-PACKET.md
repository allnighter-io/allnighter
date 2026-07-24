# Resident Run Documents Prompt — T3 Debug Packet

Date: 2026-07-24
Status: investigation and isolation harness required; no product patch yet
Tier: `T3 Critical` — repeated macOS permission regression

## Symptom / repro

A host agent submitted an ordinary read-only Team review through the resident:

```text
alln run "…review only…" --project prj_ac699217 \
  --team code_spec_review_min --lane code --no-commit --detach --json
```

The selected project resolves to
`/Users/mike/Documents/GitHub/XTerminal`. During the submission, macOS displayed
“alln would like to access files in your Documents folder.” The user did not
request filesystem permission and must choose **Don’t Allow**. The preceding
`--dry-run` only resolved the Team; the prompt was contemporaneous with the
subsequent real detached submission.

## Bug fingerprint

`resident detached read-only Team + registered project root under ~/Documents +
detached-runner/worker CWD is that root + Documents prompt`

Attempt count: this is at least the fourth founder-visible instance in the TCC
family. Earlier fixes contained launch, probe, inherited-CWD, and resident
source-probe routes; none supplied end-to-end proof for a real project-root
review submitted through the resident.

## Seam and truth ownership

The request client is process-quiet after the P0 work. The structural project
access path is instead:

```text
RunCLI.runDetached
  -> resident .teamRun request(repoRoot: registered Documents root)
  -> ResidentExecutionBroker / AsyncTeamService.start
  -> ProcessOwnership.spawnDetachedRunner(workingDirectory: repoRoot)
  -> CatalogRunCoordinator worker invocation(workingDirectory: repoRoot)
  -> vendor CLI access
```

Truth owner: the project-access and spawn-authority contract in
`AsyncTeamService` / `CatalogRunCoordinator`, including the detached runner's
effective CWD. macOS TCC owns final prompting attribution and authorization.

Lie-prone layer: successful broker health/readiness requests and
`WorkerInvocationCWD` neutral-scratch tests. They prove that diagnostics and
rootless workers do not inherit an ambient Documents CWD; they do *not* prove
that a resident can execute a project-root review without protected-folder
authorization. A green broker receipt is likewise not evidence that downstream
project access is prompt-free.

## Regression considered

This is not evidence that the resident broker has fallen back to a Codex-owned
vendor spawn. It is a separate, unresolved product contradiction: the resident
is intentionally outside the caller sandbox, while ordinary Teams still require
the resident to access the user's protected project root. Moving the coordinator
binary out of `~/Documents` prevents launch-path attribution; it cannot grant
the coordinator access to the *project* itself.

The exact prompting descendant is not yet event-proven. The detached runner is
already launched with the protected CWD, and the worker later receives the same
CWD. Either is sufficient to make the current architecture unsafe to describe
as no-prompt.

## Isolation harness (required)

Create a disposable, signed macOS harness outside protected folders with only:

1. a launchd-like detached helper with owned scratch CWD;
2. the same helper launched with a selected project root under `~/Documents`;
3. a read-only worker launched against a secret-safe snapshot under
   Allnighter-owned storage.

For each variant, record executable, parent/responsible process, effective CWD,
project path touched, and timestamp. Run one variant per TCC reset only with
explicit founder consent; join a visible dialog to its timestamp. The harness
must not import Allnighter execution code.

Success criterion: prove which paths are prompt-free and whether an
Allnighter-owned read-only snapshot lets a real review complete without granting
Documents access. It must also show whether a selected project root can be
durably authorized for mutation; if macOS cannot support that model for a
CLI-owned coordinator, stop treating it as an implementation detail.

## Fix boundary (pending harness)

Do not add another driver-specific flag, fake `HOME`, TCC reset instruction,
or broad Full Disk Access request. Do not restore blind ProbeScratch for all
runs: that violates the project-run contract and makes workers blind.

The likely durable split to test is:

- read-only answer Teams and Panels run from a client-prepared, tracked,
  secret-safe snapshot outside protected folders; and
- mutating Teams require an explicit, separately proven project-access bridge
  or fail before a vendor spawn with one actionable product-level explanation.

No silent roster reduction, source substitution, or direct client-owned vendor
fallback is allowed.

## Missing kill test / proof

There is no wall-reachable test for
`resident team submission -> detached runner -> real protected project CWD ->
TCC result`. Mock CWD assertions are insufficient. The harness result becomes
the product kill test and determines the access contract.

## Founder test

Do not approve the prompt. Record only whether a dialog appears for each
explicit harness action. A completed review from the owned snapshot, with no
Documents prompt, is the read-only acceptance proof.

## Regression law

No routine resident request may cause a macOS protected-folder prompt merely
because its registered project lies under `~/Documents`. Any path that needs
project bytes must be either a bounded, secret-safe transfer from the caller's
already-authorized workspace or an explicitly proved, durable project-access
mechanism. A broker receipt, health response, or mock CWD assertion is not
proof of that law.
