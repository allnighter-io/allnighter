# 2026-08-14 — `alln` SIGTRAPs on PATH (argv[0] catalog lookup)

```text
Tier: T3 (total CLI outage for normal use; 1.1.11 regression)
Symptom / repro: `alln menu --json` via $PATH exits 133 SIGTRAP, empty
  stdout/stderr. Same binary by absolute path exits 0. `alln --version`
  succeeds (never constructs ToolRuntime). 29 crash reports since 2026-08-08;
  worked on this machine 2026-08-10; 1.1.11 shipped the fault.
Bug fingerprint: ProtectedCWDEscape.adoptNeutral chdir +
  ExecutableResource.executableDirectoryURL from argv[0]. Bare/relative
  argv[0] resolves against ProbeScratch, not ~/.local/share/allnighter/bin.
  ModelCatalog.bundledAuthority preconditionFailure → EXC_BREAKPOINT.
  Gemini "not installed" / "not ready" was empty crash output, not a seat
  defect. Live menu (absolute path): model_gemini ready=true, agy ready.
Truth owner: ExecutableResource.directoryURL / currentExecutablePath
  (_NSGetExecutablePath + resolvingSymlinksInPath). Relocate-proof must
  invoke bare `alln` on PATH from a different cwd. XCTest hosts search
  Bundle.allBundles (the `.xctest` parent), never argv[0] or the SPM accessor.
Lie-prone layer: relocate-proof `"$STAGE/alln"` (absolute argv[0]);
  `alln --version` as catalog-load proof; argv[0] after chdir.
Attempt count: 1 on this fingerprint (1.1.11 fixed TCC accessor, created
  this trap). Isolation harness: n/a — invocation table is the primitive.
Fix identity: unreleased 1.1.12. Do not rebuild the installed CLI until
  founder says so.
Proof: scripts/swift-test.sh --filter
  'ExecutableResourceResolutionTests|CatalogAuthorityTests|CLIResourceBundlesTests|ProcessOwnershipReconcileTests/testProcessAliveAndStartTimeSelf'
  AgentOS ExecutableResourceTests
  relocate-cli-proof.sh after rebuild (PATH bare name)
```
