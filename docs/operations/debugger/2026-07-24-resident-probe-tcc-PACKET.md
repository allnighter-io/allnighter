# Resident Probe TCC Prompts — P0 Debug Packet

Date: 2026-07-24
Status: fix implemented; host confirmation pending
Tier: `T3 Critical` — repeated permission-prompt regression

## Symptom

From a Codex workspace-write session, a resident-routed `alln doctor --full`
produced two macOS prompts attributed to `alln`:

1. access to the user's Documents folder;
2. control of “Codex Computer Use”.

The caller timed out after ten seconds but the resident continued the full
probe, so a timeout did not mean that its vendor work had stopped.

## Truth owner and defect

Truth owner: `ResidentDoctorService` plus the typed `sourceProbe` boundary.

Lie-prone layer: existing probe hygiene tests. They asserted neutral CWD for
ordinary direct invocations but missed two escape paths:

- `AllnighterCLI.runDoctor` supplied the foreground client's Documents CWD to
  the resident. The resident used it only to derive diagnostic Git/Cursor facts,
  but that was enough to create a protected-folder access path.
- `ResidentDoctorService` constructed a full `CLIDetector` with
  `interactive: true`; and `CLIDetector.runResolved` independently forced
  `ToolInvocation.loginShell` through `-lic`. An alias/function could therefore
  source interactive shell configuration during a background probe.

## Fix boundary

- Dispatch `doctor`, `detect`, and `serve` before foreground `ToolRuntime`
  construction.
- Do not send a working directory for doctor. The resident always uses its
  neutral probe scratch directory and accepts no caller workspace path for a
  source probe.
- Full resident probes remain real, quota-spending smokes, but are always
  noninteractive. Alias/function fallback preserves `-lc` unless a separately
  named future setup flow explicitly opts in.
- Extend the client wait to the bounded source-probe budget so a full probe does
  not look failed while it is still executing.

## Proof

Automated:

```text
swift test --disable-sandbox --package-path Packages/AllnighterCore \
  --filter 'LaunchAuthorityProbeTests|ResidentExecutionBrokerTests|DoctorTimingTests|ResidentExecutionContractTests'
```

Required host confirmation after rebuilding the resident:

1. With no dialogs approved, run `alln doctor --full --json` from Codex.
2. Assert no Documents or Automation prompt appears.
3. Assert the command returns a classified result (including honest source
   failures) rather than timing out at the old ten-second client limit.
4. Only then proceed to a real Panel round.

No user should be asked to grant Documents, Automation, Full Disk Access, or
vendor-specific sandbox exceptions to make this path work.
